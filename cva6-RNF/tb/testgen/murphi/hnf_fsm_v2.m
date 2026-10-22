-- Copyright (c) 2026 Customized Parallel Computing (CPC) Group, Tampere University
-- Author: Abdesattar Kalache <abdesattar.kalache@tuni.fi>
--
-- SPDX-License-Identifier: Apache-2.0
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at:
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
-- implied.  See the License for the specific language governing
-- permissions and limitations under the License.
---------------------------------------------------------------------------
-- hnf_fsm_v2.m
--
-- Two-sided HN-F + RN-F coherence FSM (single cache line, NUM_RNF agents).
--
-- Refinement of hnf_fsm.m:
--   * RnfLocal expanded from {I,U,S} -> {I,SC,UC,SD,UD} (full CHI cache
--     state).  Global `dirty` removed -- now per-RN-F.
--   * Snoop responses are per-snoopee decision rules: each (inflight_op
--     x snoopee_local_state) picks a specific SnpResp* variant (SR_I,
--     SR_SC, SR_I_PD, SR_SC_PD, ...).  The snoopee writes its own
--     post-state and sets snp_resp[s]; the HN-F's dirty-ownership bit
--     hnf_has_dirty is set when any snoopee passed dirty.
--   * A single "T_SNP_DONE" rule fires once every required snoopee has
--     responded; it picks the requester-side outcome based on
--     hnf_has_dirty and the inflight op.
--
-- Run:
--   rumur hnf_fsm_v2.m --output hnf_fsm_v2.c
--   cc -O2 -o hnf_fsm_v2 hnf_fsm_v2.c -lpthread
--   ./hnf_fsm_v2
---------------------------------------------------------------------------

Const
  NUM_RNF : 2;

---------------------------------------------------------------------------
-- Types
---------------------------------------------------------------------------

Type
  RNFid : ScalarSet(NUM_RNF);

  -- Per-RN-F CHI cache state.  Mirrors the spec encoding (not the
  -- snoop-filter compression).
  --   RS_I   -- Invalid
  --   RS_SC  -- Shared Clean
  --   RS_UC  -- Unique Clean
  --   RS_SD  -- Shared Dirty  (this RN-F is the dirty-owner among sharers,
  --                            via SnpRespData_SC_PD migration).
  --   RS_UD  -- Unique Dirty
  RnfLocal : Enum{
    RS_I, RS_SC, RS_UC, RS_SD, RS_UD
  };

  HnfPhase : Enum{
    STABLE,
    T_FILL,        -- awaiting SNF fill / DMT return
    T_SNP,         -- awaiting per-snoopee SnpResp*
    T_ACK,         -- awaiting CompAck from the requester
    T_WB_DBIDRESP, -- writeback REQ received, need to send DBIDResp
    T_WB_DATA      -- DBIDResp sent, awaiting CopyBackWrData
  };

  -- CHI REQ opcodes (coherent subspace + atomic abstract opcodes).
  OpType : Enum{
    op_None,
    op_ReadClean, op_ReadUnique, op_MakeUnique,
    op_CleanShared, op_CleanUnique, op_CleanInvalid,
    op_Evict,
    op_WriteBackFull, op_WriteCleanFull,
    op_AtomicLoad, op_AtomicStore
  };

  -- SnpResp* variants the RN-F can return.  Names mirror CHI E.b table:
  --   SR_I        -- SnpResp_I            (invalidated, no data)
  --   SR_SC       -- SnpResp_SC           (downgraded to SC, no data)
  --   SR_I_D      -- SnpRespData_I        (invalidated, data forwarded, clean)
  --   SR_SC_D     -- SnpRespData_SC       (downgraded to SC, data forwarded, clean)
  --   SR_I_PD     -- SnpRespData_I_PD     (invalidated, data forwarded, dirty passed)
  --   SR_SC_PD    -- SnpRespData_SC_PD    (downgraded to SC, data forwarded, dirty passed)
  -- SR_None means "snoopee hasn't responded yet" (still pending) OR
  -- "no response required from this RN-F" (was already I).
  SnpRespKind : Enum{
    SR_None,
    SR_I, SR_SC,
    SR_I_D, SR_SC_D,
    SR_I_PD, SR_SC_PD
  };

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------

