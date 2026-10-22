# Full-system Murphi model: N detailed RN-Fs + one simplified HN-F

`sys_fsm.m` is a [rumur](https://github.com/Smattr/rumur) Murphi model
of the whole coherent subsystem on one cache line: `NUM_RNF` RN-Fs
modelled at the full detail of `../murphi_rnf/rnf_fsm.m`, a **stateless**
HN-F, and one abstract external requester.

It is not a third independent model — it is the composition of the two
existing ones, with each contributing the side it describes well:

| | `murphi_rnf/rnf_fsm.m` | `murphi/hnf_fsm_v2.m` | **`murphi_sys/sys_fsm.m`** |
|---|---|---|---|
| RN-F detail | full (1 agent) | cache state only | **full (N agents)** |
| HN-F detail | free environment | full lifecycle | **directory + lock, no phase** |
| `Env_*` events | unconstrained | not modelled | **derived from directory state** |
| per-agent `tx_phase` | yes | **no** | yes |
| snoop opcodes reachable | all 5 (injected freely) | derived | **all 5 (derived)** |

## The HN-F has no transient phase

`hnf_fsm_v2.m` spends its state vector on `T_FILL / T_SNP / T_ACK /
T_WB_DBIDRESP / T_WB_DATA`.  None of that is stored here, because the
requester's own `tx_phase` already encodes it:

| `hnf_fsm_v2` phase | derived here as |
|---|---|
| `T_FILL` / `T_SNP` | `h_busy & tx_phase[h_req] = TX_AWAIT_RSP` |
| `T_ACK` | `h_busy & tx_phase[h_req] = TX_AWAIT_COMPACK_*` |
| `T_WB_DATA` | `h_busy & tx_phase[h_req] = TX_AWAIT_COMP` |

What is left is a directory and a serialiser:

```
h_busy / h_req   single-line transaction lock (the CAM serialiser)
h_op / h_ext_op  opcode being served -> derives snoop opcode + response shape
h_snp_owed[]     which snoopees still owe a SnpResp
h_dirty          HN-F holds dirty data passed up by a snoopee
h_wait[]         REQ accepted at the HN-F, stalled behind the lock
```

Removing the duplicate encoding is not just economy.  Two independent
encodings of one phase is precisely where a model and the DUT are free
to drift apart without anything detecting it.

The invariant `SnoopOwedOnlyWhileBusy` is the guard on this design
claim: if it ever fires, the HN-F has grown a transient the lock is not
tracking.

## The point: `Env_*` events are consequences, not choices

In `rnf_fsm.m` every `Env_*` rule is an adversary — its guard names only
`tx_phase` and `tx_op`, so the environment picks freely.  Here each
guard also carries the HN-F's preconditions:

```murphi
Rule "Env_CompData_dirty"
  h_busy & !h_ext & h_req = r & NumSnoopOwed() = 0 &
  tx_phase[r] = TX_AWAIT_RSP &
  (tx_op[r] = tx_ReadClean | tx_op[r] = tx_ReadUnique) &
  h_dirty                      -- <- set only by a snoopee that passed dirty
```

so clean-vs-dirty is caused rather than chosen, and no response flit can
precede the snoop responses that justify it
(`NoResponseBeforeSnoopsResolved`).

This removes stimulus, which is the main practical payoff.  Measured
against `rnf_fsm.m` by asserting unreachability and checking whether the
assertion fails:

| condition | `rnf_fsm.m` | `sys_fsm.m` |
|---|---|---|
| snoop lands while the DUT awaits its own REQ response | reachable | reachable |
| `SnpUnique` hits the DUT mid-`ReadUnique` | reachable | reachable |
| snoop lands in the DUT's CompAck window | **reachable** | **impossible** |
| snoop lands during the DUT's *coherent* writeback data phase | **reachable** | **impossible** |
| snoop lands during the DUT's *NC-store* data phase | reachable | reachable |

The two "impossible" rows are vectors the free environment generates
today that a same-line-blocking HN-F would never produce.  The last row
is the interesting counterpart: the NC path bypasses the MSHR
(`hnf_mshr_bypass`), so it takes no lock, and a coherent snoop *can*
land mid-NC-write — a race the single-agent model could not tell apart
from the coherent-writeback one.

Both impossibility results have one cause: those phases are exactly the
windows in which the DUT *holds the lock*, and the lock holder is never
snooped — §4.11.2: "once a completion is sent for a transaction, the
HN-F must not send a Snoop request to the same cache line until it
receives a CompAck ... / a WriteData response for CopyBack and Atomic
requests".  `TX_AWAIT_COMPACK_*` is only enterable via
`Env_CompData_*` (`h_busy & !h_ext & h_req = r`) and only leavable via
`Send_CompAck_*`, which releases the lock; the coherent writeback data
phase is bracketed the same way by `Env_DBIDResp_for_Write` and
`Env_Comp_for_WriteBack`.  Nothing leaks in from an earlier transaction
either, because every lock-release path passes a `NumSnoopOwed() = 0`
gate.  Two derived properties, both verified to hold over the whole
reachable set:

```
ForAll r : RNFid Do rx_resp_owed[r] -> h_snp_owed[r] End
(h_busy & !h_ext) -> !rx_resp_owed[h_req]
```

**The CopyBack-Snoop hazard (§4.11.1, worked in §5.6.1) is still covered** — read the table
row precisely.  A snoop *does* land on the DUT while a `WriteBackFull`
is outstanding; it lands in `TX_AWAIT_RSP`, the window between the WB
REQ leaving and `DBIDResp` returning, which is where the crossing
physically occurs.  Once the HN-F has accepted the WB it owns that
line's transaction and will not snoop the writer for it.
(`hnf_fsm_v2.m` cannot deliver a snoop in `T_WB_*` either: its `Snp_*`
rules all require `phase = T_SNP`, and nothing sets `snp_required`
during writeback.)

**What this genuinely cannot reach** is a snoop for a *different* line
landing in the DUT's CompAck window or writeback data phase.  That is
legal, real, and a plausible home for L1.5 MSHR-vs-snoop interlock bugs.
It is out of reach for any single-line model, this one included — see
the fidelity gaps below.

## Cross-line activity

CHI E.b 4.11.1 — *"An RN-F node must respond to received Snoop requests
... without creating any Protocol layer dependency on completion of
outstanding requests"* — is a **cross-line** property: the snoop being
answered is for a different line than the request that is outstanding.
A single-line model cannot state it.

A second fully-modelled line is not the way to get it. The HN-F
serialises *per line*, so two lines never contend there; everything
cross-line is RN-F-side. A second line would multiply the cache states,
the tx tag, the sw tag and the HN-F lock — order 1e9 states, dead on
arrival. Instead `bg_snp` carries a snoop for *some other* line pending
at the DUT, and that other line's coherence state is never modelled
because it cannot affect this line's invariants.

Five arrival rules (`Env_Snp_ALT_*`), one per snoop opcode, all reaching
the same successor: the opcode is not stored, since nothing reads it,
but naming it gives five aim points at zero state cost. The response
rule `Snp_ALT_resp` is guarded on `bg_snp` alone — no `tx_phase` term.
That absence *is* the 4.11.1 property.

**This adds reachable interleavings, not a new checkable property**, and
the measurement says so exactly: the section multiplies the reachable
set by precisely 2 (1,240,228 -> 2,480,456), which means the coordinate
is fully independent of this line's state. Claiming the model now
*verifies* a cross-line property would be wrong.

Unlike every other `Env_*` rule here, the arrival is free
non-determinism. That is deliberate and is not a relapse into
`rnf_fsm.m`'s adversarial environment: the transaction causing a foreign
snoop lives on a line this model does not track, so an arbitrary foreign
snoop is legal-but-uncaused rather than illegal. Freedom on *this* line
would produce traces no real HN-F could emit; freedom on an unmodelled
line does not.

One knob is left deliberately unwired: if the L1.5 serialises snoop
handling against an outstanding fill, adding `& !bg_snp` to the
`Issue_*` guards would encode that and shrink the product below 2x.
Whether it does is an unconfirmed RTL fact — do not guess it. If it is
ever added, it must not be added to `Snp_ALT_resp`.

## The external requester

No CVA6 RN-F can emit `MakeUnique`, `CleanUnique`, `CleanShared` or
`CleanInvalid` — `txreq_encoder.v` never assigns them.  So in a model
where the only requesters are CVA6 RN-Fs, `SnpMakeInvalid`,
`SnpCleanInvalid` and `SnpShared` have **no producer at all**, and the
RTL handlers for them go unstimulated.  (The 2026-07-25 sweep pinned
2127 failures on a missing `SnpMakeInvalid` handler — exactly this path.)

`Ext_REQ_begin` / `Ext_REQ_complete` model an agentless requester at the
HN-F that drives the wider opcode set.  It costs no extra agent state
and reuses the same lock; all five snoop opcodes are confirmed reachable
at the DUT.

## CHI E.b hazard audit

Checked against `IHI0050E.b` §4.11 *Hazard conditions* and §5.6 *Hazard
handling examples* — the two places the spec actually enumerates them.

### §4.11.1 At the RN-F node

| clause | status |
|---|---|
| Respond to snoops without creating a Protocol-layer dependency on outstanding requests | **modelled** — the `Snp_*` rules carry no `tx_phase` guard |
| Pending request with **no** Data response yet → process the snoop normally | **modelled**, reachable |
| Pending request with **≥1** Data packet → wait for all Data packets before responding | **not modelled** — no multi-beat data (see gaps) |
| CopyBack: WriteData state = state **after** the snoop, not at REQ time | **modelled** — split five ways per Table 4-39, all five reachable |
| CopyBack: may send no valid data when post-snoop state is I or SC | **partly** — the `CBWrData_I`/`_SC` edges exist; "byte enables deasserted, data zero" is unmodelled (no data values) |
| Only response permitted for a CopyBack while a SnpResp is pending is RetryAck | **modelled** — CopyBack's `DBIDResp` requires `NumSnoopOwed() = 0` |
| Snoop hazarding an outstanding Evict must be answered SnpResp_I | **n/a** — the RTL emits no Evict; `TxOp` has none |

### §4.11.2 At the ICN(HN-F) node

| clause | status |
|---|---|
| While a Snoop response is pending, only RetryAck / **DBIDResp for WriteUnique and Atomics** / ReadReceipt / RetryAck are permitted to the same address | **modelled — was previously too strict.** Every response waited on `NumSnoopOwed() = 0`, including atomics. `Env_DBIDResp_for_Atomic` now implements the documented exception; the requester can ship atomic write data while a peer's SnpResp is outstanding (reachable). |
| Once a completion is sent, no Snoop to the same line until CompAck (Read/Dataless) or WriteData (CopyBack/Atomic) | **modelled** — this is the clause behind both "impossible" rows above. Lock release points match it exactly: Read at `Send_CompAck_*`, CopyBack/Atomic after `Send_*WrData_*`. |

### §5.6 worked examples

| example | status |
|---|---|
| 5.6.1 CopyBack-Snoop hazard at RN-F | **modelled**, reachable — incl. the `UD → SnpShared → SC → CopyBackWrData_SC` case |
| 5.6.2 Request hazard at HN-F (Read-Read) | **modelled** — lock + `h_wait[]` |
| 5.6.3 Read-CopyBack / Dataless-CopyBack hazard at HN-F | **modelled** — same mechanism |
| 5.6.4 Request-CompAck to HN-F race hazard | **modelled** — `HNF_accept_REQ` needs `!h_busy`, and the lock is held until CompAck |

### Table 4-39 (§4.7.3) — CopyBack WriteData responses

The spec's concrete form of the §4.11.1 requirement. `WriteBackFull`
initial state **UD or SD**, final state always I:

| before WriteData | response | reachable |
|---|---|---|
| UD | `CBWrData_UD_PD` | yes |
| SD | `CBWrData_SD_PD` | yes |
| UC | `CBWrData_UC` | yes |
| SC | `CBWrData_SC` | yes |
| I | `CBWrData_I` | yes |

One rule per row, so the generator can aim at each `CBWrData_*` opcode
individually.

### Two inherited citations that are wrong

Both models cite an E.b §4.7 that does not say what they claim. In E.b,
**§4.7 is "Cache state transitions at a Requester"**: §4.7.3 = Write
requests, §4.7.4 = **Atomic** transactions, §4.7.5 = Other requests.

- `hnf_fsm_v2.m` cites "§4.7.4 Snoop response handling" and "§4.7.5
  Snoop-vs-Writeback race". The real hazard text is **§4.11**.
- `rnf_fsm.m` claims "SD is not a legal WriteBackFull source per CHI E.b
  §4.2.2". §4.2.2 is *Dataless transactions*, and Table 4-39 lists
  WriteBackFull's initial state as **"UD, SD"** — SD **is** legal. The
  silent-drop behaviour is an RTL fact, not a spec one.

Neither file was edited here; `sys_fsm.m`'s own copies are corrected in
place with notes.

## Alphabet gates

Three independent switches.  Conflating them costs coverage:

| gate | governs | default |
|---|---|---|
| `SwOpEnabled` | what the DUT's own RTL can emit | `rnf_fsm.m`'s set verbatim |
| `PeerSwEnabled` | what a *peer* RN-F runs | narrow: ReadClean / ReadUnique / SetConflict |
| `ExtOpEnabled` | the external requester | widest — the snoop-opcode source |

Peers exist to create coherence traffic against the DUT, not to
exercise their own NC/LR/atomic paths: every op enabled there multiplies
the peer's share of the state space while adding nothing the DUT can
observe beyond the snoop it already causes.

## Measured configurations

`NUM_RNF=2`, RetToSrc off, narrow peers is the default.  All verify
clean (no invariant violation, no deadlock).

| configuration | states | time |
|---|---|---|
| **baseline** (single line + cross-line snoop) | **2,480,456** | 9s |
| RetToSrc enabled | 2,480,456 | 9s |
| external requester disabled | 86,812 | <1s |
| peers get the full DUT alphabet | 9,629,906 | ~40s |
| `NUM_RNF = 3` | 68,371,424 | ~7min |

RetToSrc is free: `rx_rettosrc` is a *coverage coordinate* that no rule
reads (same as in `rnf_fsm.m` — the decision rules all clear it without
branching on it).  It exists so the generator can aim at the
`SnpRespData_*` clean-data-return cells by rule name at the delivery
edge, not to drive the state machine.

The external requester is ~90% of the baseline state space and buys
three of the five snoop opcodes — the best trade in the model.

## Can it reproduce the existing vector set?

Checked against `vectors_rnf_prefix_shared/` (427 hub targets generated
from `rnf_fsm.m`) by extracting every reachable agent-0 projection
`(l1, tx_phase, tx_op, sw_queue, rx_snp)` from this model — 3,256 of
them, over 7,272 `(projection, DRIVE event)` pairs.

**All 21 DRIVE event tokens** the existing vectors use are in this
model's 25. The four extra are `Env_DBIDResp_for_Atomic` (new, from the
§4.11.2 fix) and the three `Env_*_for_NC_*` responses, which
`gen_from_rnf.py` classifies as OBSRV rather than DRIVE.

