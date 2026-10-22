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
Burst-mode test generator.

For each non-denied REQ opcode the FSM supports, emits a vector that
issues that opcode N times in a row from a single RN-F, with the FSM
returning to its initial state between issues via the BFS-computed
recovery prefix. Stresses:

  - MSHR pipelining (back-to-back allocation / retirement)
  - DBID reuse
  - Snoop-filter consistency under repeated traffic to the same line
  - HNF L3 hit/miss/replacement timing

Generated vectors are dropped into testgen/vectors/burst/ alongside the
fuzz vectors. Each one is a fully-formed replay vector consumable by
chi_tlm_rnf.cpp's replay_orchestrate via REPLAY_VECTOR.

Usage:
  ./gen_burst.py                          # default N=5, both RN-Fs
  ./gen_burst.py --burst 10               # 10 back-to-back issues
  ./gen_burst.py --rnf A                  # only RN-F A as initiator
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

VEC_DIR = os.path.join(HERE, "vectors", "burst")


def bfs_path(adj, src, dst):
    """Shortest path (list of (event, action, fs, ts)) from src to dst, or None."""
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
    """Collect every distinct REQ opcode short-name reachable from the FSM
    that is NOT in the vector-target denylist."""
    ops = set()
    for s, edges in adj.items():
        for ev, _, _ in edges:
            if ev.startswith("REQ_A_") or ev.startswith("REQ_B_"):
                op = ev[6:]
                # filter via the same denylist that gen_sequences uses
                if op in gs.VECTOR_TARGET_DENYLIST:
                    continue
                ops.add(op)
    return sorted(ops)


def build_burst_vector(adj, initial, op, rnf_letter, n_burst):
    """Construct a vector that issues REQ_<rnf>_<op> n_burst times on the
    same line. Between issues, walk back to `initial` via BFS so each
    REQ starts from a known reset state."""
    event = f"REQ_{rnf_letter}_{op}"
    full = []
    cur_state = initial
    n_emitted = 0

    for _ in range(n_burst):
        # walk back to initial if needed
        if cur_state != initial:
            back = bfs_path(adj, cur_state, initial)
            if back is None:
                break
            full.extend(back)
            cur_state = initial
        # find the edge `initial → ? labelled event`
        target_edge = next(((e, a, ns) for e, a, ns in adj[initial] if e == event), None)
        if target_edge is None:
            # event not directly emittable from initial; nothing to do
            break
        ev, act, ns = target_edge
        full.append((ev, act, initial, ns))
        cur_state = ns
        n_emitted += 1
    return full, n_emitted


def render(op, rnf_letter, n_burst, n_emitted, path):
    lines = []
    lines.append(f"# Burst vector  op=REQ_{rnf_letter}_{op}  N={n_burst}  emitted={n_emitted}")
    lines.append(f"# Length: {len(path)} edge(s)")
    lines.append(f"# Format: step | kind | event | action | from -> to")
    lines.append("#" + "-" * 78)
    for i, (ev, act, fs, ts) in enumerate(path):
        kind = "DRIVE " if gs.is_driver_event(ev)   else \
               "OBSRV " if gs.is_internal_event(ev) else "OTHER "
        lines.append(f"{i:3d} | {kind} | {ev:42s} | {act:32s} | {fs} -> {ts}")
    return "\n".join(lines) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--burst", type=int, default=5,
                    help="number of back-to-back issues per vector (default 5)")
    ap.add_argument("--rnf",   choices=("A", "B", "both"), default="both",
                    help="which RN-F to use as initiator (default both)")
    args = ap.parse_args()

    states, adj, initial = gs.load_fsm()
    ops = find_allowed_ops(adj)
    os.makedirs(VEC_DIR, exist_ok=True)

    rnfs = ("A", "B") if args.rnf == "both" else (args.rnf,)

    n_made = 0
    n_skipped = 0
    for op in ops:
        for rnf in rnfs:
            event = f"REQ_{rnf}_{op}"
            # initial-state edge presence (we burst from initial → ... → initial)
            if not any(e == event for e, _, _ in adj[initial]):
                # op cannot be issued from initial; skip
                n_skipped += 1
                continue
            path, emitted = build_burst_vector(adj, initial, op, rnf, args.burst)
            if emitted == 0:
                n_skipped += 1
                continue
            fname = f"burst_{op}_{rnf}_N{args.burst}.txt"
            with open(os.path.join(VEC_DIR, fname), "w") as f:
                f.write(render(op, rnf, args.burst, emitted, path))
            n_made += 1
            print(f"  {fname}  ({len(path)} steps, {emitted}/{args.burst} bursts)")
    print()
    print(f"emitted {n_made} burst vector(s)  (skipped {n_skipped})  → {VEC_DIR}/")


if __name__ == "__main__":
    main()
