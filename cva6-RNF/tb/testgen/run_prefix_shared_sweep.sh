#!/usr/bin/env bash
# Copyright (c) 2026 Customized Parallel Computing (CPC) Group, Tampere University
# Author: Abdesattar Kalache <abdesattar.kalache@tuni.fi>
#
# SPDX-License-Identifier: Apache-2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at:
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
# implied.  See the License for the specific language governing
# permissions and limitations under the License.
# run_prefix_shared_sweep.sh
#
# Prefix-shared sweep runner.  Complements run_all_rnf.sh (1-switch and
# 2-switch).  Each vector is a "mega-vector" that walks the prefix from
# I to a hub state ONCE, then chains all 2-switch target tails under
# that hub back-to-back.  Same coverage as 2-switch, ~30x fewer prefix
# edges simulated.
#
# Uses the existing replay_vector task in the TB (no TCL / checkpoint
# gymnastics) — the mega-vector .txt files just look like long normal
# vectors to Questa.
#
# Usage:
#   QUESTA=/path/to/questa ./run_prefix_shared_sweep.sh
#   PAR_JOBS=6 ./run_prefix_shared_sweep.sh
#   HUB_PATTERN='UC_*' ./run_prefix_shared_sweep.sh
#   COVERAGE=1 ./run_prefix_shared_sweep.sh

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
TB_DIR="$(cd "$HERE/.." && pwd)"
BUILD="$TB_DIR/questa_build"
VEC_DIR="${VEC_DIR:-$HERE/vectors_rnf_prefix_shared}"
LOG_DIR="${LOG_DIR:-$HERE/run_prefix_shared_logs}"

QUESTA="${QUESTA:-${QUESTA_HOME:-/home/dmk/fedora/questa_24/questasim}}"
BATCH_SIZE="${BATCH_SIZE:-50}"
PAR_JOBS="${PAR_JOBS:-6}"
PER_HUB_TIMEOUT="${PER_HUB_TIMEOUT:-300}"
HUB_PATTERN="${HUB_PATTERN:-*.txt}"
COVERAGE="${COVERAGE:-0}"
# Extra vsim plusargs, e.g. EXTRA_PLUSARGS=+DISABLE_SNP_MON for a
# coverage-only sweep in which a protocol-timeout does not $fatal and
# therefore does not discard the remaining tails of a mega-vector.
EXTRA_PLUSARGS="${EXTRA_PLUSARGS:-}"
MERGED_UCDB="${MERGED_UCDB:-$HERE/rnf_prefix_shared_cov_merged.ucdb}"

# ── Sanity ───────────────────────────────────────────────────────────
if [[ ! -f "$VEC_DIR/manifest.txt" ]]; then
    echo "[prefix_shared] no manifest — run: python3 gen_from_rnf_prefix_shared.py --vectors" >&2
    exit 2
fi
if [[ ! -d "$BUILD" ]]; then
    echo "[prefix_shared] build dir missing; running 'make rnf-ip-compile' first..."
    (cd "$TB_DIR" && QUESTA="$QUESTA" COVERAGE="$COVERAGE" make rnf-ip-compile) || exit $?
fi

rm -rf "$LOG_DIR"; mkdir -p "$LOG_DIR"

# ── Pre-vopt once (shared across all parallel vsims) ────────────────
OPT_TOP="rnf_ip_tb_opt"
(
    cd "$BUILD" || exit 1
    if [[ "$COVERAGE" == "1" ]]; then
        echo "[prefix_shared] pre-vopt with coverage ..."
        "$QUESTA/bin/vopt" +acc +cover=bcestf -o "$OPT_TOP" work.rnf_ip_tb \
            > vopt.log 2>&1 || { echo "[prefix_shared] vopt failed"; exit 1; }
    else
        echo "[prefix_shared] pre-vopt ..."
        "$QUESTA/bin/vopt" +acc -o "$OPT_TOP" work.rnf_ip_tb \
            > vopt.log 2>&1 || { echo "[prefix_shared] vopt failed"; exit 1; }
    fi
) || exit $?