**411 of 427 hub targets are reachable.** The 16 that are not split into
two groups, and the distinction matters:

- **15 are `l1 = I` with a snoop pending** while the agent has its own
  CopyBack/atomic outstanding. Here a snoop is delivered only to an
  agent the directory lists as a holder, so an I-line agent is snooped
  only via the silent-evict race — which needs `TX_IDLE` and so cannot
  co-occur with the agent's own outstanding transaction. `rnf_fsm.m`
  injects snoops regardless of `l1` (its `l1 != L1_I` guard was dropped
  deliberately). **This is a genuine gap, not cleanliness**: real snoop
  filters are imprecise and do snoop lines an RN silently dropped.
  Closing it means modelling the filter as state separate from the
  caches, rather than reading `l1` directly. Worth doing; not a hack.

- **1 is `<SD, AWAIT_COMPACK_DIRTY, ReadUnique>`** — correctly excluded.
  Reaching it needs the HN-F to hand dirty data to a requester that is
  already the dirty owner, which `AtMostOneDirtyOwner` (a verified
  invariant here) forbids. `rnf_fsm.m`'s free environment produces it
  because it has no notion of who owns dirty.

That 411/427 was 371/427 before the §4.11.2 retire fix — the existing
vector set is what exposed that over-constraint.

## Vector generation

