# chi-rnf project context

## Overview

CVA6 RISC-V core fitted with a CHI-E RN-F cache (L1.5), connected to the
OpenNOC behavioral HN-F and SN-F over a CHI-E interconnect.  Three testbench
configurations exist:

| TB | Description |
|----|-------------|
| `riscv_rnf_hnf_tb.sv` | RTL CVA6 RN-F + behavioral HNF + behavioral SNF |
| `riscv_rnf_gem5_tb.sv` | RTL CVA6 RN-F + gem5 CHI Ruby HNF (IPC bridge) |
| `tlm_rnf_hnf_tb.sv` | 2× SystemC TLM RN-Fs + RTL HNF + behavioral SNF (no CVA6) |

---

## Repository layout

```
chi-rnf/
  cva6-RNF/
    opennoc/          ← HNF + SNF RTL (submodule)
      rtl/
        include/      ← hnf_param.v, hnf_defines.v, snf_defines.v, chie_defines.v ...
        src/hnf/      ← hnf.v, hnf_mshr_ctl.v, hnf_cache_pipeline.v ...
        src/snf/      ← snf.v ...
        misc/         ← hnf_biq.v, assert_checker.sv, sync_fifo.v ...
    src/              ← local overrides: hnf_defines.v, hnf_mshr_ctl.v,
    |                   hnf_cache_pipeline.v, hnf_mshr_bypass.v,
    |                   hnf_link_rxreq_parse.v, tb_snf.v, tb_snf_sram.v
    cache/include/    ← hnf_param.v, chie_defines.v, rnf_defines.v ...
    tb/               ← testbenches, chi_monitor.sv, chi_icn_beh.sv,
    |                   chi_tlm_rnf.{h,cpp}, questa_sc_main.cpp
    |                   Makefile, chi_tlm_flist, chi_flist
    common_cells/     ← submodule
    openpiton/        ← submodule (CVA6 RN-F source)
```

### Source file precedence for hnf_defines.v

`chi_tlm_flist` lists `+incdir` in this order:
1. `cva6-RNF/src/`          ← **wins** (local override)
2. `cva6-RNF/cache/include/`
3. `cva6-RNF/opennoc/rtl/include/`

`tb_snf.v` and `tb_snf_sram.v` are sourced from `cva6-RNF/src/` (not opennoc).

All four HNF RTL overrides (`hnf_cache_pipeline.v`, `hnf_mshr_ctl.v`,
`hnf_mshr_bypass.v`, `hnf_link_rxreq_parse.v`) now point to
`opennoc/rtl/src/hnf/`.

---

## CHI-E parameters (fixed across all TBs)

| Parameter | Value |
|-----------|-------|
| NID_W | 7 |
| TXNID_W | 12 |
| ADDR_W | 44 |
| SNP_ADDR_W | 41 |
| DATA_W | 256 (2 DAT beats per cache line) |
| BE_W | 32 |
| DATACHECK | 0 |
| POISON | 0 |

### Flit widths

| Channel | Width |
|---------|-------|
| REQ | 131 b |
| RSP | 65 b |
| DAT | 370 b |
| SNP | 99 b |

### Node IDs (tlm_rnf_hnf_tb)

| Node | NID |
|------|-----|
| RNF0 | 0 |
| RNF1 | 1 |
| HNF  | 2 |
| SNF  | 32 |

---

## HNF supported transactions

Derived from the `display_fatal` assertion in `hnf_link_rxreq_parse.v`.
Sending any opcode not in this list causes an immediate fatal assertion.

### REQ channel (RN → HN)

| Opcode | Name |
|--------|------|
| 0x02 | ReadClean |
| 0x03 | ReadOnce |
| 0x04 | ReadNoSnp |
| 0x06 | ReadNotSharedDirty |
| 0x07 | ReadUnique |
| 0x08 | CleanInvalid |
| 0x0b | CleanUnique |
| 0x0c | MakeUnique |
| 0x17 | CleanShared |
| 0x19 | WriteUniqueFull |
| 0x1a | WriteUniquePtl |
| 0x1b | WriteBackFull |
| 0x1c | WriteNoSnpPtl |
| 0x1d | WriteNoSnpFull |
| 0x2c | WriteCleanFull / Evict |
| 0x2d | WriteEvictFull |

