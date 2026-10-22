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
RN-F IP-level test-vector generator driven by murphi_rnf/rnf_fsm.m.

Analog of gen_from_murphi.py but for the RN-F-as-DUT flow:
  * The Murphi model models a single RN-F + non-deterministic CHI env.
  * We BFS the reachable graph (rumur symmetry-reduced; only 5292
    states in the trimmed model).
  * For each coverage *target* edge we emit one vector containing the
    BFS shortest-path prefix + the target edge.
  * Each vector lists DRIVE events (TB-controllable: SW ops, env-side
    response/snoop injections) and OBSRV events (DUT decisions: REQ
    issue, CompAck, snoop response variant).

Output:
  vectors_rnf/<state>__<event>.txt   one per (state, target_event) pair
"""

import argparse
import copy
import os
import re
import sys
import tempfile
from collections import deque

HERE         = os.path.dirname(os.path.abspath(__file__))
MURPHI_DIR   = os.path.join(HERE, "murphi_rnf")
SHARED_MDIR  = os.path.join(HERE, "murphi")
# Shared parent module first so the RN-F to_dot's `import to_dot`
# resolves to the HN-F version (which provides the rumur runner).
sys.path.insert(0, SHARED_MDIR)
import importlib.util
_spec = importlib.util.spec_from_file_location(
    "rnf_to_dot", os.path.join(MURPHI_DIR, "to_dot.py"))
to_dot = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(to_dot)

VEC_DIR = os.path.join(HERE, "vectors_rnf")

# Default test address; the model is single-line so addr is symbolic.
ADDR_COHERENT = 0x80000200

# DRIVE-side events (TB-controllable input edges).
# Subset of all rule names; the rest are OBSRV (DUT-driven).
DRIVE_RULES = {
    # Software-issued enqueue (one per SwSlot opcode)
    "SW_enqueue",
    # Environment response flits
    "Env_CompData_clean", "Env_CompData_dirty",
    "Env_Comp_dataless", "Env_Comp_for_Evict",
    "Env_DBIDResp_for_Write", "Env_CompDBIDResp_for_Write",
    "Env_CompData_for_AtomicLoad",
    "Env_Comp_for_AtomicStore",
    "Env_Comp_for_WriteBack",
    # Environment snoop injection
    "Env_Snp_SnpClean", "Env_Snp_SnpUnique", "Env_Snp_SnpMakeInvalid",
    "Env_Snp_SnpCleanInvalid", "Env_Snp_SnpShared",
}

# OBSRV-side events.  Listed for documentation; the oracle uses them
# to validate the DUT's predicted behaviour against the trace.
OBSRV_RULES = {
    "Issue_ReadClean", "Issue_ReadUnique", "Issue_MakeUnique",
    "Issue_CleanUnique", "Issue_CleanInvalid", "Issue_CleanShared",
    "Issue_Evict", "Issue_WriteBackFull", "Issue_WriteCleanFull",
    "Issue_AtomicLoad", "Issue_AtomicStore",
    "SW_local_hit_drain_ReadClean", "SW_local_hit_drain_ReadUnique",
    "SW_drain_MakeUnique_when_not_I", "SW_drain_CleanUnique_when_not_shared",
    "SW_drain_CleanInvalid_when_I", "SW_drain_Evict_when_not_clean_holder",
    "SW_drain_WriteBackFull_when_not_UD", "SW_drain_WriteCleanFull_when_not_UD",
    "StoreHit_UC_to_UD",
    "Send_WriteData",
    "Send_CompAck_after_clean", "Send_CompAck_after_dirty",
    # Per-(snoop_op x L1_state) decision rules:
    "Snp_SnpClean_from_UD", "Snp_SnpClean_from_UC",
    "Snp_SnpClean_from_SD", "Snp_SnpClean_from_SC",
    "Snp_SnpUnique_from_UD", "Snp_SnpUnique_from_UC",
    "Snp_SnpUnique_from_SD", "Snp_SnpUnique_from_SC",
    "Snp_SnpMakeInvalid_any",
    "Snp_SnpCleanInvalid_from_dirty", "Snp_SnpCleanInvalid_from_clean",
    "Snp_SnpShared_from_dirty", "Snp_SnpShared_from_clean",
    "Snp_any_from_I",
}


# --------------------------------------------------------------------- #
# Murphi graph extraction (RN-F is single-DUT, no symmetry reduction)
# --------------------------------------------------------------------- #

def extract_rnf_graph():
    with tempfile.TemporaryDirectory() as td:
        pm = os.path.join(td, "p.m")
        cp = os.path.join(td, "p.c")
        bp = os.path.join(td, "p")
        to_dot.patch_model(to_dot.MODEL, pm)
        to_dot.run_rumur(pm, cp)
        to_dot.run_cc(cp, bp)
        out = to_dot.run_verifier(bp)
    return to_dot.parse_transitions(out)


# --------------------------------------------------------------------- #
# Initial state + BFS
# --------------------------------------------------------------------- #

INIT_FP_RE = re.compile(
    r"l1=L1_I tx_op=tx_None tx_phase=TX_IDLE tx_expack=false "
    r"rx_snp=rx_None rx_owed=false sw_q=sw_None"
)


def find_initial(states):
    for s in states:
        if INIT_FP_RE.search(s):
            return s
    sys.exit("could not locate initial state in RN-F Murphi graph")


def build_adj(edges):
    adj = {}
    for src, dst, rule in edges:
        adj.setdefault(src, []).append((rule, dst))
        adj.setdefault(dst, [])
    return adj


def bfs_shortest_paths(adj, initial):
    """state_fp -> list of (rule, src, dst) -- one shortest path."""
    visited = {initial: []}
    q = deque([initial])
    while q:
        s = q.popleft()
        for rule, dst in adj.get(s, []):
            if dst in visited:
                continue
            visited[dst] = visited[s] + [(rule, s, dst)]
            q.append(dst)
    return visited


# --------------------------------------------------------------------- #
# Coverage targets: every (state, DRIVE-edge) pair.
# --------------------------------------------------------------------- #

def coverage_targets(adj, paths):
    targets = []
    for s, edges in adj.items():
        if s not in paths:
            continue
        for rule, dst in edges:
            # Match by rule prefix (SW_enqueue, Env_*) since
            # parse_transitions doesn't carry the Ruleset arg.
            if any(rule.startswith(r) for r in DRIVE_RULES):
                targets.append((s, rule, dst))
    return targets


# --------------------------------------------------------------------- #
# Vector rendering
# --------------------------------------------------------------------- #

def short_state_name(fp):
    """Compact label for a state fingerprint."""
    m_l1     = re.search(r"l1=(\w+)", fp)
    m_phase  = re.search(r"tx_phase=(\w+)", fp)
    m_op     = re.search(r"tx_op=(\w+)", fp)
    m_rxsnp  = re.search(r"rx_snp=(\w+)", fp)
    m_sw     = re.search(r"sw_q=(\w+)", fp)
    parts = []
    parts.append((m_l1.group(1) if m_l1 else "?").replace("L1_", ""))
    if m_phase and m_phase.group(1) != "TX_IDLE":
        parts.append(m_phase.group(1).replace("TX_", ""))
    if m_op and m_op.group(1) != "tx_None":
        parts.append(m_op.group(1).replace("tx_", ""))
    if m_rxsnp and m_rxsnp.group(1) != "rx_None":
        parts.append(m_rxsnp.group(1).replace("rx_", "S:"))
    if m_sw and m_sw.group(1) != "sw_None":
        parts.append(m_sw.group(1).replace("sw_", "Q:"))
    return "|".join(parts) or "init"


SW_Q_RE = re.compile(r"sw_q=(\w+)")


def event_label(rule, src=None, dst=None):
    """Map a rule firing into a (kind, label) tuple.  For SW_enqueue
    we resolve the opcode by diffing src.sw_q (None) -> dst.sw_q so
    the replay driver doesn't have to re-parse state."""
    if rule == "SW_enqueue" and dst is not None:
        m = SW_Q_RE.search(dst)
        if m and m.group(1) != "sw_None":
            return ("DRIVE", f"SW_enqueue_{m.group(1).replace('sw_', '')}")
    for d in DRIVE_RULES:
        if rule.startswith(d):
            return ("DRIVE", rule)
    return ("OBSRV", rule)


