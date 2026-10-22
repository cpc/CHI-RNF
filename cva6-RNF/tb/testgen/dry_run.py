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
Dry-run companion to replay_vector.{h,cpp}. Parses a vector .txt file
exactly as the C++ runner does and prints the dispatch trace that the
C++ orchestrator + worker would execute on the real chi_tlm_rnf
instances.

Use this to sanity-check vectors before recompiling Questa.

  ./dry_run.py vectors/SC_AB__REQ_B_CleanUnique.txt
  ./dry_run.py vectors/UC_A__REQ_A_Evict.txt --addr 0x80000200
"""

import argparse
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))

# Mirror of dispatch_op() in replay_vector.cpp
DISPATCH = {
    "ReadClean":          "do_read",
    "ReadUnique":         "do_read_unique",
    "ReadNotSharedDirty": "do_read_not_shared_dirty",
    "ReadOnce":           "do_read_once",
    "ReadNoSnp":          "do_read_no_snp",
    "MakeUnique":         "do_make_unique",
    "CleanUnique":        "do_clean_unique",
    "CleanInvalid":       "do_clean_invalid",
    "CleanShared":        "do_clean_shared",
    "Evict":              "do_evict",
    "WriteBackFull":      "do_write_back_full",
    "WriteUniqueFull":    "do_write",
    "WriteNoSnpFull":     "do_write_no_snp_full",
}

REQ_RE = re.compile(r"^REQ_([AB])_(.+)$")


def parse_vector_file(path):
    """Return list of dicts: {kind, event, action, from_state, to_state}."""
    steps = []
    with open(path) as f:
        for line in f:
            line = line.rstrip("\n")
            t = line.strip()
            if not t or t.startswith("#"):
                continue
            cols = [c.strip() for c in t.split("|")]
            if len(cols) < 5:
                continue
            arrow = cols[4]
            if "->" in arrow:
                fs, ts = [s.strip() for s in arrow.split("->", 1)]
            else:
                fs, ts = "", ""
            steps.append({
                "kind":   cols[1],
                "event":  cols[2],
                "action": cols[3],
                "from":   fs,
                "to":     ts,
            })
    return steps


def dry_run(path, addr):
    steps = parse_vector_file(path)
    print(f"# DRY-RUN  vector={path}  addr=0x{addr:x}  steps={len(steps)}")
    print(f"# {'#':>3} {'role':<12} {'op':<22} {'state-transition'}")
    print("# " + "-" * 76)

    skipped_implicit = 0
    skipped_nondrive = 0
    own_calls = []
    peer_calls = []

    for i, s in enumerate(steps, 1):
        if s["kind"] != "DRIVE":
            print(f"  {i:>3} {'SKIP-NONDRV':<12} {'-':<22} {s['from']} -> {s['to']}  ({s['event']})")
            skipped_nondrive += 1
            continue
        m = REQ_RE.match(s["event"])
        if not m:
            print(f"  {i:>3} {'IMPLICIT':<12} {'-':<22} {s['from']} -> {s['to']}  ({s['event']})")
            skipped_implicit += 1
            continue
        rnf_letter, op = m.group(1), m.group(2)
        rnf_id = ord(rnf_letter) - ord('A')
        fn = DISPATCH.get(op, f"<UNSUPPORTED:{op}>")
        role = "ORCHESTR" if rnf_id == 0 else "WORKER"
        print(f"  {i:>3} {role+'/RNF'+str(rnf_id):<12} {fn+'('+hex(addr)+')':<22} {s['from']} -> {s['to']}")
        if rnf_id == 0:
            own_calls.append((fn, op))
        else:
            peer_calls.append((fn, op))

    print()
    print(f"# Summary")
    print(f"#   RNF0 (orchestrator) issues:  {len(own_calls)}")
    print(f"#   RNF1 (worker) issues:        {len(peer_calls)}")
    print(f"#   skipped (implicit FSM evt):  {skipped_implicit}")
    print(f"#   skipped (non-DRIVE row):     {skipped_nondrive}")

    unsupported = [op for fn, op in own_calls + peer_calls if fn.startswith("<UNSUPPORTED")]
    if unsupported:
        print(f"#   !! unsupported ops:           {unsupported}")
        return 1
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("vector", help="path to a .txt vector emitted by gen_sequences.py")
    ap.add_argument("--addr", default="0x80000200",
                    help="line address used for replay (default 0x80000200)")
    args = ap.parse_args()
    addr = int(args.addr, 0)
    sys.exit(dry_run(args.vector, addr))


if __name__ == "__main__":
    main()