**Not supported: ReadShared (0x01)** — use ReadClean (0x02) instead.

### RSP channel (RN → HN, responses to snoops)

`SnpResp`, `CompAck`, `RetryAck`, `Comp`, `CompDBIDResp`, `DBIDResp`,
`PCrdGrant`, `ReadReceipt`, `SnpRespFwded`, `RspLCrdReturn`

### DAT channel (RN → HN, write data / snoop data)

`NonCopyBackWrData`, `CopyBackWrData`, `SnpRespData`, `CompData`,
`SnpRespDataFwded`, `WriteDataCancel`, `NCBWrDataCompAck`, `DatLCrdReturn`

---

## TLM RN-F testbench (`tlm_rnf_hnf_tb.sv`)

### Build (from `cva6-RNF/tb/`)

```bash
export QUESTA=/path/to/questa_24/questasim

make QUESTA=$QUESTA all          # compile SC model + SV/RTL
make QUESTA=$QUESTA sim          # batch sim, writes questa_build/vsim.wlf
make QUESTA=$QUESTA wave         # interactive GUI
make clean
```

### Runtime plusargs (via SIMARGS)

```bash
make QUESTA=$QUESTA sim SIMARGS="+rnf_verbose +mon_verbosity+2 +icn_debug"
```

| Flag | Effect |
|------|--------|
| `+rnf_verbose` | SC RN-F per-step trace (REQ sent, DBID received, data beats, DONE) |
| `+mon_verbosity+N` | chi_monitor verbosity: 0=errors only, 1=completions (default), 2=+per-flit |
| `+icn_debug` | Behavioral ICN flit-level trace |

### Known quirks

**HNF initialization latency** — the RTL HNF pipeline requires ~10 000 clock
cycles after reset before it can complete transactions.  The SC model waits
12 000 cycles (`tick(12000)`) before issuing the first REQ.  Sending earlier
causes the HNF to accept write data (DBIDResp) but never send the final Comp.

**sc_main does not receive vsim plusargs** — in Questa SV+SC co-simulation,
`argc`/`argv` in `sc_main` carry Questa-internal arguments, not the vsim
command line.  The `+rnf_verbose` flag is bridged via a DPI-C function
`chi_set_rnf_verbose()` called from SV in an `initial` block.

**hnf_defines.v from src/** — the `src/` version of `hnf_defines.v` must take
precedence over the opennoc copy.  It is placed first in `+incdir` in
`chi_tlm_flist`.  Using the wrong copy causes ReadClean to deadlock at
`REQ_RCVD_HNF` (HNF issues WriteNoSnpFull to SNF, receives CompDBIDResp,
then stalls).

### Test sequence

After the 12 000-cycle HNF init wait:
1. RNF0 WriteUniqueFull → `0x80000040`
2. RNF0 ReadClean → `0x80000040` (RAW verify, data `0xa0…`)
3. RNF1 ReadClean → `0x80000040` (coherent; HNF snoops RNF0 with SnpClean)
4. RNF1 CleanUnique → `0x80000040` (exclusive; HNF snoops RNF0 with SnpMakeInvalid)
5. RNF1 WriteUniqueFull → `0x80000040` (data `0xb0…`)
6. RNF1 ReadClean → `0x80000040` (write-back verify)
7. RNF1 calls `sc_stop()`

### SC model files

| File | Role |
|------|------|
| `chi_tlm_rnf.h` | SC module declaration, flit-width constants, REQ/RSP/DAT opcodes |
| `chi_tlm_rnf.cpp` | Link activation, credit management, transaction state machine |
| `questa_sc_main.cpp` | Minimal `sc_main()` stub (must exist; must not create SC instances) |

---

## gem5 co-simulation TB

Replaces HNF/SNF with gem5 CHI Ruby over POSIX shared-memory IPC
(`/chi_vip_0`).  Key width mismatches handled in the TB:

| Field | RTL | IPC bridge |
|-------|-----|------------|
| DATA  | 256 b (2 beats) | 512 b (1 beat) |
| TXNID | 12 b | 8 b (upper 4 bits truncated) |

Start gem5 first (it creates the shm segment), then vsim.
