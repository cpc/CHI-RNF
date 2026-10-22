#!/usr/bin/env python3
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
"""
HN-F test-case generator driven by the Murphi model (Option A).

Uses rumur's symmetry-reduced exploration (the WHOLE POINT of using
Murphi) and tracks the canonical→physical permutation σ per BFS edge,
so the emitted vectors have stable A=RNFid_0 / B=RNFid_1 identity
across the entire path even though canonical position 0 itself flips
between "requester (transient)" and "lex-smallest rnf (stable)".

Output:
  vectors_murphi/<state>__<event>.txt   one per (state, REQ event) target
"""

import argparse
import copy
import os
import re
import subprocess
import sys
import tempfile
from collections import deque

HERE = os.path.dirname(os.path.abspath(__file__))
MURPHI_DIR = os.path.join(HERE, "murphi")
sys.path.insert(0, MURPHI_DIR)
# v2 pipeline: 2-sided FSM with per-snoopee snoop responses.
# The v1 to_dot.py is preserved for the original single-sided model.
import to_dot_v2 as to_dot   # type: ignore

VEC_DIR = os.path.join(HERE, "vectors_murphi")

# Address-space partition (CHI E.b sec 2.4.2):
#  - Coherent subspace:    Murphi-driven test gen targets ADDR_COHERENT.
#    Ops: ReadClean, ReadUnique, MakeUnique, CleanUnique, CleanInvalid,
#    CleanShared, Evict, WriteBackFull, WriteCleanFull. These flow
#    through the HN-F MSHR + snoop filter.
#  - Non-coherent subspace: separate generator (testgen/gen_noncoherent.py
#    — not yet implemented) targets ADDR_NONCOHERENT.
#    Ops: ReadNoSnp, WriteNoSnpFull, WriteNoSnpPtl, ReadOnce. These
#    bypass the snoop filter via hnf_mshr_bypass.
# Mixing the two on the same line is forbidden by CHI E.b sec 2.4.2.
ADDR_COHERENT     = 0x80000200   # default for coherent test vectors
ADDR_NONCOHERENT  = 0xC0000200   # reserved for non-coherent vectors

# Deny only the ops that DO appear in Murphi's OpType but aren't useful
# as terminal targets. After address-space partition, non-coherent ops
# are not in OpType at all, so we don't list them here.
VECTOR_TARGET_DENYLIST = (
    "Evict",   # CHI E.b: clean-line evict; MSHR-bypass, no ALLOC observed
)

NUM_RNF = 2
POS_TAG = {0: "A", 1: "B"}

RULE_TO_REQ_OP = {
    "ReadClean_from_I":                "ReadClean",
    "ReadClean_from_SC_nonsharer":     "ReadClean",
    "ReadClean_from_UC_other":         "ReadClean",
    "ReadUnique_from_I":               "ReadUnique",
    "ReadUnique_from_other_holder":    "ReadUnique",
    "MakeUnique_from_I":               "MakeUnique",
    "MakeUnique_from_shared":          "MakeUnique",
    "CleanUnique_sole_sharer":         "CleanUnique",
    "CleanUnique_with_others":         "CleanUnique",
    "CleanInvalid_when_others_present":"CleanInvalid",
    "Evict_self":                      "Evict",
    "WriteBackFull":                   "WriteBackFull",
    "WriteCleanFull":                  "WriteCleanFull",
    "AtomicLoad_from_I":               "AtomicLoad",
    "AtomicLoad_with_holders":         "AtomicLoad",
    "AtomicStore_from_I":              "AtomicStore",
    "AtomicStore_with_holders":        "AtomicStore",
}


# --------------------------------------------------------------------- #
# Canonical state fingerprint  ↔  state dict
# --------------------------------------------------------------------- #

STATE_RE = re.compile(
    r"rnf=\[(?P<rnf>[^\]]*)\] phase=(?P<phase>\S+) "
    r"inflight=(?P<inflight>\S+) req=(?P<req>\S+) "
    r"pend=\[(?P<pend>[^\]]*)\] "
    r"snpreq=\[(?P<snpreq>[^\]]*)\] snpresp=\[(?P<snpresp>[^\]]*)\] "
    r"hnfdirty=(?P<hnfdirty>\S+)"
)


