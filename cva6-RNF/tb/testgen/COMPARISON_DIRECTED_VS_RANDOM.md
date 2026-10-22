# Model-based directed vs constrained-random generation

Measured 2026-08-08 on the RN-F IP-level testbench. Both vector sets run
through the identical harness (`run_convergence.sh`), the identical TB
path (`replay_vector`), and an **alphabet-matched** event set, at
`PAR_JOBS=12` on the same machine with nothing else running.

Reproduce:

    ./gen_random_vectors.py --count 2000 --steps 65 --seed 1
    VEC_DIR=vectors_rnf_random BATCH=100 MAX=2000 \
        OUT=convergence_random.csv ./run_convergence.sh
    VEC_DIR=vectors_rnf_prefix_shared BATCH=60 \
        OUT=convergence_directed.csv ./run_convergence.sh

---

## 1. Making the baseline fair

**Constrained, not uniform.** A uniform draw over the event alphabet
spends most steps replying to transactions that were never issued, which
the L1.5 discards. `gen_random_vectors.py` enforces the well-formedness a
hand-written constrained-random environment would have: a memory op is
followed by a response drawn from the shapes legal for its class, only
when a request is outstanding; snoops are injected independently at a
tunable rate.

What it lacks -- the point of the comparison -- is a model of the protocol
state space. It cannot aim at a transition it has not yet taken.

**Alphabet-matched, by default.** The TB can dispatch five events the
Murphi model no longer emits (`Evict`, `CleanUnique`, `WriteBackFull`,
`WriteCleanFull`, `Env_Comp_for_Evict`). Leaving them in the random
alphabet is not a comparison of generation *strategy* -- it is a
comparison of alphabets, and it credits random with cells the directed
set was structurally unable to reach. `gen_random_vectors.py` drops them
unless `--full-alphabet` is passed. Both sets emit exactly 25 event
types, verified by diffing the vectors themselves.

**Length-matched.** 65 DRIVE steps per vector, close to the directed
set's 55511/832 = 67 average, so per-vector simulation cost is
comparable.

---

## 2. Headline

```
                        DIRECTED            RANDOM
  vectors                    832              2000
  simulation time           217 s             559 s
  generation cost            55 s              <1 s
  TOTAL                     272 s             560 s     2.1x
  ------------------------------------------------------------
  functional (type)       93.79%            91.96%
  functional bins        343/436           329/436
  statements              88.04%            88.19%
  ------------------------------------------------------------
  pass                       630              1705
  fail                       202               295
  failure rate             24.3%             14.8%
```

Directed numbers include both model fixes of section 6 -- the `l1 != L1_I`
snoop guard removal (b) and the RetToSrc coordinate (c).  Progression:

```
                         func     bins   sim
  as first measured     92.72%  323/436  187 s
  + guard fix (6b)      93.11%  333/436  222 s
  + RetToSrc (6c)       93.79%  343/436  217 s
```

Directed generation cost: rumur codegen 0.1 s + `cc -O3` 10.8 s + model
check 0.1 s + BFS vector generation 22.8 s. One-time, amortised across
every subsequent regression run.

**Random plateaus 1.83 points below directed and does not close the gap.**
It is flat at 91.96% from vector 1800 to 2000; directed passes that mark
at vector 480 / 125 s -- 4.0x sooner -- and goes on to 93.79%.  Directed
leads on both functional measures, type and raw bins.

The failure rate fell from 39.3% to 24.3% with the RetToSrc fix.  That is
not fewer bugs -- absolute failures are 202 against 327 -- it is that the
RetToSrc tails are long and mostly complete, so the denominator grew
faster than the numerator.

---

## 3. Time to reach a coverage level

```
  target   directed              random                 speedup
  88%       240 vec /   62s       300 vec /   82s        1.3x
  90%       420 vec /  109s       500 vec /  139s        1.3x
  91%       420 vec /  109s       900 vec /  251s        2.3x
  91.96%    480 vec /  125s      1800 vec /  503s        4.0x
  93%       720 vec /  188s          -- never reached --
```

Random keeps pace to about 90% -- the easy states need no guidance, and
random pays no generation cost. The advantage then grows monotonically
with the target: **2.3x at 91%, 4.0x at 91.96%, and unbounded above it**
where random stops improving altogether. Directed reaches 93% at vector
720; random never does.

That monotonic shape is the honest result. An earlier unmatched run
showed a non-monotonic 5.1x peak at 90% falling to 2.8x; that artefact
came from the alphabet mismatch, not from the generation strategy.

---

## 4. Failure density

Directed vectors expose a failure **1.6x more often per vector**: 24.3%
vs 14.8%. Per unit of simulation time the gap is wider -- 202 failures in
217 s against 295 in 559 s, i.e. **0.93 failures/s vs 0.53**.

