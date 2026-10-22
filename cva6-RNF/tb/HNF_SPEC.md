# HN-F Specification

Behavioral CHI-E Home Node (HN-F) used in the `chi-rnf` testbench.
RTL source: `cva6-RNF/opennoc/rtl/src/hnf/` (with overrides in
`cva6-RNF/src/`).

---

## 1. Role and position in the system

The HN-F is the **Home Node for Fully-coherent traffic**. It is the
serialization point for every coherent transaction targeting its address
range; it owns the coherence state for every line it tracks and is
responsible for:

- Receiving REQ flits from RN-Fs via the ICN.
- Looking up the **L3 cache** and **snoop filter** for the target line.
- Issuing **snoops** to other RN-Fs that hold the line.
- Forwarding read/write requests to the **SN-F** (memory) when the L3
  misses or a write needs to be persisted.
- Returning **Comp / CompData / CompDBIDResp / DBIDResp** to the requester.
- Updating the snoop filter on Evict / CleanInvalid / snoop-response-I.

Position in the OpenNoC mesh:

```
RN-F(s)  ── CHI REQ/RSP/DAT/SNP ──  ICN  ──  HN-F  ──  SN-F (memory)
```

Two RN-Fs (`RNF0`, `RNF1`) drive a single HN-F in the TLM testbench. The
HN-F talks to a single SN-F at NID 32.

---

## 2. Parameters (from `cache/include/hnf_param.v`)

| Parameter | Value | Description |
|-----------|------:|-------------|
| `CHIE_REQ_ADDR_WIDTH_PARAM`  | 44      | REQ flit address width (byte addr) |
| `CHIE_SNP_ADDR_WIDTH_PARAM`  | 41      | SNP flit address width (line-shifted by 3) |
| `CHIE_NID_WIDTH_PARAM`       | 7       | Node ID width |
| `CHIE_DATA_WIDTH_PARAM`      | 256     | DAT flit data width (bits) |
| `CHIE_BE_WIDTH_PARAM`        | 32      | Byte-enable width per beat |
| `HNF_SF_ENTRIES_NUM_PARAM`   | 131 072 | Snoop-filter entries |
| `HNF_SF_WAY_NUM_PARAM`       | 16      | Snoop-filter associativity |
| `HNF_MSHR_ENTRIES_NUM_PARAM` | 32      | Outstanding MSHR entries |
| `HNF_MSHR_ENTRIES_WIDTH_PARAM`| 5      | MSHR entry index width |
| `HNF_L3_CACHE_SIZE_PARAM`    | 4 096   | L3 size (KB) |
| `HNF_L3_WAY_NUM_PARAM`       | 16      | L3 associativity |
| `HNF_NID_PARAM`              | 0 (TB override: 2) | HN-F's CHI Node ID |
| `SNF_NID_PARAM`              | 32      | SN-F's CHI Node ID |
| `HNF_MSHR_RNF_NUM_PARAM`     | 4       | Maximum RN-Fs the HN-F tracks |
| `HNF_MSHR_EXCL_RN_NUM_PARAM` | 32      | Exclusive-monitor entries |
| `XP_LCRD_NUM_PARAM`          | 15      | Initial link credits per channel |

A cache line is 64 B (`CACHE_BLOCK_OFFSET = 6`), so each line is two
256-bit DAT flits.

---

## 3. Module hierarchy

