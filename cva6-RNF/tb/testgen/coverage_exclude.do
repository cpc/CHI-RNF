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
# Coverage exclusions for the RN-F IP-level sweep — reachable subset only.
#
# Apply with:
#     cd <this directory>
#     vsim -c -viewcov <ucdb> -do "do coverage_exclude.do; coverage save <ucdb>; quit -f"
#
# MUST be run from this directory, and do NOT redirect stdout away: Questa
# reports unmatched exclusions as vish-4036 warnings rather than as errors,
# so a silently-failing exclusion looks identical to a successful one.  Check
# the run log for vish-4036 after every invocation.
#
# ── Filename note for the pipeline ──────────────────────────────────────────
# Both cache/l15/rtl/l15_pipeline.tmp.v and l15_rnf_pipeline.tmp.v declare
# `module l15_pipeline`, so the two are easy to confuse.  The UCDB indexes
# l15_pipeline.tmp.v — both the recorded path AND the line numbers refer to
# that file.  Confirmed by content: the uncovered runs 2584-2621 and
# 3805-3842 land exactly on the `if (stall_s2)` / `if (stall_s3)` register-
# hold blocks in l15_pipeline.tmp.v, which are 38 statements each.  Read line
# numbers from l15_pipeline.tmp.v when editing this file.

# ── Line numbers are FRAGILE: re-derive after any RTL edit ─────────────────
# These are absolute line numbers into l15_pipeline.tmp.v.  Any edit to that
# file silently invalidates them, and the failure is worse than it looks:
#   * an exclusion landing on a non-coverable line reports vish-4036 and does
#     nothing -- visible if you read the log;
#   * an exclusion landing on a DIFFERENT coverable line reports nothing at
#     all and excludes the wrong statement, inflating coverage.
# Re-derived 2026-08-13 after two working-tree hunks (+11 at line 954, +7
# more at 4760) shifted 99 of the 134 l15_pipeline exclusions: 49 had gone
# silent with vish-4036 and the other 50 had moved onto unintended lines.
# Deltas came out exactly {0: 35, +11: 80, +18: 19}, matching the hunks.
#
# To re-derive, match by SOURCE TEXT rather than by arithmetic: take the
# content of line N from the revision the numbers were last valid for and
# locate that text in the current file, using the hunk offset only to
# disambiguate repeated lines.  After running, the log MUST show zero
# vish-4036.
set RTL /home/dmk/fedora/work/chi-rnf/cva6-RNF/cache/l15/rtl

# ── l15_pipeline: IFILL / interrupts / config / diag / HMC / ICACHE-inv ─────
# Predecoder arms for request types the IP-level TB cannot generate: there is
# no CVA6 instruction fetch, no interrupt controller, and no diag/HMC agent.
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 442
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 529
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 550
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 572
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 598
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 605
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 616
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 664
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 685
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 687
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 689
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 700
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 703
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 705
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 710
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 712
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 716

# LOAD_PREFETCH — out of scope; not driven from CVA6 in this TB config.
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 690
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 691

# ── txreq_encoder: IFILL / INTERRUPT_FWD ───────────────────────────────────
# 442-491: IFILL request encoding, both the non-cacheable (ReadNoSnp) and the
#          cacheable (ReadClean + MSG_CACHE_TYPE_INS) arms.  Structurally
#          unreachable: the IP-level DUT has no instruction-fetch port.
# 607-620: cross-CPU interrupt forwarding (L15_NOC1_REQTYPE_INTERRUPT_FWD).
for {set L 442} {$L <= 491} {incr L} { coverage exclude -src $RTL/txreq_encoder.v -line $L }
for {set L 607} {$L <= 620} {incr L} { coverage exclude -src $RTL/txreq_encoder.v -line $L }
# REMOVED: `coverage exclude ... -line 425`.  Line 425 is
#     msg_type_chi = `CHIE_READCLEAN;
# in the CACHEABLE DATA-LOAD arm (MSG_TYPE_LOAD_REQ / MSG_CACHE_TYPE_DATA),
# not in the IFILL arm.  It is COVERED — 1504 hits across the sweep — so
# excluding it silently deleted a real hit and inflated the reported number.
# The visually identical statement in the IFILL arm is line 472, which is
# already inside the 442-491 loop above.  Two lines, same text, different
# blocks: exactly the trap that makes hand-picked line exclusions unsafe.
# NOTE: line 472 was listed separately here and is already inside the 442-491
# loop above — the duplicate raised a spurious "already excluded" warning.
# NOTE: line 551 targeted a COMMENT (`// msg_type_chi = CHIE_CLEANUNIQUE;`),
# so it matched no coverage bin.  The CleanUnique encoder arm is commented out
# in the RTL entirely, leaving nothing to exclude.

