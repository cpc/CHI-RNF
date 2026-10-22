/*
 * Copyright (c) 2026 Customized Parallel Computing (CPC) Group Tampere University
 *
 * SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
 *
 * Licensed under the Solderpad Hardware License v2.1 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at:
 *
 *     https://solderpad.org/licenses/SHL-2.1/
 *
 * Unless required by applicable law or agreed to in writing, any work
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
 * implied.  See the License for the specific language governing
 * permissions and limitations under the License.
 *
 * Author:
 * Abdesattar Kalache <abdesattar.kalache@tuni.fi>
 */

`timescale 1ns/1ps


`include "rnf_param.v"
`include "rnf_defines.v"

`include "hnf_param.v"
`include "hnf_defines.v"

`include "snf_param.v"
`include "snf_defines.v"

`include "chie_defines.v"


module chi_monitor #(
    parameter int CORE_COUNT = 2,
    parameter int ICN_RNF_REQ_CRDTS = 2,
    parameter int ICN_RNF_DAT_CRDTS = 2,
    parameter int ICN_RNF_RSP_CRDTS = 10,

    parameter int ICN_HNF_SNP_CRDTS = 8,
    parameter int ICN_HNF_REQ_CRDTS = 8,
    parameter int ICN_HNF_RSP_CRDTS = 8,
    parameter int ICN_HNF_DAT_CRDTS = 8,

    parameter int NUM_DATA_FLITS    = 2,

    parameter CHIE_REQ_ADDR_WIDTH_PARAM = 44,
    parameter CHIE_SNP_ADDR_WIDTH_PARAM = 41,
    parameter CHIE_NID_WIDTH_PARAM = 7,
    parameter CHIE_DATA_WIDTH_PARAM = 256,
    parameter CHIE_BE_WIDTH_PARAM = 32,
    parameter CHIE_DATACHECK_WIDTH_PARAM = 0,
    parameter CHIE_POISON_WIDTH_PARAM = 0,
    parameter CHIE_REQ_RSVDC_WIDTH_PARAM = 0,
    parameter CHIE_DAT_RSVDC_WIDTH_PARAM = 0,
    parameter HNF_MSHR_RNF_NUM_PARAM = 4,
    parameter HNF_MSHR_RNI_NUM_PARAM = 0,
    parameter RNF_NID_LIST_PARAM = {7'd0, 7'd1},
    parameter RNI_NID_LIST_PARAM = {7'd64},
    parameter HNF_NID_PARAM = CORE_COUNT,
    parameter SNF_NID_PARAM = 32,
    parameter XP_LCRD_NUM_PARAM = 15,
    parameter HNF_SF_ENTRIES_NUM_PARAM = 131072,
    parameter HNF_SF_WAY_NUM_PARAM = 16,
    parameter HNF_MSHR_EXCL_RN_NUM_PARAM = 32,
    parameter HNF_MSHR_EXCL_RN_WIDTH_PARAM = 5,
    parameter HNF_MSHR_ENTRIES_NUM_PARAM = 32,
    parameter HNF_MSHR_ENTRIES_WIDTH_PARAM = 5,
    parameter HNF_L3_CACHE_SIZE_PARAM = 4096,
    parameter HNF_L3_WAY_NUM_PARAM = 16,
    // Verbosity: 0=errors/deadlocks only  1=+completions  2=+per-flit trace
    parameter int VERBOSITY = 1
)(
    input  logic clk,
    input  logic rst,

    // =====================================================
    // RNF VECTORIZED INTERFACE (Aggregated from N Cores)
    // =====================================================
    // TX Path (RNF -> ICN)
    input  logic [CORE_COUNT-1:0]                           rnf_txreqflitv,
    input  logic [CORE_COUNT-1:0][`CHIE_REQ_FLIT_WIDTH-1:0] rnf_txreqflit,
    input  logic [CORE_COUNT-1:0]                           rnf_txreqlcrdv,

    input  logic [CORE_COUNT-1:0]                           rnf_txrspflitv,
    input  logic [CORE_COUNT-1:0][`CHIE_RSP_FLIT_WIDTH-1:0] rnf_txrspflit,
    input  logic [CORE_COUNT-1:0]                           rnf_txrsplcrdv,

    input  logic [CORE_COUNT-1:0]                           rnf_txdatflitv,
    input  logic [CORE_COUNT-1:0][`CHIE_DAT_FLIT_WIDTH-1:0] rnf_txdatflit,
    input  logic [CORE_COUNT-1:0]                           rnf_txdatlcrdv,

    // RX Path (ICN -> RNF)
    input  logic [CORE_COUNT-1:0]                           rnf_rxsnpflitv,
    input  logic [CORE_COUNT-1:0]                           rnf_rxsnppend,
    input  logic [CORE_COUNT-1:0][`CHIE_SNP_FLIT_WIDTH-1:0] rnf_rxsnpflit,
    input  logic [CORE_COUNT-1:0]                           rnf_rxsnplcrdv,

    input  logic [CORE_COUNT-1:0]                           rnf_rxrspflitv,
    input  logic [CORE_COUNT-1:0]                           rnf_rxrsppend,
    input  logic [CORE_COUNT-1:0][`CHIE_RSP_FLIT_WIDTH-1:0] rnf_rxrspflit,
    input  logic [CORE_COUNT-1:0]                           rnf_rxrsplcrdv,

    input  logic [CORE_COUNT-1:0]                           rnf_rxdatflitv,
    input  logic [CORE_COUNT-1:0]                           rnf_rxdatpend,
    input  logic [CORE_COUNT-1:0][`CHIE_DAT_FLIT_WIDTH-1:0] rnf_rxdatflit,
    input  logic [CORE_COUNT-1:0]                           rnf_rxdatlcrdv,

    // =====================================================
    // HNF INTERFACE (Home Node)
    // =====================================================
    // HNF RX (Traffic coming into HNF)
    input  logic                         hnf_rxreqflitv,
    input  logic [`CHIE_REQ_FLIT_WIDTH-1:0] hnf_rxreqflit,
    input  logic                         hnf_rxreqpend,
    input  logic                         hnf_rxreqlcrdv,

    input  logic                         hnf_rxrspflitv,
    input  logic [`CHIE_RSP_FLIT_WIDTH-1:0] hnf_rxrspflit,
    input  logic                         hnf_rxrsppend,
    input  logic                         hnf_rxrsplcrdv,

    input  logic                         hnf_rxdatflitv,
    input  logic [`CHIE_DAT_FLIT_WIDTH-1:0] hnf_rxdatflit,
    input  logic                         hnf_rxdatpend,
    input  logic                         hnf_rxdatlcrdv,

    // HNF TX (Traffic leaving HNF)
    input  logic                         hnf_txsnpflitv,
    input  logic [`CHIE_SNP_FLIT_WIDTH-1:0] hnf_txsnpflit,
    input  logic                         hnf_txsnppend,
    input  logic                         hnf_txsnplcrdv,

    input  logic                         hnf_txreqflitv,
    input  logic [`CHIE_REQ_FLIT_WIDTH-1:0] hnf_txreqflit,
    input  logic                         hnf_txreqpend,
    input  logic                         hnf_txreqlcrdv,

    input  logic                         hnf_txrspflitv,
    input  logic [`CHIE_RSP_FLIT_WIDTH-1:0] hnf_txrspflit,
    input  logic                         hnf_txrsppend,
    input  logic                         hnf_txrsplcrdv,

    input  logic                         hnf_txdatflitv,
    input  logic [`CHIE_DAT_FLIT_WIDTH-1:0] hnf_txdatflit,
    input  logic                         hnf_txdatpend,
    input  logic                         hnf_txdatlcrdv,

    // =====================================================
    // SNF INTERFACE (Slave Node / Memory)
    // =====================================================
    input  logic                         snf_rxreqflitv,
    input  logic [`CHIE_REQ_FLIT_WIDTH-1:0] snf_rxreqflit,
    input  logic                         snf_rxreqlcrdv,

    input  logic                         snf_rxdatflitv,
    input  logic [`CHIE_DAT_FLIT_WIDTH-1:0] snf_rxdatflit,
    input  logic                         snf_rxdatlcrdv,

    input  logic                         snf_txrspflitv,
    input  logic [`CHIE_RSP_FLIT_WIDTH-1:0] snf_txrspflit,
    input  logic                         snf_txrsplcrdv,

    input  logic                         snf_txdatflitv,
    input  logic [`CHIE_DAT_FLIT_WIDTH-1:0] snf_txdatflit,
    input  logic                         snf_txdatlcrdv
);

    // Composite key width: {SrcID[NID_W-1:0], TxnID[11:0]}
    localparam int KEY_W = `CHIE_REQ_FLIT_SRCID_WIDTH + `CHIE_REQ_FLIT_TXNID_WIDTH;

    localparam int VERB_ERRORS = 0;  // collisions, mismatches, deadlocks (always)
    localparam int VERB_DONE   = 1;  // + successful transaction/snoop completions
    localparam int VERB_TRACE  = 2;  // + per-flit events (REQ, SNP, retire)

    localparam int CACHE_LINE_SZ = 64;

    // Runtime verbosity — defaults to the VERBOSITY parameter but can be
    // overridden at simulation start with:  +mon_verbosity+<level>   (0 / 1 / 2)
    int verbosity_level = VERBOSITY;
    initial begin
        void'($value$plusargs("mon_verbosity+%d", verbosity_level));
    end  // bytes; addr[5:0] masked to get line address

    typedef enum logic [3:0] {
        IDLE,
        REQ_RCVD_ICN,   // Seen at RNF TXREQ, not yet at HNF
        REQ_RCVD_HNF,   // Confirmed at HNF RXREQ
        REQ_SENT_SNF,   // HNF forwarded to SNF
        DATA_FROM_SNF,  // SNF data on its way to HNF
        DATA_FROM_HNF,  // CompData beats arriving at RNF
        RSP_FROM_HNF,   // Comp received at RNF
        WRDAT_RCVD_HNF, // WrData (CopyBackWrData/NCBWrData) received at HNF RXDAT
        COMPLETED
    } chi_state_e;

    // Per-transaction record in the main scoreboard (keyed by {SrcID, TxnID})
    typedef struct packed {
        logic [`CHIE_REQ_FLIT_SRCID_WIDTH-1:0]  src_id;
        logic [`CHIE_REQ_FLIT_TXNID_WIDTH-1:0]  txn_id;
        logic [CHIE_NID_WIDTH_PARAM-1:0]         tgt_id;     // TgtID from REQ flit (= HNF NodeID)
        logic [CHIE_REQ_ADDR_WIDTH_PARAM-1:0]    acc_addr;   // byte-accurate address from REQ flit
        logic [CHIE_REQ_ADDR_WIDTH_PARAM-1:0]    addr;       // 64B cache-line-aligned address
        logic [`CHIE_REQ_FLIT_OPCODE_WIDTH-1:0]  opcode;
        chi_state_e                              state;
        logic                                    exp_comp_ack;
        int                                      dat_cnt;      // CompData beats received so far
        int                                      exp_dat_cnt;  // beats expected (NUM_DATA_FLITS for reads)
        time                                     start_time;
    } chi_txn_t;

    // Per-snoop record in the snoop scoreboard (keyed by {HNF_SrcID, SnpTxnID})
    typedef struct packed {
        logic [`CHIE_SNP_FLIT_SRCID_WIDTH-1:0]  src_id;     // HNF NodeID that issued the snoop
        logic [`CHIE_SNP_FLIT_TXNID_WIDTH-1:0]  txn_id;     // HNF snoop TxnID (= MSHR entry index)
        logic [CHIE_REQ_ADDR_WIDTH_PARAM-1:0]    addr;       // full cache-line address
        logic [`CHIE_SNP_FLIT_OPCODE_WIDTH-1:0]  opcode;
        // Bitmask of all snooped RNF NodeIDs (bit i set ↔ NodeID i was snooped).
        // Supports broadcast snoops where HNF uses the same TxnID for multiple targets.
        logic [CORE_COUNT-1:0]                   tgt_mask;
        // Forwarding-snoop fields (FWDNID/FWDTXNID): valid when opcode is a *Fwd variant.
        // The snooped RNF forwards CompData directly to FWDNID using FWDTXNID as TxnID.
        logic [CHIE_NID_WIDTH_PARAM-1:0]         fwd_nid;
        logic [`CHIE_SNP_FLIT_FWDTXNID_WIDTH-1:0] fwd_txn_id;
        int                                      rsp_cnt;      // snoop responses received so far
        int                                      exp_rsp_cnt;  // responses expected (one per target)
        time                                     start_time;
    } chi_snp_t;

    // Active transactions: TxnID not yet retired.
    // Key: {SrcID, TxnID}
    // Removed when TxnID is retired:
    //   reads  — after all CompData beats (+ CompAck if ExpCompAck=1)
    //   writes — at CompDBIDResp; entry migrated to txn_wrpend keyed by DBID
    chi_txn_t                              scoreboard      [bit[KEY_W-1:0]];

    // DBID remap for reads: {RNF_NodeID, DBID} -> original_TxnID
    // Populated from CompData DBID field; consumed when CompAck is sent.
    logic [`CHIE_REQ_FLIT_TXNID_WIDTH-1:0] dbid_scoreboard [bit[KEY_W-1:0]];

    // Write-data pending: full transaction record after TxnID retirement.
    // Key: {SrcID, DBID} — WrData uses DBID as TxnID, so this resolves it.
    // Uses the same chi_txn_t struct for uniform tracking and deadlock display.
    chi_txn_t                              txn_wrpend      [bit[KEY_W-1:0]];

    // Snoop scoreboard: {HNF_SrcID, SnpTxnID} -> chi_snp_t
    chi_snp_t                              snp_scoreboard  [bit[KEY_W-1:0]];

    // =========================================================================
    // Helpers
    // =========================================================================

    // Print a transaction record.
    task automatic log_txn(string tag, chi_txn_t e);
        $display("[CHI_MON]%s {Src:%0h TxnID:0x%h Tgt:%0h} State:%-14s Op:%0h LineAddr:%0h AccAddr:%0h ExpAck:%b Age:%0t",
            tag,
            e.src_id, e.txn_id, e.tgt_id,
            e.state.name(),
            e.opcode, e.addr, e.acc_addr,
            e.exp_comp_ack,
            $realtime - e.start_time);
    endtask

    // =========================================================================
    // Per-core RNF monitor
    // Tracks: REQ issued, CompData/Comp/CompDBIDResp received, CompAck/SnpResp sent.
    // =========================================================================
    task automatic monitor_rnf_transaction(int core_id);
        wait (rst == 1'b0);

        forever begin
            @(posedge clk);

            // ------------------------------------------------------------------
            // 1. RSP received by this RNF core (Comp, CompDBIDResp, DBIDResp)
            //    Processed before TXREQ: CompDBIDResp retires the TxnID here so
            //    the collision check in section 2 never sees a stale entry when
            //    the RN-F legally reuses the TxnID in the same cycle.
            // ------------------------------------------------------------------
            if (rnf_rxrspflitv[core_id]) begin
                automatic logic [CHIE_NID_WIDTH_PARAM-1:0] tgt =
                    rnf_rxrspflit[core_id][`CHIE_RSP_FLIT_TGTID_RANGE];
                automatic logic [`CHIE_REQ_FLIT_TXNID_WIDTH-1:0] tid =
                    rnf_rxrspflit[core_id][`CHIE_RSP_FLIT_TXNID_RANGE];
                automatic logic [`CHIE_RSP_FLIT_OPCODE_WIDTH-1:0] rop =
                    rnf_rxrspflit[core_id][`CHIE_RSP_FLIT_OPCODE_RANGE];
                automatic logic [`CHIE_REQ_FLIT_TXNID_WIDTH-1:0] dbid =
                    rnf_rxrspflit[core_id][`CHIE_RSP_FLIT_DBID_RANGE];
                automatic bit[KEY_W-1:0] key      = {tgt, tid};
                automatic bit[KEY_W-1:0] remap_key = {tgt, dbid};

                if (scoreboard.exists(key)) begin
                    if (rop == `CHIE_COMPDBIDRESP) begin
                        // CHI: TxnID is retired at the requester after CompDBIDResp.
                        // RXRSP is processed before TXREQ each cycle so this delete
                        // happens before any new REQ reusing the same TxnID is checked.
                        // WrData uses DBID as TxnID and is tracked in wrdat_pending.
                        if (verbosity_level >= VERB_TRACE)
                            $display("[CHI_MON][RNF-%0d] CompDBIDResp t=%t {Src:%0h TxnID:0x%h Tgt:%0h} DBID:0x%h LineAddr:%0h AccAddr:%0h → retire TxnID",
                                core_id, $realtime, scoreboard[key].src_id, tid, scoreboard[key].tgt_id, dbid,
                                scoreboard[key].addr, scoreboard[key].acc_addr);
                        txn_wrpend[remap_key]       = scoreboard[key];
                        txn_wrpend[remap_key].state = RSP_FROM_HNF;
                        scoreboard.delete(key);
                    end else if (rop == `CHIE_COMP) begin
                        scoreboard[key].state = RSP_FROM_HNF;
                        if (!scoreboard[key].exp_comp_ack) begin
                            if (verbosity_level >= VERB_DONE)
                                $display("[CHI_MON][RNF-%0d] DONE  t=%t {Src:%0h TxnID:0x%h Tgt:%0h} Op:%0h LineAddr:%0h AccAddr:%0h (Comp, no CompAck)",
                                    core_id, $realtime, scoreboard[key].src_id, tid, scoreboard[key].tgt_id,
                                    scoreboard[key].opcode, scoreboard[key].addr, scoreboard[key].acc_addr);
                            scoreboard.delete(key);
                        end else begin
                            // CompAck will follow with TxnID = DBID of this Comp.
                            // Dataless ops (CleanUnique, MakeUnique) never receive
                            // CompData, so this is the only chance to populate the
                            // DBID-to-original-TxnID remap for the CompAck handler.
                            dbid_scoreboard[remap_key] = tid;
                        end
                    end else begin
                        scoreboard[key].state = RSP_FROM_HNF;
                    end
                end
            end

            // ------------------------------------------------------------------
            // 2. REQ sent by this RNF core
            // ------------------------------------------------------------------
            if (rnf_txreqflitv[core_id]) begin
                automatic logic [`CHIE_REQ_FLIT_SRCID_WIDTH-1:0] src =
                    rnf_txreqflit[core_id][`CHIE_REQ_FLIT_SRCID_RANGE];
                automatic logic [`CHIE_REQ_FLIT_TXNID_WIDTH-1:0] tid =
                    rnf_txreqflit[core_id][`CHIE_REQ_FLIT_TXNID_RANGE];
                automatic bit[KEY_W-1:0] key = {src, tid};
                automatic logic [`CHIE_REQ_FLIT_OPCODE_WIDTH-1:0] op =
                    rnf_txreqflit[core_id][`CHIE_REQ_FLIT_OPCODE_RANGE];
                automatic logic [CHIE_NID_WIDTH_PARAM-1:0] tgt =
                    rnf_txreqflit[core_id][`CHIE_REQ_FLIT_TGTID_RANGE];
                automatic logic [CHIE_REQ_ADDR_WIDTH_PARAM-1:0] acc_addr =
                    rnf_txreqflit[core_id][`CHIE_REQ_FLIT_ADDR_RANGE];
                automatic logic [CHIE_REQ_ADDR_WIDTH_PARAM-1:0] addr =
                    {acc_addr[CHIE_REQ_ADDR_WIDTH_PARAM-1:$clog2(CACHE_LINE_SZ)],
                     $clog2(CACHE_LINE_SZ)'(0)};

                if (scoreboard.exists(key)) begin
                    $display("[CHI_MON][RNF-%0d] TxnID COLLISION t=%t {Src:%0h TxnID:0x%h Tgt:%0h} newOp:%0h newLineAddr:%0h existOp:%0h existLineAddr:%0h",
                        core_id, $realtime, src, tid, tgt, op, addr,
                        scoreboard[key].opcode, scoreboard[key].addr);
                    // log_txn($sformatf("[RNF-%0d] existing", core_id), scoreboard[key]);
                end else begin
                    scoreboard[key].src_id       = src;
                    scoreboard[key].txn_id       = tid;
                    scoreboard[key].tgt_id       = tgt;
                    scoreboard[key].acc_addr     = acc_addr;
                    scoreboard[key].addr         = addr;
                    scoreboard[key].opcode       = op;
                    scoreboard[key].exp_comp_ack = rnf_txreqflit[core_id][`CHIE_REQ_FLIT_EXPCOMPACK_RANGE];
                    scoreboard[key].state        = REQ_RCVD_ICN;
                    scoreboard[key].dat_cnt      = 0;
                    scoreboard[key].exp_dat_cnt  = NUM_DATA_FLITS;
                    scoreboard[key].start_time   = $realtime;
                    if (verbosity_level >= VERB_TRACE)
                        $display("[CHI_MON][RNF-%0d] REQ   t=%t {Src:%0h TxnID:0x%h Tgt:%0h} Op:%0h LineAddr:%0h AccAddr:%0h ExpAck:%b",
                            core_id, $realtime, src, tid, tgt, op, addr, acc_addr,
                            scoreboard[key].exp_comp_ack);
                end
            end

            // ------------------------------------------------------------------
            // 3. CompData received by this RNF core (data from HNF)
            // ------------------------------------------------------------------
            if (rnf_rxdatflitv[core_id]) begin
                automatic logic [CHIE_NID_WIDTH_PARAM-1:0] tgt =
                    rnf_rxdatflit[core_id][`CHIE_DAT_FLIT_TGTID_RANGE];
                automatic logic [`CHIE_REQ_FLIT_TXNID_WIDTH-1:0] tid =
                    rnf_rxdatflit[core_id][`CHIE_DAT_FLIT_TXNID_RANGE];
                automatic bit[KEY_W-1:0] key = {tgt, tid};
                automatic logic [`CHIE_REQ_FLIT_TXNID_WIDTH-1:0] dbid =
                    rnf_rxdatflit[core_id][`CHIE_DAT_FLIT_DBID_RANGE];
                automatic bit[KEY_W-1:0] remap_key = {tgt, dbid};

                if (scoreboard.exists(key)) begin
                    scoreboard[key].state = DATA_FROM_HNF;
                    scoreboard[key].dat_cnt++;

                    // DBID=0 is a valid CHI identifier (HNFs may legitimately
                    // reuse MSHR entry 0).  Always populate the remap.
                    dbid_scoreboard[remap_key] = tid;

                    if (scoreboard[key].dat_cnt >= scoreboard[key].exp_dat_cnt) begin
                        if (!scoreboard[key].exp_comp_ack) begin
                            if (verbosity_level >= VERB_DONE)
                                $display("[CHI_MON][RNF-%0d] DONE  t=%t {Src:%0h TxnID:0x%h Tgt:%0h} Op:%0h LineAddr:%0h AccAddr:%0h (CompData, no CompAck)",
                                    core_id, $realtime, scoreboard[key].src_id, tid, scoreboard[key].tgt_id,
                                    scoreboard[key].opcode, scoreboard[key].addr, scoreboard[key].acc_addr);
                            scoreboard.delete(key);
                        end
                    end
                end
            end

            // ------------------------------------------------------------------
            // 4. RSP sent by this RNF core (CompAck, SnpResp, SnpRespFwded)
            // ------------------------------------------------------------------
            if (rnf_txrspflitv[core_id]) begin
                automatic logic [CHIE_NID_WIDTH_PARAM-1:0] src =
                    rnf_txrspflit[core_id][`CHIE_RSP_FLIT_SRCID_RANGE];
                automatic logic [`CHIE_REQ_FLIT_TXNID_WIDTH-1:0] tid =
                    rnf_txrspflit[core_id][`CHIE_RSP_FLIT_TXNID_RANGE];
                automatic logic [`CHIE_RSP_FLIT_OPCODE_WIDTH-1:0] rop =
                    rnf_txrspflit[core_id][`CHIE_RSP_FLIT_OPCODE_RANGE];
                automatic logic [CHIE_NID_WIDTH_PARAM-1:0] tgt =
                    rnf_txrspflit[core_id][`CHIE_RSP_FLIT_TGTID_RANGE];
                automatic bit[KEY_W-1:0] dbid_key = {src, tid};

                if (rop == `CHIE_COMPACK) begin
                    // tid in CompAck = DBID from CompDBIDResp/CompData, src = RNF NodeID
                    if (dbid_scoreboard.exists(dbid_key)) begin
                        automatic logic [`CHIE_REQ_FLIT_TXNID_WIDTH-1:0] orig_tid =
                            dbid_scoreboard[dbid_key];
                        automatic bit[KEY_W-1:0] orig_key = {src, orig_tid};
                        if (scoreboard.exists(orig_key)) begin
                            if (verbosity_level >= VERB_DONE)
                                $display("[CHI_MON][RNF-%0d] DONE  t=%t {Src:%0h TxnID:0x%h Tgt:%0h} Op:%0h LineAddr:%0h AccAddr:%0h (CompAck)",
                                    core_id, $realtime, src, orig_tid, scoreboard[orig_key].tgt_id,
                                    scoreboard[orig_key].opcode, scoreboard[orig_key].addr, scoreboard[orig_key].acc_addr);
                            scoreboard.delete(orig_key);
                        end
                        dbid_scoreboard.delete(dbid_key);
                    end

                end else if (rop == `CHIE_SNPRESP || rop == `CHIE_SNPRESPFWDED) begin
                    // tid = snoop TxnID (from snoop flit), tgt = HNF NodeID
                    automatic logic [`CHIE_RSP_FLIT_RESP_WIDTH-1:0] resp =
                        rnf_txrspflit[core_id][`CHIE_RSP_FLIT_RESP_RANGE];
                    // Key on TXNID only (see block 4b comment).
                    automatic bit[KEY_W-1:0] snp_key = {'0, tid};
                    if (snp_scoreboard.exists(snp_key)) begin
                        snp_scoreboard[snp_key].rsp_cnt++;
                        if (snp_scoreboard[snp_key].rsp_cnt >= snp_scoreboard[snp_key].exp_rsp_cnt) begin
                            if (verbosity_level >= VERB_DONE)
                                $display("[CHI_MON][RNF-%0d] SNP DONE t=%t {Src:%0h Tgt:%0h SnpTid:0x%h} Addr:%0h (SnpResp op=%0h Resp=%0h)",
                                    core_id, $realtime, src, tgt, tid,
                                    snp_scoreboard[snp_key].addr, rop, resp);
                            snp_scoreboard.delete(snp_key);
                        end
                    end
                end
            end

            // ------------------------------------------------------------------
            // 4b. DAT sent by this RN-F core — data-bearing snoop response
            //     variants (SnpRespData / SnpRespDataPtl / SnpRespDataFwded).
            //     These retire the snp_scoreboard entry just like TXRSP
            //     SnpResp does; without this, dirty-line snoops that answer
            //     via data (CHI E.b §4.5, §4.8) leave the entry outstanding
            //     forever and the monitor falsely flags an unretired snoop.
            //     Only the *first* beat retires; subsequent beats carry the
            //     same tid but the entry is already deleted, so the exists()
            //     guard covers it.
            // ------------------------------------------------------------------
            if (rnf_txdatflitv[core_id]) begin
                automatic logic [CHIE_NID_WIDTH_PARAM-1:0] dsrc =
                    rnf_txdatflit[core_id][`CHIE_DAT_FLIT_SRCID_RANGE];
                automatic logic [`CHIE_REQ_FLIT_TXNID_WIDTH-1:0] dtid =
                    rnf_txdatflit[core_id][`CHIE_DAT_FLIT_TXNID_RANGE];
                automatic logic [`CHIE_DAT_FLIT_OPCODE_WIDTH-1:0] dop =
                    rnf_txdatflit[core_id][`CHIE_DAT_FLIT_OPCODE_RANGE];
                automatic logic [CHIE_NID_WIDTH_PARAM-1:0] dtgt =
                    rnf_txdatflit[core_id][`CHIE_DAT_FLIT_TGTID_RANGE];
                automatic logic [`CHIE_DAT_FLIT_RESP_WIDTH-1:0] dresp =
                    rnf_txdatflit[core_id][`CHIE_DAT_FLIT_RESP_RANGE];
                // Key on TXNID only — the HN-F's outgoing-snoop SRCID and
                // the RN-F's response-flit TGTID sometimes disagree by
                // configuration (gem5 HN-F may stamp SRCID=0 while the
                // RN-F was configured with HNF_NID_PARAM=CORE_COUNT).
                // TXNID uniquely identifies an outstanding snoop at the
                // HN-F, so this key is unambiguous regardless.
                automatic bit[KEY_W-1:0] dsnp_key = {'0, dtid};

                if (dop == `CHIE_SNPRESPDATA ||
                    dop == `CHIE_SNPRESPDATAPTL ||
                    dop == `CHIE_SNPRESPDATAFWDED) begin
                    if (snp_scoreboard.exists(dsnp_key)) begin
                        snp_scoreboard[dsnp_key].rsp_cnt++;
                        if (snp_scoreboard[dsnp_key].rsp_cnt >=
                            snp_scoreboard[dsnp_key].exp_rsp_cnt) begin
                            if (verbosity_level >= VERB_DONE)
                                $display("[CHI_MON][RNF-%0d] SNP DONE t=%t {Src:%0h Tgt:%0h SnpTid:0x%h} Addr:%0h (SnpRespData op=%0h Resp=%0h)",
                                    core_id, $realtime, dsrc, dtgt, dtid,
                                    snp_scoreboard[dsnp_key].addr, dop, dresp);
                            snp_scoreboard.delete(dsnp_key);
                        end
                    end
                end
            end

        end
    endtask

    // =========================================================================
    // HNF + SNF monitor (single instance — runs once, not per-core)
    // Tracks: REQ arrival at HNF (with address assertion), snoop issuance,
    //         write-data arrival at HNF, and HNF→SNF→HNF data path.
    // =========================================================================
    task automatic monitor_hnf();
        wait (rst == 1'b0);

        forever begin
            @(posedge clk);

            // ------------------------------------------------------------------
            // HNF receives REQ from ICN — advance state + assert address
            // ------------------------------------------------------------------
            if (hnf_rxreqflitv) begin
                automatic logic [CHIE_NID_WIDTH_PARAM-1:0] src =
                    hnf_rxreqflit[`CHIE_REQ_FLIT_SRCID_RANGE];
                automatic logic [`CHIE_REQ_FLIT_TXNID_WIDTH-1:0] tid =
                    hnf_rxreqflit[`CHIE_REQ_FLIT_TXNID_RANGE];
                automatic logic [CHIE_REQ_ADDR_WIDTH_PARAM-1:0] addr =
                    hnf_rxreqflit[`CHIE_REQ_FLIT_ADDR_RANGE];
                automatic bit[KEY_W-1:0] key = {src, tid};

                if (scoreboard.exists(key)) begin
                    if (scoreboard[key].state == REQ_RCVD_ICN)
                        scoreboard[key].state = REQ_RCVD_HNF;

                    // Safety assertion: byte-accurate address must match what the RNF sent.
                    if (addr !== scoreboard[key].acc_addr) begin
                        $error("[CHI_MON][HNF] ADDR MISMATCH t=%t {Src:%0h TxnID:0x%h Tgt:%0h}: RNF sent AccAddr:%0h LineAddr:%0h, HNF sees %0h",
                            $realtime, src, tid, scoreboard[key].tgt_id, scoreboard[key].acc_addr, scoreboard[key].addr, addr);
                    end
                end
            end

            // ------------------------------------------------------------------
            // HNF sends snoop to RNF — populate snp_scoreboard
            // ------------------------------------------------------------------
            if (hnf_txsnpflitv) begin
                automatic logic [CHIE_NID_WIDTH_PARAM-1:0] src =
                    hnf_txsnpflit[`CHIE_SNP_FLIT_SRCID_RANGE];
                automatic logic [`CHIE_SNP_FLIT_TXNID_WIDTH-1:0] tid =
                    hnf_txsnpflit[`CHIE_SNP_FLIT_TXNID_RANGE];
                automatic logic [`CHIE_SNP_FLIT_OPCODE_WIDTH-1:0] sop =
                    hnf_txsnpflit[`CHIE_SNP_FLIT_OPCODE_RANGE];
                automatic logic [CHIE_NID_WIDTH_PARAM-1:0] tgt =
                    hnf_txsnpflit[`CHIE_SNP_FLIT_TGTID_RANGE];
                // SNP addr field carries addr[43:3]; reconstruct full cache-line address.
                automatic logic [CHIE_REQ_ADDR_WIDTH_PARAM-1:0] addr =
                    {hnf_txsnpflit[`CHIE_SNP_FLIT_ADDR_RANGE], 3'b000};
                // FWDNID/FWDTXNID: only meaningful for *Fwd snoop opcodes.
                // The snooped node sends CompData to FWDNID with TxnID=FWDTXNID.
                automatic logic [CHIE_NID_WIDTH_PARAM-1:0] fwd_nid =
                    hnf_txsnpflit[`CHIE_SNP_FLIT_FWDNID_RANGE];
                automatic logic [`CHIE_SNP_FLIT_FWDTXNID_WIDTH-1:0] fwd_tid =
                    hnf_txsnpflit[`CHIE_SNP_FLIT_FWDTXNID_RANGE];
                // TXNID identifies the HNF MSHR entry; same TXNID is used for all targets
                // in a broadcast (non-forwarding) snoop. Key = {HNF_SrcID, SnpTxnID}.
                // Key on TXNID only (see block 4b comment) — HN-F SRCID
                // is not reliably the same value the RN-F stamps as TGTID
                // on the response, so we drop it from the key.
                automatic bit[KEY_W-1:0] snp_key = {'0, tid};
                automatic logic tgt_bit_set =
                    (snp_scoreboard.exists(snp_key) && tgt < CORE_COUNT) ?
                    snp_scoreboard[snp_key].tgt_mask[tgt] : 1'b0;

                if (snp_scoreboard.exists(snp_key)) begin
                    // CHI: same TXNID broadcast to multiple sharers — each target adds
                    // one expected response. True collision = same target snooped twice.
                    if (tgt_bit_set) begin
                        $display("[CHI_MON][HNF] SNP COLLISION (dup tgt) t=%t {HNF:%0h SnpTid:0x%h} Op:%0h Tgt:%0h Addr:%0h",
                            $realtime, src, tid, sop, tgt, addr);
                    end else begin
                        if (tgt < CORE_COUNT)
                            snp_scoreboard[snp_key].tgt_mask[tgt] = 1'b1;
                        snp_scoreboard[snp_key].exp_rsp_cnt++;
                        if (verbosity_level >= VERB_TRACE)
                            $display("[CHI_MON][HNF] SNP+  t=%t {HNF:%0h SnpTid:0x%h} Op:%0h Tgt:%0h Addr:%0h exp_rsp=%0d",
                                $realtime, src, tid, sop, tgt, addr,
                                snp_scoreboard[snp_key].exp_rsp_cnt);
                    end
                end else begin
                    snp_scoreboard[snp_key].src_id      = src;
                    snp_scoreboard[snp_key].txn_id      = tid;
                    snp_scoreboard[snp_key].addr        = addr;
                    snp_scoreboard[snp_key].opcode      = sop;
                    snp_scoreboard[snp_key].tgt_mask    = '0;
                    if (tgt < CORE_COUNT)
                        snp_scoreboard[snp_key].tgt_mask[tgt] = 1'b1;
                    snp_scoreboard[snp_key].fwd_nid     = fwd_nid;
                    snp_scoreboard[snp_key].fwd_txn_id  = fwd_tid;
                    snp_scoreboard[snp_key].rsp_cnt     = 0;
                    snp_scoreboard[snp_key].exp_rsp_cnt = 1;
                    snp_scoreboard[snp_key].start_time  = $realtime;
                    // Log FwdNid/FwdTxnId only for forwarding snoops (non-zero FwdNid).
                    if (verbosity_level >= VERB_TRACE) begin
                        if (fwd_nid != '0)
                            $display("[CHI_MON][HNF] SNP   t=%t {HNF:%0h SnpTid:0x%h} Op:%0h Tgt:%0h Addr:%0h FwdNid:%0h FwdTxnID:0x%h",
                                $realtime, src, tid, sop, tgt, addr, fwd_nid, fwd_tid);
                        else
                            $display("[CHI_MON][HNF] SNP   t=%t {HNF:%0h SnpTid:0x%h} Op:%0h Tgt:%0h Addr:%0h",
                                $realtime, src, tid, sop, tgt, addr);
                    end
                end
            end

            // ------------------------------------------------------------------
            // HNF receives write data from RNF (CopyBackWrData / NCBWrData)
            // tid here is the DBID value the HNF assigned in CompDBIDResp.
            // ------------------------------------------------------------------
            if (hnf_rxdatflitv) begin
                automatic logic [CHIE_NID_WIDTH_PARAM-1:0] src =
                    hnf_rxdatflit[`CHIE_DAT_FLIT_SRCID_RANGE];
                automatic logic [`CHIE_REQ_FLIT_TXNID_WIDTH-1:0] tid =
                    hnf_rxdatflit[`CHIE_DAT_FLIT_TXNID_RANGE];
                automatic logic [`CHIE_DAT_FLIT_OPCODE_WIDTH-1:0] dop =
                    hnf_rxdatflit[`CHIE_DAT_FLIT_OPCODE_RANGE];
                automatic bit[KEY_W-1:0] dbid_key = {src, tid};

                if (dop == `CHIE_COPYBACKWRDATA || dop == `CHIE_NONCOPYBACKWRDATA ||
                    dop == `CHIE_NCBWRDATACOMPACK) begin
                    // WrData TxnID = DBID assigned by HNF → look up txn_wrpend[{src, dbid}]
                    // WriteCleanFull: no Comp is sent back to the RN-F; WrData arriving
                    // at the HNF is the final event — retire the entry here.
                    if (txn_wrpend.exists(dbid_key)) begin
                        if (verbosity_level >= VERB_DONE)
                            $display("[CHI_MON][HNF] DONE  t=%t {Src:%0h DBID:0x%h Tgt:%0h} Op:%0h LineAddr:%0h AccAddr:%0h (WrData op=%0h)",
                                $realtime, src, tid, txn_wrpend[dbid_key].tgt_id,
                                txn_wrpend[dbid_key].opcode, txn_wrpend[dbid_key].addr, txn_wrpend[dbid_key].acc_addr, dop);
                        txn_wrpend[dbid_key].state = WRDAT_RCVD_HNF;
                        txn_wrpend.delete(dbid_key);
                    end
                end
            end

            // ------------------------------------------------------------------
            // SNF receives request from HNF
            // ------------------------------------------------------------------
            if (snf_rxreqflitv) begin
                automatic logic [CHIE_NID_WIDTH_PARAM-1:0] src =
                    snf_rxreqflit[`CHIE_REQ_FLIT_SRCID_RANGE];
                automatic logic [`CHIE_REQ_FLIT_TXNID_WIDTH-1:0] tid =
                    snf_rxreqflit[`CHIE_REQ_FLIT_TXNID_RANGE];
                automatic bit[KEY_W-1:0] key = {src, tid};
                if (scoreboard.exists(key) && scoreboard[key].state == REQ_RCVD_HNF)
                    scoreboard[key].state = REQ_SENT_SNF;
            end

            // ------------------------------------------------------------------
            // SNF sends data to HNF
            // ------------------------------------------------------------------
            if (snf_txdatflitv) begin
                automatic logic [CHIE_NID_WIDTH_PARAM-1:0] src =
                    snf_txdatflit[`CHIE_DAT_FLIT_SRCID_RANGE];
                automatic logic [`CHIE_REQ_FLIT_TXNID_WIDTH-1:0] tid =
                    snf_txdatflit[`CHIE_DAT_FLIT_TXNID_RANGE];
                automatic bit[KEY_W-1:0] key = {src, tid};
                if (scoreboard.exists(key))
                    scoreboard[key].state = DATA_FROM_SNF;
            end
        end
    endtask

    // =========================================================================
    // Deadlock checker — prints stale entries once, then stops the simulation.
    // deadlock_ns: age threshold; period_ns: polling interval.
    // =========================================================================
    task automatic check_deadlocks(time deadlock_ns, time period_ns);
        int n;
        forever begin
            #(period_ns);
            n = 0;

            foreach (scoreboard[key]) begin
                if ($realtime - scoreboard[key].start_time > deadlock_ns) begin
                    $display("[CHI_MON] DEADLOCK t=%t IssuedAt=%t {Src:%0h TxnID:0x%h Tgt:%0h} State:%-14s Op:%0h LineAddr:%0h AccAddr:%0h Age:%0t",
                        $realtime,
                        scoreboard[key].start_time,
                        scoreboard[key].src_id, scoreboard[key].txn_id, scoreboard[key].tgt_id,
                        scoreboard[key].state.name(),
                        scoreboard[key].opcode, scoreboard[key].addr, scoreboard[key].acc_addr,
                        $realtime - scoreboard[key].start_time);
                    n++;
                end
            end

            foreach (txn_wrpend[key]) begin
                if ($realtime - txn_wrpend[key].start_time > deadlock_ns) begin
                    $display("[CHI_MON] WRDAT DEADLOCK t=%t IssuedAt=%t {Src:%0h DBID:0x%h Tgt:%0h} Op:%0h LineAddr:%0h AccAddr:%0h Age:%0t",
                        $realtime,
                        txn_wrpend[key].start_time,
                        key[KEY_W-1:`CHIE_REQ_FLIT_TXNID_WIDTH],
                        key[`CHIE_REQ_FLIT_TXNID_WIDTH-1:0],
                        txn_wrpend[key].tgt_id,
                        txn_wrpend[key].opcode, txn_wrpend[key].addr, txn_wrpend[key].acc_addr,
                        $realtime - txn_wrpend[key].start_time);
                    n++;
                end
            end

            foreach (snp_scoreboard[key]) begin
                if ($realtime - snp_scoreboard[key].start_time > deadlock_ns) begin
                    $display("[CHI_MON] SNP DEADLOCK t=%t IssuedAt=%t {HNF:%0h SnpTid:0x%h TgtMask:%0b} Op:%0h Addr:%0h rsp=%0d/%0d Age:%0t",
                        $realtime,
                        snp_scoreboard[key].start_time,
                        snp_scoreboard[key].src_id, snp_scoreboard[key].txn_id,
                        snp_scoreboard[key].tgt_mask,
                        snp_scoreboard[key].opcode,
                        snp_scoreboard[key].addr,
                        snp_scoreboard[key].rsp_cnt, snp_scoreboard[key].exp_rsp_cnt,
                        $realtime - snp_scoreboard[key].start_time);
                    n++;
                end
            end

            if (n > 0)
                $error(0, "[CHI_MON] %0d deadlock(s) detected at t=%0t — stopping simulation.", n, $realtime);
        end
    endtask

    // =========================================================================
    // Spawn monitors: one per RNF core + one shared HNF monitor + deadlock check.
    // =========================================================================
    initial begin
        $timeformat(-9, 3, " ns", 15);

        // One task per RNF core (captures ci by value via automatic).
        for (int c = 0; c < CORE_COUNT; c++) begin
            automatic int ci = c;
            fork
                monitor_rnf_transaction(ci);
            join_none
        end

        fork
            monitor_hnf();
            check_deadlocks(100000ns, 10000ns);
        join_none
    end

endmodule
