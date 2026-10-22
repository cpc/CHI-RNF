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
-- hnf_fsm.m
--
-- HN-F coherence FSM (single cache line) modelled in Murphi.
--
-- This is the same abstract model expressed in ../hnf_fsm.yaml, rewritten
-- to exploit RN-F symmetry via ScalarSet and to express the CAM-hazard
-- pending-REQ machinery as Array state instead of Cartesian-expanded
-- composite states.
--
-- Equivalent YAML size: 154 explicit states, 515 edges.
-- Equivalent Murphi size: ~10 state variables, ~25 rules.
--
-- What this model checks:
--   * Reachable-state enumeration   -- every legal coherence config visited
--   * Safety invariants             -- no double-Unique, no Unique+Shared mix
--   * Deadlock detection            -- no reachable state has zero rules firing
--                                     (unless legitimately terminal)
--   * Liveness (optional)           -- every pending REQ eventually serviced
--
-- Run:
--   mu -m500 hnf_fsm.m              # generate C++ verifier
--   g++ -O2 -o hnf_fsm hnf_fsm.cpp -I/path/to/murphi/include
--   ./hnf_fsm
---------------------------------------------------------------------------

Const
  NUM_RNF : 2;    -- two requester nodes (matches the TLM testbench)

---------------------------------------------------------------------------
-- Types
---------------------------------------------------------------------------

Type
  -- ScalarSet enables automatic symmetry reduction: any permutation of
  -- RN-F identities produces an equivalent state, so Murphi quotients
  -- the reachable state space accordingly.
  RNFid : ScalarSet(NUM_RNF);

  -- Per-RN-F local coherence state (mirrors the HNF snoop filter encoding
  -- in hnf_defines.v:85-87: SF_I=0, SF_U=1, SF_S=3).
  RnfLocal : Enum{
    RS_I,   -- this RN-F does not cache the line
    RS_U,   -- this RN-F holds the line uniquely
    RS_S    -- this RN-F holds the line shared
  };

  -- HNF MSHR transient phase for the in-flight transaction.
  -- STABLE means no transaction in progress (line state is whatever the
  -- per-RNF rnf[] array says).
  HnfPhase : Enum{
    STABLE,
    T_FILL, -- awaiting SNF fill / DMT return
    T_SNP,  -- awaiting SnpResp from peer
    T_ACK   -- awaiting CompAck from the requester
  };

  -- CHI REQ opcodes the model exercises. op_None means "no op" (used as
  -- a sentinel for empty pending slots and the idle inflight slot).
  --
  -- Address-space partition (2026-06-08): this FSM models only the
  -- COHERENT address subspace. Non-coherent ops (ReadNoSnp,
  -- WriteNoSnpFull, WriteNoSnpPtl, ReadOnce) live on a separate
  -- non-coherent address range and bypass the snoop filter / MSHR
  -- entirely. They have their own (much simpler) test flow; see
  -- testgen/gen_noncoherent.py. Mixing the two on a single line is
  -- forbidden by CHI E.b sec 2.4.2 and gives undefined semantics.
  -- Atomics (2026-06-12): two abstract opcodes capture the only two
  -- protocol-distinct shapes among the 18 CHI atomic variants:
  --   op_AtomicLoad  := { AtomicLoad.{ADD,CLR,EOR,SET,SMAX,SMIN,UMAX,UMIN},
  --                       AtomicSwap, AtomicCompare }  -- returns old value
  --   op_AtomicStore := { AtomicStore.{ADD,CLR,EOR,SET,SMAX,SMIN,UMAX,UMIN} }
  --                                                    -- no data returned
  -- The operand, compare value, and ALU selector are immaterial at the
  -- abstract protocol level; the FSM only tracks coherence transitions.
  -- Common shape: invalidate all peer copies, HNF performs the RMW,
  -- requester does NOT cache the line, no CompAck (no T_ACK phase).
  OpType : Enum{
    op_None,
    op_ReadClean, op_ReadUnique, op_MakeUnique,
    op_CleanShared, op_CleanUnique, op_CleanInvalid,
    op_Evict,
    op_WriteBackFull, op_WriteCleanFull,
    op_AtomicLoad, op_AtomicStore
  };

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------

