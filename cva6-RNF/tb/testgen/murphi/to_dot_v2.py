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
Generate a Graphviz DOT diagram of the HN-F coherence FSM by:

  1. Patching hnf_fsm.m to emit a one-line state summary before and
     after every rule firing (via Put statements).
  2. Compiling the patched model with rumur.
  3. Running the verifier and parsing the trace lines.
  4. Building a deduplicated (from_state, rule, to_state) edge set.
  5. Emitting hnf_fsm_murphi.dot.

The Murphi model is the source of truth — we don't duplicate any rule
logic in Python. State naming is canonical (after rumur's symmetry
reduction).

Usage:
  ./to_dot.py                       # → hnf_fsm_murphi.dot + .png
  ./to_dot.py --no-render           # DOT only

Requires rumur on $PATH (or override via RUMUR env var).
"""

import argparse
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
# v2: two-sided FSM (per-snoopee SnpResp* decisions, 5-state RN-F).
# Override with MURPHI_MODEL=hnf_fsm.m to fall back to the v1 single-
# sided model.
MODEL = os.environ.get("MURPHI_MODEL",
                       os.path.join(HERE, "hnf_fsm_v2.m"))
RUMUR = os.environ.get("RUMUR", "/home/dmk/fedora/rumur/build/rumur/rumur")


def emit_state_dump(label, indent="  "):
    """Murphi Put statements that emit a one-line state fingerprint.
    Format: "STATE:<label>:rnf[0]=<v>,rnf[1]=<v>,dirty=<v>,phase=<v>,..."
    """
    parts = [
        f'Put "STATE:{label}:rnf[0]=";  Put rnf[r1]; Put ",rnf[1]="; Put rnf[r2];',
        f'Put ",dirty="; Put dirty; Put ",phase="; Put phase;',
        f'Put ",inflight="; Put inflight_op;',
        f'Put ",req=";',
        f'If !IsUndefined(requester) Then Put requester; Else Put "U"; End;',
        f'Put ",pend[0]="; Put pending[r1]; Put ",pend[1]="; Put pending[r2];',
        f'Put "\\n";',
    ]
    return "\n".join(indent + p for p in parts)


def make_dump_block(label):
    """Murphi Put statements that emit a one-line state fingerprint
    with a label (BEFORE/AFTER) and the rule name.

    v2 model adds: snp_required[r], snp_resp[r], hnf_has_dirty.
    v1's `dirty` is removed (per-RN-F dirty is encoded in RnfLocal).
    """
    return f"""
    Put "STATE_{label}: ";
    For ri : RNFid Do Put "rnf["; Put ri; Put "]="; Put rnf[ri]; Put " "; End;
    Put "phase="; Put phase; Put " ";
    Put "inflight="; Put inflight_op; Put " ";
    If !IsUndefined(requester) Then
        Put "req="; Put requester; Put " ";
    End;
    For ri : RNFid Do Put "pend["; Put ri; Put "]="; Put pending[ri]; Put " "; End;
    For ri : RNFid Do Put "snpreq["; Put ri; Put "]="; Put snp_required[ri]; Put " "; End;
    For ri : RNFid Do Put "snpresp["; Put ri; Put "]="; Put snp_resp[ri]; Put " "; End;
    Put "hnfdirty="; Put hnf_has_dirty; Put " ";
    Put "STATE_END\\n";
    """


RULE_DECL_RE = re.compile(r'^\s*Rule\s+"([^"]+)"')


def patch_model(src_path, dst_path):
    """Insert state-dump Put statements at the START and END of each
    rule body, plus a `RULE: <name>` line so each edge can be labeled.
    The BEFORE/AFTER pair lets us reconstruct edges:
      RULE: <name>
      STATE_BEFORE ... STATE_END
      STATE_AFTER  ... STATE_END
    Each adjacent (BEFORE, AFTER) pair = one edge in the state graph."""
    with open(src_path) as f:
        src = f.read()

    before_block = make_dump_block("BEFORE")
    after_block  = make_dump_block("AFTER")

    out = []
    lines = src.splitlines(keepends=True)
    i = 0
    current_rule = "unknown"
    while i < len(lines):
        line = lines[i]
        stripped = line.strip()
        m = RULE_DECL_RE.match(line)
        if m:
            current_rule = m.group(1)
        # When we see "==>" alone, the next "Begin" starts a rule body.
        if stripped == "==>":
            out.append(line)
            i += 1
            while i < len(lines) and lines[i].strip() != "Begin":
                out.append(lines[i]); i += 1
            if i >= len(lines):
                break
            out.append(lines[i])  # Begin
            out.append("    -- AUTO state dump (before mutations)\n")
            out.append(f'    Put "RULE: {current_rule}\\n";\n')
            out.append("    " + before_block + "\n")
            i += 1
            # Skip body until we find the matching End; that closes
            # the rule body. Count openers/closers per line (since
            # one-liner If/End; constructs are common). Use word-
            # boundary regex to avoid matching inside identifiers.
            opener_re = re.compile(r"\b(?:For|If|Switch|Begin)\b")
            closer_re = re.compile(r"\b(?:End|Endif|Endswitch|EndSwitch)\b\s*;?")
            depth = 1
            body = []
            while i < len(lines) and depth > 0:
                line2 = lines[i]
                # Strip Murphi comments so they don't confuse the count.
                no_comment = re.sub(r"--.*$", "", line2)
                openers = len(opener_re.findall(no_comment))
                closers = len(closer_re.findall(no_comment))
                new_depth = depth + openers - closers
                if new_depth <= 0:
                    # This line contains the rule's closing End; — inject
                    # AFTER block just before it.
                    body.append("    -- AUTO state dump (after mutations)\n")
                    body.append("    " + after_block + "\n")
                body.append(line2)
                depth = new_depth
                i += 1
            out.extend(body)
        else:
            out.append(line); i += 1

    with open(dst_path, "w") as f:
        f.write("".join(out))


def run_rumur(model_path, c_path):
    print(f"[to_dot] rumur compile: {model_path}")
    # --threads 1 is COMPILE-TIME for rumur: the generated C has
    # `enum { THREADS = 1 }` so the verifier doesn't spawn worker
    # threads. Without this, 12 threads race on putchar_unlocked() and
    # the Put output gets character-level interleaved.
    r = subprocess.run(
        [RUMUR, "--threads", "1",
         "--scalarset-schedules", "off",
         "--output", c_path, model_path],
        capture_output=True, text=True
    )
    if r.returncode != 0:
        sys.exit(f"rumur failed:\n{r.stderr}")
    return r.stderr


def run_cc(c_path, bin_path):
    print(f"[to_dot] cc compile:    {c_path}")
    r = subprocess.run(
        ["cc", "-std=c11", "-march=native", "-mcx16", "-O3",
         "-o", bin_path, c_path, "-lpthread"],
        capture_output=True, text=True
    )
    if r.returncode != 0:
        sys.exit(f"cc failed:\n{r.stderr}")


def run_verifier(bin_path):
    print(f"[to_dot] verifier run:  {bin_path}")
    # Capture to a temp file (shell-style redirect) rather than a pipe.
    # Single-threaded verifier (compile-time THREADS=1) plus regular
    # file output gives clean, race-free Put output.
    out_path = bin_path + ".out"
    with open(out_path, "w") as f:
        subprocess.run([bin_path], stdout=f, stderr=subprocess.STDOUT)
    with open(out_path) as f:
        return f.read()


DUMP_RE = re.compile(
    r"STATE_(BEFORE|AFTER):(.*?)STATE_END",
    re.DOTALL
)
RULE_LINE_RE = re.compile(r"^RULE:\s*(.+?)\s*$", re.M)


NUM_RNF = 2   # must match the Murphi model's Const NUM_RNF

# Whether normalize_state_body() applies the RN-F-swap symmetry
# quotient. Toggled by --no-symmetry on the CLI.
SYMMETRY_QUOTIENT = True


def normalize_state_body(body):
    """rumur's `Put expression` emits `name:value\\n` for variable
    references. Extract semantic values; return None if the parse looks
    corrupted (rumur's stdio buffering occasionally fragments output
    across rule firings).

    v2 model: RnfLocal expands to {RS_I, RS_SC, RS_UC, RS_SD, RS_UD}.
    Adds snp_required[ri], snp_resp[ri], hnf_has_dirty.  Removes
    global `dirty` (encoded in RS_UD / RS_SD).
    """
    rnf      = re.findall(r"rnf\[ri\]\s*:\s*(RS_(?:I|SC|UC|SD|UD))\b", body)
    pend     = re.findall(r"pending\[ri\]\s*:\s*(op_\w+?)(?=\s|$)", body)
    snp_req  = re.findall(r"snp_required\[ri\]\s*:\s*(true|false)\b", body)
    snp_resp = re.findall(r"snp_resp\[ri\]\s*:\s*(SR_\w+?)(?=\s|$)", body)
    if len(rnf)      != NUM_RNF:  return None
    if len(pend)     != NUM_RNF:  return None
    if len(snp_req)  != NUM_RNF:  return None
    if len(snp_resp) != NUM_RNF:  return None

    pm = re.search(r"phase\s*:\s*(STABLE|T_FILL|T_SNP|T_ACK)\b", body)
    im = re.search(r"inflight_op\s*:\s*(op_\w+?)(?=\s|$)", body)
    hm = re.search(r"hnf_has_dirty\s*:\s*(true|false)\b", body)
    rm = re.search(r"requester\s*:\s*(?:RNFid_)?(\d+)\b", body)
    if not (pm and im and hm):
        return None

    if SYMMETRY_QUOTIENT:
        # Symmetry quotient: rumur reduces canonically internally but
        # emits raw scalarset-indexed values through Put. Restore the
        # canonical form by sorting the per-RN-F tuples — but keep the
        # requester's slot first so inflight semantics are preserved.
        req_idx = int(rm.group(1)) if rm else None
        paired = list(zip(rnf, pend, snp_req, snp_resp))
        if req_idx is not None and 0 <= req_idx < len(paired):
            head = [paired[req_idx]]
            rest = sorted(p for i, p in enumerate(paired) if i != req_idx)
            paired = head + rest
            req_tag = "R"
        else:
            paired = sorted(paired)
            req_tag = "U"
        rnf      = [p[0] for p in paired]
        pend     = [p[1] for p in paired]
        snp_req  = [p[2] for p in paired]
        snp_resp = [p[3] for p in paired]
    else:
        req_tag = f"RNFid_{rm.group(1)}" if rm else "U"

    return (
        f"rnf=[{','.join(rnf)}] phase={pm.group(1)} "
        f"inflight={im.group(1)} req={req_tag} "
        f"pend=[{','.join(pend)}] "
        f"snpreq=[{','.join(snp_req)}] snpresp=[{','.join(snp_resp)}] "
        f"hnfdirty={hm.group(1)}"
    )


def parse_transitions(stdout):
    """Walk through the verifier's stdout. Each rule firing emits:
      RULE: <name>
      STATE_BEFORE ... STATE_END
      STATE_AFTER  ... STATE_END
    Pair each adjacent (BEFORE, AFTER) into one edge labeled by the
    most recent RULE: line preceding the BEFORE. Returns
    (states, edges) where edges is a set of (from, to, rule) triples."""
    states = set()
    edges = set()
    pending_before = None
    pending_rule   = "?"
    dropped = 0

    # Build a position-ordered stream of (kind, payload) events.
    events = []
    for m in RULE_LINE_RE.finditer(stdout):
        events.append((m.start(), "RULE", m.group(1)))
    for m in DUMP_RE.finditer(stdout):
        events.append((m.start(), m.group(1), m.group(2)))
    events.sort()

    for _, kind, payload in events:
        if kind == "RULE":
            pending_rule = payload
            continue
        body = normalize_state_body(payload)
        if body is None:
            dropped += 1
            pending_before = None
            continue
        states.add(body)
        if kind == "BEFORE":
            pending_before = body
        else:   # AFTER
            if pending_before is not None and pending_before != body:
                edges.add((pending_before, body, pending_rule))
            pending_before = None
    if dropped:
        print(f"[to_dot] dropped {dropped} corrupted state dumps (stdio buffering)")
    return states, edges


def state_short(s):
    """Compact label for a normalized state fingerprint.
    Input form: "rnf=[RS_X,RS_Y] dirty=true phase=STABLE inflight=op_None req=U pend=[op_None,op_X]"
    """
    parts = []
    # RNF states
    m = re.search(r"rnf=\[([^\]]*)\]", s)
    if m:
        for v in m.group(1).split(","):
            parts.append(v.replace("RS_", "") if v else "?")
    # Phase
    m = re.search(r"phase=(\w+)", s)
    if m and m.group(1) != "STABLE":
        parts.append(m.group(1))
    # HN-F holds dirty (v2)
    if "hnfdirty=true" in s:
        parts.append("Hd")
    # Inflight
    m = re.search(r"inflight=op_(\w+)", s)
    if m and m.group(1) != "None":
        parts.append(m.group(1))
    # Pending
    m = re.search(r"pend=\[([^\]]*)\]", s)
    if m:
        for v in m.group(1).split(","):
            if v and v != "op_None":
                parts.append("Q:" + v.replace("op_", ""))
    return "|".join(parts) or "init"


def classify(state_str):
    """Classify a normalized state fingerprint into the same 5 visual
    tiers used by the YAML hnf_fsm.dot."""
    is_stable = "phase=STABLE" in state_str
    # Pending: any element of pend=[...] != op_None
    pend_match = re.search(r"pend=\[([^\]]*)\]", state_str)
    has_pending = False
    if pend_match:
        has_pending = any(v and v != "op_None"
                          for v in pend_match.group(1).split(","))
    # All RNFs invalid?
    rnf_match = re.search(r"rnf=\[([^\]]*)\]", state_str)
    all_invalid = False
    if rnf_match:
        all_invalid = all(v == "RS_I" for v in rnf_match.group(1).split(",") if v)
    # v2: no global dirty bit; "clean" means HN-F not holding dirty.
    is_clean = "hnfdirty=false" in state_str
    no_inflight = "inflight=op_None" in state_str

    if is_stable and all_invalid and is_clean and not has_pending and no_inflight:
        return "INITIAL"
    if is_stable and not has_pending:
        return "STABLE_CORE"
    if is_stable and has_pending:
        return "STABLE_PEND"
    if not is_stable and not has_pending:
        return "TRANSIENT_CORE"
    return "TRANSIENT_PEND"


def state_style(tier):
    """Mirror YAML to_dot.py's tier styling for visual consistency."""
    if tier == "INITIAL":
        return ('shape=doublecircle, style="bold,filled", '
                'fillcolor="#ffd700", color="#000000", penwidth=3, '
                'fontsize=14, fontcolor="black"')
    if tier == "STABLE_CORE":
        return ('shape=ellipse, style="filled", fillcolor="#1f4e79", '
                'color="#0b2540", penwidth=3, fontsize=12, '
                'fontcolor="white"')
    if tier == "STABLE_PEND":
        return ('shape=ellipse, style="filled", fillcolor="#b3d4f5", '
                'color="#1f4e79", penwidth=1, fontsize=8')
    if tier == "TRANSIENT_CORE":
        return ('shape=octagon, style="dashed,filled", fillcolor="#fff3d6", '
                'color="#7a5a00", penwidth=2, fontsize=11')
    # TRANSIENT_PEND
    return ('shape=octagon, style="dotted,filled", fillcolor="#f5f5f5", '
            'color="#bbbbbb", fontcolor="#666666", fontsize=8')