# ── rx_control: dead CleanUnique response paths ────────────────────────────
# The RN-F never emits CleanUnique, so its response-decode arms are dead.
coverage exclude -src $RTL/rx_control.sv -line 1059
coverage exclude -src $RTL/rx_control.sv -line 1919
# NOTE: line 1884 targeted a COMMENT (`// dataless response, CHIE_CLEANUNIQUE`)
# and matched nothing; the live arm is at 1919, already excluded above.

# ── rx_control: WriteCleanFull bypass path ─────────────────────────────────
# DEAD BY CONSTRUCTION, not merely gated.  rx_control.sv declares
# wrcl_valid_r (line 313), assigns it 1'b0 once in a combinational default
# block (line 985), and never assigns it anything else anywhere in the
# design.  The guard at line 1347 can therefore never be true.
# (An earlier revision of this comment called it "gated by a condition
# this configuration never asserts", which wrongly implied the path was
# reachable in principle.)
for {set L 1347} {$L <= 1373} {incr L} { coverage exclude -src $RTL/rx_control.sv -line $L }

# ═══════════════════════════════════════════════════════════════════════════
# l15_pipeline — enum-traced downstream exclusions
#
# The block above only covers STAGE-1 PREDECODE (the point where a PCX request
# is classified).  A request type that is classified at S1 also has decode
# logic at S1, dcache/tag/mesi operations at S2, and output-generation arms in
# three separate S3 case statements (cpx_operation_s3 / noc1_operation_s3 /
# noc3_operation_s3).  Excluding only the predecode arm therefore leaves the
# downstream consequences counted.
#
# The lines below were derived mechanically: every uncovered statement was
# mapped to its enclosing case-arm label by parsing begin/end nesting, then
# the arms belonging to absent agents were selected.  Two safety rules held:
#   1. Only lines that are ALREADY UNCOVERED appear here, so applying this
#      set cannot remove a covered statement.  Verify by checking that the
#      hit count is unchanged after applying (bins drop, hits do not).
#   2. Arms that could not be tied to an absent agent with certainty were
#      left in — see the "deliberately NOT excluded" note at the end.
# ═══════════════════════════════════════════════════════════════════════════
 
# IFILL / instruction fetch  (no I-fetch port in the IP-level TB)
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 378
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 706
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 1148
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 1150
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 1380
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 1382
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 1383
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 1384
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 1385
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 1386
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 1387
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 1678
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 1681
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 1682
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 1688
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 1689
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 4794
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 4795
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 4796
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 4797
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 5046
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 5047
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 5048
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 5049
 
# Interrupts  (no interrupt controller)
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 819
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 820
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 1997
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 1998
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 2005
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 2006
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 2010
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 2011
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 2012
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 2013
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 4909
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 4910
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 4911
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 4912
 
# Diagnostic / config-register access  (no diag agent)
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 1373
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 1374
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 1375
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 1498
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 1499
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 1500
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 3053
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 3054
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 3055
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 3056
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 3060
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 3061
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 3062
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 3063
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 3064
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 3160
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 3162
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 3497
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 3498
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 3499
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 3500
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 4705
 
# HMC / CSM  (SPARC home-map cache; HN-F NID is fixed here)
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 2033
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 2034
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 3391
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 3392
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 3394
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 3396
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 3400
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 3401
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 3402
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 3404
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 3415
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 3418
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 4571
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 4572
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 4573
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 4709
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 4710
 