Random stimulus is easier on the DUT: it drives the L1.5 into the wedge
states less often, because reaching them needs a specific sequence random
rarely assembles.

---

## 5. What each finds that the other does not

**Directed only -- 19 cells, including two whole coverpoint bins:**

```
  cp_tx_phase_at_snoop   await_comp        <-- coverpoint bin, never hit
  cp_tx_phase_when_snoop await_comp        <-- coverpoint bin, never hit
  x_phase     {SnpClean, SnpShared, SnpUnique,
               SnpCleanInvalid, SnpMakeInvalid} x await_comp
  x_race      await_comp x {SnpClean, SnpShared, SnpUnique} x ReadClean
  x_decision  SnpCleanInvalid x {I,SD}   -> SR_SC
              SnpMakeInvalid  x {I,SC,SD} -> SR_SC
              SnpUnique       x {I,SC,SD} -> SR_SC
  x_state_op  SD x AtomicLoad_SMIN
```

Two results here, both significant.

**Random never lands a snoop in the AWAIT_COMP window at all.** This is
not a missing cross cell -- it is a missing *coverpoint* bin, on two
different coverpoints. AWAIT_COMP is the narrow interval between the
data-send and the Comp response; a snoop must arrive inside a few-cycle
window to be observed there. Random injects snoops uniformly in time and
essentially never hits it. Eight further cross cells fall out of this one
gap. No amount of additional random vectors fixes it -- the probability
per vector is not small, it is effectively zero.

**Directed uniquely reaches the `SR_SC`-to-invalidating-snoop cells.**
SnpCleanInvalid, SnpMakeInvalid and SnpUnique leaving the line Shared
instead of Invalid: the conformance violations this testbench exists to
find. Reaching them requires the line in a specific state when a specific
snoop lands, which is what a reachability model can aim at.

**Random only -- 15 cells** (was 21 before the guard fix of section 6(b)):

```
  x_decision  SnpShared x SC -> SR_SC_PD
              SnpCleanInvalid x {SC,SD} -> SR_I_PD
              SnpUnique x SC -> SR_I_PD
  x_race      {await_rsp, await_ack_dy} x snoop x {AtomicLoad, ReadClean}
  x_op_seq    AtomicLoad x WRITE_SPLIT
  x_state_op  {UC,UD} x WriteNoSnpPtl,  UD x AtomicSwap
  x_trans     SD -> I via SNP_respdata
```

None of them currently exposes a protocol violation. They have three
distinct causes -- see section 6.

---

## 6. Why directed misses what it misses

Three separate causes, measured rather than assumed. Only the third is a
limitation of model-based generation as such.

### (a) The model targets the cell; the simulation never arrives -- ~9 cells

Counting snoop injections in the directed vectors by the transaction
phase they land in:

```
  AWAIT_RSP            5333        <-- incl. 766 with AtomicLoad outstanding
  AWAIT_DATA_SEND      2725
  AWAIT_COMP           2574
  AWAIT_COMPACK_CLEAN  1850
  AWAIT_COMPACK_DIRTY   370
  no outstanding tx    1000
```

The model aims at `await_rsp x snoop x AtomicLoad` 766 times. Those are
exactly the cells random reached and directed did not. It is not a
modelling gap.

```
  directed DRIVE steps planned : 41273
                      executed : 20705  = 50.2%
  runs aborted outright        :   115 / 630
```

**Half of every directed vector never runs.** The snoop-during-transaction
steps sit deep in mega-vector tails, so when the DUT wedges early the
entire downstream chain is discarded. This is the hidden cost of the
prefix-sharing optimisation: it amortises the walk to a hub, but one
wedge then destroys every target hanging off that hub. Random's short
independent vectors do not share the failure mode -- one wedge costs one
vector, not a chain of 24.

Fixing this is fixing the DUT wedge, not the generator.

### (b) A guard the model did not need to have -- 2 cells  [FIXED]

```
Rule "Env_Snp_SnpClean"
  rx_snp = rx_None & l1 != L1_I
```

L1 state at snoop injection across the whole directed set:

```
  SC 3930    UD 3381    UC 3306    SD 3235    I  0
```

The model never snoops an Invalid line, so `SnpClean x I` and
`SnpShared x I` were never attempted at all. A snoop to an invalid line
looks uninteresting from the model's side -- the RN-F just answers
SnpResp_I -- but the DUT's behaviour there is evidently not trivial,
since random found two cells in it.

**Fixed.** The `& l1 != L1_I` conjunct is removed from all five
`Env_Snp_*` injection rules. `Snp_any_from_I` already supplied the
response, so no new rules were needed. Model checks clean at 14196
states (from 11271); hubs 630 -> 832, planned DRIVE steps 41273 ->
55511; snoop injections on I go from 0 to 5190.

It recovered more than the two cells it was aimed at -- nine in total:

