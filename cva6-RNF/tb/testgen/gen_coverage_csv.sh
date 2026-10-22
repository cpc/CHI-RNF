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
# gen_coverage_csv.sh -- emit machine-readable coverage tables from the
# merged/excluded UCDBs produced by run_prefix_shared_sweep.sh.
#
#   coverage_structural.csv        one row per RTL design unit, all five
#                                  code metrics, from the POST-EXCLUSION
#                                  ucdb.  35 rows -- drill-down only.
#   coverage_structural_blocks.csv the same data rolled up to ~11 named
#                                  blocks (all rnf_link_* -> rnf_link,
#                                  etc.) plus a TOTAL row.  This is the
#                                  one to put on a chart axis.
#   coverage_functional.csv  one row per coverpoint/cross, plus a summary
#                            row per covergroup, from the MERGED ucdb
#                            (covergroups are unaffected by code exclusions)
#
# Usage:  ./gen_coverage_csv.sh [merged.ucdb] [excluded.ucdb]

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
VCOVER="${VCOVER:-/home/dmk/fedora/questa_24/questasim/bin/vcover}"
MERGED="${1:-$HERE/rnf_prefix_shared_cov_merged.ucdb}"
EXCL="${2:-$HERE/rnf_prefix_shared_cov_excluded.ucdb}"
OUT_S="$HERE/coverage_structural.csv"        # per design unit (drill-down)
OUT_SB="$HERE/coverage_structural_blocks.csv" # per block (plot this one)
OUT_F="$HERE/coverage_functional.csv"

[[ -f "$MERGED" ]] || { echo "missing $MERGED" >&2; exit 2; }
[[ -f "$EXCL"   ]] || { echo "missing $EXCL"   >&2; exit 2; }

# ── structural ───────────────────────────────────────────────────────────
# Three levels of granularity, because 35 leaf design units are far too
# many to put on a chart axis:
#
#   category  rnf_core / chi_link / storage, plus OUT_OF_SCOPE for the
#             OpenPiton SPARC-heritage units (see cat() below).  Those
#             are still reported, but on their own row BELOW the total
#             and excluded from it -- the CHI configuration never
#             instantiates them, so folding them in would understate
#             coverage of the design actually under test.
#   block     the unit a reader recognises -- all eight rnf_link_*
#             submodules roll up into one "rnf_link", the three NOC
#             buffers into "noc_buffers", and so on.  ~11 rows: this is
#             the level to plot.
#   module    the raw Questa design unit, kept for drill-down.
"$VCOVER" report -code sbcet "$EXCL" 2>/dev/null | awk -v OUT_M="$OUT_S" -v OUT_B="$OUT_SB" '
/^=== Design Unit:/ { du=$4; sub(/^work\./,"",du); seen[du]=1 }
/^ *Statements/  { SB[du]=$2; SH[du]=$3 }
/^ *Branches/    { BB[du]=$2; BH[du]=$3 }
/^ *Conditions/  { CB[du]=$2; CH[du]=$3 }
/^ *Expressions/ { EB[du]=$2; EH[du]=$3 }
/^ *Toggles/     { TB[du]=$2; TH[du]=$3 }
function cell(h,t) { return (t>0) ? sprintf("%d,%d,%.2f",h,t,100.0*h/t) : ",," }
# Sort keys: in-scope categories sort naturally, TOTAL then the
# out-of-scope block are forced to the bottom.  sed strips these.
function ord(c) { return (c=="OUT_OF_SCOPE") ? "zzz2_" c : c }
function cat(m) {
    if (m ~ /^rnf_link/)                                   return "chi_link"
    if (m ~ /^(rf_l15|sram_l15|bram_1rw)/)                 return "storage"
    # OUT OF SCOPE -- OpenPiton SPARC heritage.  l15_csm (coherence
    # state machine / directory), l15_hmc (home-map cache),
    # l15_home_encoder + flat_id_to_xy (mesh home-node addressing) and
    # the priority encoders implement the OpenPiton directory protocol.
    # A CHI configuration routes coherence through rnf_link to the HN-F
    # instead, so none of it is instantiated on a live path -- hence
    # 0/78 conditions and 2/130 expressions.  Reported separately below
    # rather than silently folded into the DUT total, which it would
    # drag down by ~1.4 points on statements.
    if (m ~ /^(l15_csm|l15_hmc|l15_home_encoder|flat_id_to_xy|l15_priority_encoder)/) return "OUT_OF_SCOPE"
    if (m ~ /^(l15_pipeline|rx_control|txreq_encoder|response_encoder|request_register|l15_mshr|noc1buffer|noc2decoder|noc3buffer|l15|l15_wrap)$/) return "rnf_core"
    return "SKIP"
}
# Roll-up name.  Anything not named here is already the right
# granularity and stands as its own block (l15_pipeline, rx_control,
# l15_mshr, txreq_encoder, response_encoder, request_register).
function blk(m) {
    if (m ~ /^rnf_link/)                                   return "rnf_link"
    if (m ~ /^noc[0-9]*(buffer|decoder)$/)                 return "noc_buffers"
    if (m ~ /^(l15|l15_wrap)$/)                            return "l15_top"
    if (m ~ /^(rf_l15|sram_l15|bram_1rw)/)                 return "storage"
    if (m ~ /^(l15_csm|l15_hmc|l15_home_encoder|flat_id_to_xy|l15_priority_encoder)/) return "sparc_legacy"
    return m
}
END {
    print "category,block,module,stmt_hit,stmt_total,stmt_pct,branch_hit,branch_total,branch_pct,cond_hit,cond_total,cond_pct,expr_hit,expr_total,expr_pct,toggle_hit,toggle_total,toggle_pct" > OUT_M
    for (m in seen) {
        c = cat(m); if (c=="SKIP") continue
        b = blk(m); bcat[b]=c; nmod[b]++
        SHb[b]+=SH[m]; SBb[b]+=SB[m]; BHb[b]+=BH[m]; BBb[b]+=BB[m]
        CHb[b]+=CH[m]; CBb[b]+=CB[m]; EHb[b]+=EH[m]; EBb[b]+=EB[m]
        THb[b]+=TH[m]; TBb[b]+=TB[m]
        # Only in-scope units feed the DUT total.
        if (c != "OUT_OF_SCOPE") {
            nmod_tot++
            SHt+=SH[m]; SBt+=SB[m]; BHt+=BH[m]; BBt+=BB[m]
            CHt+=CH[m]; CBt+=CB[m]; EHt+=EH[m]; EBt+=EB[m]
            THt+=TH[m]; TBt+=TB[m]
        }
        printf "%s,%s,%s,%s,%s,%s,%s,%s\n", ord(c), b, m,
               cell(SH[m],SB[m]), cell(BH[m],BB[m]), cell(CH[m],CB[m]),
               cell(EH[m],EB[m]), cell(TH[m],TB[m]) >> OUT_M
    }
    print "category,block,n_modules,stmt_hit,stmt_total,stmt_pct,branch_hit,branch_total,branch_pct,cond_hit,cond_total,cond_pct,expr_hit,expr_total,expr_pct,toggle_hit,toggle_total,toggle_pct" > OUT_B
    for (b in SHb)
        printf "%s,%s,%d,%s,%s,%s,%s,%s\n", ord(bcat[b]), b, nmod[b],
               cell(SHb[b],SBb[b]), cell(BHb[b],BBb[b]), cell(CHb[b],CBb[b]),
               cell(EHb[b],EBb[b]), cell(THb[b],TBb[b]) >> OUT_B
    printf "zzz1_TOTAL,ALL_DUT,%d,%s,%s,%s,%s,%s\n", nmod_tot,
           cell(SHt,SBt), cell(BHt,BBt), cell(CHt,CBt),
           cell(EHt,EBt), cell(THt,TBt) >> OUT_B
}'
for f in "$OUT_S" "$OUT_SB"; do
    { read -r hdr < "$f"; echo "$hdr"; tail -n +2 "$f" | sort -t, -k1,1 -k2,2; } \
      | sed 's/^zzz1_TOTAL/TOTAL/; s/^zzz2_OUT_OF_SCOPE/OUT_OF_SCOPE/' > "$f.tmp" && mv "$f.tmp" "$f"
