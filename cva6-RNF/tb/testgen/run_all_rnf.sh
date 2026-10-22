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
# run_all_rnf.sh -- batched sweep over the RN-F IP-level vectors.
#
# Splits vectors_rnf/*.txt into BATCH_SIZE-sized chunks, runs each
# chunk with PAR_JOBS parallel vsim invocations, prints per-batch +
# overall PASS/FAIL/TIMEOUT counts.
#
# Usage:
#   QUESTA=/path/to/questa ./run_all_rnf.sh
#   BATCH_SIZE=200 PAR_JOBS=8 ./run_all_rnf.sh
#   PATTERN='I__SW_enqueue_*' ./run_all_rnf.sh     # restrict by glob

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
TB_DIR="$(cd "$HERE/.." && pwd)"
BUILD="$TB_DIR/questa_build"
VEC_DIR="${VEC_DIR:-$HERE/vectors_rnf}"
LOG_DIR="${LOG_DIR:-$HERE/run_all_rnf_logs}"

QUESTA="${QUESTA:-${QUESTA_HOME:-/home/dmk/fedora/questa_24/questasim}}"
BATCH_SIZE="${BATCH_SIZE:-100}"
PAR_JOBS="${PAR_JOBS:-4}"
PER_VEC_TIMEOUT="${PER_VEC_TIMEOUT:-30}"   # seconds
PATTERN="${PATTERN:-*.txt}"
COVERAGE="${COVERAGE:-0}"                  # 1 = emit per-vector .ucdb
MERGED_UCDB="${MERGED_UCDB:-$(dirname "$LOG_DIR")/$(basename "$LOG_DIR" _logs)_cov_merged.ucdb}"

# ── Sanity ───────────────────────────────────────────────────────────
if [[ ! -d "$VEC_DIR" ]]; then
    echo "[run_all_rnf] no vectors at $VEC_DIR — run gen_from_rnf.py first" >&2
    exit 2
fi
if [[ ! -d "$BUILD" ]]; then
    echo "[run_all_rnf] build dir not found; running 'make rnf-ip-compile' first..."
    (cd "$TB_DIR" && QUESTA="$QUESTA" make rnf-ip-compile) || exit $?
fi

rm -rf "$LOG_DIR"
mkdir -p "$LOG_DIR"

# Pre-vopt once (with +cover when COVERAGE=1) into a named opt'd
# top so parallel vsims all share the same instrumented design and
# don't race on work/_lock.  Without this, COVERAGE=1 + -novopt
# yields empty UCDBs (no instrumentation), and dropping -novopt
# triggers a vopt race across the parallel vsim invocations.
OPT_TOP="rnf_ip_tb_opt"
(
    cd "$BUILD" || exit 1
    if [[ "$COVERAGE" == "1" ]]; then
        echo "[run_all_rnf] pre-vopt with coverage ..."
        "$QUESTA/bin/vopt" +acc +cover=bcestf -o "$OPT_TOP" work.rnf_ip_tb \
            > vopt.log 2>&1 || { echo "[run_all_rnf] vopt failed (see $BUILD/vopt.log)"; exit 1; }
    else
        echo "[run_all_rnf] pre-vopt ..."
        "$QUESTA/bin/vopt" +acc -o "$OPT_TOP" work.rnf_ip_tb \
            > vopt.log 2>&1 || { echo "[run_all_rnf] vopt failed (see $BUILD/vopt.log)"; exit 1; }
    fi
) || exit $?

mapfile -t VECTORS < <(find "$VEC_DIR" -maxdepth 1 -name "$PATTERN" | sort)
N=${#VECTORS[@]}
if (( N == 0 )); then
    echo "[run_all_rnf] no vectors matched pattern '$PATTERN'" >&2
    exit 2
fi

echo "[run_all_rnf] $N vector(s), batch=$BATCH_SIZE, parallel=$PAR_JOBS, timeout=${PER_VEC_TIMEOUT}s"
echo "[run_all_rnf] logs -> $LOG_DIR/"

# ── Per-vector runner (called by xargs -P) ────────────────────────────
run_one() {
    local vec="$1"
    local base
    base=$(basename "$vec" .txt)
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
    # Point at the pre-vopt'd top (built once above) so parallel
    # vsims don't each kick off vopt and race on work/_lock.
    timeout --kill-after=2s "$PER_VEC_TIMEOUT"s \
        vsim -c -t 10ps -suppress 3009 -suppress 12110 \
            $cov_arg "work.rnf_ip_tb_opt" \
            +VECTOR="$vec" \
            -do "run -all; $cov_save quit -f;" \
            > "$log" 2>&1
    local rc=$?

    if [[ $rc -eq 124 ]]; then
        echo "TIMEOUT" > "$result_file"
    elif grep -q 'SNP_MON.*violation' "$log"; then
        echo "FAIL" > "$result_file"     # snoop-hazard monitor tripped
    elif grep -q 'MEM_ORACLE' "$log"; then
        echo "FAIL" > "$result_file"     # data-freshness oracle mismatch
    elif grep -q '\[REPLAY\] === .* done:' "$log"; then
        echo "PASS" > "$result_file"
    else
        echo "FAIL" > "$result_file"
    fi
}
export -f run_one
export BUILD LOG_DIR PER_VEC_TIMEOUT COVERAGE

# ── Batch loop ───────────────────────────────────────────────────────
total_pass=0; total_fail=0; total_timeout=0
batch_idx=0

for (( i = 0; i < N; i += BATCH_SIZE )); do
    batch_idx=$((batch_idx + 1))
    end=$(( i + BATCH_SIZE ))
    (( end > N )) && end=$N
    batch=("${VECTORS[@]:$i:$((end - i))}")
    t0=$(date +%s)
    echo "[batch $batch_idx] vectors $((i+1))..$end (size ${#batch[@]})"

    printf '%s\n' "${batch[@]}" | \
        xargs -n1 -P "$PAR_JOBS" -I{} bash -c 'run_one "$@"' _ {}

    # Tally batch
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
echo "[run_all_rnf] DONE"
echo "  total    $N"
echo "  PASS     $total_pass"
echo "  FAIL     $total_fail"
echo "  TIMEOUT  $total_timeout"

# ── Merge per-vector UCDBs into one + summary report ────────────────
if [[ "$COVERAGE" == "1" ]]; then
    echo
    echo "[run_all_rnf] merging UCDBs..."
    ucdbs=("$LOG_DIR"/*.ucdb)
    if (( ${#ucdbs[@]} == 0 )); then
        echo "[run_all_rnf] no .ucdb files emitted -- coverage not collected"
    else
        (cd "$BUILD" && \
         vcover merge -out "$MERGED_UCDB" "${ucdbs[@]}" >/dev/null 2>&1) \
            && echo "[run_all_rnf] merged -> $MERGED_UCDB" \
            || echo "[run_all_rnf] merge failed"
        echo
        (cd "$BUILD" && vcover report -summary "$MERGED_UCDB" 2>/dev/null)
    fi
fi
