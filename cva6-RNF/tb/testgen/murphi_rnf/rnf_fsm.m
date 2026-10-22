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
-- rnf_fsm.m
--
-- CHI-E RN-F coherence FSM modelled in Murphi.
--
-- This is the dual of tb/testgen/murphi/hnf_fsm_v2.m: the DUT is the
-- single RN-F (CVA6 + L1.5 + rnf_link) and the counterparty (HN-F +
-- remote RN-Fs combined) is modelled as a non-deterministic CHI-legal
-- environment.  In the production verification flow the env is
-- replaced by gem5's SLICC CHI model via the co-sim TB; Murphi's role
-- is to enumerate every RN-F-side state and decision so the vector
-- replay covers the protocol surface.
--
-- Scope (initial):
--   * 1 RN-F (the DUT)
--   * 1 cache line
--   * 1 outstanding TX REQ at a time (MSHR depth = 1)
--   * 1 pending RX snoop at a time
--   * 1 software op queue slot
--
-- What this model checks:
--   * RN-F L1 state always in {I, SC, UC, SD, UD}
--   * Every outstanding TX REQ eventually retires (TX_IDLE again)
--   * Every received snoop eventually generates a SnpResp
--   * CompAck only after a Comp* response that requires it (ExpCompAck=1)
--   * Snoop-response variant matches the (snoop opcode x local state)
--     decision table from CHI-E spec
--
-- Run:
--   rumur rnf_fsm.m --output rnf_fsm.c
--   cc -std=c11 -march=native -mcx16 -O3 -o rnf_fsm rnf_fsm.c -lpthread
--   ./rnf_fsm
---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- Types
---------------------------------------------------------------------------

Type
  -- L1 cache state for the line on this RN-F.  Full CHI-E encoding.
  L1State : Enum{
    L1_I,    -- Invalid
    L1_SC,   -- Shared Clean
    L1_UC,   -- Unique Clean
    L1_SD,   -- Shared Dirty   (this RN-F is the dirty-owner among sharers)
    L1_UD    -- Unique Dirty
  };

  -- CHI REQ opcodes the RN-F can issue (coherent + atomic + non-cacheable).
  TxOp : Enum{
    tx_None,
    tx_ReadClean,     tx_ReadUnique,
    tx_MakeUnique,
    tx_CleanInvalid,
    tx_CleanShared,
    tx_WriteBackFull,
    tx_AtomicLoad,    tx_AtomicStore,
    -- Non-cacheable / non-coherent traffic.  These bypass the L1
    -- entirely (no fill, no state change) but still occupy the TX
    -- MSHR slot on the wire.  ReadNoSnp is emitted by NC-IFILL,
    -- WriteNoSnpPtl by the writethrough path.
    tx_ReadNoSnp,     tx_WriteNoSnpPtl
  };

  -- TX lifecycle.  Each outstanding REQ walks one of these paths:
  --   Read clean : TX_IDLE -> TX_AWAIT_RSP --(CompData)--> TX_AWAIT_COMPACK_CLEAN -> TX_IDLE
  --   Read dirty : TX_IDLE -> TX_AWAIT_RSP --(CompData_PD)--> TX_AWAIT_COMPACK_DIRTY -> TX_IDLE
  --   Write/Atom : TX_IDLE -> TX_AWAIT_RSP --(DBIDResp)--> TX_AWAIT_DATA_SEND
  --                                          --(Comp)--> TX_AWAIT_COMP -> TX_IDLE
  --   Dataless   : TX_IDLE -> TX_AWAIT_RSP --(Comp)--> TX_AWAIT_COMPACK_CLEAN -> TX_IDLE
  --                            (CleanUnique, MakeUnique, etc.)
  --   Evict      : TX_IDLE -> TX_AWAIT_RSP --(Comp)--> TX_IDLE  (no CompAck)
  --
  -- The CLEAN vs DIRTY phase split encodes what used to be a separate
  -- tx_data_dirty Boolean.  Splitting structurally eliminates the bit
  -- leaking past TX_AWAIT_COMPACK into unrelated states and shrinks
  -- the reachable space significantly.
  TxPhase : Enum{
    TX_IDLE,
    TX_AWAIT_RSP,            -- REQ on wire, awaiting first response flit
    TX_AWAIT_DATA_SEND,      -- DBIDResp received, owe write-data beats
    TX_AWAIT_COMP,           -- data sent, awaiting Comp
    TX_AWAIT_COMPACK_CLEAN,  -- CompData/Comp received with clean data
    TX_AWAIT_COMPACK_DIRTY   -- CompData received with dirty (PD) data
  };

  -- Snoop opcodes the environment can issue.
  RxSnp : Enum{
    rx_None,
    rx_SnpClean,
    rx_SnpUnique,
    rx_SnpMakeInvalid,
    rx_SnpCleanInvalid,
    rx_SnpShared
  };

  -- Software op queue.  The driver (CVA6 in real life) requests a
  -- specific REQ; the RN-F dispatches it when L1 state + outstanding
  -- TX slot allow.  Modelled as a single-slot queue.
  SwSlot : Enum{
    sw_None,
    sw_ReadClean,    sw_ReadUnique,
    sw_MakeUnique,
    sw_CleanInvalid,
    sw_CleanShared,
    sw_CBO_Zero,      -- cbo.zero: block-init STORE, not a read
    sw_AtomicLoad,    sw_AtomicStore,
    -- Non-cacheable data-path ops (IFILL-NC / writethrough).  Fire from
    -- any L1 state, do not modify L1 state, bypass coherence.
    sw_NC_Load,      sw_NC_Store,
    -- Reservation-based RISC-V atomics.  LR sets the RN-F's reservation
    -- flag; SC commits the store iff the reservation is still valid
    -- (broken by any snoop / coherence event on the line).
    sw_LR,           sw_SC,
    -- Set-conflict eviction pressure: models N loads to distinct lines
    -- mapping to the SAME cache set as the target.  In the real
    -- L1.5 (128 sets, 4-way LRU), N=WAY_COUNT distinct-tag hits force
    -- the target's way out of the set.  Modelled here as an atomic
    -- displacement of the target line:
    --   * UD  → CHI WriteBackFull → I  (dirty writeback)
    --   * SD  → silent drop → I         (SD is not a legal WriteBackFull
    --                                    source per CHI E.b §4.2.2;
    --                                    real RN-F silently drops)
    --   * UC/SC → silent drop → I       (clean silent eviction)
    --   * I   → no-op (drain)
    sw_SetConflict
  };

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------

