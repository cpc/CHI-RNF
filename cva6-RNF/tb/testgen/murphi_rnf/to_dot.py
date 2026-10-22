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
Generate a Graphviz DOT diagram of the RN-F coherence FSM.

Reuses the rumur runner, model patcher, and trace parser from the
sibling tb/testgen/murphi/ directory.  Only the model-specific bits
(MODEL path, state-dump field set, fingerprint regex) live here.

Usage:
  ./to_dot.py                       # → rnf_fsm_murphi.dot + .png
  ./to_dot.py --no-render           # DOT only
"""

import argparse
import os
import re
import subprocess
import sys
import tempfile

HERE     = os.path.dirname(os.path.abspath(__file__))
SHARED   = os.path.abspath(os.path.join(HERE, "..", "murphi"))
sys.path.insert(0, SHARED)
import to_dot as _hnf   # type: ignore -- shared rumur runner + patcher

MODEL = os.environ.get("MURPHI_MODEL",
                       os.path.join(HERE, "rnf_fsm.m"))
RUMUR = _hnf.RUMUR

NUM_RNF = 1   # single-RN-F DUT model


# --------------------------------------------------------------------- #
# Model-specific state-dump block (Murphi Put statements)
# --------------------------------------------------------------------- #

def make_dump_block(label):
    """Emit one-line fingerprint of every RN-F state variable.

    Trimmed (2026-06-18): rx_resp_kind dropped (informational only;
    decision now encoded in rule name).  tx_data_dirty folded into
    tx_phase via TX_AWAIT_COMPACK_{CLEAN,DIRTY} split.
    """
    return f"""
    Put "STATE_{label}: ";
    Put "l1=";          Put l1;            Put " ";
    Put "tx_op=";       Put tx_op;         Put " ";
    Put "tx_phase=";    Put tx_phase;      Put " ";
    Put "tx_expack=";   Put tx_expcompack; Put " ";
    Put "rx_snp=";      Put rx_snp;        Put " ";
    Put "rx_owed=";     Put rx_resp_owed;  Put " ";
    Put "sw_q=";        Put sw_queue;      Put " ";
    Put "STATE_END\\n";
    """


# --------------------------------------------------------------------- #
# Reuse the parent's patch_model, but with our make_dump_block.
# patch_model takes its dump-block content from a closure, so we
# rebind it cleanly by monkey-patching just before the call.
# --------------------------------------------------------------------- #

def patch_model(src_path, dst_path):
    # Shadow the shared module's make_dump_block for the duration of
    # this call (it's used inside patch_model via module-level lookup).
    saved = _hnf.make_dump_block
    _hnf.make_dump_block = make_dump_block
    try:
        _hnf.patch_model(src_path, dst_path)
    finally:
        _hnf.make_dump_block = saved


run_rumur    = _hnf.run_rumur
run_cc       = _hnf.run_cc
run_verifier = _hnf.run_verifier


# --------------------------------------------------------------------- #
# Fingerprint parsing -- regex maps every Put'd field back to a string.
# --------------------------------------------------------------------- #

SYMMETRY_QUOTIENT = False   # single-RN-F model, no symmetry to quotient


def normalize_state_body(body):
    m = re.search(r"l1\s*:\s*(L1_\w+?)(?=\s|$)", body)
    if not m: return None
    l1 = m.group(1)

    m = re.search(r"tx_op\s*:\s*(tx_\w+?)(?=\s|$)", body)
    if not m: return None
    tx_op = m.group(1)

    m = re.search(r"tx_phase\s*:\s*(TX_\w+?)(?=\s|$)", body)
    if not m: return None
    tx_phase = m.group(1)

    m = re.search(r"tx_expcompack\s*:\s*(true|false)\b", body)
    if not m: return None
    tx_expack = m.group(1)

    m = re.search(r"rx_snp\s*:\s*(rx_\w+?)(?=\s|$)", body)
    if not m: return None
    rx_snp = m.group(1)

    m = re.search(r"rx_resp_owed\s*:\s*(true|false)\b", body)
    if not m: return None
    rx_owed = m.group(1)

    m = re.search(r"sw_queue\s*:\s*(sw_\w+?)(?=\s|$)", body)
    if not m: return None
    sw_q = m.group(1)

    return (
        f"l1={l1} tx_op={tx_op} tx_phase={tx_phase} "
        f"tx_expack={tx_expack} "
        f"rx_snp={rx_snp} rx_owed={rx_owed} "
        f"sw_q={sw_q}"
    )


# --------------------------------------------------------------------- #
# Trace parsing -- shadow normalize_state_body in the shared parser.
# --------------------------------------------------------------------- #

def parse_transitions(stdout):
    saved = _hnf.normalize_state_body
    saved_sq = _hnf.SYMMETRY_QUOTIENT
    _hnf.normalize_state_body = normalize_state_body
    _hnf.SYMMETRY_QUOTIENT = SYMMETRY_QUOTIENT
    try:
        return _hnf.parse_transitions(stdout)
    finally:
        _hnf.normalize_state_body = saved
        _hnf.SYMMETRY_QUOTIENT = saved_sq


# --------------------------------------------------------------------- #
# State naming / classification for DOT output
# --------------------------------------------------------------------- #

def state_short(s):
    parts = []
    m = re.search(r"l1=(L1_\w+)", s);    parts.append(m.group(1).replace("L1_", "")) if m else None
    m = re.search(r"tx_phase=(\w+)", s)
    if m and m.group(1) != "TX_IDLE":    parts.append(m.group(1).replace("TX_", ""))
    m = re.search(r"tx_op=(tx_\w+)", s)
    if m and m.group(1) != "tx_None":    parts.append(m.group(1).replace("tx_", ""))
    m = re.search(r"rx_snp=(rx_\w+)", s)
    if m and m.group(1) != "rx_None":    parts.append(m.group(1).replace("rx_", "S:"))
    m = re.search(r"sw_q=(sw_\w+)", s)
    if m and m.group(1) != "sw_None":    parts.append(m.group(1).replace("sw_", "Q:"))
    return "|".join(parts) or "init"


def classify(state_str):
    is_idle    = "tx_phase=TX_IDLE" in state_str
    has_snoop  = not ("rx_snp=rx_None" in state_str)
    has_swq    = not ("sw_q=sw_None"   in state_str)
    is_invalid = "l1=L1_I" in state_str

    if is_idle and not has_snoop and not has_swq:
        return "INITIAL" if is_invalid else "STABLE_CORE"
    if is_idle:
        return "STABLE_PEND"
    if not has_snoop and not has_swq:
        return "TRANSIENT_CORE"
    return "TRANSIENT_PEND"


# Reuse styling + DOT emitter unchanged.
state_style = _hnf.state_style


def emit_dot(states, edges, out_path):
    # Re-implement minimally to use our state_short/classify.
    lines = [
        "digraph rnf_fsm_murphi {",
        '  rankdir=LR;',
        '  graph [fontname="Helvetica", nodesep=0.3, ranksep=0.5, splines=true];',
        '  node [fontname="Helvetica"];',
        '  edge [fontname="Helvetica", fontsize=7, color="#888888", arrowsize=0.6];',
        "",
    ]
    node_id = {}
    for s in sorted(states):
        nid = f"n{len(node_id)}"
        node_id[s] = nid
        style = state_style(classify(s))
        label = state_short(s)
        lines.append(f'  {nid} [label="{label}", {style}, tooltip="{s}"];')
    lines.append("")
    from collections import defaultdict
    by_pair = defaultdict(list)
    for item in edges:
        src, dst, rule = item
        by_pair[(src, dst)].append(rule)
    for (src, dst), rules in sorted(by_pair.items()):
        if src not in node_id or dst not in node_id:
            continue
        uniq = sorted(set(r for r in rules if r))
        label = "\\n".join(uniq) if uniq else ""
        if label:
            lines.append(f'  {node_id[src]} -> {node_id[dst]} [label="{label}"];')
        else:
            lines.append(f'  {node_id[src]} -> {node_id[dst]};')
    lines.append("}")
    with open(out_path, "w") as f:
        f.write("\n".join(lines))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--no-render", action="store_true")
    args = ap.parse_args()

    with tempfile.TemporaryDirectory() as td:
        patched_m = os.path.join(td, "patched.m")
        c_path    = os.path.join(td, "patched.c")
        bin_path  = os.path.join(td, "patched")

        patch_model(MODEL, patched_m)
        run_rumur(patched_m, c_path)
        run_cc(c_path, bin_path)
        stdout = run_verifier(bin_path)

        states, edges = parse_transitions(stdout)
        print(f"[to_dot] {len(states)} states, {len(edges)} edges")
        dot_path = os.path.join(HERE, "rnf_fsm_murphi.dot")
        emit_dot(states, edges, dot_path)
        print(f"[to_dot] wrote {dot_path}")
        if not args.no_render:
            png_path = dot_path + ".png"
            r = subprocess.run(["dot", "-Tpng", "-o", png_path, dot_path],
                               capture_output=True, text=True)
            if r.returncode == 0:
                print(f"[to_dot] wrote {png_path}")
            else:
                print(f"[to_dot] dot failed: {r.stderr}", file=sys.stderr)


if __name__ == "__main__":
    main()
