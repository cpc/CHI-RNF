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
-- sys_fsm.m
--
-- Full-system CHI-E coherence model: NUM_RNF detailed RN-Fs + one
-- simplified HN-F + one abstract external requester.
--
-- Relationship to the two existing models:
--
--   murphi_rnf/rnf_fsm.m   ONE RN-F in full detail, counterparty is a
--                          free non-deterministic environment.  Every
--                          Env_* rule fires whenever the TX phase
--                          allows, so the model generates response and
--                          snoop sequences that no real HN-F would
--                          produce (measured: snoop-during-CompAck and
--                          snoop-during-writeback-data are both
--                          reachable there and impossible here).
--
--   murphi/hnf_fsm_v2.m    TWO RN-Fs but only their cache state; the
--                          HN-F carries the whole transient lifecycle
--                          (T_FILL/T_SNP/T_ACK/T_WB_*).  With no
--                          per-agent tx_phase it cannot express any
--                          race whose cell is indexed by the RN-F's
--                          own outstanding-request phase.
--
-- This model inverts hnf_fsm_v2's split.  The RN-F side is ported rule
-- for rule from rnf_fsm.m (full TX lifecycle, sw queue, LR/SC
-- reservation, NC path, per-(snoop x state) decision table), replicated
-- over NUM_RNF agents.  The HN-F keeps NO transient phase of its own:
--
--   h_busy / h_req      the single-line transaction lock (CAM serialiser)
--   h_op                the opcode being served, which is what derives
--                       the snoop opcode and the response shape
--   h_snp_owed[]        which snoopees still owe a SnpResp
--   h_dirty             HN-F holds dirty data handed up by a snoopee
--   h_wait[]            REQ accepted at the HN-F, stalled behind the lock
--
-- Every HN-F "phase" is *derived* rather than stored, because the
-- requester's own tx_phase already encodes it:
--   T_FILL / T_SNP  ==  h_busy & requester tx_phase = TX_AWAIT_RSP
--   T_ACK           ==  h_busy & requester tx_phase = TX_AWAIT_COMPACK_*
--   T_WB_DATA       ==  h_busy & requester tx_phase = TX_AWAIT_COMP
-- Dropping the duplicate is not just economy: two encodings of one
-- phase is exactly where a projected trace would be free to disagree
-- with the DUT.
--
-- The focus is the Env_* alphabet.  In rnf_fsm.m those rules are the
-- adversary; here each one is a *consequence* of directory state:
--
--   Env_CompData_clean    fires only when !h_dirty      (was a free choice)
--   Env_CompData_dirty    fires only when  h_dirty, and h_dirty is set
--                         only by a snoopee that actually passed dirty
--   Env_Snp_<opcode>      opcode derived from h_op, delivered only to
--                         agents the directory says are holders
--   Env_*_for_NC_*        bypass the lock entirely (hnf_mshr_bypass),
--                         so NC traffic overlaps coherent traffic
--
-- Run:
--   rumur --output sys_fsm.c sys_fsm.m
--   cc -std=c11 -march=native -mcx16 -O3 -o sys_fsm sys_fsm.c -lpthread
--   ./sys_fsm
---------------------------------------------------------------------------

Const
  NUM_RNF : 2;
  DUT_ID  : 0;      -- vectors are projected onto this agent

---------------------------------------------------------------------------
-- Types
---------------------------------------------------------------------------