Var
  l1             : L1State;
  tx_op          : TxOp;
  tx_phase       : TxPhase;
  tx_expcompack  : Boolean;

  rx_snp         : RxSnp;
  rx_resp_owed   : Boolean;
  -- RetToSrc on the pending snoop.  The snoopee returns data on a
  -- CLEAN line only when this is set, which is what distinguishes
  -- SnpRespData_I / _SC (SR_*_D) from the dataless SnpResp_* forms.
  -- Without this coordinate BFS cannot aim at those 24 x_decision
  -- cells; they were reachable only by luck.
  rx_rettosrc    : Boolean;

  sw_queue       : SwSlot;

  -- LR reservation flag.  Set by sw_LR (Issue_LR_hit / on LR fill);
  -- cleared by any snoop, any hart store to the line, or SC completion.
  lr_valid       : Boolean;

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

Function IsUnique(s : L1State) : Boolean;
Begin
  Return s = L1_UC | s = L1_UD;
End;

Function IsShared(s : L1State) : Boolean;
Begin
  Return s = L1_SC | s = L1_SD;
End;

Function IsDirty(s : L1State) : Boolean;
Begin
  Return s = L1_UD | s = L1_SD;
End;

---------------------------------------------------------------------------
-- Initial state
---------------------------------------------------------------------------

Startstate "init"
Begin
  l1            := L1_I;
  tx_op         := tx_None;
  tx_phase      := TX_IDLE;
  tx_expcompack := false;
  rx_snp        := rx_None;
  rx_resp_owed  := false;
  rx_rettosrc   := false;
  sw_queue      := sw_None;
  lr_valid      := false;
End;

---------------------------------------------------------------------------
-- (1) Software-driven request injection
--
-- Software (CVA6) enqueues a memory op; one slot, fires only when
-- empty.  The model can pick any sw_* opcode at any time -- this is
-- the workload-side non-determinism.
---------------------------------------------------------------------------

-- Event-alphabet restriction.  The full SwSlot enum is kept (every
-- downstream Issue_/SW_drain_ rule still references its members) and
-- SW_enqueue admits the members selected below.
--
-- Atomics / LR / SC / the non-cacheable path were previously excluded
-- because "their failures swamp the coherence protocol we are actually
-- measuring".  That was true against a TB that wedged on illegal
-- CopyBack write completions and whose MEM_ORACLE could not tell a lost
-- store from a refill; with those fixed the prefix-shared sweep runs
-- 147/147 clean, so the swamping rationale no longer holds.  They are
-- re-admitted here because cg_req_issuance sits at 11/71 bins
-- (cp_req_opcode 23.07%) purely for want of stimulus: ReadNoSnp,
-- WriteNoSnpPtl and the AtomicLoad/AtomicSwap opcodes have no other
-- source in this model.
--
-- Still deliberately excluded (do NOT flip without new evidence):
--   sw_MakeUnique, sw_CBO_Zero -- exact duplicates of sw_ReadUnique on
--     this RTL (see the note below); they triple the event count for
--     one behaviour.
--   sw_AtomicStore -- no RTL path emits a CHI AtomicStore opcode; the
--     L1.5 turns every AMO into AtomicLoad/AtomicSwap.  Dropped in
--     1f20be1 for exactly this reason.
--   (sw_SetConflict was in this list; enabled 2026-08-13 -- it is the
--     only source of eviction-driven WriteBackFull, so excluding it left
--     both generators blind to the replacement path.)
Function SwOpEnabled(op : SwSlot) : Boolean;
Begin
  Switch op
    Case sw_ReadClean:    Return true;
    Case sw_ReadUnique:   Return true;
    -- sw_MakeUnique and sw_CBO_Zero are DISABLED as exact duplicates:
    -- the TB dispatches all three of ReadUnique / MakeUnique / CBO_Zero
    -- to a PCX_REQTYPE_STORE, and the L1.5 emits ReadUnique (0x07) for
    -- every one of them (CHIE_MAKEUNIQUE is unemittable; do_cbo_zero
    -- carries no ASI tag or sideband bit).  Verified with +CMO_PROBE:
    -- cbo.zero and store on cold lines both produce TXREQ 0x07.  Keeping
    -- them tripled the events reaching one behaviour and inflated the
    -- vector count without adding protocol surface.
    Case sw_MakeUnique:   Return false;
    Case sw_CleanInvalid: Return true;
    Case sw_CleanShared:  Return true;
    Case sw_CBO_Zero:     Return false;
    -- Re-admitted: the only stimulus source for AtomicLoad/AtomicSwap
    -- (0x30-0x38), ReadNoSnp (0x04) and WriteNoSnpPtl (0x1c).
    Case sw_AtomicLoad:   Return true;
    Case sw_NC_Load:      Return true;
    Case sw_NC_Store:     Return true;
    Case sw_LR:           Return true;
    Case sw_SC:           Return true;
    -- Capacity-eviction pressure: N loads to distinct lines mapping to
    -- the target's cache set.  The ONLY source of eviction-driven
    -- WriteBackFull in either generator -- without it the directed set
    -- and the constrained-random baseline share a blind spot on the
    -- entire replacement path, which would go unstated in a comparison
    -- of the two.
    Case sw_SetConflict:  Return true;
    Else                  Return false;   -- sw_AtomicStore
  EndSwitch;
End;

-- RetToSrc injection switch.  Guards the 20 Env_Snp_*_RTS_from_*
-- rules (the only ones whose guard names an L1 state).  With this
-- false the snoop alphabet keeps its five opcodes but always carries
-- RetToSrc=0, so the SR_*_D clean-data-return responses drop out of
-- the reachable set.  Flip to true to restore them.
Function RtsEnabled() : Boolean;
Begin
  Return false;
End;

Ruleset op : SwSlot Do
  Rule "SW_enqueue"
    sw_queue = sw_None & op != sw_None & SwOpEnabled(op)
  ==>
  Begin
    sw_queue := op;
  End;
EndRuleset;

---------------------------------------------------------------------------
-- (2) RN-F dispatches sw_queue into a TX REQ when L1 state + outstanding
-- slot allow.  Preconditions follow CHI E.b legal-issue rules for the
-- requester's local cache state (sec 2.4.1).
---------------------------------------------------------------------------