def parse_fp(fp):
    m = STATE_RE.match(fp)
    if not m:
        return None
    return {
        "rnf":      m.group("rnf").split(","),
        "phase":    m.group("phase"),
        "inflight": m.group("inflight"),
        # canonical req: 'R' means requester at position 0, 'U' = no requester
        "req":      0 if m.group("req") == "R" else None,
        "pend":     m.group("pend").split(","),
        "snpreq":   [v == "true" for v in m.group("snpreq").split(",")],
        "snpresp":  m.group("snpresp").split(","),
        "hnfdirty": m.group("hnfdirty") == "true",
    }


def render_fp(st):
    """Reverse of parse_fp — used to check simulator output against
    rumur's canonical AFTER fingerprint."""
    req_tag = "R" if st["req"] == 0 else "U"
    return (
        f"rnf=[{','.join(st['rnf'])}] phase={st['phase']} "
        f"inflight={st['inflight']} req={req_tag} "
        f"pend=[{','.join(st['pend'])}] "
        f"snpreq=[{','.join('true' if b else 'false' for b in st['snpreq'])}] "
        f"snpresp=[{','.join(st['snpresp'])}] "
        f"hnfdirty={'true' if st['hnfdirty'] else 'false'}"
    )


def canonicalize(st):
    """Apply the same canonical-form rules to_dot.py uses: requester
    always at position 0; otherwise positions sorted by (rnf, pend,
    snpreq, snpresp)."""
    pairs = list(zip(st["rnf"], st["pend"], st["snpreq"], st["snpresp"]))
    if st["req"] is not None and 0 <= st["req"] < NUM_RNF:
        head = [pairs[st["req"]]]
        rest = sorted(pairs[i] for i in range(NUM_RNF) if i != st["req"])
        pairs = head + rest
        new_req = 0
    else:
        pairs = sorted(pairs)
        new_req = None
    out = copy.deepcopy(st)
    out["rnf"]     = [p[0] for p in pairs]
    out["pend"]    = [p[1] for p in pairs]
    out["snpreq"]  = [p[2] for p in pairs]
    out["snpresp"] = [p[3] for p in pairs]
    out["req"]     = new_req
    return out


# --------------------------------------------------------------------- #
# Murphi rule simulator (in Python) — needed to compute per-edge σ.
# Encodes every rule's *state update* (not its guard) verbatim from
# hnf_fsm.m. Kept tiny on purpose; if a rule body changes there, mirror
# it here.
# --------------------------------------------------------------------- #

def num_unique(st):
    return sum(1 for r in st["rnf"] if r in ("RS_UC", "RS_UD"))
def num_shared(st):
    return sum(1 for r in st["rnf"] if r in ("RS_SC", "RS_SD"))
def num_snp_required(st):
    return sum(1 for b in st["snpreq"] if b)


def _enter_snoop(s, actor_pos):
    """Initialize snp_required[r2] = (r2 != actor & rnf[r2] != RS_I);
    clear snp_resp[]. Called on every rule that sets phase := T_SNP."""
    for r2 in range(NUM_RNF):
        s["snpreq"][r2]  = (r2 != actor_pos) and (s["rnf"][r2] != "RS_I")
        s["snpresp"][r2] = "SR_None"


# Map per-snoopee snoop rule names to (post-state, snp_resp, sets_hnf_dirty).
# Indexed by inflight_op and the snoopee's current rnf state.
# Used by simulate_rule for v2's per-snoopee snoop response rules.
_SNP_TABLE = {
    "Snp_SnpClean_from_UD":           ("op_ReadClean",   "RS_SC", "SR_SC_PD", True),
    "Snp_SnpClean_from_UC":           ("op_ReadClean",   "RS_SC", "SR_SC",    False),
    "Snp_SnpClean_from_SD":           ("op_ReadClean",   "RS_SC", "SR_SC_PD", True),
    "Snp_SnpClean_from_SC":           ("op_ReadClean",   None,    "SR_SC",    False),
    "Snp_SnpUnique_from_UD":          ("op_ReadUnique",  "RS_I",  "SR_I_PD",  True),
    "Snp_SnpUnique_from_UC":          ("op_ReadUnique",  "RS_I",  "SR_I_D",   False),
    "Snp_SnpUnique_from_SD":          ("op_ReadUnique",  "RS_I",  "SR_I_PD",  True),
    "Snp_SnpUnique_from_SC":          ("op_ReadUnique",  "RS_I",  "SR_I",     False),
    "Snp_SnpMakeInvalid_any":         (None,             "RS_I",  "SR_I",     False),
    "Snp_SnpCleanInvalid_from_dirty": ("op_CleanInvalid","RS_I",  "SR_I_PD",  True),
    "Snp_SnpCleanInvalid_from_clean": ("op_CleanInvalid","RS_I",  "SR_I",     False),
    "Snp_SnpShared_from_dirty":       ("op_CleanShared", "downgrade_dirty", "SR_SC_PD", True),
    "Snp_SnpShared_from_clean":       ("op_CleanShared", "downgrade_clean", "SR_SC",    False),
}


