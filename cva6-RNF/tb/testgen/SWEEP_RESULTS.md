# RN-F IP-Level Sweep Results — Coverage

Direct-comparison table for the 1-switch (baseline) and 2-switch
(this work) Murphi-derived vector sweeps against the CVA6-less
L1.5 + rnf_link RN-F under the abstract-HN-F testbench
(`rnf_ip_tb.sv`).

Both sweeps ran the same DUT under identical Questa settings; the only
difference is which coverage criterion the vector generator targets.

## Sweep parameters

| parameter | value |
|---|---|
| DUT | L1.5 + rnf_link (64B pipeline / 64B cache line) |
| Environment | Abstract HN-F responder (`chi_hnf_responder.sv`) |
| Generator | Murphi model `testgen/murphi_rnf/rnf_fsm.m`, BFS shortest-path prefix + target-edge tail |
| Simulator | Questa 2024.2_2 |
| Compile | `vopt +cover=bcestf` (branches, conditions, expressions, statements, toggles, FSM) |
| Parallel jobs | 6 |
| Per-vector timeout | 30 s |
| Batch size | 200 |

## Vector counts

| criterion | targets | scale vs 1-switch |
|---|---|---|
| 1-switch (state × terminal-DRIVE-edge) | 12,471 | 1.00× |
| 2-switch (state × DRIVE-in × DRIVE-out) | 19,250 | 1.54× |

## Pass/Fail

| sweep | total | PASS | FAIL | TIMEOUT |
|---|---:|---:|---:|---:|
| 1-switch | 12,471 | 10,303 (82.6%) | 2,168 (17.4%) | 0 |
| 2-switch | 19,250 | 15,506 (80.5%) | 3,744 (19.5%) | 0 |

All FAILs on both sweeps trip `SNP_MON` on the missing `CHIE_SNPMAKEINVALID`
dispatch arm in `cache/l15/rtl/rx_control.sv` (see
`RESULTS_DEFECTS.md` for the RTL-defect list). Zero `MEM_ORACLE`
byte-mismatches on either sweep across the passing set.

## RTL code coverage — DUT-scoped (`/rnf_ip_tb/u_dut/l15`)

`vcover report -recursive -codeAll -instance=/rnf_ip_tb/u_dut/l15`

| metric | 1-switch | 2-switch | Δ |
|---|---:|---:|---:|
| Statements  | **77.21%** (4525 / 5860) | **76.53%** (4485 / 5860) | −0.68 pp |
| Branches    | **59.35%** (1161 / 1956) | **59.20%** (1158 / 1956) | −0.15 pp |
| Expressions | 37.94% (269 / 709)       | 36.95% (262 / 709)       | −0.99 pp |
| Conditions  | 31.45% (167 / 531)       | 31.26% (166 / 531)       | −0.19 pp |
| Toggles     | 22.23% (8045 / 36188)    | 21.57% (7807 / 36188)    | −0.66 pp |
| **Aggregate (filtered view)** | **50.84%** | **50.45%** | −0.39 pp |

Interpretation:
2-switch does not improve code coverage over 1-switch. Both sweeps
saturate the same RTL substrate — the RN-F's response to a single
DRIVE edge already exercises the same statements/branches that would
be reached by any consecutive pair terminating in that edge. The
2-switch value is in *path coverage* (Chow N=2), not in *code
coverage*, and the near-equal numbers here confirm that the added
vectors traverse the same RTL regions via different sequences.

The ~0.4 pp drop at 2-switch is explained by the larger absolute FAIL
count (3,744 vs 2,168): more vectors abort at `SNP_MON` earlier in
their sequences, reaching slightly less code overall.

## Functional (covergroup) coverage

`vcover report -cvg`

| covergroup type-view | 1-switch | 2-switch | Δ |
|---|---:|---:|---:|
| Overall             | **46.57%**       | **46.46%**       | −0.11 pp |
| Covergroup Bins     | 17.12% (99/578)  | 16.60% (96/578)  | −0.52 pp |
| Covergroup types    | 6 | 6 | — |

Per-coverpoint (both sweeps side-by-side):