-- ReadClean: I-state only (otherwise it's a local hit, drained
-- silently by sw_drain_local_hit below).
Rule "Issue_ReadClean"
  sw_queue = sw_ReadClean & l1 = L1_I & tx_phase = TX_IDLE & rx_snp = rx_None
==>
Begin
  tx_op := tx_ReadClean; tx_phase := TX_AWAIT_RSP;
  tx_expcompack := true;
  sw_queue := sw_None;
End;

-- Split per L1 state, and RELAXED to allow SC.  The guard was
-- l1 = L1_I only, so the model could not express upgrading a
-- SHARED line to unique -- it forbade SC -> UC entirely, which
-- the RTL performs and the random baseline reached.  A store to
-- a shared line legitimately issues ReadUnique.  Model fidelity
-- bug, not a stimulus gap.
-- cbo.zero is a block-initialising STORE.  It used to be smuggled
-- through SW_enqueue_ReadClean's dispatch rotation in the TB, so the
-- model tracked a READ (LD MSHR slot) while the DUT issued a STORE
-- (ST slot).  The resource accounting diverged immediately and the
-- generator produced vectors that deadlock the L1.5.  Modelled
-- explicitly here: ReadUnique-shaped, because that is what
-- txreq_encoder actually emits for it.
Rule "Issue_CBO_Zero_from_I"
  sw_queue = sw_CBO_Zero & l1 = L1_I & tx_phase = TX_IDLE & rx_snp = rx_None
==>
Begin
  tx_op := tx_ReadUnique; tx_phase := TX_AWAIT_RSP;
  tx_expcompack := true;
  sw_queue := sw_None;
End;

Rule "Issue_CBO_Zero_from_SC"
  sw_queue = sw_CBO_Zero & l1 = L1_SC & tx_phase = TX_IDLE & rx_snp = rx_None
==>
Begin
  tx_op := tx_ReadUnique; tx_phase := TX_AWAIT_RSP;
  tx_expcompack := true;
  sw_queue := sw_None;
End;

Rule "Issue_ReadUnique_from_I"
  sw_queue = sw_ReadUnique & l1 = L1_I & tx_phase = TX_IDLE & rx_snp = rx_None
==>
Begin
  tx_op := tx_ReadUnique; tx_phase := TX_AWAIT_RSP;
  tx_expcompack := true;
  sw_queue := sw_None;
End;

Rule "Issue_ReadUnique_from_SC"
  sw_queue = sw_ReadUnique & l1 = L1_SC & tx_phase = TX_IDLE & rx_snp = rx_None
==>
Begin
  tx_op := tx_ReadUnique; tx_phase := TX_AWAIT_RSP;
  tx_expcompack := true;
  sw_queue := sw_None;
End;

-- Split per L1 state, and RELAXED to allow SC.  The guard was
-- l1 = L1_I only, so the model could not express upgrading a
-- SHARED line to unique -- it forbade SC -> UC entirely, which
-- the RTL performs and the random baseline reached.  A store to
-- a shared line legitimately issues MakeUnique.  Model fidelity
-- bug, not a stimulus gap.
Rule "Issue_MakeUnique_from_I"
  sw_queue = sw_MakeUnique & l1 = L1_I & tx_phase = TX_IDLE & rx_snp = rx_None
==>
Begin
  -- CHIE_MAKEUNIQUE is assigned nowhere in the RTL (no msg_type_chi /
  -- msg_txreq_opcode site in any of the 32 L1.5 files); the upgrade is
  -- served by re-issuing ReadUnique, observed as TXREQ 0x07 on a store
  -- to a non-unique line.  tx_MakeUnique was fiction.
  tx_op := tx_ReadUnique; tx_phase := TX_AWAIT_RSP;
  tx_expcompack := true;
  sw_queue := sw_None;
End;

Rule "Issue_MakeUnique_from_SC"
  sw_queue = sw_MakeUnique & l1 = L1_SC & tx_phase = TX_IDLE & rx_snp = rx_None
==>
Begin
  -- CHIE_MAKEUNIQUE is assigned nowhere in the RTL (no msg_type_chi /
  -- msg_txreq_opcode site in any of the 32 L1.5 files); the upgrade is
  -- served by re-issuing ReadUnique, observed as TXREQ 0x07 on a store
  -- to a non-unique line.  tx_MakeUnique was fiction.
  tx_op := tx_ReadUnique; tx_phase := TX_AWAIT_RSP;
  tx_expcompack := true;
  sw_queue := sw_None;
End;

-- CMOs (cbo.flush / cbo.inval) do NOT map to CHI CleanShared /
-- CleanInvalid on this DUT.  Every TXREQ opcode the L1.5 can emit is
-- enumerated by the msg_type_chi / msg_txreq_opcode assignments in
-- txreq_encoder.v and response_encoder.sv:
--
--   ReadClean  ReadNoSnp  ReadUnique  WriteNoSnpPtl  Atomic*
--   WriteBackFull / WriteBackPtl   (response_encoder.sv NOC3 path)
--
-- CleanShared and CleanInvalid appear nowhere; CleanUnique is present
-- but commented out (txreq_encoder.v:551).  A CMO on a DIRTY line is
-- serviced by the NOC3 writeback path as WriteBackFull with
-- msg_expcompack = 0 -- a copyback write (DBIDResp -> data -> Comp),
-- not a dataless CMO retired by Comp+CompAck.  A CMO on a clean or
-- invalid line emits no TXREQ at all: traced on
-- hub_I_AWAIT_RSP_CleanShared_Q_CleanShared, where two do_cbo_flush
-- produce zero requests beyond the unrelated ReadUnique.
--
-- Modelling these as tx_CleanShared / tx_CleanInvalid made every
-- vector containing them expect a transaction the DUT cannot issue.


-- Clean or invalid line: no CHI traffic, line ends Invalid.
Rule "SW_drain_CleanInvalid"
  sw_queue = sw_CleanInvalid & tx_phase = TX_IDLE & rx_snp = rx_None
==>
Begin
  -- cbo.inval is a pure CORE-side L1D self-invalidate.  The predecoder
  -- maps PCX_REQTYPE_LOAD + invalidate_cacheline to
  -- L15_REQTYPE_DCACHE_SELF_INVALIDATION, whose handler sets only
  -- WMT_DEMAP_TAGCHECK_WAY_IF_MES + CPX_GEN_DCACHE_INVALIDATION: no
  -- MESI read or write, no dcache op, no NOC1/NOC3 request.  The L1.5
  -- line -- including dirty data -- is untouched in every state, so
  -- l1 does NOT change here.  (Despite the name, this is the CMO that
  -- does NOT invalidate the L1.5; cbo.flush is the one that does.)
  sw_queue := sw_None;
