/*
 * Copyright (c) 2026 Customized Parallel Computing (CPC) Group, Tampere University
 * Author: Abdesattar Kalache <abdesattar.kalache@tuni.fi>
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
 */
/*
 * chi_hnf_responder.sv
 *
 * Abstract CHI-E HN-F counterparty for IP-level RN-F testing.
 *
 * Replaces the full HN-F RTL + chi_icn_beh combo with a programmable
 * responder that:
 *   * Issues unlimited TX*LCRDV credits to the DUT.
 *   * Watches DUT TXREQFLITV / TXRSPFLITV / TXDATFLITV traffic.
 *   * For each captured REQ, queues one of several CHI-legal response
 *     paths driven by a public API (set_next_response* below).
 *   * Can inject snoops on demand via inject_snoop(...).
 *
 * It is **not** a faithful HN-F.  It models only what the RN-F's link
 * layer needs to see to make forward progress.  Faithful HN-F coherence
 * is the gem5 SLICC env's job in the production co-sim flow; this
 * responder exists so we can drive Murphi-derived vectors through the
 * L1.5+rnf_link at Questa speed.
 *
 * Usage from the parent TB:
 *
 *   chi_hnf_responder #(.RNF_NID(0), .HNF_NID(2)) u_hnf (
 *       .clk, .rst_n, ... CHI signals ...
 *   );
 *   ...
 *   u_hnf.set_next_response_compdata_clean();   // before do_load()
 *   u_hnf.inject_snoop_clean(addr);             // any time
 */