# ── Per-hub runner ──────────────────────────────────────────────────
run_one() {
    local vec="$1"
    local base=$(basename "$vec" .txt)
    local log="$LOG_DIR/$base.log"
    local result_file="$LOG_DIR/$base.result"
    local ucdb_file="$LOG_DIR/$base.ucdb"

    local cov_arg=""
    local cov_save=""
    if [[ "$COVERAGE" == "1" ]]; then
        cov_arg="-coverage -onfinish stop"
        cov_save="coverage save $ucdb_file;"
    fi

    cd "$BUILD" >/dev/null || return 1
    # -sv_seed random gives each vsim a different $urandom stream so
    # that the amo_rotate_idx initial value diversifies across runs,
    # exercising all 8 AtomicLoad_* / AtomicStore_* CHI-opcode variants
    # instead of concentrating on ADD (idx=0).
    timeout --kill-after=5s "$PER_HUB_TIMEOUT"s \
        "$QUESTA/bin/vsim" -c -t 10ps -suppress 3009 -suppress 12110 \
            -sv_seed random \
            $cov_arg "work.$OPT_TOP" \
            +VECTOR="$vec" $EXTRA_PLUSARGS \
            -do "run -all; $cov_save quit -f;" \
            > "$log" 2>&1
    local rc=$?
    if [[ $rc -eq 124 ]]; then
        echo "TIMEOUT" > "$result_file"
    elif grep -q 'SNP_MON.*violation' "$log"; then
        echo "FAIL" > "$result_file"
    elif grep -q '\*\* Error: \[MEM_ORACLE\]' "$log"; then
        # Match ONLY the $error prefix — the benign WV_PROBE info line
        # "MEM_ORACLE check delivered" also contains the substring.
        echo "FAIL" > "$result_file"
    elif grep -q '\[REPLAY\] === .* done:' "$log"; then
        echo "PASS" > "$result_file"
    else
        echo "FAIL" > "$result_file"
    fi
}
export -f run_one
export BUILD LOG_DIR QUESTA OPT_TOP COVERAGE PER_HUB_TIMEOUT EXTRA_PLUSARGS

# ── Iterate hubs in batches ─────────────────────────────────────────
# manifest.txt lives in the same directory and matches the default
# '*.txt' pattern; it is an index, not a vector, and running it scored a
# spurious PASS in every sweep.
mapfile -t VECTORS < <(find "$VEC_DIR" -maxdepth 1 -name "$HUB_PATTERN" \
                            ! -name 'manifest.txt' | sort)
N=${#VECTORS[@]}
(( N == 0 )) && { echo "[prefix_shared] no vectors matched '$HUB_PATTERN'" >&2; exit 2; }

echo "[prefix_shared] $N hub-mega-vector(s), batch=$BATCH_SIZE, parallel=$PAR_JOBS, timeout=${PER_HUB_TIMEOUT}s"
echo "[prefix_shared] logs -> $LOG_DIR/"

total_pass=0; total_fail=0; total_timeout=0
batch_idx=0

for (( i = 0; i < N; i += BATCH_SIZE )); do
    batch_idx=$((batch_idx + 1))
    end=$(( i + BATCH_SIZE )); (( end > N )) && end=$N
    batch=("${VECTORS[@]:$i:$((end - i))}")
    t0=$(date +%s)
    echo "[batch $batch_idx] hubs $((i+1))..$end"

    printf '%s\n' "${batch[@]}" | \
        xargs -n1 -P "$PAR_JOBS" -I{} bash -c 'run_one "$@"' _ {}

    bp=0; bf=0; bt=0
    for vec in "${batch[@]}"; do
        base=$(basename "$vec" .txt)
        r=$(cat "$LOG_DIR/$base.result" 2>/dev/null)
        case "$r" in
            PASS)    bp=$((bp+1));;
            FAIL)    bf=$((bf+1));;
            TIMEOUT) bt=$((bt+1));;
            *)       bf=$((bf+1));;
        esac
    done
    total_pass=$((total_pass + bp))
    total_fail=$((total_fail + bf))
    total_timeout=$((total_timeout + bt))
    t1=$(date +%s)
    echo "[batch $batch_idx] PASS=$bp FAIL=$bf TIMEOUT=$bt  (elapsed $((t1 - t0))s)"
done

echo
echo "[prefix_shared] DONE"
echo "  total   $N"
echo "  PASS    $total_pass"
echo "  FAIL    $total_fail"
echo "  TIMEOUT $total_timeout"

# ── Coverage merge ──────────────────────────────────────────────────
if [[ "$COVERAGE" == "1" ]]; then
    echo "[prefix_shared] merging UCDBs..."
    find "$LOG_DIR" -maxdepth 1 -name '*.ucdb' > /tmp/prefix_ucdb_list.txt
    n_ucdbs=$(wc -l < /tmp/prefix_ucdb_list.txt)
    if (( n_ucdbs > 0 )); then
        (cd "$BUILD" && \
         xargs -a /tmp/prefix_ucdb_list.txt \
             "$QUESTA/bin/vcover" merge -out "$MERGED_UCDB" 2>&1 | tail -2)
        echo "[prefix_shared] merged -> $MERGED_UCDB  ($n_ucdbs UCDBs)"
    fi
fi
