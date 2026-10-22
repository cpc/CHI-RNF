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
Randomised vector generator for the HN-F test-case generator.

Walks the FSM in random-but-legal steps to produce composite vectors
that exercise sequences of (state, event) pairs the BFS-shortest-path
generator would not naturally produce together. Each fuzz vector
contains a chain of N targets; between targets the FSM is brought back
to the initial state by inserting a recovery prefix (BFS from current
state back to I), so each target's BFS path stays well-defined.

Reproducible via --seed. Each emitted vector also records the seed and
target chain in its header, so any failing vector can be regenerated
verbatim.

Usage:
  ./fuzz_sequences.py --seed 42                  # one vector, 4 targets
  ./fuzz_sequences.py --seed 42 --chain 8        # one vector, 8 targets
  ./fuzz_sequences.py --count 20 --chain 6       # 20 vectors
  ./fuzz_sequences.py --include-tracked          # use opcodes from
                                                 # extract_rtl.py too
                                                 # (requires the FSM to
                                                 # cover those — opcodes
                                                 # without FSM edges are
                                                 # silently dropped)
"""

import argparse
import os
import random
import sys
from collections import deque

try:
    import yaml
except ImportError:
    sys.exit("PyYAML required: pip install --user --break-system-packages pyyaml")

# Reuse the FSM loader / BFS code from gen_sequences (it's small).
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_sequences as gs   # type: ignore


VEC_DIR = os.path.join(HERE, "vectors", "fuzz")


def _event_allowed(ev):
    """Reuse the vector-target denylist from gen_sequences so the fuzzer
    cannot select a random terminal target the BFS generator wouldn't
    emit either. BFS may still traverse through these as path edges."""
    return gs._event_target_allowed(ev)


def bfs_path(adj, src, dst):
    """Forward BFS from src to dst. Returns list of (event, action, fs, ts) or None."""
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
                # reconstruct
                path = []
                cur = ns
                while parent[cur] is not None:
                    fs, ev_, act_, ts = parent[cur]
                    path.append((ev_, act_, fs, ts))
                    cur = fs
                path.reverse()
                return path
            q.append(ns)
    return None


def random_target(adj, rng):
    """Pick a random (state, event) pair from the FSM edges, skipping any
    event matched by EVENT_DENYLIST."""
    flat = [(s, ev) for s, edges in adj.items() for ev, _, _ in edges
            if _event_allowed(ev)]
    return rng.choice(flat)


def build_fuzz_vector(adj, initial, n_targets, rng):
    """
    Build a composite vector visiting n_targets random (state, event) pairs,
    each preceded by a recovery prefix from the FSM's current state back to
    initial then a BFS forward to the target state.
    Returns (full_path, target_log).
    """
    full = []
    log  = []
    cur_state = initial
    for _ in range(n_targets):
        st, ev = random_target(adj, rng)
        # recover to initial first (simplest assumption — current state may
        # be a transient; not every transient has a path back to I in a
        # general FSM, but in the hand-curated model they all do.)
        if cur_state != initial:
            back = bfs_path(adj, cur_state, initial)
            if back is None:
                # dead-end transient; give up on this target
                log.append(("DROP-NO-RECOVERY", cur_state, st, ev))
                continue
            full.extend(back)
            cur_state = initial
        # walk from initial to target state
        forward = bfs_path(adj, initial, st)
        if forward is None:
            log.append(("DROP-UNREACHABLE", initial, st, ev))
            continue
        full.extend(forward)
        # apply the target event
        target_edge = next(((e, a, st, ns) for e, a, ns in adj[st] if e == ev), None)
        if target_edge is None:
            log.append(("DROP-EDGE-MISSING", st, st, ev))
            continue
        full.append(target_edge)
        log.append(("HIT", st, ev, target_edge[3]))
        cur_state = target_edge[3]
    return full, log


def render(seed, chain, target_log, full):
    lines = []
    lines.append(f"# Fuzz vector  seed={seed}  chain={chain}")
    lines.append(f"# Target log:")
    for entry in target_log:
        lines.append(f"#   {' '.join(map(str, entry))}")
    lines.append(f"# Length: {len(full)} edge(s)")
    lines.append(f"# Format: step | kind | event | action | from -> to")
    lines.append("#" + "-" * 78)
    for i, (ev, act, fs, ts) in enumerate(full):
        kind = "DRIVE " if gs.is_driver_event(ev)   else \
               "OBSRV " if gs.is_internal_event(ev) else "OTHER "
        lines.append(f"{i:3d} | {kind} | {ev:42s} | {act:32s} | {fs} -> {ts}")
    return "\n".join(lines) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed",  type=int, default=0,    help="base RNG seed")
    ap.add_argument("--chain", type=int, default=4,    help="targets per vector")
    ap.add_argument("--count", type=int, default=1,    help="number of vectors")
    ap.add_argument("--include-tracked", action="store_true",
                    help="(future) include MSHR-tracked ops not yet in FSM")
    args = ap.parse_args()

    states, adj, initial = gs.load_fsm()
    os.makedirs(VEC_DIR, exist_ok=True)

    for k in range(args.count):
        seed = args.seed + k
        rng  = random.Random(seed)
        full, log = build_fuzz_vector(adj, initial, args.chain, rng)
        out = render(seed, args.chain, log, full)
        fname = f"fuzz_seed{seed:05d}_chain{args.chain}.txt"
        path = os.path.join(VEC_DIR, fname)
        with open(path, "w") as f:
            f.write(out)
        hits  = sum(1 for e in log if e[0] == "HIT")
        drops = len(log) - hits
        print(f"  {path}  ({len(full)} steps, {hits} hits, {drops} drops)")


if __name__ == "__main__":
    main()