done

# ── functional ───────────────────────────────────────────────────────────
"$VCOVER" report -details -cvg "$MERGED" 2>/dev/null | awk '
BEGIN { print "covergroup,kind,name,bins_covered,bins_missing,bins_total,pct" }
$1=="TYPE" {
    cg=$2; sub(/.*\//,"",cg); cgpct=$3; gsub("%","",cgpct); active=1
    getline l; gsub(/^ +/,"",l); split(l,b,/ +/)
    if (!(cg in doneCG)) { doneCG[cg]=1
        printf "%s,covergroup,%s,%s,%s,%s,%s\n", cg, cg, b[3], b[4]-b[3], b[4], cgpct
        # Two different totals, because they answer different
        # questions.  The vcover headline TOTAL COVERGROUP COVERAGE is
        # the unweighted MEAN of the per-type percentages; summing raw
        # bins instead weights big crosses more heavily.  Emit both.
        cov+=b[3]; tot+=b[4]; pctsum+=cgpct; ngroups++ }
    next
}
/^ Covergroup instance/ { active=0 }
active && (/^ *Coverpoint /||/^ *Cross /) {
    kind=($1=="Cross")?"cross":"coverpoint"; name=$2; p=$3; gsub("%","",p)
    getline l; gsub(/^ +/,"",l); split(l,a,/ +/)
    key=cg"|"name; if (key in seen) next; seen[key]=1
    printf "%s,%s,%s,%s,%s,%s,%s\n", cg, kind, name, a[3], a[4]-a[3], a[4], p
}
END {
    printf "TOTAL,bins,ALL_BINS,%d,%d,%d,%.2f\n", cov, tot-cov, tot, 100.0*cov/tot
    printf "TOTAL,type,ALL_COVERGROUPS,%d,%d,%d,%.2f\n",
           cov, tot-cov, tot, pctsum/ngroups
}' > "$OUT_F"

echo "wrote $OUT_S  ($(($(wc -l < "$OUT_S")-1)) rows)"
echo "wrote $OUT_SB ($(($(wc -l < "$OUT_SB")-1)) rows)"
echo "wrote $OUT_F  ($(($(wc -l < "$OUT_F")-1)) rows)"