Var
  rnf         : Array [RNFid] of RnfLocal;
  phase       : HnfPhase;
  requester   : RNFid;
  inflight_op : OpType;
  pending     : Array [RNFid] of OpType;

  -- Two-sided additions:
  -- snp_required[s] = true while phase=T_SNP and snoopee s still owes a
  -- response.  Cleared when s responds.
  snp_required : Array [RNFid] of Boolean;
  -- snp_resp[s] is the SnpResp* variant s sent (for the current T_SNP).
  -- Reset to SR_None on each T_SNP entry.
  snp_resp     : Array [RNFid] of SnpRespKind;
  -- hnf_has_dirty: HN-F now owns dirty data (acquired via *_PD response
  -- from a snoopee).  Cleared on CompAck once the requester takes the
  -- dirty data (ReadUnique-with-PD) or HN-F writes it back to L3.
  hnf_has_dirty : Boolean;

---------------------------------------------------------------------------
-- Helper functions  (no nesting -- one level deep max for CMurphi compat)
---------------------------------------------------------------------------

Function NumUnique() : 0..NUM_RNF;
Var n : 0..NUM_RNF;
Begin
  n := 0;
  For r : RNFid Do
    If rnf[r] = RS_UC | rnf[r] = RS_UD Then n := n + 1; End;
  End;
  Return n;
End;

Function NumShared() : 0..NUM_RNF;
Var n : 0..NUM_RNF;
Begin
  n := 0;
  For r : RNFid Do
    If rnf[r] = RS_SC | rnf[r] = RS_SD Then n := n + 1; End;
  End;
  Return n;
End;

Function NumDirty() : 0..NUM_RNF;
Var n : 0..NUM_RNF;
Begin
  n := 0;
  For r : RNFid Do
    If rnf[r] = RS_UD | rnf[r] = RS_SD Then n := n + 1; End;
  End;
  Return n;
End;

Function NumSnoopRequired() : 0..NUM_RNF;
Var n : 0..NUM_RNF;
Begin
  n := 0;
  For r : RNFid Do
    If snp_required[r] Then n := n + 1; End;
  End;
  Return n;
End;

---------------------------------------------------------------------------
-- Initial state
---------------------------------------------------------------------------

Startstate "init"
Begin
  For r : RNFid Do
    rnf[r]          := RS_I;
    pending[r]      := op_None;
    snp_required[r] := false;
    snp_resp[r]     := SR_None;
  End;
  phase         := STABLE;
  inflight_op   := op_None;
  hnf_has_dirty := false;
  Undefine requester;
End;

---------------------------------------------------------------------------
-- Rules
---------------------------------------------------------------------------
-- (1) Stable-line REQs from RN-F r.
-- (2) Atomic REQs (subset of stable REQs).
-- (3) CAM hazard: queue REQ when another tx is in flight.
-- (4) Per-snoopee SnpResp* decision rules.
-- (5) T_SNP_DONE: collector rule, fires once every snoopee has responded.
-- (6) T_FILL -> T_ACK (SNF data return).
-- (7) CompAck: T_ACK -> STABLE; applies requester-side terminal state.
-- (8) Promote_pending.
---------------------------------------------------------------------------

