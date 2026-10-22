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
HN-F test-case generator (step 1 prototype).

Loads hnf_fsm.yaml, computes a forward BFS from the initial state, and
emits the shortest sequence of *driver-controllable* events that leads
the HN-F into any reachable (state, pending_event) pair.

A "driver-controllable" event is one a RN-F can directly cause:
  REQ_<X>_<OP>   - RN-F X issues a REQ flit
  SNP_RESP_<X>_* - RN-F X responds to an outstanding snoop
  COMPACK_<X>_*  - RN-F X sends CompAck

Internal events the driver cannot directly emit (SNF_DATA_*, INT_*) are
still traversed by BFS - they're treated as "automatic" transitions that
the runner expects to observe but doesn't issue. The emitted vector
omits them; the runner walks them implicitly when the FSM advances.

Output formats:
  --vectors      one .txt vector per (state, event) target under vectors/
  --summary      print coverage stats to stdout
  --target S=ST  print the vector for one specific target state

Usage:
  ./gen_sequences.py --summary
  ./gen_sequences.py --vectors
  ./gen_sequences.py --target UD_A
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
FSM_PATH = os.path.join(HERE, "hnf_fsm.yaml")
VEC_DIR = os.path.join(HERE, "vectors")


def load_fsm(path=FSM_PATH):
    with open(path) as f:
        d = yaml.safe_load(f)
    states = d["states"]
    edges = d["edges"]
    initial = d["initial"]
    # adjacency: state -> list of (event, action, next_state)
    adj = {s: [] for s in states}
    for e in edges:
        if e["from"] not in states:
            sys.exit(f"edge from unknown state: {e['from']}")
        if e["to"] not in states:
            sys.exit(f"edge to unknown state: {e['to']}")
        adj[e["from"]].append((e["event"], e.get("action", ""), e["to"]))
    return states, adj, initial


# Vector-target denylist. Edges with REQ events matching any of these ops
# will NOT be emitted as terminal targets of a generated test vector. BFS
# still uses them as path-precursors when reaching other targets — only
# the vector emission is suppressed.
#
# Rationale: most of these go through the HNF MSHR bypass and produce no
# observable ALLOC event in the oracle's trace, OR they're simply not
# worth exercising as a stress target (e.g. WriteBackPtl partial
# byte-enable variants).
VECTOR_TARGET_DENYLIST = (
    "ReadOnce",
    "ReadNotSharedDirty",
    "WriteNoSnpPtl",
    "WriteEvictFull",
    "WriteBackPtl",
    "Evict",
    "WriteUniqueFull",
    "WriteUniquePtl",      # also currently disabled in chi_tlm_rnf.cpp
)


def _event_target_allowed(ev):
    """True iff `ev` is acceptable as a vector's terminal event."""
    # CAM-hazard events are model-only documentation today — they encode
    # what the HNF does when a concurrent REQ arrives during a transient,
    # but exercising them requires retry-handshake logic in chi_tlm_rnf
    # that isn't implemented yet. Skip until then.
    if ev.endswith("__HAZARD"):
        return False
    if not ev.startswith("REQ_"):
        return True
    # REQ_<X>_<opname>  → strip REQ_X_ prefix
    if len(ev) > 6:
        opname = ev[6:]
        if opname in VECTOR_TARGET_DENYLIST:
            return False
    return True


def is_driver_event(ev):
    """True if a RN-F can directly cause this event (REQ/SNP_RESP/COMPACK)."""
    return ev.startswith("REQ_") or ev.startswith("SNP_RESP_") or ev.startswith("COMPACK_")


def is_internal_event(ev):
    """True if it's an automatic HNF/SNF transition (not driver-issued)."""
    return ev.startswith("SNF_") or ev.startswith("INT_")


def bfs_shortest_paths(adj, initial):
    """
    Forward BFS over the FSM. Returns dict:
      state -> (path, length)
    where path is a list of (event, action, from_state, to_state).
    Path length counts edges (driver + internal both counted, since they're
    all observable transitions even if the driver only directly emits some).
    """
    visited = {initial: ([], 0)}
    q = deque([initial])
    while q:
        s = q.popleft()
        path, depth = visited[s]
        for ev, act, ns in adj[s]:
            if ns not in visited:
                visited[ns] = (path + [(ev, act, s, ns)], depth + 1)
                q.append(ns)
    return visited