# CAS  (SPARC atomic; RISC-V AMOs use the AMO_* path)
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 808
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 809
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 813
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 1613
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 1659
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 4829
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 4830
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 4831
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 4832
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 4833
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 4936
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 4937
 
# SPARC-only PCX request types  (RISC-V transducer never emits these)
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 532
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 553
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 575
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 823
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 825
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 827
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 829
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 831
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 833
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 4544
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 4545
 
# Prefetch  (declared out of scope)
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 1342
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 1344
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 1925
 
# IFILL CPX data-mux arms  (siblings in the same block are covered)
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 4664
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 4665
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 4666
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 4667
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 4669
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 4670
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 4671
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 4672
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 4697
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 4698
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 4699
coverage exclude -src $RTL/l15_pipeline.tmp.v -line 4700

# ── Deliberately NOT excluded — genuine, reachable gaps ────────────────────
#   L15_REQTYPE_LINE_FLUSH and its downstream arms  (~45 statements)
#       Reachable; the driver has do_cbo_inval (invalidate_cacheline) but no
#       task that raises L15_REQTYPE_LINE_FLUSH.  Closing this needs a
#       do_cbo_flush driver task, not an exclusion.
#   if (stall_s2) / if (stall_s3) register-hold blocks  (76 statements)
#       Reachable under back-pressure; never fires because the Murphi model
#       assumes MSHR depth 1, so the pipeline sees no contention.  Same root
#       cause as the request_register CAM-hit gap.
#   L15_REQTYPE_ACKDT_LD_NC, L15_REQTYPE_ACK_ATOMIC
#       NC loads and AMOs ARE driven; these arms are under-stimulated, not
#       unreachable.
#   L15_NOC1_GEN_DATA_LD_REQUEST, L15_NOC3_GEN_{INVAL,DOWNGRADE}_ACK_*
#       Could not be tied to an absent agent with certainty.  Left counted.

# ═══════════════════════════════════════════════════════════════════════════
# Remaining RTL DUT blocks — verified unreachable arms
# Each line below was confirmed (a) present in the uncovered set, and (b)
# guarded by a condition tied to an agent absent from this TB.
# ═══════════════════════════════════════════════════════════════════════════
set TILE /home/dmk/fedora/work/chi-rnf/cva6-RNF/singlecore-cva6/tile/l15/rtl

# rx_control — IFILL data return.  Guarded by `if (req_icache)`: the cacheable
# arm (READSHARED/READCLEAN 32B-subline select) and the NC arm (READNOSNP).
foreach L {1801 1802 1803 1804 1807 1808 1809 1810 1814 1818 1819 1820} {
    coverage exclude -src $RTL/rx_control.sv -line $L
}

# txreq_encoder — MSG_TYPE_CAS_REQ.  SPARC compare-and-swap; RISC-V AMOs take
# the AMO_* path and never reach this arm.
foreach L {574 575 576} { coverage exclude -src $RTL/txreq_encoder.v -line $L }

# response_encoder — MSG_TYPE_INV_FWDACK.  SPARC forwarded-invalidation ack;
# no forwarding agent exists in a single-RN-F topology.
foreach L {783 784} { coverage exclude -src $RTL/response_encoder.sv -line $L }

# l15_mshr — IFILL MSHR deallocation, guarded by mshrid_s3 == L15_MSHR_ID_IFILL.
coverage exclude -src $RTL/l15_mshr.tmp.v -line 863

# noc1buffer — CAS data path, guarded by req_type == L15_NOC1_REQTYPE_CAS_REQUEST
# (233-235 write the 16B payload, 417 acks it as NOC1_BUFFER_ACK_DATA_16B).
foreach L {233 234 235 417} { coverage exclude -src $TILE/noc1buffer.tmp.v -line $L }

set LINK /home/dmk/fedora/work/chi-rnf/cva6-RNF/cache/rnf_link