def simulate_rule(rule, src, actor_pos, queued_op=None):
    """Return un-canonicalized post-state after `rule` fires from
    `actor_pos`. queued_op is required for CAM_hazard_queue_REQ."""
    s = copy.deepcopy(src)

    # ── REQ-from-stable rules ─────────────────────────────────────────
    if rule == "ReadClean_from_I":
        s.update(phase="T_FILL", req=actor_pos, inflight="op_ReadClean")
    elif rule == "ReadUnique_from_I":
        s.update(phase="T_FILL", req=actor_pos, inflight="op_ReadUnique")
    elif rule == "AtomicLoad_from_I":
        s.update(phase="T_FILL", req=actor_pos, inflight="op_AtomicLoad")
    elif rule == "AtomicStore_from_I":
        s.update(phase="T_FILL", req=actor_pos, inflight="op_AtomicStore")
    elif rule == "MakeUnique_from_I":
        s.update(phase="T_ACK",  req=actor_pos, inflight="op_MakeUnique")
    elif rule == "CleanUnique_sole_sharer":
        s.update(phase="T_ACK",  req=actor_pos, inflight="op_CleanUnique")
    elif rule in ("ReadClean_from_SC_nonsharer", "ReadClean_from_UC_other"):
        s.update(phase="T_SNP", req=actor_pos, inflight="op_ReadClean")
        _enter_snoop(s, actor_pos)
    elif rule == "ReadUnique_from_other_holder":
        s.update(phase="T_SNP", req=actor_pos, inflight="op_ReadUnique")
        _enter_snoop(s, actor_pos)
    elif rule == "CleanUnique_with_others":
        s.update(phase="T_SNP", req=actor_pos, inflight="op_CleanUnique")
        _enter_snoop(s, actor_pos)
    elif rule == "MakeUnique_from_shared":
        s.update(phase="T_SNP", req=actor_pos, inflight="op_MakeUnique")
        _enter_snoop(s, actor_pos)
    elif rule == "CleanInvalid_when_others_present":
        s.update(phase="T_SNP", req=actor_pos, inflight="op_CleanInvalid")
        _enter_snoop(s, actor_pos)
    elif rule == "AtomicLoad_with_holders":
        s.update(phase="T_SNP", req=actor_pos, inflight="op_AtomicLoad")
        _enter_snoop(s, actor_pos)
    elif rule == "AtomicStore_with_holders":
        s.update(phase="T_SNP", req=actor_pos, inflight="op_AtomicStore")
        _enter_snoop(s, actor_pos)
    elif rule == "WriteBackFull":
        s["rnf"][actor_pos] = "RS_I"
    elif rule == "WriteCleanFull":
        s["rnf"][actor_pos] = "RS_UC"
    elif rule == "Evict_self":
        s["rnf"][actor_pos] = "RS_I"
    elif rule == "StoreHit_UC_to_UD":
        s["rnf"][actor_pos] = "RS_UD"
    elif rule == "CAM_hazard_queue_REQ":
        if queued_op is None:
            return None
        s["pend"][actor_pos] = queued_op

    # ── Per-snoopee SnpResp* decision rules ────────────────────────────
    elif rule in _SNP_TABLE:
        _expected_op, post, resp, sets_dirty = _SNP_TABLE[rule]
        if post == "downgrade_dirty":
            # SnpShared from dirty: UD -> UC, SD -> SC
            cur = s["rnf"][actor_pos]
            if cur == "RS_UD":
                s["rnf"][actor_pos] = "RS_UC"
            elif cur == "RS_SD":
                s["rnf"][actor_pos] = "RS_SC"
        elif post == "downgrade_clean":
            # SnpShared from clean: UC -> SC, SC stays
            if s["rnf"][actor_pos] == "RS_UC":
                s["rnf"][actor_pos] = "RS_SC"
        elif post is not None:
            s["rnf"][actor_pos] = post
        # else: SR_SC -> stay (e.g. Snp_SnpClean_from_SC has post=None)
        s["snpresp"][actor_pos] = resp
        s["snpreq"][actor_pos]  = False
        if sets_dirty:
            s["hnfdirty"] = True

    # ── Collector + control rules ──────────────────────────────────────
    elif rule == "T_SNP_DONE":
        op = src["inflight"]
        if op in ("op_AtomicLoad", "op_AtomicStore"):
            for i in range(NUM_RNF):
                s["rnf"][i] = "RS_I"
            s.update(phase="STABLE", inflight="op_None", req=None,
                     hnfdirty=False)
        else:
            s["phase"] = "T_ACK"

    elif rule == "SNF_DATA":
        if src["inflight"] in ("op_AtomicLoad", "op_AtomicStore"):
            for i in range(NUM_RNF):
                s["rnf"][i] = "RS_I"
            s.update(phase="STABLE", inflight="op_None", req=None,
                     hnfdirty=False)
        else:
            s["phase"] = "T_ACK"

    elif rule == "CompAck":
        op  = src["inflight"]
        req = src["req"]
        if op == "op_ReadClean":
            s["rnf"][req] = "RS_SC"
            s["hnfdirty"] = False
        elif op == "op_ReadUnique":
            for i in range(NUM_RNF):
                if i == req:
                    s["rnf"][i] = "RS_UD" if src["hnfdirty"] else "RS_UC"
                else:
                    s["rnf"][i] = "RS_I"
            s["hnfdirty"] = False
        elif op == "op_MakeUnique":
            for i in range(NUM_RNF):
                s["rnf"][i] = "RS_UC" if i == req else "RS_I"
            s["hnfdirty"] = False
        elif op == "op_CleanUnique":
            for i in range(NUM_RNF):
                s["rnf"][i] = "RS_UC" if i == req else "RS_I"
            s["hnfdirty"] = False
        elif op == "op_CleanInvalid":
            for i in range(NUM_RNF):
                s["rnf"][i] = "RS_I"
            s["hnfdirty"] = False
        # CleanShared: no state change
        s["phase"]    = "STABLE"
        s["inflight"] = "op_None"
        s["req"]      = None

    elif rule == "Promote_pending":
        s["pend"][actor_pos] = "op_None"
    else:
        return None
    return s