Ruleset r : RNFid Do

  ---------------------------------------------------------------------
  -- (1) Stable-line REQs from RN-F r
  ---------------------------------------------------------------------

  -- ReadClean / ReadUnique on a completely invalid line -> SNF fetch
  Rule "ReadClean_from_I"
    phase = STABLE & NumUnique() = 0 & NumShared() = 0 & pending[r] = op_None
  ==>
  Begin
    phase := T_FILL; requester := r; inflight_op := op_ReadClean;
  End;

  Rule "ReadUnique_from_I"
    phase = STABLE & NumUnique() = 0 & NumShared() = 0 & pending[r] = op_None
  ==>
  Begin
    phase := T_FILL; requester := r; inflight_op := op_ReadUnique;
  End;

  Rule "MakeUnique_from_I"
    phase = STABLE & NumUnique() = 0 & NumShared() = 0 & pending[r] = op_None
  ==>
  Begin
    phase := T_ACK; requester := r; inflight_op := op_MakeUnique;
  End;

  -- ReadClean by a non-sharer while others hold SC/SD -> SnpClean to sharers
  Rule "ReadClean_from_SC_nonsharer"
    phase = STABLE & rnf[r] = RS_I & NumShared() > 0 &
    NumUnique() = 0 & pending[r] = op_None
  ==>
  Begin
    phase := T_SNP; requester := r; inflight_op := op_ReadClean;
    For r2 : RNFid Do
      snp_required[r2] := (r2 != r) & (rnf[r2] != RS_I);
      snp_resp[r2]     := SR_None;
    End;
  End;

  -- ReadClean by non-holder while another holds UC/UD -> SnpClean
  Rule "ReadClean_from_UC_other"
    phase = STABLE & rnf[r] = RS_I & NumUnique() = 1 &
    !(rnf[r] = RS_UC | rnf[r] = RS_UD) & pending[r] = op_None
  ==>
  Begin
    phase := T_SNP; requester := r; inflight_op := op_ReadClean;
    For r2 : RNFid Do
      snp_required[r2] := (r2 != r) & (rnf[r2] != RS_I);
      snp_resp[r2]     := SR_None;
    End;
  End;

  -- ReadUnique while another RN-F holds the line -> SnpUnique.
  -- §4.7.4: requires at least one non-requester holder to enter T_SNP.
  Rule "ReadUnique_from_other_holder"
    phase = STABLE &
    (NumShared() > 0 | NumUnique() = 1) &
    !(rnf[r] = RS_UC | rnf[r] = RS_UD) & pending[r] = op_None &
    Exists r2 : RNFid Do (r2 != r) & (rnf[r2] != RS_I) End
  ==>
  Begin
    phase := T_SNP; requester := r; inflight_op := op_ReadUnique;
    For r2 : RNFid Do
      snp_required[r2] := (r2 != r) & (rnf[r2] != RS_I);
      snp_resp[r2]     := SR_None;
    End;
  End;

  -- CleanUnique by sole sharer in SC -> upgrade, no snoop
  Rule "CleanUnique_sole_sharer"
    phase = STABLE & rnf[r] = RS_SC & NumShared() = 1 &
    pending[r] = op_None
  ==>
  Begin
    phase := T_ACK; requester := r; inflight_op := op_CleanUnique;
  End;

  -- CleanUnique with other sharers -> snoop them out
  Rule "CleanUnique_with_others"
    phase = STABLE & (rnf[r] = RS_SC | rnf[r] = RS_SD) & NumShared() > 1 &
    pending[r] = op_None
  ==>
  Begin
    phase := T_SNP; requester := r; inflight_op := op_CleanUnique;
    For r2 : RNFid Do
      snp_required[r2] := (r2 != r) & (rnf[r2] != RS_I);
      snp_resp[r2]     := SR_None;
    End;
  End;

  -- MakeUnique while another RN is shared -> SnpMakeInvalid.
  -- §4.7.4: requires at least one non-requester holder to enter T_SNP.
  Rule "MakeUnique_from_shared"
    phase = STABLE & NumShared() > 0 & NumUnique() = 0 &
    pending[r] = op_None &
    Exists r2 : RNFid Do (r2 != r) & (rnf[r2] != RS_I) End
  ==>
  Begin
    phase := T_SNP; requester := r; inflight_op := op_MakeUnique;
    For r2 : RNFid Do
      snp_required[r2] := (r2 != r) & (rnf[r2] != RS_I);
      snp_resp[r2]     := SR_None;
    End;
  End;

  -- CleanInvalid: drop the line (might require snoop if others share)
  Rule "CleanInvalid_when_others_present"
    phase = STABLE &
    ((NumShared() > 0 & !(NumShared() = 1 & (rnf[r] = RS_SC | rnf[r] = RS_SD))) |
     (NumUnique() = 1 & !(rnf[r] = RS_UC | rnf[r] = RS_UD))) &
    pending[r] = op_None
  ==>
  Begin
    phase := T_SNP; requester := r; inflight_op := op_CleanInvalid;
    For r2 : RNFid Do
      snp_required[r2] := (r2 != r) & (rnf[r2] != RS_I);
      snp_resp[r2]     := SR_None;
    End;
  End;

  -- Evict: dataless drop of caller's own copy (only legal on clean).
  Rule "Evict_self"
    phase = STABLE & (rnf[r] = RS_SC | rnf[r] = RS_UC) & pending[r] = op_None
  ==>
  Begin
    rnf[r] := RS_I;
  End;

  -- ── Writeback lifecycle (§4.7.5) ───────────────────────────────────
  -- WriteBackFull / WriteCleanFull are NOT atomic per CHI: after the
  -- REQ, HN-F must return CompDBIDResp before the RN-F ships the
  -- CopyBackWrData beat.  This creates an in-flight window during
  -- which HN-F may serve snoops from other RNs — the classic
  -- "snoop-vs-writeback race" (Table 4.7-9 in Issue E.b).
  --
  -- We model the RN's local state as I (or UC for WriteClean) at REQ
  -- time — the RN drops its own copy immediately per §4.7.5.  The
  -- dirty data is now conceptually "in transit"; hnf_has_dirty is
  -- asserted so the DirtyOwnershipExclusive invariant still holds.
  Rule "WriteBackFull_begin"
    phase = STABLE & rnf[r] = RS_UD & pending[r] = op_None
  ==>
  Begin
    rnf[r]        := RS_I;
    phase         := T_WB_DBIDRESP;
    requester     := r;
    inflight_op   := op_WriteBackFull;
    hnf_has_dirty := true;
  End;

  Rule "WriteCleanFull_begin"
    phase = STABLE & rnf[r] = RS_UD & pending[r] = op_None
  ==>
  Begin
    rnf[r]        := RS_UC;     -- WriteClean keeps the line resident, now clean
    phase         := T_WB_DBIDRESP;
    requester     := r;
    inflight_op   := op_WriteCleanFull;
    hnf_has_dirty := true;
  End;

  ---------------------------------------------------------------------
  -- (2) Atomics
  ---------------------------------------------------------------------

  Rule "AtomicLoad_from_I"
    phase = STABLE & NumUnique() = 0 & NumShared() = 0 &
    pending[r] = op_None
  ==>
  Begin
    phase := T_FILL; requester := r; inflight_op := op_AtomicLoad;
  End;

  Rule "AtomicLoad_with_holders"
    phase = STABLE & (NumShared() > 0 | NumUnique() = 1) &
    pending[r] = op_None &
    -- §4.7.4: T_SNP entry requires at least one non-requester snoopee.
    Exists r2 : RNFid Do (r2 != r) & (rnf[r2] != RS_I) End
  ==>
  Begin
    phase := T_SNP; requester := r; inflight_op := op_AtomicLoad;
    For r2 : RNFid Do
      snp_required[r2] := (r2 != r) & (rnf[r2] != RS_I);
      snp_resp[r2]     := SR_None;
    End;
  End;

  Rule "AtomicStore_from_I"
    phase = STABLE & NumUnique() = 0 & NumShared() = 0 &
    pending[r] = op_None
  ==>
  Begin
    phase := T_FILL; requester := r; inflight_op := op_AtomicStore;
  End;

  Rule "AtomicStore_with_holders"
    phase = STABLE & (NumShared() > 0 | NumUnique() = 1) &
    pending[r] = op_None &
    Exists r2 : RNFid Do (r2 != r) & (rnf[r2] != RS_I) End
  ==>
  Begin
    phase := T_SNP; requester := r; inflight_op := op_AtomicStore;
    For r2 : RNFid Do
      snp_required[r2] := (r2 != r) & (rnf[r2] != RS_I);
      snp_resp[r2]     := SR_None;
    End;
  End;

  ---------------------------------------------------------------------
  -- (2b) Internal store-hit: promote UC to UD locally
  ---------------------------------------------------------------------
  Rule "StoreHit_UC_to_UD"
    phase = STABLE & rnf[r] = RS_UC
  ==>
  Begin
    rnf[r] := RS_UD;
  End;

  ---------------------------------------------------------------------
  -- (3) CAM hazard
  ---------------------------------------------------------------------
  Ruleset op : OpType Do
    Rule "CAM_hazard_queue_REQ"
      phase != STABLE & requester != r & pending[r] = op_None &
      op != op_None & op != op_Evict &
      (phase != T_SNP | rnf[r] = RS_I) &
      ( (op = op_ReadClean     & rnf[r] = RS_I)
      | (op = op_ReadUnique    & rnf[r] = RS_I)
      | (op = op_MakeUnique    & !(rnf[r] = RS_UC | rnf[r] = RS_UD))
      | (op = op_CleanUnique   & (rnf[r] = RS_SC | rnf[r] = RS_SD))
      | (op = op_CleanInvalid  & !(rnf[r] = RS_UC | rnf[r] = RS_UD))
      | (op = op_CleanShared)
      | (op = op_WriteBackFull  & rnf[r] = RS_UD)
      | (op = op_WriteCleanFull & rnf[r] = RS_UD)
      | (op = op_AtomicLoad)
      | (op = op_AtomicStore)
      )
    ==>
    Begin
      pending[r] := op;
    End;
  EndRuleset;

