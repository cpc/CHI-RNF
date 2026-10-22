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
State-graph extractor for murphi_sys/sys_fsm.m.

Reuses the rumur runner / model patcher / trace parser from
tb/testgen/murphi/to_dot.py; only the model path, the state-dump block
and the fingerprint parser are model-specific.

Two things differ from murphi_rnf/to_dot.py and both matter:

  * The fingerprint is COMPLETE.  rnf_fsm.m's dump omits rx_rettosrc
    and lr_valid, so states differing only in those collapse into one
    and BFS can hand back a path that does not actually establish the
    reservation / RetToSrc precondition it claims.  Every state variable
    is dumped here.

  * Per-agent attribution.  rumur's `Put <expr>` emits the EXPRESSION
    TEXT, not the evaluated index, so `Put l1[0]` yields `l1[0]:L1_I`.
    Agent identity therefore survives into the fingerprint directly and
    an event can be attributed by diffing agent i's group -- the
    patcher's own `RULE:` line carries no ruleset argument.

Usage:
  ./to_dot.py --stats
"""

import argparse
import os
import re
import sys
import tempfile

HERE   = os.path.dirname(os.path.abspath(__file__))
SHARED = os.path.abspath(os.path.join(HERE, "..", "murphi"))

# Load the shared runner BY PATH, not by sys.path order.  murphi_rnf's
# to_dot.py does `sys.path.insert(0, SHARED); import to_dot`, which
# resolves to whichever directory happens to be first -- import it from
# a caller whose sys.path[0] is this directory and it imports ITSELF,
# recursing until RecursionError.  gen_from_rnf.py works around that by
# ordering sys.path at the call site; an explicit path load removes the
# hazard instead of documenting it.
import importlib.util as _ilu
_spec = _ilu.spec_from_file_location(
    "_hnf_to_dot", os.path.join(SHARED, "to_dot.py"))
_hnf = _ilu.module_from_spec(_spec)
_spec.loader.exec_module(_hnf)

MODEL   = os.environ.get("MURPHI_MODEL", os.path.join(HERE, "sys_fsm.m"))
NUM_RNF = int(os.environ.get("NUM_RNF", "2"))

# Per-agent state variables, in fingerprint order.
AGENT_VARS = [
    ("l1",            r"L1_\w+"),
    ("tx_op",         r"tx_\w+"),
    ("tx_phase",      r"TX_\w+"),
    ("tx_expcompack", r"true|false"),
    ("rx_snp",        r"rx_\w+"),
    ("rx_resp_owed",  r"true|false"),
    ("rx_rettosrc",   r"true|false"),
    ("sw_queue",      r"sw_\w+"),
    ("lr_valid",      r"true|false"),
    ("h_snp_owed",    r"true|false"),
    ("h_wait",        r"true|false"),
    ("h_retire",      r"true|false"),
]

# HN-F scalars.
HNF_VARS = [
    ("h_busy",   r"true|false"),
    ("h_ext",    r"true|false"),
    ("h_op",     r"tx_\w+"),
    ("h_ext_op", r"ext_\w+"),
    ("h_dirty",  r"true|false"),
    ("h_req",    r"\d+"),
    ("bg_snp",   r"true|false"),
]


def make_dump_block(label):
    puts = []
    for i in range(NUM_RNF):
        for name, _ in AGENT_VARS:
            puts.append(f"Put {name}[{i}];")
    for name, _ in HNF_VARS:
        puts.append(f"Put {name};")
    body = "\n    ".join(puts)
    return f"""
    Put "STATE_{label}: ";
    {body}
    Put "STATE_END\\n";
    """


def normalize_state_body(body):
    """Map the Put'd field set back to a compact canonical string.
    Returns None on a fragmented dump (rumur's stdio buffering can
    split output across rule firings)."""
    parts = []
    for i in range(NUM_RNF):
        vals = []
        for name, pat in AGENT_VARS:
            m = re.search(rf"{re.escape(name)}\[{i}\]\s*:\s*({pat})(?=\s|$)", body)
            if not m:
                return None
            vals.append(m.group(1))
        parts.append(f"a{i}=[{','.join(vals)}]")
    for name, pat in HNF_VARS:
        m = re.search(rf"\b{re.escape(name)}\s*:\s*({pat})(?=\s|$)", body)
        if not m:
            return None
        parts.append(f"{name}={m.group(1)}")
    return " ".join(parts)


def patch_model(src_path, dst_path):
    saved = _hnf.make_dump_block
    _hnf.make_dump_block = make_dump_block
    try:
        _hnf.patch_model(src_path, dst_path)
    finally:
        _hnf.make_dump_block = saved


def parse_transitions(stdout):
    saved = _hnf.normalize_state_body
    saved_sq = _hnf.SYMMETRY_QUOTIENT
    _hnf.normalize_state_body = normalize_state_body
    _hnf.SYMMETRY_QUOTIENT = False      # DUT is distinguished; no quotient
    try:
        return _hnf.parse_transitions(stdout)
    finally:
        _hnf.normalize_state_body = saved
        _hnf.SYMMETRY_QUOTIENT = saved_sq


def extract(keep_dump=None):
    with tempfile.TemporaryDirectory() as td:
        pm = os.path.join(td, "p.m")
        cp = os.path.join(td, "p.c")
        bp = os.path.join(td, "p")
        patch_model(MODEL, pm)
        _hnf.run_rumur(pm, cp)
        _hnf.run_cc(cp, bp)
        out = _hnf.run_verifier(bp)
        if keep_dump:
            with open(keep_dump, "w") as f:
                f.write(out[:2000])
    states, edges = parse_transitions(out)
    return states, edges, len(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--stats", action="store_true")
    ap.add_argument("--sample", help="write the first 2 kB of raw dump here")
    args = ap.parse_args()
    states, edges, nbytes = extract(keep_dump=args.sample)
    rules = {}
    for _, _, r in edges:
        rules[r] = rules.get(r, 0) + 1
    print(f"dump size:   {nbytes/1e6:.1f} MB")
    print(f"states:      {len(states)}")
    print(f"edges:       {len(edges)}")
    print(f"rule names:  {len(rules)}")


if __name__ == "__main__":
    main()