# --------------------------------------------------------------------- #
# Per-edge permutation finder: compute σ by trying each actor candidate
# and matching the simulated dst against the actual canonical dst.
# --------------------------------------------------------------------- #

_UNIQUE = ("RS_UC", "RS_UD")
_SHARED = ("RS_SC", "RS_SD")
_DIRTY  = ("RS_UD", "RS_SD")


def actor_candidates(rule, src):
    """Canonical positions in src that could be the actor for this rule,
    given src's state. Drawn directly from Murphi guards in hnf_fsm_v2.m."""
    if rule == "CompAck":
        return [src["req"]] if src["req"] is not None else []
    if rule == "T_SNP_DONE":
        return [None]   # no per-RN-F actor
    if rule in _SNP_TABLE:
        # Per-snoopee snoop rule: actor is the snoopee s with snp_required[s].
        # Filter by the rule's (inflight_op, snoopee state) preconditions.
        expected_op, post, resp, _ = _SNP_TABLE[rule]
        if expected_op is not None and src["inflight"] != expected_op:
            return []
        if rule == "Snp_SnpMakeInvalid_any":
            allowed_ops = ("op_CleanUnique", "op_MakeUnique",
                           "op_AtomicLoad", "op_AtomicStore")
            if src["inflight"] not in allowed_ops:
                return []
        # State-of-snoopee predicate
        def ok_state(r):
            if rule.endswith("_from_UD"): return src["rnf"][r] == "RS_UD"
            if rule.endswith("_from_UC"): return src["rnf"][r] == "RS_UC"
            if rule.endswith("_from_SD"): return src["rnf"][r] == "RS_SD"
            if rule.endswith("_from_SC"): return src["rnf"][r] == "RS_SC"
            if rule.endswith("_from_dirty"): return src["rnf"][r] in _DIRTY
            if rule.endswith("_from_clean"): return src["rnf"][r] in ("RS_UC", "RS_SC")
            if rule == "Snp_SnpMakeInvalid_any":
                return src["rnf"][r] != "RS_I"
            return False
        return [r for r in range(NUM_RNF)
                if src["snpreq"][r] and ok_state(r)]
    if rule == "CAM_hazard_queue_REQ":
        return [i for i in range(NUM_RNF)
                if i != src["req"] and src["pend"][i] == "op_None"]
    if rule == "SNF_DATA":
        return [None]
    if rule == "Promote_pending":
        return [i for i in range(NUM_RNF) if src["pend"][i] != "op_None"]
    if rule == "StoreHit_UC_to_UD":
        return [i for i, r in enumerate(src["rnf"]) if r == "RS_UC"]
    if rule == "WriteCleanFull":
        return [i for i, r in enumerate(src["rnf"]) if r == "RS_UD"]
    if rule == "Evict_self":
        return [i for i, r in enumerate(src["rnf"]) if r in ("RS_SC", "RS_UC")]
    if rule == "WriteBackFull":
        return [i for i, r in enumerate(src["rnf"]) if r == "RS_UD"]
    # ── REQ-from-stable rules ─────────────────────────────────────────
    if rule == "ReadClean_from_I":
        return [i for i, r in enumerate(src["rnf"])
                if r == "RS_I" and src["pend"][i] == "op_None"]
    if rule == "ReadUnique_from_I":
        return [i for i, r in enumerate(src["rnf"])
                if r == "RS_I" and src["pend"][i] == "op_None"]
    if rule == "MakeUnique_from_I":
        return [i for i, r in enumerate(src["rnf"])
                if r == "RS_I" and src["pend"][i] == "op_None"]
    if rule in ("AtomicLoad_from_I", "AtomicStore_from_I"):
        return [i for i in range(NUM_RNF) if src["pend"][i] == "op_None"]
    if rule in ("AtomicLoad_with_holders", "AtomicStore_with_holders"):
        return [i for i in range(NUM_RNF) if src["pend"][i] == "op_None"]
    if rule == "ReadClean_from_SC_nonsharer":
        if num_unique(src) != 0 or num_shared(src) == 0:
            return []
        return [i for i, r in enumerate(src["rnf"])
                if r == "RS_I" and src["pend"][i] == "op_None"]
    if rule == "ReadClean_from_UC_other":
        if num_unique(src) != 1:
            return []
        return [i for i, r in enumerate(src["rnf"])
                if r == "RS_I" and src["pend"][i] == "op_None"]
    if rule == "ReadUnique_from_other_holder":
        return [i for i, r in enumerate(src["rnf"])
                if r not in _UNIQUE and src["pend"][i] == "op_None"]
    if rule == "CleanUnique_sole_sharer":
        if num_shared(src) != 1:
            return []
        return [i for i, r in enumerate(src["rnf"])
                if r == "RS_SC" and src["pend"][i] == "op_None"]
    if rule == "CleanUnique_with_others":
        if num_shared(src) <= 1:
            return []
        return [i for i, r in enumerate(src["rnf"])
                if r in _SHARED and src["pend"][i] == "op_None"]
    if rule == "MakeUnique_from_shared":
        return [i for i, r in enumerate(src["rnf"])
                if r in _SHARED and src["pend"][i] == "op_None"]
    if rule == "CleanInvalid_when_others_present":
        return [i for i, r in enumerate(src["rnf"])
                if r not in _UNIQUE and src["pend"][i] == "op_None"]
    return []