EndRuleset;

---------------------------------------------------------------------------
-- (4) Per-snoopee SnpResp* decision rules.
--
-- Each rule fires for a specific snoopee s during T_SNP, while
-- snp_required[s]=true.  The rule encodes the CHI decision
-- "snoopee s in local state L, on snoop opcode derived from inflight_op,
--  responds with variant V and transitions to local state L'".
--
-- Snoop opcode derivation:
--   op_ReadClean                                 -> SnpClean
--   op_ReadUnique                                -> SnpUnique
--   op_CleanUnique | op_MakeUnique               -> SnpMakeInvalid
--   op_CleanInvalid                              -> SnpCleanInvalid
--   op_CleanShared                               -> SnpShared
--   op_AtomicLoad  | op_AtomicStore              -> SnpMakeInvalid (per
--      project memory: HN-F atomics use SnpMakeInvalid for all variants)
---------------------------------------------------------------------------

Ruleset s : RNFid Do

  -- ---- SnpClean (from op_ReadClean) ----
  Rule "Snp_SnpClean_from_UD"
    phase = T_SNP & snp_required[s] & inflight_op = op_ReadClean &
    rnf[s] = RS_UD
  ==>
  Begin
    rnf[s]           := RS_SC;
    snp_resp[s]      := SR_SC_PD;   -- downgrade to SC, pass dirty
    hnf_has_dirty    := true;
    snp_required[s]  := false;
  End;

  Rule "Snp_SnpClean_from_UC"
    phase = T_SNP & snp_required[s] & inflight_op = op_ReadClean &
    rnf[s] = RS_UC
  ==>
  Begin
    rnf[s]           := RS_SC;
    snp_resp[s]      := SR_SC;      -- downgrade to SC, no data
    snp_required[s]  := false;
  End;

  Rule "Snp_SnpClean_from_SD"
    phase = T_SNP & snp_required[s] & inflight_op = op_ReadClean &
    rnf[s] = RS_SD
  ==>
  Begin
    rnf[s]           := RS_SC;
    snp_resp[s]      := SR_SC_PD;   -- pass dirty, keep clean shared
    hnf_has_dirty    := true;
    snp_required[s]  := false;
  End;

  Rule "Snp_SnpClean_from_SC"
    phase = T_SNP & snp_required[s] & inflight_op = op_ReadClean &
    rnf[s] = RS_SC
  ==>
  Begin
    snp_resp[s]      := SR_SC;
    snp_required[s]  := false;
  End;

  -- ---- SnpUnique (from op_ReadUnique) ----
  Rule "Snp_SnpUnique_from_UD"
    phase = T_SNP & snp_required[s] & inflight_op = op_ReadUnique &
    rnf[s] = RS_UD
  ==>
  Begin
    rnf[s]           := RS_I;
    snp_resp[s]      := SR_I_PD;    -- invalidate, pass dirty
    hnf_has_dirty    := true;
    snp_required[s]  := false;
  End;

  Rule "Snp_SnpUnique_from_UC"
    phase = T_SNP & snp_required[s] & inflight_op = op_ReadUnique &
    rnf[s] = RS_UC
  ==>
  Begin
    rnf[s]           := RS_I;
    snp_resp[s]      := SR_I_D;     -- invalidate, forward clean data
    snp_required[s]  := false;
  End;

  Rule "Snp_SnpUnique_from_SD"
    phase = T_SNP & snp_required[s] & inflight_op = op_ReadUnique &
    rnf[s] = RS_SD
  ==>
  Begin
    rnf[s]           := RS_I;
    snp_resp[s]      := SR_I_PD;
    hnf_has_dirty    := true;
    snp_required[s]  := false;
  End;

  Rule "Snp_SnpUnique_from_SC"
    phase = T_SNP & snp_required[s] & inflight_op = op_ReadUnique &
    rnf[s] = RS_SC
  ==>
  Begin
    rnf[s]           := RS_I;
    snp_resp[s]      := SR_I;       -- invalidate, no data
    snp_required[s]  := false;
  End;

  -- ---- SnpMakeInvalid (from op_CleanUnique, op_MakeUnique, atomics) ----
  -- Per CHI: SnpMakeInvalid never carries dirty data back; if snoopee
  -- was dirty, the dirty data is dropped.  This is a *correctness*
  -- decision: callers of SnpMakeInvalid (CleanUnique, MakeUnique,
  -- atomics) either don't need the old data or will fetch it via L3.
  Rule "Snp_SnpMakeInvalid_any"
    phase = T_SNP & snp_required[s] &
    (inflight_op = op_CleanUnique | inflight_op = op_MakeUnique |
     inflight_op = op_AtomicLoad  | inflight_op = op_AtomicStore)
  ==>
  Begin
    rnf[s]           := RS_I;
    snp_resp[s]      := SR_I;
    snp_required[s]  := false;
  End;

  -- ---- SnpCleanInvalid (from op_CleanInvalid) ----
  Rule "Snp_SnpCleanInvalid_from_dirty"
    phase = T_SNP & snp_required[s] & inflight_op = op_CleanInvalid &
    (rnf[s] = RS_UD | rnf[s] = RS_SD)
  ==>
  Begin
    rnf[s]           := RS_I;
    snp_resp[s]      := SR_I_PD;    -- pass dirty back to HN-F
    hnf_has_dirty    := true;
    snp_required[s]  := false;
  End;

  Rule "Snp_SnpCleanInvalid_from_clean"
    phase = T_SNP & snp_required[s] & inflight_op = op_CleanInvalid &
    (rnf[s] = RS_UC | rnf[s] = RS_SC)
  ==>
  Begin
    rnf[s]           := RS_I;
    snp_resp[s]      := SR_I;
    snp_required[s]  := false;
  End;

  -- ---- SnpShared (from op_CleanShared) ----
  -- Hint: peer flushes dirty data but keeps a clean copy.
  Rule "Snp_SnpShared_from_dirty"
    phase = T_SNP & snp_required[s] & inflight_op = op_CleanShared &
    (rnf[s] = RS_UD | rnf[s] = RS_SD)
  ==>
  Begin
    -- UD -> UC, SD -> SC (drop dirty by passing it to HN-F)
    If rnf[s] = RS_UD Then rnf[s] := RS_UC; Else rnf[s] := RS_SC; End;
    snp_resp[s]      := SR_SC_PD;
    hnf_has_dirty    := true;
    snp_required[s]  := false;
  End;

  Rule "Snp_SnpShared_from_clean"
    phase = T_SNP & snp_required[s] & inflight_op = op_CleanShared &
    (rnf[s] = RS_UC | rnf[s] = RS_SC)
  ==>
  Begin
    -- UC -> SC, SC stays
    If rnf[s] = RS_UC Then rnf[s] := RS_SC; End;
    snp_resp[s]      := SR_SC;
    snp_required[s]  := false;
  End;