Not yet wired up.  `sys_fsm.m` is designed so that
`../gen_from_rnf.py` ports across with two changes:

1. **Agent attribution.** Rules live inside `Ruleset r : RNFid`, and
   `parse_transitions` does not carry the ruleset argument.  Classify by
   diffing the state fingerprint instead: an event belongs to the DUT
   iff agent 0's fields changed.  Vectors carry DUT-targeted events
   only — peers are virtual and never instantiated in `rnf_ip_tb`.
2. **Internal edges.** `HNF_accept_REQ`, `Ext_REQ_*` and every
   peer-side rule have no TB-visible event.  They must stay in the BFS
   path but be dropped from the emitted vector.  This needs no TB
   change: `rnf_ip_tb.sv:2073` already skips any line without `DRIVE`.

`RNFid` is a plain subrange, **not** a ScalarSet, so the DUT stays
distinguishable and `gen_from_murphi.py`'s σ-permutation tracking is not
needed.  At `NUM_RNF=2` symmetry reduction would have bought 2×.

The `@trig` / `@assert` contract is unchanged — `tx_phase`, `tx_op`,
`rx_snp`, `sw_q` all exist per agent, which is the whole reason the
composition was needed rather than a projection of `hnf_fsm_v2` traces.

Expect target counts to scale with the state space, so dedupe coverage
targets by `(l1[0], tx_phase[0], rx_snp[0], event)` equivalence class
rather than by raw state fingerprint.