def edge_actor_and_sigma(rule, src_fp, dst_fp):
    """Returns (actor_canon_pos_in_src, sigma) where σ[src_pos] = dst_pos.
    Returns (None, None) if not derivable."""
    src = parse_fp(src_fp)
    dst = parse_fp(dst_fp)
    if not src or not dst:
        return None, None

    queued_op = None
    if rule == "CAM_hazard_queue_REQ":
        for i in range(NUM_RNF):
            if src["pend"][i] == "op_None" and dst["pend"][i] != "op_None":
                queued_op = dst["pend"][i]
                break

    for actor in actor_candidates(rule, src):
        sim_dst = simulate_rule(rule, src, actor, queued_op=queued_op)
        if sim_dst is None:
            continue
        canon = canonicalize(sim_dst)
        if render_fp(canon) == render_fp(dst):
            sigma = derive_sigma(sim_dst)
            return actor, sigma
    return None, None


def derive_sigma(uncanon_dst):
    """Given an uncanonicalized dst (output of simulate_rule), compute
    σ[i] = the canonical-position that src-position i ends up at."""
    pairs = list(zip(uncanon_dst["rnf"], uncanon_dst["pend"]))
    req = uncanon_dst["req"]
    # Reproduce canonicalize()'s ordering exactly, but remember source
    # positions instead of just the values.
    if req is not None and 0 <= req < NUM_RNF:
        head_src = [req]
        rest_src = sorted((i for i in range(NUM_RNF) if i != req),
                          key=lambda j: pairs[j])
        order = head_src + rest_src
    else:
        order = sorted(range(NUM_RNF), key=lambda j: pairs[j])
    # sigma[src_pos] = dst_pos
    sigma = [0] * NUM_RNF
    for dst_pos, src_pos in enumerate(order):
        sigma[src_pos] = dst_pos
    return sigma


