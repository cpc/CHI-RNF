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
Emit hnf_fsm.yaml as a Graphviz DOT file for visualization.

Output conventions:
  - Stable states     → solid ellipse
  - Transient states  → dashed octagon
  - Initial state     → bold double-outline
  - REQ_A_*           → blue edge  (RN-F A drives)
  - REQ_B_*           → red  edge  (RN-F B drives)
  - SNP_RESP_*        → orange edge (peer's response)
  - COMPACK_*         → green edge
  - SNF_* / INT_*     → grey  dashed edge (internal / automatic)

Usage:
  ./to_dot.py                          # → hnf_fsm.dot on stdout
  ./to_dot.py -o hnf_fsm.dot
  ./to_dot.py -o hnf_fsm.dot --render  # also runs `dot -Tpng -O`
"""

import argparse
import os
import sys
import subprocess

try:
    import yaml
except ImportError:
    sys.exit("PyYAML required: pip install --user --break-system-packages pyyaml")

HERE = os.path.dirname(os.path.abspath(__file__))
FSM_PATH = os.path.join(HERE, "hnf_fsm.yaml")


def edge_style(event):
    # CAM-hazard self-loops get a distinct purple dotted style
    if event.endswith("__HAZARD"):
        return 'color="#9467bd", style="dotted", fontcolor="#9467bd"'
    if event.startswith("REQ_A_"):
        return 'color="#1f77b4"'             # blue
    if event.startswith("REQ_B_"):
        return 'color="#d62728"'             # red
    if event.startswith("SNP_RESP_"):
        return 'color="#ff7f0e"'             # orange
    if event.startswith("COMPACK_"):
        return 'color="#2ca02c"'             # green
    if event.startswith("SNF_") or event.startswith("INT_"):
        return 'color="#7f7f7f", style="dashed"'    # grey
    return 'color="black"'


def state_style(name, transient, is_initial):
    # Pending-REQ composite states (__PEND_*) are auto-generated and
    # numerous — fade them into the background so the core FSM dominates
    # the diagram.
    is_pend = "__PEND_" in name
    if is_initial:
        # Initial state: gold double-circle, large and bold
        return ('shape=doublecircle, style="bold,filled", '
                'fillcolor="#ffd700", color="#000000", penwidth=3, '
                'fontsize=14, fontcolor="black"')
    if not transient:
        # Stable states: saturated colour, white bold text, thick border.
        # These are the "anchor" states in the FSM and should pop visually.
        if is_pend:
            # Stable __PEND_ variants — softer than core stables but still
            # filled (so they're distinguishable from transients)
            return ('shape=ellipse, style="filled", fillcolor="#b3d4f5", '
                    'color="#1f4e79", penwidth=1, fontsize=8')
        return ('shape=ellipse, style="filled", fillcolor="#1f4e79", '
                'color="#0b2540", penwidth=3, fontsize=14, '
                'fontcolor="white"')
    # Transients
    if is_pend:
        # Pending transient variants — muted and small
        return ('shape=octagon, style="dotted,filled", fillcolor="#f5f5f5", '
                'color="#bbbbbb", fontcolor="#666666", fontsize=8')
    # Core transient states (T_FILL_*, T_SNP_*, T_ACK_*)
    return ('shape=octagon, style="dashed,filled", fillcolor="#fff3d6", '
            'color="#7a5a00", penwidth=2, fontsize=11')


def short_event(ev):
    """Compact edge label to keep the graph legible."""
    if ev.endswith("__HAZARD"):
        # REQ_B_ReadClean__HAZARD → ⚡B_ReadClean
        rest = ev.replace("REQ_", "").replace("__HAZARD", "")
        return "⚡" + rest
    if ev.startswith("REQ_"):
        return ev.replace("REQ_", "")
    if ev.startswith("SNP_RESP_"):
        # SNP_RESP_A_I_FOR_ReadClean → SnpResp_A:I_RC
        rest = ev.replace("SNP_RESP_", "")
        return "SR_" + rest
    if ev.startswith("COMPACK_"):
        return ev.replace("COMPACK_", "Ack_")
    if ev.startswith("SNF_"):
        return ev.replace("SNF_", "")
    return ev


def to_dot(yaml_path=FSM_PATH):
    with open(yaml_path) as f:
        d = yaml.safe_load(f)
    states = d["states"]
    edges  = d["edges"]
    initial = d["initial"]

    lines = []
    lines.append("digraph hnf_fsm {")
    lines.append('  rankdir=LR;')
    lines.append('  graph [fontname="Helvetica", fontsize=11, splines=true, nodesep=0.5, ranksep=0.7];')
    lines.append('  node  [fontname="Helvetica", fontsize=10];')
    lines.append('  edge  [fontname="Helvetica", fontsize=8];')
    lines.append('')

    # Group stable vs transient with subgraphs (visual hint, no rank-pin)
    lines.append("  // ── states ──")
    for name, info in states.items():
        is_init = (name == initial)
        style   = state_style(name, info.get("transient", False), is_init)
        lines.append(f'  "{name}" [{style}];')

    lines.append('')
    lines.append("  // ── edges ──")
    for e in edges:
        fr  = e["from"]
        to  = e["to"]
        ev  = e["event"]
        lbl = short_event(ev)
        st  = edge_style(ev)
        lines.append(f'  "{fr}" -> "{to}" [label="{lbl}", {st}];')

    # Legend (subgraph with cluster prefix for box)
    lines.append('')
    lines.append("  // ── legend ──")
    lines.append("  subgraph cluster_legend {")
    lines.append('    label="Legend"; style="dashed"; fontsize=10;')
    lines.append('    L_initial   [label="initial state", shape=doublecircle, style="bold,filled", fillcolor="#ffd700", penwidth=3];')
    lines.append('    L_stable    [label="stable", shape=ellipse, style="filled", fillcolor="#1f4e79", fontcolor="white", penwidth=3];')
    lines.append('    L_transient [label="transient", shape=octagon, style="dashed,filled", fillcolor="#fff3d6", penwidth=2];')
    lines.append('    L_pendS     [label="stable + pending", shape=ellipse, style="filled", fillcolor="#b3d4f5", fontsize=8];')
    lines.append('    L_pendT     [label="transient + pending", shape=octagon, style="dotted,filled", fillcolor="#f5f5f5", fontcolor="#666666", fontsize=8];')
    lines.append('    L_a [label="RN-F A REQ",  shape=plaintext, fontcolor="#1f77b4"];')
    lines.append('    L_b [label="RN-F B REQ",  shape=plaintext, fontcolor="#d62728"];')
    lines.append('    L_s [label="SnpResp",     shape=plaintext, fontcolor="#ff7f0e"];')
    lines.append('    L_c [label="CompAck",     shape=plaintext, fontcolor="#2ca02c"];')
    lines.append('    L_i [label="internal/auto",shape=plaintext, fontcolor="#7f7f7f"];')
    lines.append('    L_h [label="CAM hazard (⚡)",shape=plaintext, fontcolor="#9467bd"];')
    lines.append("  }")
    lines.append("}")
    return "\n".join(lines) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-o", "--output", help="write DOT to this file (default: stdout)")
    ap.add_argument("--render", action="store_true",
                    help="also run `dot -Tpng -O <output>` to produce a .png")
    args = ap.parse_args()

    text = to_dot()
    if args.output:
        with open(args.output, "w") as f:
            f.write(text)
        print(f"wrote {args.output}", file=sys.stderr)
        if args.render:
            r = subprocess.run(["dot", "-Tpng", "-O", args.output])
            if r.returncode == 0:
                print(f"rendered {args.output}.png", file=sys.stderr)
            else:
                print("dot failed — is graphviz installed?", file=sys.stderr)
                sys.exit(r.returncode)
    else:
        sys.stdout.write(text)


if __name__ == "__main__":
    main()