Var
  -- Per-RN-F local coherence state (snoop-filter view).
  rnf : Array [RNFid] of RnfLocal;

  -- Dirty bit for the line (relevant only when one RN-F holds RS_U;
  -- distinguishes UC vs UD).
  dirty : Boolean;

  -- HNF MSHR transient phase. STABLE iff no transaction in flight.
  phase : HnfPhase;

  -- Requester of the in-flight transaction (valid when phase != STABLE).
  requester : RNFid;

  -- Op the in-flight transaction is executing (valid when phase != STABLE).
  inflight_op : OpType;

  -- Per-RN-F pending REQ slot. Each RN-F can have at most one queued
  -- REQ at a time. op_None == slot empty.
  -- This single Array replaces 140 hand-enumerated composite states
  -- (T_<phase>_<rnf>__PEND_<peer>_<op>) in the YAML version.
  pending : Array [RNFid] of OpType;

---------------------------------------------------------------------------
-- Helper functions
---------------------------------------------------------------------------

-- CMurphi 5.4.9 silently fails to emit C++ when one function calls
-- another. All helpers are inlined directly (one level of function
-- depth max). Counters use local n vars; no nested calls.
-- Also: no backticks in comments (parser chokes on them).

Function NumUnique() : 0..NUM_RNF;
Var n : 0..NUM_RNF;
Begin
  n := 0;
  For r : RNFid Do
    If rnf[r] = RS_U Then n := n + 1; End;
  End;
  Return n;
End;

Function NumShared() : 0..NUM_RNF;
Var n : 0..NUM_RNF;
Begin
  n := 0;
  For r : RNFid Do
    If rnf[r] = RS_S Then n := n + 1; End;
  End;
  Return n;
End;

---------------------------------------------------------------------------
-- Initial state
---------------------------------------------------------------------------

Startstate "init"
Begin
  For r : RNFid Do rnf[r] := RS_I; End;
  dirty       := false;
  phase       := STABLE;
  inflight_op := op_None;
  For r : RNFid Do pending[r] := op_None; End;
  Undefine requester;
End;

---------------------------------------------------------------------------
-- Rules
---------------------------------------------------------------------------
-- All rules are parameterised by the issuing RN-F via Ruleset. ScalarSet
-- symmetry means we author each rule once and Murphi covers both
-- (A-issues, B-acts as peer) and (B-issues, A-acts as peer) automatically.
---------------------------------------------------------------------------