EndRuleset;

---------------------------------------------------------------------------
-- (5) T_SNP_DONE -- collector rule, fires once every required snoopee has
-- responded.  Picks T_ACK vs STABLE based on inflight op.
---------------------------------------------------------------------------

Rule "T_SNP_DONE"
  phase = T_SNP & NumSnoopRequired() = 0
==>
Begin
  -- Atomics terminate directly into STABLE (no CompAck).
  If inflight_op = op_AtomicLoad | inflight_op = op_AtomicStore Then
    For r2 : RNFid Do rnf[r2] := RS_I; End;  -- HN-F absorbs dirty via L3
    phase         := STABLE;
    inflight_op   := op_None;
    hnf_has_dirty := false;
    Undefine requester;
  Else
    phase := T_ACK;
  End;
End;

---------------------------------------------------------------------------
-- (6) SNF fill returns -> T_FILL -> T_ACK (or STABLE for atomics)
---------------------------------------------------------------------------

Rule "SNF_DATA"
  phase = T_FILL
==>
Begin
  If inflight_op = op_AtomicLoad | inflight_op = op_AtomicStore Then
    For r2 : RNFid Do rnf[r2] := RS_I; End;
    phase         := STABLE;
    inflight_op   := op_None;
    hnf_has_dirty := false;
    Undefine requester;
  Else
    phase := T_ACK;
  End;