```
hnf (hnf.v)
 ├── hnf_link               (CHI flit ingress/egress, link-activation, credits)
 │    ├── hnf_link_rxreq_parse   (REQ decode + supported-opcode assertion)
 │    ├── hnf_link_rxrsp_parse   (RSP decode)
 │    ├── hnf_link_rxdat_parse   (DAT decode)
 │    ├── hnf_link_txreq_wrap    (REQ to SN-F)
 │    ├── hnf_link_txrsp_wrap    (RSP to RN-F)
 │    ├── hnf_link_txsnp_wrap    (SNP to RN-F)
 │    └── hnf_link_txdat_wrap    (DAT to RN-F or SN-F)
 │
 ├── hnf_mshr                (MSHR top wrapper)
 │    ├── hnf_mshr_addr_buffer    (address CAM, hazard detection)
 │    ├── hnf_mshr_ctl            (per-entry state machine + arbiter)
 │    ├── hnf_mshr_bypass         (zero-latency fast path for non-hazarding REQs)
 │    ├── hnf_mshr_global_monitor (multi-RNF exclusive monitor)
 │    └── hnf_mshr_qos            (priority/QoS arbitration)
 │
 ├── hnf_cache_pipeline      (8-stage L3 pipeline: tag/data/SF lookup, snoop gen,
 │                            data return, L3 fill, evict)
 │
 ├── hnf_data_buffer         (per-MSHR line buffer for RN-F write data and
 │                            in-flight CompData)
 │
 ├── hnf_sf_sram             (snoop-filter SRAM, 131 072 × 16-way)
 ├── hnf_tag_sram            (L3 tag SRAM)
 ├── hnf_lru_sram            (L3/SF LRU state SRAM)
 ├── hnf_data_sram           (L3 data SRAM)
 └── hnf_mem_ctl             (SN-F controller — packs/unpacks SN-F protocol)
```

---

## 4. Supported CHI opcodes

The HN-F's REQ allow-list is enforced by `display_fatal` in
`hnf_link_rxreq_parse.v` line ~255. Any incoming REQ outside this list
triggers a fatal assertion.

| Opcode | Name | RN-F→HN-F flow | Notes |
|-------:|------|----------------|-------|
| 0x02 | ReadClean | REQ → 2×CompData (+CompAck) | ends in SC; SnpClean to other holders |
| 0x03 | ReadOnce | REQ → 2×CompData (+CompAck) | non-allocating, no SF update |
| 0x04 | ReadNoSnp | REQ → 2×CompData | non-coherent, DMT to SN-F |
| 0x07 | ReadUnique | REQ → 2×CompData (+CompAck) | ends in UC; invalidating snoops |
| 0x08 | CleanShared | REQ → Comp | dataless hint, state unchanged |
| 0x09 | CleanInvalid | REQ → Comp | invalidates the line at all holders |
| 0x0b | CleanUnique | REQ → Comp + CompAck | SC→UC, snoops other holders |
| 0x0c | MakeUnique | REQ → Comp + CompAck | I→UCE, no data fetch |
| 0x0d | Evict | REQ → Comp | RN-F drops a clean line; SF cleanup |
| 0x15 | WriteEvictFull | REQ → DBIDResp → 2×CopyBackWrData → Comp | write-evict |
| 0x17 | WriteCleanFull | REQ → DBIDResp → 2×CopyBackWrData → Comp | write-back, keep clean |
| 0x18 | WriteUniquePtl | REQ → DBIDResp → 2×NonCopyBackWrData (with BE) → Comp | partial RMW |
| 0x19 | WriteUniqueFull | REQ → DBIDResp → 2×NonCopyBackWrData → Comp | full coherent write |
| 0x1a | WriteBackPtl | REQ → DBIDResp → 2×CopyBackWrData (with BE) → Comp | partial WB |
| 0x1b | WriteBackFull | REQ → CompDBIDResp → 2×CopyBackWrData | full WB |
| 0x1c | WriteNoSnpPtl | REQ → (Comp)DBIDResp → 2×NonCopyBackWrData (with BE) → Comp | non-coherent |
| 0x1d | WriteNoSnpFull | REQ → (Comp)DBIDResp → 2×NonCopyBackWrData → Comp | non-coherent |
| 0x26 | ReadNotSharedDirty | REQ → 2×CompData (+CompAck) | ends in SC (never SD) |

