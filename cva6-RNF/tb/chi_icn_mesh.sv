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
// chi_icn_mesh.sv — adapter that exposes the same external interface as
// chi_icn_beh but internally instantiates an OpenNoC mesh_wrapper_2x2.
//
// 2x2 mesh layout:
//   XP(0,0)  P0=RNF0  P1=RNF1     (both RNFs share the corner XP)
//   XP(1,0)  P0=HNF
//   XP(0,1)  (unused)
//   XP(1,1)  P0=SNF
//
// NID encoding (CHI TgtID, 7b): {Y[2:0], X[2:0], port}
//   RNF0=0x00, RNF1=0x01, HNF=0x02, SNF=0x12 (=18)
// SNF_NID_PARAM must be overridden to 18 at instantiation time when this
// adapter is used (override in tlm_rnf_hnf_tb.sv under `ifdef ICN_MESH).
//
// Build with ICN=mesh — see Makefile.

`include "chie_defines.v"
`include "hnf_defines.v"

module chi_icn_mesh #(
    parameter int CORE_COUNT             = 2,
    parameter int ICN_RNF_REQ_CRDTS      = 2,
    parameter int ICN_RNF_DAT_CRDTS      = 2,
    parameter int ICN_RNF_RSP_CRDTS      = 10,
    parameter int ICN_HNF_SNP_CRDTS      = 8,
    parameter int ICN_HNF_REQ_CRDTS      = 8,
    parameter int ICN_HNF_RSP_CRDTS      = 8,
    parameter int ICN_HNF_DAT_CRDTS      = 8,
    parameter int NUM_DATA_FLITS         = 2,
    parameter CHIE_REQ_ADDR_WIDTH_PARAM  = 44,
    parameter CHIE_SNP_ADDR_WIDTH_PARAM  = 41,
    parameter CHIE_NID_WIDTH_PARAM       = 7,
    parameter CHIE_DATA_WIDTH_PARAM      = 256,
    parameter CHIE_BE_WIDTH_PARAM        = 32,
    parameter CHIE_DATACHECK_WIDTH_PARAM = 0,
    parameter CHIE_POISON_WIDTH_PARAM    = 0,
    parameter CHIE_REQ_RSVDC_WIDTH_PARAM = 0,
    parameter CHIE_DAT_RSVDC_WIDTH_PARAM = 0,
    parameter HNF_MSHR_RNF_NUM_PARAM     = 4,
    parameter HNF_MSHR_RNI_NUM_PARAM     = 0,
    parameter RNF_NID_LIST_PARAM         = {7'd0, 7'd1},
    parameter RNI_NID_LIST_PARAM         = {7'd64},
    parameter HNF_NID_PARAM              = CORE_COUNT,
    parameter SNF_NID_PARAM              = 18,
    parameter XP_LCRD_NUM_PARAM          = 15,
    parameter HNF_SF_ENTRIES_NUM_PARAM   = 131072,
    parameter HNF_SF_WAY_NUM_PARAM       = 16,
    parameter HNF_MSHR_EXCL_RN_NUM_PARAM = 32,
    parameter HNF_MSHR_EXCL_RN_WIDTH_PARAM = 5,
    parameter HNF_MSHR_ENTRIES_NUM_PARAM = 32,
    parameter HNF_MSHR_ENTRIES_WIDTH_PARAM = 5,
    parameter HNF_L3_CACHE_SIZE_PARAM    = 4096,
    parameter HNF_L3_WAY_NUM_PARAM       = 16
)(
    input  logic clk,
    input  logic rst,

    // ===== RNF vectorised TX (TB → ICN) =====
    input  logic [CORE_COUNT-1:0]                                rnf_txreqflitv,
    input  logic [CORE_COUNT-1:0][`CHIE_REQ_FLIT_WIDTH-1:0]     rnf_txreqflit,
    output logic [CORE_COUNT-1:0]                                rnf_txreqlcrdv,
    input  logic [CORE_COUNT-1:0]                                rnf_txrspflitv,
    input  logic [CORE_COUNT-1:0][`CHIE_RSP_FLIT_WIDTH-1:0]     rnf_txrspflit,
    output logic [CORE_COUNT-1:0]                                rnf_txrsplcrdv,
    input  logic [CORE_COUNT-1:0]                                rnf_txdatflitv,
    input  logic [CORE_COUNT-1:0][`CHIE_DAT_FLIT_WIDTH-1:0]     rnf_txdatflit,
    output logic [CORE_COUNT-1:0]                                rnf_txdatlcrdv,

    // ===== RNF vectorised RX (ICN → TB) =====
    output logic [CORE_COUNT-1:0]                                rnf_rxsnpflitv,
    output logic [CORE_COUNT-1:0]                                rnf_rxsnppend,
    output logic [CORE_COUNT-1:0][`CHIE_SNP_FLIT_WIDTH-1:0]     rnf_rxsnpflit,
    input  logic [CORE_COUNT-1:0]                                rnf_rxsnplcrdv,
    output logic [CORE_COUNT-1:0]                                rnf_rxrspflitv,
    output logic [CORE_COUNT-1:0]                                rnf_rxrsppend,
    output logic [CORE_COUNT-1:0][`CHIE_RSP_FLIT_WIDTH-1:0]     rnf_rxrspflit,
    input  logic [CORE_COUNT-1:0]                                rnf_rxrsplcrdv,
    output logic [CORE_COUNT-1:0]                                rnf_rxdatflitv,
    output logic [CORE_COUNT-1:0]                                rnf_rxdatpend,
    output logic [CORE_COUNT-1:0][`CHIE_DAT_FLIT_WIDTH-1:0]     rnf_rxdatflit,
    input  logic [CORE_COUNT-1:0]                                rnf_rxdatlcrdv,

    // ===== Link activate (vectorised) =====
    input  logic [CORE_COUNT-1:0] rnf_txlinkactivereq,
    output logic [CORE_COUNT-1:0] rnf_txlinkactiveack,
    output logic [CORE_COUNT-1:0] rnf_rxlinkactivereq,
    input  logic [CORE_COUNT-1:0] rnf_rxlinkactiveack,
    input  logic [CORE_COUNT-1:0] rnf_txactive,
    output logic [CORE_COUNT-1:0] rnf_rxactive,

    // ===== HNF RX (ICN → HNF) =====
    output logic                                hnf_rxreqflitv,
    output logic [`CHIE_REQ_FLIT_WIDTH-1:0]     hnf_rxreqflit,
    output logic                                hnf_rxreqpend,
    input  logic                                hnf_rxreqlcrdv,
    output logic                                hnf_rxrspflitv,
    output logic [`CHIE_RSP_FLIT_WIDTH-1:0]     hnf_rxrspflit,
    output logic                                hnf_rxrsppend,
    input  logic                                hnf_rxrsplcrdv,
    output logic                                hnf_rxdatflitv,
    output logic [`CHIE_DAT_FLIT_WIDTH-1:0]     hnf_rxdatflit,
    output logic                                hnf_rxdatpend,
    input  logic                                hnf_rxdatlcrdv,

    // ===== HNF TX (HNF → ICN) =====
    input  logic                                hnf_txsnpflitv,
    // HNF emits 106-bit SNP flit (CHIE_SNP_FLIT_WIDTH + 7-bit target NID
    // in the upper 7 bits). Mesh routes on those upper bits.
    input  logic [`HNF_SNP_FLIT_WIDTH-1:0]      hnf_txsnpflit,
    input  logic                                hnf_txsnppend,
    output logic                                hnf_txsnplcrdv,
    input  logic                                hnf_txreqflitv,
    input  logic [`CHIE_REQ_FLIT_WIDTH-1:0]     hnf_txreqflit,
    input  logic                                hnf_txreqpend,
    output logic                                hnf_txreqlcrdv,
    input  logic                                hnf_txrspflitv,
    input  logic [`CHIE_RSP_FLIT_WIDTH-1:0]     hnf_txrspflit,
    input  logic                                hnf_txrsppend,
    output logic                                hnf_txrsplcrdv,
    input  logic                                hnf_txdatflitv,
    input  logic [`CHIE_DAT_FLIT_WIDTH-1:0]     hnf_txdatflit,
    input  logic                                hnf_txdatpend,
    output logic                                hnf_txdatlcrdv,

    // ===== SNF =====
    output logic                                snf_rxreqflitv,
    output logic [`CHIE_REQ_FLIT_WIDTH-1:0]     snf_rxreqflit,
    input  logic                                snf_rxreqlcrdv,
    output logic                                snf_rxdatflitv,
    output logic [`CHIE_DAT_FLIT_WIDTH-1:0]     snf_rxdatflit,
    input  logic                                snf_rxdatlcrdv,
    input  logic                                snf_txrspflitv,
    input  logic [`CHIE_RSP_FLIT_WIDTH-1:0]     snf_txrspflit,
    output logic                                snf_txrsplcrdv,
    input  logic                                snf_txdatflitv,
    input  logic [`CHIE_DAT_FLIT_WIDTH-1:0]     snf_txdatflit,
    output logic                                snf_txdatlcrdv,
    input  logic                                snf_txlinkactivereq,
    output logic                                snf_txlinkactiveack,
    output logic                                snf_rxlinkactivereq,
    input  logic                                snf_rxlinkactiveack,
    input  logic                                snf_txactive,
    output logic                                snf_rxactive
);

    // ============================================================================
    // DEBUG: structured-flit views (same shape as chi_icn_beh's _dbg signals)
    // Inspect via wave or examine to see parsed REQ/RSP/DAT/SNP fields at every
    // endpoint port, plus the inter-XP wires (mesh-specific).
    // ============================================================================

    typedef struct packed {
        logic                                    valid;
        logic                                    tracetag;
        logic [1:0]                              tagop;
        logic                                    expcompack;
        logic                                    excl;
        logic                                    snoopme;
        logic [7:0]                              lpid;
        logic                                    snpattr;
        logic                                    DoDWT;
        logic [3:0]                              memattr;
        logic [3:0]                              pcrdtype;
        logic [1:0]                              order;
        logic                                    allowretry;
        logic                                    likelyshared;
        logic                                    ns;
        logic [CHIE_REQ_ADDR_WIDTH_PARAM-1:0]    addr;
        logic [2:0]                              size;
        logic [6:0]                              opcode;
        logic [11:0]                             returntxnid;
        logic                                    stshv_endian;
        logic [CHIE_NID_WIDTH_PARAM-1:0]         return_stsh_nid;
        logic [11:0]                             txnid;
        logic [CHIE_NID_WIDTH_PARAM-1:0]         srcid;
        logic [CHIE_NID_WIDTH_PARAM-1:0]         tgtid;
        logic [3:0]                              qos;
    } chie_req_s;

    typedef struct packed {
        logic                                    valid;
        logic [CHIE_DATA_WIDTH_PARAM-1:0]        data;
        logic [CHIE_BE_WIDTH_PARAM-1:0]          be;
        logic                                    tracetag;
        logic [(CHIE_DATA_WIDTH_PARAM/128)-1:0]  tu;
        logic [(CHIE_DATA_WIDTH_PARAM/32)-1:0]   tag;
        logic [1:0]                              tagop;
        logic [1:0]                              dataid;
        logic [1:0]                              ccid;
        logic [11:0]                             dbid;
        logic [2:0]                              cbusy;
        logic [3:0]                              attr;
        logic [2:0]                              resp;
        logic [1:0]                              resperr;
        logic [3:0]                              opcode;
        logic [CHIE_NID_WIDTH_PARAM-1:0]         homenid;
        logic [11:0]                             txnid;
        logic [CHIE_NID_WIDTH_PARAM-1:0]         srcid;
        logic [CHIE_NID_WIDTH_PARAM-1:0]         tgtid;
        logic [3:0]                              qos;
    } chie_dat_s;

    typedef struct packed {
        logic                                    valid;
        logic                                    tracetag;
        logic [1:0]                              tagop;
        logic [3:0]                              pcrdtype;
        logic [11:0]                             dbid;
        logic [2:0]                              cbusy;
        logic [2:0]                              fwd_pull;
        logic [2:0]                              resp;
        logic [1:0]                              resperr;
        logic [4:0]                              opcode;
        logic [11:0]                             txnid;
        logic [CHIE_NID_WIDTH_PARAM-1:0]         srcid;
        logic [CHIE_NID_WIDTH_PARAM-1:0]         tgtid;
        logic [3:0]                              qos;
    } chie_rsp_s;

    typedef struct packed {
        logic                                    valid;
        logic                                    tracetag;
        logic [1:0]                              tagop;
        logic                                    do_not_goto_sd;
        logic                                    ret_to_src;
        logic [11:0]                             fwdtxnid;
        logic [CHIE_NID_WIDTH_PARAM-1:0]         fwdnid;
        logic                                    ns;
        logic [CHIE_REQ_ADDR_WIDTH_PARAM-1:0]    addr;
        logic [4:0]                              opcode;
        logic [11:0]                             txnid;
        logic [CHIE_NID_WIDTH_PARAM-1:0]         srcid;
        logic [CHIE_NID_WIDTH_PARAM-1:0]         tgtid;
        logic [3:0]                              qos;
    } chie_snp_s;

    function automatic chie_req_s parse_req_flit(
            logic [`CHIE_REQ_FLIT_WIDTH-1:0] raw_flit, logic valid);
        chie_req_s s;
        s.valid           = valid;
        s.qos             = raw_flit[`CHIE_REQ_FLIT_QOS_RANGE];
        s.tgtid           = raw_flit[`CHIE_REQ_FLIT_TGTID_RANGE];
        s.srcid           = raw_flit[`CHIE_REQ_FLIT_SRCID_RANGE];
        s.txnid           = raw_flit[`CHIE_REQ_FLIT_TXNID_RANGE];
        s.return_stsh_nid = raw_flit[`CHIE_REQ_FLIT_RETURNNID_RANGE];
        s.stshv_endian    = raw_flit[`CHIE_REQ_FLIT_STASHNIDVALID_RANGE];
        s.returntxnid     = raw_flit[`CHIE_REQ_FLIT_RETURNTXNID_RANGE];
        s.opcode          = raw_flit[`CHIE_REQ_FLIT_OPCODE_RANGE];
        s.size            = raw_flit[`CHIE_REQ_FLIT_SIZE_RANGE];
        s.addr            = raw_flit[`CHIE_REQ_FLIT_ADDR_RANGE];
        s.ns              = raw_flit[`CHIE_REQ_FLIT_NS_RANGE];
        s.likelyshared    = raw_flit[`CHIE_REQ_FLIT_LIKELYSHARED_RANGE];
        s.allowretry      = raw_flit[`CHIE_REQ_FLIT_ALLOWRETRY_RANGE];
        s.order           = raw_flit[`CHIE_REQ_FLIT_ORDER_RANGE];
        s.pcrdtype        = raw_flit[`CHIE_REQ_FLIT_PCRDTYPE_RANGE];
        s.memattr         = raw_flit[`CHIE_REQ_FLIT_MEMATTR_RANGE];
        s.snpattr         = raw_flit[`CHIE_REQ_FLIT_SNPATTR_RANGE];
        s.DoDWT           = raw_flit[`CHIE_REQ_FLIT_DODWT_RANGE];
        s.lpid            = raw_flit[`CHIE_REQ_FLIT_LPID_RANGE];
        s.excl            = raw_flit[`CHIE_REQ_FLIT_EXCL_RANGE];
        s.snoopme         = raw_flit[`CHIE_REQ_FLIT_SNOOPME_RANGE];
        s.expcompack      = raw_flit[`CHIE_REQ_FLIT_EXPCOMPACK_RANGE];
        s.tagop           = raw_flit[`CHIE_REQ_FLIT_TAGOP_RANGE];
        s.tracetag        = raw_flit[`CHIE_REQ_FLIT_TRACETAG_RANGE];
        return s;
    endfunction

    function automatic chie_dat_s parse_dat_flit(
            logic [`CHIE_DAT_FLIT_WIDTH-1:0] raw_flit, logic valid);
        chie_dat_s s;
        s.valid     = valid;
        s.qos       = raw_flit[`CHIE_DAT_FLIT_QOS_RANGE];
        s.tgtid     = raw_flit[`CHIE_DAT_FLIT_TGTID_RANGE];
        s.srcid     = raw_flit[`CHIE_DAT_FLIT_SRCID_RANGE];
        s.txnid     = raw_flit[`CHIE_DAT_FLIT_TXNID_RANGE];
        s.homenid   = raw_flit[`CHIE_DAT_FLIT_HOMENID_RANGE];
        s.opcode    = raw_flit[`CHIE_DAT_FLIT_OPCODE_RANGE];
        s.resperr   = raw_flit[`CHIE_DAT_FLIT_RESPERR_RANGE];
        s.resp      = raw_flit[`CHIE_DAT_FLIT_RESP_RANGE];
        s.attr      = raw_flit[`CHIE_DAT_FLIT_DATASOURCE_RANGE];
        s.cbusy     = raw_flit[`CHIE_DAT_FLIT_CBUSY_RANGE];
        s.dbid      = raw_flit[`CHIE_DAT_FLIT_DBID_RANGE];
        s.ccid      = raw_flit[`CHIE_DAT_FLIT_CCID_RANGE];
        s.dataid    = raw_flit[`CHIE_DAT_FLIT_DATAID_RANGE];
        s.tagop     = raw_flit[`CHIE_DAT_FLIT_TAGOP_RANGE];
        s.tag       = raw_flit[`CHIE_DAT_FLIT_TAG_RANGE];
        s.tu        = raw_flit[`CHIE_DAT_FLIT_TU_RANGE];
        s.tracetag  = raw_flit[`CHIE_DAT_FLIT_TRACETAG_RANGE];
        s.be        = raw_flit[`CHIE_DAT_FLIT_BE_RANGE];
        s.data      = raw_flit[`CHIE_DAT_FLIT_DATA_RANGE];
        return s;
    endfunction

    function automatic chie_rsp_s parse_rsp_flit(
            logic [`CHIE_RSP_FLIT_WIDTH-1:0] raw_flit, logic valid);
        chie_rsp_s s;
        s.valid     = valid;
        s.qos       = raw_flit[`CHIE_RSP_FLIT_QOS_RANGE];
        s.tgtid     = raw_flit[`CHIE_RSP_FLIT_TGTID_RANGE];
        s.srcid     = raw_flit[`CHIE_RSP_FLIT_SRCID_RANGE];
        s.txnid     = raw_flit[`CHIE_RSP_FLIT_TXNID_RANGE];
        s.opcode    = raw_flit[`CHIE_RSP_FLIT_OPCODE_RANGE];
        s.resperr   = raw_flit[`CHIE_RSP_FLIT_RESPERR_RANGE];
        s.resp      = raw_flit[`CHIE_RSP_FLIT_RESP_RANGE];
        s.fwd_pull  = raw_flit[`CHIE_RSP_FLIT_FWDSTATE_RANGE];
        s.cbusy     = raw_flit[`CHIE_RSP_FLIT_CBUSY_RANGE];
        s.dbid      = raw_flit[`CHIE_RSP_FLIT_DBID_RANGE];
        s.pcrdtype  = raw_flit[`CHIE_RSP_FLIT_PCRDTYPE_RANGE];
        s.tagop     = raw_flit[`CHIE_RSP_FLIT_TAGOP_RANGE];
        s.tracetag  = raw_flit[`CHIE_RSP_FLIT_TRACETAG_RANGE];
        return s;
    endfunction

    function automatic chie_snp_s parse_snp_flit(
            logic [`CHIE_SNP_FLIT_WIDTH-1:0] raw_flit, logic valid);
        chie_snp_s s;
        s.valid          = valid;
        s.qos            = raw_flit[`CHIE_SNP_FLIT_QOS_RANGE];
        s.srcid          = raw_flit[`CHIE_SNP_FLIT_SRCID_RANGE];
        s.tgtid          = raw_flit[`CHIE_SNP_FLIT_TGTID_RANGE];
        s.txnid          = raw_flit[`CHIE_SNP_FLIT_TXNID_RANGE];
        s.opcode         = raw_flit[`CHIE_SNP_FLIT_OPCODE_RANGE];
        s.addr           = raw_flit[`CHIE_SNP_FLIT_ADDR_RANGE];
        s.ns             = raw_flit[`CHIE_SNP_FLIT_NS_RANGE];
        s.fwdnid         = raw_flit[`CHIE_SNP_FLIT_FWDNID_RANGE];
        s.fwdtxnid       = raw_flit[`CHIE_SNP_FLIT_FWDTXNID_RANGE];
        s.ret_to_src     = raw_flit[`CHIE_SNP_FLIT_RETTOSRC_RANGE];
        s.do_not_goto_sd = raw_flit[`CHIE_SNP_FLIT_DONOTGOTOSD_RANGE];
        s.tracetag       = raw_flit[`CHIE_SNP_FLIT_TRACETAG_RANGE];
        return s;
    endfunction

    // ── Per-endpoint parsed flit views ─────────────────────────────────────
    // RNF TX (driver → mesh)
    chie_req_s [CORE_COUNT-1:0] rnf_txreqflit_dbg;
    chie_rsp_s [CORE_COUNT-1:0] rnf_txrspflit_dbg;
    chie_dat_s [CORE_COUNT-1:0] rnf_txdatflit_dbg;
    // RNF RX (mesh → driver)
    chie_rsp_s [CORE_COUNT-1:0] rnf_rxrspflit_dbg;
    chie_dat_s [CORE_COUNT-1:0] rnf_rxdatflit_dbg;
    chie_snp_s [CORE_COUNT-1:0] rnf_rxsnpflit_dbg;
    // HNF RX (mesh → HNF)
    chie_req_s hnf_rxreqflit_dbg;
    chie_rsp_s hnf_rxrspflit_dbg;
    chie_dat_s hnf_rxdatflit_dbg;
    // HNF TX (HNF → mesh) — txsnp uses lower 99 bits (upper 7 = TgtID for routing)
    chie_req_s hnf_txreqflit_dbg;
    chie_rsp_s hnf_txrspflit_dbg;
    chie_dat_s hnf_txdatflit_dbg;
    chie_snp_s hnf_txsnpflit_dbg;
    // SNF (memory) — RX from HNF, TX to HNF
    chie_req_s snf_rxreqflit_dbg;
    chie_dat_s snf_rxdatflit_dbg;
    chie_rsp_s snf_txrspflit_dbg;
    chie_dat_s snf_txdatflit_dbg;

    // HNF doesn't have link-activate at its module port — wire it always-active.
    logic hnf_la_tied = 1'b1;
    logic hnf_la_unused;

    // ── Initial-credit injection ───────────────────────────────────────────────
    // chi_icn_beh tracks HNF/SNF credits internally (hardcoded
    // hnf_rx_req_crdts=4 at line 1050) because the HNF only PULSES
    // rxreq_lcrdv on flit arrival, never advertising its initial
    // Endpoint LCRDV grants pass through unmodified.
    // RTL endpoints (HNF, SNF) naturally emit their initial credit burst
    // at reset deassertion via their own link-layer FSMs. The chi_xp_channel
    // TX credit counter is only 4 bits wide (LCRD_NUM_WIDTH=4, max=15) and
    // any extra injected pulses on top of the endpoint's natural burst can
    // wrap the counter (15→0), bricking the credit flow.
    wire hnf_rxreqlcrdv_eff = hnf_rxreqlcrdv;
    wire hnf_rxrsplcrdv_eff = hnf_rxrsplcrdv;
    wire hnf_rxdatlcrdv_eff = hnf_rxdatlcrdv;
    wire snf_rxreqlcrdv_eff = snf_rxreqlcrdv;
    wire snf_rxdatlcrdv_eff = snf_rxdatlcrdv;

    mesh_wrapper_2x2 #(
        .REQ_FLIT_WIDTH (`CHIE_REQ_FLIT_WIDTH),
        .RSP_FLIT_WIDTH (`CHIE_RSP_FLIT_WIDTH),
        .DAT_FLIT_WIDTH (`CHIE_DAT_FLIT_WIDTH),
        .SNP_FLIT_WIDTH (`CHIE_SNP_FLIT_WIDTH)
    ) u_mesh (
        .clk   (clk),
        .reset (rst),

        // -------- XP_0_0_P0 = RNF0 --------
        .XP_0_0_P0_TXSACTIVE       (rnf_txactive[0]),
        .XP_0_0_P0_RXSACTIVE       (rnf_rxactive[0]),
        .XP_0_0_P0_TXLINKACTIVEREQ (rnf_txlinkactivereq[0]),
        .XP_0_0_P0_TXLINKACTIVEACK (rnf_txlinkactiveack[0]),
        .XP_0_0_P0_RXLINKACTIVEREQ (rnf_rxlinkactivereq[0]),
        .XP_0_0_P0_RXLINKACTIVEACK (rnf_rxlinkactiveack[0]),
        .XP_0_0_P0_TXREQFLITPEND   (1'b0),
        .XP_0_0_P0_TXREQFLITV      (rnf_txreqflitv[0]),
        .XP_0_0_P0_TXREQFLIT       (rnf_txreqflit[0]),
        .XP_0_0_P0_TXREQLCRDV      (rnf_txreqlcrdv[0]),
        .XP_0_0_P0_TXRSPFLITPEND   (1'b0),
        .XP_0_0_P0_TXRSPFLITV      (rnf_txrspflitv[0]),
        .XP_0_0_P0_TXRSPFLIT       (rnf_txrspflit[0]),
        .XP_0_0_P0_TXRSPLCRDV      (rnf_txrsplcrdv[0]),
        .XP_0_0_P0_RXRSPFLITPEND   (rnf_rxrsppend[0]),
        .XP_0_0_P0_RXRSPFLITV      (rnf_rxrspflitv[0]),
        .XP_0_0_P0_RXRSPFLIT       (rnf_rxrspflit[0]),
        .XP_0_0_P0_RXRSPLCRDV      (rnf_rxrsplcrdv[0]),
        .XP_0_0_P0_TXDATFLITPEND   (1'b0),
        .XP_0_0_P0_TXDATFLITV      (rnf_txdatflitv[0]),
        .XP_0_0_P0_TXDATFLIT       (rnf_txdatflit[0]),
        .XP_0_0_P0_TXDATLCRDV      (rnf_txdatlcrdv[0]),
        .XP_0_0_P0_RXDATFLITPEND   (rnf_rxdatpend[0]),
        .XP_0_0_P0_RXDATFLITV      (rnf_rxdatflitv[0]),
        .XP_0_0_P0_RXDATFLIT       (rnf_rxdatflit[0]),
        .XP_0_0_P0_RXDATLCRDV      (rnf_rxdatlcrdv[0]),
        .XP_0_0_P0_RXSNPFLITPEND   (rnf_rxsnppend[0]),
        .XP_0_0_P0_RXSNPFLITV      (rnf_rxsnpflitv[0]),
        .XP_0_0_P0_RXSNPFLIT       (rnf_rxsnpflit[0]),
        .XP_0_0_P0_RXSNPLCRDV      (rnf_rxsnplcrdv[0]),

        // -------- XP_0_0_P1 = RNF1 --------
        .XP_0_0_P1_TXSACTIVE       (rnf_txactive[1]),
        .XP_0_0_P1_RXSACTIVE       (rnf_rxactive[1]),
        .XP_0_0_P1_TXLINKACTIVEREQ (rnf_txlinkactivereq[1]),
        .XP_0_0_P1_TXLINKACTIVEACK (rnf_txlinkactiveack[1]),
        .XP_0_0_P1_RXLINKACTIVEREQ (rnf_rxlinkactivereq[1]),
        .XP_0_0_P1_RXLINKACTIVEACK (rnf_rxlinkactiveack[1]),
        .XP_0_0_P1_TXREQFLITPEND   (1'b0),
        .XP_0_0_P1_TXREQFLITV      (rnf_txreqflitv[1]),
        .XP_0_0_P1_TXREQFLIT       (rnf_txreqflit[1]),
        .XP_0_0_P1_TXREQLCRDV      (rnf_txreqlcrdv[1]),
        .XP_0_0_P1_TXRSPFLITPEND   (1'b0),
        .XP_0_0_P1_TXRSPFLITV      (rnf_txrspflitv[1]),
        .XP_0_0_P1_TXRSPFLIT       (rnf_txrspflit[1]),
        .XP_0_0_P1_TXRSPLCRDV      (rnf_txrsplcrdv[1]),
        .XP_0_0_P1_RXRSPFLITPEND   (rnf_rxrsppend[1]),
        .XP_0_0_P1_RXRSPFLITV      (rnf_rxrspflitv[1]),
        .XP_0_0_P1_RXRSPFLIT       (rnf_rxrspflit[1]),
        .XP_0_0_P1_RXRSPLCRDV      (rnf_rxrsplcrdv[1]),
        .XP_0_0_P1_TXDATFLITPEND   (1'b0),
        .XP_0_0_P1_TXDATFLITV      (rnf_txdatflitv[1]),
        .XP_0_0_P1_TXDATFLIT       (rnf_txdatflit[1]),
        .XP_0_0_P1_TXDATLCRDV      (rnf_txdatlcrdv[1]),
        .XP_0_0_P1_RXDATFLITPEND   (rnf_rxdatpend[1]),
        .XP_0_0_P1_RXDATFLITV      (rnf_rxdatflitv[1]),
        .XP_0_0_P1_RXDATFLIT       (rnf_rxdatflit[1]),
        .XP_0_0_P1_RXDATLCRDV      (rnf_rxdatlcrdv[1]),
        .XP_0_0_P1_RXSNPFLITPEND   (rnf_rxsnppend[1]),
        .XP_0_0_P1_RXSNPFLITV      (rnf_rxsnpflitv[1]),
        .XP_0_0_P1_RXSNPFLIT       (rnf_rxsnpflit[1]),
        .XP_0_0_P1_RXSNPLCRDV      (rnf_rxsnplcrdv[1]),

        // -------- XP_1_0_P0 = HNF (link-activate tied always-on) --------
        .XP_1_0_P0_TXSACTIVE       (1'b1),
        .XP_1_0_P0_RXSACTIVE       (hnf_la_unused),
        .XP_1_0_P0_TXLINKACTIVEREQ (1'b1),
        .XP_1_0_P0_TXLINKACTIVEACK (),
        .XP_1_0_P0_RXLINKACTIVEREQ (),
        .XP_1_0_P0_RXLINKACTIVEACK (1'b1),
        .XP_1_0_P0_TXREQFLITPEND   (hnf_txreqpend),
        .XP_1_0_P0_TXREQFLITV      (hnf_txreqflitv),
        .XP_1_0_P0_TXREQFLIT       (hnf_txreqflit),
        .XP_1_0_P0_TXREQLCRDV      (hnf_txreqlcrdv),
        .XP_1_0_P0_RXREQFLITPEND   (hnf_rxreqpend),
        .XP_1_0_P0_RXREQFLITV      (hnf_rxreqflitv),
        .XP_1_0_P0_RXREQFLIT       (hnf_rxreqflit),
        .XP_1_0_P0_RXREQLCRDV      (hnf_rxreqlcrdv_eff),
        .XP_1_0_P0_TXRSPFLITPEND   (hnf_txrsppend),
        .XP_1_0_P0_TXRSPFLITV      (hnf_txrspflitv),
        .XP_1_0_P0_TXRSPFLIT       (hnf_txrspflit),
        .XP_1_0_P0_TXRSPLCRDV      (hnf_txrsplcrdv),
        .XP_1_0_P0_RXRSPFLITPEND   (hnf_rxrsppend),
        .XP_1_0_P0_RXRSPFLITV      (hnf_rxrspflitv),
        .XP_1_0_P0_RXRSPFLIT       (hnf_rxrspflit),
        .XP_1_0_P0_RXRSPLCRDV      (hnf_rxrsplcrdv_eff),
        .XP_1_0_P0_TXDATFLITPEND   (hnf_txdatpend),
        .XP_1_0_P0_TXDATFLITV      (hnf_txdatflitv),
        .XP_1_0_P0_TXDATFLIT       (hnf_txdatflit),
        .XP_1_0_P0_TXDATLCRDV      (hnf_txdatlcrdv),
        .XP_1_0_P0_RXDATFLITPEND   (hnf_rxdatpend),
        .XP_1_0_P0_RXDATFLITV      (hnf_rxdatflitv),
        .XP_1_0_P0_RXDATFLIT       (hnf_rxdatflit),
        .XP_1_0_P0_RXDATLCRDV      (hnf_rxdatlcrdv_eff),
        .XP_1_0_P0_TXSNPFLITPEND   (hnf_txsnppend),
        .XP_1_0_P0_TXSNPFLITV      (hnf_txsnpflitv),
        .XP_1_0_P0_TXSNPFLIT       (hnf_txsnpflit),
        .XP_1_0_P0_TXSNPLCRDV      (hnf_txsnplcrdv),

        // -------- XP_1_1_P0 = SNF --------
        .XP_1_1_P0_TXSACTIVE       (snf_txactive),
        .XP_1_1_P0_RXSACTIVE       (snf_rxactive),
        .XP_1_1_P0_TXLINKACTIVEREQ (snf_txlinkactivereq),
        .XP_1_1_P0_TXLINKACTIVEACK (snf_txlinkactiveack),
        .XP_1_1_P0_RXLINKACTIVEREQ (snf_rxlinkactivereq),
        .XP_1_1_P0_RXLINKACTIVEACK (snf_rxlinkactiveack),
        .XP_1_1_P0_RXREQFLITPEND   (),
        .XP_1_1_P0_RXREQFLITV      (snf_rxreqflitv),
        .XP_1_1_P0_RXREQFLIT       (snf_rxreqflit),
        .XP_1_1_P0_RXREQLCRDV      (snf_rxreqlcrdv_eff),
        .XP_1_1_P0_TXRSPFLITPEND   (1'b0),
        .XP_1_1_P0_TXRSPFLITV      (snf_txrspflitv),
        .XP_1_1_P0_TXRSPFLIT       (snf_txrspflit),
        .XP_1_1_P0_TXRSPLCRDV      (snf_txrsplcrdv),
        .XP_1_1_P0_TXDATFLITPEND   (1'b0),
        .XP_1_1_P0_TXDATFLITV      (snf_txdatflitv),
        .XP_1_1_P0_TXDATFLIT       (snf_txdatflit),
        .XP_1_1_P0_TXDATLCRDV      (snf_txdatlcrdv),
        .XP_1_1_P0_RXDATFLITPEND   (),
        .XP_1_1_P0_RXDATFLITV      (snf_rxdatflitv),
        .XP_1_1_P0_RXDATFLIT       (snf_rxdatflit),
        .XP_1_1_P0_RXDATLCRDV      (snf_rxdatlcrdv_eff)
    );

    // ── Drive the parsed-flit debug views every cycle ─────────────────────
    always_comb begin
        // RNF TX (driver → mesh)
        for (int i = 0; i < CORE_COUNT; i++) begin
            rnf_txreqflit_dbg[i] = parse_req_flit(rnf_txreqflit[i], rnf_txreqflitv[i]);
            rnf_txrspflit_dbg[i] = parse_rsp_flit(rnf_txrspflit[i], rnf_txrspflitv[i]);
            rnf_txdatflit_dbg[i] = parse_dat_flit(rnf_txdatflit[i], rnf_txdatflitv[i]);
            // RNF RX (mesh → driver)
            rnf_rxrspflit_dbg[i] = parse_rsp_flit(rnf_rxrspflit[i], rnf_rxrspflitv[i]);
            rnf_rxdatflit_dbg[i] = parse_dat_flit(rnf_rxdatflit[i], rnf_rxdatflitv[i]);
            rnf_rxsnpflit_dbg[i] = parse_snp_flit(rnf_rxsnpflit[i], rnf_rxsnpflitv[i]);
        end
        // HNF RX (mesh → HNF)
        hnf_rxreqflit_dbg = parse_req_flit(hnf_rxreqflit, hnf_rxreqflitv);
        hnf_rxrspflit_dbg = parse_rsp_flit(hnf_rxrspflit, hnf_rxrspflitv);
        hnf_rxdatflit_dbg = parse_dat_flit(hnf_rxdatflit, hnf_rxdatflitv);
        // HNF TX (HNF → mesh)
        hnf_txreqflit_dbg = parse_req_flit(hnf_txreqflit, hnf_txreqflitv);
        hnf_txrspflit_dbg = parse_rsp_flit(hnf_txrspflit, hnf_txrspflitv);
        hnf_txdatflit_dbg = parse_dat_flit(hnf_txdatflit, hnf_txdatflitv);
        // SNP from HNF is 106 bits; lower 99 are the standard CHI SNP flit
        // (upper 7 are the routing TgtID, already inside the std flit).
        hnf_txsnpflit_dbg = parse_snp_flit(hnf_txsnpflit[`CHIE_SNP_FLIT_WIDTH-1:0],
                                          hnf_txsnpflitv);
        // SNF
        snf_rxreqflit_dbg = parse_req_flit(snf_rxreqflit, snf_rxreqflitv);
        snf_rxdatflit_dbg = parse_dat_flit(snf_rxdatflit, snf_rxdatflitv);
        snf_txrspflit_dbg = parse_rsp_flit(snf_txrspflit, snf_txrspflitv);
        snf_txdatflit_dbg = parse_dat_flit(snf_txdatflit, snf_txdatflitv);
    end

endmodule
