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
gen_random_vectors.py -- constrained-random baseline for the model-based
directed generator (gen_from_rnf_prefix_shared.py).

Exists to answer one question: how much of the coverage that the
Murphi-directed vectors reach can be reached by random stimulus, and how
long does random take to get there?

CONSTRAINED, not uniform.  A uniform draw over the event alphabet spends
most of its steps on responses to transactions that were never issued,
which the L1.5 discards -- that would be a strawman.  This generator
enforces the well-formedness a hand-written constrained-random testbench
would have:

  * a memory op is followed by a response drawn from the shapes that are
    legal for its class (read / write / atomic / dataless)
  * responses are only emitted when a request is outstanding
  * snoops are injected at a tunable rate, independent of the above

What it does NOT have -- and this is the whole point of the comparison --
is any model of the protocol state space.  It cannot aim at a transition
it has not yet taken, so it re-walks easy states and only reaches deep
ones by luck.

Output format matches the directed vectors exactly (replay_vector in
rnf_ip_tb.sv only reads lines containing DRIVE and takes the event token),
so both sets run through the identical TB path.

Usage:
    ./gen_random_vectors.py --count 2000 --steps 65 --seed 1
"""

import argparse
import os
import random
import shutil

# ── Event alphabet: exactly what dispatch_sw / inject_env_snoop accept ──
# Kept identical to the TB's dispatch tables so neither generator has
# access to stimulus the other lacks.

READ_OPS = ["SW_enqueue_ReadClean", "SW_enqueue_NC_Load", "SW_enqueue_LR"]
WRITE_OPS = ["SW_enqueue_ReadUnique", "SW_enqueue_NC_Store",
             "SW_enqueue_MakeUnique", "SW_enqueue_SC",
             "SW_enqueue_WriteBackFull", "SW_enqueue_WriteCleanFull"]
ATOMIC_OPS = ["SW_enqueue_AtomicLoad", "SW_enqueue_AtomicStore"]
DATALESS_OPS = ["SW_enqueue_CleanInvalid", "SW_enqueue_CleanShared",
                "SW_enqueue_CleanUnique", "SW_enqueue_Evict",
                "SW_enqueue_SetConflict"]

SW_OPS = READ_OPS + WRITE_OPS + ATOMIC_OPS + DATALESS_OPS

SNOOPS = ["Env_Snp_SnpClean", "Env_Snp_SnpShared", "Env_Snp_SnpUnique",
          "Env_Snp_SnpCleanInvalid", "Env_Snp_SnpMakeInvalid"]

# ── Alphabet matching (default ON) ─────────────────────────────────────
# The TB can dispatch these five, but the Murphi model no longer emits
# them: no RTL in this design assigns Evict / CleanUnique /
# WriteCleanFull, and WriteBackFull now arises only as a side effect of
# a capacity eviction (Issue_SetConflict_dirty) rather than as a
# software event.  Leaving them in the random alphabet hands random a
# larger event set than the directed generator has, which is not a
# comparison of generation STRATEGY -- it is a comparison of alphabets,
# and it silently credits random with cells the directed set was never
# able to reach.  Drop them unless --full-alphabet is passed.
#
# KEEP THIS IN SYNC WITH SwOpEnabled() IN murphi_rnf/rnf_fsm.m.  As of
# 2026-08-13 that predicate enables ReadClean, ReadUnique, CleanShared,
# CleanInvalid, AtomicLoad, NC_Load, NC_Store, LR and SC, and disables
# MakeUnique / CBO_Zero (exact duplicates of ReadUnique on this RTL, all
# three emit ReadUnique 0x07), AtomicStore (no RTL path emits a CHI
# AtomicStore opcode).  SetConflict IS enabled -- it is the only source
# of eviction-driven WriteBackFull, so both sides must have it.  Anything the model cannot enqueue
# must not be in the random alphabet either, or the comparison measures
# alphabet rather than strategy.
DIRECTED_EXCLUDED = {
    "SW_enqueue_Evict",
    "SW_enqueue_CleanUnique",
    "SW_enqueue_WriteBackFull",
    "SW_enqueue_WriteCleanFull",
    "Env_Comp_for_Evict",
    # added 2026-08-13 to track SwOpEnabled()
    "SW_enqueue_MakeUnique",
    "SW_enqueue_CBO_Zero",
    "SW_enqueue_AtomicStore",
}

# Response shapes that are legal replies to each request class.  This is
# the "constrained" half: a constrained-random TB would know this much
# from the CHI spec without knowing anything about reachable states.
RESP_FOR = {
    "read": ["Env_CompData_clean", "Env_CompData_dirty"],
    "write": ["Env_DBIDResp_for_Write", "Env_CompDBIDResp_for_Write",
              "Env_Comp_for_WriteBack"],
    "atomic": ["Env_CompData_for_AtomicLoad", "Env_DBIDResp_for_Write",
               "Env_Comp_for_AtomicStore"],
    "dataless": ["Env_Comp_dataless", "Env_Comp_for_Evict"],
}


def op_class(op):
    if op in READ_OPS:
        return "read"
    if op in ATOMIC_OPS:
        return "atomic"
    if op in DATALESS_OPS:
        return "dataless"
    return "write"


def gen_vector(rng, n_steps, p_snoop):
    """One random vector: n_steps DRIVE events, well-formed req/resp pairs."""
    lines, step = [], 0
    while step < n_steps:
        # Independent snoop injection -- models an unrelated agent on the
        # interconnect, so it may land at any point including mid-tx.
        if rng.random() < p_snoop:
            lines.append((step, rng.choice(SNOOPS)))
            step += 1
            continue

        op = rng.choice(SW_OPS)
        lines.append((step, op))
        step += 1
        if step >= n_steps:
            break

        # Reply to it.  Occasionally skip, which exercises the TB's
        # program_default_for_sw fallback -- a real constrained-random
        # environment would have the same gap.
        if rng.random() < 0.85:
            lines.append((step, rng.choice(RESP_FOR[op_class(op)])))
            step += 1
    return lines


def write_vector(path, idx, seed, lines):
    with open(path, "w") as f:
        f.write("# Random vector %d  seed=%d  steps=%d\n" % (idx, seed, len(lines)))
        f.write("# Source: gen_random_vectors.py (constrained-random baseline)\n")
        f.write("# Format: step | kind | event | rule | from -> to\n")
        f.write("#" + "-" * 78 + "\n")
        for step, ev in lines:
            # 'rule' and the state columns are placeholders: the random
            # generator has no state model, which is precisely the
            # property under test.  replay_vector ignores both.
            f.write("%3d | DRIVE  | %-42s | %-36s | ? -> ?\n" % (step, ev, "random"))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--count", type=int, default=2000, help="number of vectors")
    ap.add_argument("--steps", type=int, default=65,
                    help="DRIVE steps per vector (65 matches the directed "
                         "set's 41273/631 average, so per-vector sim cost "
                         "is comparable)")
    ap.add_argument("--p-snoop", type=float, default=0.15)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--outdir", default=None)
    ap.add_argument("--full-alphabet", action="store_true",
                    help="keep the 5 events the Murphi model no longer "
                         "emits (Evict, CleanUnique, WriteBackFull, "
                         "WriteCleanFull, Env_Comp_for_Evict).  Off by "
                         "default so the comparison is alphabet-matched.")
    args = ap.parse_args()

    if not args.full_alphabet:
        for lst in (READ_OPS, WRITE_OPS, ATOMIC_OPS, DATALESS_OPS, SW_OPS, SNOOPS):
            lst[:] = [e for e in lst if e not in DIRECTED_EXCLUDED]
        for k in RESP_FOR:
            RESP_FOR[k] = [e for e in RESP_FOR[k] if e not in DIRECTED_EXCLUDED]
            if not RESP_FOR[k]:                     # dataless loses one of two
                RESP_FOR[k] = ["Env_Comp_dataless"]

    here = os.path.dirname(os.path.abspath(__file__))
    outdir = args.outdir or os.path.join(here, "vectors_rnf_random")
    if os.path.isdir(outdir):
        shutil.rmtree(outdir)
    os.makedirs(outdir)

    rng = random.Random(args.seed)
    total_steps = 0
    with open(os.path.join(outdir, "manifest.txt"), "w") as mf:
        mf.write("# name  file  steps\n")
        for i in range(args.count):
            lines = gen_vector(rng, args.steps, args.p_snoop)
            name = "rand_%05d" % i
            write_vector(os.path.join(outdir, name + ".txt"), i, args.seed, lines)
            mf.write("%s  %s.txt  %d\n" % (name, name, len(lines)))
            total_steps += len(lines)

    print("wrote %d vectors to %s" % (args.count, outdir))
    print("  %d DRIVE steps total, %.1f per vector"
          % (total_steps, total_steps / float(args.count)))


if __name__ == "__main__":
    main()
