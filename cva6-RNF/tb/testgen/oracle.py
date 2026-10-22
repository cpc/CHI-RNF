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
Test-gen oracle: diffs an expected vector trace against an actual
simulation log containing the [MSHR_OBS] lines emitted by
mshr_observer.sv.

Comparison is structural at the *transaction* level, not flit level —
the FSM-vs-driver granularity mismatch (see README) means individual
COMPACK / SNP_RESP events are merged into the parent REQ. So the
oracle:

  1. Walks the expected vector and extracts the ordered list of
     REQ_<X>_<op> events.
  2. For each, computes the expected MSHR ALLOC signature:
        srcid = 0 for X=A, 1 for X=B
        op    = canonical opcode hex from extract_rtl.py
  3. Parses [MSHR_OBS] ALLOC lines from the sim log and aligns them
     against the expected list in order.
  4. Reports per-step PASS/FAIL plus any unmatched observations.

Usage:
  ./oracle.py vectors/UC_A__REQ_A_Evict.txt sim.log
  ./oracle.py vectors/fuzz/fuzz_seed00042_chain4.txt sim.log --verbose
"""

import argparse
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import extract_rtl as ex   # type: ignore


REQ_EDGE_RE = re.compile(r"REQ_([AB])_([A-Za-z0-9]+)")

# Opcodes that take the HNF *bypass* path (hnf_mshr_bypass.v classification
# signals req_cb_s0 / req_wuf_s0 / req_wup_s0 / req_rd_s0 / req_wrnosnp_s0).
# These never assert mshr_alloc_en_s1_q, so the mshr_observer bound to
# hnf_mshr_ctl will NOT emit an ALLOC line for them — and the oracle must
# not expect one.
#
# TODO: replace this allow-by-omission scheme with a proper observer on
# hnf_mshr_bypass that emits BYPASS events; then the oracle can verify
# the bypass actually fired instead of silently passing.
BYPASS_OPCODES = {
    # Empirically (scanned [MSHR_OBS] lines across all generated runs),
    # these opcodes never produce an ALLOC — they really do take the
    # hnf_mshr_bypass path and the oracle must not expect one.
    "WriteEvictFull",     # req_cb_s0
    "WriteCleanFull",     # req_cb_s0
    "WriteUniqueFull",    # req_wuf_s0
    "WriteUniquePtl",     # req_wup_s0
    "ReadOnce",           # req_rd_s0
    "WriteNoSnpPtl",      # req_wrnosnp_s0
    # NOTE: ReadNoSnp, WriteBackFull, WriteNoSnpFull were previously
    # listed here but the mshr_observer empirically DOES emit ALLOC for
    # them (their classifier output goes through a different MSHR path
    # than the pure bypass). Removed 2026-06-08 after Murphi sweep showed
    # 123/452 false oracle FAILs caused by this stale assumption.
}

# Note: SV $timeformat adds " ns" after %0t — the (?:\s+ns)? tolerates it.
ALLOC_RE = re.compile(
    r"\[MSHR_OBS\]\s+t=(\S+)(?:\s+ns)?\s+ALLOC\s+slot=(\d+)\s+op=0x([0-9a-fA-F]+)\s+"
    r"src=(\d+)\s+txn=0x([0-9a-fA-F]+)\s+addr=0x([0-9a-fA-F]+)\s+compack=([01])"
)
RETIRE_RE = re.compile(r"\[MSHR_OBS\]\s+t=(\S+)(?:\s+ns)?\s+RETIRE\s+slot=(\d+)")


def expected_allocs(vector_path):
    """Return list of dicts: {step, rnf, op_short, op_hex} in vector order."""
    opc = ex.extract_opcodes()
    expected = []
    step = 0
    with open(vector_path) as f:
        for line in f:
            t = line.strip()
            if not t or t.startswith("#"):
                continue
            cols = [c.strip() for c in t.split("|")]
            if len(cols) < 5:
                continue
            step += 1
            kind  = cols[1]
            event = cols[2]
            # DRIVE = self-issued blocking step. FORK = peer-issued
            # fire-and-forget step (cross-RN-F concurrent burst). Both
            # produce real REQ flits at the HNF, so both contribute to
            # the expected-ALLOC list. JOIN / OBSRV / IMPLICIT are bars
            # or auto-events with no flit emission — skip those.
            if kind != "DRIVE" and kind != "FORK":
                continue
            m = REQ_EDGE_RE.match(event)
            if not m:
                continue
            rnf_letter = m.group(1)
            op_short   = m.group(2)
            # Bypass-path opcodes never reach the regular MSHR; skip them
            # from the expected ALLOC stream. The transaction still runs in
            # sim — we just can't observe it from hnf_mshr_ctl. See
            # BYPASS_OPCODES note above.
            if op_short in BYPASS_OPCODES:
                continue
            chie_name  = ex.FSM_TO_CHIE.get(op_short)
            op_hex     = opc.get(chie_name) if chie_name else None
            # Some abstract events (e.g. AtomicLoad in the Murphi model)
            # match any of several concrete CHIE_* opcodes on the wire.
            alt_names  = getattr(ex, "FSM_TO_CHIE_ALT", {}).get(op_short, None)
            op_hex_set = set()
            if op_hex is not None:
                op_hex_set.add(op_hex)
            if alt_names:
                for n in alt_names:
                    v = opc.get(n)
                    if v is not None:
                        op_hex_set.add(v)
            expected.append({
                "step":      step,
                "event":     event,
                "rnf":       0 if rnf_letter == "A" else 1,
                "op_short":  op_short,
                "chie":      chie_name,
                "op_hex":    op_hex,
                "op_hex_set": op_hex_set,
            })
    return expected


def parse_simlog(path):
    """Returns (allocs, retires) — lists of dicts in time order."""
    allocs, retires = [], []
    with open(path) as f:
        for line in f:
            m = ALLOC_RE.search(line)
            if m:
                allocs.append({
                    "t":       m.group(1),
                    "slot":    int(m.group(2)),
                    "op_hex":  int(m.group(3), 16),
                    "src":     int(m.group(4)),
                    "txn":     int(m.group(5), 16),
                    "addr":    int(m.group(6), 16),
                    "compack": int(m.group(7)),
                })
                continue
            m = RETIRE_RE.search(line)
            if m:
                retires.append({
                    "t":    m.group(1),
                    "slot": int(m.group(2)),
                })
    return allocs, retires


def compare(expected, allocs, verbose=False, unordered=False):
    """Align expected vs observed. Ordered mode (default): positional
    match — pass iff expected[i] equals observed[i] for every i. Used
    for BFS / burst / fuzz vectors where order is deterministic.

    Unordered mode (cross-RN-F concurrent): the FORK + DRIVE pair fires
    in non-deterministic order, so positional matching is wrong. Instead
    compare multisets of (src, op_hex) tuples. Pass iff the bag of
    expected equals the bag of observed."""
    fails = 0
    print(f"# Oracle diff:  expected={len(expected)}  observed={len(allocs)}"
          f"  mode={'unordered' if unordered else 'ordered'}")
    print(f"# {'#':>3} {'exp_rnf':>7} {'exp_op':<22} {'obs_rnf':>7} {'obs_op':<8} {'result'}")
    print("# " + "-" * 70)

    if unordered:
        from collections import Counter
        exp_bag = Counter((e["rnf"], e["op_hex"]) for e in expected)
        obs_bag = Counter((o["src"], o["op_hex"]) for o in allocs)
        # symmetric diff
        missing = exp_bag - obs_bag
        extra   = obs_bag - exp_bag
        for (rnf, op_hex), cnt in sorted(missing.items()):
            for _ in range(cnt):
                print(f"   - {rnf:>7} 0x{op_hex:02x}{'':<19} {'-':>7} {'-':<8} MISSING")
                fails += 1
        for (rnf, op_hex), cnt in sorted(extra.items()):
            for _ in range(cnt):
                print(f"   - {'-':>7} {'-':<22} {rnf:>7} 0x{op_hex:02x}{'':<5} EXTRA")
                fails += 1
        if verbose and fails == 0:
            for (rnf, op_hex), cnt in sorted(exp_bag.items()):
                print(f"   - {rnf:>7} 0x{op_hex:02x}{'':<19} {rnf:>7} 0x{op_hex:02x}{'':<5} OK (×{cnt})")
        return fails

    # ordered (default)
    n = max(len(expected), len(allocs))
    for i in range(n):
        e = expected[i] if i < len(expected) else None
        o = allocs[i]   if i < len(allocs)   else None
        if e is None:
            print(f"  {i+1:>3} {'-':>7} {'-':<22} {o['src']:>7} {hex(o['op_hex']):<8} EXTRA")
            fails += 1
            continue
        if o is None:
            tag = f"{e['op_short']}({hex(e['op_hex']) if e['op_hex'] is not None else '??'})"
            print(f"  {i+1:>3} {e['rnf']:>7} {tag:<22} {'-':>7} {'-':<8} MISSING")
            fails += 1
            continue
        ok_rnf = (e["rnf"] == o["src"])
        # For atomics, e["op_hex_set"] holds all acceptable concrete
        # opcodes (e.g. {0x30, 0x38} for the abstract "AtomicLoad").
        ok_op  = (len(e["op_hex_set"]) > 0 and o["op_hex"] in e["op_hex_set"])
        if len(e["op_hex_set"]) > 1:
            tag = f"{e['op_short']}({'|'.join(hex(v) for v in sorted(e['op_hex_set']))})"
        else:
            tag = f"{e['op_short']}({hex(e['op_hex']) if e['op_hex'] is not None else '??'})"
        result = "OK" if (ok_rnf and ok_op) else "FAIL"
        if result == "FAIL":
            fails += 1
        if verbose or result != "OK":
            print(f"  {i+1:>3} {e['rnf']:>7} {tag:<22} {o['src']:>7} {hex(o['op_hex']):<8} {result}")
    return fails


def vector_has_fork(vector_path):
    """Return True if the vector contains any FORK step (cross-RN-F)."""
    with open(vector_path) as f:
        for line in f:
            t = line.strip()
            if not t or t.startswith("#"):
                continue
            cols = [c.strip() for c in t.split("|")]
            if len(cols) >= 2 and cols[1] == "FORK":
                return True
    return False


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("vector", help="path to expected vector .txt")
    ap.add_argument("simlog", help="path to simulation log containing [MSHR_OBS] lines")
    ap.add_argument("--verbose", "-v", action="store_true",
                    help="print every step, not just failures")
    args = ap.parse_args()

    if not os.path.exists(args.vector):
        sys.exit(f"vector not found: {args.vector}")
    if not os.path.exists(args.simlog):
        sys.exit(f"simlog not found: {args.simlog}")

    expected         = expected_allocs(args.vector)
    allocs, retires  = parse_simlog(args.simlog)
    unordered        = vector_has_fork(args.vector)

    fails = compare(expected, allocs, verbose=args.verbose, unordered=unordered)

    print()
    print(f"# Retires observed: {len(retires)}")
    print(f"# Final result:     {'PASS' if fails == 0 else f'FAIL ({fails} mismatch)'}")
    sys.exit(0 if fails == 0 else 1)


if __name__ == "__main__":
    main()