def coverage_targets(states, adj):
    """All (state, event) pairs reachable as outgoing edges from that state.
    These are the coverage goals: each one should be hit by at least one
    generated test vector. Filtered by VECTOR_TARGET_DENYLIST."""
    targets = []
    for s, edges in adj.items():
        for ev, _act, _ns in edges:
            if not _event_target_allowed(ev):
                continue
            targets.append((s, ev))
    return targets


def vector_for_target(adj, initial, state, event):
    """
    Return the shortest sequence of edges that lands the HNF *in* `state`
    *with* `event` about to be applied next. Returns the path list plus
    the (event, action, state, to_state) of the final triggering edge.
    Returns None if unreachable.
    """
    paths = bfs_shortest_paths(adj, initial)
    if state not in paths:
        return None
    prefix, _depth = paths[state]
    # find the matching outgoing edge for the target event
    final_edge = next(((ev, act, state, ns) for ev, act, ns in adj[state]
                       if ev == event), None)
    if final_edge is None:
        return None
    return prefix + [final_edge]


def render_vector(target_state, target_event, full_path):
    """Pretty-print a vector for inspection / for the SystemC runner."""
    lines = []
    lines.append(f"# Target: state={target_state}  event={target_event}")
    lines.append(f"# Length: {len(full_path)} edge(s)")
    lines.append("# Format: step | kind | event | action | from -> to")
    lines.append("#" + "-" * 78)
    for i, (ev, act, fs, ts) in enumerate(full_path):
        kind = "DRIVE " if is_driver_event(ev) else \
               "OBSRV " if is_internal_event(ev) else "OTHER "
        lines.append(f"{i:3d} | {kind} | {ev:42s} | {act:32s} | {fs} -> {ts}")
    return "\n".join(lines) + "\n"


def emit_all_vectors(states, adj, initial, out_dir=VEC_DIR):
    os.makedirs(out_dir, exist_ok=True)
    targets = coverage_targets(states, adj)
    reachable = bfs_shortest_paths(adj, initial)
    emitted = 0
    skipped = 0
    for st, ev in targets:
        if st not in reachable:
            skipped += 1
            continue
        path = vector_for_target(adj, initial, st, ev)
        if path is None:
            skipped += 1
            continue
        # sanitize filename
        safe_ev = ev.replace("/", "_")
        fname = f"{st}__{safe_ev}.txt"
        with open(os.path.join(out_dir, fname), "w") as f:
            f.write(render_vector(st, ev, path))
        emitted += 1
    return emitted, skipped


def print_summary(states, adj, initial):
    reachable = bfs_shortest_paths(adj, initial)
    targets = coverage_targets(states, adj)

    print(f"FSM: {len(states)} states, {sum(len(v) for v in adj.values())} edges")
    print(f"Initial state: {initial}")
    print()

    print(f"State reachability from {initial}:")
    for s in states:
        if s in reachable:
            _, d = reachable[s]
            mark = "T" if states[s].get("transient") else " "
            print(f"  [{mark}] {s:12s}  depth={d}")
        else:
            print(f"  [!] {s:12s}  UNREACHABLE")
    print()

    print(f"Coverage targets: {len(targets)} (state, event) pairs")
    cov_ok = 0
    cov_no = 0
    for st, ev in targets:
        if st in reachable and any(e == ev for e, _, _ in adj[st]):
            cov_ok += 1
        else:
            cov_no += 1
    print(f"  reachable:   {cov_ok}")
    print(f"  unreachable: {cov_no}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--summary", action="store_true",
                    help="print FSM reachability / coverage stats")
    ap.add_argument("--vectors", action="store_true",
                    help="emit one .txt vector per (state, event) target")
    ap.add_argument("--target", metavar="STATE",
                    help="print shortest vectors for each outgoing event of STATE")
    args = ap.parse_args()

    states, adj, initial = load_fsm()

    if args.summary or (not args.vectors and not args.target):
        print_summary(states, adj, initial)

    if args.vectors:
        n, skipped = emit_all_vectors(states, adj, initial)
        print(f"\nEmitted {n} vectors to {VEC_DIR}/  (skipped {skipped} unreachable)")

    if args.target:
        st = args.target
        if st not in states:
            sys.exit(f"unknown state: {st}")
        outs = [ev for ev, _, _ in adj[st]]
        if not outs:
            print(f"# {st} has no outgoing edges")
            return
        for ev in outs:
            path = vector_for_target(adj, initial, st, ev)
            if path is None:
                print(f"# {st} / {ev}: UNREACHABLE\n")
                continue
            print(render_vector(st, ev, path))


if __name__ == "__main__":
    main()
