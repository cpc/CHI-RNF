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
# run_random_seeds.sh -- repeat the constrained-random convergence
# experiment across N seeds.
#
# One random run is a single sample of a stochastic process; quoting its
# time-to-coverage as though it were a property of the method overstates
# what was measured.  This runs the whole experiment per seed and keeps
# every curve, so the comparison against the directed set can be stated
# as a distribution (min / median / max) rather than a point.
#
# Also re-measures the directed set once, because both sets are being
# scored against a covergroup that has changed (CompDBIDResp stimulus,
# ReadNoSnp scoped out) since the last comparison.
#
# Usage:
#   SEEDS=10 COUNT=2000 ./run_random_seeds.sh
#
# Outputs:
#   convergence_random_seed<N>.csv   one curve per seed
#   convergence_directed.csv         directed reference, same harness
#   convergence_random_summary.csv   milestone crossings, all seeds

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

SEEDS="${SEEDS:-10}"
COUNT="${COUNT:-2000}"
STEPS="${STEPS:-65}"
BATCH="${BATCH:-100}"
PAR_JOBS="${PAR_JOBS:-12}"
DO_DIRECTED="${DO_DIRECTED:-1}"

echo "[seeds] $SEEDS random runs x $COUNT vectors, batch=$BATCH, par=$PAR_JOBS"

if [[ "$DO_DIRECTED" == "1" ]]; then
    echo "[seeds] === directed reference ==="
    VEC_DIR=vectors_rnf_prefix_shared BATCH=60 PAR_JOBS="$PAR_JOBS" PER_TIMEOUT=600 \
        OUT=convergence_directed.csv ./run_convergence.sh 2>&1 | tail -2
fi

for (( s = 1; s <= SEEDS; s++ )); do
    echo "[seeds] === random seed $s / $SEEDS ==="
    ./gen_random_vectors.py --count "$COUNT" --steps "$STEPS" --seed "$s" >/dev/null
    VEC_DIR=vectors_rnf_random BATCH="$BATCH" MAX="$COUNT" PAR_JOBS="$PAR_JOBS" \
        OUT="convergence_random_seed${s}.csv" ./run_convergence.sh 2>&1 | tail -1
    # Retain the merged UCDB per seed.  run_convergence.sh reuses one
    # work dir and rm -rf's it, so without this only the LAST run's
    # bin-level data survives -- and if a run is interrupted mid-seed,
    # what survives is a partial UCDB that silently misattributes to the
    # previous seed.  That produced a bogus head-to-head once already.
    if [[ -s .conv_vectors_rnf_random/running.ucdb ]]; then
        cp -f .conv_vectors_rnf_random/running.ucdb "cov_random_seed${s}.ucdb"
        echo "[seeds] retained cov_random_seed${s}.ucdb"
    fi
done

# ── Milestone table across seeds ────────────────────────────────────
# For each target coverage level, the first (vectors, sim_s) at which
# each curve reaches it.  A seed that never reaches a level is recorded
# as NA -- that is a result, not a gap.
{
  echo "target,source,seed,vectors,sim_s,final_pct"
  for m in 85 88 90 91 92 93 94 95 96; do
      if [[ -f convergence_directed.csv ]]; then
          awk -F, -v m="$m" 'NR>1 && $6+0>=m {print m",directed,-,"$1","$3; found=1; exit}
              END{ if(!found) print m",directed,-,NA,NA" }' convergence_directed.csv \
            | while read -r row; do
                fin=$(awk -F, 'END{print $6}' convergence_directed.csv); echo "$row,$fin"; done
      fi
      for (( s = 1; s <= SEEDS; s++ )); do
          f="convergence_random_seed${s}.csv"
          [[ -f "$f" ]] || continue
          awk -F, -v m="$m" -v s="$s" 'NR>1 && $6+0>=m {print m",random,"s","$1","$3; found=1; exit}
              END{ if(!found) print m",random,"s",NA,NA" }' "$f" \
            | while read -r row; do
                fin=$(awk -F, 'END{print $6}' "$f"); echo "$row,$fin"; done
      done
  done
} > convergence_random_summary.csv

echo "[seeds] wrote convergence_random_summary.csv"