# --------------------------------------------------------------------- #
# Murphi graph extraction (CANONICAL form, symmetry-reduced)
# --------------------------------------------------------------------- #

def extract_murphi_graph():
    """Extract the canonical (symmetry-reduced) graph. rumur's BFS uses
    symmetry reduction — the whole point of using Murphi — so we feed
    test gen from the reduced state space and recover physical identity
    via per-edge permutation tracking."""
    with tempfile.TemporaryDirectory() as td:
        pm = os.path.join(td, "p.m")
        cp = os.path.join(td, "p.c")
        bp = os.path.join(td, "p")
        to_dot.patch_model(to_dot.MODEL, pm)
        to_dot.run_rumur(pm, cp)
        to_dot.run_cc(cp, bp)
        out = to_dot.run_verifier(bp)
    to_dot.SYMMETRY_QUOTIENT = True
    return to_dot.parse_transitions(out)


# --------------------------------------------------------------------- #
# Build (state, edges) and per-edge metadata (actor canonical pos, σ)
# --------------------------------------------------------------------- #

def build_graph(edges):
    """Adjacency with per-edge metadata.
    adj[src] = list of (rule, dst, actor_canon_pos_in_src, sigma)."""
    adj = {}
    failed = 0
    for src, dst, rule in edges:
        actor, sigma = edge_actor_and_sigma(rule, src, dst)
        adj.setdefault(src, []).append((rule, dst, actor, sigma))
        adj.setdefault(dst, [])
        if actor is None and rule not in ("SNF_DATA", "Promote_pending"):
            failed += 1
    if failed:
        print(f"[gen_from_murphi] {failed} edges with undetermined σ "
              "(treated as identity)")
    return adj


def find_initial(adj):
    """Initial state: all RS_I, STABLE, no inflight, no pending, no
    pending snoops, hnf_has_dirty=false."""
    for fp in adj:
        f = parse_fp(fp)
        if (f and all(r == "RS_I" for r in f["rnf"])
                and f["phase"] == "STABLE" and f["inflight"] == "op_None"
                and f["req"] is None
                and all(p == "op_None" for p in f["pend"])
                and not any(f["snpreq"])
                and not f["hnfdirty"]):
            return fp
    sys.exit("could not locate initial state in Murphi graph")


# --------------------------------------------------------------------- #
# BFS that tracks physical→canonical position mapping
# --------------------------------------------------------------------- #

def apply_sigma(phys_to_canon, sigma):
    """Update the physical→canonical map after an edge transition.
    phys_to_canon[phys] = canon_pos_in_src. After the edge, the same
    physical RN-F is at canon_pos_in_dst = sigma[canon_pos_in_src]."""
    if sigma is None:
        return phys_to_canon[:]
    return [sigma[c] for c in phys_to_canon]


