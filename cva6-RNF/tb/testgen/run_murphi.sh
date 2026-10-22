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
# run_murphi.sh — run every Murphi-generated vector (testgen/vectors_murphi/)
# through a fresh vsim invocation, with coverage enabled.
#
# Mirrors run_all.sh's vsim invocation (coverage args, $finish→$stop
# remap, classification) but only walks vectors_murphi/.
#
# Run from cva6-RNF/tb/  (or cwd-agnostic — we resolve relative to script).
#
#   QUESTA=/path/to/questasim ./testgen/run_murphi.sh
#
# Env knobs:
#   PER_VEC_TIMEOUT — seconds before SIGKILL on hung vsim   (default 120)
#   ADDR            — replay line address (default 0x80000200)
#   KEEP_LOGS       — 0/1 keep per-vector .log on PASS      (default 1)
#
# Output:
#   testgen/run_all_logs/murphi/<vec>.log    per-vector sim log
#   testgen/run_all_logs/murphi/<vec>.ucdb   coverage db (per vector)
#   testgen/murphi_summary.tsv               one row per vector

set -u
set -o pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"      # cva6-RNF/tb/testgen
TB="$(cd "$HERE/.." && pwd)"               # cva6-RNF/tb
BUILD="$TB/questa_build"
VEC_DIR="$HERE/vectors_murphi"
LOG_DIR="$HERE/run_all_logs/murphi"
SUMMARY="$HERE/murphi_summary.tsv"

PER_VEC_TIMEOUT="${PER_VEC_TIMEOUT:-120}"
# Coherent address subspace. Murphi vectors only target this range —
# non-coherent ops (ReadNoSnp, WriteNoSnpFull, ...) belong in a
# separate test flow over a different address range (CHI E.b sec 2.4.2).
ADDR="${ADDR:-0x80000200}"
KEEP_LOGS="${KEEP_LOGS:-1}"

mkdir -p "$LOG_DIR"
: > "$SUMMARY"
printf 'vector\taddr\tstatus\tseconds\tdetail\n' >> "$SUMMARY"

# vsim PATH
if ! command -v vsim >/dev/null 2>&1; then
    if [[ -n "${QUESTA:-}" ]]; then
        export PATH="$QUESTA/bin:$PATH"
    fi
fi
if ! command -v vsim >/dev/null 2>&1; then
    echo "ERROR: vsim not in PATH. Set QUESTA=..." >&2
    exit 2
fi
if ! vsim -version >/dev/null 2>&1; then
    echo "ERROR: 'vsim -version' failed (license?)." >&2
    exit 2
fi
if [[ ! -d "$BUILD" ]]; then
    echo "ERROR: $BUILD missing. Run 'make all REPLAY=1 MSHR_OBS=1 COVERAGE=1' first." >&2
    exit 2
fi

mapfile -t VECTORS < <(find "$VEC_DIR" -maxdepth 1 -name '*.txt' | sort)
n_total=${#VECTORS[@]}
if [[ $n_total -eq 0 ]]; then
    echo "ERROR: no vectors found under $VEC_DIR" >&2
    exit 2
fi

n_pass=0; n_fail=0; n_timeout=0; n_error=0

echo "[run_murphi] vectors:  $n_total"
echo "[run_murphi] addr:     $ADDR"
echo "[run_murphi] coverage: on  (UCDB per vector)"
echo "[run_murphi] timeout:  ${PER_VEC_TIMEOUT}s per vector"
echo "[run_murphi] logs:     $LOG_DIR"
echo

i=0
for vec in "${VECTORS[@]}"; do
    i=$((i + 1))
    base="$(basename "$vec" .txt)"
    name="$base"
    log="$LOG_DIR/$name.log"
    ucdb_path="$LOG_DIR/$name.ucdb"

    cov_arg="-coverage"
    cov_do="coverage save $ucdb_path;"
    cov_onfinish="-onfinish stop"

    t0=$(date +%s)
    set +e
    timeout --kill-after=5s "${PER_VEC_TIMEOUT}s" \
        bash -c "cd '$BUILD' && \
                 REPLAY_VECTOR='$vec' REPLAY_ADDR='$ADDR' \
                 vsim -c -t 10ps -suppress 3009 $cov_arg $cov_onfinish work.tlm_rnf_hnf_tb \
                      -do 'log -r /*; run -all; $cov_do quit -f;' \
                      > '$log' 2>&1"
    rc=$?
    set -e
    t1=$(date +%s); dt=$((t1 - t0))

    status="ERROR"; detail=""
    if [[ $rc -eq 124 || $rc -eq 137 ]]; then
        status="TIMEOUT"; detail="vsim killed after ${PER_VEC_TIMEOUT}s"
        n_timeout=$((n_timeout + 1))
    elif grep -q "DEADLOCK" "$log"; then
        status="DEADLOCK"; detail="$(grep -m1 DEADLOCK "$log" | tr -s ' ')"
        n_fail=$((n_fail + 1))
    elif grep -qE "Errors: [^0]" "$log"; then
        status="ERROR"; detail="$(grep -m1 'Errors:' "$log")"
        n_error=$((n_error + 1))
    elif grep -q "DATA_CHECK_RESULT: FAIL" "$log"; then
        status="DATA_FAIL"; detail="$(grep -m1 'DATA_CHECK_RESULT: FAIL' "$log" | tr -s ' ')"
        n_fail=$((n_fail + 1))
    else
        oracle_out="$(python3 "$HERE/oracle.py" "$vec" "$log" 2>&1 || true)"
        if echo "$oracle_out" | grep -q '^# Final result:     PASS'; then
            status="PASS"
            n_pass=$((n_pass + 1))
        else
            mismatch="$(echo "$oracle_out" | grep -m1 'FAIL' || true)"
            status="FAIL"; detail="${mismatch:-oracle FAIL}"
            n_fail=$((n_fail + 1))
        fi
    fi

    printf '[%4d/%4d] %-60s  %-8s  %3ds  %s\n' \
        "$i" "$n_total" "$base" "$status" "$dt" "$detail"
    printf '%s\t%s\t%s\t%d\t%s\n' \
        "$base" "$ADDR" "$status" "$dt" "$detail" >> "$SUMMARY"

    if [[ "$KEEP_LOGS" != "1" && "$status" == "PASS" ]]; then
        rm -f "$log"
    fi
done

echo
echo "[run_murphi] done"
printf '  total     %d\n' "$n_total"
printf '  pass      %d\n' "$n_pass"
printf '  fail      %d\n' "$n_fail"
printf '  timeout   %d\n' "$n_timeout"
printf '  error     %d\n' "$n_error"
echo "  summary:  $SUMMARY"
echo "  logs:     $LOG_DIR"
echo
echo "Merge coverage:  vcover merge -64 testgen/murphi_merged.ucdb $LOG_DIR/*.ucdb"

if [[ $n_fail -gt 0 || $n_error -gt 0 || $n_timeout -gt 0 ]]; then
    exit 1
fi
exit 0
