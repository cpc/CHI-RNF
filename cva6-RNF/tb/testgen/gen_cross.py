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
Cross-RN-F concurrent-burst generator (Option A).

For each non-denied REQ opcode the FSM can issue from initial state,
emits a vector that performs N rounds of:

    FORK   REQ_B_<op>   (peer fires async)
    DRIVE  REQ_A_<op>   (self fires, do_*() blocks)
    JOIN                (collect peer completion)
    [recovery edges back to FSM initial state]

Both RN-Fs hit the HNF within a handful of cycles of each other,
stressing snoop arbitration, cross-MSHR-slot interaction, and
snoop-filter consistency under contended access to the same line.

The address is provided at replay time via REPLAY_ADDR; the generator
emits the vector at the abstract event level only.

Usage:
  ./gen_cross.py                          # default N=5
  ./gen_cross.py --rounds 10              # 10 concurrent rounds per op
"""

import argparse
import os
import sys
from collections import deque

try:
    import yaml
except ImportError:
    sys.exit("PyYAML required: pip install --user --break-system-packages pyyaml")

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_sequences as gs
import oracle as ora      # for BYPASS_OPCODES — cross-RN-F race is meaningless
                          # for ops that don't trigger snoops

VEC_DIR = os.path.join(HERE, "vectors", "cross")


def bfs_path(adj, src, dst):
    """Shortest path of edges from src to dst (or None)."""
    if src == dst:
        return []
    parent = {src: None}
    q = deque([src])
    while q:
        s = q.popleft()
        for ev, act, ns in adj[s]:
            if ns in parent:
                continue
            parent[ns] = (s, ev, act, ns)
            if ns == dst:
                path = []
                cur = ns
                while parent[cur] is not None:
                    fs, ev_, act_, ts = parent[cur]
                    path.append((ev_, act_, fs, ts))
                    cur = fs
                return list(reversed(path))
            q.append(ns)
    return None


def find_allowed_ops(adj):
    """REQ opcodes that (1) the FSM can issue from initial state for *both*
    RN-Fs, (2) are not in VECTOR_TARGET_DENYLIST, and (3) are not bypass-
    classed. Cross-RN-F concurrent burst targets snoop / cross-MSHR
    interaction; bypass ops (ReadNoSnp / WriteNoSnp{Full,Ptl} / ReadOnce)
    don't generate snoops and don't allocate the regular MSHR — running
    them concurrently exercises CAM-hazard fallback rather than the
    intended race path, and the oracle can't score them either."""
    ops_a = set()
    ops_b = set()
    for ev, _, _ in adj["I"]:
        if ev.startswith("REQ_A_"):
            ops_a.add(ev[6:])
        elif ev.startswith("REQ_B_"):
            ops_b.add(ev[6:])
    common = ops_a & ops_b
    return sorted(op for op in common
                  if op not in gs.VECTOR_TARGET_DENYLIST
                  and op not in ora.BYPASS_OPCODES)


def render(op, n_rounds, n_emitted, full):
    lines = []
    lines.append(f"# Cross-burst vector  op=REQ_{{A,B}}_{op}  rounds={n_rounds}  "
                 f"emitted={n_emitted}")
    lines.append(f"# Pattern per round: FORK peer REQ_B → DRIVE self REQ_A → JOIN → recover")
    lines.append(f"# Length: {len(full)} edge(s)")
    lines.append(f"# Format: step | kind | event | action | from -> to")
    lines.append("#" + "-" * 78)
    for i, (kind, ev, act, fs, ts) in enumerate(full):
        lines.append(f"{i:3d} | {kind:6s} | {ev:42s} | {act:32s} | {fs} -> {ts}")
    return "\n".join(lines) + "\n"


def build_cross_vector(adj, initial, op, n_rounds):
    """Construct a cross-RN-F concurrent burst vector for `op`.
    Returns (steps_with_kind, rounds_emitted)."""
    event_a = f"REQ_A_{op}"
    event_b = f"REQ_B_{op}"
    edge_a = next(((e, a, ns) for e, a, ns in adj[initial] if e == event_a), None)
    edge_b = next(((e, a, ns) for e, a, ns in adj[initial] if e == event_b), None)
    if edge_a is None or edge_b is None:
        return [], 0

    out = []          # list of (kind, ev, action, from, to)
    cur_state_a = initial
    cur_state_b = initial
    rounds_done = 0

    for r in range(n_rounds):
        # Recover to initial for whichever RN-F left it last round
        if cur_state_a != initial:
            back = bfs_path(adj, cur_state_a, initial)
            if back is None:
                break
            for ev, act, fs, ts in back:
                out.append(("DRIVE", ev, act, fs, ts))
            cur_state_a = initial
        if cur_state_b != initial:
            back = bfs_path(adj, cur_state_b, initial)
            if back is None:
                break
            for ev, act, fs, ts in back:
                out.append(("DRIVE", ev, act, fs, ts))
            cur_state_b = initial

        # Concurrent issue: FORK peer (B) first, then DRIVE self (A)
        evb, actb, nsb = edge_b
        eva, acta, nsa = edge_a
        out.append(("FORK",  evb, actb, initial, nsb))
        out.append(("DRIVE", eva, acta, initial, nsa))
        out.append(("JOIN",  "_peer", "wait_peer_done",
                    "concurrent", "synced"))
        cur_state_a = nsa
        cur_state_b = nsb
        rounds_done += 1

    return out, rounds_done


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--rounds", type=int, default=5,
                    help="number of concurrent rounds per vector (default 5)")
    args = ap.parse_args()

    states, adj, initial = gs.load_fsm()
    ops = find_allowed_ops(adj)
    if not ops:
        sys.exit("no eligible ops (need REQ_A and REQ_B edges out of initial state)")
    os.makedirs(VEC_DIR, exist_ok=True)

    n_made = 0
    for op in ops:
        path, emitted = build_cross_vector(adj, initial, op, args.rounds)
        if emitted == 0:
            print(f"  skip {op} (no path)")
            continue
        fname = f"cross_{op}_R{args.rounds}.txt"
        with open(os.path.join(VEC_DIR, fname), "w") as f:
            f.write(render(op, args.rounds, emitted, path))
        print(f"  {fname}  ({len(path)} steps, {emitted}/{args.rounds} rounds)")
        n_made += 1
    print()
    print(f"emitted {n_made} cross-burst vector(s)  → {VEC_DIR}/")


if __name__ == "__main__":
    main()