# --------------------------------------------------------------------- #
# Trigger metadata (phase 1: emit only -- replay still dispatches
# sequentially and ignores everything after the "from -> to" column)
# --------------------------------------------------------------------- #
#
# Every edge already carries its full Murphi source-state fingerprint
# (l1= tx_op= tx_phase= tx_expack= rx_snp= rx_owed= sw_q=); until now the
# generators collapsed it to a human label and discarded the rest.  That
# is the precondition the TB needs in order to fire an event when the DUT
# is actually in the right state, instead of dispatching sequentially and
# hoping.
#
# Split into two kinds deliberately:
#
#   @trig{...}   CHI-OBSERVABLE state the TB can wait on -- tx_phase and
#                tx_op are what rnf_phase_tracker derives from the CHI
#                wires, rx_snp is the responder's pending snoop, sw_q is
#                the TB's own queue.
#
#   @assert{...} l1 (cache state) ONLY.  This is deliberately NOT a wait
#                condition: the TB can only infer L1 state, and that
#                inference disagreed with the actual cache state on 8532
#                of 71960 probe samples (11.9%).  Gating a wait on it
#                would hang or misfire roughly one step in eight.  Check
#                it after the fact; never block on it.
TRIGGER_FIELDS = ("tx_phase", "tx_op", "rx_snp", "sw_q")
ASSERT_FIELDS  = ("l1",)