**Not supported** (triggers fatal): ReadShared (0x01), MakeInvalid (0x0a),
all Atomics, all CHI-E extended opcodes (bit[6]=1), Stash variants,
DVMOp, partial-zero writes.

Opcode values come from `cva6-RNF/cache/include/chie_defines.v` and the
two identical copies under `cache/rnf_link/include/` and
`opennoc/rtl/include/`.

---

## 5. Coherence protocol

### 5.1 Cache states tracked

The HN-F tracks the line's **directory state** (per snoop-filter entry)
plus per-MSHR transient state. From the directory's point of view a line
can be:

- **Invalid** — no RN-F holds the line (line may still be present in L3).
- **Shared(C)** — one or more RN-Fs hold the line in SC.
- **Unique(C/D)** — exactly one RN-F holds the line in UC / UD / UCE / SD.

The RN-F-visible state machine (I, SC, UC, UCE, UD, SD) is enforced by
the RN-F cache; the HN-F sees only the directory abstraction plus
explicit ack-Resp values returned in snoop responses.

### 5.2 Snoop generation

For each coherent REQ the HN-F looks up the snoop filter. If sharers
exist that the REQ requires to be invalidated or downgraded, the HN-F
issues a snoop on the TXSNP channel to each holder. Snoop opcode
selection (typical):

| Triggering REQ from RN-F X | Snoop sent to other RN-F holder(s) |
|---------------------------|------------------------------------|
| ReadClean / ReadOnce | SnpCleanFwd or SnpShared (downgrade UC→SC) |
| ReadNotSharedDirty | SnpNotSharedDirty / SnpNotSharedDirtyFwd |
| ReadUnique | SnpUniqueFwd (invalidate, forward data) |
| CleanUnique | SnpCleanInvalid (invalidate clean line) |
| MakeUnique | SnpMakeInvalid (invalidate, no data) |
| CleanInvalid | SnpCleanInvalid |
| WriteUniqueFull/Ptl (no allocate) | SnpCleanInvalid to all sharers |
| WriteBackFull/Ptl, WriteCleanFull, Evict | (no snoop — local action) |
| WriteNoSnp* | (no snoop — non-coherent) |

Snoop response expectations:
- **SnpResp(I)** — target invalidated, no data forwarded
- **SnpResp(SC)** — target downgraded to SC, clean
- **SnpRespData(I/SC/UC, dirty?)** — same plus data forwarded
- **SnpRespFwded** — target forwarded data directly to a third party (DCT)

### 5.3 Ordered transactions and CompAck

Any REQ with `ExpCompAck = 1` causes the HN-F to arm the MSHR's
`compack_busy` bit. The MSHR entry only retires when the RN-F replies
with `CompAck` (RSP opcode 0x02, TxnID = DBID from the last
Comp/CompData/CompDBIDResp).

> **Trap:** `compack_busy` is keyed purely off the REQ's ExpCompAck bit
> — the opcode is ignored. A WriteNoSnpFull sent with `order=2 /
> expcompack=1` (to disable DWT) therefore requires a CompAck even
> though the CHI spec normally doesn't ask for one on
> WriteNoSnp.

### 5.4 Address ordering and CAM hazards

Multiple in-flight REQs to the same cache line are serialised by the
**address buffer** (`hnf_mshr_addr_buffer.v`):

- On every REQ arrival, the new request's line address is compared
  against every active MSHR entry whose address is registered
  (`abf_can_compare_sx_q[i] == 1`).
- A match raises `rxreq_cam_hazard_s1_q = 1`, which forces the new REQ
  through the slower **cache pipeline path** instead of the bypass.
- The hazard clears when the conflicting MSHR retires
  (`mshr_dbf_retired_*` signals) or is being evicted from L3.

This guarantees that two transactions to the same line are processed in
a serialized fashion, even when the issuing RN-Fs send them
concurrently.

---

## 6. MSHR microarchitecture

