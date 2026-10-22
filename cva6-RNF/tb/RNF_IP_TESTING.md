# RN-F IP-level testing

CVA6-less harness that drives the L1.5 + rnf_link directly. The CPU
side is poked via the transducer interface; the CHI side is answered
by an abstract HN-F (`chi_hnf_responder.sv`). Stimulus is replayed
from Murphi-derived vectors in `testgen/vectors_rnf/`.

## Layout

- `rnf_ip_tb.sv` — DUT instantiation, CPU-port tasks (`do_load`,
  `do_store`, `do_amo`, `do_cbo_inval`), vector replay, smoke pre-roll.
- `chi_hnf_responder.sv` — programmable HN-F: TX/RX flit glue, RX
  credit tracking, response FSM, snoop injection API.
- `rnf_coverage/` — `rnf_phase_tracker` infers L1 state from CHI
  traffic; `rnf_coverage` defines six covergroups.
- `testgen/run_all_rnf.sh` — parallel vsim sweep; pre-vopts once with
  `+cover`, merges per-vector UCDBs.

## Running

```
QUESTA=/path/to/questa COVERAGE=1 make rnf-ip-compile
cd testgen && COVERAGE=1 ./run_all_rnf.sh            # full 12471-vector sweep
```

Smoke (no vector): `make rnf-ip-sim`. Add `+DBG_TRACE` for flit dump.

## Coverage status (single RN-F)

12471 / 12471 PASS.

| Coverpoint | Status |
|---|---|
| `cp_prev_state` | **100%** (I/SC/UC/SD/UD) |
| `cp_next_state` | **100%** |
| `cp_trigger`    | 66% — `SNP_respdata` bin not reached |
| `x_trans`       | ~19% |
| Code coverage   | ~48% (Statements 75%, FSM States 75%) |

The `SNP_respdata` gap is structural: the L1.5 snoop pipeline does not
emit `SnpRespData_*_PD` under any single-RN-F stimulus we've tried —
the RTL path exists ([response_encoder.sv:780](../cache/l15/rtl/response_encoder.sv#L780))
but its `tagcheck_state_m_s3` gate is never reached from this env.
Closing it needs a multi-RN-F harness.

## Notable env fixes

- DBIDResp opcode was `5'h03` (RetryAck); now `CHIE_DBIDRESP` (`5'h06`).
- `DBID` and `HOMENID` populated so WriteBack data and CompAck route.
- RX credit counters initialised to `XP_LCRD_NUM_PARAM` (15) per CHI
  link-layer convention; `RX*FLITV` is credit-gated.
- Snoop opcodes via `CHIE_SNP*` macros (the spec values used before
  were undefined in this codebase).
- `Env_CompData_{clean,dirty}` mapped opcode-aware: ReadClean→SC/SD_PD,
  ReadUnique→UC/UD_PD. Was always UC/UD_PD.
- `SW_enqueue_ReadUnique` dispatches via `do_store` so the L1.5 issues
  CHI ReadUnique (`07`) instead of always ReadClean (`02`).
- Vector replay appends a directed store+SnpClean exerciser and a
  `do_cbo_inval` drain so queued snoops retire before `$finish`.