def _state_fields(fp, names):
    out = []
    for n in names:
        m = re.search(rf"\b{n}=(\w+)", fp)
        if m:
            out.append(f"{n}={m.group(1)}")
    return ";".join(out)


def trigger_spec(src_fp):
    """Machine-readable precondition suffix for one vector line.

    Appended after the "from -> to" column, which the SV replay parser
    never reads (extract_event_token stops at the first '|' after the
    fixed event column), so existing vectors and this format stay
    interchangeable.
    """
    trig = _state_fields(src_fp, TRIGGER_FIELDS)
    asrt = _state_fields(src_fp, ASSERT_FIELDS)
    s = ""
    if trig:
        s += f"  @trig{{{trig}}}"
    if asrt:
        s += f" @assert{{{asrt}}}"
    return s


def render_vector(target_state, target_event, path, addr=ADDR_COHERENT):
    lines = [
        f"# Target: state={target_state}  event={target_event}",
        f"# Length: {len(path)} edge(s)",
        f"# Source: Murphi model murphi_rnf/rnf_fsm.m  addr=0x{addr:016x}",
        f"# Format: step | kind | event | rule | from -> to  @trig{{...}} @assert{{...}}",
        f"#   @trig   = CHI-observable precondition the replay may wait on",
        f"#   @assert = inferred-only state; check after the fact, never block on it",
        "#" + "-" * 78,
    ]
    for i, (rule, src, dst) in enumerate(path):
        kind, ev = event_label(rule, src, dst)
        sn = short_state_name(src)
        dn = short_state_name(dst)
        lines.append(f"{i:3d} | {kind:6s} | {ev:42s} | {rule:36s} | {sn} -> {dn}"
                     f"{trigger_spec(src)}")
    return "\n".join(lines) + "\n"


def safe_basename(s):
    return (s.replace("[", "_").replace("]", "_")
             .replace("=", "_").replace("/", "_")
             .replace("|", "_").replace(":", "_"))


def emit_vectors(adj, initial, out_dir=VEC_DIR):
    os.makedirs(out_dir, exist_ok=True)
    paths = bfs_shortest_paths(adj, initial)
    targets = coverage_targets(adj, paths)
    seen = set()
    emitted = 0
    skipped = 0
    for src, rule, dst in targets:
        prefix = paths.get(src)
        if prefix is None:
            skipped += 1
            continue
        full = prefix + [(rule, src, dst)]
        sn = short_state_name(src)
        base = safe_basename(f"{sn}__{rule}")
        name = base
        n = 1
        while name in seen:
            n += 1
            name = f"{base}__{n}"
        seen.add(name)
        with open(os.path.join(out_dir, f"{name}.txt"), "w") as f:
            f.write(render_vector(sn, rule, full))
        emitted += 1
    return emitted, skipped


def print_summary(adj, initial, edges):
    paths = bfs_shortest_paths(adj, initial)
    targets = coverage_targets(adj, paths)
    drive_kinds = set()
    obsrv_kinds = set()
    for src, dst, rule in edges:
        kind, _ = event_label(rule, src, dst)
        (drive_kinds if kind == "DRIVE" else obsrv_kinds).add(rule)
    print(f"RN-F FSM:       {len(adj)} reachable states, {len(edges)} edges")
    print(f"Initial state:  {short_state_name(initial)}")
    print(f"DRIVE edges:    {len(drive_kinds)} unique rule names")
    print(f"OBSRV edges:    {len(obsrv_kinds)} unique rule names")
    print(f"Vector targets: {len(targets)}")
    print(f"Output dir:     {VEC_DIR}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--summary", action="store_true")
    ap.add_argument("--vectors", action="store_true")
    args = ap.parse_args()

    states, edges = extract_rnf_graph()
    adj = build_adj(edges)
    initial = find_initial(adj)

    if args.summary or (not args.vectors):
        print_summary(adj, initial, edges)

    if args.vectors:
        n, skipped = emit_vectors(adj, initial)
        print(f"Emitted {n} vectors to {VEC_DIR}/ (skipped {skipped})")


if __name__ == "__main__":
    main()