```
  x_decision  SnpClean x {I,SC} -> SR_SC_PD      <-- targeted
              SnpShared x I     -> SR_SC_PD      <-- targeted
              SnpUnique x I     -> SR_SC
  x_race      await_ack_dy x SnpClean  x AtomicLoad
              await_rsp    x SnpShared x AtomicLoad
              await_rsp    x SnpUnique x AtomicLoad
  x_op_seq    WriteBackFull x DATALESS
  x_state_op  I x AtomicLoad_UMAX
```

The six beyond the two targeted are a volume effect: the larger vector
set re-rolls `-sv_seed random` more often and executes more steps
overall. Functional coverage went 92.72% -> 93.11%, bins 323 -> 333, and
the failure rate rose 30.8% -> 39.3% for 35 s more simulation.

### (c) The genuine abstraction gap -- 24 cells  [FIXED]

A snoop rule in `rnf_fsm.m`:

```
Rule "Snp_SnpClean_from_UD"
  rx_snp = rx_SnpClean & rx_resp_owed & l1 = L1_UD
==>  l1 := L1_SC; rx_snp := rx_None; rx_resp_owed := false;
```

It assigns the post-snoop L1 state and nothing else. The model's state
space is `(snoop_op x L1_state) -> next_state`, but `x_decision` measures
`(snoop_op x L1_state x response_variant)`. The model *does* snoop SC and
SD lines thousands of times; it simply **has no coordinate for the
response variant**, so BFS cannot aim at SR_I versus SR_I_PD. Those cells
are hit incidentally, as a function of whatever dirtiness the DUT
happened to carry, and random's larger sample wins them by volume.

This is the real lesson, and it does cut against the directed flow:
*model-based generation is only as complete as its abstraction.* 2-switch
completeness in the model does not imply cell completeness in the
covergroup, because the projection from RTL behaviour to model state is
lossy.

**Fixed.** Classifying the 48 x_decision cells that were still uncovered
showed the shape of the gap precisely:

```
  clean data -- needs RetToSrc     24    <-- no coordinate in the model
  dataless                          8
  PassDirty from a dirty line       8
  PassDirty from a CLEAN line       8    <-- protocol-anomalous, a bug
                                            signature; must NOT be targeted
```

Half the gap was one missing coordinate. A snoopee returns data on a
clean line only when the snoop carries RetToSrc, so `rx_rettosrc` was
added to the model state, set by four new `Env_Snp_*_RTS` injection rules
(SnpMakeInvalid has no RTS form -- it never returns data), and cleared by
all fourteen response rules. The TB dispatches the new events through the
`rettosrc` argument already present on the injectors.

```
  states           14196 -> 23660   (no error found)
  hub tails        26094 -> 41094
  RTS snoop steps      0 -> 15113
  x_decision       51/100 -> 65/100
  x_decision gaps      48 -> 35   (RetToSrc class 24 -> 10)
  cg_snoop_decisions 91.83% -> 94.16%
```

Note what was deliberately *not* targeted: the eight PassDirty-from-clean
cells. Those are protocol-anomalous -- a snoopee cannot pass dirty data
from a clean line -- so they are a bug signature, not a coverage goal.
Extending the model to reach them would be teaching it to reproduce a
defect.

### Summary

```
  cause                                  status
  (a) vectors abort before target        open -- DUT wedge bug
  (b) l1 != L1_I snoop guard             FIXED -- 92.72% -> 93.11%
  (c) no RetToSrc coordinate             FIXED -- 93.11% -> 93.79%
```

Both modelling causes are now closed. (b) and (c) together moved directed
functional coverage 92.72% -> 93.79% and raw bins 323 -> 343, for 30 s
more simulation. What remains is (a): half of every directed vector still
never executes because the DUT wedges, and prefix sharing amplifies each
wedge into a lost tail chain. That is a DUT bug, not a generator
limitation, and it is now the only thing standing between this flow and
the residual cells random still reaches.

---

## 7. Caveats

**Neither set is proven saturated.** Random is flat over its last three
batches (1800-2000), which is a plateau rather than a proven fixpoint.
Directed was still climbing at 630.

**Structural numbers here are pre-exclusion.** This harness reports raw
statement coverage without applying `coverage_exclude.do`, so the 88.19%
column is not comparable to the 91.82% in
`coverage_structural_blocks.csv`. The two columns are comparable to each
other, which is what the experiment needs. Note both approaches land on
exactly the same statement coverage.

**`-sv_seed random` gives the longer run extra variant rotation.** 2000
vectors sample the eight-way `AtomicLoad_*` rotation about 3x more often
than 630 do, which accounts for `I x AtomicLoad_UMAX` on the random side.

**Correction to an earlier figure.** A note in this repo, repeated in the
commit message on `6e9dc66`, put the directed sweep at 13 s. That was
`vcover`'s merge elapsed time misread out of the sweep log. The directed
sweep is 174-187 s.