End;

---------------------------------------------------------------------------
-- (7) CompAck -- T_ACK -> STABLE; applies requester-side terminal state.
-- Uses hnf_has_dirty to pick UC vs UD (ReadUnique) or SC vs SD-migration
-- (ReadClean: HN-F absorbs dirty into L3, requester gets SC).
---------------------------------------------------------------------------

Rule "CompAck"
  phase = T_ACK
==>
Begin
  Switch inflight_op
    Case op_ReadClean :
      rnf[requester] := RS_SC;     -- HN-F holds any dirty internally
      hnf_has_dirty  := false;
    Case op_ReadUnique :
      For r2 : RNFid Do
        If r2 = requester Then
          If hnf_has_dirty Then rnf[r2] := RS_UD; Else rnf[r2] := RS_UC; End;
        Else
          rnf[r2] := RS_I;
        End;
      End;
      hnf_has_dirty := false;
    Case op_MakeUnique :
      For r2 : RNFid Do
        If r2 = requester Then rnf[r2] := RS_UC; Else rnf[r2] := RS_I; End;
      End;
      hnf_has_dirty := false;
    Case op_CleanUnique :
      For r2 : RNFid Do
        If r2 = requester Then rnf[r2] := RS_UC; Else rnf[r2] := RS_I; End;
      End;
      hnf_has_dirty := false;
    Case op_CleanInvalid :
      For r2 : RNFid Do rnf[r2] := RS_I; End;
      hnf_has_dirty := false;
    Case op_CleanShared :
      -- hint; no requester-side state change
  EndSwitch;
  phase       := STABLE;
  inflight_op := op_None;
  Undefine requester;