# rnf_link_txrsp_wrap — CHI retry protocol, completer side.  RetryAck (the
# always block at 214) and PCrdGrant (at 231) are responses a COMPLETER sends
# to throttle a requester; an RN-F receives them and never transmits them.
# rnf_link is written as a generic CHI link, so the logic is present but has
# no way to activate here:
#   * qos_txrsp_retryack_* / qos_txrsp_pcrdgnt_* are declared in l15_rnf.v
#     (1608, 1612) and connected into rnf_link (1687, 1693) with NO DRIVER;
#   * the gating valids qos_txrsp_retryack_valid_s1 / qos_txrsp_pcrdgnt_valid_s2
#     appear only at l15_rnf.v 1686/1692 -- never declared, never driven, so
#     they are implicit wires floating at z;
#   * no QoS or retry block is instantiated anywhere under cache/.
# The arbitration arms that select these flits (txrsp_wrap 266-267) therefore
# never assert and both always blocks are unreachable by any stimulus.
# Re-check this if retry support is ever added -- these become live.
foreach L {214 216 217 218 219 220 221 222 223 224 225 226 227 228} {
    coverage exclude -src $LINK/rnf_link_txrsp_wrap.v -line $L
}
foreach L {231 233 234 235 236 237 238 239 240 241 242 243 244 245} {
    coverage exclude -src $LINK/rnf_link_txrsp_wrap.v -line $L
}

# ── CSM / distributed home-map subtree ─────────────────────────────────────
# OpenPiton's coherent-shared-memory machinery: l15_csm resolves which tile
# owns a line and l15_hmc caches that mapping.  This RN-F talks to ONE fixed
# HN-F (HNF_NID_PARAM), so the home ID is a constant and essentially none of
# the lookup, replacement or ticket logic activates -- l15_hmc measured 15%
# branch and 13% condition coverage, and the three units together left 505
# uncovered items, the largest single block in the design.
#
# This is a CONFIGURATION exclusion, not a dead-code one: the logic is
# perfectly reachable in a multi-tile OpenPiton system.  It is waived here
# because a single-HN-F RN-F cannot exercise it by construction, and leaving
# it in the denominator understates coverage of the design actually built.
# DELETE THIS BLOCK if a multi-home configuration is ever synthesised.
#
# Excluded by DESIGN UNIT rather than by scope so it holds for both the
# IP-level TB (rnf_ip_tb.u_dut.l15...) and the gem5 co-sim TB
# (tb_chi_system.u_rnf_wrap.RNF_GEN[i].u_rnf.l15.l15...).
#
# The four priority encoders are instantiated ONLY under l15_hmc (24/12/6/3
# instances, all inside the CSM subtree -- verified), so excluding them is
# safe.  flat_id_to_xy is deliberately NOT excluded: 2 instances exist and
# only 1 is under CSM, so a -du exclusion there would waive live logic.
foreach DU {l15_csm l15_hmc l15_home_encoder
            l15_priority_encoder_1 l15_priority_encoder_2
            l15_priority_encoder_3 l15_priority_encoder_4} {
    coverage exclude -du work.$DU
}

# ── txreq_encoder: request types this L1.5 never issues ───────────────────
# Encoder arms for PCX request classes that no RISC-V path produces.  Not
# dead by construction the way the CHI retry logic is -- the encoder would
# emit them if the L1.5 asked -- but nothing upstream ever asks, so no
# stimulus can reach them.
#
#   414-415  MSG_TYPE_PREFETCH_REQ.  Guarded by `if (req_prefetch)`; the
#            L1.5 never sets req_prefetch (CVA6 issues no prefetch through
#            the PCX request path).
#   572      L15_NOC1_REQTYPE_CAS_REQUEST case label.  SPARC compare-and-
#            swap; RISC-V AMOs take the AMO_* path.  Its payload (574-576)
#            is already excluded above for the same reason.
# Two candidates were TRIED AND REVERTED, because a -line exclusion waives
# every item on the line and both of these lines carry live ones:
#
#   369-370  On-chip-device address decode.  Only the TRUE arm of
#            `msg_dest_fbits = (addr[39:33]==7'b1110000) ? addr[...] :
#            NOC_FBITS_L2` is unreachable; the assignment itself and the
#            NOC_FBITS_L2 arm run on every request.  Excluding the pair cost
#            1 covered statement and 1 covered branch (356->355, 62->61).
#   1050     `req_type == 3` and `req_type == 7` are unreachable, but the
#            same expression tests L15_NOC1_REQTYPE_LD_REQUEST, which is live.
#
# Both remain in the denominator as a result.  Prune a line only after
# confirming the hit counts do not move.
foreach L {414 415 572} {
    coverage exclude -src $RTL/txreq_encoder.v -line $L
}