def emit_dot(states, edges, out_path):
    lines = [
        "digraph hnf_fsm_murphi {",
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
        tier = classify(s)
        style = state_style(tier)
        label = state_short(s)
        lines.append(f'  {nid} [label="{label}", {style}, tooltip="{s}"];')
    lines.append("")
    # Collapse parallel edges (same src,dst with different rule names)
    # into one edge with a multi-line label.
    from collections import defaultdict
    by_pair = defaultdict(list)
    for item in edges:
        if len(item) == 3:
            src, dst, rule = item
        else:
            src, dst = item; rule = ""
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
    lines.append("")
    # Legend cluster (same 5-tier scheme as YAML DOT)
    lines += [
        "  subgraph cluster_legend {",
        '    label="Legend"; style="dashed"; fontsize=10;',
        '    L_init [label="initial", shape=doublecircle, style="bold,filled", '
        'fillcolor="#ffd700", penwidth=3];',
        '    L_stable [label="stable", shape=ellipse, style="filled", '
        'fillcolor="#1f4e79", fontcolor="white", penwidth=3];',
        '    L_transient [label="transient", shape=octagon, style="dashed,filled", '
        'fillcolor="#fff3d6", penwidth=2];',
        '    L_spend [label="stable+pending", shape=ellipse, style="filled", '
        'fillcolor="#b3d4f5", fontsize=8];',
        '    L_tpend [label="transient+pending", shape=octagon, style="dotted,filled", '
        'fillcolor="#f5f5f5", fontcolor="#666666", fontsize=8];',
        "  }",
        "}",
    ]
    with open(out_path, "w") as f:
        f.write("\n".join(lines))


def main():
    global SYMMETRY_QUOTIENT
    ap = argparse.ArgumentParser()
    ap.add_argument("--no-render", action="store_true",
                    help="don't run `dot` to produce PNG")
    ap.add_argument("--variant", choices=["both", "reduced", "raw"],
                    default="both",
                    help="which graph(s) to emit (default: both)")
    args = ap.parse_args()

    with tempfile.TemporaryDirectory() as td:
        patched_m = os.path.join(td, "patched.m")
        c_path    = os.path.join(td, "patched.c")
        bin_path  = os.path.join(td, "patched")

        patch_model(MODEL, patched_m)
        run_rumur(patched_m, c_path)
        run_cc(c_path, bin_path)
        stdout = run_verifier(bin_path)

        variants = []
        if args.variant in ("both", "reduced"):
            variants.append((True,  "hnf_fsm_murphi.dot",
                             "symmetry-reduced"))
        if args.variant in ("both", "raw"):
            variants.append((False, "hnf_fsm_murphi_raw.dot",
                             "raw (no symmetry quotient)"))

        for quotient, name, desc in variants:
            SYMMETRY_QUOTIENT = quotient
            states, edges = parse_transitions(stdout)
            print(f"[to_dot] {desc}: {len(states)} states, "
                  f"{len(edges)} edges")
            dot_path = os.path.join(HERE, name)
            emit_dot(states, edges, dot_path)
            print(f"[to_dot] wrote {dot_path}")
            if not args.no_render:
                png_path = dot_path + ".png"
                r = subprocess.run(
                    ["dot", "-Tpng", "-o", png_path, dot_path],
                    capture_output=True, text=True)
                if r.returncode == 0:
                    print(f"[to_dot] wrote {png_path}")
                else:
                    print(f"[to_dot] dot failed: {r.stderr}",
                          file=sys.stderr)


if __name__ == "__main__":
    main()
