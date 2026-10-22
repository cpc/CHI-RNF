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
"""Race-target vectors for cg_race_intersections.

The 2-switch target set enumerates DRIVE-DRIVE edge PAIRS.  It does not
enumerate the covergroup's race cross, so the 100 x_race cells are only
reached incidentally -- the prefix-shared set drives 60 of them and lands
26, because chained tails let the DUT drift away from the hub state the
model assumes.

This enumerates the cross itself as the coverage goal.  A race cell is

    (tx_phase, snoop_opcode, tx_op)

read off any model edge whose event is an Env_Snp_* and whose SOURCE
state has a transaction outstanding -- which is exactly the covergroup's
sample gate (fresh_snoop_during_tx: snoop arrives, tx_phase != TX_IDLE).

One STANDALONE vector per cell, walking from I via BFS and ending on the
snoop edge.  Standalone rather than prefix-shared on purpose: re-walking
from I keeps the DUT on the model's path, which is what the chained tails
lose.  Where several model edges land on the same cell, the one with the
shortest prefix wins.
"""

import argparse
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from gen_from_rnf import (
    extract_rnf_graph,
    build_adj,
    bfs_shortest_paths,
    find_initial,
    event_label,
    short_state_name,
    render_vector,
    safe_basename,
)

VEC_DIR = os.path.join(HERE, "vectors_rnf_race")

SNP_RE = re.compile(r"^Env_Snp_(Snp\w+?)(?:_RTS.*)?$")


def field(fp, name):
    m = re.search(rf"\b{name}=(\w+)", fp)
    return m.group(1) if m else ""


def race_cells(adj, paths):
    """(tx_phase, snoop_op, tx_op) -> (src_fp, rule, dst_fp), shortest prefix."""
    cells = {}
    for src, edges in adj.items():
        if src not in paths:
            continue
        phase = field(src, "tx_phase")
        op = field(src, "tx_op")
        # The covergroup's gate: a transaction must be in flight.
        if phase in ("", "TX_IDLE") or op in ("", "tx_None"):
            continue
        for rule, dst in edges:
            m = SNP_RE.match(rule)
            if not m:
                continue
            key = (phase, m.group(1), op)
            if key not in cells or len(paths[src]) < len(paths[cells[key][0]]):
                cells[key] = (src, rule, dst)
    return cells


def emit(cells, paths, out_dir=VEC_DIR):
    os.makedirs(out_dir, exist_ok=True)
    n = 0
    for (phase, snoop, op), (src, rule, dst) in sorted(cells.items()):
        path = paths[src] + [(rule, src, dst)]
        _, ev = event_label(rule, src, dst)
        fname = safe_basename(
            f"race_{phase.replace('TX_AWAIT_', '')}_{snoop}_{op.replace('tx_', '')}")
        with open(os.path.join(out_dir, f"{fname}.txt"), "w") as f:
            f.write(render_vector(short_state_name(src), ev, path))
        n += 1
    return n


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--vectors", action="store_true")
    args = ap.parse_args()

    states, edges = extract_rnf_graph()
    adj = build_adj(edges)
    initial = find_initial(adj)
    paths = bfs_shortest_paths(adj, initial)
    cells = race_cells(adj, paths)

    phases = sorted({k[0] for k in cells})
    snoops = sorted({k[1] for k in cells})
    ops = sorted({k[2] for k in cells})
    print(f"reachable race cells in the model: {len(cells)}")
    print(f"  tx_phase : {len(phases)}  {[p.replace('TX_AWAIT_', '') for p in phases]}")
    print(f"  snoop_op : {len(snoops)}  {snoops}")
    print(f"  tx_op    : {len(ops)}  {[o.replace('tx_', '') for o in ops]}")
    print(f"  prefix len: min={min(len(paths[v[0]]) for v in cells.values())} "
          f"max={max(len(paths[v[0]]) for v in cells.values())}")

    if args.vectors:
        n = emit(cells, paths)
        print(f"emitted {n} standalone race vectors -> {VEC_DIR}")


if __name__ == "__main__":
    main()