The MSHR is the heart of the HN-F. It holds up to **32 outstanding
transactions** (parameter `HNF_MSHR_ENTRIES_NUM_PARAM`).

### 6.1 Per-entry busy bits

A given entry is "busy" — i.e. cannot retire — while any of these are
set (`hnf_mshr_ctl.v` line ~2408):

```
mshr_entry_busy_sx = mshr_pipeline_busy_sx     // L3 lookup / fill in flight
                   | mshr_mem_busy_sx          // MEM RD or MEM WR in flight
                   | mshr_datbuf_busy_sx       // RN-F or SN-F data buffer occupied
                   | mshr_rsp_busy_sx          // Comp/DBID/RdReceipt pending
                   | mshr_snp_busy_sx          // Snoop responses pending
                   | mshr_compack_busy_sx;     // CompAck pending
```

Retirement (`mshr_can_retire_entry_sx1`) tears down all the per-entry
state, frees the L3 / data-buffer slots, and clears the SF entry hazard
so other in-flight REQs to the same line can finally make progress.

### 6.2 The bypass path (`hnf_mshr_bypass.v`)

For transactions that do **not** need a cache-pipeline lookup, the
HN-F provides a 1-cycle bypass:

- **READ side bypass** — `tx_rdnosnp_s1_q`, `tx_wrnosnpful_s1`,
  `tx_wrnosnpptl_s1`: forwards the REQ straight to SN-F (or returns
  Comp directly).
- **RSP side bypass** — `rd_receipt_s1_q`, `wr_compdbid_s1_q`,
  `wr_dbid_s1_q`: returns DBIDResp / CompDBIDResp / ReadReceipt to the
  RN-F at MSHR allocation time.

A `cam_hazard` blocks both bypasses and forces the cache-pipeline path
(`txreq_mshr_bypass_lost_s1 = 1`,
`txrsp_mshr_bypass_lost_s1 = 1`).

### 6.3 Comp/CompDBIDResp at MSHR allocation

```verilog
wr_compdbid_s0 = (req_cb_s0 ||
                  (req_wrnosnp_s0 &&
                    (excl == 1 || (order == 2 && expcompack == 1))))
                 && mshr_alloc_en_s0;
```

This fires for:
- WriteBackFull (`req_cb_s0`) — combined Comp + DBIDResp at allocation
- WriteNoSnpFull/Ptl with `excl=1` OR `order=2/expcompack=1` — same
  combined response, used to *disable DWT* (see §7.2).

### 6.4 DBID semantics

When the HN-F sends DBIDResp / CompDBIDResp / CompData, the DBID field
carries the value the RN-F must place in subsequent flits that target
the same transaction:

- **DBID in DBIDResp / CompDBIDResp** → used by RN-F as TxnID in
  NonCopyBackWrData / CopyBackWrData (write data beats).
- **DBID in CompData** → used by RN-F as TxnID in CompAck (RSP).

In the current configuration the HN-F often returns `DBID = 0` because
only one MSHR entry is active at a time in the non-interleaved tests.
DBID=0 is a valid identifier; the chi_monitor was updated to remap it
correctly.

---

## 7. DMT and DWT

### 7.1 Direct Memory Transfer (DMT)

For `ReadNoSnp` the HN-F can shortcut data return through the SN-F:

```verilog
// hnf_mshr_bypass.v
assign do_dmt_s0 = (!(((order == 2'b10) && (expcompack == 0)) ||
                       (excl == 1))) &&
                    ((opcode == CHIE_READNOSNP));
```

When DMT is enabled:
- HN-F forwards ReadNoSnp to SN-F with **ReturnNID = original RN-F SrcID**
  and **ReturnTxnID = original RN-F TxnID**.
- SN-F replies with CompData targeted directly at the RN-F (skipping
  the HN-F on the data path).
- HN-F's MSHR is told the data was returned indirectly
  (`mshr_alloc_dmt_s1[entry] = 1`, latched into
  `mshr_dmt_sx8_q[entry]`).