End;

-- cbo.flush.  Same story as CleanInvalid above: dirty -> WriteBackFull,
-- otherwise silent.  Note the line still ends Invalid on the dirty
-- path -- WriteBackFull evicts, it does not retain a clean copy, so
-- this DUT cannot express CleanShared's "write back but keep it".
Rule "Issue_CleanShared_dirty"
  sw_queue = sw_CleanShared & IsDirty(l1) &
  tx_phase = TX_IDLE & rx_snp = rx_None
==>
Begin
  tx_op := tx_WriteBackFull; tx_phase := TX_AWAIT_RSP;
  tx_expcompack := false;
  sw_queue := sw_None;
  lr_valid := false;
End;

-- Clean line: no CHI traffic, but the line STILL goes Invalid.
-- L15_REQTYPE_LINE_FLUSH applies
-- L15_S3_MESI_INVALIDATE_FLUSH_WAY_IF_MES on every valid state, not
-- just M.  Verified with +CMO_PROBE: a load fills to UC
-- (tagcheck_state_s2=2), cbo.flush emits no TXREQ, and the following
-- load MISSES with a fresh ReadClean -- so the line was dropped.
Rule "SW_drain_CleanShared_clean"
  sw_queue = sw_CleanShared & !IsDirty(l1) &
  tx_phase = TX_IDLE & rx_snp = rx_None
==>
Begin
  l1 := L1_I;
  lr_valid := false;
  sw_queue := sw_None;
End;

