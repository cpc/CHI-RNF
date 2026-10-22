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
 * rnf_ip_tb.sv
 *
 * IP-level testbench for the CHI-E RN-F (cache/l15 + cache/rnf_link).
 *
 * Scope: bypass CVA6 entirely.  The DUT is l15_wrap (which instantiates
 * `l15` + `rnf_link`).  The CPU side is stimulated via the transducer
 * interface from this TB; the CHI side is answered by an abstract HN-F
 * responder (chi_hnf_responder.sv).
 *
 * This file provides:
 *   * DUT instantiation with RNF_PARAM defaults.
 *   * OpenPiton NOC ports + RTAP test ports tied off.
 *   * A small library of CPU-port tasks (do_load, do_store, do_amo,
 *     do_cbo_*) that drive the transducer interface and wait for the
 *     L1.5's transducer_val response.
 *   * A smoke-test sequence in the initial block that issues a load
 *     against the abstract responder, validates the round-trip, and
 *     finishes.
 *
 * The smoke test is intentionally minimal -- the heavy-lift sweeping
 * (vector replay against Murphi-derived test cases, snoop injection,
 * data oracle, etc.) is a separate driver layer that will hang off
 * this TB once the bring-up is stable.
 */

`include "rnf_param.v"
`include "rnf_defines.v"
`include "chie_defines.v"
`include "l15.tmp.h"

