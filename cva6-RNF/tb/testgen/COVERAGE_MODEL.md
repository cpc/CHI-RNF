# Functional coverage model

Reference for `rnf_coverage.sv` and the numbers in `coverage_functional.csv`.
Every denominator below is derived from first principles and reconciles
against the Questa report.

Source of truth: `../rnf_coverage/rnf_coverage.sv` (bin declarations) and
`../rnf_coverage/rnf_phase_tracker.sv` (the signals sampled).

Numbers are from the 631-hub prefix-shared sweep, 2026-08-07.
Regenerate with `./gen_coverage_csv.sh`.

---

## 1. Alphabets

The coverage model is built from nine finite alphabets. Everything else is
a product of these.

```
  S = {I, SC, UC, SD, UD}                      L1 states               5
  G = {REQ_complete, SNP_resp, SNP_respdata}   transition triggers     3
  O = {SnpClean, SnpShared, SnpUnique,
       SnpCleanInvalid, SnpMakeInvalid}        snoop opcodes           5
  R = {SR_I, SR_SC, SR_I_D, SR_SC_D,
       SR_I_PD, SR_SC_PD}                      snoop responses         6
  P = {idle, rsp, dsend, comp, ack_cl, ack_dy} tx phases               6
  P+= P minus {idle}                                                   5
  T = {ReadClean, ReadUnique,
       WriteBackFull, AtomicLoad}              tx ops                  4
  E = {RD_CLEAN, RD_DIRTY, DATALESS,
       WR_SPLIT, WR_COMB}                      lifecycle shapes        5
  Q = legal REQ opcodes (20 minus 11 illegal)                         14
  B = {0, 1}                                   snoop-seen flag         2
```

Notes on two sizes that are not obvious:

- `R` encodes the CHI Resp field as `{PassDirty, final_state}`. Only the
  `I` and `SC` final states occur for these five snoop opcodes, giving
  `2 states x {none, D, PD} = 6`.
- `T` is 4, not 5. The coverpoint also declares `OtherCoh = default`, and
  per the SystemVerilog LRM a `default` bin is excluded from crosses and
  from the coverpoint's own bin count.

---

## 2. The two rules

```
  cross:       bins  = (D1 x D2 x ... x Dk)  MINUS  excluded
               total = product(|Di|) - |excluded|

  covergroup:  pct   = MEAN of member pcts        <-- not sum/sum
```

The covergroup rule matters. `cg_snoop_decisions` reads 90.88% while its
bins are only 102/152 = 67%, because four coverpoints at 100% are averaged
in alongside two crosses at 52% and 93%. All member weights are 1.

---

## 3. Derivations

### cg_l1_transitions
sampled when the inferred L1 state changes

```
   x_trans  =  S x S x G                     5 * 5 * 3   =  75
   minus  5 self-loops x 3 triggers                      -  15
   minus  snoop-on-I, illegal promotions (8 groups)      -  38
                                                   total =  22
   covered 19  ->  86.36%

   pct = (100 + 100 + 100 + 86.36) / 4               =  96.59
```

The 13 `ignore_bins` groups overlap (e.g. `snp_from_I` shares two cells
with `self_loop_I`), so they do not sum linearly to 53.

### cg_snoop_decisions
sampled when SnpResp or SnpRespData fires

```
   x_decision  =  O x S x R                  5 * 5 * 6   = 150
   minus  MakeInvalid never returns data   1 * 5 * 4     -  20
   minus  Clean/Shared never invalidate    2 * 5 * 3     -  30
                                                   total = 100
   covered 52  ->  52.00%

   x_phase     =  O x P                      5 * 6       =  30
   covered 28  ->  93.33%

   pct = (100 + 100 + 100 + 100 + 52.00 + 93.33) / 6 =  90.88
```

The two exclusion sets are disjoint (different opcodes), so |E| = 50 exactly.

### cg_tx_lifecycle
sampled when a transaction retires

```
   x_op_seq  =  T x E                        4 * 5       =  20
   no exclusions                                   total =  20
   covered 15  ->  75.00%

   cp_phase_seq  4/5 = 80.00%   (WR_COMB never seen)

   pct = (100 + 80.00 + 100 + 75.00) / 4             =  88.75
```

### cg_tx_transient
sampled every cycle a REQ is outstanding

```
   x_phase_op  =  P+ x T                     5 * 4       =  20
   minus  ack_dy x {WriteBackFull, AtomicLoad}          -   2
                                                   total =  18
   covered 17  ->  94.44%

   pct = (100 + 100 + 94.44) / 3                     =  98.14
```

### cg_race_intersections
sampled when a fresh snoop lands mid-transaction

```
   x_race  =  P+ x O x T                     5 * 5 * 4   = 100
   NO EXCLUSIONS AT ALL                            total = 100
   covered 57  ->  57.00%

   pct = (100 + 100 + 100 + 57.00) / 4               =  89.25
```

