# The DUT wedge -- what is established, and what is not

Status 2026-08-09: **NOT FIXED.** This is the largest single lever left on
the IP-level flow, and it is open.

## Scale

```
  planned DRIVE steps in the 832-vector set : 81431
  actually executed                         : 35901 = 44.1%
  runs that never reach "done:"             :   155 / 832
```

56% of the model's targeting is aimed at cells the simulation never
reaches. No amount of covergroup or model work recovers that; every
other open item is smaller.

## Established by measurement

**Not opcode-specific.** Unanswered snoops spread across all five
opcodes (txnid 1..5 = Clean/Unique/MakeInvalid/CleanInvalid/Shared),
roughly 30/17/10/22/14. So it is not a missing per-opcode handler.

**Snoops are locked out of the pipeline whenever `fetch_state_s1 !=
NORMAL`.** `l15_pipeline.tmp.v:364-387`:

```
  case (fetch_state_s1)
    L15_FETCH_STATE_NORMAL:      source = noc2 ? NOC2 : pcx ? PCX : INVALID
    L15_FETCH_STATE_PCX_INVAL_2/3/4,
    L15_FETCH_STATE_PCX_WRITEBACK_DONE: source = PCX     <-- NOC2 locked out
    L15_FETCH_STATE_CPX_INVAL_*, EVICT_*, ICACHE_INVAL_2: source = NOC2
```

NC load, NC store and atomics all drive `NORMAL -> PCX_INVAL_2`, so every
one of them closes the snoop channel for the duration of its sub-block
walk.

**But that lockout alone cannot explain it.** The walk advances on
`!stall_s1` and is 3-4 cycles. The SNP_MON timeout is 500 cycles. So the
wedge requires S1 to *stall*, not merely to be busy.

```
  stall_s1 = val_s1 && (stall_tag_match_stall_s1
                     || stall_index_conflict_stall_s1
                     || stall_s2
                     || stall_mshr_allocation_busy_s1
                     || stall_pcx_noc1_buffer_s1)
```

**The L1.5 refuses CPU requests for 1000+ cycles.** `hdrack=0` appears in
511 of 833 runs. A representative failing trace:

```
  [2021500] do_amo(...)   hdrack=1
  [3029500] do_store(...) hdrack=0        <-- refused for ~1000 cycles
  [3544500] [SNP_MON] FATAL: snoop txnid=4 unanswered for 500 cycles
```

and another, where the accepted request is itself the trigger:

```
  [15249500] do_store_nc(...) hdrack=1    <-- drives PCX_INVAL_2
  [15743500] [SNP_MON] FATAL: snoop txnid=2 unanswered for 500 cycles
```

## Hypothesis -- NOT confirmed

Circular dependency:

    PCX sub-block walk needs an MSHR
      -> all MSHRs busy awaiting CHI completions
        -> HN-F is waiting for a SnpResp before completing them
          -> SnpResp cannot be emitted, NOC2 locked out by the walk

This predicts `stall_mshr_allocation_busy_s1` (i.e.
`decoder_no_free_mshr_s1`) high, with `fetch_state_s1` parked in a
`PCX_*` state. **It has not been checked.** Do not repeat the reasoning
as though it were a finding.

## What was tried and did not work

Batch probing via `vsim -c -do "run 157400ns; ..."` -- simulating to the
hang (157 us) exceeds 10 minutes per iteration, which is too slow to
iterate on. This needs a waveform, not log greps.

## Next concrete step

Run one wedging vector (`vectors_rnf_prefix_shared/hub_I.txt`, fails at
~157.4 us) to just before the timeout and capture:

```
  fetch_state_s1
  stall_s1  stall_s2
  stall_mshr_allocation_busy_s1   decoder_no_free_mshr_s1
  stall_pcx_noc1_buffer_s1
  mshr_val_array
  noc2decoder_l15_val   pcxdecoder_l15_val
```

Cheapest route is `make rnf-ip-wave` with a `-do` that breaks at
157300ns, rather than a full `log -r /*` from time zero.

If the hypothesis holds, the fix is not the arbitration table -- it is
breaking the cycle, e.g. reserving an MSHR for snoop responses, or
letting a pending snoop preempt a stalled PCX walk. Both are changes to
third-party OpenPiton-derived pipeline RTL and want care.

## Why this matters beyond the wedge

The directed flow is currently aiming at cells it cannot reach. Against
the constrained-random baseline it leads on bins (356 vs 345-352) and on
time (249 s vs ~525 s) but trails on the mean-of-means type metric.
`cg_race_intersections` sits at 81/114 -- and those 33 cells are
precisely the ones lost when a vector wedges before its tail executes.
Fixing the wedge is worth more to the comparison than any further
covergroup work.