`include "rnf_param.v"
`include "rnf_defines.v"
`include "chie_defines.v"

module chi_hnf_responder `RNF_PARAM (
    input  logic clk,
    input  logic rst_n,

    // ── TX side from DUT ────────────────────────────────────────────
    input  logic                          TXREQFLITV,
    input  logic [`CHIE_REQ_FLIT_RANGE]   TXREQFLIT,
    input  logic                          TXREQFLITPEND,
    input  logic                          TXRSPFLITV,
    input  logic [`CHIE_RSP_FLIT_RANGE]   TXRSPFLIT,
    input  logic                          TXRSPFLITPEND,
    input  logic                          TXDATFLITV,
    input  logic [`CHIE_DAT_FLIT_RANGE]   TXDATFLIT,
    input  logic                          TXDATFLITPEND,

    // Credits we issue to DUT
    output logic                          TXREQLCRDV,
    output logic                          TXRSPLCRDV,
    output logic                          TXDATLCRDV,

    // ── RX side to DUT ──────────────────────────────────────────────
    output logic                          RXRSPFLITV,
    output logic [`CHIE_RSP_FLIT_RANGE]   RXRSPFLIT,
    output logic                          RXRSPFLITPEND,
    output logic                          RXDATFLITV,
    output logic [`CHIE_DAT_FLIT_RANGE]   RXDATFLIT,
    output logic                          RXDATFLITPEND,
    output logic                          RXSNPFLITV,
    output logic [`CHIE_SNP_FLIT_RANGE]   RXSNPFLIT,
    output logic                          RXSNPFLITPEND,

    // Credits coming back from DUT (DUT's "RX*LCRDV" -- ignored, we
    // assume the DUT eventually grants them; we just wait on the
    // FLITV-as-handshake convention used by rnf_link).
    input  logic                          RXRSPLCRDV,
    input  logic                          RXDATLCRDV,
    input  logic                          RXSNPLCRDV,

    // Link-active handshake (simple loopback: ack what DUT requests)
    input  logic                          TXLINKACTIVEREQ,
    output logic                          TXLINKACTIVEACK,
    output logic                          RXLINKACTIVEREQ,
    input  logic                          RXLINKACTIVEACK,
    input  logic                          TXACTIVE,
    output logic                          RXACTIVE
);

    // ── Credits + link-active are always-on for IP-level smoke testing ─
    // The DUT's rnf_link is heavily credit-paced; flooding it with
    // credits each cycle avoids stalls unrelated to the test scenario.
    assign TXREQLCRDV     = 1'b1;
    assign TXRSPLCRDV     = 1'b1;

    // ── TXDAT credit hold ──────────────────────────────────────────
    // TX_AWAIT_DATA_SEND runs from the DBIDResp arriving to the RN-F's
    // WriteData leaving -- a couple of cycles, so a snoop injected on
    // entry to the phase loses the race and only
    // (await_datasend, SnpClean, WriteBackFull) ever landed; the other
    // four snoop opcodes never did.  Withholding TXDAT link credit is
    // ordinary link-layer backpressure and holds the phase open long
    // enough for the snoop to arrive inside it.
    //
    // Keep the hold well under SNP_MON's 500-cycle timeout: it also
    // blocks SnpRespData, so an over-long hold would starve the very
    // snoop response the race is meant to produce.
    int unsigned datasend_hold;
    int unsigned txdat_hold_cnt;
    initial      datasend_hold = 0;

    task automatic set_datasend_hold(input int unsigned n);
        datasend_hold = n;
    endtask

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)                    txdat_hold_cnt <= 0;
        else if (RXRSPFLITV &&
                 (RXRSPFLIT[`CHIE_RSP_FLIT_OPCODE_RANGE] == `CHIE_DBIDRESP ||
                  RXRSPFLIT[`CHIE_RSP_FLIT_OPCODE_RANGE] == `CHIE_COMPDBIDRESP))
                                       txdat_hold_cnt <= datasend_hold;
        else if (txdat_hold_cnt != 0)  txdat_hold_cnt <= txdat_hold_cnt - 1;
    end

    assign TXDATLCRDV     = (txdat_hold_cnt == 0);
    assign TXLINKACTIVEACK = TXLINKACTIVEREQ;
    assign RXLINKACTIVEREQ = TXLINKACTIVEREQ;   // mirror DUT
    assign RXACTIVE        = TXACTIVE;          // mirror DUT

    // ── Response programming API (testbench writes these) ──────────
    // The testbench picks the response shape *before* issuing the
    // memory op that produces the REQ.  When the DUT's TXREQ fires,
    // this responder consumes the directive and emits the chosen
    // response flit(s) automatically.
    typedef enum logic [3:0] {
        RESP_NONE,
        RESP_COMPDATA_UC,            // CompData_UC      (clean unique)
        RESP_COMPDATA_UD_PD,         // CompData_UD_PD   (dirty unique, pass-dirty)
        RESP_COMPDATA_SC,            // CompData_SC      (clean shared)
        RESP_COMPDATA_SD_PD,         // CompData_SD_PD   (dirty shared, pass-dirty)
        RESP_COMP,                   // Comp             (dataless / atomic store)
        RESP_DBIDRESP_THEN_COMP,     // DBIDResp -> wait WriteData -> Comp
        RESP_DBIDRESP_THEN_COMPDATA, // DBIDResp -> wait WriteData -> CompData
        RESP_COMPDBIDRESP            // CompDBIDResp -> wait WriteData (combined)
                                      //   (AtomicLoad / AtomicSwap: return old value)
    } resp_kind_e;

    // ── Directive request / consume pattern ────────────────────────
    // Tasks set req_* + req_pulse; an always_ff below latches into
    // the FSM-visible next_resp / next_resp_data / have_directive
    // and clears have_directive on FSM completion (resp_done).  This
    // split avoids multi-driven errors that arise when a function
    // writes a var that an always_ff also writes.
    resp_kind_e               req_resp;
    logic [255:0]             req_resp_data;
    logic                     req_resp_pulse;

    resp_kind_e               next_resp;
    logic [255:0]             next_resp_data;
    logic                     have_directive;

    initial begin
        req_resp_pulse = 1'b0;
    end

    task automatic set_next_response_compdata_uc(input logic [255:0] data);
        req_resp       = RESP_COMPDATA_UC;
        req_resp_data  = data;
        req_resp_pulse = 1'b1;
        @(posedge clk);
        req_resp_pulse = 1'b0;
    endtask
    task automatic set_next_response_compdata_ud_pd(input logic [255:0] data);
        req_resp       = RESP_COMPDATA_UD_PD;
        req_resp_data  = data;
        req_resp_pulse = 1'b1;
        @(posedge clk);
        req_resp_pulse = 1'b0;
    endtask
    task automatic set_next_response_compdata_sc(input logic [255:0] data);
        req_resp       = RESP_COMPDATA_SC;
        req_resp_data  = data;
        req_resp_pulse = 1'b1;
        @(posedge clk);
        req_resp_pulse = 1'b0;
    endtask
    task automatic set_next_response_compdata_sd_pd(input logic [255:0] data);
        req_resp       = RESP_COMPDATA_SD_PD;
        req_resp_data  = data;
        req_resp_pulse = 1'b1;
        @(posedge clk);
        req_resp_pulse = 1'b0;
    endtask
    task automatic set_next_response_comp();
        req_resp       = RESP_COMP;
        req_resp_pulse = 1'b1;
        @(posedge clk);
        req_resp_pulse = 1'b0;
    endtask
    task automatic set_next_response_dbidresp_then_comp();
        req_resp       = RESP_DBIDRESP_THEN_COMP;
        req_resp_pulse = 1'b1;
        @(posedge clk);
        req_resp_pulse = 1'b0;
    endtask

    // Combined completion: one CompDBIDResp instead of the split
    // DBIDResp ... Comp pair.  rx_control.sv:1877 handles the opcode,
    // but nothing in this TB emitted it, so cp_phase_seq's
    // SEQ_WRITE_COMBINED bin and the whole WRITE_COMBINED column of
    // x_op_seq were unreachable for want of stimulus.
    task automatic set_next_response_compdbidresp();
        req_resp       = RESP_COMPDBIDRESP;
        req_resp_pulse = 1'b1;
        @(posedge clk);
        req_resp_pulse = 1'b0;
    endtask

    task automatic set_next_response_dbidresp_then_compdata(input logic [255:0] data);
        req_resp       = RESP_DBIDRESP_THEN_COMPDATA;
        req_resp_data  = data;
        req_resp_pulse = 1'b1;
        @(posedge clk);
        req_resp_pulse = 1'b0;
    endtask

    // ── Forward declaration: resp_done is computed in the response
    //    FSM below but consumed by the REQ-capture always_ff next.
    //    Some Questa MFCU paths reject forward net references; declare
    //    here so it's visible before its first use.
    logic resp_done;

    // ── Latch directive request + clear on FSM completion ─────────
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            next_resp      <= RESP_NONE;
            next_resp_data <= 256'h0;
            have_directive <= 1'b0;
        end
        else if (req_resp_pulse) begin
            next_resp      <= req_resp;
            next_resp_data <= req_resp_data;
            have_directive <= 1'b1;
        end
        else if (resp_done) begin
            have_directive <= 1'b0;
        end
    end

    // ── REQ capture ────────────────────────────────────────────────
    // When the DUT issues a REQ, latch its TXNID + opcode and kick off
    // the chosen response flow.
    logic [11:0]                captured_txnid;
    logic [6:0]                 captured_opcode;
    logic [39:0]                captured_line;
    logic                       have_req;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            captured_txnid  <= '0;
            captured_opcode <= '0;
            captured_line   <= '0;
            have_req        <= 1'b0;
        end
        else if (TXREQFLITV) begin
            captured_txnid  <= TXREQFLIT[`CHIE_REQ_FLIT_TXNID_RANGE];
            captured_opcode <= TXREQFLIT[`CHIE_REQ_FLIT_OPCODE_RANGE];
            captured_line   <= TXREQFLIT[`CHIE_REQ_FLIT_ADDR_RANGE] & ~40'h3F;
            have_req        <= 1'b1;
        end
        else if (resp_done) begin
            have_req        <= 1'b0;
        end
    end

    // ── Backing memory ─────────────────────────────────────────────
    // Without this the responder discarded every CopyBackWrData payload
    // and served CompData from `next_resp_data` (default 256'h0), so a
    // line that was written back and re-read came back as zeros.  The
    // TB's MEM_ORACLE models write-back memory, so it could not tell a
    // genuine lost store from a legitimate refill — every such case
    // showed up as a false "RN-F returned stale/wrong data".
    //
    // Policy:
    //   * absorb CopyBackWrData (the cacheable writeback path) only.
    //     NonCopyBackWrData carries atomic operands and NC-write data,
    //     which are not a plain line image -- absorbing those would put
    //     the operand, not the result, into memory.
    //   * serve CompData from memory once a line is known; on the first
    //     read of a line, seed it from the directive constant so the
    //     clean/dirty payloads the vectors program still appear.
    logic [511:0] mem       [logic [39:0]];
    logic         mem_valid [logic [39:0]];
    logic [39:0]  line_by_txnid [logic [11:0]];
    logic [6:0]   opc_by_txnid  [logic [11:0]];

    // Blocking assignments: Questa rejects non-blocking writes to
    // associative-array elements.  TB-only scoreboard state, not
    // synthesised, so intra-block ordering races do not matter.
    always @(posedge clk) if (rst_n && TXREQFLITV) begin : req_line_track
        line_by_txnid[TXREQFLIT[`CHIE_REQ_FLIT_TXNID_RANGE]] =
            TXREQFLIT[`CHIE_REQ_FLIT_ADDR_RANGE] & ~40'h3F;
        opc_by_txnid[TXREQFLIT[`CHIE_REQ_FLIT_TXNID_RANGE]] =
            TXREQFLIT[`CHIE_REQ_FLIT_OPCODE_RANGE];
    end

    // Line address of the snoop currently outstanding.  SnpRespData*
    // carries the dirty line back to the HN-F but is tagged with the
    // *snoop's* TXNID, so it cannot be looked up in line_by_txnid.
    // Single snoop in flight in this env (see inject_snoop below).
    // Sourced from the RXSNPFLIT output port rather than
    // pending_snp_flit, which is declared further down the file.
    logic [39:0] snp_line;
    always @(posedge clk) if (rst_n && RXSNPFLITV)
        snp_line = {RXSNPFLIT[`CHIE_SNP_FLIT_ADDR_RANGE], 3'b000} & ~40'h3F;

    always @(posedge clk) if (rst_n && TXDATFLITV) begin : wrdata_absorb
        automatic logic [3:0]   dop = TXDATFLIT[`CHIE_DAT_FLIT_OPCODE_RANGE];
        automatic logic [11:0]  dtid = TXDATFLIT[`CHIE_DAT_FLIT_TXNID_RANGE];
        automatic bit is_wb   = (dop == `CHIE_COPYBACKWRDATA);
        automatic bit is_snpd = (dop == `CHIE_SNPRESPDATA) ||
                                (dop == `CHIE_SNPRESPDATAPTL) ||
                                (dop == `CHIE_SNPRESPDATAFWDED);
        // NonCopyBackWrData carries both atomic operands and
        // writethrough (WriteUnique / WriteNoSnp) data.  Absorb it only
        // for the write opcodes -- an atomic's operand is not the
        // resulting line value, so storing it would corrupt memory.
        automatic bit is_ncbw = (dop == `CHIE_NONCOPYBACKWRDATA) &&
                                opc_by_txnid.exists(dtid) &&
                                (opc_by_txnid[dtid] == 7'h18 ||
                                 opc_by_txnid[dtid] == 7'h19 ||
                                 opc_by_txnid[dtid] == 7'h1c ||
                                 opc_by_txnid[dtid] == 7'h1d);
        if (((is_wb || is_ncbw) && line_by_txnid.exists(dtid)) || is_snpd) begin
            automatic logic [39:0]  line = is_snpd ? snp_line : line_by_txnid[dtid];
            automatic logic [1:0]   did  = TXDATFLIT[`CHIE_DAT_FLIT_DATAID_RANGE];
            automatic logic [255:0] pay  = TXDATFLIT[`CHIE_DAT_FLIT_DATA_RANGE];
            automatic logic [31:0]  be   = TXDATFLIT[`CHIE_DAT_FLIT_BE_RANGE];
            automatic int           base = (did == 2'b10) ? 32 : 0;
            if (!mem_valid.exists(line)) begin
                mem[line]       = 512'h0;
                mem_valid[line] = 1'b1;
            end
            for (int i = 0; i < 32; i++)
                if (be[i]) mem[line][8*(base + i) +: 8] = pay[8*i +: 8];
        end
    end

    // Returns the 32 B half selected by `dataid`, seeding the line from
    // `fallback` (the directive payload) if it has never been written.
    function automatic logic [255:0] fetch_line_half(
        input logic [39:0]  line,
        input logic [1:0]   dataid,
        input logic [255:0] fallback
    );
        automatic int base = (dataid == 2'b10) ? 32 : 0;
        if (!mem_valid.exists(line)) begin
            mem[line]       = {fallback, fallback};
            mem_valid[line] = 1'b1;
        end
        return mem[line][8*base +: 256];
    endfunction

    // ── Response state machine ─────────────────────────────────────
    typedef enum logic [3:0] {
        S_IDLE,
        S_SEND_COMPDATA,               // beat 0, DATAID=0
        S_SEND_COMPDATA_BEAT1,         // beat 1, DATAID=2
        S_SEND_COMP,
        S_SEND_DBIDRESP,
        S_SEND_COMPDBID,
        S_WAIT_WRITEDATA,
        S_SEND_COMP_AFTER_WRDATA,
        S_SEND_COMPDATA_AFTER_WRDATA,        // beat 0
        S_SEND_COMPDATA_AFTER_WRDATA_BEAT1   // beat 1
    } state_e;

    state_e state, state_n;
    assign resp_done = (state != S_IDLE) && (state_n == S_IDLE);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= S_IDLE;
        else        state <= state_n;
    end

    // ── RX-channel credit tracking ─────────────────────────────────
    // The new (post-2026-07 merge) DUT drains its initial credit pool
    // via explicit LCRDV pulses shortly after reset (~7 pulses per
    // channel).  Older RTL kept them implicit — we compensated with
    // `<= XP_LCRD_NUM_PARAM` at reset.  Doing that on the new RTL
    // double-counts (start=15 + 7 grants = 22) and we ship flits into
    // an over-committed buffer.  Start at 0 and rely on LCRDV.
    int unsigned rxrsp_credit, rxdat_credit, rxsnp_credit;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rxrsp_credit <= 0;
            rxdat_credit <= 0;
            rxsnp_credit <= 0;
        end else begin
            rxrsp_credit <= rxrsp_credit
                          + (RXRSPLCRDV ? 1 : 0)
                          - (RXRSPFLITV ? 1 : 0);
            rxdat_credit <= rxdat_credit
                          + (RXDATLCRDV ? 1 : 0)
                          - (RXDATFLITV ? 1 : 0);
            rxsnp_credit <= rxsnp_credit
                          + (RXSNPLCRDV ? 1 : 0)
                          - (RXSNPFLITV ? 1 : 0);
        end
    end
    // ── Programmable response delay ────────────────────────────────
    // With a zero-delay responder every transaction completes within a
    // few cycles of its TXREQ, so TX_AWAIT_RSP never lasts long enough
    // for an injected snoop to land in it, and fast ops (ReadClean,
    // AtomicLoad) are never outstanding when a snoop arrives.  That left
    // cp_tx_phase_when_snoop.await_rsp, cp_tx_op_during_snoop.ReadClean
    // and .AtomicLoad at zero hits, which in turn blocked 60 of the 87
    // missing x_race cells.
    //
    // CHI places no upper bound on completer latency, so holding the
    // response is legal stimulus rather than a coverage trick.  Keep the
    // value well under the 500-cycle SNP_MON timeout: the point is to
    // overlap a snoop with an outstanding transaction, not to stall the
    // link.
    int unsigned resp_delay;      // cycles to hold before driving a flit
    int unsigned delay_cnt;
    initial      resp_delay = 0;

    task automatic set_response_delay(input int unsigned n);
        resp_delay = n;
    endtask

    // The delay is CONSTANT on purpose.  Two ways of varying it were
    // measured and both were worse:
    //   * TB look-ahead, delaying only transactions a snoop was about to
    //     race: 245 bins, 32 failures.
    //   * per-REQ alternation inside this module:                245 bins, 31 failures.
    //   * constant delay:                                        251 bins,  1 failure.
    // Variable latency, not latency itself, is what breaks the run --
    // both variants produced ~30 MEM_ORACLE failures that the constant
    // delay does not.  Known cost of the constant window: it puts a
    // snoop inside essentially every transaction, so
    // cp_snoop_seen_during loses its "no snoop" arm and x_op_seq drops
    // from 19 bins to 12.  Net is still +17 bins.  Recovering those 7
    // wants a second sweep pass with +NO_RACE_WINDOW and a UCDB merge,
    // not a variable delay.
    //
    // Reload on every state change so each send state (and each CompData
    // beat) serves its own delay; count down otherwise.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)                 delay_cnt <= 0;
        else if (state != state_n)  delay_cnt <= resp_delay;
        else if (delay_cnt != 0)    delay_cnt <= delay_cnt - 1;
    end
    wire delay_done = (delay_cnt == 0);

    // Gate BOTH the FSM transition and the flit drive.  Gating only the
    // transition would leave the always_ff below driving FLITV every
    // cycle it sat in a send state with credit, emitting duplicate flits.
    wire have_rsp_credit = (rxrsp_credit != 0) && delay_done;
    wire have_dat_credit = (rxdat_credit != 0) && delay_done;
    wire have_snp_credit = (rxsnp_credit != 0);

    always_comb begin
        state_n = state;
        unique case (state)
            S_IDLE: begin
                if (have_req && have_directive) begin
                    unique case (next_resp)
                        RESP_COMPDATA_UC,
                        RESP_COMPDATA_UD_PD,
                        RESP_COMPDATA_SC,
                        RESP_COMPDATA_SD_PD: state_n = S_SEND_COMPDATA;
                        RESP_COMP:           state_n = S_SEND_COMP;
                        RESP_DBIDRESP_THEN_COMP,
                        RESP_DBIDRESP_THEN_COMPDATA: state_n = S_SEND_DBIDRESP;
                        RESP_COMPDBIDRESP:           state_n = S_SEND_COMPDBID;
                        default:             state_n = S_IDLE;
                    endcase
                end
            end
            // Stay in send states until credit is available so the flit
            // we drive in the always_ff below is guaranteed to be
            // accepted by the DUT.
            S_SEND_COMPDATA:       if (have_dat_credit) state_n = S_SEND_COMPDATA_BEAT1;
            S_SEND_COMPDATA_BEAT1: if (have_dat_credit) state_n = S_IDLE;
            S_SEND_COMP:     if (have_rsp_credit) state_n = S_IDLE;
            S_SEND_DBIDRESP: if (have_rsp_credit) state_n = S_WAIT_WRITEDATA;
            S_SEND_COMPDBID: if (have_rsp_credit) state_n = S_WAIT_WRITEDATA;
            S_WAIT_WRITEDATA: if (TXDATFLITV) begin
                // CompDBIDResp already carried the completion, so the
                // transaction ends with the WriteData -- no trailing Comp.
                state_n = (next_resp == RESP_COMPDBIDRESP)
                          ? S_IDLE
                          : (next_resp == RESP_DBIDRESP_THEN_COMPDATA)
                            ? S_SEND_COMPDATA_AFTER_WRDATA
                            : S_SEND_COMP_AFTER_WRDATA;
            end
            S_SEND_COMP_AFTER_WRDATA:     if (have_rsp_credit) state_n = S_IDLE;
            S_SEND_COMPDATA_AFTER_WRDATA:       if (have_dat_credit)
                                                    state_n = S_SEND_COMPDATA_AFTER_WRDATA_BEAT1;
            S_SEND_COMPDATA_AFTER_WRDATA_BEAT1: if (have_dat_credit) state_n = S_IDLE;
            default:                             state_n = S_IDLE;
        endcase
    end

    // ── Drive RX channels based on state ───────────────────────────
    // Note: CHI E.b RSP opcodes (5-bit field in flit):
    //   Comp                = 5'h04
    //   CompDBIDResp        = 5'h05  (we model split as DBIDResp + Comp)
    //   DBIDResp            = 5'h03
    //   CompAck             = 5'h0E  (RN-F -> HN-F, not us)
    //
    // CHI E.b DAT opcodes (4-bit field):
    //   CompData            = 4'h4
    //   CopyBackWrData      = 4'h2  (RN-F -> HN-F, not us)
    //   NonCopyBackWrData   = 4'h3  (RN-F -> HN-F, not us)
    //
    // Resp (state) field inside CompData carries the post-state for
    // the requester (UC/UD/SC/SD via 3-bit Resp + PassDirty bit).
    logic [`CHIE_RSP_FLIT_RANGE]  rsp_flit;
    logic [`CHIE_DAT_FLIT_RANGE]  dat_flit;
    logic [`CHIE_SNP_FLIT_RANGE]  snp_flit;

    // Build RSP flit: { ..., TGTID=DUT_NID=0, SRCID=HNF_NID, TXNID=captured, OPCODE=Comp }
    // For DBIDResp/CompDBIDResp the DBID field must be populated — the
    // RN-F uses it as the TXNID on its subsequent WriteData beat.
    function automatic logic [`CHIE_RSP_FLIT_RANGE] build_comp(
        input logic [11:0] txnid,
        input logic [4:0]  opcode,
        input logic [2:0]  resp_state
    );
        logic [`CHIE_RSP_FLIT_RANGE] f;
        f                                         = '0;
        f[`CHIE_RSP_FLIT_TGTID_RANGE]            = RNF_NID[CHIE_NID_WIDTH_PARAM-1:0];
        f[`CHIE_RSP_FLIT_SRCID_RANGE]            = HNF_NID_PARAM[CHIE_NID_WIDTH_PARAM-1:0];
        f[`CHIE_RSP_FLIT_TXNID_RANGE]            = txnid;
        f[`CHIE_RSP_FLIT_OPCODE_RANGE]           = opcode;
        f[`CHIE_RSP_FLIT_RESP_RANGE]             = resp_state;
        // Echo TXNID into DBID for write-data flows.  Harmless when
        // unused by non-write responses.
        f[`CHIE_RSP_FLIT_DBID_RANGE]             = txnid;
        return f;
    endfunction

    // Build DAT flit for CompData.  Post-merge L1.5 (rx_control.sv:1949)
    // requires `is_last_beat = &line_be` before it will assert
    // `data_rdy_r` and let CompAck fire.  With CHIE_DATA_WIDTH=256 each
    // beat covers 32 bytes of a 64-byte line, so we must send TWO
    // CompData flits — DATAID=0 for beat 0 and DATAID=2 for beat 1.
    // `dataid` selects which half.
    function automatic logic [`CHIE_DAT_FLIT_RANGE] build_compdata(
        input logic [11:0]  txnid,
        input logic [2:0]   resp_state,
        input logic         pass_dirty,
        input logic [255:0] data,
        input logic [1:0]   dataid
    );
        logic [`CHIE_DAT_FLIT_RANGE] f;
        f                                       = '0;
        f[`CHIE_DAT_FLIT_TGTID_RANGE]          = RNF_NID[CHIE_NID_WIDTH_PARAM-1:0];
        f[`CHIE_DAT_FLIT_SRCID_RANGE]          = HNF_NID_PARAM[CHIE_NID_WIDTH_PARAM-1:0];
        f[`CHIE_DAT_FLIT_HOMENID_RANGE]        = HNF_NID_PARAM[CHIE_NID_WIDTH_PARAM-1:0];
        f[`CHIE_DAT_FLIT_TXNID_RANGE]          = txnid;
        f[`CHIE_DAT_FLIT_DBID_RANGE]           = txnid;
        f[`CHIE_DAT_FLIT_OPCODE_RANGE]         = `CHIE_COMPDATA;
        f[`CHIE_DAT_FLIT_RESP_RANGE]           = resp_state;
        f[`CHIE_DAT_FLIT_DATAID_RANGE]         = dataid;
        f[`CHIE_DAT_FLIT_DATA_RANGE]           = data;
        return f;
    endfunction

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            RXRSPFLITV    <= 1'b0;
            RXRSPFLIT     <= '0;
            RXRSPFLITPEND <= 1'b0;
            RXDATFLITV    <= 1'b0;
            RXDATFLIT     <= '0;
            RXDATFLITPEND <= 1'b0;
        end
        else begin
            // Defaults each cycle
            RXRSPFLITV    <= 1'b0;
            RXDATFLITV    <= 1'b0;
            RXRSPFLITPEND <= 1'b0;
            RXDATFLITPEND <= 1'b0;

            // Drive FLITV only when we're transitioning out of the
            // send state — i.e. we have credit and the flit will be
            // accepted.  Without this guard, a no-credit cycle silently
            // drops the flit.
            unique case (state)
                S_SEND_COMPDATA,
                S_SEND_COMPDATA_BEAT1: if (have_dat_credit) begin
                    // CHIE_COMP_RESP_* encoding (chie_defines.v:900-904):
                    //   {PD, state[1:0]}; UC=010, UD_PD=110, SC=001, SD_PD=111
                    logic [2:0] resp_state;
                    logic       pass_dirty;
                    logic [1:0] dataid;
                    unique case (next_resp)
                        RESP_COMPDATA_UC:    begin resp_state = 3'b010; pass_dirty = 1'b0; end
                        RESP_COMPDATA_UD_PD: begin resp_state = 3'b110; pass_dirty = 1'b1; end
                        RESP_COMPDATA_SC:    begin resp_state = 3'b001; pass_dirty = 1'b0; end
                        RESP_COMPDATA_SD_PD: begin resp_state = 3'b111; pass_dirty = 1'b1; end
                        default:             begin resp_state = 3'b010; pass_dirty = 1'b0; end
                    endcase
                    dataid = (state == S_SEND_COMPDATA) ? 2'b00 : 2'b10;
                    RXDATFLITV <= 1'b1;
                    RXDATFLIT  <= build_compdata(captured_txnid, resp_state, pass_dirty,
                                                 fetch_line_half(captured_line, dataid,
                                                                 next_resp_data),
                                                 dataid);
                end
                S_SEND_COMP: if (have_rsp_credit) begin
                    RXRSPFLITV <= 1'b1;
                    RXRSPFLIT  <= build_comp(captured_txnid, `CHIE_COMP, 3'b000);
                end
                S_SEND_DBIDRESP: if (have_rsp_credit) begin
                    RXRSPFLITV <= 1'b1;
                    RXRSPFLIT  <= build_comp(captured_txnid, `CHIE_DBIDRESP, 3'b000);
                end
                S_SEND_COMPDBID: if (have_rsp_credit) begin
                    RXRSPFLITV <= 1'b1;
                    RXRSPFLIT  <= build_comp(captured_txnid, `CHIE_COMPDBIDRESP, 3'b000);
                end
                S_SEND_COMP_AFTER_WRDATA: if (have_rsp_credit) begin
                    RXRSPFLITV <= 1'b1;
                    RXRSPFLIT  <= build_comp(captured_txnid, `CHIE_COMP, 3'b000);
                end
                S_SEND_COMPDATA_AFTER_WRDATA,
                S_SEND_COMPDATA_AFTER_WRDATA_BEAT1: if (have_dat_credit) begin
                    // AtomicLoad / AtomicSwap: return old value on DAT.
                    logic [1:0] dataid;
                    dataid = (state == S_SEND_COMPDATA_AFTER_WRDATA) ? 2'b00 : 2'b10;
                    RXDATFLITV <= 1'b1;
                    RXDATFLIT  <= build_compdata(captured_txnid, 3'b010, 1'b0,
                                                 next_resp_data, dataid);
                end
                default: ;
            endcase
        end
    end

    // ── Snoop injection API ────────────────────────────────────────
    // The testbench calls inject_snoop_*(addr) to put a snoop on the
    // RXSNP channel.  Single-slot: the new snoop waits if one is
    // already pending (we expect the DUT's snoop handler to be quick).
    logic        snp_pending;
    logic [`CHIE_SNP_FLIT_RANGE] pending_snp_flit;
    // Inject pulse + flit, set by inject_snoop_* tasks below; consumed
    // by the always_ff that updates snp_pending.  Declared up here so
    // forward references in tasks resolve.
    logic        snp_inject;
    logic [`CHIE_SNP_FLIT_RANGE] snp_inject_flit;

    // No initial block for these vars -- Questa flags 'multiply driven'
    // when an initial sets a var that an always_ff later writes.
    // pending_snp_flit is reset inside the always_ff; snp_inject and
    // snp_inject_flit are pure task-set scratch (default X is fine
    // because the always_ff guards on snp_inject == 1).

    function automatic logic [`CHIE_SNP_FLIT_RANGE] build_snp(
        input logic [4:0]  opcode,
        input logic [11:0] txnid,
        input logic [CHIE_SNP_ADDR_WIDTH_PARAM-1:0] addr,
        input logic        rettosrc
    );
        logic [`CHIE_SNP_FLIT_RANGE] f;
        f                                         = '0;
        f[`CHIE_SNP_FLIT_SRCID_RANGE]            = HNF_NID_PARAM[CHIE_NID_WIDTH_PARAM-1:0];
        f[`CHIE_SNP_FLIT_TXNID_RANGE]            = txnid;
        f[`CHIE_SNP_FLIT_OPCODE_RANGE]           = opcode;
        f[`CHIE_SNP_FLIT_ADDR_RANGE]             = {3'd0, addr[CHIE_SNP_ADDR_WIDTH_PARAM-1:3]};
        // RetToSrc=1 asks the snoopee to return data even when the line
        // is clean, producing SnpRespData_I / SnpRespData_SC (no
        // PassDirty).  Without it the RN-F only sends data when dirty,
        // so the SR_I_D / SR_SC_D response variants never occur.
        f[`CHIE_SNP_FLIT_RETTOSRC_RANGE]         = rettosrc;
        return f;
    endfunction

    // Public snoop-injection tasks.  Opcodes per chie_defines.v:
    //   CHIE_SNPSHARED        = 5'h01
    //   CHIE_SNPCLEAN         = 5'h02
    //   CHIE_SNPUNIQUE        = 5'h07
    //   CHIE_SNPCLEANINVALID  = 5'h09
    //   CHIE_SNPMAKEINVALID   = 5'h0a
    // The previous values (5'h05/08/0F/04) were CHI-spec numbers from
    // memory; this codebase uses its own encoding (see chie_defines.v
    // lines 578-593).  Using wrong opcodes made the L1.5 silently
    // ignore every snoop — no SnpResp ever came back.
    task automatic try_inject_snoop(input logic [4:0]  opcode,
                                    input logic [11:0] txnid,
                                    input logic [CHIE_SNP_ADDR_WIDTH_PARAM-1:0] addr,
                                    input logic        rettosrc = 1'b0);
        int wait_cycles;
        wait_cycles = 0;
        while (snp_pending && wait_cycles < 200) begin
            @(posedge clk);
            wait_cycles++;
        end
        if (snp_pending) return;       // slot still busy; drop this snoop
        snp_inject_flit = build_snp(opcode, txnid, addr, rettosrc);
        snp_inject      = 1'b1;
        @(posedge clk);
        snp_inject      = 1'b0;
    endtask

    task automatic inject_snoop_clean       (input logic [CHIE_SNP_ADDR_WIDTH_PARAM-1:0] addr,
                                             input logic rts = 1'b0);
        try_inject_snoop(`CHIE_SNPCLEAN, 12'h1, addr, rts);
    endtask
    task automatic inject_snoop_unique      (input logic [CHIE_SNP_ADDR_WIDTH_PARAM-1:0] addr,
                                             input logic rts = 1'b0);
        try_inject_snoop(`CHIE_SNPUNIQUE, 12'h2, addr, rts);
    endtask
    task automatic inject_snoop_makeinvalid (input logic [CHIE_SNP_ADDR_WIDTH_PARAM-1:0] addr,
                                             input logic rts = 1'b0);
        try_inject_snoop(`CHIE_SNPMAKEINVALID, 12'h3, addr, rts);
    endtask
    task automatic inject_snoop_cleaninvalid(input logic [CHIE_SNP_ADDR_WIDTH_PARAM-1:0] addr,
                                             input logic rts = 1'b0);
        try_inject_snoop(`CHIE_SNPCLEANINVALID, 12'h4, addr, rts);
    endtask
    task automatic inject_snoop_shared      (input logic [CHIE_SNP_ADDR_WIDTH_PARAM-1:0] addr,
                                             input logic rts = 1'b0);
        try_inject_snoop(`CHIE_SNPSHARED, 12'h5, addr, rts);
    endtask

    // Drive RXSNP channel from pending slot.
    // snp_pending is updated *only* by the always_ff below; the
    // inject_snoop_* tasks set snp_inject + snp_inject_flit (declared
    // up by pending_snp_flit) which the FF consumes.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            RXSNPFLITV       <= 1'b0;
            RXSNPFLIT        <= '0;
            RXSNPFLITPEND    <= 1'b0;
            snp_pending      <= 1'b0;
            pending_snp_flit <= '0;
        end
        else begin
            // Latch a new snoop if the inject pulse is set and slot is free
            if (snp_inject && !snp_pending) begin
                snp_pending      <= 1'b1;
                pending_snp_flit <= snp_inject_flit;
            end
            // Clear once the snoop flit has actually been driven (i.e.
            // we had credit and the DUT consumed one).  The old
            // condition (RXSNPLCRDV) waited for the DUT to *return* a
            // credit, which only happens after the snoop is processed
            // — so snp_pending stayed high for many cycles and the
            // trace looked like the same snoop firing every cycle.
            else if (snp_pending && have_snp_credit) begin
                snp_pending <= 1'b0;
            end
            RXSNPFLITV    <= snp_pending && have_snp_credit;
            RXSNPFLIT     <= pending_snp_flit;
            RXSNPFLITPEND <= 1'b0;
        end
    end

endmodule