### cg_req_issuance
sampled when a REQ leaves the DUT

```
   x_state_op  =  S x Q                      5 * 14      =  70
   minus  WriteBackFull from non-UD        1 * 4         -   4
   minus  ReadClean/Unique from non-I      2 * 4         -   8
                                                   total =  58
   covered 49  ->  84.48%

   pct = (100 + 92.85 + 84.48) / 3                   =  92.44
```

`Q` is 14 because eleven REQ opcodes are `illegal_bins` (no RTL in this
design assigns them). Those propagate into the cross, which is why it is
5 x 14 and not 5 x 20.

---

## 4. Totals

```
  bins    35 + 152 + 31 + 27 + 114 + 77          = 436
  covered 32 + 102 + 25 + 26 +  71 + 67          = 323

  ALL_BINS         = 323/436                     =  74.08%
  ALL_COVERGROUPS  = (96.59 + 90.88 + 88.75
                    + 98.14 + 89.25 + 92.44)/6   =  92.67%
```

Both rows are emitted because they answer different questions.
`ALL_COVERGROUPS` is what `vcover` prints as `TOTAL COVERGROUP COVERAGE`
and what a sign-off goal is compared against. `ALL_BINS` weights the two
100-cell crosses at 23% of the score each. They differ by 18 points --
quoting one where the other is meant materially misreports the result.

---

## 5. Split by kind

```
                covered  missing  total
  coverpoints        86        2     88   97.7%
  crosses           237      111    348   68.1%
  ------------------------------------------------
  total             323      113    436   74.1%
```

Every individual protocol element -- each snoop opcode, cache state,
response variant and transaction phase -- is hit. 98% of the loss is in
*combinations*, not in features.

---

## 6. The 113 missing bins

Two coverpoint bins:

| bin | why |
|---|---|
| `cp_phase_seq / WR_COMB` | HN-F BFM only sends split `DBIDResp`+`Comp`, never combined `CompDBIDResp`. The RTL handles it (`rx_control.sv:1877`) -- BFM gap, not a design gap. |
| `cp_req_opcode / ReadNoSnp` | Assigned at `txreq_encoder.v:449` on the IFILL-non-cacheable arm. No instruction-fetch port exists in this L1.5-only DUT. |

111 cross cells:

| group | cells | nature |
|---|---:|---|
| `x_race` 43 + `x_phase` 2 | 45 | needs two overlapping transactions; the Murphi model has one MSHR |
| `x_decision` | 48 | SnpCleanInvalid 18, SnpUnique 16, SnpClean 6, SnpShared 6, SnpMakeInvalid 2 |
| `x_state_op` 9, `x_op_seq` 5, `x_trans` 3, `x_phase_op` 1 | 18 | 5 ReadNoSnp, 2 WriteNoSnpPtl-from-UC/UD, 2 atomic variants, 3 L1 transitions, rest structural |

---

## 7. Three caveats

**Questa truncates percentages, it does not round.** 13/14 = 92.857 is
printed as `92.85`, not 92.86. Likewise 98.148 -> `98.14` and the grand
total 92.679 -> `92.67`. Every value is floor-to-2-decimals, so each is up
to 0.01 low and the error compounds through the covergroup means. Worth a
footnote if these are quoted against a threshold.

**The `x_state_op` atomic cells are seed-dependent.** The sweep runs with
`-sv_seed random`, so which of the eight `AtomicLoad_*` variants get
exercised rotates between runs -- the missing cells were `EOR`/`CLR`/`SMIN`
on one sweep and `UMIN` on the next. They are genuinely reachable but not
guaranteed in any single sweep. Pin the seed before a final results run.

**`x_race` and `x_op_seq` under-enumerate their missing cells by name.**
Their `cp_tx_op*` operand carries a `default` bin, and Questa cannot name
cross cells involving it: the report lists 16 of 43 for `x_race` and 1 of 5
for `x_op_seq`. The summary counts are authoritative and are what
`gen_coverage_csv.sh` parses. The other five crosses reconcile
cell-for-cell.

---

## 8. Reading the model as a spec

`x_race` is the only cross with no exclusions -- all 100 cells assert that
a snoop of any kind may arrive against a transaction of any kind in any
phase. That is a deliberate claim about CHI, and it is why the cross scores
worst. Every other cross had protocol-impossible combinations pruned first.

Each `ignore_bins` / `illegal_bins` group is therefore a machine-checked
protocol assertion, not bookkeeping. `illegal_bins` fires an error if the
combination is ever observed; `ignore_bins` silently removes it. The
convention in `rnf_coverage.sv` is:

- `illegal_bins`  -- CHI forbids it, or no RTL implements the opcode
- `ignore_bins`   -- reachable in principle but out of this TB's scope

A cell must be confirmed UNCOVERED before it is pruned. Pruning a covered
cell silently deletes real coverage, and has happened twice in this
codebase's history.