### 7.2 Direct Write Transfer (DWT)

For `WriteNoSnpFull/Ptl` and `WriteUniqueFull` with `MemAttr.Allocate=0`:

```verilog
do_dwt_wrnosnpfull_s0 = (!(order == 2'b10 && expcompack == 1) &&
                          !excl &&
                          (opcode == WRITENOSNPFULL))
                       || /* other op-dependent terms */;
```

When DWT is enabled the HN-F instructs the SN-F to send a DBIDResp
directly to the RN-F (ReturnNID = RN-F, ReturnTxnID = original
RN-F TxnID). The RN-F then sends `NonCopyBackWrData` with
`TgtID = SNF_NID, TxnID = SNF_DBID`.

> **Caveat — ICN routing in this testbench:** the behavioral ICN
> (`chi_icn_beh.sv`) routes every RN-F TX DAT to the HN-F regardless of
> TgtID. DWT therefore breaks: the data arrives at the HN-F with a
> DBID the HN-F does not recognise. The fix used in the SC RN-F is to
> set `order=2/expcompack=1` on every WriteNoSnp* REQ, which forces
> the HN-F to disable DWT and return a combined CompDBIDResp instead.

---

## 8. Cache pipeline

`hnf_cache_pipeline.v` is an 8-stage pipeline (s0…s7+sx8) that handles
every transaction the bypass cannot. Per cycle:

| Stage | Activity |
|-------|----------|
| s0  | Tag SRAM read enable, SF read enable, MSHR entry select |
| s1  | Tag/SF hit determination, way selection, hazard checks |
| s2  | L3 data SRAM read enable (on hit), MSHR state update |
| s3  | Snoop generation if needed (`mshr_needsnp_sx3`) |
| s4  | Data forwarding to data buffer or RN-F |
| s5  | L3 fill data assemble |
| s6  | L3 write back to data SRAM (on fill / on WB) |
| s7  | L3 evict commit (`l3_evict_sx7_q`) |
| sx8 | Final DMT/DWT state latch, retirement signaling |

The pipeline interlocks with the MSHR via `mshr_pipeline_busy_sx`
(set by `l3_rd_busy` / `l3_fill_busy` per entry). A single MSHR entry
can re-enter the pipeline if `mshr_resent_s1_q` is asserted
(used when a snoop response unblocks the pipeline read).

---

## 9. Snoop filter

`hnf_sf_sram` holds 131 072 × 16-way entries. Each entry tracks the
set of RN-Fs that currently hold a given cache line. The HN-F looks up
the SF in parallel with the L3 tag.

SF update events:
- On `ReadClean / ReadUnique / ReadNotSharedDirty`: add the requesting
  RN-F to the holders set.
- On `Evict / CleanInvalid / WriteUnique* (allocate=0)`: remove the
  RN-F from the holders set.
- On `MakeUnique / CleanUnique`: mark the requesting RN-F as the
  unique owner (after invalidating snoops complete).
- On `WriteBackFull/Ptl`: remove the RN-F from holders, mark line
  invalid in directory but write data to L3.

When the SF would evict an entry to make room for a new one, the
HN-F first issues back-invalidate snoops to the existing holders
(`l3_evict_sx7_q` path).

---

## 10. Link layer

`hnf_link.v` plus its parsers/wrappers implement CHI link-level
flow control:

- **L-credits** — each of REQ, RSP, DAT, SNP has an independent credit
  counter. Initial credits are granted via the LCRDV signal after
  link activation. The HN-F advertises `XP_LCRD_NUM_PARAM = 15`
  credits per channel.
- **Link activation handshake** — TXLINKACTIVEREQ /
  RXLINKACTIVEACK, four-phase.
- **Flit pending** — `FLITPEND` is asserted one cycle ahead of
  `FLITV` to give the receiver one cycle of pipeline lookahead.