def bfs_shortest_paths(adj, initial):
    """Return state_fp -> (path, phys_to_canon_at_state) where path is
    a list of (rule, src, dst, actor_canon, sigma, actor_phys)."""
    init_map = list(range(NUM_RNF))  # phys 0 → canon 0, phys 1 → canon 1
    visited = {initial: ([], init_map)}
    q = deque([initial])
    while q:
        s = q.popleft()
        path, phys = visited[s]
        for rule, dst, actor_canon, sigma in adj.get(s, []):
            if dst in visited:
                continue
            # Find the actor's PHYSICAL identity: phys_to_canon[phys] == actor_canon
            actor_phys = None
            if actor_canon is not None:
                for ph, ca in enumerate(phys):
                    if ca == actor_canon:
                        actor_phys = ph
                        break
            new_phys = apply_sigma(phys, sigma)
            new_path = path + [(rule, s, dst, actor_canon, sigma, actor_phys)]
            visited[dst] = (new_path, new_phys)
            q.append(dst)
    return visited


# --------------------------------------------------------------------- #
# Event naming (DRIVE / OBSRV) given a per-edge actor_phys
# --------------------------------------------------------------------- #

def edge_event(rule, actor_phys, src, dst):
    actor = POS_TAG.get(actor_phys if actor_phys is not None else -1, "?")
    op = RULE_TO_REQ_OP.get(rule)
    if op is not None:
        return ("DRIVE", f"REQ_{actor}_{op}")
    if rule == "CAM_hazard_queue_REQ":
        for i in range(NUM_RNF):
            if src["pend"][i] == "op_None" and dst["pend"][i] != "op_None":
                queued = dst["pend"][i].replace("op_", "")
                return ("DRIVE", f"REQ_{actor}_{queued}")
        return ("DRIVE", f"REQ_{actor}_?")
    if rule == "SNF_DATA":
        return ("OBSRV", "SNF_DATA")
    if rule in _SNP_TABLE:
        # Per-snoopee SnpResp* decision.  Encode (snoop opcode, resp
        # variant) so the replay/oracle can check the on-wire opcode.
        _, _, resp, _ = _SNP_TABLE[rule]
        snoop_op = {
            "op_ReadClean":    "SnpClean",
            "op_ReadUnique":   "SnpUnique",
            "op_CleanUnique":  "SnpMakeInvalid",
            "op_MakeUnique":   "SnpMakeInvalid",
            "op_CleanInvalid": "SnpCleanInvalid",
            "op_CleanShared":  "SnpShared",
            "op_AtomicLoad":   "SnpMakeInvalid",
            "op_AtomicStore":  "SnpMakeInvalid",
        }.get(src["inflight"], "Snp?")
        return ("OBSRV", f"SNP_RESP_{actor}_{snoop_op}_{resp}")
    if rule == "T_SNP_DONE":
        return ("OBSRV", "T_SNP_DONE")
    if rule == "CompAck":
        return ("DRIVE", f"COMPACK_{actor}")
    if rule == "Promote_pending":
        return ("OBSRV", f"INT_PROMOTE_{actor}")
    if rule == "StoreHit_UC_to_UD":
        return ("OBSRV", f"INT_STOREHIT_{actor}")
    return ("OTHER", f"UNKNOWN_{rule}")


# --------------------------------------------------------------------- #
# State name (cosmetic) + vector rendering
# --------------------------------------------------------------------- #

def state_name(fp_str, phys_to_canon=None):
    fp = parse_fp(fp_str)
    if fp is None:
        return "BAD"
    rnf_short = "".join(r.replace("RS_", "") for r in fp["rnf"])
    if fp["phase"] != "STABLE":
        parts = [fp["phase"]]
        if fp["req"] is not None and phys_to_canon is not None:
            # Find physical RN-F whose canonical position == req
            for ph, ca in enumerate(phys_to_canon):
                if ca == fp["req"]:
                    parts.append(POS_TAG.get(ph, "?"))
                    break
        elif fp["req"] is not None:
            parts.append(POS_TAG.get(fp["req"], "?"))
        parts.append(fp["inflight"].replace("op_", ""))
        out = "_".join(parts) + f"[{rnf_short}]"
    else:
        out = "I" if rnf_short == "II" else rnf_short
        if fp.get("hnfdirty"):
            out += "_Hd"
    queued = [(i, p) for i, p in enumerate(fp["pend"]) if p != "op_None"]
    if queued:
        suf = "_".join(
            f"PEND[{POS_TAG.get(i, i)}]={p.replace('op_','')}"
            for i, p in queued)
        out += "__" + suf
    return out


