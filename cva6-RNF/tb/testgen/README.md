# HN-F test-case generator

FSM-driven test vector generator + replay driver + oracle + coverage
for the HN-F coherence engine. Two generator flows:

| Flow | Source of truth | Primary use |
|---|---|---|
| **Murphi** (recommended) | [`murphi/hnf_fsm.m`](murphi/) | Symmetry-reduced, formally verified |
| **YAML** (legacy) | `hnf_fsm.yaml` | Older flat-graph model |

The Murphi flow drives [`gen_from_murphi.py`](gen_from_murphi.py) and
verifies a 172-state coherent FSM. See [`murphi/README.md`](murphi/README.md)
for the model itself.

## Address-space partition

Coherent ops (`ReadClean/Unique`, `MakeUnique`, `Clean*`, `Evict`,
`WriteBack/CleanFull`) target `ADDR_COHERENT = 0x80000200`.
Non-coherent ops (`ReadNoSnp`, `WriteNoSnpFull`, `WriteNoSnpPtl`,
`ReadOnce`) belong in a separate subspace at `ADDR_NONCOHERENT =
0xC0000200`. Mixing on a single line is forbidden by CHI E.b §2.4.2.

## Make targets (run from `cva6-RNF/tb/`)

```
make testgen-murphi              # verify Murphi model (invariants)
make testgen-murphi-dot          # render FSM as Graphviz PNG
make testgen-vectors             # YAML-based BFS vectors (legacy)
make testgen-summary             # FSM reachability stats
make testgen-replay VECTOR=...txt SIMLOG=...log     # build + sim + oracle
make testgen-oracle  VECTOR=...txt SIMLOG=...log    # score an existing log
```

For the Murphi flow specifically:

```bash
python3 testgen/gen_from_murphi.py --vectors      # → vectors_murphi/
QUESTA=... ./testgen/run_murphi.sh                # batch-run all vectors
vcover merge -64 testgen/murphi_merged.ucdb \
    testgen/run_all_logs/murphi/*.ucdb            # merge coverage
vcover report testgen/murphi_merged.ucdb          # text summary
```

## Build flags

| Flag | Effect |
|---|---|
| `REPLAY=1`     | Adds `-DRNF_REPLAY_DEMO` so RNFs run vectors instead of IL1..IL19 |
| `MSHR_OBS=1`   | Includes `mshr_observer.sv` (oracle needs `[MSHR_OBS]` lines) |
| `COVERAGE=1`   | Adds `+cover=bcsf` to vlog + Tier-1 observers (`mshr_coverage.sv`, `coherence_coverage.sv`) |
| `HNF_ASSERT=1` | Protocol-checker `$fatal`s in HNF |

Typical exhaustive build:
```bash
make QUESTA=$QUESTA clean
make QUESTA=$QUESTA all REPLAY=1 MSHR_OBS=1 COVERAGE=1 HNF_ASSERT=1
```

## File layout

```
gen_from_murphi.py        Murphi-driven vector generator (recommended)
gen_sequences.py          YAML-driven generator (legacy)
gen_burst.py              Back-to-back same-op stress (single RN-F)
gen_cross.py              Cross-RN-F concurrent burst
fuzz_sequences.py         Randomized FSM walks
oracle.py                 Diff expected vector vs MSHR trace
extract_rtl.py            Cross-check FSM against chie_defines.v
replay_vector.{h,cpp}     SC runner — parses vector, dispatches do_* on RNFs
run_murphi.sh             Batch-run Murphi vectors with coverage
run_all.sh                Batch-run YAML vectors (bfs/burst/cross/fuzz)
murphi/                   Murphi model, verifier, DOT generator
mshr_observer.sv          MSHR trace observer (bound to hnf_mshr_ctl)
mshr_coverage.sv          Tier-1 MSHR functional coverage
coherence_coverage.sv     Tier-1 coherence-state coverage
vectors_murphi/           Murphi-generated vectors
vectors/                  YAML-generated vectors (bfs/, burst/, cross/, fuzz/)
```

## Data integrity check

The replay orchestrator tracks expected-vs-observed line data per
address. Writes update a process-global shadow keyed by `(line_addr,
seq)`. Reads `memcmp` against the shadow if the line was previously
written. Mismatches print:

```
[REPLAY] DATA_MISMATCH addr=0x... op=ReadClean byte[i] got=X exp=Y
[REPLAY] DATA_CHECK_RESULT: PASS|FAIL (N checks)
```

Catches data-path bugs (SNF beat-drop, tb_snf back-to-back corruption,
PassDirty races) that neither MSHR nor coherence coverage would notice.

## Functional coverage (Tier 1)

Two bind-attached observers (no edits to monitor/ICN/HNF RTL):

| File | Bound to | Covers |
|---|---|---|
| `mshr_coverage.sv` | `hnf_mshr_ctl` | slot × op × src × compack × transient phase |
| `coherence_coverage.sv` | `hnf_cache_pipeline` | abstract state × op × initiator × L3 hit |

The Murphi-driven sweep (`./run_murphi.sh`) achieves:
- coherence: **95%+** (FSM-driven coverage is highly effective here)
- MSHR: lower — single-slot, single-vector cold start. Combine with
  `testgen-run-burst` / `testgen-run-cross` / `testgen-run-sweep`
  (YAML-based flows) for multi-slot / multi-address coverage.

## Excluded ops

Listed in `VECTOR_TARGET_DENYLIST` (per-generator). For the Murphi
flow:

```
Evict  (clean evict; bypass path, no MSHR ALLOC)
```

Non-coherent ops (`ReadNoSnp`, `WriteNoSnp*`, `ReadOnce`) are not in
the Murphi model at all — they belong in the non-coherent subspace.

## Known limitations

1. **FSM vs driver granularity** — vector edges are flit-level
   (REQ/COMPACK/SNP_RESP/SNF_DATA); `do_*` helpers are transaction-
   level. The runner dispatches one `do_*` per `REQ_*` and treats
   downstream flits as implicit.
2. **Single line per vector** — multi-line scenarios need model
   extension.
3. **Bracket-free filenames** — vsim's `-do` Tcl interprets `[...]`;
   `gen_from_murphi.py` sanitizes basenames to avoid silently dropped
   UCDBs.
4. **Driver loses dirty data on `SnpCleanInvalid` to UD** — CHI E.b
   non-conformance, currently mirrored by the Murphi `SNP_RESP` rule.
   Documented in the `project-chi-eb-conformance` memory; SnpRespData
   forwarding is a deferred fix.