## Known fidelity gaps

- **No multi-beat data.** `CompData` and `WriteData` are single
  transitions, so §4.11.1's "wait to receive all Data response packets
  before responding to the Snoop request" and "must not respond to a
  Snoop request before receiving all data packets" are neither modelled
  nor testable from these vectors.
- **No RetryAck / retry path.** Every "RetryAck is permitted" clause in
  §4.11 is out of scope. Consistent with the coverage model, which
  excludes the CHI retry path (`e7868f0`).
- **CopyBack completion shape.** Table 4-39 gives `CompDBIDResp`
  (combined) as *the* Comp response for CopyBack, but the model —
  following `rnf_fsm.m` — also allows a separate `DBIDResp` → data →
  `Comp`. Left alone deliberately: changing it reshapes the TX lifecycle
  shared with `rnf_fsm.m` and the TB's `Env_*` tokens. Worth resolving
  against the RTL before either model is trusted on this point.
- **No RespSepData / DataSepResp flows.** The separate-response
  ordering rules are not represented.
- **Atomics do not self-invalidate.** `Issue_AtomicLoad` fires from any
  L1 state and the requester keeps its copy, so a local line can survive
  an atomic that mutates memory. Inherited from `rnf_fsm.m` and left
  deliberately: this model carries no data values so nothing detects it,
  and changing it would be inventing DUT behaviour. If the RTL does
  self-invalidate, confirm that first and fix both models together.
- **Single cache line.** Set-conflict eviction is modelled as an atomic
  displacement (`sw_SetConflict`), not as real multi-line pressure.
- **Peers share the DUT's RTL semantics.** A peer is another CVA6 RN-F,
  not a generic CHI agent; generic-agent behaviour is what the external
  requester covers.

## Run

```sh
rumur --output sys_fsm.c sys_fsm.m
cc -std=c11 -march=native -mcx16 -O3 -o sys_fsm sys_fsm.c -lpthread
./sys_fsm
```