# ── txreq_encoder: CSM-driven conditions ──────────────────────────────────
# csm_noc1encoder_req_val is an INPUT PORT (line 88) driven by l15_csm, which
# is excluded above as a subsystem.  With CSM inactive the port is tied 0, so
# every FEC target on the two expressions that consume it is unreachable:
#
#   235   if ((last_req_source == `L15_NOC1ENCODER_SOURCE_L15 && flit_state != 0)
#          || csm_noc1encoder_req_val == 1'b0)
#         All three input terms report no hits -- last_req_source cannot vary
#         because the TX REQ arbiter only ever sees one live source.
#   1032  if (csm_noc1encoder_req_val && flit_state == msg_length && channel_ready ...)
#         The CSM acknowledge path.  Its guard is constant-false, which masks
#         flit_state, channel_ready and req_source alongside it.
#
# Scoped with `-code c` DELIBERATELY.  Line 235's BRANCHES are covered (its
# else-path drives req_source = SOURCE_L15), so a plain -line exclusion would
# waive live branch bins -- the same trap that reverted 369-370 above.
# Restricting to the condition metric removes 7 unreachable FEC targets and
# leaves statements and branches at 356/371 and 62/76, unchanged.
#
# DELETE ALONGSIDE the l15_csm exclusion if a multi-home build is synthesised.
coverage exclude -src $RTL/txreq_encoder.v -line 235  -code c
coverage exclude -src $RTL/txreq_encoder.v -line 1032 -code c

# rx_control — RSP-channel cacheline-state decode, case (rxrsp_resp_r) at 1909.
# Only the CHIE_COMP_RESP_I arm (1933) is reachable.  The state-GRANTING arms
# are dead because no dataless Comp that grants a state ever arrives:
#
#   txreq_encoder.v:550-554 has CHIE_CLEANUNIQUE COMMENTED OUT -- a store
#   upgrade emits CHIE_READUNIQUE instead, whose completion is CompData on the
#   DAT channel, decoded by the separate case (rxdat_resp_r) at line 1746.
#   MakeUnique likewise maps to ReadUnique.  With neither emitted, the RSP
#   channel only ever carries Comp for CMOs/WriteNoSnpPtl, CompDBIDResp,
#   DBIDResp and ReadReceipt -- all with Resp = I.
#
# 1920 is doubly dead: its guard is req_opcode == CHIE_CLEANUNIQUE (1919),
# which cannot hold while that encoder line stays commented out.
#
# UNCOMMENT txreq_encoder.v:551 AND THESE BECOME LIVE -- re-check then.
#
# Deliberately NOT excluded, these are stimulus gaps and not dead code:
#   1894 CHIE_READRECEIPT   -- HN-F may send it for ordered reads; ours do not
#   1898/1900 CHIE_RESPSEPDATA -- split completion (RespSepData + DataSepResp);
#                              the RTL supports it (respsepdata_received /
#                              datasepresp_received at 992-993) but neither the
#                              abstract HN-F nor gem5 ever chooses that shape
#   1902 CHIE_RETRYACK      -- RN-F sets allowretry=1, so a completer may
#                              legitimately throttle it; no responder does
foreach L {1910 1912 1913 1915 1920 1921 1922 1924 1926 1928 1929} {
    coverage exclude -src $RTL/rx_control.sv -line $L
}