Ruleset r : RNFid Do

  ---------------------------------------------------------------------
  -- (1) Stable-line REQs from RN-F r
  ---------------------------------------------------------------------

  -- ReadClean / ReadUnique on an invalid line -> SNF fetch
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

  -- MakeUnique: skips SNF fetch, goes directly to T_ACK
  Rule "MakeUnique_from_I"
    phase = STABLE & NumUnique() = 0 & NumShared() = 0 & pending[r] = op_None
  ==>
  Begin
    phase := T_ACK; requester := r; inflight_op := op_MakeUnique;
  End;

  -- ReadClean from SC by a non-sharer -> snoop existing sharer(s)
  Rule "ReadClean_from_SC_nonsharer"
    phase = STABLE & rnf[r] = RS_I & NumShared() > 0 &
    NumUnique() = 0 & pending[r] = op_None
  ==>
  Begin
    phase := T_SNP; requester := r; inflight_op := op_ReadClean;
  End;

  -- ReadClean by a non-holder while another RN-F holds UC/UD -> SnpClean
  Rule "ReadClean_from_UC_other"
    phase = STABLE & rnf[r] = RS_I & NumUnique() = 1 & rnf[r] != RS_U &
    pending[r] = op_None
  ==>
  Begin
    phase := T_SNP; requester := r; inflight_op := op_ReadClean;
  End;

  -- ReadUnique while another RN-F holds the line -> SnpUnique
  Rule "ReadUnique_from_other_holder"
    phase = STABLE &
    (NumShared() > 0 | NumUnique() = 1) &
    rnf[r] != RS_U & pending[r] = op_None
  ==>
  Begin
    phase := T_SNP; requester := r; inflight_op := op_ReadUnique;
  End;

  -- CleanUnique by sole sharer in SC -> upgrade, no snoop
  Rule "CleanUnique_sole_sharer"
    phase = STABLE & rnf[r] = RS_S & NumShared() = 1 &
    pending[r] = op_None
  ==>
  Begin
    phase := T_ACK; requester := r; inflight_op := op_CleanUnique;
  End;

  -- CleanUnique with other sharers -> must snoop them out
  Rule "CleanUnique_with_others"
    phase = STABLE & rnf[r] = RS_S & NumShared() > 1 &
    pending[r] = op_None
  ==>
  Begin
    phase := T_SNP; requester := r; inflight_op := op_CleanUnique;
  End;

  -- MakeUnique while line is shared (r might not be a sharer) -> SnpMakeInvalid
  Rule "MakeUnique_from_shared"
    phase = STABLE & NumShared() > 0 & NumUnique() = 0 &
    pending[r] = op_None
  ==>
  Begin
    phase := T_SNP; requester := r; inflight_op := op_MakeUnique;
  End;

  -- CleanInvalid: drop the line (might require snoop if others share)
  Rule "CleanInvalid_when_others_present"
    phase = STABLE &
    ((NumShared() > 0 & !(NumShared() = 1 & rnf[r] = RS_S)) |
     (NumUnique() = 1 & rnf[r] != RS_U)) &
    pending[r] = op_None
  ==>
  Begin
    phase := T_SNP; requester := r; inflight_op := op_CleanInvalid;
  End;

  -- Evict: dataless drop of caller's own copy, no snoops.
  -- CHI: Evict is only legal on CLEAN lines (UC, SC). A dirty holder
  -- must use WriteBackFull. The !dirty guard enforces that.
  Rule "Evict_self"
    phase = STABLE & (rnf[r] = RS_S | rnf[r] = RS_U) &
    !dirty & pending[r] = op_None
  ==>
  Begin
    rnf[r] := RS_I;
  End;

  -- WriteBackFull / WriteCleanFull / WriteEvictFull: holder writes back
  -- (modelled as a no-snoop transient; bypass path in real HNF)
  Rule "WriteBackFull"
    phase = STABLE & rnf[r] = RS_U & dirty & pending[r] = op_None
  ==>
  Begin
    rnf[r] := RS_I;
    dirty  := false;
  End;

  Rule "WriteCleanFull"
    phase = STABLE & rnf[r] = RS_U & dirty & pending[r] = op_None
  ==>
  Begin
    -- Data written back, holder downgrades from UD to UC
    dirty := false;
  End;

  ---------------------------------------------------------------------
  -- (1b) Atomics
  --
  -- Issuable from any local cache state (I, S, U); HNF performs the RMW.
  -- From I with no peer holders: line miss in HNF L3, fetch via T_FILL.
  -- From any state with peer holders: snoop-invalidate first via T_SNP.
  -- The "no holders + line resident in HNF L3" case also routes through
  -- T_FILL as an abstraction (the model doesn't distinguish L3 hit/miss
  -- for non-cached lines).
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
    pending[r] = op_None
  ==>
  Begin
    phase := T_SNP; requester := r; inflight_op := op_AtomicLoad;
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
    pending[r] = op_None
  ==>
  Begin
    phase := T_SNP; requester := r; inflight_op := op_AtomicStore;
  End;

  ---------------------------------------------------------------------
  -- (2) Internal "store hit" event -- promotes UC to UD locally
  ---------------------------------------------------------------------
  Rule "StoreHit_UC_to_UD"
    phase = STABLE & rnf[r] = RS_U & !dirty
  ==>
  Begin
    dirty := true;
  End;

  ---------------------------------------------------------------------
  -- (3) CAM hazard: REQ from r while another RN-F's transaction is
  -- in-flight. The REQ is queued in pending[r] for later service.
  -- This single rule replaces 60 hand-written __HAZARD edges in YAML.
  ---------------------------------------------------------------------
  -- CHI E.b conformance: an RN-F may only issue REQs that its current
  -- cache state legally permits. Earlier guard allowed e.g.
  -- WriteBackFull from an I-holder (protocol violation per CHI E.b
  -- sec 2.4.1). Per-op preconditions added below.
  --
  -- Additionally: during T_SNP, only an RN-F currently in RS_I may
  -- queue. The driver (chi_tlm_rnf.cpp) eagerly invalidates the
  -- snoopee on snoop receipt (before SnpResp is transmitted), so any
  -- queued REQ from the snoopee that requires its pre-snoop state
  -- (S/U/UD) can never be issued in practice. This abstraction lives
  -- in both model and driver; see project-chi-eb-conformance memory.
  Ruleset op : OpType Do
    Rule "CAM_hazard_queue_REQ"
      phase != STABLE & requester != r & pending[r] = op_None &
      op != op_None & op != op_Evict &
      (phase != T_SNP | rnf[r] = RS_I) &
      -- Non-coherent ops (ReadNoSnp, WriteNoSnpFull) intentionally
      -- excluded from CAM hazard queueing: they bypass the snoop
      -- filter and have undefined semantics when raced against
      -- coherently-shared cache lines (CHI E.b sec 2.4.2). Their
      -- proper test coverage belongs in a non-coherent address
      -- subspace, not interleaved with coherent transactions.
      ( (op = op_ReadClean     & rnf[r] = RS_I)
      | (op = op_ReadUnique    & rnf[r] = RS_I)
      | (op = op_MakeUnique    & rnf[r] != RS_U)
      | (op = op_CleanUnique   & rnf[r] = RS_S)
      | (op = op_CleanInvalid  & rnf[r] != RS_U)
      | (op = op_CleanShared)
      | (op = op_WriteBackFull  & rnf[r] = RS_U & dirty)
      | (op = op_WriteCleanFull & rnf[r] = RS_U & dirty)
      -- Atomics are state-agnostic at the requester: HNF performs the
      -- RMW regardless of whether the requester holds the line.  But
      -- during T_SNP we still gate to RS_I (consistent with the
      -- requester != r & T_SNP guard above; covered by the outer guard).
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
-- (4) Transient -> resolution rules (not parameterised by issuing RN-F;
-- they fire on the in-flight requester whose identity is in requester).
---------------------------------------------------------------------------

-- SNF fill returns data -> T_FILL -> {T_ACK | STABLE for atomics}
Rule "SNF_DATA"
  phase = T_FILL
==>
Begin
  If inflight_op = op_AtomicLoad | inflight_op = op_AtomicStore Then
    -- Atomic: HNF applies RMW to the just-fetched line, responds with
    -- Comp/CompData (no CompAck expected).  No RN-F caches the result.
    -- HNF L3 absorbs the modified value internally -- represented as
    -- "no per-RNF dirty" at the directory level.
    For r2 : RNFid Do rnf[r2] := RS_I; End;
    dirty       := false;
    phase       := STABLE;
    inflight_op := op_None;
    Undefine requester;
  Else
    phase := T_ACK;
  End;
End;

-- Snoop resolves -> T_SNP -> T_ACK
-- (We collapse snoop response variants into one "snoop completes"
-- rule. The resulting line state depends on op + previous holders.)
Rule "SNP_RESP"
  phase = T_SNP
==>
Begin
  -- Apply snoop effect to other RN-Fs based on inflight_op
  Switch inflight_op
    Case op_ReadClean :
      -- SnpClean: peers in U/S downgrade to S; dirty data forwarded
      -- (so directory clears dirty bit).
      For r2 : RNFid Do
        If r2 != requester & rnf[r2] != RS_I Then
          rnf[r2] := RS_S;
        End;
      End;
      dirty := false;
    Case op_ReadUnique :
      -- SnpUnique: peers invalidated; data forwarded to requester
      For r2 : RNFid Do
        If r2 != requester Then rnf[r2] := RS_I; End;
      End;
      -- Dirty bit stays: requester will become UC or UD based on whether
      -- the snooped peer was dirty. Conservative: clear dirty at the
      -- directory; requester's local cache holds dirty if applicable.
      dirty := false;
    Case op_CleanUnique, op_MakeUnique :
      -- SnpMakeInvalid: peers invalidated, no data forwarded
      For r2 : RNFid Do
        If r2 != requester Then rnf[r2] := RS_I; End;
      End;
      dirty := false;
    Case op_CleanInvalid :
      For r2 : RNFid Do
        If r2 != requester Then rnf[r2] := RS_I; End;
      End;
      dirty := false;
    Case op_CleanShared :
      -- Hint: peers flush dirty data, line stays shared
      dirty := false;
    Case op_AtomicLoad, op_AtomicStore :
      -- Snoop invalidated all peers; HNF will RMW the line and respond.
      For r2 : RNFid Do rnf[r2] := RS_I; End;
      dirty := false;
  EndSwitch;
  -- Atomics need no CompAck: terminate directly into STABLE.
  If inflight_op = op_AtomicLoad | inflight_op = op_AtomicStore Then
    phase       := STABLE;
    inflight_op := op_None;
    Undefine requester;
  Else
    phase := T_ACK;
  End;
End;

-- CompAck retires the MSHR -> STABLE
Rule "CompAck"
  phase = T_ACK
==>
Begin
  -- Apply terminal state based on the in-flight op
  Switch inflight_op
    Case op_ReadClean :
      rnf[requester] := RS_S;
      -- existing sharers (if any) stay; if requester was sole holder
      -- before, they go to S now (was I -> S)
    Case op_ReadUnique, op_MakeUnique :
      For r2 : RNFid Do
        If r2 = requester Then rnf[r2] := RS_U; Else rnf[r2] := RS_I; End;
      End;
      dirty := (inflight_op = op_MakeUnique);   -- MakeUnique -> UCE (clean)
    Case op_CleanUnique :
      For r2 : RNFid Do
        If r2 = requester Then rnf[r2] := RS_U; Else rnf[r2] := RS_I; End;
      End;
      dirty := false;
    Case op_CleanInvalid :
      For r2 : RNFid Do rnf[r2] := RS_I; End;
      dirty := false;
    Case op_CleanShared :
      dirty := dirty;   -- no-op; CleanShared is a hint, no state change
  EndSwitch;
  phase := STABLE;
  inflight_op := op_None;
  Undefine requester;
End;

---------------------------------------------------------------------------
-- (5) Pending-REQ promotion: when STABLE and some RN-F has a pending REQ,
-- start servicing it. Murphi non-deterministically picks which pending
-- REQ to promote first.
---------------------------------------------------------------------------

Ruleset r : RNFid Do
  Rule "Promote_pending"
    phase = STABLE & pending[r] != op_None
  ==>
  Begin
    -- Re-issue the queued REQ. Murphi will re-fire the matching
    -- stable-state rule from above on the next step.
    -- We just clear the pending slot -- the REQ rule itself will fire
    -- in the next step because its guard pending[r] = op_None is now true.
    pending[r] := op_None;
    -- Note: we don't directly transition into T_FILL/T_SNP/T_ACK here;
    -- Murphi's rule-firing engine will pick whichever stable-state REQ
    -- rule matches r's intent next. (In a fully-faithful model we'd
    -- carry the queued op as inflight_op_next and dispatch
    -- explicitly -- left as a refinement.)
  End;
EndRuleset;

---------------------------------------------------------------------------
-- Safety invariants
---------------------------------------------------------------------------

Invariant "AtMostOneUnique"
  NumUnique() <= 1;

Invariant "NoUniqueAndSharedSimultaneously"
  !(NumUnique() > 0 & NumShared() > 0);

Invariant "DirtyOnlyWhenUnique"
  dirty -> NumUnique() = 1;

Invariant "InflightConsistency"
  (phase != STABLE) -> (inflight_op != op_None);

Invariant "StableHasNoInflightOp"
  (phase = STABLE) -> (inflight_op = op_None);

---------------------------------------------------------------------------
-- (Optional) Liveness -- every pending REQ is eventually served.
-- Murphi proper supports this via the -fairness flag. Uncomment to enable.
---------------------------------------------------------------------------
-- LivenessProperty "PendingEventuallyDrained"
--   AlwaysEventually !HasAnyPending();