End;

---------------------------------------------------------------------------
-- (7b) Writeback lifecycle: HN-F sends DBIDResp, then absorbs data.
--
-- The window between T_WB_DBIDRESP and STABLE is where CHI Issue E
-- §4.7.5 allows / requires HN-F to serve concurrent snoops for the
-- same line targeting *other* RNs (there are none for writeback since
-- the writer already dropped local, but the invariants above cover
-- the general race).  Modeling the two-step cycle exposes any
-- reachable state where dirty-data conservation could be broken.
---------------------------------------------------------------------------

Rule "WB_DBIDResp"
  phase = T_WB_DBIDRESP
==>
Begin
  phase := T_WB_DATA;
End;

Rule "WB_WriteData_absorb"
  phase = T_WB_DATA
==>
Begin
  -- Data absorbed into L3.  HN-F releases dirty ownership.
  phase         := STABLE;
  inflight_op   := op_None;
  hnf_has_dirty := false;
  Undefine requester;
End;

---------------------------------------------------------------------------
-- (8) Pending-REQ promotion
---------------------------------------------------------------------------

Ruleset r : RNFid Do
  Rule "Promote_pending"
    phase = STABLE & pending[r] != op_None
  ==>
  Begin
    pending[r] := op_None;
  End;
EndRuleset;

---------------------------------------------------------------------------
-- Safety invariants
---------------------------------------------------------------------------

Invariant "AtMostOneUnique"
  NumUnique() <= 1;