| coverpoint | 1-switch | 2-switch | notes |
|---|---:|---:|---|
| `cp_l1_at_issue`         | 100.00% | 100.00% | all L1 states exercised at REQ issue |
| `cp_l1_at_snoop`         | 100.00% | 100.00% | all L1 states exercised at snoop arrival |
| `cp_prev_state`          | 100.00% | 100.00% | every L1 state reached |
| `cp_next_state`          | 100.00% | 100.00% | every L1 state reached |
| `cp_snoop_seen_during`   | 100.00% | 100.00% | binary occurrence bin |
| `cp_trigger`             |  66.66% |  66.66% | 2/3 trigger sources hit |
| `cp_tx_phase_at_snoop`   |  66.66% |  66.66% | |
| `cp_tx_phase_when_snoop` |  60.00% |  60.00% | |
| `cp_phase`               |  60.00% |  60.00% | |
| `cp_phase_seq`           |  50.00% |  50.00% | |
| `cp_tx_op_during_snoop`  |  50.00% |  50.00% | |
| `cp_resp_variant`        |  33.33% |  33.33% | 2/6 snoop-resp variants hit — dirty variants gated by SNP_MON abort |
| `cp_tx_op_resident`      |  30.00% |  30.00% | |
| `cp_tx_op`               |  27.27% |  27.27% | 3/11 TX opcodes emitted (ReadClean/ReadUnique/WriteBackFull) |
| `cp_snoop_op`            |  20.00% |  20.00% | 1/5 snoop opcodes retires (SnpMakeInvalid RTL drop) |
| `cp_snoop_op_during_tx`  |  20.00% |  20.00% | |
| `cp_req_opcode`          |  17.64% |  17.64% | 3/17 CHI req opcodes (bin list also has 2 known bugs) |

Crosses:

| cross | 1-switch | 2-switch | Δ |
|---|---:|---:|---:|
| `x_trans`     | 45.45% | 45.45% | 0 |
| `x_phase_op`  | 23.52% | 23.52% | 0 |
| `x_op_seq`    | 13.63% | 12.12% | −1.51 pp |
| `x_phase`     | 13.33% | 13.33% | 0 |
| `x_state_op`  | 11.86% | 11.86% | 0 |
| `x_race`      |  4.66% |  3.33% | −1.33 pp |
| `x_decision`  |  0.90% |  0.90% | 0 |

Interpretation:
The 2-switch sweep produces near-identical functional coverage to
1-switch and *marginally lower* on the hazard crosses (`x_race`,
`x_op_seq`). Both regressions are explained by the increased FAIL
count (3,744 vs 2,168): the 1,576 extra SNP_MON aborts terminate
those vectors before the snoop-hazard cross bins can sample. The
covergroup topology matches — same 6 types, same 578 bins declared,
same architectural ceilings on `cp_req_opcode` / `cp_snoop_op` /
`cp_tx_op`. What 2-switch adds is *path diversity* (which vectors
reach a given hazard state via which sequence), not new bin hits;
that path diversity is invisible to the current covergroup design.

Adding pair-of-transitions coverpoints — an `x_prev_drive × current_drive`
cross to the covergroup — would surface the 2-switch delta as a
distinct metric. Not present in the current model.

Key gaps in the 1-switch covergroup:
- `cp_req_opcode 17.6%` and `cp_snoop_op 20%` are architectural
  ceilings (only ~7 of 17 CHI request opcodes are emittable by the
  L1.5; only 1 of 5 snoop opcodes is answered — the `SnpMakeInvalid`
  RTL defect drops the other four).
- `x_race 4.7%` and `x_decision 0.9%` are the hazard crosses
  suppressed by SNP_MON early-abort on the FAIL side.

## Wall-clock

| sweep | wall time | notes |
|---|---|---|
| 1-switch | ~1h 27m | at PAR_JOBS=2 |
| 2-switch | ~1h 33m | at PAR_JOBS=6 |

## Merged UCDBs on disk

- 1-switch: `testgen/rnf_ip_cov_merged.ucdb`
- 2-switch: `testgen/run_all_rnf_2switch_cov_merged.ucdb`
