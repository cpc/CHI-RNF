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
measure_2switch_traversal.py -- how many of the model's 2-switch
transition pairs does a vector set actually traverse?

This is the metric the directed generator OPTIMISES, as opposed to the
SystemVerilog covergroups, which were written independently of the model
and which the generator therefore has no guarantee over.  Directed is
100% by construction (one vector per target, unreachable=0).  Random has
no notion of model state, so it traverses pairs only incidentally.

Method: replay each vector's DRIVE events through the model FSM from the
initial state, matching an event to an outgoing edge by its event label.
Events with no matching edge at the current state are SKIPPED and the
walk continues -- deliberately generous to random, since aborting on the
first illegal event would understate it.

No simulation required; the FSM and the vectors are both already here.

Usage:  ./measure_2switch_traversal.py vectors_rnf_random [vectors_...]
"""
import os
import sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from gen_from_rnf import (extract_rnf_graph, build_adj, bfs_shortest_paths,
                          find_initial, event_label)
from gen_from_rnf_2switch import (coverage_targets_2switch_drivedrive,
                                  is_drive_rule)


def load_events(path):
    """DRIVE event tokens from a vector file, in order."""
    evs = []
    with open(path) as f:
        for line in f:
            if "DRIVE" not in line or line.lstrip().startswith("#"):
                continue
            parts = [p.strip() for p in line.split("|")]
            if len(parts) >= 3:
                evs.append(parts[2])
    return evs


def main():
    dirs = sys.argv[1:] or ["vectors_rnf_random"]

    nodes, edges = extract_rnf_graph()
    adj = build_adj(edges)
    initial = find_initial(nodes)
    paths = bfs_shortest_paths(adj, initial)
    targets = coverage_targets_2switch_drivedrive(adj, paths)
    tset = set(targets)
    print("model: %d reachable states, %d 2-switch DD targets"
          % (len(paths), len(tset)))

    # event label -> outgoing (rule, dst), per state
    bylabel = defaultdict(list)
    for s, es in adj.items():
        for rule, dst in es:
            lab = event_label(rule, s, dst)
            if isinstance(lab, tuple):
                lab = lab[-1]
            bylabel[(s, lab)].append((rule, dst))

    for d in dirs:
        base = d if os.path.isabs(d) else os.path.join(HERE, d)
        if not os.path.isdir(base):
            print("  %-28s MISSING" % d)
            continue
        files = sorted(f for f in os.listdir(base) if f.endswith(".txt")
                       and f != "manifest.txt")
        hit = set()
        matched = total = 0
        for fn in files:
            st = initial
            prev = None          # (src, rule_in) of the last DRIVE edge
            for ev in load_events(os.path.join(base, fn)):
                total += 1
                cand = bylabel.get((st, ev))
                if not cand:
                    prev = None  # walk broken; no pair can span the gap
                    continue
                rule, dst = cand[0]
                matched += 1
                if prev is not None and is_drive_rule(rule) \
                        and is_drive_rule(prev[1]):
                    t = (prev[0], prev[1], st, rule, dst)
                    if t in tset:
                        hit.add(t)
                prev = (st, rule) if is_drive_rule(rule) else None
                st = dst
        pct = 100.0 * len(hit) / len(tset) if tset else 0.0
        print("  %-28s %6d/%d pairs = %5.2f%%   (%d/%d events matched an edge)"
              % (d, len(hit), len(tset), pct, matched, total))


if __name__ == "__main__":
    main()