Type
  -- Plain subrange, NOT a ScalarSet: the DUT must stay distinguishable
  -- from its peers or the vector projection has no stable identity.
  -- With NUM_RNF=2 symmetry reduction would buy 2x at the cost of
  -- reintroducing gen_from_murphi.py's sigma-permutation tracking.
  RNFid : 0 .. NUM_RNF - 1;

  L1State : Enum{ L1_I, L1_SC, L1_UC, L1_SD, L1_UD };

  -- Only the opcodes this RTL can actually emit.  CleanShared /
  -- CleanInvalid / MakeUnique / CleanUnique are absent on purpose:
  -- txreq_encoder.v never assigns them (see rnf_fsm.m's notes), CMOs
  -- come out as WriteBackFull or as no TXREQ at all.
  TxOp : Enum{
    tx_None,
    tx_ReadClean, tx_ReadUnique,
    tx_WriteBackFull,
    tx_AtomicLoad, tx_AtomicStore,
    tx_ReadNoSnp, tx_WriteNoSnpPtl
  };

  TxPhase : Enum{
    TX_IDLE,
    TX_AWAIT_RSP,
    TX_AWAIT_DATA_SEND,
    TX_AWAIT_COMP,
    TX_AWAIT_COMPACK_CLEAN,
    TX_AWAIT_COMPACK_DIRTY
  };

  RxSnp : Enum{
    rx_None,
    rx_SnpClean, rx_SnpUnique, rx_SnpMakeInvalid,
    rx_SnpCleanInvalid, rx_SnpShared
  };

  SwSlot : Enum{
    sw_None,
    sw_ReadClean, sw_ReadUnique,
    sw_MakeUnique,
    sw_CleanInvalid, sw_CleanShared,
    sw_CBO_Zero,
    sw_AtomicLoad, sw_AtomicStore,
    sw_NC_Load, sw_NC_Store,
    sw_LR, sw_SC,
    sw_SetConflict
  };

  -- Coherent opcodes the abstract external requester may drive.  This
  -- is the ONLY source of SnpCleanInvalid / SnpShared / SnpMakeInvalid
  -- stimulus, because no CVA6 RN-F can emit the REQs that cause them.
  -- Modelling it as an agentless HN-F-side transaction costs zero
  -- extra agent state.
  ExtOp : Enum{
    ext_None,
    ext_ReadClean,      -- -> SnpClean at every holder
    ext_ReadUnique,     -- -> SnpUnique
    ext_MakeUnique,     -- -> SnpMakeInvalid
    ext_CleanInvalid,   -- -> SnpCleanInvalid
    ext_CleanShared     -- -> SnpShared
  };

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------

Var
  -- ---- Per-RN-F (full rnf_fsm.m fidelity) ----
  l1            : Array [RNFid] of L1State;
  tx_op         : Array [RNFid] of TxOp;
  tx_phase      : Array [RNFid] of TxPhase;
  tx_expcompack : Array [RNFid] of Boolean;
  rx_snp        : Array [RNFid] of RxSnp;
  rx_resp_owed  : Array [RNFid] of Boolean;
  rx_rettosrc   : Array [RNFid] of Boolean;
  sw_queue      : Array [RNFid] of SwSlot;
  lr_valid      : Array [RNFid] of Boolean;

  -- ---- HN-F (no transient phase; see header) ----
  h_busy     : Boolean;
  h_req      : RNFid;             -- meaningful only while h_busy & !h_ext
  h_ext      : Boolean;           -- lock held by the external requester
  h_op       : TxOp;              -- inflight coherent opcode (RN-F owner)
  h_ext_op   : ExtOp;             -- inflight opcode (external owner)
  h_snp_owed : Array [RNFid] of Boolean;
  h_dirty    : Boolean;
  h_wait     : Array [RNFid] of Boolean;   -- REQ stalled behind the lock
  -- 4.11.2 separates two things this model used to conflate: blocking
  -- SNOOPS to the requester, and the HN-F's own transaction occupancy.
  -- For CopyBack and Atomic the snoop-block lifts when the HN-F has the
  -- WriteData -- it does NOT wait for its own Comp.  h_retire[r] is that
  -- window: r's data is in, the line is snoopable by a NEW transaction,
  -- and only the Comp delivery back to r is outstanding.
  h_retire   : Array [RNFid] of Boolean;

  -- ---- Cross-line background activity at the DUT ----
  -- A snoop for ANOTHER cache line pending at the DUT.  Scalar, not an
  -- array: peers are virtual and only DUT-observable interference
  -- matters.  The other line's coherence state is deliberately NOT
  -- modelled -- it is irrelevant to this line's invariants, and
  -- modelling a second full line would multiply the cache states, the
  -- tx tag, the sw tag and the HN-F lock (order 1e9 states).  The HN-F
  -- serialises PER LINE, so two lines never contend there; everything
  -- cross-line is RN-F-side, which is exactly what this one bit carries.
  bg_snp     : Boolean;

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

Function NumUnique() : 0 .. NUM_RNF;
Var n : 0 .. NUM_RNF;
Begin
  n := 0;
  For r : RNFid Do
    If IsUnique(l1[r]) Then n := n + 1; End;
  End;
  Return n;
End;

Function NumShared() : 0 .. NUM_RNF;
Var n : 0 .. NUM_RNF;
Begin
  n := 0;
  For r : RNFid Do
    If IsShared(l1[r]) Then n := n + 1; End;
  End;
  Return n;
End;

Function NumDirty() : 0 .. NUM_RNF;
Var n : 0 .. NUM_RNF;
Begin
  n := 0;
  For r : RNFid Do
    If IsDirty(l1[r]) Then n := n + 1; End;
  End;
  Return n;
End;

Function NumSnoopOwed() : 0 .. NUM_RNF;
Var n : 0 .. NUM_RNF;
Begin
  n := 0;
  For r : RNFid Do
    If h_snp_owed[r] Then n := n + 1; End;
  End;
  Return n;
End;

-- Snoop opcode an RN-F-sourced coherent REQ produces at the snoopees.
Function SnpOfTx(op : TxOp) : RxSnp;
Begin
  Switch op
    Case tx_ReadClean:    Return rx_SnpClean;
    Case tx_ReadUnique:   Return rx_SnpUnique;
    -- Project memory: the HN-F uses SnpMakeInvalid for every atomic
    -- variant, matching hnf_fsm_v2.m's derivation table.
    Case tx_AtomicLoad:   Return rx_SnpMakeInvalid;
    Case tx_AtomicStore:  Return rx_SnpMakeInvalid;
    Else                  Return rx_None;     -- WriteBackFull / NC: no snoop
  EndSwitch;
End;

Function SnpOfExt(op : ExtOp) : RxSnp;
Begin
  Switch op
    Case ext_ReadClean:    Return rx_SnpClean;
    Case ext_ReadUnique:   Return rx_SnpUnique;
    Case ext_MakeUnique:   Return rx_SnpMakeInvalid;
    Case ext_CleanInvalid: Return rx_SnpCleanInvalid;
    Case ext_CleanShared:  Return rx_SnpShared;
    Else                   Return rx_None;
  EndSwitch;
End;

-- Does this coherent REQ need the line lock + a snoop phase?
Function IsCoherent(op : TxOp) : Boolean;
Begin
  Return op = tx_ReadClean | op = tx_ReadUnique | op = tx_WriteBackFull |
         op = tx_AtomicLoad | op = tx_AtomicStore;
End;

---------------------------------------------------------------------------
-- Alphabet gates
--
-- Two independent switches, and conflating them costs real coverage:
--
--   SwOpEnabled   what the DUT's own RTL can emit.  Carried over from
--                 rnf_fsm.m verbatim, including the reasons each
--                 disabled entry is disabled.
--
--   PeerSwEnabled what a *peer* RN-F runs.  Peers exist to create
--                 coherence traffic against the DUT, not to exercise
--                 their own NC / LR / atomic paths -- every op enabled
--                 here multiplies the peer's share of the state space
--                 while adding nothing the DUT can observe beyond the
--                 snoop it already causes.  Widen only with a reason.
--
--   ExtOpEnabled  the abstract external requester.  Deliberately WIDER
--                 than either: MakeUnique / CleanInvalid / CleanShared
--                 are the only producers of SnpMakeInvalid /
--                 SnpCleanInvalid / SnpShared, and the RTL has handlers
--                 for those that would otherwise go unstimulated (the
--                 2026-07-25 sweep pinned 2127 failures on a missing
--                 SnpMakeInvalid handler -- exactly this path).
---------------------------------------------------------------------------

Function SwOpEnabled(op : SwSlot) : Boolean;
Begin
  Switch op
    Case sw_ReadClean:    Return true;
    Case sw_ReadUnique:   Return true;
    -- Exact duplicates of sw_ReadUnique on this RTL: the L1.5 emits
    -- ReadUnique (0x07) for store / MakeUnique / cbo.zero alike.
    Case sw_MakeUnique:   Return false;
    Case sw_CBO_Zero:     Return false;
    Case sw_CleanInvalid: Return true;
    Case sw_CleanShared:  Return true;
    Case sw_AtomicLoad:   Return true;
    -- No RTL path emits a CHI AtomicStore; every AMO becomes
    -- AtomicLoad / AtomicSwap.
    Case sw_AtomicStore:  Return false;
    Case sw_NC_Load:      Return true;
    Case sw_NC_Store:     Return true;
    Case sw_LR:           Return true;
    Case sw_SC:           Return true;
    -- Only source of eviction-driven WriteBackFull.
    Case sw_SetConflict:  Return true;
    Else                  Return false;
  EndSwitch;
End;

Function PeerSwEnabled(op : SwSlot) : Boolean;
Begin
  Switch op
    Case sw_ReadClean:    Return true;   -- -> SnpClean at the DUT
    Case sw_ReadUnique:   Return true;   -- -> SnpUnique at the DUT
    Case sw_SetConflict:  Return true;   -- -> peer WriteBackFull, lock contention
    Else                  Return false;
  EndSwitch;
End;

Function ExtOpEnabled(op : ExtOp) : Boolean;
Begin
  Switch op
    Case ext_ReadClean:    Return true;
    Case ext_ReadUnique:   Return true;
    Case ext_MakeUnique:   Return true;
    Case ext_CleanInvalid: Return true;
    Case ext_CleanShared:  Return true;
    Else                   Return false;
  EndSwitch;
End;

Function SwEnabledFor(r : RNFid; op : SwSlot) : Boolean;
Begin
  If r = DUT_ID Then Return SwOpEnabled(op); Else Return PeerSwEnabled(op); End;
End;

-- RetToSrc injection switch.  Off keeps the snoop alphabet at five
-- opcodes with RetToSrc=0, dropping the SR_*_D clean-data-return
-- responses from the reachable set.  Same default as rnf_fsm.m.
Function RtsEnabled() : Boolean;
Begin
  Return false;
End;

---------------------------------------------------------------------------
-- Initial state
---------------------------------------------------------------------------

Startstate "init"
Begin
  For r : RNFid Do
    l1[r]            := L1_I;
    tx_op[r]         := tx_None;
    tx_phase[r]      := TX_IDLE;
    tx_expcompack[r] := false;
    rx_snp[r]        := rx_None;
    rx_resp_owed[r]  := false;
    rx_rettosrc[r]   := false;
    sw_queue[r]      := sw_None;
    lr_valid[r]      := false;
    h_snp_owed[r]    := false;
    h_wait[r]        := false;
    h_retire[r]      := false;
  End;
  bg_snp   := false;
  h_busy   := false;
  h_ext    := false;
  h_req    := DUT_ID;
  h_op     := tx_None;
  h_ext_op := ext_None;
  h_dirty  := false;
End;

---------------------------------------------------------------------------
-- (1) Software-driven request injection
---------------------------------------------------------------------------

Ruleset r : RNFid Do
Ruleset op : SwSlot Do
  Rule "SW_enqueue"
    sw_queue[r] = sw_None & op != sw_None & SwEnabledFor(r, op)
  ==>
  Begin
    sw_queue[r] := op;
  End;
EndRuleset;
EndRuleset;

---------------------------------------------------------------------------
-- (2) RN-F dispatches sw_queue into a TX REQ.
--
-- Ported from rnf_fsm.m.  The only addition is the last line of each
-- coherent issue rule: h_wait[r] := true, i.e. "the REQ is now at the
-- HN-F, queued behind the line lock".  That flag is what makes the CAM
-- hazard a first-class state instead of an assumption.
---------------------------------------------------------------------------

Ruleset r : RNFid Do

  -- ReadClean: I-state only (otherwise it is a local hit).
  Rule "Issue_ReadClean"
    sw_queue[r] = sw_ReadClean & l1[r] = L1_I &
    tx_phase[r] = TX_IDLE & rx_snp[r] = rx_None
  ==>
  Begin
    tx_op[r] := tx_ReadClean; tx_phase[r] := TX_AWAIT_RSP;
    tx_expcompack[r] := true;
    sw_queue[r] := sw_None;
    h_wait[r] := true;
  End;

  Rule "Issue_ReadUnique_from_I"
    sw_queue[r] = sw_ReadUnique & l1[r] = L1_I &
    tx_phase[r] = TX_IDLE & rx_snp[r] = rx_None
  ==>
  Begin
    tx_op[r] := tx_ReadUnique; tx_phase[r] := TX_AWAIT_RSP;
    tx_expcompack[r] := true;
    sw_queue[r] := sw_None;
    h_wait[r] := true;
  End;

  -- SC -> UC upgrade.  The RTL performs it by re-issuing ReadUnique;
  -- CHIE_MAKEUNIQUE is assigned nowhere in the L1.5.
  Rule "Issue_ReadUnique_from_SC"
    sw_queue[r] = sw_ReadUnique & l1[r] = L1_SC &
    tx_phase[r] = TX_IDLE & rx_snp[r] = rx_None
  ==>
  Begin
    tx_op[r] := tx_ReadUnique; tx_phase[r] := TX_AWAIT_RSP;
    tx_expcompack[r] := true;
    sw_queue[r] := sw_None;
    h_wait[r] := true;
  End;

  -- cbo.inval: pure core-side L1D self-invalidate.  No MESI write, no
  -- dcache op, no NOC1/NOC3 request -- the L1.5 line including dirty
  -- data is untouched in every state, so l1 does NOT change.
  Rule "SW_drain_CleanInvalid"
    sw_queue[r] = sw_CleanInvalid &
    tx_phase[r] = TX_IDLE & rx_snp[r] = rx_None
  ==>
  Begin
    sw_queue[r] := sw_None;
  End;

  -- cbo.flush on a dirty line: serviced by the NOC3 writeback path as
  -- WriteBackFull (copyback, expcompack=0), not as a dataless CMO.
  Rule "Issue_CleanShared_dirty"
    sw_queue[r] = sw_CleanShared & IsDirty(l1[r]) &
    tx_phase[r] = TX_IDLE & rx_snp[r] = rx_None
  ==>
  Begin
    tx_op[r] := tx_WriteBackFull; tx_phase[r] := TX_AWAIT_RSP;
    tx_expcompack[r] := false;
    sw_queue[r] := sw_None;
    lr_valid[r] := false;
    h_wait[r] := true;
  End;

  -- cbo.flush on a clean line: no CHI traffic, but the line still goes
  -- Invalid (LINE_FLUSH applies INVALIDATE_FLUSH_WAY_IF_MES on every
  -- valid state, not just M).
  Rule "SW_drain_CleanShared_clean"
    sw_queue[r] = sw_CleanShared & !IsDirty(l1[r]) &
    tx_phase[r] = TX_IDLE & rx_snp[r] = rx_None
  ==>
  Begin
    l1[r] := L1_I;
    lr_valid[r] := false;
    sw_queue[r] := sw_None;
  End;

  -- Atomics: issue from any L1 state; the HN-F performs the RMW and the
  -- RN-F does not cache the result.
  --
  -- FIDELITY NOTE (inherited from rnf_fsm.m, deliberately not "fixed"):
  -- the requester does not invalidate its own copy here, so a local
  -- copy can survive an atomic that mutates memory.  This model carries
  -- no data values, so nothing detects it.  Changing it would be
  -- inventing DUT behaviour rather than modelling it -- if the RTL does
  -- self-invalidate, confirm that first and change both models together.
  Rule "Issue_AtomicLoad"
    sw_queue[r] = sw_AtomicLoad &
    tx_phase[r] = TX_IDLE & rx_snp[r] = rx_None
  ==>
  Begin
    tx_op[r] := tx_AtomicLoad; tx_phase[r] := TX_AWAIT_RSP;
    tx_expcompack[r] := false;
    sw_queue[r] := sw_None;
    h_wait[r] := true;
  End;

  Rule "Issue_AtomicStore"
    sw_queue[r] = sw_AtomicStore &
    tx_phase[r] = TX_IDLE & rx_snp[r] = rx_None
  ==>
  Begin
    tx_op[r] := tx_AtomicStore; tx_phase[r] := TX_AWAIT_RSP;
    tx_expcompack[r] := false;
    sw_queue[r] := sw_None;
    h_wait[r] := true;
  End;

  -- ---- Non-cacheable path: bypasses the snoop filter AND the lock ----
  -- hnf_mshr_bypass.  No h_wait, so NC traffic overlaps a coherent
  -- transaction instead of serialising behind it.
  Rule "Issue_NC_Load"
    sw_queue[r] = sw_NC_Load &
    tx_phase[r] = TX_IDLE & rx_snp[r] = rx_None
  ==>
  Begin
    tx_op[r] := tx_ReadNoSnp; tx_phase[r] := TX_AWAIT_RSP;
    tx_expcompack[r] := false;
    sw_queue[r] := sw_None;
  End;

  -- Split per L1 state so each <state, WriteNoSnpPtl> pair is its own
  -- BFS edge; with one state-agnostic rule the UC / UD pairs were
  -- reachable only by luck.
  Rule "Issue_NC_Store_from_I"
    sw_queue[r] = sw_NC_Store & tx_phase[r] = TX_IDLE &
    rx_snp[r] = rx_None & l1[r] = L1_I
  ==>
  Begin
    tx_op[r] := tx_WriteNoSnpPtl; tx_phase[r] := TX_AWAIT_RSP;
    tx_expcompack[r] := false;
    sw_queue[r] := sw_None;
  End;

  Rule "Issue_NC_Store_from_SC"
    sw_queue[r] = sw_NC_Store & tx_phase[r] = TX_IDLE &
    rx_snp[r] = rx_None & l1[r] = L1_SC
  ==>
  Begin
    tx_op[r] := tx_WriteNoSnpPtl; tx_phase[r] := TX_AWAIT_RSP;
    tx_expcompack[r] := false;
    sw_queue[r] := sw_None;
  End;

  Rule "Issue_NC_Store_from_UC"
    sw_queue[r] = sw_NC_Store & tx_phase[r] = TX_IDLE &
    rx_snp[r] = rx_None & l1[r] = L1_UC
  ==>
  Begin
    tx_op[r] := tx_WriteNoSnpPtl; tx_phase[r] := TX_AWAIT_RSP;
    tx_expcompack[r] := false;
    sw_queue[r] := sw_None;
  End;

  Rule "Issue_NC_Store_from_SD"
    sw_queue[r] = sw_NC_Store & tx_phase[r] = TX_IDLE &
    rx_snp[r] = rx_None & l1[r] = L1_SD
  ==>
  Begin
    tx_op[r] := tx_WriteNoSnpPtl; tx_phase[r] := TX_AWAIT_RSP;
    tx_expcompack[r] := false;
    sw_queue[r] := sw_None;
  End;

  Rule "Issue_NC_Store_from_UD"
    sw_queue[r] = sw_NC_Store & tx_phase[r] = TX_IDLE &
    rx_snp[r] = rx_None & l1[r] = L1_UD
  ==>
  Begin
    tx_op[r] := tx_WriteNoSnpPtl; tx_phase[r] := TX_AWAIT_RSP;
    tx_expcompack[r] := false;
    sw_queue[r] := sw_None;
  End;

  -- ---- LR / SC reservation path ----
  -- The L1.5 emits ReadUnique (not ReadClean) for LR_REQUEST: the line
  -- is fetched unique so the following SC commits without an upgrade.
  Rule "Issue_LR_miss"
    sw_queue[r] = sw_LR & l1[r] = L1_I &
    tx_phase[r] = TX_IDLE & rx_snp[r] = rx_None
  ==>
  Begin
    tx_op[r] := tx_ReadUnique; tx_phase[r] := TX_AWAIT_RSP;
    tx_expcompack[r] := true;
    lr_valid[r] := true;
    sw_queue[r] := sw_None;
    h_wait[r] := true;
  End;

  Rule "Issue_LR_hit"
    sw_queue[r] = sw_LR & l1[r] != L1_I &
    tx_phase[r] = TX_IDLE & rx_snp[r] = rx_None
  ==>
  Begin
    lr_valid[r] := true;
    sw_queue[r] := sw_None;
  End;

  Rule "Issue_SC_local"
    sw_queue[r] = sw_SC & lr_valid[r] & IsUnique(l1[r]) &
    tx_phase[r] = TX_IDLE & rx_snp[r] = rx_None
  ==>
  Begin
    If l1[r] = L1_UC Then l1[r] := L1_UD; End;
    lr_valid[r] := false;
    sw_queue[r] := sw_None;
  End;

  Rule "Issue_SC_upgrade"
    sw_queue[r] = sw_SC & lr_valid[r] & IsShared(l1[r]) &
    tx_phase[r] = TX_IDLE & rx_snp[r] = rx_None
  ==>
  Begin
    tx_op[r] := tx_ReadUnique; tx_phase[r] := TX_AWAIT_RSP;
    tx_expcompack[r] := true;
    lr_valid[r] := false;
    sw_queue[r] := sw_None;
    h_wait[r] := true;
  End;

  Rule "Issue_SC_miss"
    sw_queue[r] = sw_SC & lr_valid[r] & l1[r] = L1_I &
    tx_phase[r] = TX_IDLE & rx_snp[r] = rx_None
  ==>
  Begin
    lr_valid[r] := false;
    sw_queue[r] := sw_None;
  End;

  Rule "SW_drain_SC_fail"
    sw_queue[r] = sw_SC & !lr_valid[r]
  ==>
  Begin
    sw_queue[r] := sw_None;
  End;

  -- ---- Local-hit / infeasible-op drains ----
  Rule "SW_local_hit_drain_ReadClean"
    sw_queue[r] = sw_ReadClean & l1[r] != L1_I
  ==>
  Begin
    sw_queue[r] := sw_None;
  End;

  Rule "SW_local_hit_drain_ReadUnique"
    sw_queue[r] = sw_ReadUnique & IsUnique(l1[r])
  ==>
  Begin
    sw_queue[r] := sw_None;
  End;

  -- ---- Set-conflict eviction ----
  Rule "Issue_SetConflict_dirty"
    sw_queue[r] = sw_SetConflict & l1[r] = L1_UD &
    tx_phase[r] = TX_IDLE & rx_snp[r] = rx_None
  ==>
  Begin
    tx_op[r] := tx_WriteBackFull; tx_phase[r] := TX_AWAIT_RSP;
    tx_expcompack[r] := false;
    sw_queue[r] := sw_None;
    lr_valid[r] := false;
    h_wait[r] := true;
  End;

  -- Clean or SD target: silent eviction, no CHI traffic.
  --
  -- NOTE ON A CITATION INHERITED FROM rnf_fsm.m: that model groups SD
  -- here claiming "SD is not a legal WriteBackFull source per CHI E.b
  -- 4.2.2".  Both halves are wrong.  4.2.2 is "Dataless transactions";
  -- WriteBackFull is a Write transaction (4.2.3).  And Table 4-39
  -- (4.7.3) lists WriteBackFull's initial state as "UD, SD" -- SD IS a
  -- legal source.  SD is grouped here because the L1.5 takes the
  -- silent-drop path for it, which is an RTL fact, not a spec one.
  Rule "SW_drain_SetConflict_clean_or_SD"
    sw_queue[r] = sw_SetConflict &
    (l1[r] = L1_UC | l1[r] = L1_SC | l1[r] = L1_SD) &
    tx_phase[r] = TX_IDLE & rx_snp[r] = rx_None
  ==>
  Begin
    l1[r] := L1_I;
    lr_valid[r] := false;
    sw_queue[r] := sw_None;
  End;

  Rule "SW_drain_SetConflict_when_I"
    sw_queue[r] = sw_SetConflict & l1[r] = L1_I
  ==>
  Begin
    sw_queue[r] := sw_None;
  End;

  Rule "StoreHit_UC_to_UD"
    l1[r] = L1_UC & sw_queue[r] = sw_None &
    tx_phase[r] = TX_IDLE & rx_snp[r] = rx_None
  ==>
  Begin
    l1[r] := L1_UD;
  End;

EndRuleset;

---------------------------------------------------------------------------
-- (3) HN-F: accept a waiting REQ into the line lock.
--
-- The whole HN-F "transient lifecycle" is this one rule plus the snoop
-- bookkeeping it sets up.  Everything after it is derived from the
-- requester's own tx_phase.
---------------------------------------------------------------------------

Ruleset r : RNFid Do
  Rule "HNF_accept_REQ"
    !h_busy & h_wait[r]
  ==>
  Begin
    h_busy  := true;
    h_ext   := false;
    h_req   := r;
    h_op    := tx_op[r];
    h_wait[r] := false;
    h_dirty := false;
    -- Snoop every OTHER agent the directory says holds the line.
    -- The requester is never self-snooped.  This follows from the
    -- one-transaction-per-line lock rather than from a single quotable
    -- clause; it is consistent with 4.11.2 ("once a completion is sent
    -- ... must not send a Snoop request to the same cache line until it
    -- receives a CompAck / WriteData") and with the RespSepData rule in
    -- 2.9 ("Home, before sending RespSepData ... must ensure that no
    -- Snoop transactions are outstanding to that Requester to the same
    -- address").  NOT 4.7.4 -- that section is "Atomic transactions".
    If SnpOfTx(tx_op[r]) != rx_None Then
      For r2 : RNFid Do
        If r2 != r & l1[r2] != L1_I Then h_snp_owed[r2] := true; End;
      End;
    End;
  End;
EndRuleset;

---------------------------------------------------------------------------
-- (4) Abstract external requester -- the snoop-opcode source.
---------------------------------------------------------------------------

Ruleset op : ExtOp Do
  Rule "Ext_REQ_begin"
    !h_busy & op != ext_None & ExtOpEnabled(op) &
    Exists r : RNFid Do l1[r] != L1_I End
  ==>
  Begin
    h_busy   := true;
    h_ext    := true;
    h_ext_op := op;
    h_op     := tx_None;
    h_dirty  := false;
    For r : RNFid Do
      If l1[r] != L1_I Then h_snp_owed[r] := true; End;
    End;
  End;
EndRuleset;

Rule "Ext_REQ_complete"
  h_busy & h_ext & NumSnoopOwed() = 0
==>
Begin
  -- The external agent takes the line (or the CMO retires it); any
  -- dirty data handed up is absorbed into L3.
  bg_snp   := false;
  h_busy   := false;
  h_ext    := false;
  h_ext_op := ext_None;
  h_dirty  := false;
End;

---------------------------------------------------------------------------
-- (5) Env_Snp_* -- snoop DELIVERY to a snoopee.
--
-- Split from the HN-F's snoop *decision* (section 3) so the snoop can
-- land while the snoopee has its own REQ outstanding.  That split is
-- the whole reason this model can express race cells hnf_fsm_v2 cannot:
-- there, snoop-send and snoop-arrive are the same event.
--
-- The opcode is derived, never chosen: SnpOfTx(h_op) for an RN-F-sourced
-- transaction, SnpOfExt(h_ext_op) for the external one.
---------------------------------------------------------------------------

Ruleset r : RNFid Do

  Rule "Env_Snp_deliver"
    h_busy & h_snp_owed[r] & rx_snp[r] = rx_None & !RtsEnabled()
  ==>
  Begin
    If h_ext Then rx_snp[r] := SnpOfExt(h_ext_op);
             Else rx_snp[r] := SnpOfTx(h_op); End;
    rx_resp_owed[r] := true;
    rx_rettosrc[r]  := false;
  End;

  -- RetToSrc=1 variant.  Guarded by RtsEnabled() exactly as in
  -- rnf_fsm.m; with it false the SR_*_D clean-data-return responses
  -- drop out of the reachable set.
  Rule "Env_Snp_deliver_RTS"
    h_busy & h_snp_owed[r] & rx_snp[r] = rx_None & RtsEnabled()
  ==>
  Begin
    If h_ext Then rx_snp[r] := SnpOfExt(h_ext_op);
             Else rx_snp[r] := SnpOfTx(h_op); End;
    rx_resp_owed[r] := true;
    rx_rettosrc[r]  := true;
  End;

EndRuleset;

---------------------------------------------------------------------------
-- (6) RN-F per-(snoop opcode x L1 state) decision table.
--
-- Ported from rnf_fsm.m.  Additions: clearing h_snp_owed[r], and
-- setting h_dirty when the response passes dirty data up.  h_dirty is
-- what later selects Env_CompData_dirty over Env_CompData_clean --
-- the causal link that the free-environment model does not have.
---------------------------------------------------------------------------

Ruleset r : RNFid Do

  -- ---- SnpClean ----
  Rule "Snp_SnpClean_from_UD"
    rx_snp[r] = rx_SnpClean & rx_resp_owed[r] & l1[r] = L1_UD
  ==>
  Begin
    l1[r] := L1_SC;                       -- SnpRespData_SC_PD
    -- Latch dirty ONLY when a requester is waiting for it.  On an
    -- external (agentless) transaction there is nobody to forward it
    -- to, so the HN-F pushes it straight to L3; holding it would model
    -- the HN-F sitting on stale-dirty while the snoopee -- left
    -- writable by SnpShared -- store-hits back to dirty.
    If !h_ext Then h_dirty := true; End;
    rx_snp[r] := rx_None; rx_resp_owed[r] := false;
    rx_rettosrc[r] := false; lr_valid[r] := false;
    h_snp_owed[r] := false;
  End;

  Rule "Snp_SnpClean_from_UC"
    rx_snp[r] = rx_SnpClean & rx_resp_owed[r] & l1[r] = L1_UC
  ==>
  Begin
    l1[r] := L1_SC;                       -- SnpResp_SC
    rx_snp[r] := rx_None; rx_resp_owed[r] := false;
    rx_rettosrc[r] := false; lr_valid[r] := false;
    h_snp_owed[r] := false;
  End;

  Rule "Snp_SnpClean_from_SD"
    rx_snp[r] = rx_SnpClean & rx_resp_owed[r] & l1[r] = L1_SD
  ==>
  Begin
    l1[r] := L1_SC;                       -- SnpRespData_SC_PD
    -- Latch dirty ONLY when a requester is waiting for it.  On an
    -- external (agentless) transaction there is nobody to forward it
    -- to, so the HN-F pushes it straight to L3; holding it would model
    -- the HN-F sitting on stale-dirty while the snoopee -- left
    -- writable by SnpShared -- store-hits back to dirty.
    If !h_ext Then h_dirty := true; End;
    rx_snp[r] := rx_None; rx_resp_owed[r] := false;
    rx_rettosrc[r] := false; lr_valid[r] := false;
    h_snp_owed[r] := false;
  End;

  Rule "Snp_SnpClean_from_SC"
    rx_snp[r] = rx_SnpClean & rx_resp_owed[r] & l1[r] = L1_SC
  ==>
  Begin
    rx_snp[r] := rx_None; rx_resp_owed[r] := false;
    rx_rettosrc[r] := false; lr_valid[r] := false;
    h_snp_owed[r] := false;
  End;

  -- ---- SnpUnique ----
  Rule "Snp_SnpUnique_from_UD"
    rx_snp[r] = rx_SnpUnique & rx_resp_owed[r] & l1[r] = L1_UD
  ==>
  Begin
    l1[r] := L1_I;                        -- SnpRespData_I_PD
    -- Latch dirty ONLY when a requester is waiting for it.  On an
    -- external (agentless) transaction there is nobody to forward it
    -- to, so the HN-F pushes it straight to L3; holding it would model
    -- the HN-F sitting on stale-dirty while the snoopee -- left
    -- writable by SnpShared -- store-hits back to dirty.
    If !h_ext Then h_dirty := true; End;
    rx_snp[r] := rx_None; rx_resp_owed[r] := false;
    rx_rettosrc[r] := false; lr_valid[r] := false;
    h_snp_owed[r] := false;
  End;

  Rule "Snp_SnpUnique_from_UC"
    rx_snp[r] = rx_SnpUnique & rx_resp_owed[r] & l1[r] = L1_UC
  ==>
  Begin
    l1[r] := L1_I;
    rx_snp[r] := rx_None; rx_resp_owed[r] := false;
    rx_rettosrc[r] := false; lr_valid[r] := false;
    h_snp_owed[r] := false;
  End;

  Rule "Snp_SnpUnique_from_SD"
    rx_snp[r] = rx_SnpUnique & rx_resp_owed[r] & l1[r] = L1_SD
  ==>
  Begin
    l1[r] := L1_I;
    -- Latch dirty ONLY when a requester is waiting for it.  On an
    -- external (agentless) transaction there is nobody to forward it
    -- to, so the HN-F pushes it straight to L3; holding it would model
    -- the HN-F sitting on stale-dirty while the snoopee -- left
    -- writable by SnpShared -- store-hits back to dirty.
    If !h_ext Then h_dirty := true; End;
    rx_snp[r] := rx_None; rx_resp_owed[r] := false;
    rx_rettosrc[r] := false; lr_valid[r] := false;
    h_snp_owed[r] := false;
  End;

  Rule "Snp_SnpUnique_from_SC"
    rx_snp[r] = rx_SnpUnique & rx_resp_owed[r] & l1[r] = L1_SC
  ==>
  Begin
    l1[r] := L1_I;
    rx_snp[r] := rx_None; rx_resp_owed[r] := false;
    rx_rettosrc[r] := false; lr_valid[r] := false;
    h_snp_owed[r] := false;
  End;

  -- ---- SnpMakeInvalid ----
  -- Never carries dirty data back; if the snoopee was dirty the data is
  -- dropped, because the causer (MakeUnique / CleanUnique / atomic)
  -- either does not need it or refetches via L3.  h_dirty stays clear.
  Rule "Snp_SnpMakeInvalid_any"
    rx_snp[r] = rx_SnpMakeInvalid & rx_resp_owed[r] & l1[r] != L1_I
  ==>
  Begin
    l1[r] := L1_I;
    rx_snp[r] := rx_None; rx_resp_owed[r] := false;
    rx_rettosrc[r] := false; lr_valid[r] := false;
    h_snp_owed[r] := false;
  End;

  -- ---- SnpCleanInvalid ----
  Rule "Snp_SnpCleanInvalid_from_dirty"
    rx_snp[r] = rx_SnpCleanInvalid & rx_resp_owed[r] & IsDirty(l1[r])
  ==>
  Begin
    l1[r] := L1_I;
    -- Latch dirty ONLY when a requester is waiting for it.  On an
    -- external (agentless) transaction there is nobody to forward it
    -- to, so the HN-F pushes it straight to L3; holding it would model
    -- the HN-F sitting on stale-dirty while the snoopee -- left
    -- writable by SnpShared -- store-hits back to dirty.
    If !h_ext Then h_dirty := true; End;
    rx_snp[r] := rx_None; rx_resp_owed[r] := false;
    rx_rettosrc[r] := false; lr_valid[r] := false;
    h_snp_owed[r] := false;
  End;

  Rule "Snp_SnpCleanInvalid_from_clean"
    rx_snp[r] = rx_SnpCleanInvalid & rx_resp_owed[r] &
    (l1[r] = L1_UC | l1[r] = L1_SC)
  ==>
  Begin
    l1[r] := L1_I;
    rx_snp[r] := rx_None; rx_resp_owed[r] := false;
    rx_rettosrc[r] := false; lr_valid[r] := false;
    h_snp_owed[r] := false;
  End;

  -- ---- SnpShared ----
  Rule "Snp_SnpShared_from_dirty"
    rx_snp[r] = rx_SnpShared & rx_resp_owed[r] & IsDirty(l1[r])
  ==>
  Begin
    If l1[r] = L1_UD Then l1[r] := L1_UC; Else l1[r] := L1_SC; End;
    -- Latch dirty ONLY when a requester is waiting for it.  On an
    -- external (agentless) transaction there is nobody to forward it
    -- to, so the HN-F pushes it straight to L3; holding it would model
    -- the HN-F sitting on stale-dirty while the snoopee -- left
    -- writable by SnpShared -- store-hits back to dirty.
    If !h_ext Then h_dirty := true; End;
    rx_snp[r] := rx_None; rx_resp_owed[r] := false;
    rx_rettosrc[r] := false; lr_valid[r] := false;
    h_snp_owed[r] := false;
  End;

  Rule "Snp_SnpShared_from_clean"
    rx_snp[r] = rx_SnpShared & rx_resp_owed[r] &
    (l1[r] = L1_UC | l1[r] = L1_SC)
  ==>
  Begin
    If l1[r] = L1_UC Then l1[r] := L1_SC; End;
    rx_snp[r] := rx_None; rx_resp_owed[r] := false;
    rx_rettosrc[r] := false; lr_valid[r] := false;
    h_snp_owed[r] := false;
  End;

  -- ---- Snoop arrives but the line is already I ----
  -- The snoopee dropped its copy (silent clean eviction, or an
  -- invalidating snoop from an earlier transaction) between the HN-F's
  -- directory lookup and the snoop landing.  Per CHI E.b it answers
  -- SnpResp_I.  This is the snoop-filter imprecision the composed model
  -- gets for free -- and it is real: silent clean eviction is legal.
  Rule "Snp_any_from_I"
    rx_snp[r] != rx_None & rx_resp_owed[r] & l1[r] = L1_I
  ==>
  Begin
    rx_snp[r] := rx_None; rx_resp_owed[r] := false;
    rx_rettosrc[r] := false; lr_valid[r] := false;
    h_snp_owed[r] := false;
  End;

EndRuleset;

---------------------------------------------------------------------------
-- (7) Env_* -- HN-F response flits to the requester.
--
-- This is the section the whole model exists for.  Compare against
-- rnf_fsm.m: there, every one of these rules has a guard mentioning
-- only tx_phase and tx_op, so the environment picks freely.  Here each
-- guard also carries the HN-F's own preconditions --
--   h_busy & h_req = r      this agent actually owns the transaction
--   NumSnoopOwed() = 0      every snoopee has answered first
--   h_dirty / !h_dirty      clean-vs-dirty is a consequence, not a coin
-- so an Env_* event can only appear in a trace where a real HN-F would
-- have produced it.
---------------------------------------------------------------------------

Ruleset r : RNFid Do

  -- ---- Read-shape: CompData ----
  Rule "Env_CompData_clean"
    h_busy & !h_ext & h_req = r & NumSnoopOwed() = 0 &
    tx_phase[r] = TX_AWAIT_RSP &
    (tx_op[r] = tx_ReadClean | tx_op[r] = tx_ReadUnique) &
    !h_dirty
  ==>
  Begin
    tx_phase[r] := TX_AWAIT_COMPACK_CLEAN;
  End;

  -- Reachable only after a snoopee passed dirty data up (SR_*_PD).
  Rule "Env_CompData_dirty"
    h_busy & !h_ext & h_req = r & NumSnoopOwed() = 0 &
    tx_phase[r] = TX_AWAIT_RSP &
    (tx_op[r] = tx_ReadClean | tx_op[r] = tx_ReadUnique) &
    h_dirty
  ==>
  Begin
    tx_phase[r] := TX_AWAIT_COMPACK_DIRTY;
  End;

  -- ---- Write-shape: DBIDResp then Comp, or the combined form ----
  --
  -- CHI E.b 4.11.1: "The only response that can be received for a
  -- CopyBack request, while a Snoop response to a Snoop request to the
  -- same address is pending, is a RetryAck."  So a CopyBack's DBIDResp
  -- waits for every snoopee -- NumSnoopOwed() = 0.
  Rule "Env_DBIDResp_for_Write"
    h_busy & !h_ext & h_req = r & NumSnoopOwed() = 0 &
    tx_phase[r] = TX_AWAIT_RSP & tx_op[r] = tx_WriteBackFull
  ==>
  Begin
    tx_phase[r] := TX_AWAIT_DATA_SEND;
  End;

  -- Atomics are the documented exception.  CHI E.b 4.11.2: "While a
  -- Snoop transaction response is pending, the only transaction
  -- responses that are permitted to be sent to the same address are:
  -- ... RetryAck and DBIDResp for a WriteUnique and Atomics."
  -- So DBIDResp for an atomic MAY be sent before the snoopees have
  -- answered.  Requiring NumSnoopOwed() = 0 here (as the CopyBack rule
  -- does) was stricter than the spec and silently dropped the
  -- interleaving where the requester ships atomic write data while a
  -- peer's SnpResp is still outstanding.
  Rule "Env_DBIDResp_for_Atomic"
    h_busy & !h_ext & h_req = r &
    tx_phase[r] = TX_AWAIT_RSP &
    (tx_op[r] = tx_AtomicLoad | tx_op[r] = tx_AtomicStore)
  ==>
  Begin
    tx_phase[r] := TX_AWAIT_DATA_SEND;
  End;

  Rule "Env_CompDBIDResp_for_Write"
    h_busy & !h_ext & h_req = r & NumSnoopOwed() = 0 &
    tx_phase[r] = TX_AWAIT_RSP & tx_op[r] = tx_WriteBackFull
  ==>
  Begin
    tx_phase[r] := TX_AWAIT_DATA_SEND;
  End;

  -- ---- Atomic completion ----
  -- Only the DBIDResp is permitted to overtake the snoop responses
  -- (4.11.2); the completion itself still waits for every snoopee, and
  -- it is what releases the lock -- so NumSnoopOwed() = 0 belongs here
  -- rather than on the DBIDResp.  Without it the lock could be released
  -- with a snoop still owed, which SnoopOwedOnlyWhileBusy would catch.
  Rule "Env_CompData_for_AtomicLoad"
    h_retire[r] & tx_phase[r] = TX_AWAIT_COMP & tx_op[r] = tx_AtomicLoad
  ==>
  Begin
    tx_op[r] := tx_None; tx_phase[r] := TX_IDLE;
    tx_expcompack[r] := false;
    h_retire[r] := false;
  End;

  Rule "Env_Comp_for_AtomicStore"
    h_retire[r] & tx_phase[r] = TX_AWAIT_COMP & tx_op[r] = tx_AtomicStore
  ==>
  Begin
    tx_op[r] := tx_None; tx_phase[r] := TX_IDLE;
    tx_expcompack[r] := false;
    h_retire[r] := false;
  End;

  -- ---- Writeback completion ----
  -- The copyback lands in L3, so the HN-F is left clean: h_dirty stays
  -- false throughout the writeback.  The writer keeps its UD copy until
  -- this Comp, matching rnf_fsm.m -- and it is the lock holder, so it
  -- can never be snooped for its own writeback in that window.
  Rule "Env_Comp_for_WriteBack"
    h_retire[r] & tx_phase[r] = TX_AWAIT_COMP & tx_op[r] = tx_WriteBackFull
  ==>
  Begin
    tx_op[r] := tx_None; tx_phase[r] := TX_IDLE;
    tx_expcompack[r] := false;
    h_retire[r] := false;
  End;

  -- ---- Non-cacheable: no lock, no directory effect ----
  Rule "Env_CompData_for_NC_Load"
    tx_phase[r] = TX_AWAIT_RSP & tx_op[r] = tx_ReadNoSnp
  ==>
  Begin
    tx_op[r] := tx_None; tx_phase[r] := TX_IDLE;
    tx_expcompack[r] := false;
  End;

  Rule "Env_DBIDResp_for_NC_Store"
    tx_phase[r] = TX_AWAIT_RSP & tx_op[r] = tx_WriteNoSnpPtl
  ==>
  Begin
    tx_phase[r] := TX_AWAIT_DATA_SEND;
  End;

  Rule "Env_Comp_for_NC_Store"
    tx_phase[r] = TX_AWAIT_COMP & tx_op[r] = tx_WriteNoSnpPtl
  ==>
  Begin
    tx_op[r] := tx_None; tx_phase[r] := TX_IDLE;
    tx_expcompack[r] := false;
  End;

EndRuleset;

---------------------------------------------------------------------------
-- (7b) HN-F retires a CopyBack / Atomic once it holds the WriteData.
--
-- 4.11.2: "the HN-F must not send a Snoop request to the same cache line
-- until it receives ... a WriteData response for CopyBack and Atomic
-- requests."  Receiving the WriteData is the release point, NOT the
-- Comp the HN-F later sends back.  Modelling the release at completion
-- (as this model first did) forbids a legal window -- and it is one the
-- existing prefix-shared vector set deliberately targets: 50 of its 427
-- hub states are "TX_AWAIT_COMP with a snoop pending".
--
-- The snoop responses this transaction is still collecting are a
-- separate matter, so the retire waits on NumSnoopOwed() = 0.
---------------------------------------------------------------------------

Ruleset r : RNFid Do
  Rule "HNF_retire_write"
    h_busy & !h_ext & h_req = r & NumSnoopOwed() = 0 &
    tx_phase[r] = TX_AWAIT_COMP & !h_retire[r] &
    (tx_op[r] = tx_WriteBackFull |
     tx_op[r] = tx_AtomicLoad | tx_op[r] = tx_AtomicStore)
  ==>
  Begin
    h_busy := false; h_op := tx_None; h_dirty := false;
    h_retire[r] := true;
  End;
EndRuleset;

---------------------------------------------------------------------------
-- (8) RN-F-sourced completions: write data and CompAck.
---------------------------------------------------------------------------

Ruleset r : RNFid Do

  -- CHI E.b 4.11.1, CopyBack requirements:
  --   "The cache state in the WriteData response must be the state of
  --    the cache line AFTER the snoop request is processed, not the
  --    state at the time of sending the CopyBack request."
  --   "A Request Node is permitted to not send valid CopyBack Data, if
  --    the cache line state after the Snoop response is sent is I or
  --    SC.  The cache state in the WriteData response ... must be I and
  --    all byte enables must be deasserted and the corresponding data
  --    must be set to zero."
  -- 5.6.1's worked example is precisely this: UD -> SnpShared -> SC ->
  -- CopyBackWrData_SC.
  --
  -- Split by the state actually reported so each spec outcome is its
  -- own BFS edge the generator can aim at.  With one state-agnostic
  -- rule the snooped-CopyBack outcomes were reachable but not
  -- addressable, which is how the 5.6.1 case goes untested.
  -- One rule per row of Table 4-39's WriteBackFull block, keyed on the
  -- "Before WriteData response" column.  Initial state UD or SD; final
  -- state always I:
  --
  --     before WriteData   WriteData response
  --     UD                 CBWrData_UD_PD
  --     UC                 CBWrData_UC
  --     SD                 CBWrData_SD_PD
  --     SC                 CBWrData_SC
  --     I                  CBWrData_I
  --
  -- Five distinct wire-level responses, so five distinct BFS edges --
  -- a coarser split would leave the generator unable to aim at the
  -- individual CBWrData_* opcodes, which is the whole point.  The split
  -- is total over L1State; a state with no enabled rule would surface
  -- as a rumur deadlock.
  Rule "Send_CopyBackWrData_UD_PD"
    tx_phase[r] = TX_AWAIT_DATA_SEND & tx_op[r] = tx_WriteBackFull &
    l1[r] = L1_UD
  ==>
  Begin
    tx_phase[r] := TX_AWAIT_COMP;
    -- The line is NOT dropped here.  Table 4-39's "Final" column is the
    -- end-of-transaction state; it does not pin whether the RN gives the
    -- line up at WriteData or at Comp.  rnf_fsm.m drops it at Comp
    -- (Env_Comp_for_WriteBack), and dropping it earlier here made states
    -- like <UD, AWAIT_COMP, WriteBackFull> unreachable -- 24 of the
    -- existing prefix-shared hub states target exactly those.  Keep the
    -- two models agreeing until the RTL settles it.
  End;

  Rule "Send_CopyBackWrData_SD_PD"
    tx_phase[r] = TX_AWAIT_DATA_SEND & tx_op[r] = tx_WriteBackFull &
    l1[r] = L1_SD
  ==>
  Begin
    tx_phase[r] := TX_AWAIT_COMP;
    -- The line is NOT dropped here.  Table 4-39's "Final" column is the
    -- end-of-transaction state; it does not pin whether the RN gives the
    -- line up at WriteData or at Comp.  rnf_fsm.m drops it at Comp
    -- (Env_Comp_for_WriteBack), and dropping it earlier here made states
    -- like <UD, AWAIT_COMP, WriteBackFull> unreachable -- 24 of the
    -- existing prefix-shared hub states target exactly those.  Keep the
    -- two models agreeing until the RTL settles it.
  End;

  -- Snoop downgraded the line and took the dirty data with it.  5.6.1's
  -- worked example is exactly the SC row: UD -> SnpShared -> SC ->
  -- CopyBackWrData_SC.
  Rule "Send_CopyBackWrData_UC"
    tx_phase[r] = TX_AWAIT_DATA_SEND & tx_op[r] = tx_WriteBackFull &
    l1[r] = L1_UC
  ==>
  Begin
    tx_phase[r] := TX_AWAIT_COMP;
    -- The line is NOT dropped here.  Table 4-39's "Final" column is the
    -- end-of-transaction state; it does not pin whether the RN gives the
    -- line up at WriteData or at Comp.  rnf_fsm.m drops it at Comp
    -- (Env_Comp_for_WriteBack), and dropping it earlier here made states
    -- like <UD, AWAIT_COMP, WriteBackFull> unreachable -- 24 of the
    -- existing prefix-shared hub states target exactly those.  Keep the
    -- two models agreeing until the RTL settles it.
  End;

  Rule "Send_CopyBackWrData_SC"
    tx_phase[r] = TX_AWAIT_DATA_SEND & tx_op[r] = tx_WriteBackFull &
    l1[r] = L1_SC
  ==>
  Begin
    tx_phase[r] := TX_AWAIT_COMP;
    -- The line is NOT dropped here.  Table 4-39's "Final" column is the
    -- end-of-transaction state; it does not pin whether the RN gives the
    -- line up at WriteData or at Comp.  rnf_fsm.m drops it at Comp
    -- (Env_Comp_for_WriteBack), and dropping it earlier here made states
    -- like <UD, AWAIT_COMP, WriteBackFull> unreachable -- 24 of the
    -- existing prefix-shared hub states target exactly those.  Keep the
    -- two models agreeing until the RTL settles it.
  End;

  -- Snoop took the line away entirely.  4.11.1: the RN is permitted to
  -- send no valid CopyBack data here -- state I, byte enables
  -- deasserted, data zero.
  Rule "Send_CopyBackWrData_I"
    tx_phase[r] = TX_AWAIT_DATA_SEND & tx_op[r] = tx_WriteBackFull &
    l1[r] = L1_I
  ==>
  Begin
    tx_phase[r] := TX_AWAIT_COMP;
    -- The line is NOT dropped here.  Table 4-39's "Final" column is the
    -- end-of-transaction state; it does not pin whether the RN gives the
    -- line up at WriteData or at Comp.  rnf_fsm.m drops it at Comp
    -- (Env_Comp_for_WriteBack), and dropping it earlier here made states
    -- like <UD, AWAIT_COMP, WriteBackFull> unreachable -- 24 of the
    -- existing prefix-shared hub states target exactly those.  Keep the
    -- two models agreeing until the RTL settles it.
  End;

  -- Atomics and the non-cacheable write path: no cached line to report.
  -- An atomic's WriteData releases the line for the same reason as a
  -- CopyBack's; NC never held it.
  Rule "Send_WriteData"
    tx_phase[r] = TX_AWAIT_DATA_SEND & tx_op[r] != tx_WriteBackFull
  ==>
  Begin
    tx_phase[r] := TX_AWAIT_COMP;
  End;

  -- CompAck releases the line lock.  Peers were already moved to their
  -- post-snoop states by their own SnpResp rules, so the terminal
  -- directory update touches only the requester -- no reaching into
  -- another agent's cache state from here.
  Rule "Send_CompAck_after_clean"
    tx_phase[r] = TX_AWAIT_COMPACK_CLEAN & tx_expcompack[r] &
    h_busy & !h_ext & h_req = r
  ==>
  Begin
    Switch tx_op[r]
      Case tx_ReadClean:  l1[r] := L1_SC;
      Case tx_ReadUnique: l1[r] := L1_UC;
    EndSwitch;
    tx_op[r] := tx_None; tx_phase[r] := TX_IDLE;
    tx_expcompack[r] := false;
    -- CompAck is what releases the line for a Read (4.11.2).
    h_busy := false; h_op := tx_None; h_dirty := false;
  End;

  -- Dirty data handed to the requester: ownership transfers, so
  -- h_dirty clears here rather than being written back to L3.
  Rule "Send_CompAck_after_dirty"
    tx_phase[r] = TX_AWAIT_COMPACK_DIRTY & tx_expcompack[r] &
    h_busy & !h_ext & h_req = r
  ==>
  Begin
    Switch tx_op[r]
      Case tx_ReadClean:  l1[r] := L1_SD;
      Case tx_ReadUnique: l1[r] := L1_UD;
    EndSwitch;
    tx_op[r] := tx_None; tx_phase[r] := TX_IDLE;
    tx_expcompack[r] := false;
    h_busy := false; h_op := tx_None; h_dirty := false;
  End;

EndRuleset;

---------------------------------------------------------------------------
-- (9) Cross-line background activity at the DUT.
--
-- CHI E.b 4.11.1: "An RN-F node must respond to received Snoop requests
-- ... in a timely manner without creating any Protocol layer dependency
-- on completion of outstanding requests."  That is a CROSS-LINE
-- property: the snoop being answered is for a different line than the
-- request that is outstanding.  A single-line model cannot state it.
--
-- Unlike every other Env_* rule in this model, the arrival below is
-- FREE non-determinism.  That is deliberate and is not a relapse into
-- rnf_fsm.m's adversarial environment: the transaction that causes a
-- foreign snoop lives on a line this model does not track, so from this
-- line's point of view an arbitrary foreign snoop is legal-but-uncaused,
-- not illegal.  Freedom on THIS line would produce traces a real HN-F
-- could never emit; freedom on an unmodelled line does not.
--
-- Five arrival rules, one per snoop opcode, all reaching the same
-- successor state.  The opcode is not stored -- the other line's
-- coherence is not modelled, so nothing reads it -- but naming it gives
-- the generator five distinct aim points at zero state cost.  Measured:
-- this section multiplies the reachable set by EXACTLY 2, which is the
-- honest signal that it adds reachable interleavings and no new
-- checkable property.
--
-- KNOB (not wired, deliberately): if the L1.5 serialises snoop handling
-- against an outstanding fill, add `& !bg_snp` to the Issue_* guards in
-- section (2).  That would encode a real RTL property and shrink the
-- product below 2x.  Left unwired because whether it does so is an RTL
-- fact that has not been confirmed -- do not guess it.
--
-- The response rule must stay unguarded beyond bg_snp: that IS the
-- 4.11.1 requirement.  If coupling is ever added above, it must not be
-- added here.
---------------------------------------------------------------------------

Rule "Env_Snp_ALT_SnpClean"        !bg_snp ==> Begin bg_snp := true; End;
Rule "Env_Snp_ALT_SnpUnique"       !bg_snp ==> Begin bg_snp := true; End;
Rule "Env_Snp_ALT_SnpMakeInvalid"  !bg_snp ==> Begin bg_snp := true; End;
Rule "Env_Snp_ALT_SnpCleanInvalid" !bg_snp ==> Begin bg_snp := true; End;
Rule "Env_Snp_ALT_SnpShared"       !bg_snp ==> Begin bg_snp := true; End;

-- Answering a foreign snoop never depends on this line's transaction
-- state -- no tx_phase term in the guard.  That is the property.
Rule "Snp_ALT_resp"                 bg_snp ==> Begin bg_snp := false; End;

---------------------------------------------------------------------------
-- Invariants
--
-- RN-F-side ones are rnf_fsm.m's, lifted to every agent.  Coherence
-- ones are hnf_fsm_v2.m's, now evaluated over the detailed L1 states
-- rather than a compressed directory view.
---------------------------------------------------------------------------

-- ---- Per-agent TX lifecycle (rnf_fsm.m) ----
Invariant "TxIdleMeansNoOp"
  ForAll r : RNFid Do (tx_phase[r] = TX_IDLE) -> (tx_op[r] = tx_None) End;

Invariant "TxBusyMeansHasOp"
  ForAll r : RNFid Do (tx_phase[r] != TX_IDLE) -> (tx_op[r] != tx_None) End;

Invariant "ExpCompAckOnlyDuringTx"
  ForAll r : RNFid Do tx_expcompack[r] -> (tx_phase[r] != TX_IDLE) End;

Invariant "CompAckOnlyForAckBearing"
  ForAll r : RNFid Do
    ((tx_phase[r] = TX_AWAIT_COMPACK_CLEAN |
      tx_phase[r] = TX_AWAIT_COMPACK_DIRTY) & tx_expcompack[r]) ->
      (tx_op[r] = tx_ReadClean | tx_op[r] = tx_ReadUnique)
  End;

Invariant "DirtyPhaseOnlyForReads"
  ForAll r : RNFid Do
    (tx_phase[r] = TX_AWAIT_COMPACK_DIRTY) ->
      (tx_op[r] = tx_ReadClean | tx_op[r] = tx_ReadUnique)
  End;

Invariant "SnoopOwnedIffPending"
  ForAll r : RNFid Do rx_resp_owed[r] = (rx_snp[r] != rx_None) End;

-- ---- System coherence (hnf_fsm_v2.m) ----
Invariant "AtMostOneUnique"
  NumUnique() <= 1;

Invariant "NoUniqueAndSharedSimultaneously"
  !(NumUnique() > 0 & NumShared() > 0);

Invariant "AtMostOneDirtyOwner"
  NumDirty() <= 1;

Invariant "DirtyOwnershipExclusive"
  !(h_dirty & NumDirty() > 0);

-- ---- HN-F structural (the "only stable states" claim) ----
-- No snoop may be outstanding while the line is unlocked: if this ever
-- fires, the HN-F has grown a transient phase it is not tracking.
Invariant "SnoopOwedOnlyWhileBusy"
  (!h_busy) -> (NumSnoopOwed() = 0);

-- The retiring slot only ever holds an agent whose WriteData is in and
-- whose Comp has not yet been delivered.
Invariant "RetireImpliesAwaitingComp"
  ForAll r : RNFid Do
    h_retire[r] -> (tx_phase[r] = TX_AWAIT_COMP &
                    (tx_op[r] = tx_WriteBackFull |
                     tx_op[r] = tx_AtomicLoad | tx_op[r] = tx_AtomicStore))
  End;

-- The requester is never snooped for its own REQ.  See the note in
-- HNF_accept_REQ: this is the lock's consequence, consistent with
-- 4.11.2, not a direct quote.  (hnf_fsm_v2.m cites "4.7.4 Snoop
-- response handling" for this; in E.b 4.7.4 is "Atomic transactions".)
Invariant "Hazard_NoSelfSnoop"
  (h_busy & !h_ext) -> !h_snp_owed[h_req];

-- A locked line always has an owning opcode.
Invariant "BusyMeansHasOp"
  h_busy -> ((h_ext & h_ext_op != ext_None) | (!h_ext & h_op != tx_None));

-- An agent's REQ is either waiting for the lock or holding it, never
-- both.  Model well-formedness for the h_wait[] queue, whose behaviour
-- follows 5.6.4 (Request-CompAck to HN-F race hazard: "the HN-F detects
-- an address hazard and blocks the processing of the new request until
-- the CompAck response is received").  NOT 4.7.3 -- that section is
-- "Write request transactions".
Invariant "Hazard_RequesterNotAlsoWaiting"
  (h_busy & !h_ext) -> !h_wait[h_req];

-- CHI E.b 4.11.2: "While a Snoop transaction response is pending, the
-- only transaction responses that are permitted to be sent to the same
-- address are: RetryAck for a CopyBack; RetryAck and DBIDResp for a
-- WriteUnique and Atomics; RetryAck and, if applicable, a ReadReceipt
-- for a Read request type; RetryAck for a Dataless request type."
--
-- So a Read's CompData and a CopyBack's DBIDResp must both still be
-- outstanding while any snoopee owes a response -- the requester stays
-- in TX_AWAIT_RSP.  Atomics are the documented exception and are
-- excluded here: their DBIDResp may legitimately overtake the snoop
-- responses (see Env_DBIDResp_for_Atomic).  What is still forbidden for
-- an atomic -- sending the completion early -- is covered by h_busy,
-- since the completion is what releases the lock.
--
-- This invariant previously had no atomic exemption, which made the
-- model stricter than the spec and silently dropped that interleaving.
Invariant "NoResponseBeforeSnoopsResolved"
  ForAll r : RNFid Do
    (h_busy & !h_ext & h_req = r & NumSnoopOwed() > 0 &
     tx_op[r] != tx_AtomicLoad & tx_op[r] != tx_AtomicStore) ->
      (tx_phase[r] = TX_AWAIT_RSP)
  End;
