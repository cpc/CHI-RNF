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
RN-F IP-level 2-switch (both-DRIVE) test-vector generator.

Companion to gen_from_rnf.py.  Where the 1-switch generator emits one
vector per (state, DRIVE-edge) pair, this one emits one vector per
(state, DRIVE-edge-in, DRIVE-edge-out) consecutive-pair — Chow's
N-switch coverage at N=2 restricted to the DRIVE×DRIVE subspace
(both transitions TB-driven, which is where write-visibility faults
in the RNF_COHERENCE_BUG.md class live).

Vector shape:
  [BFS shortest-path prefix to src(edge_in)]  +  edge_in  +  edge_out

Output:
  vectors_rnf_2switch/<state>__<edge_in>__<edge_out>.txt

The 1-switch dir vectors_rnf/ is left untouched.
"""

import argparse
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

# Re-use everything from the 1-switch generator so we don't diverge.
from gen_from_rnf import (
    DRIVE_RULES,
    extract_rnf_graph,
    build_adj,
    bfs_shortest_paths,
    find_initial,
    event_label,
    short_state_name,
    render_vector,
    safe_basename,
    ADDR_COHERENT,
)

VEC_DIR_2S = os.path.join(HERE, "vectors_rnf_2switch")


def is_drive_rule(rule):
    return any(rule.startswith(d) for d in DRIVE_RULES)


def coverage_targets_2switch_drivedrive(adj, paths):
    """Enumerate every (mid_state, drive_edge_in, drive_edge_out) triple
    where both edges are DRIVE and mid_state is reachable and edge_in
    ends at mid_state, edge_out starts at mid_state."""
    # in_edges[mid] = list of (rule_in, src_of_edge_in)
    reachable = set(paths.keys())
    in_edges = {s: [] for s in reachable}
    for s, es in adj.items():
        if s not in reachable:
            continue
        for rule, dst in es:
            if dst in reachable:
                in_edges[dst].append((rule, s))

    targets = []
    for mid in reachable:
        drive_ins = [(r, u) for (r, u) in in_edges[mid] if is_drive_rule(r)]
        if not drive_ins:
            continue
        for r_out, v in adj.get(mid, []):
            if v not in reachable:
                continue
            if not is_drive_rule(r_out):
                continue
            for r_in, u in drive_ins:
                targets.append((u, r_in, mid, r_out, v))
    return targets


def emit_vectors_2switch(adj, initial, out_dir=VEC_DIR_2S):
    os.makedirs(out_dir, exist_ok=True)
    paths = bfs_shortest_paths(adj, initial)
    targets = coverage_targets_2switch_drivedrive(adj, paths)
    seen = set()
    emitted = 0
    skipped = 0
    for src, rule_in, mid, rule_out, dst in targets:
        prefix = paths.get(src)
        if prefix is None:
            skipped += 1
            continue
        full = prefix + [(rule_in, src, mid), (rule_out, mid, dst)]
        # Filename: <mid_state>__<edge_in>__<edge_out>
        # Use edge_in's rendered event label + edge_out's for uniqueness.
        _, ev_in = event_label(rule_in, src, mid)
        _, ev_out = event_label(rule_out, mid, dst)
        mid_name = short_state_name(mid)
        base = safe_basename(f"{mid_name}__{ev_in}__{ev_out}")
        name = base
        n = 1
        while name in seen:
            n += 1
            name = f"{base}__{n}"
        seen.add(name)
        target_state_label = f"{mid_name} -> {short_state_name(dst)}"
        target_event_label = f"{ev_in} ; {ev_out}"
        with open(os.path.join(out_dir, f"{name}.txt"), "w") as f:
            f.write(render_vector(target_state_label, target_event_label, full))
        emitted += 1
    return emitted, skipped


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--summary", action="store_true")
    ap.add_argument("--vectors", action="store_true")
    args = ap.parse_args()

    states, edges = extract_rnf_graph()
    adj = build_adj(edges)
    initial = find_initial(adj)
    paths = bfs_shortest_paths(adj, initial)

    if args.summary or (not args.vectors):
        targets = coverage_targets_2switch_drivedrive(adj, paths)
        print(f"RN-F FSM:            {len(adj)} reachable states, {len(edges)} edges")
        print(f"Initial state:       {short_state_name(initial)}")
        print(f"2-switch DD targets: {len(targets)}")
        print(f"Output dir:          {VEC_DIR_2S}")

    if args.vectors:
        n, skipped = emit_vectors_2switch(adj, initial)
        print(f"Emitted {n} vectors to {VEC_DIR_2S}/ (skipped {skipped})")


if __name__ == "__main__":
    main()
