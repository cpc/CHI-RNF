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
# run_convergence.sh -- measure coverage as a function of vectors run, for
# any vector directory.  Used to compare the model-based directed set
# against the constrained-random baseline on time-to-convergence.
#
# Runs vectors in batches; after each batch merges every UCDB produced so
# far and records CUMULATIVE coverage against vector count and wall-clock
# seconds.  The merge is incremental (running merged ucdb + new batch) so
# the measurement cost does not grow quadratically with batch index.
#
# Usage:
#   VEC_DIR=vectors_rnf_random  BATCH=100 MAX=2000 \
#     OUT=convergence_random.csv ./run_convergence.sh
#
#   VEC_DIR=vectors_rnf_prefix_shared BATCH=50 \
#     OUT=convergence_directed.csv ./run_convergence.sh

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
TB_DIR="$(cd "$HERE/.." && pwd)"
BUILD="$TB_DIR/questa_build"

QUESTA="${QUESTA:-${QUESTA_HOME:-/home/dmk/fedora/questa_24/questasim}}"
VEC_DIR="${VEC_DIR:-$HERE/vectors_rnf_random}"
[[ "$VEC_DIR" = /* ]] || VEC_DIR="$HERE/$VEC_DIR"
# Was BATCH given explicitly?  The default below would otherwise make
# "is BATCH set" always true and silently disable event-axis sampling.
BATCH_EXPLICIT="${BATCH+set}"
BATCH="${BATCH:-100}"
MAX="${MAX:-0}"                     # 0 = all vectors in VEC_DIR
PAR_JOBS="${PAR_JOBS:-12}"
PER_TIMEOUT="${PER_TIMEOUT:-420}"
# Extra vsim plusargs, e.g. EXTRA_PLUSARGS=+USE_TRIGGERS.  The race-cell
# vectors need it: it enables the non-blocking dispatch without which a
# transaction is never outstanding when their snoop lands.
EXTRA_PLUSARGS="${EXTRA_PLUSARGS:-}"
OUT="${OUT:-$HERE/convergence.csv}"
[[ "$OUT" = /* ]] || OUT="$HERE/$OUT"
WORK="${WORK:-$HERE/.conv_$(basename "$VEC_DIR")}"

[[ -d "$BUILD" ]] || { echo "no build dir -- run 'make rnf-ip-compile' first" >&2; exit 2; }

rm -rf "$WORK"; mkdir -p "$WORK/logs"
RUNNING="$WORK/running.ucdb"

# ── vopt once, shared by every vsim ─────────────────────────────────
OPT_TOP="rnf_ip_tb_opt"
(cd "$BUILD" && "$QUESTA/bin/vopt" +acc +cover=bcestf -o "$OPT_TOP" work.rnf_ip_tb \
   > "$WORK/vopt.log" 2>&1) || { echo "vopt failed, see $WORK/vopt.log" >&2; exit 1; }

run_one() {
    local vec="$1" base
    base=$(basename "$vec" .txt)
    cd "$BUILD" >/dev/null || return 1
    timeout --kill-after=5s "$PER_TIMEOUT"s \
        "$QUESTA/bin/vsim" -c -t 10ps -suppress 3009 -suppress 12110 -sv_seed random \
            -coverage -onfinish stop "work.$OPT_TOP" +VECTOR="$vec" $EXTRA_PLUSARGS \
            -do "run -all; coverage save $WORK/logs/$base.ucdb; quit -f;" \
        > "$WORK/logs/$base.log" 2>&1
    if grep -q '\*\* Error: \[MEM_ORACLE\]\|SNP_MON.*violation' "$WORK/logs/$base.log"; then
        echo FAIL > "$WORK/logs/$base.result"
    elif grep -q '\[REPLAY\] === .* done:' "$WORK/logs/$base.log"; then
        echo PASS > "$WORK/logs/$base.result"
    else
        echo FAIL > "$WORK/logs/$base.result"
    fi
}
export -f run_one
export BUILD QUESTA OPT_TOP WORK PER_TIMEOUT EXTRA_PLUSARGS

mapfile -t VECTORS < <(find "$VEC_DIR" -maxdepth 1 -name '*.txt' ! -name manifest.txt | sort)
N=${#VECTORS[@]}
(( MAX > 0 && MAX < N )) && N=$MAX
(( N == 0 )) && { echo "no vectors in $VEC_DIR" >&2; exit 2; }

echo "[conv] $VEC_DIR: $N vectors, batch=$BATCH, par=$PAR_JOBS"
echo "vectors,wall_s,sim_s,events_exec,pass,fail,func_pct,func_bins_cov,func_bins_tot,stmt_pct,stmt_hit,stmt_tot" > "$OUT"

T0=$(date +%s); SIM_ACC=0; PASS=0; FAIL=0

# Two-rate sampling schedule: the convergence knee is below ~1000
# vectors, so sample finely there and coarsely after, instead of paying
# for a merge every BATCH vectors all the way out.
#   BATCH1 (default 50) applies while i <  SCHED_THRESH
#   BATCH2 (default 1000) applies while i >= SCHED_THRESH
# Setting BATCH overrides both (uniform, previous behaviour).
# Two-rate sampling on the EVENTS axis (executed DRIVE events), not the
# vector axis -- vectors are not comparable between directed and random
# (different events/vector), so the curves only line up on events.
#   EV_STEP1 events per sample while cumulative events <  EV_THRESH
#   EV_STEP2 events per sample once cumulative events >= EV_THRESH
# The batch size in VECTORS is derived after each sample from the
# observed events/vector rate, so the spacing adapts to whatever the
# vector set actually delivers.  Set BATCH to force a fixed vector
# batch instead (previous uniform behaviour).
EV_STEP1="${EV_STEP1:-50}"
EV_STEP2="${EV_STEP2:-1000}"
EV_THRESH="${EV_THRESH:-1000}"
if [[ -n "$BATCH_EXPLICIT" ]]; then B="$BATCH"; else B=1; fi
i=0
while (( i < N )); do
    end=$(( i + B )); (( end > N )) && end=$N
    batch=("${VECTORS[@]:$i:$((end - i))}")

    s0=$(date +%s)
    printf '%s\n' "${batch[@]}" | xargs -P "$PAR_JOBS" -I{} bash -c 'run_one "$@"' _ {}
    s1=$(date +%s); SIM_ACC=$(( SIM_ACC + s1 - s0 ))

    for vec in "${batch[@]}"; do
        r=$(cat "$WORK/logs/$(basename "$vec" .txt).result" 2>/dev/null)
        [[ "$r" == PASS ]] && PASS=$((PASS+1)) || FAIL=$((FAIL+1))
    done

    # Incremental cumulative merge: running + this batch -> running.
    # Consumed UCDBs are MOVED to merged/ rather than selected by mtime,
    # which would race with files written in the same second as the mark.
    : > "$WORK/new.list"
    for vec in "${batch[@]}"; do
        u="$WORK/logs/$(basename "$vec" .txt).ucdb"
        [[ -s "$u" ]] && echo "$u" >> "$WORK/new.list"
    done
    if [[ -s "$WORK/new.list" ]]; then
        if [[ -s "$RUNNING" ]]; then
            xargs -a "$WORK/new.list" "$QUESTA/bin/vcover" merge \
                -out "$WORK/next.ucdb" "$RUNNING" >/dev/null 2>&1
        else
            xargs -a "$WORK/new.list" "$QUESTA/bin/vcover" merge \
                -out "$WORK/next.ucdb" >/dev/null 2>&1
        fi
        mv -f "$WORK/next.ucdb" "$RUNNING"
        mkdir -p "$WORK/merged"
        xargs -a "$WORK/new.list" -I{} mv -f {} "$WORK/merged/" 2>/dev/null
    fi

    FUNC=$("$QUESTA/bin/vcover" report -cvg "$RUNNING" 2>/dev/null \
           | grep -i "TOTAL COVERGROUP COVERAGE" | grep -oP '[0-9]+\.[0-9]+' | head -1)
    read -r FC FT < <("$QUESTA/bin/vcover" report -details -cvg "$RUNNING" 2>/dev/null | awk '
        /TYPE \/[^ ]*\// { cg=$2; if (cg in s) next; s[cg]=1
            getline l; gsub(/^ +/,"",l); split(l,b,/ +/); c+=b[3]; t+=b[4] }
        END { print c, t }')

    read -r SH ST < <("$QUESTA/bin/vcover" report -code s "$RUNNING" 2>/dev/null | awk '
        # Same in-scope set as gen_coverage_csv.sh cat(): rnf_core +
        # chi_link + storage, excluding the OpenPiton SPARC-heritage
        # units.  Anchored, because a bare /^l15/ also matches l15_csm,
        # l15_hmc and l15_home_encoder and inflates the denominator.
        /^=== Design Unit:/ { du=$4; sub(/^work\./,"",du)
            keep = (du ~ /^(l15_pipeline|rx_control|txreq_encoder|response_encoder|request_register|l15_mshr|noc1buffer|noc2decoder|noc3buffer|l15|l15_wrap)$/) \
                || (du ~ /^rnf_link/) || (du ~ /^(rf_l15|sram_l15|bram_1rw)/) }
        /^ *Statements/ && keep { t+=$2; h+=$3 }
        END { print h, t }')

    T1=$(date +%s)
    SP=$(awk -v h="$SH" -v t="$ST" 'BEGIN{printf "%.2f", (t>0)?100*h/t:0}')
    # Executed DRIVE events so far -- the real stimulus delivered, as
    # opposed to what the vectors planned.  Directed loses ~58% to DUT
    # wedges, random ~11%, so vectors-run is not a fair x-axis.
    EV=$(grep -h "REPLAY" "$WORK"/logs/*.log 2>/dev/null \
         | grep -oP 'done: \K[0-9]+' | awk '{s+=$1} END{print s+0}')
    echo "$end,$((T1-T0)),$SIM_ACC,${EV:-0},$PASS,$FAIL,${FUNC:-0},${FC:-0},${FT:-0},$SP,${SH:-0},${ST:-0}" >> "$OUT"
    echo "[conv] $end/$N ev=${EV}  func=${FUNC}%  stmt=${SP}%  sim=${SIM_ACC}s"
    i=$end
    # Pick the next vector batch so the NEXT sample lands ~one event-step
    # further along, using the events/vector rate measured so far.
    if [[ -z "$BATCH_EXPLICIT" ]]; then
        if (( ${EV:-0} < EV_THRESH )); then tgt=$EV_STEP1; else tgt=$EV_STEP2; fi
        rate=$(( ${EV:-0} / (end > 0 ? end : 1) )); (( rate < 1 )) && rate=1
        B=$(( tgt / rate )); (( B < 1 )) && B=1
    fi
done

echo "[conv] wrote $OUT"