def render_vector(target_state, target_event, full_path):
    lines = [
        f"# Target: state={target_state}  event={target_event}",
        f"# Length: {len(full_path)} edge(s)",
        f"# Source: Murphi model (symmetry-reduced; physical identity",
        f"#         recovered via per-edge permutation σ)",
        "# Format: step | kind | event | action | from -> to",
        "#" + "-" * 78,
    ]
    for i, (rule, src_fp, dst_fp, actor_canon, sigma, actor_phys) in enumerate(full_path):
        sfp, dfp = parse_fp(src_fp), parse_fp(dst_fp)
        kind, ev = edge_event(rule, actor_phys, sfp, dfp)
        sn, dn = state_name(src_fp), state_name(dst_fp)
        lines.append(f"{i:3d} | {kind:6s} | {ev:42s} | {rule:32s} | {sn} -> {dn}")
    return "\n".join(lines) + "\n"


def coverage_targets(adj, paths):
    """All (state, REQ_event) pairs reachable. Filter by denylist."""
    targets = []
    for s, edges in adj.items():
        if s not in paths:
            continue
        _, phys = paths[s]
        for rule, dst, actor_canon, sigma in edges:
            # Find actor_phys at this state's phys mapping
            actor_phys = None
            if actor_canon is not None:
                for ph, ca in enumerate(phys):
                    if ca == actor_canon:
                        actor_phys = ph
                        break
            sfp, dfp = parse_fp(s), parse_fp(dst)
            kind, ev = edge_event(rule, actor_phys, sfp, dfp)
            if kind != "DRIVE" or not ev.startswith("REQ_"):
                continue
            parts = ev.split("_", 2)
            if len(parts) == 3 and parts[2] in VECTOR_TARGET_DENYLIST:
                continue
            targets.append((s, ev, rule, dst, actor_canon, sigma, actor_phys))
    return targets


def emit_vectors(adj, initial, out_dir=VEC_DIR):
    os.makedirs(out_dir, exist_ok=True)
    paths = bfs_shortest_paths(adj, initial)
    targets = coverage_targets(adj, paths)
    emitted = 0
    skipped = 0
    seen_names = set()
    # Tcl interprets [] as command substitution when filenames are
    # passed via `-do`. Strip any shell/Tcl-metacharacters from the
    # basename. The state-name inside the file header keeps the
    # original text — only the filename is sanitized.
    def safe_basename(s):
        return (s.replace("[", "_").replace("]", "_")
                 .replace("=", "_").replace("/", "_"))
    for src, ev, rule, dst, actor_canon, sigma, actor_phys in targets:
        if src not in paths:
            skipped += 1
            continue
        prefix, _ = paths[src]
        full = prefix + [(rule, src, dst, actor_canon, sigma, actor_phys)]
        sn = state_name(src)
        safe_ev = safe_basename(ev)
        base = safe_basename(f"{sn}__{safe_ev}")
        name = base
        n = 1
        while name in seen_names:
            n += 1
            name = f"{base}__{n}"
        seen_names.add(name)
        with open(os.path.join(out_dir, f"{name}.txt"), "w") as f:
            f.write(render_vector(sn, ev, full))
        emitted += 1
    return emitted, skipped


# --------------------------------------------------------------------- #
# Entrypoint
# --------------------------------------------------------------------- #

def print_summary(adj, initial, edges):
    paths = bfs_shortest_paths(adj, initial)
    targets = coverage_targets(adj, paths)
    print(f"Murphi FSM:    {len(adj)} states (canonical, symmetry-reduced),"
          f" {len(edges)} edges")
    print(f"Initial state: {state_name(initial)}")
    print(f"Reachable:     {len(paths)} / {len(adj)} states")
    print(f"DRIVE-REQ coverage targets: {len(targets)}")
    print(f"Vector output dir: {VEC_DIR}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--summary", action="store_true")
    ap.add_argument("--vectors", action="store_true")
    ap.add_argument("--target", metavar="STATE_NAME")
    args = ap.parse_args()

    states, edges = extract_murphi_graph()
    adj = build_graph(edges)
    initial = find_initial(adj)

    if args.summary or (not args.vectors and not args.target):
        print_summary(adj, initial, edges)

    if args.vectors:
        n, skipped = emit_vectors(adj, initial)
        print(f"Emitted {n} vectors to {VEC_DIR}/ (skipped {skipped})")


if __name__ == "__main__":
    main()