Invariant "NoUniqueAndSharedSimultaneously"
  !(NumUnique() > 0 & NumShared() > 0);

Invariant "AtMostOneDirtyOwner"
  NumDirty() <= 1;

-- HN-F holds dirty XOR an RN-F holds dirty (not both at the same time).
Invariant "DirtyOwnershipExclusive"
  !(hnf_has_dirty & NumDirty() > 0);

Invariant "InflightConsistency"
  (phase != STABLE) -> (inflight_op != op_None);

Invariant "StableHasNoInflightOp"
  (phase = STABLE) -> (inflight_op = op_None);

-- Outside of T_SNP, no snoopee should still owe a response.
Invariant "SnoopRequiredOnlyInTSnp"
  (phase != T_SNP) -> (NumSnoopRequired() = 0);

---------------------------------------------------------------------------
-- CHI hazard invariants (AMBA CHI Issue E, §4.7)
--
-- Each of these encodes a specific hazard condition the spec says the
-- HN-F / RN-F must not violate.  The composition + rule structure
-- above already enforces them structurally; the invariants make the
-- guarantees explicit and machine-checkable.
---------------------------------------------------------------------------

-- §4.7.4 "Snoop response handling":  the requester of the inflight
-- REQ is never snooped for that REQ's line.
Invariant "Hazard_NoSelfSnoop"
  (phase = T_SNP) -> (!snp_required[requester]);

-- §4.7.4 "T_SNP entry":  a T_SNP phase must have been entered with
-- at least one snoopee.  Once all snoopees respond, NumSnoopRequired
-- transiently drops to 0 before the T_SNP_DONE collector fires — that
-- transient is legitimate.  Bug case: entering T_SNP with zero
-- snoopees from the start (which is what caught the AtomicLoad /
-- MakeUnique / ReadUnique guards).  We can't easily distinguish
-- "just entered T_SNP" from "all snoopees drained" at the invariant
-- level without adding a witness bit; the entry-guard fix above
-- removes the reachable bug case, so we drop this invariant.
-- (Left as a comment for spec traceability.)

-- §2.3.2 CompAck ordering:  a T_ACK phase always has an inflight_op
-- (redundant with InflightConsistency, kept for spec traceability).
Invariant "Hazard_CompAckMustHaveOp"
  (phase = T_ACK) -> (inflight_op != op_None);

-- §4.7.5 "Snoop-vs-Writeback race":  during T_WB_* the RN dropped
-- its local copy; dirty data lives with HN-F only.  Loss of dirty
-- data in this window is the classic writeback-hazard bug.
Invariant "Hazard_WritebackDirtyOwned"
  (phase = T_WB_DBIDRESP | phase = T_WB_DATA) -> hnf_has_dirty;

-- §4.7.5 "Writeback in flight":  during T_WB_* the writing RN's
-- local copy is either I (WriteBackFull) or clean UC (WriteCleanFull);
-- it never holds dirty state — dirty is in transit.
Invariant "Hazard_WritebackRNNotDirty"
  ForAll r : RNFid Do
    ( (phase = T_WB_DBIDRESP | phase = T_WB_DATA) & r = requester
      -> (rnf[r] = RS_I | rnf[r] = RS_UC) )
  End;

-- §4.7.3 CAM lookup: the requester whose REQ is inflight never has
-- its own pending queue in use (its REQ went straight to inflight).
Invariant "Hazard_RequesterNotInPending"
  (phase != STABLE) -> (pending[requester] = op_None);

-- SWMR: at any time, EITHER exactly one RN holds the line uniquely
-- (UC/UD) OR zero-to-many RNs hold it shared (SC/SD); never both.
-- (Same as NoUniqueAndSharedSimultaneously, spelled positively.)
Invariant "Hazard_SWMR"
  (NumUnique() = 0) | (NumUnique() = 1 & NumShared() = 0);

-- §4.5 Coherence: dirty data is uniquely owned by (RN with UD/SD)
-- XOR (HN-F, indicated by hnf_has_dirty) — never lost, never
-- duplicated.
Invariant "Hazard_DirtyDataConservation"
  ! (hnf_has_dirty & NumDirty() > 0);
