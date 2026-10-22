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
Extract HN-F-relevant info from the RTL so the test generator stays in
sync with the actual implementation:

  1. Full opcode table from chie_defines.v
  2. List of per-opcode MSHR tracker flags from hnf_mshr_ctl.v
     (each flag identifies an opcode the HNF actually tracks; opcodes
     NOT in this list are either unsupported or handled in a degenerate
     fast path)
  3. Cross-check: opcodes referenced in hnf_fsm.yaml that are missing
     from the RTL, and tracked opcodes the FSM doesn't model yet.

Usage:
  ./extract_rtl.py                 # full report
  ./extract_rtl.py --emit-yaml     # emit machine-readable extracted_opcodes.yaml
"""

import argparse
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
CHIE_DEFINES = os.path.join(REPO, "cva6-RNF", "cache", "include", "chie_defines.v")
MSHR_CTL     = os.path.join(REPO, "cva6-RNF", "opennoc", "rtl", "src", "hnf",
                            "hnf_mshr_ctl.v")
FSM_YAML     = os.path.join(HERE, "hnf_fsm.yaml")


OPCODE_RE = re.compile(
    r"^`define\s+(CHIE_[A-Z0-9_]+)\s+\{1'h([01]),\s*6'h([0-9a-fA-F]+)\}"
)


def extract_opcodes(path=CHIE_DEFINES):
    """Returns dict name -> 7-bit value (int)."""
    out = {}
    with open(path) as f:
        for line in f:
            m = OPCODE_RE.match(line.rstrip())
            if not m:
                continue
            name = m.group(1)
            msb  = int(m.group(2))
            lsb  = int(m.group(3), 16)
            out[name] = (msb << 6) | lsb
    return out


MSHR_FLAG_RE = re.compile(
    r"reg\s*\[`MSHR_ENTRIES_NUM-1:0\]\s+(mshr_[a-z_]+_s1_q)\s*;"
)

# Map MSHR flag name -> canonical opcode name (CHIE_*). Built from comments /
# context in hnf_mshr_ctl.v; this is the part where heuristic mapping kicks in
# and may need extending as the RTL grows.
MSHR_FLAG_TO_OPCODE = {
    "mshr_rdnosnp_s1_q":  "CHIE_READNOSNP",
    "mshr_ro_s1_q":       "CHIE_READONCE",
    "mshr_rdnosd_s1_q":   "CHIE_READNOTSHAREDDIRTY",
    "mshr_ru_s1_q":       "CHIE_READUNIQUE",
    "mshr_rc_s1_q":       "CHIE_READCLEAN",
    "mshr_wrnosnp_s1_q":  "CHIE_WRITENOSNPFULL",
    "mshr_wrnosnpp_s1_q": "CHIE_WRITENOSNPPTL",
    "mshr_wu_s1_q":       "CHIE_WRITEUNIQUEFULL",   # ambiguous: full/ptl share base
    # WriteUniquePtl intentionally excluded from the test pipeline — partial
    # byte-enable merge path has open issues; do not stress-test until fixed.
    # "mshr_wup_s1_q":      "CHIE_WRITEUNIQUEPTL",
    "mshr_wuf_s1_q":      "CHIE_WRITEUNIQUEFULL",
    "mshr_wb_s1_q":       "CHIE_WRITEBACKFULL",
    "mshr_wc_s1_q":       "CHIE_WRITECLEANFULL",
    "mshr_we_s1_q":       "CHIE_WRITEEVICTFULL",
    "mshr_mu_s1_q":       "CHIE_MAKEUNIQUE",
    "mshr_cu_s1_q":       "CHIE_CLEANUNIQUE",
    "mshr_evi_s1_q":      "CHIE_EVICT",
    "mshr_cs_s1_q":       "CHIE_CLEANSHARED",
    "mshr_ci_s1_q":       "CHIE_CLEANINVALID",
    # Atomics tracked by the HN-F RMW path.  atomicld groups
    # {AtomicLoad_*, AtomicSwap, AtomicCompare} (CompData-return shape);
    # atomicst is the Comp-only AtomicStore_* family.  Both decode to
    # the *_ADD canonical opcode; SWAP is distinguished by mshr_atomic_op.
    "mshr_atomicld_s1_q": "CHIE_ATOMICLOAD_ADD",
    "mshr_atomicst_s1_q": "CHIE_ATOMICSTORE_ADD",
}


def extract_mshr_flags(path=MSHR_CTL):
    """Returns list of (flag_name, opcode_name_or_None) in declaration order."""
    out = []
    with open(path) as f:
        for line in f:
            m = MSHR_FLAG_RE.search(line)
            if not m:
                continue
            flag = m.group(1)
            # only interested in per-opcode trackers (skip control flags like
            # mshr_can_alloc_entry, mshr_sn_order, mshr_excl, mshr_compack, ...)
            if flag in MSHR_FLAG_TO_OPCODE:
                out.append((flag, MSHR_FLAG_TO_OPCODE[flag]))
    return out


REQ_EVENT_RE = re.compile(r"REQ_[AB]_([A-Za-z0-9]+)")


def extract_fsm_opcodes(path=FSM_YAML):
    """Returns set of opcode names (without REQ_X_ prefix) referenced in FSM
    edges. Pure regex — avoids the PyYAML dep here so the script also works
    in trimmed environments."""
    names = set()
    with open(path) as f:
        for line in f:
            for m in REQ_EVENT_RE.finditer(line):
                names.add(m.group(1))
    return names


# Map FSM short-names -> canonical CHIE_* names.
FSM_TO_CHIE = {
    "ReadClean":          "CHIE_READCLEAN",
    "ReadUnique":         "CHIE_READUNIQUE",
    "ReadNotSharedDirty": "CHIE_READNOTSHAREDDIRTY",
    "ReadOnce":           "CHIE_READONCE",
    "ReadNoSnp":          "CHIE_READNOSNP",
    "MakeUnique":         "CHIE_MAKEUNIQUE",
    "CleanUnique":        "CHIE_CLEANUNIQUE",
    "CleanInvalid":       "CHIE_CLEANINVALID",
    "CleanShared":        "CHIE_CLEANSHARED",
    "Evict":              "CHIE_EVICT",
    "WriteBackFull":      "CHIE_WRITEBACKFULL",
    "WriteEvictFull":     "CHIE_WRITEEVICTFULL",
    "WriteCleanFull":     "CHIE_WRITECLEANFULL",
    "WriteUniqueFull":    "CHIE_WRITEUNIQUEFULL",
    "WriteNoSnpFull":     "CHIE_WRITENOSNPFULL",
    "AtomicLoad":         "CHIE_ATOMICLOAD_ADD",
    "AtomicStore":        "CHIE_ATOMICSTORE_ADD",
    "AtomicSwap":         "CHIE_ATOMICSWAP",
}

# Some FSM events accept *any* of several concrete opcodes on the wire.
# Atomics: the Murphi model abstracts {AtomicLoad_*, AtomicSwap} as a
# single "AtomicLoad" rule because they share the protocol shape.  The
# replay engine intentionally alternates AtomicLoad_ADD and AtomicSwap
# so coverage hits both ALU paths.  The oracle therefore treats either
# concrete CHIE_* opcode as a valid match for the abstract event.
FSM_TO_CHIE_ALT = {
    "AtomicLoad":         ["CHIE_ATOMICLOAD_ADD", "CHIE_ATOMICSWAP"],
}


def report(opc, flags, fsm_ops, args):
    print(f"# RTL extraction report")
    print(f"# repo: {REPO}")
    print()

    print(f"## Opcode table  ({len(opc)} entries from chie_defines.v)")
    if args.verbose:
        for name, val in sorted(opc.items(), key=lambda x: x[1]):
            print(f"  0x{val:02x}  {name}")
        print()

    print(f"## MSHR-tracked opcodes  ({len(flags)} flags found in hnf_mshr_ctl.v)")
    print(f"#   flag                    -> opcode                            value")
    for flag, op in flags:
        val = opc.get(op, None)
        vs  = f"0x{val:02x}" if val is not None else "??"
        print(f"  {flag:24s} -> {op:34s} {vs}")
    print()

    tracked = {op for _, op in flags}

    print(f"## FSM opcode coverage")
    print(f"#   FSM-referenced ops: {len(fsm_ops)}")
    missing_in_rtl = []
    not_modeled    = []
    for short in sorted(fsm_ops):
        chie = FSM_TO_CHIE.get(short)
        if chie is None:
            missing_in_rtl.append(short)
            print(f"   FSM op '{short}' has no mapping to CHIE_* (extend FSM_TO_CHIE)")
        elif chie not in opc:
            missing_in_rtl.append(short)
            print(f"   FSM op '{short}' -> {chie} not in chie_defines.v")
    for op in sorted(tracked):
        short = next((k for k, v in FSM_TO_CHIE.items() if v == op), None)
        if short is None or short not in fsm_ops:
            not_modeled.append(op)
    if not_modeled:
        print()
        print(f"## Tracked opcodes NOT YET modeled in hnf_fsm.yaml  ({len(not_modeled)})")
        for op in not_modeled:
            val = opc.get(op, 0)
            print(f"   0x{val:02x}  {op}   <- candidate for FSM expansion")

    if args.emit_yaml:
        out_path = os.path.join(HERE, "extracted_opcodes.yaml")
        with open(out_path, "w") as f:
            f.write("# Auto-generated by extract_rtl.py — do not hand-edit.\n")
            f.write("opcodes:\n")
            for name, val in sorted(opc.items(), key=lambda x: x[1]):
                f.write(f"  {name}: 0x{val:02x}\n")
            f.write("\nmshr_tracked:\n")
            for flag, op in flags:
                f.write(f"  - {{ flag: {flag},  opcode: {op} }}\n")
        print(f"\nWrote {out_path}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--verbose", "-v", action="store_true",
                    help="dump full opcode table")
    ap.add_argument("--emit-yaml", action="store_true",
                    help="emit extracted_opcodes.yaml")
    args = ap.parse_args()

    opc   = extract_opcodes()
    flags = extract_mshr_flags()
    fsm   = extract_fsm_opcodes()

    if not opc:
        sys.exit(f"no opcodes extracted from {CHIE_DEFINES}")
    if not flags:
        sys.exit(f"no MSHR flags extracted from {MSHR_CTL}")

    report(opc, flags, fsm, args)


if __name__ == "__main__":
    main()
