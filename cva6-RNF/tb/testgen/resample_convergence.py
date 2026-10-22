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
"""Resample N convergence curves onto a fixed executed-event grid.

Every generator is sampled per batch, and a batch is a fixed number of
VECTORS -- but a directed vector executes ~54 DRIVE events and a random
one ~65, so the raw curves sit on different x-points and cannot be
plotted against each other directly.  Coverage is cumulative and
monotonic, so the correct resampling is a step function: at grid point E,
report the last measurement taken at or before E.  No interpolation --
inventing intermediate values would imply coverage the run never
demonstrated.

Grid points before a curve's first sample are left blank rather than
zero: nothing was measured there.

The bin TOTAL is read from the data (func_bins_tot), not hard-coded.  It
has already moved twice -- 343 -> 297 when protocol-impossible cross
cells were pruned, then 297 -> 295 when the WriteCleanFull and
SnpCleanInvalid/RetToSrc cells were waived -- and a stale constant here
silently rescales every percentage in the comparison.  Curves measured
against different totals are NOT comparable; this refuses to mix them.

usage:
  resample_convergence.py [--step N] LABEL=file.csv [LABEL=file.csv ...] > out.csv

e.g.
  resample_convergence.py --step 1000 \
      directed=convergence_directed_fine.csv \
      random_s1=convergence_random_seed1_fine.csv \
      random_s2=convergence_random_seed2_fine.csv \
      random_s3=convergence_random_seed3_fine.csv > convergence_comparison.csv
"""
import csv
import sys


def load(path):
    rows = [dict(r) for r in csv.DictReader(open(path))]
    if not rows:
        sys.exit(f"{path}: no data rows")
    totals = {int(r["func_bins_tot"]) for r in rows}
    if len(totals) != 1:
        sys.exit(f"{path}: mixed func_bins_tot {sorted(totals)} -- "
                 "the covergroup changed mid-run; re-measure")
    series = sorted(((int(r["events_exec"]), int(r["func_bins_cov"]),
                      float(r["func_pct"]), float(r["stmt_pct"]), int(r["sim_s"]))
                     for r in rows), key=lambda t: t[0])
    return series, totals.pop()


def step_at(series, e):
    """Last sample at or before e; None if the run had not started."""
    out = None
    for s in series:
        if s[0] <= e:
            out = s
        else:
            break
    return out


def main():
    args = sys.argv[1:]
    step = 1000
    if args and args[0] == "--step":
        step = int(args[1])
        args = args[2:]
    if not args:
        sys.exit(__doc__)

    curves = []
    totals = set()
    for a in args:
        if "=" not in a:
            sys.exit(f"expected LABEL=file.csv, got {a!r}")
        label, path = a.split("=", 1)
        series, tot = load(path)
        curves.append((label, series))
        totals.add(tot)

    if len(totals) != 1:
        sys.exit(f"curves scored against different bin totals {sorted(totals)} -- "
                 "not comparable; re-measure all against one covergroup")
    total = totals.pop()

    hdr = ["events"]
    for label, _ in curves:
        hdr += [f"{label}_bins", f"{label}_pct_of_total",
                f"{label}_func_pct", f"{label}_sim_s"]
    hdr.append("bins_total")

    w = csv.writer(sys.stdout)
    w.writerow(hdr)
    end = max(s[-1][0] for _, s in curves)
    e = 0
    while e <= end:
        row = [e]
        for _, series in curves:
            p = step_at(series, e)
            if p:
                row += [p[1], f"{100.0 * p[1] / total:.2f}", p[2], p[4]]
            else:
                row += ["", "", "", ""]
        row.append(total)
        w.writerow(row)
        e += step


if __name__ == "__main__":
    main()
