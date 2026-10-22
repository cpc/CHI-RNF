# Murphi model of the HN-F coherence FSM

`hnf_fsm.m` is a [Murphi](https://github.com/Smattr/rumur)
formal-verification model of the HN-F coherence protocol. It is the
**primary source of truth** for the FSM: drives test-vector generation
(`testgen/gen_from_murphi.py`) and is checked for safety invariants.

## Why Murphi

- **Symmetry reduction**: `ScalarSet(NUM_RNF)` quotients RN-F
  permutations automatically; rules authored once, state space halved
  (or `n!`× reduced for more RN-Fs).
- **Pending-REQ machinery**: `Array[RNFid] of OpType` instead of
  hand-expanded `__PEND_<peer>_<op>` state names.
- **Invariant checking**: catches model bugs the YAML flat graph hid
  (e.g. Evict-while-dirty, snoop-downgrade-leaves-dirty).

## Run the verifier

```bash
make testgen-murphi       # rumur compile + verify + reports
```

Override `RUMUR=/path/to/rumur` if not at the default
`/home/dmk/fedora/rumur/build/rumur/rumur`.

**Use [rumur](https://github.com/Smattr/rumur), not CMurphi 5.x.**
CMurphi's parser silently fails on UTF-8, backticks, function-call
chains; rumur gives proper diagnostics.

### Current result

```
State Space Explored: 172 states, 367 rules fired in 0s.
Status: No error found.
```

All five safety invariants hold:
`AtMostOneUnique`, `NoUniqueAndSharedSimultaneously`,
`DirtyOnlyWhenUnique`, `InflightConsistency`,
`StableHasNoInflightOp`.

## Address-space partition (2026-06-08)

The model covers only the **coherent address subspace** (10 ops:
ReadClean/Unique, MakeUnique, Clean*, Evict, WriteBack/CleanFull).
Non-coherent ops (`ReadNoSnp`, `WriteNoSnpFull`, ...) live in a
separate subspace at a distinct address and bypass the FSM entirely
(CHI E.b §2.4.2). Mixing the two on a single line is forbidden.

## State variables

| Variable | Type | Purpose |
|---|---|---|
| `rnf[r]` | `{RS_I, RS_S, RS_U}` | per-RN-F snoop-filter state |
| `dirty` | `Boolean` | UD-vs-UC distinction |
| `phase` | `{STABLE, T_FILL, T_SNP, T_ACK}` | MSHR transient phase |
| `requester` | `RNFid` | inflight REQ owner |
| `inflight_op` | `OpType` | inflight op |
| `pending[r]` | `OpType` | queued REQ per RN-F |

## Rules (5 families)

1. **Stable-line REQ** — issue from RN-F r.
2. **Internal store-hit** — UC → UD locally.
3. **CAM hazard queueing** — second REQ during a transient. Per-op
   preconditions ensure CHI E.b legality (e.g. WriteBackFull requires
   U+dirty). Snoopee can't queue during T_SNP (matches driver's eager-
   invalidate-on-snoop behavior).
4. **Transient resolution** — SNF_DATA, SNP_RESP, CompAck.
5. **Pending promotion** — re-fire queued REQ once stable.

## DOT visualization

```bash
make testgen-murphi-dot   # generates hnf_fsm_murphi.dot (+ raw variant) + PNG
```

`to_dot.py` patches `hnf_fsm.m` with `Put` state-dump instructions and
parses rumur stdout. Three gotchas it handles:

1. `rumur --threads 1` is **compile-time** (baked into generated C as
   `enum { THREADS = 1 }`). Without it 12 worker threads race on
   `putchar_unlocked` and shred output.
2. Capture stdout to a **file**, not a pipe — avoids buffer fragmentation.
3. One-liner `If ... End;` constructs need word-boundary depth counting,
   not whole-line matching.

Emits both `hnf_fsm_murphi.dot` (360 canonical states) and
`hnf_fsm_murphi_raw.dot` (708 states — un-symmetry-reduced).

## Known limitations / approximations

- **Pending-REQ promotion** clears the slot then expects the matching
  stable rule to fire. Not explicit dispatch.
- **Snoop-response variants** (SnpRespData, PassDirty, IsShared)
  collapsed into one transition. Driver mirrors this — both currently
  drop dirty data on SnpCleanInvalid to UD (CHI E.b non-conformance;
  documented in `project-chi-eb-conformance` memory).
- **DCT** not modelled.
- **Two RN-Fs**, **single address**. Multi-line / set-conflict cases
  need model extension.

## What Murphi can't do

- Doesn't prove the **RTL** matches the model — only that the model is
  internally consistent.
- Misses RTL timing races, MSHR-depth bugs, data corruption.
- Simulation (`testgen-run-*`) still mandatory for signoff.