`timescale 1ns/1ps

module rnf_ip_tb import wt_cache_pkg::*;;

    // CHI parameter mirror -- match rnf_param.v defaults so the
    // `CHIE_*_RANGE macros expand against the same values used inside
    // the DUT.  These are visible to flit-width macro expansions in
    // this TB's scope.
    localparam int CHIE_REQ_ADDR_WIDTH_PARAM  = 44;
    localparam int CHIE_SNP_ADDR_WIDTH_PARAM  = 41;
    localparam int CHIE_NID_WIDTH_PARAM       = 7;
    localparam int CHIE_DATA_WIDTH_PARAM      = 256;
    localparam int CHIE_BE_WIDTH_PARAM        = 32;
    localparam int CHIE_DATACHECK_WIDTH_PARAM = 0;
    localparam int CHIE_POISON_WIDTH_PARAM    = 0;
    localparam int CHIE_REQ_RSVDC_WIDTH_PARAM = 0;
    localparam int CHIE_DAT_RSVDC_WIDTH_PARAM = 0;

    // ── Clock / reset ───────────────────────────────────────────────
    logic clk;
    logic rst_n;

    initial clk = 1'b0;
    always #5 clk = ~clk;   // 100 MHz

    initial begin
        rst_n = 1'b0;
        #100  rst_n = 1'b1;
    end

    // ── DUT  ↔  HN-F responder wires ────────────────────────────────
    // CHI -- DUT TX ⇒ responder; DUT RX ⇐ responder.
    logic                          rxrspflitv,    rxrspflitpend;
    logic [`CHIE_RSP_FLIT_RANGE]   rxrspflit;
    logic                          rxdatflitv,    rxdatflitpend;
    logic [`CHIE_DAT_FLIT_RANGE]   rxdatflit;
    logic                          rxsnpflitv,    rxsnpflitpend;
    logic [`CHIE_SNP_FLIT_RANGE]   rxsnpflit;

    logic                          txreqlcrdv, txrsplcrdv, txdatlcrdv;
    logic                          rxrsplcrdv, rxdatlcrdv, rxsnplcrdv;

    logic                          txreqflitv, txreqflitpend;
    logic [`CHIE_REQ_FLIT_RANGE]   txreqflit;
    logic                          txrspflitv, txrspflitpend;
    logic [`CHIE_RSP_FLIT_RANGE]   txrspflit;
    logic                          txdatflitv, txdatflitpend;
    logic [`CHIE_DAT_FLIT_RANGE]   txdatflit;

    logic                          txlinkactivereq, txlinkactiveack;
    logic                          rxlinkactivereq, rxlinkactiveack;
    logic                          txactive, rxactive;

    // ── CPU port (transducer interface) ─────────────────────────────
    logic [4:0]                    transducer_l15_rqtype;
    logic [`L15_AMO_OP_WIDTH-1:0]  transducer_l15_amo_op;
    logic                          transducer_l15_nc;
    logic [2:0]                    transducer_l15_size;
    logic [`L15_THREADID_MASK]     transducer_l15_threadid;
    logic                          transducer_l15_prefetch;
    logic                          transducer_l15_invalidate_cacheline;
    logic                          transducer_l15_blockstore;
    logic                          transducer_l15_blockinitstore;
    logic [1:0]                    transducer_l15_l1rplway;
    logic                          transducer_l15_val;
    logic [39:0]                   transducer_l15_address;
    logic [63:0]                   transducer_l15_data;
    logic [63:0]                   transducer_l15_data_next_entry;
    logic [`TLB_CSM_WIDTH-1:0]     transducer_l15_csm_data;

    wire                           l15_transducer_ack;
    wire                           l15_transducer_header_ack;
    wire                           l15_transducer_val;
    wire [3:0]                     l15_transducer_returntype;
    wire                           l15_transducer_l2miss;
    wire [1:0]                     l15_transducer_error;
    wire                           l15_transducer_noncacheable;
    wire                           l15_transducer_atomic;
    wire [`L15_THREADID_MASK]      l15_transducer_threadid;
    wire                           l15_transducer_prefetch;
    wire                           l15_transducer_f4b;
    wire [63:0]                    l15_transducer_data_0;
    wire [63:0]                    l15_transducer_data_1;
    wire [63:0]                    l15_transducer_data_2;
    wire [63:0]                    l15_transducer_data_3;
    wire                           l15_transducer_inval_icache_all_way;
    wire                           l15_transducer_inval_dcache_all_way;
    wire [15:4]                    l15_transducer_inval_address_15_4;
    wire                           l15_transducer_cross_invalidate;
    wire [1:0]                     l15_transducer_cross_invalidate_way;
    wire                           l15_transducer_inval_dcache_inval;
    wire                           l15_transducer_inval_icache_inval;
    wire [1:0]                     l15_transducer_inval_way;
    wire                           l15_transducer_blockinitstore;
    logic                          transducer_l15_req_ack;

    logic [63:0]                   transducer_l15_data_bigend;

    // ── Tie-offs for OpenPiton NOC / config / RTAP ports ────────────
    // The L1.5 has legacy OpenPiton routing ports.  In the CHI-only
    // flow these are unused; tie ready=1, valid=0, data=0.
    wire        noc1_out_val;
    wire [`NOC_DATA_WIDTH-1:0] noc1_out_data;
    wire        noc2_in_rdy;
    wire        noc3_out_val;
    wire [`NOC_DATA_WIDTH-1:0] noc3_out_data;
    wire        l15_dmbr_l1missIn, l15_dmbr_l2responseIn, l15_dmbr_l2missIn;
    wire [`DMBR_TAG_WIDTH-1:0] l15_dmbr_l1missTag, l15_dmbr_l2missTag;
    wire        l15_config_req_val_s2, l15_config_req_rw_s2;
    wire [63:0] l15_config_write_req_data_s2;
    wire [`CONFIG_REG_ADDRESS_MASK] l15_config_req_address_s2;
    wire [`SRAM_WRAPPER_BUS_WIDTH-1:0] srams_rtap_data;

    // ── DUT instantiation ───────────────────────────────────────────
    l15_wrap u_dut (
        .clk(clk),
        .rst_n(rst_n),

        // Transducer in
        .transducer_l15_rqtype              (transducer_l15_rqtype),
        .transducer_l15_amo_op              (transducer_l15_amo_op),
        .transducer_l15_nc                  (transducer_l15_nc),
        .transducer_l15_size                (transducer_l15_size),
        .transducer_l15_threadid            (transducer_l15_threadid),
        .transducer_l15_prefetch            (transducer_l15_prefetch),
        .transducer_l15_invalidate_cacheline(transducer_l15_invalidate_cacheline),
        .transducer_l15_blockstore          (transducer_l15_blockstore),
        .transducer_l15_blockinitstore      (transducer_l15_blockinitstore),
        .transducer_l15_l1rplway            (transducer_l15_l1rplway),
        .transducer_l15_val                 (transducer_l15_val),
        .transducer_l15_address             (transducer_l15_address),
        .transducer_l15_data                (transducer_l15_data_bigend),
        .transducer_l15_data_next_entry     (transducer_l15_data_next_entry),
        .transducer_l15_csm_data            (transducer_l15_csm_data),

        // Transducer out
        .l15_transducer_ack                 (l15_transducer_ack),
        .l15_transducer_header_ack          (l15_transducer_header_ack),
        .l15_transducer_val                 (l15_transducer_val),
        .l15_transducer_returntype          (l15_transducer_returntype),
        .l15_transducer_l2miss              (l15_transducer_l2miss),
        .l15_transducer_error               (l15_transducer_error),
        .l15_transducer_noncacheable        (l15_transducer_noncacheable),
        .l15_transducer_atomic              (l15_transducer_atomic),
        .l15_transducer_threadid            (l15_transducer_threadid),
        .l15_transducer_prefetch            (l15_transducer_prefetch),
        .l15_transducer_f4b                 (l15_transducer_f4b),
        .l15_transducer_data_0              (l15_transducer_data_0),
        .l15_transducer_data_1              (l15_transducer_data_1),
        .l15_transducer_data_2              (l15_transducer_data_2),
        .l15_transducer_data_3              (l15_transducer_data_3),
        .l15_transducer_inval_icache_all_way(l15_transducer_inval_icache_all_way),
        .l15_transducer_inval_dcache_all_way(l15_transducer_inval_dcache_all_way),
        .l15_transducer_inval_address_15_4  (l15_transducer_inval_address_15_4),
        .l15_transducer_cross_invalidate    (l15_transducer_cross_invalidate),
        .l15_transducer_cross_invalidate_way(l15_transducer_cross_invalidate_way),
        .l15_transducer_inval_dcache_inval  (l15_transducer_inval_dcache_inval),
        .l15_transducer_inval_icache_inval  (l15_transducer_inval_icache_inval),
        .l15_transducer_inval_way           (l15_transducer_inval_way),
        .l15_transducer_blockinitstore      (l15_transducer_blockinitstore),
        .transducer_l15_req_ack             (transducer_l15_req_ack),

        // OpenPiton legacy ports -- tied off for CHI-only flow
        .noc1_out_rdy                       (1'b1),
        .noc2_in_val                        (1'b0),
        .noc2_in_data                       ('0),
        .noc3_out_rdy                       (1'b1),
        .dmbr_l15_stall                     (1'b0),
        .chipid                             ('0),
        .coreid_x                           ('0),
        .coreid_y                           ('0),
        .config_l15_read_res_data_s3        (64'h0),
        .config_csm_en                      (1'b0),
        .config_system_tile_count           (32'h1),
        .config_home_alloc_method           ('0),
        .config_hmt_base                    ('0),
        .noc1_out_val                       (noc1_out_val),
        .noc1_out_data                      (noc1_out_data),
        .noc2_in_rdy                        (noc2_in_rdy),
        .noc3_out_val                       (noc3_out_val),
        .noc3_out_data                      (noc3_out_data),
        .l15_dmbr_l1missIn                  (l15_dmbr_l1missIn),
        .l15_dmbr_l1missTag                 (l15_dmbr_l1missTag),
        .l15_dmbr_l2responseIn              (l15_dmbr_l2responseIn),
        .l15_dmbr_l2missIn                  (l15_dmbr_l2missIn),
        .l15_dmbr_l2missTag                 (l15_dmbr_l2missTag),
        .l15_config_req_val_s2              (l15_config_req_val_s2),
        .l15_config_req_rw_s2               (l15_config_req_rw_s2),
        .l15_config_write_req_data_s2       (l15_config_write_req_data_s2),
        .l15_config_req_address_s2          (l15_config_req_address_s2),
        .srams_rtap_data                    (srams_rtap_data),
        .rtap_srams_bist_command            ('0),
        .rtap_srams_bist_data               ('0),

        // CHI side
        .RXRSPFLITV    (rxrspflitv),
        .RXRSPFLIT     (rxrspflit),
        .RXRSPFLITPEND (rxrspflitpend),
        .RXDATFLITV    (rxdatflitv),
        .RXDATFLIT     (rxdatflit),
        .RXDATFLITPEND (rxdatflitpend),
        .RXSNPFLITV    (rxsnpflitv),
        .RXSNPFLIT     (rxsnpflit),
        .RXSNPFLITPEND (rxsnpflitpend),
        .TXREQLCRDV    (txreqlcrdv),
        .TXRSPLCRDV    (txrsplcrdv),
        .TXDATLCRDV    (txdatlcrdv),
        .RXRSPLCRDV    (rxrsplcrdv),
        .RXDATLCRDV    (rxdatlcrdv),
        .RXSNPLCRDV    (rxsnplcrdv),
        .TXREQFLITV    (txreqflitv),
        .TXREQFLIT     (txreqflit),
        .TXREQFLITPEND (txreqflitpend),
        .TXRSPFLITV    (txrspflitv),
        .TXRSPFLIT     (txrspflit),
        .TXRSPFLITPEND (txrspflitpend),
        .TXDATFLITV    (txdatflitv),
        .TXDATFLIT     (txdatflit),
        .TXDATFLITPEND (txdatflitpend),
        .TXLINKACTIVEREQ(txlinkactivereq),
        .TXLINKACTIVEACK(txlinkactiveack),
        .RXLINKACTIVEREQ(rxlinkactivereq),
        .RXLINKACTIVEACK(rxlinkactiveack),
        .TXACTIVE      (txactive),
        .RXACTIVE      (rxactive)
    );

    // ── Abstract HN-F responder ─────────────────────────────────────
    chi_hnf_responder u_hnf (
        .clk(clk),
        .rst_n(rst_n),

        .TXREQFLITV    (txreqflitv),
        .TXREQFLIT     (txreqflit),
        .TXREQFLITPEND (txreqflitpend),
        .TXRSPFLITV    (txrspflitv),
        .TXRSPFLIT     (txrspflit),
        .TXRSPFLITPEND (txrspflitpend),
        .TXDATFLITV    (txdatflitv),
        .TXDATFLIT     (txdatflit),
        .TXDATFLITPEND (txdatflitpend),

        .TXREQLCRDV    (txreqlcrdv),
        .TXRSPLCRDV    (txrsplcrdv),
        .TXDATLCRDV    (txdatlcrdv),

        .RXRSPFLITV    (rxrspflitv),
        .RXRSPFLIT     (rxrspflit),
        .RXRSPFLITPEND (rxrspflitpend),
        .RXDATFLITV    (rxdatflitv),
        .RXDATFLIT     (rxdatflit),
        .RXDATFLITPEND (rxdatflitpend),
        .RXSNPFLITV    (rxsnpflitv),
        .RXSNPFLIT     (rxsnpflit),
        .RXSNPFLITPEND (rxsnpflitpend),
        .RXRSPLCRDV    (rxrsplcrdv),
        .RXDATLCRDV    (rxdatlcrdv),
        .RXSNPLCRDV    (rxsnplcrdv),

        .TXLINKACTIVEREQ(txlinkactivereq),
        .TXLINKACTIVEACK(txlinkactiveack),
        .RXLINKACTIVEREQ(rxlinkactivereq),
        .RXLINKACTIVEACK(rxlinkactiveack),
        .TXACTIVE      (txactive),
        .RXACTIVE      (rxactive)
    );

    // Request data needs to be endian-swapped for L15
    assign transducer_l15_data_bigend = swendian64(transducer_l15_data);


    // Always accept transducer requests at the L1.5 head (no
    // back-pressure modelling in the smoke harness).
    assign transducer_l15_req_ack = 1'b1;

    // ── Debug trace (gated by +DBG_TRACE) ───────────────────────────
    // Dumps every TX/RX flit edge so post-UD_PD wedges are diagnosable
    // without scrolling waveform.
    logic dbg_trace_en;
    initial dbg_trace_en = 1'b0;
    initial if ($test$plusargs("DBG_TRACE")) dbg_trace_en = 1'b1;
    int unsigned dbg_rxrsplcrdv_count, dbg_rxdatlcrdv_count, dbg_rxsnplcrdv_count;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dbg_rxrsplcrdv_count <= 0;
            dbg_rxdatlcrdv_count <= 0;
            dbg_rxsnplcrdv_count <= 0;
        end else begin
            if (rxrsplcrdv) dbg_rxrsplcrdv_count <= dbg_rxrsplcrdv_count + 1;
            if (rxdatlcrdv) dbg_rxdatlcrdv_count <= dbg_rxdatlcrdv_count + 1;
            if (rxsnplcrdv) dbg_rxsnplcrdv_count <= dbg_rxsnplcrdv_count + 1;
        end
    end
    always_ff @(posedge clk) if (dbg_trace_en) begin
        if (rxrsplcrdv) $display("[%0t] LCRDV RSP (total=%0d)", $time, dbg_rxrsplcrdv_count);
        if (rxdatlcrdv) $display("[%0t] LCRDV DAT (total=%0d)", $time, dbg_rxdatlcrdv_count);
        if (rxsnplcrdv) $display("[%0t] LCRDV SNP (total=%0d)", $time, dbg_rxsnplcrdv_count);
        if (txreqflitv)
            $display("[%0t] TXREQ opcode=%02h addr=%010h txnid=%0d",
                     $time,
                     txreqflit[`CHIE_REQ_FLIT_OPCODE_RANGE],
                     txreqflit[`CHIE_REQ_FLIT_ADDR_RANGE],
                     txreqflit[`CHIE_REQ_FLIT_TXNID_RANGE]);
        if (txrspflitv)
            $display("[%0t] TXRSP opcode=%02h txnid=%0d resp=%03b",
                     $time,
                     txrspflit[`CHIE_RSP_FLIT_OPCODE_RANGE],
                     txrspflit[`CHIE_RSP_FLIT_TXNID_RANGE],
                     txrspflit[`CHIE_RSP_FLIT_RESP_RANGE]);
        if (txdatflitv)
            $display("[%0t] TXDAT opcode=%02h txnid=%0d resp=%03b",
                     $time,
                     txdatflit[`CHIE_DAT_FLIT_OPCODE_RANGE],
                     txdatflit[`CHIE_DAT_FLIT_TXNID_RANGE],
                     txdatflit[`CHIE_DAT_FLIT_RESP_RANGE]);
        if (rxrspflitv)
            $display("[%0t] RXRSP opcode=%02h txnid=%0d",
                     $time,
                     rxrspflit[`CHIE_RSP_FLIT_OPCODE_RANGE],
                     rxrspflit[`CHIE_RSP_FLIT_TXNID_RANGE]);
        if (rxdatflitv)
            $display("[%0t] RXDAT opcode=%02h txnid=%0d resp=%03b",
                     $time,
                     rxdatflit[`CHIE_DAT_FLIT_OPCODE_RANGE],
                     rxdatflit[`CHIE_DAT_FLIT_TXNID_RANGE],
                     rxdatflit[`CHIE_DAT_FLIT_RESP_RANGE]);
        if (rxsnpflitv)
            $display("[%0t] RXSNP opcode=%02h addr=%010h txnid=%0d",
                     $time,
                     rxsnpflit[`CHIE_SNP_FLIT_OPCODE_RANGE],
                     rxsnpflit[`CHIE_SNP_FLIT_ADDR_RANGE],
                     rxsnpflit[`CHIE_SNP_FLIT_TXNID_RANGE]);
    end

    // ── Snoop-response protocol monitor ─────────────────────────────
    // CHI-E §4.5.4 / Table 4.10 require every accepted RXSNP to be
    // answered by *some* SnpResp variant within a bounded window:
    //   * TXRSP opcode 5'h01  (CHIE_SNPRESP, dataless)
    //   * TXDAT opcode 4'h1   (CHIE_SNPRESPDATA)
    //   * TXDAT opcode 4'h5   (CHIE_SNPRESPDATAPTL)
    //   * TXDAT opcode 4'h6   (CHIE_SNPRESPDATAFWDED)
    // The L1.5 currently *drops* snoops on UD/SD lines — never emits
    // any of the above — so these hazard cases were passing silently.
    // This monitor tracks up to SNP_MON_DEPTH outstanding snoop
    // TXNIDs and $fatals when any of them ages past SNP_MON_TIMEOUT.
    // Gated by +DISABLE_SNP_MON so a diagnostic run can suppress it.
    localparam int SNP_MON_DEPTH   = 8;
    // 500 cycles ≈ 5us at 100MHz.  CHI doesn't specify a hard limit
    // but responses that don't arrive in this many cycles from an
    // otherwise-idle DUT indicate a stall, not slow processing.
    localparam int SNP_MON_TIMEOUT = 500;
    logic        snp_mon_disabled;
    initial      snp_mon_disabled = 1'b0;
    initial      if ($test$plusargs("DISABLE_SNP_MON")) snp_mon_disabled = 1'b1;

    logic [11:0] snp_mon_txnid   [SNP_MON_DEPTH-1:0];
    int unsigned snp_mon_age     [SNP_MON_DEPTH-1:0];
    logic        snp_mon_valid   [SNP_MON_DEPTH-1:0];

    function automatic bit txdat_is_snpresp(input logic [3:0] op);
        return (op == 4'h1) || (op == 4'h5) || (op == 4'h6);
    endfunction

    always_ff @(posedge clk or negedge rst_n) begin
        int         i, slot;
        bit         matched;
        logic [11:0] resp_txnid;
        if (!rst_n) begin
            for (i = 0; i < SNP_MON_DEPTH; i++) begin
                snp_mon_txnid[i] <= '0;
                snp_mon_age[i]   <= 0;
                snp_mon_valid[i] <= 1'b0;
            end
        end
        else begin
            // Age all live entries; fail if any exceeds timeout.
            for (i = 0; i < SNP_MON_DEPTH; i++) begin
                if (snp_mon_valid[i]) begin
                    snp_mon_age[i] <= snp_mon_age[i] + 1;
                    if (!snp_mon_disabled &&
                        snp_mon_age[i] >= SNP_MON_TIMEOUT) begin
                        $display("[%0t] [SNP_MON] FATAL: snoop txnid=%0d unanswered for %0d cycles (CHI-E Table 4.10 violation)",
                                 $time, snp_mon_txnid[i], snp_mon_age[i]);
                        $fatal(1, "RN-F dropped an accepted snoop without emitting SnpResp / SnpRespData");
                    end
                end
            end
            // Retire on matching TXRSP SnpResp or TXDAT SnpRespData*.
            if (txrspflitv &&
                txrspflit[`CHIE_RSP_FLIT_OPCODE_RANGE] == 5'h01) begin
                resp_txnid = txrspflit[`CHIE_RSP_FLIT_TXNID_RANGE];
                matched = 1'b0;
                for (i = 0; i < SNP_MON_DEPTH; i++)
                    if (!matched && snp_mon_valid[i] &&
                        snp_mon_txnid[i] == resp_txnid) begin
                        snp_mon_valid[i] <= 1'b0;
                        matched = 1'b1;
                    end
            end
            if (txdatflitv &&
                txdat_is_snpresp(txdatflit[`CHIE_DAT_FLIT_OPCODE_RANGE])) begin
                resp_txnid = txdatflit[`CHIE_DAT_FLIT_TXNID_RANGE];
                matched = 1'b0;
                for (i = 0; i < SNP_MON_DEPTH; i++)
                    if (!matched && snp_mon_valid[i] &&
                        snp_mon_txnid[i] == resp_txnid) begin
                        snp_mon_valid[i] <= 1'b0;
                        matched = 1'b1;
                    end
            end
            // Record new snoops.  Only count when the DUT actually
            // accepts (RXSNPFLITV asserted and rxsnplcrdv already
            // credited it — but our responder gates FLITV on credit,
            // so a live FLITV cycle is an accepted flit).
            if (rxsnpflitv) begin
                slot = -1;
                for (i = 0; i < SNP_MON_DEPTH; i++)
                    if (slot < 0 && !snp_mon_valid[i]) slot = i;
                if (slot >= 0) begin
                    snp_mon_txnid[slot] <= rxsnpflit[`CHIE_SNP_FLIT_TXNID_RANGE];
                    snp_mon_age[slot]   <= 0;
                    snp_mon_valid[slot] <= 1'b1;
                end
                else if (!snp_mon_disabled) begin
                    $fatal(1, "[SNP_MON] more than %0d outstanding snoops; raise SNP_MON_DEPTH",
                           SNP_MON_DEPTH);
                end
            end
        end
    end

    // Backstop: if the sim reaches $finish while any snoop is still
    // outstanding, that's also a Table 4.10 violation — the DUT
    // received the snoop but never emitted a response.
    final begin
        int i, n_outstanding;
        n_outstanding = 0;
        for (i = 0; i < SNP_MON_DEPTH; i++)
            if (snp_mon_valid[i]) begin
                $display("[SNP_MON] outstanding snoop at $finish: txnid=%0d, age=%0d cycles",
                         snp_mon_txnid[i], snp_mon_age[i]);
                n_outstanding++;
            end
        if (n_outstanding > 0 && !snp_mon_disabled)
            $error("[SNP_MON] %0d snoop(s) never answered — CHI-E Table 4.10 violation (RN-F bug)",
                   n_outstanding);
    end

    // ── Data-freshness oracle (single-hart coherence sanity) ────────
    // Tracks the byte-accurate ground-truth for every 64 B cache line
    // the RN-F has ever loaded or stored, and asserts that any bytes
    // the RN-F ships out (SnpRespData / SnpRespDataPtl / CopyBackWrData)
    // match the oracle.  Catches:
    //   * RN-F emits stale bytes on a snoop-response with data
    //   * RN-F emits stale bytes on a writeback
    //   * RN-F fabricates data for a line it never received
    // Does NOT catch cross-hart stale-copy failures (would need a peer
    // RN-F).  Gated by +DISABLE_MEM_ORACLE for diagnostic runs.
    localparam int LINE_BYTES = 64;

    logic        mem_oracle_disabled;
    initial      mem_oracle_disabled = 1'b0;
    initial      if ($test$plusargs("DISABLE_MEM_ORACLE")) mem_oracle_disabled = 1'b1;

    // Post-vector data-integrity probe: when 1, the TB is driving synthetic
    // LDs against every touched line to check the RN-F's cached bytes vs the
    // oracle.  Two effects while set:
    //   * rxdat_capture ignores probe-induced CompData so a probe miss +
    //     HNF-supplied garbage doesn't overwrite ground truth.
    //   * load_return_check skips $error on l2miss (probe on evicted line
    //     is a silent skip, not a data-corruption event).
    logic        probing;
    int          probe_hit_cnt, probe_miss_cnt, probe_skip_cnt;
    initial      probing = 1'b0;
    logic        probe_disabled;
    initial      probe_disabled = 1'b0;
    initial      if ($test$plusargs("DISABLE_MEM_PROBE")) probe_disabled = 1'b1;

    // Write-visibility probe: LD → ST → LD-back triple appended at the
    // end of each vector's replay.  BFS-generated vectors leave the RN-F
    // in a diverse set of quiescent stable states; the triple fires from
    // each such state, exercising the hart-side write-visibility path
    // (RVWMO Load Value axiom) that the CHI-only Murphi model treats as
    // a silent drain.  Reproduces the RNF_COHERENCE_BUG.md failure mode
    // by construction on any state where the store's bytes fail to
    // become visible to the immediately-following load.
    logic        wv_probe_disabled;
    initial      wv_probe_disabled = 1'b0;
    initial      if ($test$plusargs("DISABLE_WRITE_VIS_PROBE")) wv_probe_disabled = 1'b1;
    int          wv_probe_fired_cnt;
    int          wv_probe_skipped_cnt;
    initial      wv_probe_fired_cnt = 0;
    initial      wv_probe_skipped_cnt = 0;

    // The directed SnpRespData exerciser (see end of replay_vector) is
    // a TB self-check on a hardcoded address, not part of the vector's
    // Murphi model.  While active, oracle updates are suppressed so the
    // exerciser's activity doesn't populate ground truth that the probe
    // would then try to verify against a state the oracle can't cleanly
    // reproduce (e.g. a store whose header-ack timing the oracle
    // under-models).  Net effect: probe_all_dirty_lines never sees the
    // exerciser's address in oracle_mem and doesn't probe it.
    logic        exerciser_active;
    initial      exerciser_active = 1'b0;
    // TXREQ counter — probe uses "did the L1.5 emit a TXREQ during this
    // LD?" as a robust hit/miss disambiguator (l15_transducer_l2miss is
    // not asserted reliably on the reload path).
    int          txreq_emit_cnt;
    int          probe_txreq_snap;
    initial      txreq_emit_cnt = 0;
    initial      probe_txreq_snap = 0;
    always @(posedge clk) if (rst_n && txreqflitv) txreq_emit_cnt++;

    // ── Model-soundness trace (+MODEL_TRACE) ───────────────────────
    // The Murphi model assumes every SW_enqueue produces a CHI REQ.
    // The L1.5 filters many of them (a store to a line already UD, a
    // flush of a clean line, ...).  Emitting a timestamped record for
    // each SW dispatch and each TXREQ lets an offline pass attribute
    // every REQ to the SW event that preceded it and report the
    // per-event filter rate.  Off by default -- pure logging, no
    // effect on stimulus.
    logic model_trace_en;
    initial model_trace_en = $test$plusargs("MODEL_TRACE");

    // ── Trigger evaluation (vector @trig{...} preconditions) ───────
    // Phase 2 of trigger-annotated vectors: instead of dispatching every
    // DRIVE event on a fixed 5-cycle cadence and hoping the DUT is where
    // the model says, wait until the event's precondition actually
    // holds.  Opt-in via +USE_TRIGGERS so the untriggered behaviour
    // stays the committed baseline and the two can be compared.
    //
    // rnf_phase_tracker only exists in COVERAGE=1 builds, so derive the
    // two fields triggers use straight from the CHI wires here -- that
    // works in every build and keeps the replay independent of whether
    // covergroups are compiled in.
    logic use_triggers;
    int unsigned trigger_wait_cyc;
    int unsigned trigger_miss_cnt;
    initial begin
        use_triggers     = $test$plusargs("USE_TRIGGERS");
        trigger_wait_cyc = 200;
        void'($value$plusargs("TRIGGER_WAIT=%d", trigger_wait_cyc));
        trigger_miss_cnt = 0;
    end

    string tb_tx_phase;
    string tb_tx_op;
    logic  tb_tx_expack;
    initial begin tb_tx_phase = "TX_IDLE"; tb_tx_op = "tx_None"; tb_tx_expack = 1'b0; end

    // CHI REQ opcode -> the model's TxOp name.  ReadShared folds into
    // tx_ReadClean: the model has no separate shared-read op.
    function automatic string opcode_to_txop(input logic [6:0] op);
        if (op >= 7'h28 && op <= 7'h2f) return "tx_AtomicStore";
        if (op >= 7'h30 && op <= 7'h39) return "tx_AtomicLoad";
        case (op)
            7'h01, 7'h02:               return "tx_ReadClean";
            7'h04:                      return "tx_ReadNoSnp";
            7'h07:                      return "tx_ReadUnique";
            7'h08:                      return "tx_CleanShared";
            7'h09:                      return "tx_CleanInvalid";
            7'h0c:                      return "tx_MakeUnique";
            7'h15, 7'h17, 7'h1a, 7'h1b: return "tx_WriteBackFull";
            7'h18, 7'h19, 7'h1c, 7'h1d: return "tx_WriteNoSnpPtl";
            default:                    return "tx_None";
        endcase
    endfunction

    always @(posedge clk) if (rst_n) begin : tx_phase_track
        automatic logic [2:0] dat_resp = rxdatflit[`CHIE_DAT_FLIT_RESP_RANGE];
        if (txreqflitv) begin
            tb_tx_op      = opcode_to_txop(txreqflit[`CHIE_REQ_FLIT_OPCODE_RANGE]);
            tb_tx_phase   = "TX_AWAIT_RSP";
            tb_tx_expack  = txreqflit[`CHIE_REQ_FLIT_EXPCOMPACK_RANGE];
        end
        else if (txrspflitv &&
                 txrspflit[`CHIE_RSP_FLIT_OPCODE_RANGE] == `CHIE_COMPACK) begin
            tb_tx_phase = "TX_IDLE";
            tb_tx_op    = "tx_None";
        end
        else if (rxrspflitv) begin
            case (rxrspflit[`CHIE_RSP_FLIT_OPCODE_RANGE])
                `CHIE_DBIDRESP, `CHIE_COMPDBIDRESP:
                    tb_tx_phase = "TX_AWAIT_DATA_SEND";
                `CHIE_COMP: begin
                    tb_tx_phase = "TX_IDLE";
                    tb_tx_op    = "tx_None";
                end
                default: ;
            endcase
        end
        else if (rxdatflitv &&
                 rxdatflit[`CHIE_DAT_FLIT_OPCODE_RANGE] == `CHIE_COMPDATA) begin
            // Resp = {PD, state[1:0]} -- bit 2 is pass-dirty.
            // Only a REQ with ExpCompAck=1 is owed a CompAck.  Without
            // this the tracker parked in AWAIT_COMPACK forever on
            // atomics (which do not set it) and every later trigger
            // reported a spurious miss.
            if (tb_tx_expack)
                tb_tx_phase = dat_resp[2] ? "TX_AWAIT_COMPACK_DIRTY"
                                          : "TX_AWAIT_COMPACK_CLEAN";
            else begin
                tb_tx_phase = "TX_IDLE";
                tb_tx_op    = "tx_None";
            end
        end
        else if (txdatflitv &&
                 (txdatflit[`CHIE_DAT_FLIT_OPCODE_RANGE] == `CHIE_COPYBACKWRDATA ||
                  txdatflit[`CHIE_DAT_FLIT_OPCODE_RANGE] == `CHIE_NONCOPYBACKWRDATA))
            tb_tx_phase = "TX_AWAIT_COMP";
    end

    // Pull "<name>=<value>" out of a @trig body; "" when absent.
    function automatic string trig_field(input string trig, input string name);
        int i, j, k;
        string key;
        key = {name, "="};
        for (i = 0; i + key.len() <= trig.len(); i++) begin
            if (trig.substr(i, i + key.len() - 1) == key) begin
                j = i + key.len();
                k = j;
                while (k < trig.len() && trig[k] != ";") k++;
                return trig.substr(j, k - 1);
            end
        end
        return "";
    endfunction

    // Only tx_phase and tx_op are evaluated.  rx_snp and sw_q are
    // carried in the vector but not checked yet: rx_snp needs the
    // responder's pending-snoop view and sw_q has no TB counterpart
    // (dispatch_sw is blocking, so the model's queued-but-not-issued
    // state has no observable analogue here).
    // Does this precondition require a transaction to be in flight?
    function automatic bit trig_needs_tx(input string trig);
        string ph;
        if (!use_triggers || trig.len() == 0) return 1'b0;
        ph = trig_field(trig, "tx_phase");
        return (ph.len() != 0 && ph != "TX_IDLE");
    endfunction

    function automatic bit trig_satisfied(input string trig);
        string want_phase, want_op;
        want_phase = trig_field(trig, "tx_phase");
        want_op    = trig_field(trig, "tx_op");
        if (want_phase.len() && want_phase != tb_tx_phase) return 1'b0;
        if (want_op.len()    && want_op    != tb_tx_op)    return 1'b0;
        return 1'b1;
    endfunction

    // Wait for a precondition, bounded.  A trigger that never fires is
    // reported and stepped over rather than hanging the vector -- the
    // miss count is the point of the exercise, it measures how often the
    // model's predicted state and the DUT's actual state disagree.
    task automatic await_trigger(input string trig);
        int unsigned c;
        if (!use_triggers || trig.len() == 0) return;
        c = 0;
        while (!trig_satisfied(trig) && c < trigger_wait_cyc) begin
            @(posedge clk);
            c++;
        end
        if (c >= trigger_wait_cyc) begin
            trigger_miss_cnt++;
            if (trigger_miss_cnt <= 15)
                $display("[%0t] [TRIGGER_MISS] want{%s}  have{tx_phase=%s;tx_op=%s}",
                         $time, trig, tb_tx_phase, tb_tx_op);
        end
    endtask

    // ── Race-window controls ───────────────────────────────────────
    // +RESP_DELAY=<n> holds every HN-F response n cycles so a snoop can
    // be injected while the transaction is still outstanding.  Without
    // it the responder answers within a few cycles and the
    // await_rsp / ReadClean / AtomicLoad race bins are unreachable.
    // Default 60: long enough to overlap the snoop injection below,
    // far short of the 500-cycle SNP_MON timeout.
    // +NO_RACE_WINDOW restores the old zero-delay behaviour.
    int unsigned resp_delay_arg;
    int unsigned datasend_hold_arg;
    initial begin
        resp_delay_arg = 60;
        void'($value$plusargs("RESP_DELAY=%d", resp_delay_arg));
        if ($test$plusargs("NO_RACE_WINDOW")) resp_delay_arg = 0;
        // +DATASEND_HOLD=<n> withholds TXDAT link credit for n cycles
        // after a DBIDResp so TX_AWAIT_DATA_SEND stays open long enough
        // for an injected snoop to arrive inside it.
        datasend_hold_arg = 0;
        void'($value$plusargs("DATASEND_HOLD=%d", datasend_hold_arg));
        @(posedge rst_n);
        u_hnf.set_response_delay(resp_delay_arg);
        u_hnf.set_datasend_hold(datasend_hold_arg);
    end
    always @(posedge clk) if (rst_n && txreqflitv && model_trace_en)
        $display("[MTRACE] %0t REQ op=0x%02h addr=0x%010h txnid=0x%03h",
                 $time,
                 txreqflit[`CHIE_REQ_FLIT_OPCODE_RANGE],
                 txreqflit[`CHIE_REQ_FLIT_ADDR_RANGE] & 40'hFF_FFFF_FFFF,
                 txreqflit[`CHIE_REQ_FLIT_TXNID_RANGE]);

    // Byte-level ground-truth: line[addr>>6] -> 64 bytes of expected data.
    // Note: struct is unpacked (LINE_BYTES-element byte array can't be
    // packed).  Associative array key = line-aligned 40-bit address.
    typedef struct {
        logic [7:0]  b [LINE_BYTES];
        logic        ever_loaded;   // RN-F has ever installed this line
        // Per-byte knowledge.  `ever_loaded` is line-granular but the
        // data is byte-granular: a store to bytes 0..7 marked the whole
        // line loaded, so a later load of bytes 8..15 compared against
        // never-written X and reported a mismatch the DUT was not
        // responsible for.  Only bytes with valid[i] set are checked.
        logic [63:0] valid;
        // Set when the line is dropped locally (cbo_inval) while its CHI
        // transaction is still in flight.  The RN-F legitimately emits
        // CopyBackWrData / SnpRespData for the line after that point, so
        // egress checks must skip it rather than report "never loaded".
        // Cleared as soon as a fill or store re-establishes the line.
        logic        purged;
    } oracle_line_t;
    oracle_line_t oracle_mem [logic [39:0]];

    // ── Pending-store byte mask (store-over-fill ordering) ──────────
    // store_merge below records a store at header_ack -- i.e. BEFORE
    // the line has even been fetched.  When the store misses, the
    // L1.5 issues a ReadUnique and the CompData fill lands afterwards,
    // so Ingress 2 would overwrite the stored bytes and the oracle
    // would then expect the fill pattern where the DUT correctly holds
    // the store.  (Observed on hub_UD_AWAIT_COMP_WriteBackFull_Q_CBO_Zero:
    // store 0xdeadbeef_f00dcafe, fill 0xDEADBEEF, WriteBackFull sends
    // the store bytes, oracle expects the fill bytes.)
    //
    // One bit per byte of the 64 B line, set by store_merge and
    // honoured by the fill ingress, which skips masked bytes -- the
    // real cache merges the store on top of the fill, so this
    // reproduces the DUT's ordering.
    //
    // Clear points matter: a mask that is never cleared blocks
    // legitimate later fills.  Cleared (a) per 32 B slice once that
    // slice's fill has landed and been merged, since oracle and DUT
    // agree from then on, and (b) whenever the line is purged.
    logic [63:0] oracle_st_pend [logic [39:0]];
    // Lines the vector touched with an AMO — probe cannot cleanly
    // verify these, so skip them.  Cleared per vector.
    bit           amo_touched [logic [39:0]];
    // Lines the directed SnpRespData exerciser has written to.  The
    // exerciser deliberately runs with exerciser_active=1 (which gates
    // store_merge off), so the oracle never learns what the RN-F was
    // asked to install.  Recording every exerciser-touched line here
    // lets the egress MEM_ORACLE skip integrity checks on them — the
    // exerciser exists purely for coverage of the SR_*_PD snoop-
    // response variants, NOT for data-integrity checking.
    bit           exerciser_touched [logic [39:0]];

    // Outstanding-TXREQ tracker so CompData beats can be correlated to
    // their address.  RN-F allocates its own TXNIDs from a small pool;
    // the responder uses one at a time in this env, but a small table
    // is cheap and future-proofs multi-in-flight extensions.
    logic [39:0] req_addr_by_txnid [logic [11:0]];
    logic [6:0]  req_opcode_by_txnid [logic [11:0]];

    // Latest pending store from the transducer, captured on the cycle
    // the L1.5 accepts the header.  Merged into the oracle when it
    // becomes globally observable (heuristic: at header_ack + a small
    // settle; a real cache would merge at retirement but that's not
    // observable here).
    logic [39:0] pending_store_addr;
    logic [63:0] pending_store_data;
    logic [2:0]  pending_store_size;
    logic        pending_store_val;

    initial pending_store_val = 1'b0;

    // Blocking assignment used below because Questa doesn't allow
    // non-blocking writes to associative-array elements.  This code
    // is TB-only (not synthesised), so blocking-in-clocked-block is
    // acceptable and races don't matter within a scoreboard update.

    int unsigned x_txnid_count;
    final if (x_txnid_count)
        $display("[X_TXNID] %0d TXREQ flits carried an undefined TXNID", x_txnid_count);

    // ── Ingress 1: TXREQ captures (address ↔ txnid) ────────────────
    always @(posedge clk) if (rst_n && txreqflitv) begin : txreq_capture
        automatic logic [11:0] rtid   = txreqflit[`CHIE_REQ_FLIT_TXNID_RANGE];
        automatic logic [43:0] raddr  = txreqflit[`CHIE_REQ_FLIT_ADDR_RANGE];
        automatic logic [6:0]  ropc   = txreqflit[`CHIE_REQ_FLIT_OPCODE_RANGE];
        // The DUT has been observed driving a partially-X TXNID
        // (12'h0XX) with txreqflitv asserted, mid-run at ~21.5us.
        // Indexing an assoc array with an X key is an error in Questa
        // and poisons the address<->txnid map, which then mis-attributes
        // CompData payloads and can raise FALSE MEM_ORACLE failures.
        // Drop the entry and report once per occurrence -- an X TXNID on
        // an outgoing REQ is an RTL defect, not something to absorb.
        if (^rtid === 1'bx) begin
            x_txnid_count++;
            if (x_txnid_count <= 5)
                $display("[X_TXNID] %0t TXREQ with undefined TXNID=%h opcode=%h addr=%h",
                         $time, rtid, ropc, raddr[39:0]);
        end
        else begin
            req_addr_by_txnid[rtid]   = raddr[39:0];
            req_opcode_by_txnid[rtid] = ropc;
        end
    end

    // ── Ingress 2: RXDAT CompData — commit the payload into oracle
    // Both beats of a 2-beat CompData carry DATAID = 0 then 2.  We
    // write the corresponding 32 B slice of the line for each beat.
    always @(posedge clk) if (rst_n && rxdatflitv) begin : rxdat_capture
        automatic logic [3:0]  dop  = rxdatflit[`CHIE_DAT_FLIT_OPCODE_RANGE];
        automatic logic [11:0] dtid = rxdatflit[`CHIE_DAT_FLIT_TXNID_RANGE];
        automatic logic [1:0]  did  = rxdatflit[`CHIE_DAT_FLIT_DATAID_RANGE];
        if (dop == `CHIE_COMPDATA && req_addr_by_txnid.exists(dtid) && !probing && !exerciser_active) begin
            automatic logic [39:0]  line = req_addr_by_txnid[dtid] & ~40'h3F;
            automatic logic [255:0] pay  = rxdatflit[`CHIE_DAT_FLIT_DATA_RANGE];
            automatic int base = (did == 2'b10) ? 32 : 0;
            automatic logic [63:0] pend =
                oracle_st_pend.exists(line) ? oracle_st_pend[line] : 64'h0;
            for (int i = 0; i < 32; i++)
                if (!pend[base + i]) begin      // a pending store owns this byte
                    oracle_mem[line].b[base + i]     = pay[8*i +: 8];
                    oracle_mem[line].valid[base + i] = 1'b1;
                end
            oracle_mem[line].ever_loaded = 1'b1;
            oracle_mem[line].purged      = 1'b0;
            // This slice is now consistent with the DUT; release it so a
            // later refill is not blocked by a stale mask.
            for (int i = 0; i < 32; i++)
                pend[base + i] = 1'b0;
            oracle_st_pend[line] = pend;
        end
    end

    // ── Ingress 3: transducer STORE — merge stored bytes into oracle
    // Snap the store fields on header_ack, then merge into the oracle
    // one cycle later.
    always @(posedge clk) if (rst_n) begin : store_merge
        // NC stores are included deliberately.  They are writethrough:
        // the data lands in memory (the responder absorbs the
        // NonCopyBackWrData for WriteNoSnp/WriteUnique) and becomes
        // observable to a later cacheable read of the line once it
        // refills.  Measured on hub_I_AWAIT_RSP_ReadClean_Q_NC_Store: a
        // do_store_nc at 20645 ns is read back intact at 30655 ns.  So
        // the line image must track them -- excluding them just moved
        // the mismatch to the other side.
        if (transducer_l15_val && l15_transducer_header_ack &&
            transducer_l15_rqtype == `PCX_REQTYPE_STORE &&
            !exerciser_active) begin
            pending_store_addr = transducer_l15_address;
            pending_store_data = transducer_l15_data;
            pending_store_size = transducer_l15_size;
            pending_store_val  = 1'b1;
        end
        else if (pending_store_val) begin : do_merge
            automatic logic [39:0] line = pending_store_addr & ~40'h3F;
            automatic int          off  = pending_store_addr[5:0];
            automatic int          nb   = (1 << (pending_store_size - 1));
            automatic logic [63:0] pend =
                oracle_st_pend.exists(line) ? oracle_st_pend[line] : 64'h0;
            for (int i = 0; i < nb; i++) begin
                oracle_mem[line].b[off + i]     = pending_store_data[8*i +: 8];
                oracle_mem[line].valid[off + i] = 1'b1;
                pend[off + i] = 1'b1;   // protect from a fill still in flight
            end
            oracle_st_pend[line] = pend;
            oracle_mem[line].ever_loaded = 1'b1;
            oracle_mem[line].purged      = 1'b0;
            pending_store_val = 1'b0;
        end
    end

    // ── Invalidating snoops drop the line from the RN-F ─────────────
    // SnpUnique (0x07), SnpCleanInvalid (0x09) and SnpMakeInvalid (0x0a)
    // all leave the line Invalid.  SnpMakeInvalid in particular
    // DISCARDS dirty data rather than writing it back -- the snooper is
    // about to overwrite the whole line -- so a store the RN-F accepted
    // moments earlier is legitimately lost, and the next miss refills
    // the pre-store contents from memory.  Without this the oracle kept
    // asserting the stored bytes and reported the correct behaviour as
    // "RN-F returned stale/wrong data" (seen on
    // hub_SD_AWAIT_RSP_WriteBackFull_Q_ReadUnique: store at 21165 ns,
    // SnpMakeInvalid at 21250 ns, loads thereafter return the old fill).
    // Same treatment as the cbo_inval tombstone: drop byte validity,
    // suppress the never-loaded complaint, and let a later fill or store
    // re-establish the line.
    always @(posedge clk) if (rst_n && rxsnpflitv) begin : snp_invalidate
        automatic logic [4:0]  sop = rxsnpflit[`CHIE_SNP_FLIT_OPCODE_RANGE];
        automatic logic [39:0] sline =
            ({rxsnpflit[`CHIE_SNP_FLIT_ADDR_RANGE], 3'b000}) & ~40'h3F;
        if (sop == 5'h07 || sop == 5'h09 || sop == 5'h0a) begin
            if (oracle_mem.exists(sline)) begin
                oracle_mem[sline].valid  = 64'h0;
                oracle_mem[sline].purged = 1'b1;
            end
            if (oracle_st_pend.exists(sline))
                oracle_st_pend.delete(sline);
        end
    end

    // ── Egress check: TXDAT SnpRespData / SnpRespDataPtl / CopyBack
    // Compare the outgoing 256-bit payload against the oracle slice
    // selected by DATAID.  Report per-byte mismatches (up to 4) so a
    // failure is human-readable in the log.  Report is $error, so the
    // sweep classifier picks it up as FAIL if paired with the same
    // regex hook we added for SNP_MON.
    always_ff @(posedge clk) if (rst_n && txdatflitv && !mem_oracle_disabled) begin
        automatic logic [3:0]  dop  = txdatflit[`CHIE_DAT_FLIT_OPCODE_RANGE];
        automatic logic [11:0] dtid = txdatflit[`CHIE_DAT_FLIT_TXNID_RANGE];
        automatic logic [1:0]  did  = txdatflit[`CHIE_DAT_FLIT_DATAID_RANGE];
        automatic bit is_data_snpresp = (dop == `CHIE_SNPRESPDATA) ||
                                        (dop == `CHIE_SNPRESPDATAPTL) ||
                                        (dop == `CHIE_SNPRESPDATAFWDED);
        automatic bit is_writeback    = (dop == 4'h2);   // CopyBackWrData

        if (is_data_snpresp || is_writeback) begin
            // We need the line address.  For SnpRespData the snoop
            // scoreboard (in chi_hnf_responder) captured the snoop's
            // addr; here we use the responder's snp_pending state
            // conservatively — good enough for single-snoop patterns.
            // For CopyBackWrData: the RN-F issued a WriteBack REQ; we
            // can look it up in req_addr_by_txnid[dtid].
            automatic logic [39:0] line = '0;
            automatic bit          have_line = 1'b0;
            if (is_writeback && req_addr_by_txnid.exists(dtid)) begin
                line = req_addr_by_txnid[dtid] & ~40'h3F;
                have_line = 1'b1;
            end
            else if (is_data_snpresp) begin
                // For SnpRespData the tid mirrors the snoop's TXNID; the
                // responder stashed the pending snoop's addr — take
                // that as the line.  (In this env only one snoop is
                // in flight at a time.)
                line = u_hnf.pending_snp_flit[`CHIE_SNP_FLIT_ADDR_RANGE] << 3;
                line = line & ~40'h3F;
                have_line = 1'b1;
            end
            if (have_line) begin
                // Skip lines the oracle can't model:
                //   * amo_touched — do_amo mutates the line at the HN-F but
                //     store_merge only tracks PCX_REQTYPE_STORE, so post-AMO
                //     wire data won't match the oracle's stale snapshot.
                //   * exerciser_touched — the directed SnpRespData exerciser
                //     runs with exerciser_active=1 which gates store_merge
                //     off; the oracle never sees the write.
                if (amo_touched.exists(line) || exerciser_touched.exists(line)) begin
                    // silently accept — line is architecturally unverifiable
                end
                else if (oracle_mem.exists(line) && oracle_mem[line].purged) begin
                    // Line was dropped locally while this transaction was
                    // still in flight — emitting data for it is correct.
                end
                else if (!oracle_mem.exists(line) || !oracle_mem[line].ever_loaded) begin
                    $error("[MEM_ORACLE] RN-F emitted data for line 0x%010h that was never loaded (op=0x%0h txnid=0x%h at %0t)",
                           line, dop, dtid, $time);
                end else begin
                    automatic logic [255:0] pay = txdatflit[`CHIE_DAT_FLIT_DATA_RANGE];
                    automatic int base = (did == 2'b10) ? 32 : 0;
                    automatic int mismatch_cnt = 0;
                    for (int i = 0; i < 32; i++) begin
                        if (oracle_mem[line].valid[base + i] &&
                            pay[8*i +: 8] !== oracle_mem[line].b[base + i]) begin
                            if (mismatch_cnt < 4)
                                $error("[MEM_ORACLE] byte mismatch line=0x%010h byte[%0d]=0x%02h expected=0x%02h (op=0x%0h dataid=%0d at %0t) — RN-F sent stale/wrong data",
                                       line, base + i, pay[8*i +: 8],
                                       oracle_mem[line].b[base + i],
                                       dop, did, $time);
                            mismatch_cnt++;
                        end
                    end
                end
            end
        end
    end

    // ── Egress check: load return to LSU on l15_transducer_val ─────
    // Capture outstanding load's (addr,size) when the transducer
    // accepts the header, then on the load-return beat compare the
    // 8-byte word delivered on l15_transducer_data_0 against the
    // oracle's expected bytes at that address.  Catches an internal
    // L1.5 corruption between cache-array read and CPU-side response
    // — symmetric to the SnpRespData check on the CHI side.
    // AMO returns are skipped: the returned value is the *old* pre-op
    // value, whereas the oracle already holds the post-op value.
    logic [39:0] pending_load_addr;
    logic [2:0]  pending_load_size;
    logic        pending_load_val;
    initial      pending_load_val = 1'b0;

    always @(posedge clk) if (rst_n) begin : load_capture
        if (transducer_l15_val && l15_transducer_header_ack &&
            transducer_l15_rqtype == `PCX_REQTYPE_LOAD &&
            !transducer_l15_invalidate_cacheline) begin
            pending_load_addr = transducer_l15_address;
            pending_load_size = transducer_l15_size;
            pending_load_val  = 1'b1;
        end
        else if (pending_load_val && l15_transducer_val &&
                 l15_transducer_returntype == `CPX_RESTYPE_LOAD &&
                 !mem_oracle_disabled) begin : load_return_check
            // Compare the 8-byte word containing the load address
            // against the oracle.  The L1.5 applies swendian64() to
            // the load-return path (SPARC-legacy big-endian internal
            // ↔ CVA6 native), so data_0 byte-order is reversed vs the
            // CHI-native bytes we cached in the oracle: got byte i
            // corresponds to oracle byte (woff + 7 - i).
            automatic logic [39:0] line = pending_load_addr & ~40'h3F;
            // The L1.5 returns a 16 B chunk: data_0 holds the first 8
            // bytes of the 16 B-ALIGNED chunk containing the address and
            // data_1 the second 8.  Indexing with the 8 B-aligned offset
            // (addr & 0x38) charged data_0 against the wrong half
            // whenever addr[3] was set -- loads of 0x..08 and 0x..00
            // return identical data_0, so the odd word reported a
            // mismatch the DUT was not responsible for.
            automatic int          woff = (pending_load_addr & 40'h30);
            // Miss detection during probe: did the L1.5 emit a TXREQ
            // between probe-LD dispatch and return?  If so the LD went
            // to CHI (i.e. missed) and returned HNF-arm bytes, not the
            // RN-F's cached state — a byte check is meaningless.  The
            // per-probe-word wrapper snapshots txreq_emit_cnt before
            // do_load and compares here via probe_txreq_snap.
            automatic bit probe_miss = probing &&
                                       (txreq_emit_cnt > probe_txreq_snap);
            if (probe_miss) begin
                probe_miss_cnt++;
            end
            else if (amo_touched.exists(line) || exerciser_touched.exists(line)) begin
                // Line is architecturally unverifiable — see MEM_ORACLE
                // egress-check comment above.
            end
            else if (oracle_mem.exists(line) && oracle_mem[line].ever_loaded) begin
                automatic int mismatch_cnt = 0;
                automatic bit is_probe = probing;
                // Both halves of the returned 16 B chunk are checked:
                // h=0 -> data_0 covers bytes woff..woff+7,
                // h=1 -> data_1 covers bytes woff+8..woff+15.
                for (int h = 0; h < 2; h++)
                for (int i = 0; i < 8; i++) begin
                    automatic int         bidx = woff + 8*h + 7 - i;
                    automatic logic [7:0] got  = h ? l15_transducer_data_1[8*i +: 8]
                                                   : l15_transducer_data_0[8*i +: 8];
                    automatic logic [7:0] exp  = oracle_mem[line].b[bidx];
                    if (oracle_mem[line].valid[bidx] && got !== exp) begin
                        if (mismatch_cnt < 4)
                            $error("[MEM_ORACLE]%s load-return byte mismatch addr=0x%010h  got data_%0d byte %0d = 0x%02h  expected 0x%02h  (line-byte[%0d], size=%0d, at %0t) — RN-F returned stale/wrong data to LSU",
                                   is_probe ? " PROBE" : "",
                                   pending_load_addr, h, i, got, exp,
                                   bidx, 1 << pending_load_size, $time);
                        mismatch_cnt++;
                    end
                end
                if (is_probe) probe_hit_cnt++;
            end
            pending_load_val = 1'b0;
        end
    end

    // ── CPU-port driver tasks ───────────────────────────────────────
    // Drive the L1.5 transducer interface for one memory op.  Waits
    // for l15_transducer_ack to confirm header acceptance, then waits
    // for l15_transducer_val to capture the returned data (if any).

    // ── CMO: dcache self-invalidation via transducer ────────────────
    // Drives PCX_REQTYPE_LOAD with transducer_l15_invalidate_cacheline=1.
    // L1.5 pipeline maps this to L15_REQTYPE_DCACHE_SELF_INVALIDATION
    // (see l15_rnf_pipeline.tmp.v line 770) which emits CHI CleanInvalid
    // on the wire.  Front B of the env expansion.
    task automatic do_cbo_inval(input logic [39:0] addr);
        bit got_hdrack;
        @(posedge clk);
        transducer_l15_rqtype               <= `PCX_REQTYPE_LOAD;
        transducer_l15_size                 <= 3'b011;
        transducer_l15_address              <= addr;
        transducer_l15_invalidate_cacheline <= 1'b1;
        transducer_l15_val                  <= 1'b1;
        @(posedge clk);
        got_hdrack = 1'b0;
        fork
            begin : ci_hdr_wait
                while (!l15_transducer_header_ack) @(posedge clk);  // pre-test: see comment on the ack wait
                got_hdrack = 1'b1;
                // Hold val until the request RETIRES -- see do_cbo_flush.
                while (!l15_transducer_ack) @(posedge clk);
            end
            begin : ci_hdr_to
                repeat (1000) @(posedge clk);
            end
        join_any
        disable ci_hdr_wait;
        disable ci_hdr_to;
        transducer_l15_val                  <= 1'b0;
        transducer_l15_invalidate_cacheline <= 1'b0;
        $display("[%0t] do_cbo_inval(0x%010h) hdrack=%b", $time, addr, got_hdrack);
        // Cache-Maintenance Invalidate drops the line locally.  The
        // next load MUST miss and re-fetch fresh contents from the HN-F
        // — which the auto-responder often serves as 0x0.  Purge the
        // oracle so MEM_ORACLE compares against whatever CompData
        // actually delivers, not the stale pre-invalidate snapshot.
        // Tombstone rather than delete: the CHI CleanInvalid is still in
        // flight at header-ack, and the RN-F legitimately emits
        // CopyBackWrData / SnpRespData for this line afterwards.  Deleting
        // the entry made the egress check report "never loaded" for those
        // perfectly correct flits.  Dropping every byte's valid bit stops
        // the oracle asserting stale contents; `purged` suppresses the
        // never-loaded complaint until a fill or store re-establishes it.
        if (got_hdrack) begin
            automatic logic [39:0] inv_line = addr & ~40'h3F;
            if (oracle_mem.exists(inv_line)) begin
                oracle_mem[inv_line].valid  = 64'h0;
                oracle_mem[inv_line].purged = 1'b1;
            end
            if (oracle_st_pend.exists(inv_line))
                oracle_st_pend.delete(inv_line);
        end
        @(posedge clk);
    endtask

    task automatic drive_idle();
        transducer_l15_rqtype               <= '0;
        transducer_l15_amo_op               <= '0;
        transducer_l15_nc                   <= 1'b0;
        transducer_l15_size                 <= 3'b011;   // 8B default
        transducer_l15_threadid             <= '0;
        transducer_l15_prefetch             <= 1'b0;
        transducer_l15_invalidate_cacheline <= 1'b0;
        transducer_l15_blockstore           <= 1'b0;
        transducer_l15_blockinitstore       <= 1'b0;
        transducer_l15_l1rplway             <= '0;
        transducer_l15_val                  <= 1'b0;
        transducer_l15_address              <= '0;
        transducer_l15_data                 <= '0;
        transducer_l15_data_next_entry      <= '0;
        transducer_l15_csm_data             <= '0;
    endtask

    // Shared status flag: last do_load's header-ack outcome.  Read by
    // the probe to bail as soon as the L1.5 stops accepting requests
    // (i.e. left wedged by the vector's tail activity).
    bit last_do_load_ack;
    initial last_do_load_ack = 1'b0;

    task automatic do_load(input logic [39:0] addr);
        bit got_ack, got_val;
        @(posedge clk);
        transducer_l15_rqtype  <= `PCX_REQTYPE_LOAD;
        transducer_l15_size    <= 3'b011;
        transducer_l15_address <= addr;
        transducer_l15_val     <= 1'b1;
        @(posedge clk);
        got_ack = 1'b0;
        fork
            begin : ld_ack_wait
                // Pre-test, NOT do-while: this DUT asserts
                // l15_transducer_ack in the SAME cycle as
                // l15_transducer_header_ack (traced on
                // hub_UC_AWAIT_RSP_WriteBackFull_S_SnpClean --
                // HDR and ACK share a timestamp on every
                // request).  A do-while advances a clock before
                // sampling, so it misses that coincident ack and
                // holds val high; the L1.5 then re-accepts the
                // still-valid request and acks again, 2-3x per
                // call.  Checking first exits immediately when
                // the two coincide, and still waits when a
                // multi-pass type genuinely retires later.
                while (!l15_transducer_ack) @(posedge clk);
                got_ack = 1'b1;
            end
            begin : ld_ack_to
                repeat (2000) @(posedge clk);
            end
        join_any
        disable ld_ack_wait;
        disable ld_ack_to;
        transducer_l15_val     <= 1'b0;
        last_do_load_ack = got_ack;
        $display("[%0t] do_load(0x%010h): REQ %s by L1.5",
                 $time, addr, got_ack ? "accepted" : "no-ack-timeout");
        if (!got_ack) begin
            @(posedge clk);
            return;
        end
        got_val = 1'b0;
        fork
            begin : ld_val_wait
                wait (l15_transducer_val);
                got_val = 1'b1;
            end
            begin : ld_val_to
                repeat (1000) @(posedge clk);
            end
        join_any
        disable ld_val_wait;
        disable ld_val_to;
        if (got_val)
            $display("[%0t] do_load(0x%010h): RESP returntype=%h data0=0x%016h",
                     $time, addr, l15_transducer_returntype, l15_transducer_data_0);
        else
            $display("[%0t] do_load(0x%010h): no-val-timeout (bounded skip)",
                     $time, addr);
        @(posedge clk);
    endtask

    // Stores in the OpenPiton convention drop `val` once
    // `l15_transducer_header_ack` fires (the L1.5 has accepted the
    // request into stage-1 of the pipeline).  Waiting on the full
    // `_ack` was wrong -- it only fires after the entire CHI
    // handshake completes, which for stores depends on the
    // responder + DUT MSHR / snoop-filter, causing 1114 of 6821
    // failures.
    task automatic do_store(input logic [39:0] addr, input logic [63:0] data);
        bit got_hdrack;
        @(posedge clk);
        transducer_l15_rqtype  <= `PCX_REQTYPE_STORE;
        transducer_l15_size    <= 3'b100;// 64-bit store //b011; // 32-bit store
        transducer_l15_address <= addr;
        transducer_l15_data    <= data;
        transducer_l15_val     <= 1'b1;
        @(posedge clk);
        got_hdrack = 1'b0;
        fork
            begin : st_hdrack_wait
                while (!l15_transducer_header_ack) @(posedge clk);  // pre-test: see comment on the ack wait
                got_hdrack = 1'b1;
                // Two-phase handshake: hold val + payload (incl. nc)
                // until the request RETIRES, not just until the header
                // is taken.  Multi-pass types re-read these inputs.
                // Pre-test, NOT do-while: this DUT asserts
                // l15_transducer_ack in the SAME cycle as
                // l15_transducer_header_ack (traced on
                // hub_UC_AWAIT_RSP_WriteBackFull_S_SnpClean --
                // HDR and ACK share a timestamp on every
                // request).  A do-while advances a clock before
                // sampling, so it misses that coincident ack and
                // holds val high; the L1.5 then re-accepts the
                // still-valid request and acks again, 2-3x per
                // call.  Checking first exits immediately when
                // the two coincide, and still waits when a
                // multi-pass type genuinely retires later.
                while (!l15_transducer_ack) @(posedge clk);
            end
            begin : st_hdrack_to
                repeat (2000) @(posedge clk);
            end
        join_any
        disable st_hdrack_wait;
        disable st_hdrack_to;
        transducer_l15_val     <= 1'b0;
        $display("[%0t] do_store(0x%010h, 0x%016h) hdrack=%b",
                 $time, addr, data, got_hdrack);
        @(posedge clk);
    endtask

    // Load with prefetch flag (transducer_l15_prefetch=1).  Exercises
    // the L15_REQTYPE_LOAD_PREFETCH predecoder branch and downstream
    // hint-only tag/data lookup path.  Same PCX_REQTYPE_LOAD, just
    // with the prefetch bit set; L1.5 pipeline should service it as a
    // hint.  No return-data checking (prefetch may or may not fill).
    task automatic do_load_prefetch(input logic [39:0] addr);
        bit got_ack;
        @(posedge clk);
        transducer_l15_rqtype   <= `PCX_REQTYPE_LOAD;
        transducer_l15_size     <= 3'b011;
        transducer_l15_address  <= addr;
        transducer_l15_prefetch <= 1'b1;
        transducer_l15_val      <= 1'b1;
        @(posedge clk);
        got_ack = 1'b0;
        fork
            begin : pf_ack_wait do @(posedge clk); while (!l15_transducer_ack); got_ack = 1'b1; end
            begin : pf_ack_to   repeat (2000) @(posedge clk); end
        join_any
        disable pf_ack_wait; disable pf_ack_to;
        transducer_l15_val      <= 1'b0;
        transducer_l15_prefetch <= 1'b0;
        last_do_load_ack = got_ack;
        $display("[%0t] do_load_prefetch(0x%010h): REQ %s", $time, addr,
                 got_ack ? "accepted" : "no-ack-timeout");
        @(posedge clk);
    endtask

    // Zicbom `cbo.flush` shape -- a full line flush (write back if dirty,
    // then invalidate).  The L1.5 decodes this from the ADDRESS rather
    // than a sideband bit: a PCX_REQTYPE_STORE whose address[39:32]
    // (`L15_ADDR_TYPE) equals `L15_ADDR_TYPE_LINE_FLUSH (8'hB3) predecodes
    // to L15_REQTYPE_LINE_FLUSH -- see l15_rnf_pipeline.tmp.v:791.
    // Exercises the flush walk: DCACHE_READ_FLUSH_WAY_IF_M, the
    // MESI/LRSC/WMT flush-way updates, and the NOC1/NOC3 writeback-if-
    // flush-M arms, none of which do_cbo_inval reaches.
    task automatic do_cbo_flush(input logic [39:0] addr);
        bit got_hdrack;
        automatic logic [39:0] flush_addr = {8'hB3, addr[31:0]};
        @(posedge clk);
        transducer_l15_rqtype  <= `PCX_REQTYPE_STORE;
        transducer_l15_size    <= 3'b011;
        transducer_l15_address <= flush_addr;
        transducer_l15_data    <= 64'h0;
        transducer_l15_val     <= 1'b1;
        @(posedge clk);
        got_hdrack = 1'b0;
        fork
            begin : fl_hdr_wait while (!l15_transducer_header_ack) @(posedge clk); got_hdrack = 1'b1; // hold val until the request RETIRES: the production driver
                // (wt_l15_adapter.sv) ties l15_val to the pending-request
                // FIFO with the ~header_ack_q term commented out, and gates
                // its arbiter on l15_ack -- so a real requester never drops
                // val on header_ack.  LINE_FLUSH re-reads the PCX inputs on
                // its PCX_INVAL_2/3/4 sub-block passes, ~110 ns after header_ack.
                while (!l15_transducer_ack) @(posedge clk); end
            begin : fl_hdr_to   repeat (1000) @(posedge clk); end
        join_any
        disable fl_hdr_wait; disable fl_hdr_to;
        transducer_l15_val     <= 1'b0;
        $display("[%0t] do_cbo_flush(0x%010h -> 0x%010h) hdrack=%b",
                 $time, addr, flush_addr, got_hdrack);
        // The flush walks all four sub-blocks; give it room to retire.
        repeat (40) @(posedge clk);
    endtask

    // Set-conflict eviction: issue L15_WAY_COUNT loads to distinct
    // lines that map to the *same* L1.5 set as `addr`, forcing LRU
    // replacement of the target line.  Cache geometry: 128 sets × 4
    // ways × 16 B/line → set-index stride = 128 × 16 = 0x800 bytes.
    // Adding k·0x800 to any address preserves the low 4 offset bits
    // and the 7 index bits, yielding a same-set conflict tag.  With 4
    // distinct conflicting tags the LRU way holding `addr` is evicted:
    //   * if the target line was dirty (UD) the L1.5 issues CHI
    //     WriteBackFull on the wire
    //   * if clean (UC/SC) the eviction is silent (no wire traffic)
    // The k=0 offset is the target itself and is intentionally skipped
    // so we don't reload it while trying to displace it.
    task automatic do_set_conflict(input logic [39:0] addr);
        automatic logic [39:0] conflict_stride = 40'h800;
        $display("[%0t] do_set_conflict(0x%010h): %0d same-set loads",
                 $time, addr, `L15_WAY_COUNT);
        for (int k = 1; k <= `L15_WAY_COUNT; k++) begin
            automatic logic [39:0] conflict_addr = addr + (k * conflict_stride);
            // Between conflict loads, yield up to 200 cycles for the
            // L1.5 to drain any pending RX snoop.  A 4-load burst
            // otherwise stacks against the 500-cycle SNP_MON timeout
            // because each ReadClean holds the pipeline while snoop
            // response drains behind it.
            begin : drain_snp_before_next_load
                automatic int drain_budget = 200;
                automatic bit any_pending;
                while (drain_budget > 0) begin
                    any_pending = 1'b0;
                    for (int i = 0; i < SNP_MON_DEPTH; i++)
                        if (snp_mon_valid[i]) any_pending = 1'b1;
                    if (!any_pending) break;
                    @(posedge clk);
                    drain_budget--;
                end
            end
            do_load(conflict_addr);
        end
    endtask

    // Store with block-init-store flag (transducer_l15_blockinitstore=1).
    // Zicboz `cbo.zero` shape — bulk-zero a cache line.  Exercises the
    // L1.5 block-init-store path and its downstream tag/data allocation.
    task automatic do_cbo_zero(input logic [39:0] addr);
        bit got_hdrack;
        @(posedge clk);
        transducer_l15_rqtype           <= `PCX_REQTYPE_STORE;
        transducer_l15_size             <= 3'b011;
        transducer_l15_address          <= addr;
        transducer_l15_data             <= 64'h0;
        transducer_l15_blockinitstore   <= 1'b1;
        transducer_l15_val              <= 1'b1;
        @(posedge clk);
        got_hdrack = 1'b0;
        fork
            begin : cz_hdr_wait while (!l15_transducer_header_ack) @(posedge clk); got_hdrack = 1'b1; // hold val until the request RETIRES: the production driver
                // (wt_l15_adapter.sv) ties l15_val to the pending-request
                // FIFO with the ~header_ack_q term commented out, and gates
                // its arbiter on l15_ack -- so a real requester never drops
                // val on header_ack.  LINE_FLUSH re-reads the PCX inputs on
                // its PCX_INVAL_2/3/4 sub-block passes, ~110 ns after header_ack.
                while (!l15_transducer_ack) @(posedge clk); end
            begin : cz_hdr_to   repeat (1000) @(posedge clk); end
        join_any
        disable cz_hdr_wait; disable cz_hdr_to;
        transducer_l15_val              <= 1'b0;
        transducer_l15_blockinitstore   <= 1'b0;
        $display("[%0t] do_cbo_zero(0x%010h) hdrack=%b", $time, addr, got_hdrack);
        @(posedge clk);
    endtask

    // Non-cacheable LOAD.  Drives PCX_REQTYPE_LOAD with transducer_l15_nc=1.
    // The L1.5's write-buffer / NC-load path emits CHI ReadClean-with-
    // noncacheable-attribute (data-side) or ReadNoSnp (IFILL-NC).  No
    // cache install; oracle is not updated on the return (bytes come
    // straight from HN-F).
    task automatic do_load_nc(input logic [39:0] addr);
        bit got_ack;
        @(posedge clk);
        transducer_l15_rqtype  <= `PCX_REQTYPE_LOAD;
        transducer_l15_size    <= 3'b011;
        transducer_l15_address <= addr;
        transducer_l15_nc      <= 1'b1;
        transducer_l15_val     <= 1'b1;
        @(posedge clk);
        got_ack = 1'b0;
        fork
            begin : nc_ld_ack_wait
                // Pre-test, NOT do-while: this DUT asserts
                // l15_transducer_ack in the SAME cycle as
                // l15_transducer_header_ack (traced on
                // hub_UC_AWAIT_RSP_WriteBackFull_S_SnpClean --
                // HDR and ACK share a timestamp on every
                // request).  A do-while advances a clock before
                // sampling, so it misses that coincident ack and
                // holds val high; the L1.5 then re-accepts the
                // still-valid request and acks again, 2-3x per
                // call.  Checking first exits immediately when
                // the two coincide, and still waits when a
                // multi-pass type genuinely retires later.
                while (!l15_transducer_ack) @(posedge clk);
                got_ack = 1'b1;
            end
            begin : nc_ld_ack_to
                repeat (2000) @(posedge clk);
            end
        join_any
        disable nc_ld_ack_wait;
        disable nc_ld_ack_to;
        transducer_l15_val     <= 1'b0;
        transducer_l15_nc      <= 1'b0;
        last_do_load_ack = got_ack;
        $display("[%0t] do_load_nc(0x%010h): REQ %s by L1.5",
                 $time, addr, got_ack ? "accepted" : "no-ack-timeout");
        if (!got_ack) begin
            @(posedge clk);
            return;
        end
        // Bounded wait for return; NC LD response follows the same
        // l15_transducer_val handshake.
        fork
            begin : nc_ld_val_wait
                wait (l15_transducer_val);
            end
            begin : nc_ld_val_to
                repeat (1000) @(posedge clk);
            end
        join_any
        disable nc_ld_val_wait;
        disable nc_ld_val_to;
        @(posedge clk);
    endtask

    // Non-cacheable STORE (writethrough).  Drives PCX_REQTYPE_STORE
    // with transducer_l15_nc=1.  The L1.5 pipeline routes this via
    // WRITETHROUGH_REQUEST → CHI WriteNoSnpPtl.  No cache mutation.
    task automatic do_store_nc(input logic [39:0] addr, input logic [63:0] data);
        bit got_hdrack;
        @(posedge clk);
        transducer_l15_rqtype  <= `PCX_REQTYPE_STORE;
        transducer_l15_size    <= 3'b011;
        transducer_l15_address <= addr;
        transducer_l15_data    <= data;
        transducer_l15_nc      <= 1'b1;
        transducer_l15_val     <= 1'b1;
        @(posedge clk);
        got_hdrack = 1'b0;
        fork
            begin : nc_st_hdrack_wait
                while (!l15_transducer_header_ack) @(posedge clk);  // pre-test: see comment on the ack wait
                got_hdrack = 1'b1;
                // Two-phase handshake: hold val + payload (incl. nc)
                // until the request RETIRES, not just until the header
                // is taken.  Multi-pass types re-read these inputs.
                // Pre-test, NOT do-while: this DUT asserts
                // l15_transducer_ack in the SAME cycle as
                // l15_transducer_header_ack (traced on
                // hub_UC_AWAIT_RSP_WriteBackFull_S_SnpClean --
                // HDR and ACK share a timestamp on every
                // request).  A do-while advances a clock before
                // sampling, so it misses that coincident ack and
                // holds val high; the L1.5 then re-accepts the
                // still-valid request and acks again, 2-3x per
                // call.  Checking first exits immediately when
                // the two coincide, and still waits when a
                // multi-pass type genuinely retires later.
                while (!l15_transducer_ack) @(posedge clk);
            end
            begin : nc_st_hdrack_to
                repeat (2000) @(posedge clk);
            end
        join_any
        disable nc_st_hdrack_wait;
        disable nc_st_hdrack_to;
        transducer_l15_val     <= 1'b0;
        transducer_l15_nc      <= 1'b0;
        $display("[%0t] do_store_nc(0x%010h, 0x%016h) hdrack=%b",
                 $time, addr, data, got_hdrack);
        @(posedge clk);
    endtask

    // Rotating AMO-opcode picker for SW_enqueue_AtomicLoad / _AtomicStore.
    // Cycles through the 9 opcodes {ADD, AND, OR, XOR, MAX, MAXU, MIN,
    // MINU, SWAP} so the txreq_encoder's per-opcode branches all get
    // exercised across the vector set — including the CHI AtomicSwap
    // (0x38) which routes through L15_REQTYPE_SWP_LOADSTUB.
    int amo_rotate_idx;
    initial amo_rotate_idx = $urandom() % 9;
    function automatic logic [`L15_AMO_OP_WIDTH-1:0] next_amo_op();
        logic [`L15_AMO_OP_WIDTH-1:0] ops [9] = '{
            `L15_AMO_OP_ADD, `L15_AMO_OP_AND, `L15_AMO_OP_OR,   `L15_AMO_OP_XOR,
            `L15_AMO_OP_MAX, `L15_AMO_OP_MAXU, `L15_AMO_OP_MIN, `L15_AMO_OP_MINU,
            `L15_AMO_OP_SWAP
        };
        automatic logic [`L15_AMO_OP_WIDTH-1:0] op = ops[amo_rotate_idx % 9];
        amo_rotate_idx++;
        return op;
    endfunction

    // Store-variant rotation: plain ST vs cbo.zero (blockinitstore-
    // driven).
    int st_variant_idx;
    initial st_variant_idx = $urandom() % 2;

    // do_amo: AtomicLoad-shape returns the old value via _val;
    // AtomicStore-shape doesn't (no result).  `expect_val` controls
    // whether we wait for the load-return half.  Waiting on _val when
    // the L1.5 won't ever drive it is the dominant cause of do_amo
    // hangs in the vector sweep (3428 of 6821 failures).
    task automatic do_amo(input logic [39:0] addr,
                          input logic [`L15_AMO_OP_WIDTH-1:0] amo_op,
                          input logic [63:0] data,
                          input bit          expect_val = 1'b1);
        bit got_header_ack;
        // AMOs mutate memory at the HN-F and may or may not install the
        // line in the L1.5 depending on the specific opcode + response
        // shape (AtomicLoad returns CompData; AtomicStore doesn't).
        // rxdat_capture and store_merge are gated on CompData / STORE
        // req-type respectively — neither cleanly represents an AMO's
        // post-op state.  Rather than modelling every AMO's exact
        // side effect, mark the target line as unverifiable so the
        // post-vector probe skips it.  Analogous to exerciser_active.
        begin : mark_amo_line
            automatic logic [39:0] amo_line = addr & ~40'h3F;
            amo_touched[amo_line] = 1'b1;
        end
        @(posedge clk);
        transducer_l15_rqtype  <= `PCX_REQTYPE_AMO;
        transducer_l15_amo_op  <= amo_op;
        transducer_l15_size    <= 3'b011;
        transducer_l15_address <= addr;
        transducer_l15_data    <= data;
        transducer_l15_val     <= 1'b1;
        @(posedge clk);
        // Bounded header-ack wait: the L1.5 pipeline serializes AMOs;
        // a back-to-back AMO can wait for the previous one to drain.
        got_header_ack = 1'b0;
        fork
            begin : amo_hdrack_wait
                while (!l15_transducer_header_ack) @(posedge clk);  // pre-test: see comment on the ack wait
                got_header_ack = 1'b1;
                // Two-phase handshake: hold val + payload until the
                // request RETIRES (l15_transducer_ack), not just until
                // the header is taken.  Atomics are multi-pass through
                // PCX_INVAL_2/3/4 and re-read the PCX inputs on later
                // passes; releasing early makes the pipeline re-decode
                // with stale fields.
                // Pre-test, NOT do-while: this DUT asserts
                // l15_transducer_ack in the SAME cycle as
                // l15_transducer_header_ack (traced on
                // hub_UC_AWAIT_RSP_WriteBackFull_S_SnpClean --
                // HDR and ACK share a timestamp on every
                // request).  A do-while advances a clock before
                // sampling, so it misses that coincident ack and
                // holds val high; the L1.5 then re-accepts the
                // still-valid request and acks again, 2-3x per
                // call.  Checking first exits immediately when
                // the two coincide, and still waits when a
                // multi-pass type genuinely retires later.
                while (!l15_transducer_ack) @(posedge clk);
            end
            begin : amo_hdrack_timeout
                repeat (2000) @(posedge clk);
            end
        join_any
        disable amo_hdrack_wait;
        disable amo_hdrack_timeout;
        transducer_l15_val     <= 1'b0;
        $display("[%0t] do_amo(addr=0x%010h op=%h data=0x%016h) hdrack=%b",
                 $time, addr, amo_op, data, got_header_ack);
        if (!got_header_ack) begin
            // L1.5 didn't accept the AMO -- give up, move on.
            @(posedge clk);
            return;
        end
        if (expect_val) begin
            // Bounded wait -- if the L1.5 silently drops the AMO
            // result (rare, but possible in this IP-level config),
            // give up after a generous slot.
            fork
                begin : amo_wait
                    wait (l15_transducer_val);
                    $display("[%0t]   atomic result returntype=%h data0=0x%016h",
                             $time, l15_transducer_returntype, l15_transducer_data_0);
                end
                begin : amo_timeout
                    repeat (500) @(posedge clk);
                    $display("[%0t]   atomic result did not arrive (bounded skip)",
                             $time);
                end
            join_any
            disable amo_wait;
            disable amo_timeout;
        end
        @(posedge clk);
    endtask

    // ── Vector-file replay driver (global Env queue + background pop) ─
    // The earlier bounded look-ahead missed Env_* directives that the
    // Murphi BFS placed after the next SW_enqueue in the vector,
    // causing auto-response defaults to win and downstream loads to
    // hang.  Replaced with a global FIFO:
    //
    //   1. Pre-parse the entire vector into a queue of DRIVE events
    //      (preserving order).
    //   2. Pull all Env_response_* events into a separate response
    //      queue `g_env_resp_q`.  Env_snoop_* events get injected
    //      eagerly in vector order (non-blocking).
    //   3. A background process watches `txreqflitv` and pops the
    //      next Env_response from `g_env_resp_q` to program the
    //      responder -- so every REQ the DUT issues gets matched
    //      with the vector's Nth Env_response, regardless of how
    //      the BFS ordered SWs vs Envs around it.
    //   4. The main thread then drives SW_enqueue events sequentially
    //      via dispatch_sw (which blocks per-op).  CMO/replacement
    //      ops still get skipped.
    string g_env_resp_q[$];          // global FIFO of pending Env_response_*
    int    g_env_resp_pop_count;
    int    g_env_resp_push_count;

    // Background popper: each time the DUT issues TXREQ, dequeue the
    // next Env_response_* and program the responder.  Falls back to
    // opcode-aware default if the queue is empty.
    initial begin : env_resp_popper
        string ev;
        logic [6:0] tx_opcode;
        @(posedge rst_n);
        forever begin
            @(posedge clk);
            if (txreqflitv && !u_hnf.have_directive) begin
                tx_opcode = txreqflit[`CHIE_REQ_FLIT_OPCODE_RANGE];
                if (g_env_resp_q.size() > 0) begin
                    ev = g_env_resp_q.pop_front();
                    g_env_resp_pop_count++;
                    if (model_trace_en)
                        $display("[MTRACE] %0t POP ev=%s op=0x%02h", $time, ev, tx_opcode);
                    // Atomic-load-shape REQ override: the L1.5 always
                    // emits CHI AtomicLoad (0x30/0x38) for AMO PCX
                    // requests, so a vector-prescribed DBIDResp+Comp
                    // (for AtomicStore semantics) leaves the L1.5
                    // hanging waiting for CompData.  Force
                    // DBIDRESP_COMPDATA in that mismatch.
                    // CopyBack writes (WriteEvictFull 0x15, WriteCleanFull
                    // 0x17, WriteBackPtl 0x1a, WriteBackFull 0x1b) must be
                    // completed with a single CompDBIDResp.  The split
                    // DBIDResp-then-Comp shape is legal only for
                    // WriteUnique / WriteNoSnp.  Sending the split for a
                    // CopyBack write is illegal stimulus and wedges the
                    // DUT: rx_control retires the REQ entry when it sends
                    // WriteData after the DBIDResp, so the trailing Comp
                    // finds req_valid=0 and self-loops in REQ_CHECK with
                    // noc_in_rdy=0, blocking every later snoop (SNP_MON).
                    // The project's own HN-F never splits here either --
                    // hnf_mshr_ctl.v:2411 sets comp_rdy and dbid_rdy in
                    // the same cycle for the WB/WC/WE family, so the
                    // response mux always picks CompDBIDResp.
                    // The vector's Env_* directives are consumed FIFO,
                    // one per TXREQ, but the model's step order and the
                    // DUT's actual REQ emission drift apart, so the
                    // popped directive routinely belongs to a different
                    // transaction class than the REQ in front of us.
                    // Sending a shape that is illegal for the REQ's
                    // opcode wedges the DUT -- a CompData answering a
                    // WriteNoSnpPtl walks rx_control into
                    // RECEIVING_DATA -> WAITING_ACK, where it parks with
                    // noc_in_rdy=0 and blocks every later snoop
                    // (SNP_MON).  Two such cases were patched
                    // individually here; this dispatches on the REQ
                    // opcode class instead, and lets the popped event
                    // choose only WITHIN the shapes legal for that class.
                    // Opcode values from cache/rnf_link/include/chie_defines.v.
                    case (tx_opcode) inside
                        // Reads -> CompData.  Murphi distinguishes only
                        // clean vs dirty; the L1 post-state comes from
                        // (tx_op x env).  ReadClean lands in SC/SD,
                        // ReadUnique etc. in UC/UD -- a fixed mapping
                        // here previously kept cp_prev_state/
                        // cp_next_state out of the shared bins.
                        7'h01, 7'h02, 7'h04, 7'h07, 7'h26: begin
                            if (ev == "Env_CompData_dirty") begin
                                if (tx_opcode == 7'h02)
                                    u_hnf.set_next_response_compdata_sd_pd(256'hDEADBEEF);
                                else
                                    u_hnf.set_next_response_compdata_ud_pd(256'hDEADBEEF);
                            end
                            else begin
                                if (tx_opcode == 7'h02)
                                    u_hnf.set_next_response_compdata_sc(256'hCAFEBABE);
                                else
                                    u_hnf.set_next_response_compdata_uc(256'hCAFEBABE);
                            end
                        end
                        // Dataless coherence ops -> Comp.
                        7'h08, 7'h09, 7'h0a, 7'h0b, 7'h0c, 7'h0d:
                            u_hnf.set_next_response_comp();
                        // CopyBack writes -> CompDBIDResp ONLY (see the
                        // auto-responder note; the split shape is not a
                        // legal completion for these and wedges
                        // rx_control's REQ_CHECK).
                        7'h15, 7'h17, 7'h1a, 7'h1b:
                            u_hnf.set_next_response_compdbidresp();
                        // WriteUnique / WriteNoSnp -> both shapes legal;
                        // let the directive pick so the split and
                        // combined phase-sequence bins both stay live.
                        7'h18, 7'h19, 7'h1c, 7'h1d: begin
                            if (ev == "Env_CompDBIDResp_for_Write")
                                u_hnf.set_next_response_compdbidresp();
                            else
                                u_hnf.set_next_response_dbidresp_then_comp();
                        end
                        // AtomicStore -> operand in, no data back.
                        [7'h28:7'h2f]:
                            u_hnf.set_next_response_dbidresp_then_comp();
                        // AtomicLoad / Swap / Compare -> operand in,
                        // old value back as CompData.
                        [7'h30:7'h39]:
                            u_hnf.set_next_response_dbidresp_then_compdata(
                                256'h12345678_9ABCDEF0);
                        default:
                            program_env_response(ev);
                    endcase
                end
            end
        end
    end

    // ── Post-vector data-integrity probe ────────────────────────────
    // For each 64B line the vector ever touched (oracle_mem key with
    // ever_loaded=1), issue 8 synthetic 8B loads at offsets 0,8,…,56 via
    // the transducer.  The existing load_return_check compares delivered
    // bytes against the oracle; a mismatch on hit reveals persistent
    // stale data in the RN-F's cache (the RNF_COHERENCE_BUG.md failure
    // class — a "lost dirty store").
    //
    // Bail as soon as the first probe on a line MISSes: the L1.5's
    // linefill reloads from the HNF stub (whose response bytes are
    // arbitrary), so subsequent hits on the reloaded line would compare
    // against fresh HNF bytes rather than the RN-F's original cached
    // state and produce false positives.  A miss means the line is no
    // longer resident — expected after eviction, not a bug.
    // Returns 0 if the L1.5 stopped accepting requests mid-probe (wedged
    // from the vector's tail activity), so probe_all_dirty_lines can
    // give up and mark all remaining lines as skipped.
    task automatic probe_line_words(input logic [39:0] line_addr,
                                    output bit          ok);
        int      offs [8] = '{0, 8, 16, 24, 32, 40, 48, 56};
        ok = 1'b1;
        for (int k = 0; k < 8; k++) begin : one_word
            automatic logic [39:0] a = line_addr + offs[k];
            // Pre-arm HNF with a benign CompData_UC so a probe miss
            // still returns (with unchecked bytes) instead of hanging.
            u_hnf.set_next_response_compdata_uc(256'h0);
            // Snapshot txreq count so load_return_check can distinguish
            // hit (no TXREQ) from miss (TXREQ emitted for reload).
            probe_txreq_snap = txreq_emit_cnt;
            begin : probe_word
                automatic int miss_before = probe_miss_cnt;
                do_load(a);
                if (!last_do_load_ack) begin
                    $display("[%0t] [PROBE] L1.5 wedged (no-ack on line 0x%010h word %0d) — aborting probe",
                             $time, line_addr, k);
                    probe_skip_cnt += (8 - k);
                    ok = 1'b0;
                    return;
                end
                if (probe_miss_cnt > miss_before) begin
                    $display("[%0t] [PROBE] line 0x%010h evicted (miss at word %0d) — skipping remaining offsets",
                             $time, line_addr, k);
                    probe_skip_cnt += (8 - k - 1);
                    return;
                end
            end
        end
    endtask

    // Write-visibility probe: LD → ST → LD-back triple at end of vector.
    // Semantics:
    //   1. do_load(addr)   → if L1.5 misses, RN-F emits ReadClean;
    //                        pre-armed HN-F CompData installs line;
    //                        oracle updates via rxdat_capture.
    //                        If hits, no CHI, no oracle change.
    //   2. do_store(addr, PATTERN) → hart ST.  If line UC, StoreHit_UC_to_UD
    //                        promotes locally; if SC, RN-F emits ReadUnique
    //                        upgrade (pre-armed HN-F responds).
    //                        store_merge captures PATTERN into oracle.
    //   3. do_load(addr)   → hits cached line (now UD).  load_return_check
    //                        compares returned bytes vs oracle's PATTERN.
    //                        Mismatch → [MEM_ORACLE] fires, sweep classifier
    //                        promotes to FAIL.
    //
    // Guarded on: L1.5 responsiveness (last_do_load_ack) + probing quiescent.
    // Probes the vector's default line 0x2000 so the vector's own end-state
    // is the initial condition (as the paper argues).
    task automatic write_visibility_probe();
        logic [39:0] addr = 40'h00_0000_2000;
        logic [63:0] pat  = 64'hFACE_CAFE_0BAD_F00D;
        int          miss_before, miss_after;
        if (wv_probe_disabled || mem_oracle_disabled) return;
        // Wait a bit for outstanding activity to settle before injecting.
        repeat (100) @(posedge clk);
        $display("[%0t] [WV_PROBE] BEGIN addr=0x%010h", $time, addr);

        // Step 1 — install (or confirm cached).  Arm HN-F in case of miss.
        u_hnf.set_next_response_compdata_uc(256'hAAAA_BBBB);
        do_load(addr);
        if (!last_do_load_ack) begin
            $display("[%0t] [WV_PROBE] SKIP: L1.5 wedged on step 1", $time);
            wv_probe_skipped_cnt++;
            return;
        end
        repeat (30) @(posedge clk);

        // Step 2 — hart ST.  Line may be SC/UC/UD after step 1; pre-arm
        // HN-F for a potential ReadUnique upgrade if the store hits SC.
        u_hnf.set_next_response_compdata_ud_pd(256'hAAAA_BBBB);
        do_store(addr, pat);
        repeat (100) @(posedge clk);

        // Step 3 — hart LD-back.  Cache should now hold pat's bytes.
        // load_return_check compares vs oracle (which store_merge just
        // updated with pat).  A byte-mismatch fires [MEM_ORACLE].
        //
        // Guard against probe-triggered miss falsely reporting: use the
        // existing probing flag so a MISS on step 3 is silently skipped
        // (an evicted line means oracle can't verify anything meaningful).
        probing        = 1'b1;
        probe_txreq_snap = txreq_emit_cnt;
        miss_before    = probe_miss_cnt;
        do_load(addr);
        miss_after     = probe_miss_cnt;
        probing        = 1'b0;
        if (miss_after > miss_before) begin
            $display("[%0t] [WV_PROBE] END: LD-back missed (line evicted); indeterminate",
                     $time);
        end else begin
            $display("[%0t] [WV_PROBE] END: LD-back hit; MEM_ORACLE check delivered", $time);
        end
        wv_probe_fired_cnt++;
    endtask

    task automatic probe_all_dirty_lines();
        logic [39:0] key;
        int          n_lines;
        if (probe_disabled || mem_oracle_disabled) return;
        // Wait until the L1.5 is idle (no header pending, no outstanding
        // TX transactions from the vector's tail activity).
        repeat (50) @(posedge clk);
        probing        = 1'b1;
        probe_hit_cnt  = 0;
        probe_miss_cnt = 0;
        probe_skip_cnt = 0;
        n_lines        = 0;
        if (oracle_mem.first(key)) do begin
            // NOTE: with the current vector set this post-vector probe
            // reports 0 words compared.  That is a property of the
            // stimulus, not a broken check: every vector ends with
            // repeated invalidating snoops on the target line, so the
            // probe's own loads MISS (probe_miss) and the miss path
            // deliberately skips comparison -- a non-resident line tells
            // us nothing.  Re-seeding the oracle from the responder's
            // memory here does NOT help, because the miss happens before
            // any comparison.  Live checking comes from the per-load
            // load_return_check and from write_visibility_probe instead.
            // Probe only lines with at least one byte the oracle actually
            // knows -- ever_loaded alone admits lines whose bytes are all
            // unknown or have been purged, which produces mismatch reports
            // against X rather than a real integrity check.
            if (oracle_mem[key].ever_loaded && |oracle_mem[key].valid &&
                !amo_touched.exists(key)) begin
                automatic bit line_ok;
                $display("[%0t] [PROBE] line 0x%010h — 8-word integrity check", $time, key);
                probe_line_words(key, line_ok);
                n_lines++;
                if (!line_ok) begin
                    // L1.5 is not accepting requests — no point probing
                    // remaining lines this vector.
                    break;
                end
            end
            else if (amo_touched.exists(key))
                $display("[%0t] [PROBE] line 0x%010h — skipped (AMO-touched, unverifiable)",
                         $time, key);
        end while (oracle_mem.next(key));
        probing = 1'b0;
        $display("[PROBE] === %0d lines probed, hits=%0d, miss=%0d, skipped=%0d ===",
                 n_lines, probe_hit_cnt, probe_miss_cnt, probe_skip_cnt);
    endtask

    // ── Directed race sweep (+RACE_SWEEP) ──────────────────────────
    // cg_race_intersections samples on "snoop arrives while a
    // transaction is outstanding"; its gate compares no addresses, so
    // any snoop during any live transaction counts.  The Murphi vectors
    // reach only 26 of the 100 x_race cells because they hammer one
    // address: a load to a resident line HITS and issues no ReadClean,
    // so cp_tx_op_during_snoop.ReadClean and .AtomicLoad never fire and
    // cap the cross at 50 before anything else.
    //
    // This walks the cross directly.  Each iteration uses a FRESH line
    // so the operation is guaranteed to miss and put a REQ on the wire,
    // holds the response long enough to observe the phase, waits for the
    // target phase, then injects the snoop.  Independent of the model,
    // so it is immune to the model/DUT divergence the trigger misses
    // measure.
    task automatic wait_for_phase(input string want, input int unsigned lim,
                                  output bit ok);
        int unsigned c;
        c  = 0;
        ok = 1'b0;
        while (c < lim) begin
            if (tb_tx_phase == want) begin ok = 1'b1; return; end
            @(posedge clk);
            c++;
        end
    endtask

    task automatic race_launch_op(input int op_i, input logic [39:0] a);
        case (op_i)
            0: do_load(a);                                   // -> ReadClean
            1: do_store(a, 64'hACE0_0001_D0D0_CAFE);         // -> ReadUnique
            2: begin                                          // -> WriteBackFull
                   do_store(a, 64'hBEEF_0002_D0D0_CAFE);
                   do_cbo_flush(a);
               end
            3: do_amo(a, next_amo_op(), 64'h0000_0003_AAAA_BBBB, 1'b1); // AtomicLoad
            default: ;
        endcase
    endtask

    task automatic race_sweep();
        string phases[5];
        logic [39:0] a;
        bit    ok;
        int    idx, n_hit, n_skip;
        phases[0] = "TX_AWAIT_RSP";
        phases[1] = "TX_AWAIT_DATA_SEND";
        phases[2] = "TX_AWAIT_COMP";
        phases[3] = "TX_AWAIT_COMPACK_CLEAN";
        phases[4] = "TX_AWAIT_COMPACK_DIRTY";
        idx = 0; n_hit = 0; n_skip = 0;
        $display("[%0t] === RACE_SWEEP start ===", $time);
        // Hold responses long enough that the phase is observable and a
        // snoop can be injected inside it.  Well under SNP_MON's 500.
        u_hnf.set_response_delay(120);

        for (int op_i = 0; op_i < 4; op_i++)
        for (int ph   = 0; ph   < 5; ph++)
        for (int sn   = 0; sn   < 5; sn++) begin
            // Fresh 64 B line per cell -> guaranteed miss -> REQ issues.
            a = 40'h00_0040_0000 + (idx << 6);
            idx++;
            // Dirty CompData for the *_DIRTY phase, clean otherwise, so
            // reads can reach both CompAck arms.
            if (ph == 4) u_hnf.set_next_response_compdata_ud_pd(256'hDEADBEEF);
            else         u_hnf.set_next_response_compdata_uc(256'hCAFEBABE);

            fork
                race_launch_op(op_i, a);
            join_none

            wait_for_phase(phases[ph], 400, ok);
            if (ok) begin
                case (sn)
                    0: u_hnf.inject_snoop_clean       ({1'b0, a});
                    1: u_hnf.inject_snoop_unique      ({1'b0, a});
                    2: u_hnf.inject_snoop_makeinvalid ({1'b0, a});
                    3: u_hnf.inject_snoop_cleaninvalid({1'b0, a});
                    4: u_hnf.inject_snoop_shared      ({1'b0, a});
                endcase
                n_hit++;
            end
            else n_skip++;

            // Let the transaction and snoop response drain before the
            // next cell, so races do not pile up across iterations.
            repeat (250) @(posedge clk);
        end

        u_hnf.set_response_delay(0);
        $display("[%0t] === RACE_SWEEP done: %0d cells raced, %0d phase-unreached ===",
                 $time, n_hit, n_skip);
    endtask

    task automatic replay_vector(input string path);
        int fd;
        string line, event_name;
        string drv_events[$];
        string drv_trigs[$];      // parallel to drv_events; "" when absent
        int    n_drive, i;
        logic [39:0] addr = 40'h00_0000_2000;
        logic [63:0] dummy_data = 64'hDEAD_BEEF_F00D_CAFE;

        fd = $fopen(path, "r");
        if (fd == 0) begin
            $display("[REPLAY] cannot open vector file: %s", path);
            return;
        end
        $display("[REPLAY] === replaying %s ===", path);

        // Deterministic per-vector atomic-variant offset.
        //
        // amo_rotate_idx used to start at $urandom()%9, so which of the
        // nine AMO variants got exercised from which L1 state depended
        // on -sv_seed.  That made part of x_state_op a lottery: the
        // constrained-random baseline reached <UC,AtomicLoad_ADD> and
        // <UC,AtomicSwap> while the directed set missed them, purely on
        // the draw.  Model-directed generation should be reproducible,
        // so derive the offset from the vector name instead -- each
        // vector's rotation is then fixed, and the offsets spread
        // uniformly over all nine variants across the 832-vector set.
        begin
            int h;
            h = 0;
            for (int i = 0; i < path.len(); i++)
                h += path[i];
            amo_rotate_idx = h % 9;
        end

        // Reset the global env-response queue for this vector.
        g_env_resp_q.delete();
        g_env_resp_push_count = 0;
        g_env_resp_pop_count  = 0;

        // Pass 1: parse, keep DRIVE events only, separated by class.
        while (!$feof(fd)) begin
            void'($fgets(line, fd));
            if (line.len() < 3 || line[0] == "#") continue;
            if (!contains_substr(line, "DRIVE")) continue;
            event_name = extract_event_token(line);
            drv_events.push_back(event_name);
            drv_trigs.push_back(extract_trigger(line));
            if (is_env_response(event_name)) begin
                g_env_resp_q.push_back(event_name);
                g_env_resp_push_count++;
            end
        end
        $fclose(fd);
        n_drive = drv_events.size();

        // Pass 2: walk events in order, only dispatching SW + snoop.
        // Env_response_* events are consumed by the background popper.
        for (i = 0; i < n_drive; i++) begin
            event_name = drv_events[i];
            if (is_sw_enqueue(event_name)) begin
                await_trigger(drv_trigs[i]);
                // do_load / do_store / do_amo block until the response
                // comes back, so a blocking dispatch guarantees TX_IDLE
                // by the time the next event fires and NO race can ever
                // be produced -- which is why model-derived race vectors
                // landed 5 of 100 cells.  The vector already says when
                // that is wrong: if the NEXT event's precondition needs a
                // transaction in flight, this one must stay outstanding,
                // so launch it and let the next event's await_trigger
                // synchronise on the phase instead.
                if (i + 1 < n_drive && trig_needs_tx(drv_trigs[i+1]))
                    fork dispatch_sw(event_name, addr, dummy_data); join_none
                else
                    dispatch_sw(event_name, addr, dummy_data);
            end
            else if (is_env_snoop(event_name)) begin
                await_trigger(drv_trigs[i]);
                inject_env_snoop(event_name, addr);
            end
            // Env_response_* skipped here -- popped on TXREQ instead.
            repeat (5) @(posedge clk);
        end

        // ── +PREFIX_ONLY guard: skip all post-replay tail activity so
        //    the state at $finish is a clean "hub" reachable via BFS
        //    prefix only.  Prefix-shared driver checkpoints here and
        //    restores this state for each downstream target tail.
        if ($test$plusargs("PREFIX_ONLY")) begin
            $display("[REPLAY] PREFIX_ONLY: skipping exerciser/probes; hub reached at %0t", $time);
            return;
        end

        // ── Directed SnpRespData exerciser ──────────────────────────
        // Murphi vectors typically invalidate dirty lines (via
        // CleanInvalid/Evict) BEFORE snoops arrive, so the L1.5
        // returns SnpResp_I (dataless) — the SNP_respdata trigger bin
        // never hits.  Append a directed store-then-snoop pair on a
        // far-off address so every vector also exercises the
        // SnpRespData_*_PD path.  ReadUnique fetches the line dirty
        // (UD_PD response is opcode-aware), then SnpClean while still
        // in UD yields SnpRespData_SC_PD on the wire.
        begin
            logic [39:0] dirty_addr = 40'h00_00EE_0000;
            exerciser_active = 1'b1;
            // Register the line as exerciser-owned so the egress MEM_ORACLE
            // skips it — store_merge is gated off during the exerciser
            // so the oracle can never model this line's contents.
            exerciser_touched[dirty_addr & ~40'h3F] = 1'b1;
            u_hnf.set_next_response_compdata_ud_pd(256'hCAFE_F00D);
            do_store(dirty_addr, 64'hDEAD_BEEF_CAFE_BABE);
            repeat (300) @(posedge clk);
            u_hnf.inject_snoop_clean({1'b0, dirty_addr});
            repeat (300) @(posedge clk);
            exerciser_active = 1'b0;
        end

        // ── Snoop drain ─────────────────────────────────────────────
        // Use do_cbo_inval (no cache-way allocation) to poke the L1.5
        // pipeline so queued snoops retire before $finish.
        repeat (4) begin
            do_cbo_inval(40'h00_00FF_0000 | (i * 'h40));
            i++;
            repeat (20) @(posedge clk);
        end

        // ── Post-vector data-integrity probe (per-line LD sweep) ────
        probe_all_dirty_lines();

        // ── Post-vector write-visibility probe (LD → ST → LD-back) ──
        // Fires directly on the vector's default line 0x2000 from the
        // vector's own quiescent end-state.  Reproduces the .md-class
        // failure by construction on any state the RN-F fails to make
        // the store visible to the following load.
        write_visibility_probe();

        $display("[REPLAY] === %s done: %0d DRIVE, env_q push=%0d pop=%0d WV_PROBE fired=%0d skipped=%0d trig_miss=%0d ===",
                 path, n_drive, g_env_resp_push_count, g_env_resp_pop_count,
                 wv_probe_fired_cnt, wv_probe_skipped_cnt, trigger_miss_cnt);
    endtask

    // ── Event-class predicates ──────────────────────────────────────
    function automatic bit is_sw_enqueue(input string ev);
        return (ev.len() >= 11 && ev.substr(0, 10) == "SW_enqueue_");
    endfunction

    function automatic bit is_env_response(input string ev);
        // Env_Comp_*, Env_CompData_*, Env_DBIDResp_*, Env_CompDBIDResp_*
        return ((ev.len() >= 4 && ev.substr(0, 3) == "Env_") &&
                (contains_substr(ev, "Comp") ||
                 contains_substr(ev, "DBIDResp")));
    endfunction

    function automatic bit is_env_snoop(input string ev);
        return (ev.len() >= 8 && ev.substr(0, 7) == "Env_Snp_");
    endfunction

    // Pre-arm a default CHI response shape based on the SW op, used
    // when the vector has no Env_* between this SW and the next one.
    task automatic program_default_for_sw(input string sw_ev);
        if (model_trace_en)
            $display("[MTRACE] %0t DEFARM sw=%s", $time, sw_ev);
        case (sw_ev)
            "SW_enqueue_ReadClean",
            "SW_enqueue_ReadUnique":
                u_hnf.set_next_response_compdata_uc(256'h0);
            "SW_enqueue_AtomicLoad":
                u_hnf.set_next_response_dbidresp_then_compdata(256'h0);
            "SW_enqueue_AtomicStore",
            "SW_enqueue_WriteBackFull",
            "SW_enqueue_WriteCleanFull":
                u_hnf.set_next_response_dbidresp_then_comp();
            "SW_enqueue_MakeUnique",
            "SW_enqueue_CleanUnique",
            "SW_enqueue_CleanInvalid",
            "SW_enqueue_CleanShared":
                u_hnf.set_next_response_comp();
            "SW_enqueue_Evict":
                u_hnf.set_next_response_comp();
            // SetConflict expands into WAY_COUNT sequential loads and,
            // if the target was dirty, one WriteBackFull.  The HN-F
            // stays in its default read-shape auto-response mode
            // (Comp/CompData); explicit Env_* directives in the
            // vector can override per REQ if needed.
            "SW_enqueue_SetConflict":
                u_hnf.set_next_response_compdata_uc(256'h0);
            // NC LD: L1.5 emits ReadClean (data-side NC) or ReadNoSnp
            // (IFILL-NC).  Either way response is CompData; arm same as
            // regular LD.
            "SW_enqueue_NC_Load":
                u_hnf.set_next_response_compdata_uc(256'h0);
            // NC ST (writethrough): CHI WriteNoSnpPtl expects
            // DBIDResp → data-beat → Comp.
            "SW_enqueue_NC_Store":
                u_hnf.set_next_response_dbidresp_then_comp();
            // LR: read-shape (ReadClean/ReadUnique-with-reservation).
            "SW_enqueue_LR":
                u_hnf.set_next_response_compdata_uc(256'h0);
            // SC: succeeds locally when line is unique + reservation
            // valid; otherwise no CHI activity.  When it does need an
            // upgrade, the L1.5 emits ReadUnique-shape (rare path);
            // arm compdata to be safe.
            "SW_enqueue_SC":
                u_hnf.set_next_response_compdata_uc(256'h0);
            default:
                u_hnf.set_next_response_comp();
        endcase
    endtask

    function automatic bit contains_substr(input string haystack,
                                           input string needle);
        int hi, ni;
        bit match;
        if (needle.len() == 0) return 1'b1;
        if (haystack.len() < needle.len()) return 1'b0;
        for (hi = 0; hi <= haystack.len() - needle.len(); hi++) begin
            match = 1'b1;
            for (ni = 0; ni < needle.len(); ni++) begin
                if (haystack[hi + ni] != needle[ni]) begin
                    match = 1'b0;
                    break;
                end
            end
            if (match) return 1'b1;
        end
        return 1'b0;
    endfunction

    // Pull the "@trig{...}" body out of a vector line; "" when absent.
    // The suffix sits after the "from -> to" column, which
    // extract_event_token never reaches, so vectors with and without it
    // parse identically.
    function automatic string extract_trigger(input string line);
        int i, j;
        for (i = 0; i + 6 <= line.len(); i++) begin
            if (line.substr(i, i + 5) == "@trig{") begin
                j = i + 6;
                while (j < line.len() && line[j] != "}") j++;
                return line.substr(i + 6, j - 1);
            end
        end
        return "";
    endfunction

    function automatic string extract_event_token(input string line);
        // The vector files use fixed-column formatting:
        //   "{step:3d} | {kind:6s} | {event:42s} | ..."
        // So the event field always starts at column 15 and ends at
        // the next '|' or padding boundary.  Substring + rtrim
        // sidesteps the SV string-byte-concat quirks that bit us
        // with character-at-a-time accumulation.
        int start, end_, j;
        string field;
        if (line.len() < 16) return "";
        start = 15;            // first char of event field
        // End = next '|' at or after start, capped at line length.
        end_ = line.len();
        for (j = start; j < line.len(); j++) begin
            if (line[j] == "|") begin end_ = j; break; end
        end
        // Substr is inclusive of both ends.
        field = line.substr(start, end_ - 1);
        // Trim trailing whitespace.
        j = field.len() - 1;
        while (j >= 0 && (field[j] == " " || field[j] == "\t"
                          || field[j] == "\n" || field[j] == "\r")) j--;
        if (j < 0) return "";
        return field.substr(0, j);
    endfunction

    // ── Dispatchers ─────────────────────────────────────────────────
    // dispatch_sw blocks until L1.5 returns; called only after the
    // look-ahead has pre-armed the responder for the upcoming REQ.
    //
    // NOTE: cache-maintenance and replacement-driven ops (Clean*,
    // MakeUnique, Evict, WriteBackFull, WriteCleanFull) have no
    // direct PCX request-type from the transducer interface -- in
    // real silicon they're triggered by Zicbom CMOs (via CVA6) or
    // by L1.5 replacement policy.  IP-level stimulation of them
    // requires either cache-pressure engineering or extra MMIO/CSR
    // wiring; skipping for now so they don't deadlock.
    task automatic dispatch_sw(input string ev,
                               input logic [39:0] addr,
                               input logic [63:0] data);
        if (model_trace_en)
            $display("[MTRACE] %0t SW  %s addr=0x%010h", $time, ev, addr);
        case (ev)
            // sw_ReadClean = hart LD.  Rotate through {plain, cbo.zero}
            // to exercise both LOAD and the blockinitstore path
            // downstream.  Prefetch is excluded from this rotation —
            // marked out-of-scope in the coverage exclusion file
            // (matches the paper's "reachable subset" methodology).
            // ReadClean is a READ.  cbo.zero used to be rotated in here to
            // pick up a predecoder branch cheaply, but it drives
            // PCX_REQTYPE_STORE and takes the ST MSHR slot -- so the model
            // tracked a read while the DUT ran a store, and the vectors
            // deadlocked the L1.5.  It has its own event now.
            "SW_enqueue_ReadClean":      do_load(addr);
            "SW_enqueue_CBO_Zero":       do_cbo_zero(addr);
            "SW_enqueue_ReadUnique":      do_store(addr, data);
            // Rotate through the 8 AMO opcodes on each dispatch so that
            // txreq_encoder's per-opcode branches (AtomicLoad_ADD,
            // _CLR, _EOR, _SET, _SMAX, _SMIN, _UMAX, _UMIN and their
            // AtomicStore counterparts) all get exercised across the
            // vector set.  Uses a shared static counter so that the
            // opcode picked for one dispatch persists across vectors
            // in the same mega-vector run.
            "SW_enqueue_AtomicLoad":     do_amo(addr, next_amo_op(), data, 1'b1);
            "SW_enqueue_AtomicStore":    do_amo(addr, next_amo_op(), data, 1'b0);
            // Non-cacheable data-path (writethrough / IFILL-NC) — bypasses
            // cache, exercises RTL branches guarded on req_nc.
            "SW_enqueue_NC_Load":        do_load_nc(addr);
            "SW_enqueue_NC_Store":       do_store_nc(addr, data);
            // RISC-V LR/SC via PCX_REQTYPE_AMO + AMO_OP_LR/SC.
            // LR is load-shape (returns value); SC is store-shape.
            "SW_enqueue_LR":             do_amo(addr, `L15_AMO_OP_LR, 64'h0, 1'b1);
            "SW_enqueue_SC":             do_amo(addr, `L15_AMO_OP_SC, data, 1'b1);
            // Plain store (no special PCX type for the store-init case)
            // -- works for write-allocate paths but not CMOs.
            "SW_enqueue_MakeUnique":     do_store(addr, data);
            // CleanInvalid: drives transducer_l15_invalidate_cacheline,
            // which the predecoder maps to DCACHE_SELF_INVALIDATION.
            // That handler emits NO CHI traffic -- it does a WMT demap
            // (DEMAP_TAGCHECK_WAY_IF_MES) plus CPX_GEN_DCACHE_INVALIDATION
            // and touches neither MESI nor NOC1/NOC3; CHIE_CLEANINVALID is
            // assigned nowhere in the RTL.  So this invalidates the CORE's
            // L1D only and leaves the L1.5 line, dirty data included,
            // untouched.  Kept as stimulus because it is the only thing
            // that reaches that predecode branch and handler, but it is
            // invisible at the CHI port -- do not expect a REQ from it.
            "SW_enqueue_CleanInvalid":   do_cbo_inval(addr);
            // The remaining CMO / replacement-driven ops still lack a
            // direct transducer trigger (CleanShared/CleanUnique need
            // either Zicbom cbo.clean or a successful store-upgrade;
            // Evict/WriteBackFull arise from cache replacement only).
            // CleanShared is the closest SW-visible analogue of a line
            // flush (clean any dirty copy, keep the line readable), so it
            // drives the flush walk rather than being skipped.
            "SW_enqueue_CleanShared":    do_cbo_flush(addr);
            "SW_enqueue_CleanUnique",
            "SW_enqueue_Evict",
            "SW_enqueue_WriteBackFull",
            "SW_enqueue_WriteCleanFull":
                $display("[REPLAY] skip CMO/replacement op '%s' (no transducer mapping)", ev);
            // Set-conflict eviction: issue L15_WAY_COUNT loads to the
            // same set as `addr`, forcing LRU replacement of the
            // target line and (if it was dirty) a CHI WriteBackFull
            // on the wire.
            "SW_enqueue_SetConflict":    do_set_conflict(addr);
            default:
                $display("[REPLAY] unknown SW event: '%s'", ev);
        endcase
    endtask

    // program_env_response is non-blocking: it just sets the next
    // directive on the abstract HN-F.  The directive is consumed when
    // the DUT issues the corresponding REQ on the wire.
    task automatic program_env_response(input string ev);
        if (model_trace_en)
            $display("[MTRACE] %0t ENVARM ev=%s", $time, ev);
        case (ev)
            "Env_CompData_clean":
                u_hnf.set_next_response_compdata_uc(256'hCAFEBABE);
            "Env_CompData_dirty":
                u_hnf.set_next_response_compdata_ud_pd(256'hDEADBEEF);
            "Env_Comp_dataless",
            "Env_Comp_for_Evict",
            "Env_Comp_for_AtomicStore",
            "Env_Comp_for_WriteBack":
                u_hnf.set_next_response_comp();
            "Env_DBIDResp_for_Write":
                u_hnf.set_next_response_dbidresp_then_comp();
            // Combined completion, distinct from the split shape above.
            // These two were mapped to the same task, so no vector ever
            // emitted a CompDBIDResp and the combined-write coverage
            // bins were unreachable.  The split shape also wedges the
            // DUT: rx_control retires the REQ entry when it sends
            // WriteData after the DBIDResp, so the trailing Comp finds
            // req_valid=0 and self-loops in NOC2_STATE_REQ_CHECK with
            // noc_in_rdy=0, blocking every later snoop (SNP_MON).
            "Env_CompDBIDResp_for_Write":
                u_hnf.set_next_response_compdbidresp();
            // AtomicLoad / AtomicSwap return the old value as CompData
            // after the operand WriteData -- need the DBIDResp+CompData
            // shape, not the DBIDResp+Comp one used for stores.
            "Env_CompData_for_AtomicLoad":
                u_hnf.set_next_response_dbidresp_then_compdata(256'h12345678_9ABCDEF0);
            default:
                $display("[REPLAY] unknown Env response: '%s'", ev);
        endcase
    endtask

    // inject_env_snoop drives RXSNPFLITV via the responder's snoop
    // queue.  It serializes (one snoop at a time) but otherwise does
    // not block the dispatch loop.
    function automatic bit starts_with(input string s, input string pre);
        if (s.len() < pre.len()) return 0;
        return (s.substr(0, pre.len()-1) == pre);
    endfunction

    // NOTE: addr is 40-bit but CHIE_SNP_ADDR_WIDTH_PARAM is 41.  The calls
    // below used addr[40:0] -- a 41-bit select from a 40-bit variable, so
    // bit 40 read as X and EVERY injected snoop carried an X in its
    // address MSB.  Zero-extend instead.
    task automatic inject_env_snoop(input string ev, input logic [39:0] addr);
        // Land the snoop while a transaction is genuinely outstanding.
        // u_hnf.have_req is set on TXREQ and cleared when the responder
        // completes the transaction, so it is exactly "the DUT has a REQ
        // in flight" -- and unlike the coverage tracker it exists in
        // non-coverage builds too.  Bounded wait: most SW ops are
        // absorbed locally and never produce a REQ, so give up quickly
        // and inject anyway rather than stalling the replay.
        if (resp_delay_arg != 0) begin
            int unsigned wait_cyc;
            wait_cyc = 0;
            while (!u_hnf.have_req && wait_cyc < 40) begin
                @(posedge clk);
                wait_cyc++;
            end
        end
        case (ev)
            "Env_Snp_SnpClean":          u_hnf.inject_snoop_clean({1'b0, addr});
            "Env_Snp_SnpUnique":         u_hnf.inject_snoop_unique({1'b0, addr});
            "Env_Snp_SnpMakeInvalid":    u_hnf.inject_snoop_makeinvalid({1'b0, addr});
            "Env_Snp_SnpCleanInvalid":   u_hnf.inject_snoop_cleaninvalid({1'b0, addr});
            "Env_Snp_SnpShared":         u_hnf.inject_snoop_shared({1'b0, addr});
            // RetToSrc=1 variants.  The snoopee returns data on a CLEAN
            // line only when the snoop asks for it, which is the only
            // way to produce SnpRespData_I / _SC (the SR_*_D response
            // variants).  SnpMakeInvalid has no RTS form -- it never
            // returns data in any case.
            // RetToSrc variants.  The model names them per L1 state --
            // Env_Snp_SnpClean_RTS_from_UD and so on -- so these must be
            // PREFIX matches.  Exact-equality cases silently dropped all
            // 20 per-state variants into `default`, which showed up as
            // "unknown Env snoop" in 731 logs and made the SR_*_D cells
            // look like wedge losses when in fact no RTS snoop was ever
            // injected.
            default: begin
                if      (starts_with(ev, "Env_Snp_SnpCleanInvalid_RTS"))
                    u_hnf.inject_snoop_cleaninvalid({1'b0, addr}, 1'b1);
                else if (starts_with(ev, "Env_Snp_SnpClean_RTS"))
                    u_hnf.inject_snoop_clean       ({1'b0, addr}, 1'b1);
                else if (starts_with(ev, "Env_Snp_SnpUnique_RTS"))
                    u_hnf.inject_snoop_unique      ({1'b0, addr}, 1'b1);
                else if (starts_with(ev, "Env_Snp_SnpShared_RTS"))
                    u_hnf.inject_snoop_shared      ({1'b0, addr}, 1'b1);
                else
                    $display("[REPLAY] unknown Env snoop: '%s'", ev);
            end
        endcase
    endtask


    // ══════════════════════════════════════════════════════════════════
    //  CHI flit decode -- one struct per channel, for waveform debug.
    //  Types and parse_*_flit helpers mirror chi_icn_beh.sv so a trace
    //  reads the same on either side.  Each struct carries its own
    //  `valid`, so a single wave signal shows whether the flit is real
    //  and what it holds.  Combinational taps only; nothing drives the DUT.
    // ══════════════════════════════════════════════════════════════════
`include "chi_flit_dbg.svh"

    chie_req_s dbg_txreq;   // RN-F -> HN-F requests
    chie_rsp_s dbg_txrsp;   // CompAck, SnpResp
    chie_dat_s dbg_txdat;   // WriteData, SnpRespData
    chie_snp_s dbg_rxsnp;   // incoming snoops
    chie_rsp_s dbg_rxrsp;   // Comp, DBIDResp, CompDBIDResp
    chie_dat_s dbg_rxdat;   // CompData

    always_comb begin
        dbg_txreq = parse_req_flit(txreqflit, txreqflitv);
        dbg_txrsp = parse_rsp_flit(txrspflit, txrspflitv);
        dbg_txdat = parse_dat_flit(txdatflit, txdatflitv);
        dbg_rxsnp = parse_snp_flit(rxsnpflit, rxsnpflitv);
        dbg_rxrsp = parse_rsp_flit(rxrspflit, rxrspflitv);
        dbg_rxdat = parse_dat_flit(rxdatflit, rxdatflitv);
    end

    // ── Top-level test sequence: replay a vector or run the smoke ──
    // ── Directed L1-state pre-roll ──────────────────────────────────
    // Walks the inferred_l1 tracker through every CHI-E cache state
    // at least once so cg_l1_transitions reaches 100% on
    // (cp_prev_state, cp_next_state).
    //
    // Strategy: issue four independent loads to four distinct
    // addresses, each pre-programmed with a different CompData Resp
    // value (UC/UD/SC/SD).  The tracker latches the actual Resp from
    // the wire and updates inferred_l1 accordingly -- so each load's
    // post-CompAck terminal state advances the tracker through the
    // target state.
    //
    // Stores are skipped: the L1.5's transducer-side store handshake
    // doesn't return l15_transducer_ack reliably in this IP-level
    // bring-up.  ReadClean loads + Resp variants are enough to
    // exercise every L1-state coverpoint bin.
    task automatic l1_state_preroll();
        $display("[%0t] === L1-state pre-roll ===", $time);

        // Phase 1: four loads → SC, SD, UC, UD.  Addresses are spaced
        // by 64B (cache-line size) so each goes to a distinct cache
        // set.  Using 0x10000-step addresses collided in set-0 and
        // forced same-way evictions, which wedged the L1.5 (CompData
        // arriving before its eviction WCF completed was dropped).
        // Use addresses that scatter across the L1.5 hash by varying
        // page index and low bits — 0x10000-step addresses empirically
        // collide in one set.  Each address is used by both its load
        // and its snoop so the snoop hits the line.
        u_hnf.set_next_response_compdata_sc(256'hAA);
        do_load(40'h00_0001_1040);    // -> SC
        repeat (50) @(posedge clk);

        u_hnf.set_next_response_compdata_sd_pd(256'hBB);
        do_load(40'h00_0002_2080);    // -> SD
        repeat (50) @(posedge clk);

        u_hnf.set_next_response_compdata_uc(256'hCC);
        do_load(40'h00_0003_30C0);    // -> UC
        repeat (50) @(posedge clk);

        u_hnf.set_next_response_compdata_ud_pd(256'hDD);
        do_load(40'h00_0004_4100);    // -> UD
        repeat (200) @(posedge clk);

        // ── Phase 2: data-bearing snoops + interleaved CMO wake-up ─
        // The L1.5 snoop pipeline is event-driven — it only advances
        // when a CPU request also pokes the pipeline.  Issuing CMO
        // ops between snoops keeps it draining so each SnpResp fires
        // and the corresponding L1-state transition is observed.
        $display("[%0t] === Phase 2: data-bearing snoops + CMO drain ===", $time);

        u_hnf.inject_snoop_clean       (41'h0_0004_4100); // UD -> SC
        repeat (50) @(posedge clk);
        do_cbo_inval(40'h00_0004_4100);                    // wake + REQ CleanInvalid
        repeat (200) @(posedge clk);

        u_hnf.inject_snoop_unique      (41'h0_0001_1040); // SC -> I
        repeat (50) @(posedge clk);
        do_cbo_inval(40'h00_0001_1040);
        repeat (200) @(posedge clk);

        u_hnf.inject_snoop_shared      (41'h0_0003_30C0); // UC -> SC
        repeat (50) @(posedge clk);
        do_cbo_inval(40'h00_0003_30C0);
        repeat (200) @(posedge clk);

        u_hnf.inject_snoop_cleaninvalid(41'h0_0002_2080); // SD -> I
        repeat (50) @(posedge clk);
        do_cbo_inval(40'h00_0002_2080);
        repeat (200) @(posedge clk);

        rettosrc_epilogue();

        $display("[%0t] === pre-roll complete ===", $time);
    endtask

    // ── RetToSrc=1 snoops on CLEAN lines ────────────────────────────
    // A snoopee returns data on a clean line only when the snoop asks
    // for it via RetToSrc, yielding SnpRespData_I / SnpRespData_SC --
    // the SR_I_D / SR_SC_D response variants.  Every other snoop in
    // this TB lands on a dirty or invalid line, so those two bins were
    // unreachable purely for lack of stimulus, not by construction:
    // rx_control.sv:2017/2027 do forward rxsnp_rettosrc_r into the
    // L1.5 snoop message.
    //
    // Runs as an EPILOGUE after vector replay (and at the end of the
    // pre-roll) on addresses no vector touches, so it cannot perturb
    // the model-driven sequence or the memory oracle.
    // Walks the full (snoop_op x L1_state) matrix with RetToSrc=1 so
    // every x_decision cell whose response variant is SR_*_D becomes
    // reachable, not just the four combinations that were hand-written
    // first.  Addresses step by 0x1_0040 (page index + line) because
    // 0x1_0000-step addresses collide in one L1.5 set and force
    // same-way evictions that wedge the pipeline.
    // Sweeps BOTH RetToSrc values, not just 1.  The original matrix
    // hard-coded RetToSrc=1 on all five injections, which reaches the
    // SR_*_D (data-bearing) variants but leaves their DATALESS partners
    // unreachable: on a CLEAN line a snoopee returns data only when
    // asked, so RetToSrc=0 is what elicits SnpResp_SC / SnpResp_I.  With
    // only the RTS=1 half driven, <SnpShared,UC,SR_SC> and
    // <SnpUnique,UC,SR_I> sat uncovered and looked like RTL policy
    // ("this DUT always returns data") when they were pure stimulus gaps
    // -- the covered siblings <SnpShared,UC,SR_SC_D> and
    // <SnpUnique,UC,SR_I_D> had 128 hits each from this very loop.
    task automatic rettosrc_epilogue();
        logic [39:0] a;
        logic        rts_v;
        int idx;
        $display("[%0t] === RetToSrc snoop matrix (2 rts x 4 states x 5 ops) ===",
                 $time);
        idx = 0;
        for (int rts = 0; rts < 2; rts++) begin
            rts_v = (rts == 1);
            for (int st = 0; st < 4; st++) begin
                for (int op = 0; op < 5; op++) begin
                    a = 40'h00_0010_0000 + (idx * 40'h0_0001_0040);
                    case (st)
                        0: u_hnf.set_next_response_compdata_uc   (256'hE0 + idx);
                        1: u_hnf.set_next_response_compdata_sc   (256'hE0 + idx);
                        2: u_hnf.set_next_response_compdata_ud_pd(256'hE0 + idx);
                        3: u_hnf.set_next_response_compdata_sd_pd(256'hE0 + idx);
                    endcase
                    do_load(a);
                    repeat (60) @(posedge clk);
                    case (op)
                        0: u_hnf.inject_snoop_clean       ({1'b0, a}, rts_v);
                        1: u_hnf.inject_snoop_shared      ({1'b0, a}, rts_v);
                        2: u_hnf.inject_snoop_unique      ({1'b0, a}, rts_v);
                        3: u_hnf.inject_snoop_cleaninvalid({1'b0, a}, rts_v);
                        4: u_hnf.inject_snoop_makeinvalid ({1'b0, a}, rts_v);
                    endcase
                    repeat (40) @(posedge clk);
                    do_cbo_inval(a);       // also purges the oracle entry
                    repeat (80) @(posedge clk);
                    idx++;
                end
            end
        end
        $display("[%0t] === RetToSrc epilogue complete ===", $time);
    endtask

    string g_vector_path;
    // ── Auto-response background driver ─────────────────────────────
    // Vector replay programs env responses *between* memory ops, but
    // each memory op task blocks until L1.5 returns data.  Without
    // this fallback, vectors that don't explicitly pre-program every
    // REQ would deadlock.
    //
    // Gated by g_auto_response_en so the directed pre-roll (which
    // programs every response explicitly) can disable it -- otherwise
    // the auto-thread races with the pre-roll's set_next_response_*
    // calls and clobbers them with CompData_UC.
    logic g_auto_response_en = 1'b1;
    // Alternates split vs combined write completion (see below).
    logic g_wr_combined_sel  = 1'b0;
    initial begin : auto_response
        @(posedge rst_n);
        forever begin
            @(posedge clk);
            if (g_auto_response_en && txreqflitv && !u_hnf.have_directive) begin
                // Pick a CHI-shape-appropriate default based on the
                // REQ opcode currently on the wire.  Without this, an
                // eviction-WriteBack triggered as a side-effect of a
                // load to a different way would never get a response
                // (CompData_UC isn't a valid reply to a writeback).
                case (txreqflit[`CHIE_REQ_FLIT_OPCODE_RANGE])
                    7'h00,            // Evict
                    7'h08:            // CleanShared
                        u_hnf.set_next_response_comp();
                    7'h09,            // CleanInvalid
                    7'h0A,            // CleanUnique
                    7'h0B:            // MakeUnique
                        u_hnf.set_next_response_comp();
                    // Write-shaped REQs: the RN-F needs a DBID before it
                    // can send data.  Answering with CompData instead
                    // leaves the transaction outstanding forever and pins
                    // its MSHR slot -- which is what stalled every
                    // subsequent request and produced the SNP_MON class.
                    // Opcode list checked against every msg_type_chi
                    // assignment in txreq_encoder.v plus the WriteBackFull
                    // path in response_encoder.sv:
                    //   0x1b WriteBackFull   0x17 WriteCleanFull
                    //   0x1c WriteNoSnpPtl   0x15 WriteEvictFull
                    //   0x1d WriteUniqueFull / WriteNoSnpFull
                    // CopyBack writes: CompDBIDResp ONLY.  The split
                    // DBIDResp-then-Comp is not a legal completion for a
                    // CopyBack write -- rx_control retires the REQ entry
                    // when it sends WriteData after the DBIDResp, so the
                    // trailing Comp finds req_valid=0 and self-loops in
                    // NOC2_STATE_REQ_CHECK with noc_in_rdy=0, blocking
                    // every later snoop (the SNP_MON failure class).  The
                    // project's own HN-F never splits here either:
                    // hnf_mshr_ctl.v:2411 sets comp_rdy and dbid_rdy in
                    // the same cycle for the WB/WC/WE family, so its
                    // response mux always picks CompDBIDResp.
                    7'h1B,            // WriteBackFull
                    7'h17,            // WriteCleanFull
                    7'h15:            // WriteEvictFull
                        u_hnf.set_next_response_compdbidresp();
                    7'h1c,            // WriteNoSnpPtl   <- was missing
                    7'h1D: begin      // WriteUniqueFull / WriteNoSnpFull
                        // Alternate the two CHI-legal write completions.
                        // Both shapes ARE legal for these (non-CopyBack)
                        // writes; only the combined form reaches
                        // cp_phase_seq's SEQ_WRITE_COMBINED bin and the
                        // WRITE_COMBINED column of x_op_seq, which no
                        // stimulus in this TB produced before.
                        g_wr_combined_sel <= ~g_wr_combined_sel;
                        if (g_wr_combined_sel)
                            u_hnf.set_next_response_compdbidresp();
                        else
                            u_hnf.set_next_response_dbidresp_then_comp();
                    end
                    // ALL eight AtomicStore opcodes (0x28-0x2f), not just
                    // _ADD -- the same "only the first was listed" gap
                    // that pinned an MSHR on the AtomicLoad range below.
                    7'h28, 7'h29, 7'h2a, 7'h2b,
                    7'h2c, 7'h2d, 7'h2e, 7'h2f:
                        u_hnf.set_next_response_dbidresp_then_comp();
                    // ALL nine atomic opcodes txreq_encoder can emit --
                    // AtomicLoad_{ADD,CLR,EOR,SET,SMAX,SMIN,UMAX,UMIN}
                    // 0x30-0x37 plus AtomicSwap 0x38.  Only 0x30 and 0x38
                    // were listed, so the other seven fell through to the
                    // CompData_UC default, which an atomic cannot consume:
                    // the transaction never completed and its MSHR slot
                    // stayed pinned, refusing every later request.
                    7'h30, 7'h31, 7'h32, 7'h33,   // AtomicLoad_ADD/CLR/EOR/SET
                    7'h34, 7'h35, 7'h36, 7'h37,   // AtomicLoad_SMAX/SMIN/UMAX/UMIN
                    7'h38:                        // AtomicSwap
                        u_hnf.set_next_response_dbidresp_then_compdata(256'h0);
                    default:          // ReadClean / ReadUnique / ...
                        u_hnf.set_next_response_compdata_uc(256'h0);
                endcase
            end
        end
    end

    initial begin
        drive_idle();
        @(posedge rst_n);
        repeat (10) @(posedge clk);
            
        // L1.5 SRAMs use bram_1rw_wrapper with a BIST-clear loop that
        // walks 2^ADDR_WIDTH = 512 addresses (data + hmt) writing zero.
        // Any transducer write during that window is silently redirected
        // to bist_index, overwriting real data.  Wait 2000 cycles (~4x
        // BIST duration) to be safely past init on every configuration.
        repeat (2000) @(posedge clk);

        // Pre-roll runs ONLY when no vector is supplied (smoke /
        // standalone runs).  When replaying a Murphi-derived vector,
        // skip the pre-roll: vectors carry their own sw_* sequences
        // and the pre-roll's leftover cached lines + pending snoop
        // wedge the L1.5 before the vector's first load completes.
        if ($test$plusargs("RACE_SWEEP")) begin
            race_sweep();
        end
        else if ($test$plusargs("LOSTSTORE_TEST")) begin
            run_loststore_test();
        end
        else if ($test$plusargs("CMO_PROBE")) begin
            run_cmo_probe();
        end
        else if ($value$plusargs("VECTOR=%s", g_vector_path)) begin
            $display("[%0t] === vector replay: %s ===", $time, g_vector_path);
            replay_vector(g_vector_path);
            // Epilogue on addresses outside the vector's footprint --
            // the only stimulus in this TB that sets RetToSrc, and thus
            // the only source of clean-data snoop responses.
            rettosrc_epilogue();
        end else begin
            l1_state_preroll();   // smoke / standalone: walk L1 bins
            // Skip the trailing smoke loads — they target the same
            // cache set as pre-roll's UD line (0x44100), trigger an
            // eviction WCF, and wedge waiting for CompAck that the
            // L1.5 won't send until the queued Phase-2 snoops drain.
            // Pre-roll alone now exercises every state + every snoop
            // variant, which is what the coverage needs.
        end
        $finish;
    end

    // ── Custom directed test: reproduce RNF_COHERENCE_BUG.md class ──
    // Bug shape: hart stores to a line; later hart LD of same line
    // returns stale (pre-store) bytes.  Single-hart is sufficient since
    // the RN-F's own cache is what must hold the freshest bytes.
    //
    // Sequence:
    //   phase 1  install line (LD miss → RN-F fetches ReadClean)
    //   phase 2  STORE known pattern to same line (dirty upgrade)
    //   phase 3  quiesce
    //   phase 4  LD-back — MEM_ORACLE checks bytes against oracle
    //              (which now carries the store's bytes after
    //              store_merge fired).  Mismatch ⇒ bug reproduced.
    //   phase 5  optional: HNF issues a snoop between store and LD
    //              to widen the timing window (co-sim's actual trigger).
    task automatic run_loststore_test();
        logic [39:0] addr       = 40'h00_1234_5000;
        logic [63:0] store_pat  = 64'hFACE_CAFE_0BAD_F00D;
        logic [63:0] second_pat = 64'h1122_3344_5566_7788;
        int          n_errors_before, n_errors_after;

        $display("[%0t] === LOSTSTORE_TEST start ===", $time);

        // Phase 1 — install line via LD miss
        u_hnf.set_next_response_compdata_uc(256'hAAAAAAAA_BBBBBBBB);
        do_load(addr);
        repeat (50) @(posedge clk);

        // Phase 2 — hart STORE (line is UC, needs upgrade to UD via
        // ReadUnique per the L1.5's store-hit-shared path).  Arm HNF
        // to deliver CompData_UD_PD for the upgrade so the L1.5 can
        // complete and merge the store bytes.
        u_hnf.set_next_response_compdata_ud_pd(256'hAAAAAAAA_BBBBBBBB);
        do_store(addr, store_pat);
        repeat (200) @(posedge clk);

        // Phase 3 — quiesce
        repeat (100) @(posedge clk);

        // Phase 4 — LD back on same address.  If the RN-F's cache
        // dropped the dirty store, load_return_check fires
        // [MEM_ORACLE] mismatch and this counts as bug reproduced.
        $display("[%0t] [LOSTSTORE] phase 4: LD-back check (post-store, no snoop)",
                 $time);
        do_load(addr);
        repeat (50) @(posedge clk);

        // Phase 5 — inject a data-returning snoop, then LD-back
        // again.  This is the tighter co-sim window: snoop-vs-store
        // overlap on the same line.  RN-F should reply SnpRespData
        // with the freshest bytes (checked by TXDAT egress oracle),
        // and the LD-back should still see the store pattern.
        $display("[%0t] [LOSTSTORE] phase 5: 2nd STORE + SnpShared, then LD-back",
                 $time);
        u_hnf.set_next_response_compdata_ud_pd(256'h0);
        do_store(addr, second_pat);
        // Immediately snoop before the store has fully drained.
        u_hnf.inject_snoop_shared({1'b0, addr});
        repeat (300) @(posedge clk);
        do_load(addr);
        repeat (50) @(posedge clk);

        $display("[%0t] === LOSTSTORE_TEST end ===", $time);
    endtask


    // ── CMO_PROBE ────────────────────────────────────────────────────
    // Answers two questions the RTL source alone could not settle,
    // both of which decide Murphi rules:
    //   (1) does cbo.flush on a CLEAN (non-dirty) line still drop the
    //       L1.5 line to I?  `L15_S3_MESI_INVALIDATE_FLUSH_WAY_IF_MES`
    //       reads as "any valid state", but that is a macro name, not
    //       observed behaviour.  A following load that MISSES (emits a
    //       fresh TXREQ) proves the line went away.
    //   (2) is cbo.zero distinguishable from a plain store at the CHI
    //       port?  do_cbo_zero drives PCX_REQTYPE_STORE with no ASI
    //       tag and no sideband bit, so it should produce exactly the
    //       same REQ as do_store on the same line state.
    // Run: vsim ... +CMO_PROBE
    task automatic run_cmo_probe();
        $display("[%0t] === CMO_PROBE start ===", $time);

        // (1) clean line -> cbo.flush -> reload
        do_load(40'h0000003000);            // fill: expect ReadClean, lands clean
        repeat (60) @(posedge clk);
        $display("[%0t] CMO_PROBE A: after fill, tagcheck_state_s2=%0d",
                 $time, u_dut.l15.pipeline.tagcheck_state_s2);

        do_cbo_flush(40'h0000003000);       // flush a CLEAN line
        repeat (60) @(posedge clk);
        $display("[%0t] CMO_PROBE B: after cbo.flush of clean line", $time);

        $display("[%0t] CMO_PROBE C: reload -- a TXREQ here means the flush invalidated",
                 $time);
        do_load(40'h0000003000);
        repeat (60) @(posedge clk);

        // (2) cbo.zero on an untouched line, vs a store on another
        $display("[%0t] CMO_PROBE D: cbo.zero on cold line", $time);
        do_cbo_zero(40'h0000004000);
        repeat (60) @(posedge clk);

        $display("[%0t] CMO_PROBE E: store on cold line (comparison)", $time);
        do_store(40'h0000005000, 64'hA5A5A5A5A5A5A5A5);
        repeat (60) @(posedge clk);

        $display("[%0t] === CMO_PROBE end ===", $time);
    endtask

    // ── Timeout watchdog ────────────────────────────────────────────
    // Backstop only -- per-task bounded waits already stop any single
    // op blocking forever.  Sized for the prefix-shared mega-vectors:
    // a hub chains every 2-switch tail under it back-to-back, so the
    // largest run ~170 tails and finish replay past 900 us, and the
    // RetToSrc epilogue still has to follow.  The old 1 ms budget was
    // set when a vector was a single tail and now expires mid-epilogue
    // on the big hubs.  Override with +WATCHDOG_NS=<n> for a shorter
    // leash when bisecting a genuine hang.
    int unsigned watchdog_ns = 10_000_000;   // 10 ms
    initial begin
        void'($value$plusargs("WATCHDOG_NS=%d", watchdog_ns));
        #(watchdog_ns);
        $display("[%0t] TIMEOUT", $time);
        $fatal(1, "rnf_ip_tb watchdog expired");
    end

endmodule