The TLM RN-F's `chi_tlm_rnf.cpp` mirrors this on the SC side: each
channel has its own credit counter (`m_req_crd`, `m_rsp_crd`,
`m_dat_crd`) that is incremented by `*LCRDV` pulses and decremented on
every flit sent.

---

## 11. Known quirks and gotchas (this implementation)

1. **`compack_busy` is opcode-agnostic.** Any REQ with `ExpCompAck=1`
   wedges the MSHR until a `CompAck` arrives. WriteNoSnp* with
   `order=2/expcompack=1` therefore requires the RN-F to send CompAck —
   the chi_tlm_rnf model does this inline.

2. **`hnf_defines.v` override.** The version under `cva6-RNF/src/`
   must take precedence over the OpenNoC copy. Using the OpenNoC
   version causes ReadClean to deadlock at `REQ_RCVD_HNF` (HNF issues
   WriteNoSnpFull to SNF, gets CompDBIDResp, then stalls).

3. **HNF init latency.** ~10 000 cycles after reset before the HNF
   pipeline can complete transactions. The SC RN-Fs wait 12 000
   cycles before issuing their first REQ.

4. **DBID=0 is valid.** The HNF returns `DBID=0` for most transactions
   in the current configuration (single MSHR entry active at a time).
   The chi_monitor used to skip its DBID-remap table when DBID=0,
   causing false-positive `TxnID COLLISION` errors; this has been
   fixed.

5. **TXSNP port width mismatch.** The HNF's TXSNPFLIT port is 106 bits
   but the ICN's snoop bus is wired at 99 bits. The upper 7 bits are
   silently zero on both ends and the connection works, but you'll see
   a vsim-3015 warning at elaboration.

6. **WriteNoSnpPtl with `order=2/expcompack=1`.** This combination
   disables DWT for `WriteNoSnpFull` but the corresponding
   `do_dwt_wrnosnpptl_s0` term in `hnf_mshr_bypass.v` may not be
   wired the same way. The TLM Ph11 test of WriteNoSnpPtl with
   `be0=0xFFFFFFFF, be1=0` currently fails — the partial write does
   not reach memory. Suspected: HNF/SNF byte-merge path for the
   `Ptl` variant.

7. **WriteUniqueFull→ReadNoSnp ordering.** A `ReadNoSnp` immediately
   after a `WriteUniqueFull` to the same address (Ph18) currently
   returns stale memory data. `ReadOnce` of the same line returns the
   new value, suggesting the WriteUniqueFull data is in L3 but not
   yet committed through to the SN-F when the DMT-routed ReadNoSnp
   fires.

---

## 12. Reference: signal/state naming conventions

- `_s0`, `_s1`, …, `_sx7` — pipeline stages (combinational at the
  named stage; `_q` suffix means flopped one cycle later).
- `mshr_*_sx`     — per-MSHR-entry signals at stage sx (combinational).
- `mshr_*_sx_q`   — same, registered one cycle later.
- `txreq_*`, `txrsp_*`, `txdat_*`, `txsnp_*` — outgoing channels.
- `rxreq_*`, `rxrsp_*`, `rxdat_*` — incoming channels.
- `_busy_*` — entry is occupied / cannot retire.
- `_rdy_*`  — entry has work pending on the given channel; arbitrate
  before sending.

---

## 13. References

- ARM IHI 0050E — *AMBA 5 CHI Architecture Specification* (Issue E).
- `cva6-RNF/cache/include/chie_defines.v` — canonical CHI-E flit
  field and opcode definitions used by this RTL.
- `cva6-RNF/cache/include/hnf_param.v` — parameter block for the
  HN-F instantiation.
- `cva6-RNF/opennoc/rtl/src/hnf/` — source code (the
  `cva6-RNF/src/` overrides take precedence for the four files listed
  in `chi_tlm_flist`).
- `cva6-RNF/tb/readme.md` — testbench overview and phase list.