-- Atomics: any L1 state (HN-F performs the RMW; RN-F doesn't cache result).
Rule "Issue_AtomicLoad"
  sw_queue = sw_AtomicLoad & tx_phase = TX_IDLE & rx_snp = rx_None
==>
Begin
  tx_op := tx_AtomicLoad; tx_phase := TX_AWAIT_RSP;
  tx_expcompack := false;
  sw_queue := sw_None;
End;

Rule "Issue_AtomicStore"
  sw_queue = sw_AtomicStore & tx_phase = TX_IDLE & rx_snp = rx_None
==>
Begin
  tx_op := tx_AtomicStore; tx_phase := TX_AWAIT_RSP;
  tx_expcompack := false;
  sw_queue := sw_None;
End;

-- Non-cacheable LOAD (IFILL-NC or NC data-side LD).  L1 state is not
-- touched — the read bypasses the local cache and the response bytes
-- go straight back to the LSU / IFU without any allocation.
Rule "Issue_NC_Load"
  sw_queue = sw_NC_Load & tx_phase = TX_IDLE & rx_snp = rx_None
==>
Begin
  tx_op := tx_ReadNoSnp; tx_phase := TX_AWAIT_RSP;
  tx_expcompack := false;
  sw_queue := sw_None;
End;

-- Non-cacheable STORE (writethrough).  Follows the write lifecycle
-- (DBIDResp → send data → Comp) but does not install / mutate any
-- cached line.
-- NC_Store issuance split PER L1 STATE.  The guard placed no
-- constraint on l1, so BFS reached the pair only when the walk
-- happened to sit in UC/UD with an NC_Store queued -- it never did,
-- leaving x_state_op <UC,WriteNoSnpPtl> and <UD,WriteNoSnpPtl>
-- untargeted while the random baseline hit both.  One rule per
-- state makes each an explicit BFS edge.
Rule "Issue_NC_Store_from_I"
  sw_queue = sw_NC_Store & tx_phase = TX_IDLE & rx_snp = rx_None & l1 = L1_I
==>
Begin
  tx_op := tx_WriteNoSnpPtl; tx_phase := TX_AWAIT_RSP;
  tx_expcompack := false;
  sw_queue := sw_None;
End;

Rule "Issue_NC_Store_from_SC"
  sw_queue = sw_NC_Store & tx_phase = TX_IDLE & rx_snp = rx_None & l1 = L1_SC
==>
Begin
  tx_op := tx_WriteNoSnpPtl; tx_phase := TX_AWAIT_RSP;
  tx_expcompack := false;
  sw_queue := sw_None;
End;

Rule "Issue_NC_Store_from_UC"
  sw_queue = sw_NC_Store & tx_phase = TX_IDLE & rx_snp = rx_None & l1 = L1_UC
==>
Begin
  tx_op := tx_WriteNoSnpPtl; tx_phase := TX_AWAIT_RSP;
  tx_expcompack := false;
  sw_queue := sw_None;
End;

Rule "Issue_NC_Store_from_SD"
  sw_queue = sw_NC_Store & tx_phase = TX_IDLE & rx_snp = rx_None & l1 = L1_SD
==>
Begin
  tx_op := tx_WriteNoSnpPtl; tx_phase := TX_AWAIT_RSP;
  tx_expcompack := false;
  sw_queue := sw_None;
End;

Rule "Issue_NC_Store_from_UD"
  sw_queue = sw_NC_Store & tx_phase = TX_IDLE & rx_snp = rx_None & l1 = L1_UD
==>
Begin
  tx_op := tx_WriteNoSnpPtl; tx_phase := TX_AWAIT_RSP;
  tx_expcompack := false;
  sw_queue := sw_None;
End;

-- LR miss: emits Read-shape CHI REQ AND sets the reservation flag
-- when the fill completes.  For simplicity the reservation is set at
-- issue-time; snoop rules later invalidate it before SC can commit.
-- NOTE: the L1.5 RTL emits CHI ReadUnique (not ReadClean) for
-- L15_NOC1_REQTYPE_LR_REQUEST (see txreq_encoder.v:619 and the
-- L15_AMO_OP_LR predecoder path).  LR fetches the line in unique
-- state so the subsequent SC can commit without another upgrade.
Rule "Issue_LR_miss"
  sw_queue = sw_LR & l1 = L1_I & tx_phase = TX_IDLE & rx_snp = rx_None
==>
Begin
  tx_op := tx_ReadUnique; tx_phase := TX_AWAIT_RSP;
  tx_expcompack := true;
  lr_valid := true;
  sw_queue := sw_None;
End;

-- LR hit: no CHI activity, but the reservation is (re)armed.
Rule "Issue_LR_hit"
  sw_queue = sw_LR & l1 != L1_I & tx_phase = TX_IDLE & rx_snp = rx_None
==>
Begin
  lr_valid := true;
  sw_queue := sw_None;
End;

-- SC success (local unique): line writable, reservation valid.
-- Commit locally with no CHI, promote UC->UD, then release
-- reservation.
Rule "Issue_SC_local"
  sw_queue = sw_SC & lr_valid & IsUnique(l1) &
  tx_phase = TX_IDLE & rx_snp = rx_None
==>
Begin
  If l1 = L1_UC Then l1 := L1_UD; End;
  lr_valid := false;
  sw_queue := sw_None;
End;

-- SC upgrade: cached shared, reservation valid.  Needs upgrade to
-- unique via CHI ReadUnique before the store commits.  Reservation
-- is cleared unconditionally at issue since the intervening tx
-- window is where races kill it in real HW.
Rule "Issue_SC_upgrade"
  sw_queue = sw_SC & lr_valid & IsShared(l1) &
  tx_phase = TX_IDLE & rx_snp = rx_None
==>
Begin
  tx_op := tx_ReadUnique; tx_phase := TX_AWAIT_RSP;
  tx_expcompack := true;
  lr_valid := false;
  sw_queue := sw_None;
End;

-- SC miss with reservation still nominally valid (rare — LR should
-- have installed the line, but eviction between LR and SC leaves I).
-- Model as SC-fail drain rather than opening a fresh fill transaction.
Rule "Issue_SC_miss"
  sw_queue = sw_SC & lr_valid & l1 = L1_I &
  tx_phase = TX_IDLE & rx_snp = rx_None
==>
Begin
  lr_valid := false;
  sw_queue := sw_None;
End;

-- SC fail: no reservation held.  Silent drain, SC returns failure to
-- the hart, no CHI activity.
Rule "SW_drain_SC_fail"
  sw_queue = sw_SC & !lr_valid
==>
Begin
  sw_queue := sw_None;
End;

-- Drain sw_queue when the requested op can't legally fire from the
-- current L1 state (CHI E.b sec 2.4.1).  Software stalls would
-- otherwise deadlock the model; in practice the RN-F's coherence
-- logic silently drops infeasible ops (e.g. CleanUnique on an
-- invalid line == no-op).
Rule "SW_local_hit_drain_ReadClean"
  sw_queue = sw_ReadClean & l1 != L1_I
==>
Begin
  sw_queue := sw_None;
End;

Rule "SW_local_hit_drain_ReadUnique"
  sw_queue = sw_ReadUnique & IsUnique(l1)
==>
Begin
  sw_queue := sw_None;
End;

Rule "SW_drain_MakeUnique_when_not_I"
  sw_queue = sw_MakeUnique & l1 != L1_I
==>
Begin
  sw_queue := sw_None;
End;

-- ── Set-conflict eviction ───────────────────────────────────────────
-- Models N loads to distinct lines mapping to the target's cache set.
-- Result depends on the target line's current state.

-- UD target: displaced by LRU → dirty writeback via CHI WriteBackFull.
-- Reuses the existing WB TX lifecycle (Env_Comp_for_WriteBack drops
-- the line to I once Comp is received).
Rule "Issue_SetConflict_dirty"
  sw_queue = sw_SetConflict & l1 = L1_UD &
  tx_phase = TX_IDLE & rx_snp = rx_None
==>
Begin
  tx_op := tx_WriteBackFull; tx_phase := TX_AWAIT_RSP;
  tx_expcompack := false;
  sw_queue := sw_None;
  -- Any pending LR reservation on the line dies with the eviction.
  lr_valid := false;
End;

-- Clean or SD target: silent eviction, no CHI traffic, line → I.
-- Groups UC / SC / SD because none of them can legally emit
-- WriteBackFull from this position (SD's dirty data would leak, but
-- the L1.5 RTL takes the same silent-drop path).
Rule "SW_drain_SetConflict_clean_or_SD"
  sw_queue = sw_SetConflict &
  (l1 = L1_UC | l1 = L1_SC | l1 = L1_SD) &
  tx_phase = TX_IDLE & rx_snp = rx_None
==>
Begin
  l1 := L1_I;
  lr_valid := false;
  sw_queue := sw_None;
End;

-- I target: nothing to evict.
Rule "SW_drain_SetConflict_when_I"
  sw_queue = sw_SetConflict & l1 = L1_I
==>
Begin
  sw_queue := sw_None;
End;

-- Local store-hit promotes UC -> UD without any REQ.
Rule "StoreHit_UC_to_UD"
  l1 = L1_UC & sw_queue = sw_None & tx_phase = TX_IDLE & rx_snp = rx_None
==>
Begin
  l1 := L1_UD;
End;

---------------------------------------------------------------------------
-- (3) Environment-side responses (non-deterministic, CHI-legal).
-- The environment can pick any valid response flit for the outstanding
-- TX REQ at any time.  This is the worst-case adversary view.
---------------------------------------------------------------------------

-- ── Read-shape: CompData with clean ────────────────────────────────
Rule "Env_CompData_clean"
  tx_phase = TX_AWAIT_RSP &
  (tx_op = tx_ReadClean | tx_op = tx_ReadUnique)
==>
Begin
  tx_phase := TX_AWAIT_COMPACK_CLEAN;
End;

-- ── Read-shape: CompData with dirty (PD attribute on the wire) ────
Rule "Env_CompData_dirty"
  tx_phase = TX_AWAIT_RSP &
  (tx_op = tx_ReadClean | tx_op = tx_ReadUnique)
==>
Begin
  tx_phase := TX_AWAIT_COMPACK_DIRTY;
End;

-- (Env_Comp_dataless removed: its only producer was tx_MakeUnique,
--  which the RTL cannot emit.  Every REQ this DUT issues is either a
--  read completed by CompData or a write completed by DBIDResp/Comp.)

-- ── Write-shape (WriteBack/Clean): CompDBIDResp combo or split ─────
-- Modelled as separate DBIDResp then Comp.
Rule "Env_DBIDResp_for_Write"
  tx_phase = TX_AWAIT_RSP &
  (tx_op = tx_WriteBackFull |
   tx_op = tx_AtomicLoad   | tx_op = tx_AtomicStore)
==>
Begin
  tx_phase := TX_AWAIT_DATA_SEND;
End;

-- ── CompDBIDResp (combined) for write paths ─────────────────────────
Rule "Env_CompDBIDResp_for_Write"
  tx_phase = TX_AWAIT_RSP &
  tx_op = tx_WriteBackFull
==>
Begin
  -- Combined DBID+Comp: skip TX_AWAIT_DATA_SEND, go straight to "send data"
  -- then retire on data-send.  Model as: TX_AWAIT_DATA_SEND but mark
  -- the Comp side already done by jumping past TX_AWAIT_COMP.
  tx_phase := TX_AWAIT_DATA_SEND;
End;

-- ── Atomic: CompData (returns old value for AtomicLoad/Swap) ────────
Rule "Env_CompData_for_AtomicLoad"
  tx_phase = TX_AWAIT_COMP & tx_op = tx_AtomicLoad
==>
Begin
  -- AtomicLoad terminates with CompData (no CompAck).
  tx_op := tx_None; tx_phase := TX_IDLE;
  tx_expcompack := false;
End;

-- ── Atomic: Comp (AtomicStore) ─────────────────────────────────────
Rule "Env_Comp_for_AtomicStore"
  tx_phase = TX_AWAIT_COMP & tx_op = tx_AtomicStore
==>
Begin
  tx_op := tx_None; tx_phase := TX_IDLE;
  tx_expcompack := false;
End;

-- ── Comp for WriteBack/Clean after data sent ───────────────────────
Rule "Env_Comp_for_WriteBack"
  tx_phase = TX_AWAIT_COMP &
  tx_op = tx_WriteBackFull
==>
Begin
  -- WriteBackFull drops the line to I.  (WriteCleanFull removed: its
  -- RTL path is gated by wrcl_valid_r, which rx_control.sv assigns
  -- 1'b0 and never sets, so the transaction cannot occur.)
  l1 := L1_I;
  tx_op := tx_None; tx_phase := TX_IDLE;
  tx_expcompack := false;
End;

-- ── NC-Load: single CompData response, no CompAck, no cache install ─
Rule "Env_CompData_for_NC_Load"
  tx_phase = TX_AWAIT_RSP & tx_op = tx_ReadNoSnp
==>
Begin
  -- ReadNoSnp returns CompData directly and retires.  No CompAck,
  -- no L1 state change.
  tx_op := tx_None; tx_phase := TX_IDLE;
  tx_expcompack := false;
End;

-- ── NC-Store: DBIDResp → send data → Comp lifecycle ────────────────
Rule "Env_DBIDResp_for_NC_Store"
  tx_phase = TX_AWAIT_RSP & tx_op = tx_WriteNoSnpPtl
==>
Begin
  tx_phase := TX_AWAIT_DATA_SEND;
End;

Rule "Env_Comp_for_NC_Store"
  tx_phase = TX_AWAIT_COMP & tx_op = tx_WriteNoSnpPtl
==>
Begin
  -- Non-cacheable, no L1 change.
  tx_op := tx_None; tx_phase := TX_IDLE;
  tx_expcompack := false;
End;

---------------------------------------------------------------------------
-- (4) RN-F sends write data (after DBIDResp); covers writes + atomics
---------------------------------------------------------------------------

Rule "Send_WriteData"
  tx_phase = TX_AWAIT_DATA_SEND
==>
Begin
  tx_phase := TX_AWAIT_COMP;
End;

---------------------------------------------------------------------------
-- (5) RN-F sends CompAck; closes the TX lifecycle for ExpCompAck ops.
-- Picks post-CompAck L1 state based on tx_op + tx_data_dirty.
---------------------------------------------------------------------------

-- Two CompAck rules, one per phase variant.  The rule name encodes
-- whether the line received dirty data so downstream tooling can
-- distinguish UC vs UD / SC vs SD post-state without an extra
-- Boolean in the state vector.
Rule "Send_CompAck_after_clean"
  tx_phase = TX_AWAIT_COMPACK_CLEAN & tx_expcompack
==>
Begin
  Switch tx_op
    Case tx_ReadClean :    l1 := L1_SC;
    Case tx_ReadUnique :   l1 := L1_UC;
  EndSwitch;
  tx_op := tx_None; tx_phase := TX_IDLE;
  tx_expcompack := false;
End;

Rule "Send_CompAck_after_dirty"
  tx_phase = TX_AWAIT_COMPACK_DIRTY & tx_expcompack
==>
Begin
  -- DIRTY phase is only reachable for read-shape ops; the env-side
  -- response rules enforce this.
  Switch tx_op
    Case tx_ReadClean :  l1 := L1_SD;
    Case tx_ReadUnique : l1 := L1_UD;
  EndSwitch;
  tx_op := tx_None; tx_phase := TX_IDLE;
  tx_expcompack := false;
End;

---------------------------------------------------------------------------
-- (6) Environment-side snoop injection.  Bounded to one outstanding
-- snoop at a time so the state space stays tractable.
---------------------------------------------------------------------------

-- NOTE: these five injection rules formerly carried `& l1 != L1_I`, on
-- the reasoning that snooping an invalid line is uninteresting because
-- the RN-F just answers SnpResp_I.  That excluded l1 = I from the snoop
-- cross ENTIRELY: across 631 generated vectors the L1 state at snoop
-- injection was SC 3930 / UD 3381 / UC 3306 / SD 3235 / I zero.  The
-- constrained-random baseline did reach two x_decision cells there, so
-- the DUT behaviour on that path is evidently not trivial.  The guard
-- is dropped; Snp_any_from_I below already supplies the response, so
-- no new rules are needed.
Rule "Env_Snp_SnpClean"
  rx_snp = rx_None
==>
Begin
  rx_snp := rx_SnpClean; rx_resp_owed := true; rx_rettosrc := false;
End;

-- RetToSrc injection is split PER L1 STATE.  With a single
-- state-agnostic _RTS rule, BFS fired it wherever the search happened
-- to be -- overwhelmingly on I and SC, because those are the common
-- states -- so the SR_*_D (clean-data-return) cells on UC / SD / UD
-- were never targeted at all: 10 of the x_decision holes.  One rule
-- per state makes each (op, L1 state) pair its own edge, so the
-- 2-switch target enumeration is obliged to emit a vector for each.
Rule "Env_Snp_SnpClean_RTS_from_I"
  rx_snp = rx_None & l1 = L1_I & RtsEnabled()
==>
Begin
  rx_snp := rx_SnpClean; rx_resp_owed := true; rx_rettosrc := true;
End;

Rule "Env_Snp_SnpClean_RTS_from_SC"
  rx_snp = rx_None & l1 = L1_SC & RtsEnabled()
==>
Begin
  rx_snp := rx_SnpClean; rx_resp_owed := true; rx_rettosrc := true;
End;

Rule "Env_Snp_SnpClean_RTS_from_UC"
  rx_snp = rx_None & l1 = L1_UC & RtsEnabled()
==>
Begin
  rx_snp := rx_SnpClean; rx_resp_owed := true; rx_rettosrc := true;
End;

Rule "Env_Snp_SnpClean_RTS_from_SD"
  rx_snp = rx_None & l1 = L1_SD & RtsEnabled()
==>
Begin
  rx_snp := rx_SnpClean; rx_resp_owed := true; rx_rettosrc := true;
End;

Rule "Env_Snp_SnpClean_RTS_from_UD"
  rx_snp = rx_None & l1 = L1_UD & RtsEnabled()
==>
Begin
  rx_snp := rx_SnpClean; rx_resp_owed := true; rx_rettosrc := true;
End;

Rule "Env_Snp_SnpUnique"
  rx_snp = rx_None
==>
Begin
  rx_snp := rx_SnpUnique; rx_resp_owed := true; rx_rettosrc := false;
End;

Rule "Env_Snp_SnpUnique_RTS_from_I"
  rx_snp = rx_None & l1 = L1_I & RtsEnabled()
==>
Begin
  rx_snp := rx_SnpUnique; rx_resp_owed := true; rx_rettosrc := true;
End;

Rule "Env_Snp_SnpUnique_RTS_from_SC"
  rx_snp = rx_None & l1 = L1_SC & RtsEnabled()
==>
Begin
  rx_snp := rx_SnpUnique; rx_resp_owed := true; rx_rettosrc := true;
End;

Rule "Env_Snp_SnpUnique_RTS_from_UC"
  rx_snp = rx_None & l1 = L1_UC & RtsEnabled()
==>
Begin
  rx_snp := rx_SnpUnique; rx_resp_owed := true; rx_rettosrc := true;
End;

Rule "Env_Snp_SnpUnique_RTS_from_SD"
  rx_snp = rx_None & l1 = L1_SD & RtsEnabled()
==>
Begin
  rx_snp := rx_SnpUnique; rx_resp_owed := true; rx_rettosrc := true;
End;

Rule "Env_Snp_SnpUnique_RTS_from_UD"
  rx_snp = rx_None & l1 = L1_UD & RtsEnabled()
==>
Begin
  rx_snp := rx_SnpUnique; rx_resp_owed := true; rx_rettosrc := true;
End;

Rule "Env_Snp_SnpMakeInvalid"
  rx_snp = rx_None
==>
Begin
  rx_snp := rx_SnpMakeInvalid; rx_resp_owed := true; rx_rettosrc := false;
End;

Rule "Env_Snp_SnpCleanInvalid"
  rx_snp = rx_None
==>
Begin
  rx_snp := rx_SnpCleanInvalid; rx_resp_owed := true; rx_rettosrc := false;
End;

Rule "Env_Snp_SnpCleanInvalid_RTS_from_I"
  rx_snp = rx_None & l1 = L1_I & RtsEnabled()
==>
Begin
  rx_snp := rx_SnpCleanInvalid; rx_resp_owed := true; rx_rettosrc := true;
End;

Rule "Env_Snp_SnpCleanInvalid_RTS_from_SC"
  rx_snp = rx_None & l1 = L1_SC & RtsEnabled()
==>
Begin
  rx_snp := rx_SnpCleanInvalid; rx_resp_owed := true; rx_rettosrc := true;
End;

Rule "Env_Snp_SnpCleanInvalid_RTS_from_UC"
  rx_snp = rx_None & l1 = L1_UC & RtsEnabled()
==>
Begin
  rx_snp := rx_SnpCleanInvalid; rx_resp_owed := true; rx_rettosrc := true;
End;

Rule "Env_Snp_SnpCleanInvalid_RTS_from_SD"
  rx_snp = rx_None & l1 = L1_SD & RtsEnabled()
==>
Begin
  rx_snp := rx_SnpCleanInvalid; rx_resp_owed := true; rx_rettosrc := true;
End;

Rule "Env_Snp_SnpCleanInvalid_RTS_from_UD"
  rx_snp = rx_None & l1 = L1_UD & RtsEnabled()
==>
Begin
  rx_snp := rx_SnpCleanInvalid; rx_resp_owed := true; rx_rettosrc := true;
End;

Rule "Env_Snp_SnpShared"
  rx_snp = rx_None
==>
Begin
  rx_snp := rx_SnpShared; rx_resp_owed := true; rx_rettosrc := false;
End;

Rule "Env_Snp_SnpShared_RTS_from_I"
  rx_snp = rx_None & l1 = L1_I & RtsEnabled()
==>
Begin
  rx_snp := rx_SnpShared; rx_resp_owed := true; rx_rettosrc := true;
End;

Rule "Env_Snp_SnpShared_RTS_from_SC"
  rx_snp = rx_None & l1 = L1_SC & RtsEnabled()
==>
Begin
  rx_snp := rx_SnpShared; rx_resp_owed := true; rx_rettosrc := true;
End;

Rule "Env_Snp_SnpShared_RTS_from_UC"
  rx_snp = rx_None & l1 = L1_UC & RtsEnabled()
==>
Begin
  rx_snp := rx_SnpShared; rx_resp_owed := true; rx_rettosrc := true;
End;

Rule "Env_Snp_SnpShared_RTS_from_SD"
  rx_snp = rx_None & l1 = L1_SD & RtsEnabled()
==>
Begin
  rx_snp := rx_SnpShared; rx_resp_owed := true; rx_rettosrc := true;
End;

Rule "Env_Snp_SnpShared_RTS_from_UD"
  rx_snp = rx_None & l1 = L1_UD & RtsEnabled()
==>
Begin
  rx_snp := rx_SnpShared; rx_resp_owed := true; rx_rettosrc := true;
End;

---------------------------------------------------------------------------
-- (7) RN-F per-(snoop opcode, L1 state) decision rules.
-- These mirror hnf_fsm_v2.m's _SNP_TABLE but from the snoopee side:
-- each rule picks a SnpResp* variant and the post-snoop L1 state.
---------------------------------------------------------------------------

-- ── SnpClean ────────────────────────────────────────────────────────
Rule "Snp_SnpClean_from_UD"
  rx_snp = rx_SnpClean & rx_resp_owed & l1 = L1_UD
==>
Begin
  l1 := L1_SC;
  rx_snp := rx_None; rx_resp_owed := false; rx_rettosrc := false; lr_valid := false;
End;

Rule "Snp_SnpClean_from_UC"
  rx_snp = rx_SnpClean & rx_resp_owed & l1 = L1_UC
==>
Begin
  l1 := L1_SC;
  rx_snp := rx_None; rx_resp_owed := false; rx_rettosrc := false; lr_valid := false;
End;

Rule "Snp_SnpClean_from_SD"
  rx_snp = rx_SnpClean & rx_resp_owed & l1 = L1_SD
==>
Begin
  l1 := L1_SC;
  rx_snp := rx_None; rx_resp_owed := false; rx_rettosrc := false; lr_valid := false;
End;

Rule "Snp_SnpClean_from_SC"
  rx_snp = rx_SnpClean & rx_resp_owed & l1 = L1_SC
==>
Begin
  rx_snp := rx_None; rx_resp_owed := false; rx_rettosrc := false; lr_valid := false;
End;

-- ── SnpUnique ───────────────────────────────────────────────────────
Rule "Snp_SnpUnique_from_UD"
  rx_snp = rx_SnpUnique & rx_resp_owed & l1 = L1_UD
==>
Begin
  l1 := L1_I;
  rx_snp := rx_None; rx_resp_owed := false; rx_rettosrc := false; lr_valid := false;
End;

Rule "Snp_SnpUnique_from_UC"
  rx_snp = rx_SnpUnique & rx_resp_owed & l1 = L1_UC
==>
Begin
  l1 := L1_I;
  rx_snp := rx_None; rx_resp_owed := false; rx_rettosrc := false; lr_valid := false;
End;

Rule "Snp_SnpUnique_from_SD"
  rx_snp = rx_SnpUnique & rx_resp_owed & l1 = L1_SD
==>
Begin
  l1 := L1_I;
  rx_snp := rx_None; rx_resp_owed := false; rx_rettosrc := false; lr_valid := false;
End;

Rule "Snp_SnpUnique_from_SC"
  rx_snp = rx_SnpUnique & rx_resp_owed & l1 = L1_SC
==>
Begin
  l1 := L1_I;
  rx_snp := rx_None; rx_resp_owed := false; rx_rettosrc := false; lr_valid := false;
End;

-- ── SnpMakeInvalid (no data ever returned per CHI-E) ───────────────
Rule "Snp_SnpMakeInvalid_any"
  rx_snp = rx_SnpMakeInvalid & rx_resp_owed
==>
Begin
  l1 := L1_I;
  rx_snp := rx_None; rx_resp_owed := false; rx_rettosrc := false; lr_valid := false;
End;

-- ── SnpCleanInvalid ────────────────────────────────────────────────
Rule "Snp_SnpCleanInvalid_from_dirty"
  rx_snp = rx_SnpCleanInvalid & rx_resp_owed & IsDirty(l1)
==>
Begin
  l1 := L1_I;
  rx_snp := rx_None; rx_resp_owed := false; rx_rettosrc := false; lr_valid := false;
End;

Rule "Snp_SnpCleanInvalid_from_clean"
  rx_snp = rx_SnpCleanInvalid & rx_resp_owed &
  (l1 = L1_UC | l1 = L1_SC)
==>
Begin
  l1 := L1_I;
  rx_snp := rx_None; rx_resp_owed := false; rx_rettosrc := false; lr_valid := false;
End;

-- ── SnpShared (hint: peer flushes dirty, keeps shared copy) ─────────
Rule "Snp_SnpShared_from_dirty"
  rx_snp = rx_SnpShared & rx_resp_owed & IsDirty(l1)
==>
Begin
  If l1 = L1_UD Then l1 := L1_UC; Else l1 := L1_SC; End;
  rx_snp := rx_None; rx_resp_owed := false; rx_rettosrc := false; lr_valid := false;
End;

Rule "Snp_SnpShared_from_clean"
  rx_snp = rx_SnpShared & rx_resp_owed &
  (l1 = L1_UC | l1 = L1_SC)
==>
Begin
  If l1 = L1_UC Then l1 := L1_SC; End;
  rx_snp := rx_None; rx_resp_owed := false; rx_rettosrc := false; lr_valid := false;
End;

-- ── Snoop arrives but line is already I ────────────────────────────
-- Race: the env injected a snoop while we held a copy; before we
-- responded, the RN-F's own CompAck (or another invalidating action)
-- dropped L1 to I.  Per CHI E.b, the RN-F responds SnpResp_I.
Ruleset s : RxSnp Do
  Rule "Snp_any_from_I"
    rx_snp = s & s != rx_None & rx_resp_owed & l1 = L1_I
  ==>
  Begin
    rx_snp := rx_None; rx_resp_owed := false; rx_rettosrc := false; lr_valid := false;
  End;
EndRuleset;

---------------------------------------------------------------------------
-- Safety invariants
---------------------------------------------------------------------------

-- L1 state is always a CHI-legal value (vacuous given enum, but kept
-- as a placeholder for future multi-line / multi-RNF extensions).
Invariant "L1StateValid"
  l1 = L1_I | l1 = L1_SC | l1 = L1_UC | l1 = L1_SD | l1 = L1_UD;

-- TX_IDLE iff no outstanding REQ.
Invariant "TxIdleMeansNoOp"
  (tx_phase = TX_IDLE) -> (tx_op = tx_None);

Invariant "TxBusyMeansHasOp"
  (tx_phase != TX_IDLE) -> (tx_op != tx_None);

-- ExpCompAck only set during an outstanding TX with an ack-bearing op.
Invariant "ExpCompAckOnlyDuringTx"
  tx_expcompack -> (tx_phase != TX_IDLE);

-- Cannot send CompAck on an op that doesn't expect one.
Invariant "CompAckOnlyForAckBearing"
  ((tx_phase = TX_AWAIT_COMPACK_CLEAN | tx_phase = TX_AWAIT_COMPACK_DIRTY) &
   tx_expcompack) ->
    (tx_op = tx_ReadClean | tx_op = tx_ReadUnique);

-- DIRTY-phase reachable only via CompData (reads), not dataless ops.
Invariant "DirtyPhaseOnlyForReads"
  (tx_phase = TX_AWAIT_COMPACK_DIRTY) ->
    (tx_op = tx_ReadClean | tx_op = tx_ReadUnique);

-- rx_resp_owed iff there's a pending snoop.
Invariant "SnoopOwnedIffPending"
  rx_resp_owed = (rx_snp != rx_None);
