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

//`include "rnf_param.v"
`include "rnf_defines.v"

//`include "hnf_param.v"
`include "hnf_defines.v"

//`include "snf_param.v"
`include "snf_defines.v"

`include "chie_defines.v"

// `define DEBUG 1
// `define TB_SNF 1
// `define TB_NO_MONITOR


module tb_chi_system;

  parameter int  CORE_COUNT = 1;
  parameter real CLK_PERIOD = 10.0;

  parameter CHIE_REQ_ADDR_WIDTH_PARAM = 44;
  parameter CHIE_SNP_ADDR_WIDTH_PARAM = 41;
  parameter CHIE_NID_WIDTH_PARAM = 7;
  parameter CHIE_DATA_WIDTH_PARAM = 256;
  parameter CHIE_BE_WIDTH_PARAM = 32;
  parameter CHIE_DATACHECK_WIDTH_PARAM = 0;
  parameter CHIE_POISON_WIDTH_PARAM = 0;
  parameter CHIE_REQ_RSVDC_WIDTH_PARAM = 0;
  parameter CHIE_DAT_RSVDC_WIDTH_PARAM = 0;
  parameter HNF_MSHR_RNF_NUM_PARAM = 4;
  parameter HNF_MSHR_RNI_NUM_PARAM = 0;
  parameter RNF_NID_LIST_PARAM = {7'd0, 7'd1};
  parameter RNI_NID_LIST_PARAM = {7'd64};
  parameter HNF_NID_PARAM = CORE_COUNT;
  parameter SNF_NID_PARAM = 32;
  parameter XP_LCRD_NUM_PARAM = 15;
  parameter HNF_SF_ENTRIES_NUM_PARAM = 131072;
  parameter HNF_SF_WAY_NUM_PARAM = 16;
  parameter HNF_MSHR_EXCL_RN_NUM_PARAM = 32;
  parameter HNF_MSHR_EXCL_RN_WIDTH_PARAM = 5;
  parameter HNF_MSHR_ENTRIES_NUM_PARAM = 32;
  parameter HNF_MSHR_ENTRIES_WIDTH_PARAM = 5;
  parameter HNF_L3_CACHE_SIZE_PARAM = 4096;
  parameter HNF_L3_WAY_NUM_PARAM = 16;

  // --- Global Signals ---
  logic clk;
  logic rst_n;
  logic clk_en;
  logic program_load_done;

  // --- Interconnect Wires (RNF side - Vectorized) ---
  // RX Path
  logic [CORE_COUNT-1:0]                      rnf_rxrspflitv, rnf_rxrspflitpend;
  logic [CORE_COUNT*`CHIE_RSP_FLIT_WIDTH-1:0] rnf_rxrspflit;
  logic [CORE_COUNT-1:0]                      rnf_rxdatflitv, rnf_rxdatflitpend;
  logic [CORE_COUNT*`CHIE_DAT_FLIT_WIDTH-1:0] rnf_rxdatflit;
  logic [CORE_COUNT-1:0]                      rnf_rxsnpflitv, rnf_rxsnpflitpend;
  logic [CORE_COUNT*`CHIE_SNP_FLIT_WIDTH-1:0] rnf_rxsnpflit;

  // TX Path
  logic [CORE_COUNT-1:0]                      rnf_txreqflitv, rnf_txreqflitpend;
  logic [CORE_COUNT*`CHIE_REQ_FLIT_WIDTH-1:0] rnf_txreqflit;
  logic [CORE_COUNT-1:0]                      rnf_txrspflitv, rnf_txrspflitpend;
  logic [CORE_COUNT*`CHIE_RSP_FLIT_WIDTH-1:0] rnf_txrspflit;
  logic [CORE_COUNT-1:0]                      rnf_txdatflitv, rnf_txdatflitpend;
  logic [CORE_COUNT*`CHIE_DAT_FLIT_WIDTH-1:0] rnf_txdatflit;

  // Link Credits
  logic [CORE_COUNT-1:0] rnf_txreqlcrdv, rnf_txrsplcrdv, rnf_txdatlcrdv;
  logic [CORE_COUNT-1:0] rnf_rxrsplcrdv, rnf_rxdatlcrdv, rnf_rxsnplcrdv;
  logic [CORE_COUNT-1:0] icn_rnf_rxsnppend, icn_rnf_rxdatpend, icn_rnf_rxrsppend;

  // --- Handshake Signals ---
  logic [CORE_COUNT-1:0] rnf_txlinkactivereq, rnf_txlinkactiveack;
  logic [CORE_COUNT-1:0] rnf_rxlinkactivereq, rnf_rxlinkactiveack;
  logic [CORE_COUNT-1:0] rnf_txactive, rnf_rxactive;


  // --- HNF Bridge Signals ---
  logic                        hnf_txreqflitv, hnf_txreqflitpend;
  logic [`CHIE_REQ_FLIT_RANGE] hnf_txreqflit;
  logic                        hnf_txrspflitv, hnf_txrspflitpend;
  logic [`CHIE_RSP_FLIT_RANGE] hnf_txrspflit;
  logic                        hnf_txdatflitv, hnf_txdatflitpend;
  logic [`CHIE_DAT_FLIT_RANGE] hnf_txdatflit;

  logic                        hnf_rxreqflitv, hnf_rxreqflitpend;
  logic [`CHIE_REQ_FLIT_RANGE] hnf_rxreqflit;

  logic                        hnf_rxrspflitv, hnf_rxrspflitpend;
  logic [`CHIE_RSP_FLIT_RANGE] hnf_rxrspflit;
  logic                        hnf_rxsnpflitv, hnf_rxsnpflitpend;
  logic [`HNF_SNP_FLIT_RANGE]  hnf_rxsnpflit;
  logic                        hnf_rxdatflitv, hnf_rxdatflitpend;
  logic [`CHIE_DAT_FLIT_RANGE] hnf_rxdatflit;

  logic       hnf_txreqlcrdv, hnf_txrsplcrdv, hnf_txdatlcrdv, hnf_txsnplcrdv;
  logic       hnf_rxrsplcrdv, hnf_rxsnplcrdv, hnf_rxdatlcrdv;
  logic [2:0] hnf_notify;

  // --- SNF Signals
  logic                        snf_rxreqflitv, snf_rxreqflitpend;
  logic [`CHIE_REQ_FLIT_RANGE] snf_rxreqflit;

  logic                        snf_rxdatflitv, snf_rxdatflitpend;
  logic [`CHIE_DAT_FLIT_RANGE] snf_rxdatflit;

  logic                        snf_txrspflitv, snf_txrspflitpend;
  logic [`CHIE_RSP_FLIT_RANGE] snf_txrspflit;

  logic                        snf_txdatflitv, snf_txdatflitpend;
  logic [`CHIE_DAT_FLIT_RANGE] snf_txdatflit;

  // Credits for SNF
  logic snf_txreqlcrdv, snf_txdatlcrdv; // SNF receiving
  logic snf_rxrsplcrdv, snf_rxdatlcrdv_out; // SNF sending
  logic snf_rst_n;

  // TB signals for pre-loading the SN-F
  logic                        tb_snf_rxreqflitv, tb_snf_rxreqflitpend;
  logic [`CHIE_REQ_FLIT_RANGE] tb_snf_rxreqflit;

  logic                        tb_snf_rxdatflitv, tb_snf_rxdatflitpend;
  logic [`CHIE_DAT_FLIT_RANGE] tb_snf_rxdatflit;

  // ICN2SN-F signals
  logic                        icn_snf_rxreqflitv, icn_snf_rxreqflitpend;
  logic [`CHIE_REQ_FLIT_RANGE] icn_snf_rxreqflit;

  logic                        icn_snf_rxdatflitv, icn_snf_rxdatflitpend;
  logic [`CHIE_DAT_FLIT_RANGE] icn_snf_rxdatflit;
  logic                        icn_snf_txdatlcrdv, icn_snf_txrsplcrdv;
  // HNF
  logic                        icn_hnf_rxreqflitv, icn_hnf_rxreqpend;
  logic [`CHIE_REQ_FLIT_RANGE] icn_hnf_rxreqflit;

  logic                        icn_hnf_rxdatflitv, icn_hnf_rxdatpend;
  logic [`CHIE_DAT_FLIT_RANGE] icn_hnf_rxdatflit;

  logic                        icn_hnf_rxrspflitv, icn_hnf_rxrsppend;
  logic [`CHIE_RSP_FLIT_RANGE] icn_hnf_rxrspflit;

  logic hnf_rxreqlcrdv;


  // --- REQ Channel (Request) ---
  typedef struct packed {
      logic [CHIE_REQ_RSVDC_WIDTH_PARAM-1:0]   rsvdc;         // Top MSB
      logic                                    tracetag;
      logic [1:0]                              tagop;
      logic                                    expcompack;
      logic                                    snoopme_excl;  // Shared Bit
      logic [7:0]                              lpid;
      logic                                    dodwt_snpattr; // Shared Bit
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
      logic                                    stshv_endian;  // Shared Bit
      logic [CHIE_NID_WIDTH_PARAM-1:0]         return_stsh_nid;
      logic [11:0]                             txnid;
      logic [CHIE_NID_WIDTH_PARAM-1:0]         srcid;
      logic [CHIE_NID_WIDTH_PARAM-1:0]         tgtid;
      logic [3:0]                              qos;           // LSB 0
  } chie_req_s;

  // --- DAT Channel (Data) ---
  typedef struct packed {
      logic [CHIE_POISON_WIDTH_PARAM-1:0]      poison;        // Absolute MSB
      logic [CHIE_DATACHECK_WIDTH_PARAM-1:0]   datacheck;
      logic [CHIE_DATA_WIDTH_PARAM-1:0]        data;
      logic [CHIE_BE_WIDTH_PARAM-1:0]          be;
      logic [CHIE_DAT_RSVDC_WIDTH_PARAM-1:0]   rsvdc;
      logic                                    tracetag;
      logic [(CHIE_DATA_WIDTH_PARAM/128)-1:0]  tu;
      logic [(CHIE_DATA_WIDTH_PARAM/32)-1:0]   tag;
      logic [1:0]                              tagop;
      logic [1:0]                              dataid;
      logic [1:0]                              ccid;
      logic [11:0]                             dbid;
      logic [2:0]                              cbusy;
      union packed {
          logic [3:0]                          datasource;
          logic [3:0]                          fwdstate;
          logic [3:0]                          datapull;
      } attr;
      logic [2:0]                              resp;
      logic [1:0]                              resperr;
      logic [3:0]                              opcode;
      logic [CHIE_NID_WIDTH_PARAM-1:0]         homenid;
      logic [11:0]                             txnid;
      logic [CHIE_NID_WIDTH_PARAM-1:0]         srcid;
      logic [CHIE_NID_WIDTH_PARAM-1:0]         tgtid;
      logic [3:0]                              qos;           // LSB 0
  } chie_dat_s;

  // --- RSP Channel (Response) ---
  typedef struct packed {
      logic                                    tracetag;      // MSB
      logic [1:0]                              tagop;
      logic [3:0]                              pcrdtype;
      logic [11:0]                             dbid;
      logic [2:0]                              cbusy;
      logic [2:0]                              fwd_pull;      // Shared Bits
      logic [2:0]                              resp;
      logic [1:0]                              resperr;
      logic [4:0]                              opcode;
      logic [11:0]                             txnid;
      logic [CHIE_NID_WIDTH_PARAM-1:0]         srcid;
      logic [CHIE_NID_WIDTH_PARAM-1:0]         tgtid;
      logic [3:0]                              qos;           // LSB 0
  } chie_rsp_s;


  // ============================================================================
  // CHI DEBUG SIGNALS (STRUCT-BASED)
  // ============================================================================

  // --- SNF Node (Scalar) ---
  // ICN -> SNF (RX Path)
  chie_req_s snf_rxreq_dbg;
  chie_dat_s snf_rxdat_dbg;

  // SNF -> ICN (TX Path)
  chie_rsp_s snf_txrsp_dbg;
  chie_dat_s snf_txdat_dbg;


  // ============================================================================
  // CHANNEL PARSING FUNCTIONS
  // These functions take a raw bit-vector and return a structured struct.
  // ============================================================================

  // --- REQ Channel Parser ---
  function automatic chie_req_s parse_req_flit(logic [`CHIE_REQ_FLIT_WIDTH-1:0] raw_flit);
      chie_req_s s;
      s.qos             = raw_flit[`CHIE_REQ_FLIT_QOS_RANGE];
      s.tgtid           = raw_flit[`CHIE_REQ_FLIT_TGTID_RANGE];
      s.srcid           = raw_flit[`CHIE_REQ_FLIT_SRCID_RANGE];
      s.txnid           = raw_flit[`CHIE_REQ_FLIT_TXNID_RANGE];
      s.return_stsh_nid = raw_flit[`CHIE_REQ_FLIT_RETURNNID_RANGE]; // Aliased with STASHNID
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
      s.dodwt_snpattr   = raw_flit[`CHIE_REQ_FLIT_SNPATTR_RANGE];
      s.lpid            = raw_flit[`CHIE_REQ_FLIT_LPID_RANGE];
      s.snoopme_excl    = raw_flit[`CHIE_REQ_FLIT_EXCL_RANGE];
      s.expcompack      = raw_flit[`CHIE_REQ_FLIT_EXPCOMPACK_RANGE];
      s.tagop           = raw_flit[`CHIE_REQ_FLIT_TAGOP_RANGE];
      s.tracetag        = raw_flit[`CHIE_REQ_FLIT_TRACETAG_RANGE];
      //s.rsvdc           = raw_flit[`CHIE_REQ_FLIT_RSVDC_RANGE];
      return s;
  endfunction

  // --- DAT Channel Parser ---
  function automatic chie_dat_s parse_dat_flit(logic [`CHIE_DAT_FLIT_WIDTH-1:0] raw_flit);
      chie_dat_s s;
      s.qos             = raw_flit[`CHIE_DAT_FLIT_QOS_RANGE];
      s.tgtid           = raw_flit[`CHIE_DAT_FLIT_TGTID_RANGE];
      s.srcid           = raw_flit[`CHIE_DAT_FLIT_SRCID_RANGE];
      s.txnid           = raw_flit[`CHIE_DAT_FLIT_TXNID_RANGE];
      s.homenid         = raw_flit[`CHIE_DAT_FLIT_HOMENID_RANGE];
      s.opcode          = raw_flit[`CHIE_DAT_FLIT_OPCODE_RANGE];
      s.resperr         = raw_flit[`CHIE_DAT_FLIT_RESPERR_RANGE];
      s.resp            = raw_flit[`CHIE_DAT_FLIT_RESP_RANGE];
      s.attr.datasource = raw_flit[`CHIE_DAT_FLIT_DATASOURCE_RANGE];
      s.cbusy           = raw_flit[`CHIE_DAT_FLIT_CBUSY_RANGE];
      s.dbid            = raw_flit[`CHIE_DAT_FLIT_DBID_RANGE];
      s.ccid            = raw_flit[`CHIE_DAT_FLIT_CCID_RANGE];
      s.dataid          = raw_flit[`CHIE_DAT_FLIT_DATAID_RANGE];
      s.tagop           = raw_flit[`CHIE_DAT_FLIT_TAGOP_RANGE];
      s.tag             = raw_flit[`CHIE_DAT_FLIT_TAG_RANGE];
      s.tu              = raw_flit[`CHIE_DAT_FLIT_TU_RANGE];
      s.tracetag        = raw_flit[`CHIE_DAT_FLIT_TRACETAG_RANGE];
      //s.rsvdc           = raw_flit[`CHIE_DAT_FLIT_RSVDC_RANGE];
      s.be              = raw_flit[`CHIE_DAT_FLIT_BE_RANGE];
      s.data            = raw_flit[`CHIE_DAT_FLIT_DATA_RANGE];
      //s.datacheck       = raw_flit[`CHIE_DAT_FLIT_DATACHECK_RANGE];
      //s.poison          = raw_flit[`CHIE_DAT_FLIT_POISON_RANGE];
      return s;
  endfunction

  // --- RSP Channel Parser ---
  function automatic chie_rsp_s parse_rsp_flit(logic [`CHIE_RSP_FLIT_WIDTH-1:0] raw_flit);
      chie_rsp_s s;
      s.qos             = raw_flit[`CHIE_RSP_FLIT_QOS_RANGE];
      s.tgtid           = raw_flit[`CHIE_RSP_FLIT_TGTID_RANGE];
      s.srcid           = raw_flit[`CHIE_RSP_FLIT_SRCID_RANGE];
      s.txnid           = raw_flit[`CHIE_RSP_FLIT_TXNID_RANGE];
      s.opcode          = raw_flit[`CHIE_RSP_FLIT_OPCODE_RANGE];
      s.resperr         = raw_flit[`CHIE_RSP_FLIT_RESPERR_RANGE];
      s.resp            = raw_flit[`CHIE_RSP_FLIT_RESP_RANGE];
      s.fwd_pull        = raw_flit[`CHIE_RSP_FLIT_FWDSTATE_RANGE];
      s.cbusy           = raw_flit[`CHIE_RSP_FLIT_CBUSY_RANGE];
      s.dbid            = raw_flit[`CHIE_RSP_FLIT_DBID_RANGE];
      s.pcrdtype        = raw_flit[`CHIE_RSP_FLIT_PCRDTYPE_RANGE];
      s.tagop           = raw_flit[`CHIE_RSP_FLIT_TAGOP_RANGE];
      s.tracetag        = raw_flit[`CHIE_RSP_FLIT_TRACETAG_RANGE];
      return s;
  endfunction

  // --- Assignment logic using the parsing functions ---
  always_comb begin
      // RX Path (To SNF)
      snf_rxreq_dbg = parse_req_flit(tb_snf_rxreqflit);
      snf_rxdat_dbg = parse_dat_flit(tb_snf_rxdatflit);

      // TX Path (From SNF)
      snf_txrsp_dbg = parse_rsp_flit(snf_txrspflit);
      snf_txdat_dbg = parse_dat_flit(snf_txdatflit);
  end

    // --- 1. Clock and Reset Generation ---
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    initial begin
        rst_n  = 0;
        clk_en = 1;
        #100 rst_n = 1;
    end

    // --- 2. Instantiate RNF Wrapper ---
    rnf_wrapper #(
        .corecount_g(CORE_COUNT),
        .CHIE_REQ_ADDR_WIDTH_PARAM   (CHIE_REQ_ADDR_WIDTH_PARAM),
        .CHIE_SNP_ADDR_WIDTH_PARAM   (CHIE_SNP_ADDR_WIDTH_PARAM),
        .CHIE_NID_WIDTH_PARAM        (CHIE_NID_WIDTH_PARAM),
        .CHIE_DATA_WIDTH_PARAM       (CHIE_DATA_WIDTH_PARAM),
        .CHIE_BE_WIDTH_PARAM         (CHIE_BE_WIDTH_PARAM),
        .CHIE_DATACHECK_WIDTH_PARAM  (CHIE_DATACHECK_WIDTH_PARAM),
        .CHIE_POISON_WIDTH_PARAM     (CHIE_POISON_WIDTH_PARAM),
        .CHIE_REQ_RSVDC_WIDTH_PARAM  (CHIE_REQ_RSVDC_WIDTH_PARAM),
        .CHIE_DAT_RSVDC_WIDTH_PARAM  (CHIE_DAT_RSVDC_WIDTH_PARAM),
        .HNF_MSHR_RNF_NUM_PARAM      (HNF_MSHR_RNF_NUM_PARAM),
        .HNF_NID_PARAM               (HNF_NID_PARAM),
        .SNF_NID_PARAM               (SNF_NID_PARAM),
        .XP_LCRD_NUM_PARAM           (XP_LCRD_NUM_PARAM),
        .HNF_SF_ENTRIES_NUM_PARAM    (HNF_SF_ENTRIES_NUM_PARAM),
        .HNF_SF_WAY_NUM_PARAM        (HNF_SF_WAY_NUM_PARAM),
        .HNF_MSHR_EXCL_RN_NUM_PARAM  (HNF_MSHR_EXCL_RN_NUM_PARAM),
        .HNF_MSHR_EXCL_RN_WIDTH_PARAM(HNF_MSHR_EXCL_RN_WIDTH_PARAM),
        .HNF_MSHR_ENTRIES_NUM_PARAM  (HNF_MSHR_ENTRIES_NUM_PARAM),
        .HNF_MSHR_ENTRIES_WIDTH_PARAM(HNF_MSHR_ENTRIES_WIDTH_PARAM),
        .HNF_L3_CACHE_SIZE_PARAM     (HNF_L3_CACHE_SIZE_PARAM),
        .HNF_L3_WAY_NUM_PARAM        (HNF_L3_WAY_NUM_PARAM)
        ) u_rnf_wrap (
        .clk             (clk),
        .rst_n           (rst_n & program_load_done),
        .clk_en          (clk_en),
        .debug_req_i     ('0),

        // RX Interface
        .rxrspflitv      (rnf_rxrspflitv),
        .rxrspflit       (rnf_rxrspflit),
        .rxrspflitpend   (icn_rnf_rxrsppend),
        .rxdatflitv      (rnf_rxdatflitv),
        .rxdatflit       (rnf_rxdatflit),
        .rxdatflitpend   (icn_rnf_rxdatpend),
        .rxsnpflitv      (rnf_rxsnpflitv),
        .rxsnpflit       (rnf_rxsnpflit),
        .rxsnpflitpend   (icn_rnf_rxsnppend),

        // TX Interface
        .txreqflitv      (rnf_txreqflitv),
        .txreqflit       (rnf_txreqflit),
        .txreqflitpend   (rnf_txreqflitpend),
        .txrspflitv      (rnf_txrspflitv),
        .txrspflit       (rnf_txrspflit),
        .txrspflitpend   (rnf_txrspflitpend),
        .txdatflitv      (rnf_txdatflitv),
        .txdatflit       (rnf_txdatflit),
        .txdatflitpend   (rnf_txdatflitpend),

        // Credits
        .txreqlcrdv      (rnf_txreqlcrdv),
        .txrsplcrdv      (rnf_txrsplcrdv),
        .txdatlcrdv      (rnf_txdatlcrdv),
        .rxrsplcrdv      (rnf_rxrsplcrdv),
        .rxdatlcrdv      (rnf_rxdatlcrdv),
        .rxsnplcrdv      (rnf_rxsnplcrdv),

        // Handshake Ports
        .txlinkactivereq  (rnf_txlinkactivereq),
        .txlinkactiveack  (rnf_txlinkactiveack),
        .rxlinkactivereq  (rnf_rxlinkactivereq),
        .rxlinkactiveack  (rnf_rxlinkactiveack),
        .txactive         (rnf_txactive),
        .rxactive         (rnf_rxactive)
    );


    // --- 3. Instantiate HNF ---
    hnf #(
      .CHIE_REQ_ADDR_WIDTH_PARAM   (CHIE_REQ_ADDR_WIDTH_PARAM),
      .CHIE_SNP_ADDR_WIDTH_PARAM   (CHIE_SNP_ADDR_WIDTH_PARAM),
      .CHIE_NID_WIDTH_PARAM        (CHIE_NID_WIDTH_PARAM),
      .CHIE_DATA_WIDTH_PARAM       (CHIE_DATA_WIDTH_PARAM),
      .CHIE_BE_WIDTH_PARAM         (CHIE_BE_WIDTH_PARAM),
      .CHIE_DATACHECK_WIDTH_PARAM  (CHIE_DATACHECK_WIDTH_PARAM),
      .CHIE_POISON_WIDTH_PARAM     (CHIE_POISON_WIDTH_PARAM),
      .CHIE_REQ_RSVDC_WIDTH_PARAM  (CHIE_REQ_RSVDC_WIDTH_PARAM),
      .CHIE_DAT_RSVDC_WIDTH_PARAM  (CHIE_DAT_RSVDC_WIDTH_PARAM),
      .HNF_MSHR_RNF_NUM_PARAM      (HNF_MSHR_RNF_NUM_PARAM),
      .HNF_MSHR_RNI_NUM_PARAM      (HNF_MSHR_RNI_NUM_PARAM),
      .RNF_NID_LIST_PARAM          (RNF_NID_LIST_PARAM),
      .RNI_NID_LIST_PARAM          (RNI_NID_LIST_PARAM),
      .HNF_NID_PARAM               (HNF_NID_PARAM),
      .SNF_NID_PARAM               (SNF_NID_PARAM),
      .XP_LCRD_NUM_PARAM           (XP_LCRD_NUM_PARAM),
      .HNF_SF_ENTRIES_NUM_PARAM    (HNF_SF_ENTRIES_NUM_PARAM),
      .HNF_SF_WAY_NUM_PARAM        (HNF_SF_WAY_NUM_PARAM),
      .HNF_MSHR_EXCL_RN_NUM_PARAM  (HNF_MSHR_EXCL_RN_NUM_PARAM),
      .HNF_MSHR_EXCL_RN_WIDTH_PARAM(HNF_MSHR_EXCL_RN_WIDTH_PARAM),
      .HNF_MSHR_ENTRIES_NUM_PARAM  (HNF_MSHR_ENTRIES_NUM_PARAM),
      .HNF_MSHR_ENTRIES_WIDTH_PARAM(HNF_MSHR_ENTRIES_WIDTH_PARAM),
      .HNF_L3_CACHE_SIZE_PARAM     (HNF_L3_CACHE_SIZE_PARAM),
      .HNF_L3_WAY_NUM_PARAM        (HNF_L3_WAY_NUM_PARAM)
      ) u_hnf (
      .CLK             (clk),
      .RST             (~(rst_n & program_load_done)),

      // HNF Inbound (from RNF TX)
      .RXREQFLITV      (icn_hnf_rxreqflitv),
      .RXREQFLIT       (icn_hnf_rxreqflit),
      .RXREQFLITPEND   (icn_hnf_rxreqpend),
      .RXRSPFLITV      (icn_hnf_rxrspflitv),
      .RXRSPFLIT       (icn_hnf_rxrspflit),
      .RXRSPFLITPEND   (icn_hnf_rxrsppend),
      .RXDATFLITV      (icn_hnf_rxdatflitv),
      .RXDATFLIT       (icn_hnf_rxdatflit),
      .RXDATFLITPEND   (icn_hnf_rxdatpend),

      // HNF Outbound (to RNF RX)
      .TXREQFLITV      (hnf_txreqflitv),
      .TXREQFLIT       (hnf_txreqflit),
      .TXREQFLITPEND   (hnf_txreqpend),
      .TXRSPFLITV      (hnf_txrspflitv),
      .TXRSPFLIT       (hnf_txrspflit),
      .TXRSPFLITPEND   (hnf_txrspflitpend),
      .TXSNPFLITV      (hnf_txsnpflitv),
      .TXSNPFLIT       (hnf_txsnpflit),
      .TXSNPFLITPEND   (hnf_txsnpflitpend),
      .TXDATFLITV      (hnf_txdatflitv),
      .TXDATFLIT       (hnf_txdatflit),
      .TXDATFLITPEND   (hnf_txdatflitpend),

      // Credit/Flow Control
      .RXREQLCRDV      (hnf_rxreqlcrdv),
      .RXRSPLCRDV      (hnf_rxrsplcrdv),
      .RXDATLCRDV      (hnf_rxdatlcrdv),
      .TXREQLCRDV      (hnf_txreqlcrdv),
      .TXRSPLCRDV      (hnf_txrsplcrdv),
      .TXSNPLCRDV      (hnf_txsnplcrdv),
      .TXDATLCRDV      (hnf_txdatlcrdv),

      .notify_reg      (hnf_notify)
    );


    assign snf_rxreqflitv = (program_load_done) ? icn_snf_rxreqflitv : tb_snf_rxreqflitv;
    assign snf_rxreqflit  = (program_load_done) ? icn_snf_rxreqflit : tb_snf_rxreqflit;

    assign snf_rxdatflitv = (program_load_done) ? icn_snf_rxdatflitv : tb_snf_rxdatflitv;
    assign snf_rxdatflit  = (program_load_done) ? icn_snf_rxdatflit : tb_snf_rxdatflit;


    logic snf_rxreqlcrdv, snf_rxdatlcrdv;
    logic snf_txlinkactivereq, snf_txlinkactiveack, snf_rxlinkactivereq, snf_rxlinkactiveack, snf_txactive, snf_rxactive;

    // --- 4. Instantiate SNF ---
    `ifdef TB_SNF
      // CREDIT tie-off (infinite credits)
      //assign snf_rxreqlcrdv = 1'b1;
      assign snf_rxdatlcrdv = 1'b1;

      // Link Activation Interface tie-off (always active)
      assign snf_txlinkactivereq = 1'b1;
      assign snf_rxlinkactiveack = 1'b1;
      assign snf_txactive = 1'b1;

      tb_snf #(
        .CHIE_REQ_ADDR_WIDTH_PARAM   (CHIE_REQ_ADDR_WIDTH_PARAM),
        .CHIE_SNP_ADDR_WIDTH_PARAM   (CHIE_SNP_ADDR_WIDTH_PARAM),
        .CHIE_NID_WIDTH_PARAM        (CHIE_NID_WIDTH_PARAM),
        .CHIE_DATA_WIDTH_PARAM       (CHIE_DATA_WIDTH_PARAM),
        .CHIE_BE_WIDTH_PARAM         (CHIE_BE_WIDTH_PARAM),
        .CHIE_DATACHECK_WIDTH_PARAM  (CHIE_DATACHECK_WIDTH_PARAM),
        .CHIE_POISON_WIDTH_PARAM     (CHIE_POISON_WIDTH_PARAM),
        .CHIE_REQ_RSVDC_WIDTH_PARAM  (CHIE_REQ_RSVDC_WIDTH_PARAM),
        .CHIE_DAT_RSVDC_WIDTH_PARAM  (CHIE_DAT_RSVDC_WIDTH_PARAM),
        .HNF_MSHR_RNF_NUM_PARAM      (HNF_MSHR_RNF_NUM_PARAM),
        .HNF_MSHR_RNI_NUM_PARAM      (HNF_MSHR_RNI_NUM_PARAM),
        .RNF_NID_LIST_PARAM          (RNF_NID_LIST_PARAM),
        .RNI_NID_LIST_PARAM          (RNI_NID_LIST_PARAM),
        .HNF_NID_PARAM               (HNF_NID_PARAM),
        .SNF_NID_PARAM               (SNF_NID_PARAM),
        .XP_LCRD_NUM_PARAM           (XP_LCRD_NUM_PARAM),
        .HNF_SF_ENTRIES_NUM_PARAM    (HNF_SF_ENTRIES_NUM_PARAM),
        .HNF_SF_WAY_NUM_PARAM        (HNF_SF_WAY_NUM_PARAM),
        .HNF_MSHR_EXCL_RN_NUM_PARAM  (HNF_MSHR_EXCL_RN_NUM_PARAM),
        .HNF_MSHR_EXCL_RN_WIDTH_PARAM(HNF_MSHR_EXCL_RN_WIDTH_PARAM),
        .HNF_MSHR_ENTRIES_NUM_PARAM  (HNF_MSHR_ENTRIES_NUM_PARAM),
        .HNF_MSHR_ENTRIES_WIDTH_PARAM(HNF_MSHR_ENTRIES_WIDTH_PARAM),
        .HNF_L3_CACHE_SIZE_PARAM     (HNF_L3_CACHE_SIZE_PARAM),
        .HNF_L3_WAY_NUM_PARAM        (HNF_L3_WAY_NUM_PARAM)
        ) u_tb_snf (
        .CLK             (clk),
        .RST             (~rst_n),

        .RXREQFLITV    (snf_rxreqflitv),
        .RXREQFLIT     (snf_rxreqflit),
        .RXREQLCRDTV   (snf_rxreqlcrdv),

        .RXDATFLITV    (snf_rxdatflitv),
        .RXDATFLIT     (snf_rxdatflit),

        .TXRSPFLITV    (snf_txrspflitv),
        .TXRSPFLIT     (snf_txrspflit),
        .TXDATFLITV    (snf_txdatflitv),
        .TXDATFLIT     (snf_txdatflit),

        .dbg_sn_wr_en  (1'b0),
        .dbg_sn_wr_data('0),
        .dbg_sn_addr   ('0),
        .dbg_sn_rd_en  (1'b0),
        .dbg_sn_rd_data()
      );
    `else
      // --- Slave Node Memory Subsystem (SN-F) ---
      mem_ss #(
        // Protocol & Width Parameters
        .CHIE_REQ_ADDR_WIDTH_PARAM    (CHIE_REQ_ADDR_WIDTH_PARAM),
        .CHIE_SNP_ADDR_WIDTH_PARAM    (CHIE_SNP_ADDR_WIDTH_PARAM),
        .CHIE_NID_WIDTH_PARAM         (CHIE_NID_WIDTH_PARAM),
        .CHIE_DATA_WIDTH_PARAM        (CHIE_DATA_WIDTH_PARAM),
        .CHIE_BE_WIDTH_PARAM          (CHIE_BE_WIDTH_PARAM),
        .CHIE_DATACHECK_WIDTH_PARAM   (CHIE_DATACHECK_WIDTH_PARAM),
        .CHIE_POISON_WIDTH_PARAM      (CHIE_POISON_WIDTH_PARAM),
        .CHIE_REQ_RSVDC_WIDTH_PARAM   (CHIE_REQ_RSVDC_WIDTH_PARAM),
        .CHIE_DAT_RSVDC_WIDTH_PARAM   (CHIE_DAT_RSVDC_WIDTH_PARAM),

        // Node & List Parameters
        .HNF_MSHR_RNF_NUM_PARAM       (HNF_MSHR_RNF_NUM_PARAM),
        .HNF_MSHR_RNI_NUM_PARAM       (HNF_MSHR_RNI_NUM_PARAM),
        .RNF_NID_LIST_PARAM           (RNF_NID_LIST_PARAM),
        .RNI_NID_LIST_PARAM           (RNI_NID_LIST_PARAM),
        .HNF_NID_PARAM                (HNF_NID_PARAM),
        .SNF_NID_PARAM                (SNF_NID_PARAM),

        // Cache & SF Configuration
        .XP_LCRD_NUM_PARAM            (XP_LCRD_NUM_PARAM),
        .HNF_SF_ENTRIES_NUM_PARAM     (HNF_SF_ENTRIES_NUM_PARAM),
        .HNF_SF_WAY_NUM_PARAM         (HNF_SF_WAY_NUM_PARAM),
        .HNF_MSHR_EXCL_RN_NUM_PARAM   (HNF_MSHR_EXCL_RN_NUM_PARAM),
        .HNF_MSHR_EXCL_RN_WIDTH_PARAM (HNF_MSHR_EXCL_RN_WIDTH_PARAM),
        .HNF_MSHR_ENTRIES_NUM_PARAM   (HNF_MSHR_ENTRIES_NUM_PARAM),
        .HNF_MSHR_ENTRIES_WIDTH_PARAM (HNF_MSHR_ENTRIES_WIDTH_PARAM),
        .HNF_L3_CACHE_SIZE_PARAM      (HNF_L3_CACHE_SIZE_PARAM),
        .HNF_L3_WAY_NUM_PARAM         (HNF_L3_WAY_NUM_PARAM),

        // Internal AXI Overrides (Matching CHI and your bridge)
        .AXI_DATA_WIDTH               (CHIE_DATA_WIDTH_PARAM), // 512
        .AXI_ADDR_WIDTH               (CHIE_REQ_ADDR_WIDTH_PARAM),
        .AXI_ID_WIDTH                 (10),
        .AXI_USER_WIDTH               (10)
      ) u_mem_ss (
        .CLK                (CLK),
        .RST                (RST),

        // CHI Link Control
        .TXLINKACTIVEREQ    (snf_txlinkactivereq),
        .TXLINKACTIVEACK    (snf_txlinkactiveack),
        .RXLINKACTIVEREQ    (snf_rxlinkactivereq),
        .RXLINKACTIVEACK    (snf_rxlinkactiveack),
        .TXSACTIVE          (snf_txsactive),
        .RXSACTIVE          (snf_rxsactive),

        // CHI RX Channels (From Interconnect/HN-F)
        .RXREQFLITV         (snf_rxreqflitv),
        .RXREQFLIT          (snf_rxreqflit),
        .RXREQFLITPEND      (1'b0),
        .RXREQLCRDV         (snf_rxreqlcrdv),

        .RXDATFLITV         (snf_rxdatflitv),
        .RXDATFLIT          (snf_rxdatflit),
        .RXDATFLITPEND      (1'b0),
        .RXDATLCRDV         (snf_rxdatlcrdv),

        // CHI TX Channels (To Interconnect/HN-F)
        .TXRSPFLITV         (snf_txrspflitv),
        .TXRSPFLIT          (snf_txrspflit),
        .TXRSPFLITPEND      (),
        .TXRSPLCRDV         (icn_snf_txrsplcrdv),

        .TXDATFLITV         (snf_txdatflitv),
        .TXDATFLIT          (snf_txdatflit),
        .TXDATFLITPEND      (),
        .TXDATLCRDV         (icn_snf_txdatlcrdv)
      );
    `endif


  chi_icn_beh #(
    .CORE_COUNT (CORE_COUNT),

    .CHIE_REQ_ADDR_WIDTH_PARAM   (CHIE_REQ_ADDR_WIDTH_PARAM),
    .CHIE_SNP_ADDR_WIDTH_PARAM   (CHIE_SNP_ADDR_WIDTH_PARAM),
    .CHIE_NID_WIDTH_PARAM        (CHIE_NID_WIDTH_PARAM),
    .CHIE_DATA_WIDTH_PARAM       (CHIE_DATA_WIDTH_PARAM),
    .CHIE_BE_WIDTH_PARAM         (CHIE_BE_WIDTH_PARAM),
    .CHIE_DATACHECK_WIDTH_PARAM  (CHIE_DATACHECK_WIDTH_PARAM),
    .CHIE_POISON_WIDTH_PARAM     (CHIE_POISON_WIDTH_PARAM),
    .CHIE_REQ_RSVDC_WIDTH_PARAM  (CHIE_REQ_RSVDC_WIDTH_PARAM),
    .CHIE_DAT_RSVDC_WIDTH_PARAM  (CHIE_DAT_RSVDC_WIDTH_PARAM),
    .HNF_MSHR_RNF_NUM_PARAM      (HNF_MSHR_RNF_NUM_PARAM),
    .HNF_MSHR_RNI_NUM_PARAM      (HNF_MSHR_RNI_NUM_PARAM),
    .RNF_NID_LIST_PARAM          (RNF_NID_LIST_PARAM),
    .RNI_NID_LIST_PARAM          (RNI_NID_LIST_PARAM),
    .HNF_NID_PARAM               (HNF_NID_PARAM),
    .SNF_NID_PARAM               (SNF_NID_PARAM),
    .XP_LCRD_NUM_PARAM           (XP_LCRD_NUM_PARAM),
    .HNF_SF_ENTRIES_NUM_PARAM    (HNF_SF_ENTRIES_NUM_PARAM),
    .HNF_SF_WAY_NUM_PARAM        (HNF_SF_WAY_NUM_PARAM),
    .HNF_MSHR_EXCL_RN_NUM_PARAM  (HNF_MSHR_EXCL_RN_NUM_PARAM),
    .HNF_MSHR_EXCL_RN_WIDTH_PARAM(HNF_MSHR_EXCL_RN_WIDTH_PARAM),
    .HNF_MSHR_ENTRIES_NUM_PARAM  (HNF_MSHR_ENTRIES_NUM_PARAM),
    .HNF_MSHR_ENTRIES_WIDTH_PARAM(HNF_MSHR_ENTRIES_WIDTH_PARAM),
    .HNF_L3_CACHE_SIZE_PARAM     (HNF_L3_CACHE_SIZE_PARAM),
    .HNF_L3_WAY_NUM_PARAM        (HNF_L3_WAY_NUM_PARAM)
  ) u_chi_icn (
    .clk                  (clk),
    .rst                  (~(rst_n & program_load_done)),

    // --- RNF VECTORIZED INTERFACE ---
    // These connect to your arrayed signals from the cores
    .rnf_txreqflitv       (rnf_txreqflitv),
    .rnf_txreqflit        (rnf_txreqflit),
    .rnf_txreqlcrdv       (rnf_txreqlcrdv),

    .rnf_txrspflitv       (rnf_txrspflitv),
    .rnf_txrspflit        (rnf_txrspflit),
    .rnf_txrsplcrdv       (rnf_txrsplcrdv),

    .rnf_txdatflitv       (rnf_txdatflitv),
    .rnf_txdatflit        (rnf_txdatflit),
    .rnf_txdatlcrdv       (rnf_txdatlcrdv),

    .rnf_rxsnpflitv       (rnf_rxsnpflitv),
    .rnf_rxsnppend        (icn_rnf_rxsnppend),
    .rnf_rxsnpflit        (rnf_rxsnpflit),
    .rnf_rxsnplcrdv       (rnf_rxsnplcrdv),

    .rnf_rxrspflitv       (rnf_rxrspflitv),
    .rnf_rxrsppend        (icn_rnf_rxrsppend),
    .rnf_rxrspflit        (rnf_rxrspflit),
    .rnf_rxrsplcrdv       (rnf_rxrsplcrdv),

    .rnf_rxdatflitv       (rnf_rxdatflitv),
    .rnf_rxdatpend        (icn_rnf_rxdatpend),
    .rnf_rxdatflit        (rnf_rxdatflit),
    .rnf_rxdatlcrdv       (rnf_rxdatlcrdv),

    // Link layer handshakes (Vectorized)
    .rnf_txlinkactivereq  (rnf_txlinkactivereq),
    .rnf_txlinkactiveack  (rnf_txlinkactiveack),
    .rnf_rxlinkactivereq  (rnf_rxlinkactivereq),
    .rnf_rxlinkactiveack  (rnf_rxlinkactiveack),
    .rnf_txactive         (rnf_txactive),
    .rnf_rxactive         (rnf_rxactive),

    // --- HNF INTERFACE (Connected via your Arbiter/Mux) ---
    .hnf_rxreqflitv       (icn_hnf_rxreqflitv), // Internal wires from arbiter
    .hnf_rxreqflit        (icn_hnf_rxreqflit),
    .hnf_rxreqpend        (icn_hnf_rxreqpend),
    .hnf_rxreqlcrdv       (hnf_rxreqlcrdv),

    .hnf_rxrspflitv       (icn_hnf_rxrspflitv),
    .hnf_rxrspflit        (icn_hnf_rxrspflit),
    .hnf_rxrsppend        (icn_hnf_rxrsppend),
    .hnf_rxrsplcrdv       (hnf_rxrsplcrdv),

    .hnf_rxdatflitv       (icn_hnf_rxdatflitv),
    .hnf_rxdatflit        (icn_hnf_rxdatflit),
    .hnf_rxdatpend        (icn_hnf_rxdatpend),
    .hnf_rxdatlcrdv       (hnf_rxdatlcrdv),

    .hnf_txreqflitv       (hnf_txreqflitv),
    .hnf_txreqflit        (hnf_txreqflit),
    .hnf_txreqpend        (hnf_txreqpend),
    .hnf_txreqlcrdv       (hnf_txreqlcrdv),

    .hnf_txsnpflitv       (hnf_txsnpflitv),
    .hnf_txsnpflit        (hnf_txsnpflit),
    .hnf_txsnppend        (hnf_txsnppend),
    .hnf_txsnplcrdv       (hnf_txsnplcrdv),

    .hnf_txrspflitv       (hnf_txrspflitv),
    .hnf_txrspflit        (hnf_txrspflit),
    .hnf_txrsppend        (hnf_txrsppend),
    .hnf_txrsplcrdv       (hnf_txrsplcrdv),

    .hnf_txdatflitv       (hnf_txdatflitv),
    .hnf_txdatflit        (hnf_txdatflit),
    .hnf_txdatpend        (hnf_txdatpend),
    .hnf_txdatlcrdv       (hnf_txdatlcrdv),

    // --- SNF INTERFACE (Slave Node / Memory) ---
    .snf_rxreqflitv       (icn_snf_rxreqflitv),
    .snf_rxreqflit        (icn_snf_rxreqflit),
    .snf_rxreqlcrdv       (snf_rxreqlcrdv),

    .snf_rxdatflitv       (icn_snf_rxdatflitv),
    .snf_rxdatflit        (icn_snf_rxdatflit),
    .snf_rxdatlcrdv       (snf_rxdatlcrdv),

    .snf_txrspflitv       (snf_txrspflitv),
    .snf_txrspflit        (snf_txrspflit),
    .snf_txrsplcrdv       (icn_snf_txrsplcrdv),

    .snf_txdatflitv       (snf_txdatflitv),
    .snf_txdatflit        (snf_txdatflit),
    .snf_txdatlcrdv       (icn_snf_txdatlcrdv),

    .snf_txlinkactivereq  (snf_txlinkactivereq),
    .snf_txlinkactiveack  (snf_txlinkactiveack),
    .snf_rxlinkactivereq  (snf_rxlinkactivereq),
    .snf_rxlinkactiveack  (snf_rxlinkactiveack),
    .snf_txactive         (snf_txactive),
    .snf_rxactive         (snf_rxactive)
  );

  `ifndef TB_NO_MONITOR
    chi_monitor #(
      .CORE_COUNT (CORE_COUNT),

      .CHIE_REQ_ADDR_WIDTH_PARAM   (CHIE_REQ_ADDR_WIDTH_PARAM),
      .CHIE_SNP_ADDR_WIDTH_PARAM   (CHIE_SNP_ADDR_WIDTH_PARAM),
      .CHIE_NID_WIDTH_PARAM        (CHIE_NID_WIDTH_PARAM),
      .CHIE_DATA_WIDTH_PARAM       (CHIE_DATA_WIDTH_PARAM),
      .CHIE_BE_WIDTH_PARAM         (CHIE_BE_WIDTH_PARAM),
      .CHIE_DATACHECK_WIDTH_PARAM  (CHIE_DATACHECK_WIDTH_PARAM),
      .CHIE_POISON_WIDTH_PARAM     (CHIE_POISON_WIDTH_PARAM),
      .CHIE_REQ_RSVDC_WIDTH_PARAM  (CHIE_REQ_RSVDC_WIDTH_PARAM),
      .CHIE_DAT_RSVDC_WIDTH_PARAM  (CHIE_DAT_RSVDC_WIDTH_PARAM),
      .HNF_MSHR_RNF_NUM_PARAM      (HNF_MSHR_RNF_NUM_PARAM),
      .HNF_MSHR_RNI_NUM_PARAM      (HNF_MSHR_RNI_NUM_PARAM),
      .RNF_NID_LIST_PARAM          (RNF_NID_LIST_PARAM),
      .RNI_NID_LIST_PARAM          (RNI_NID_LIST_PARAM),
      .HNF_NID_PARAM               (HNF_NID_PARAM),
      .SNF_NID_PARAM               (SNF_NID_PARAM),
      .XP_LCRD_NUM_PARAM           (XP_LCRD_NUM_PARAM),
      .HNF_SF_ENTRIES_NUM_PARAM    (HNF_SF_ENTRIES_NUM_PARAM),
      .HNF_SF_WAY_NUM_PARAM        (HNF_SF_WAY_NUM_PARAM),
      .HNF_MSHR_EXCL_RN_NUM_PARAM  (HNF_MSHR_EXCL_RN_NUM_PARAM),
      .HNF_MSHR_EXCL_RN_WIDTH_PARAM(HNF_MSHR_EXCL_RN_WIDTH_PARAM),
      .HNF_MSHR_ENTRIES_NUM_PARAM  (HNF_MSHR_ENTRIES_NUM_PARAM),
      .HNF_MSHR_ENTRIES_WIDTH_PARAM(HNF_MSHR_ENTRIES_WIDTH_PARAM),
      .HNF_L3_CACHE_SIZE_PARAM     (HNF_L3_CACHE_SIZE_PARAM),
      .HNF_L3_WAY_NUM_PARAM        (HNF_L3_WAY_NUM_PARAM)
    ) u_chi_monitor (
      .clk                  (clk),
      .rst                  (~(rst_n & program_load_done)),

      // --- RNF VECTORIZED INTERFACE ---
      // These connect to your arrayed signals from the cores
      .rnf_txreqflitv       (rnf_txreqflitv),
      .rnf_txreqflit        (rnf_txreqflit),
      .rnf_txreqlcrdv       (rnf_txreqlcrdv),

      .rnf_txrspflitv       (rnf_txrspflitv),
      .rnf_txrspflit        (rnf_txrspflit),
      .rnf_txrsplcrdv       (rnf_txrsplcrdv),

      .rnf_txdatflitv       (rnf_txdatflitv),
      .rnf_txdatflit        (rnf_txdatflit),
      .rnf_txdatlcrdv       (rnf_txdatlcrdv),

      .rnf_rxsnpflitv       (rnf_rxsnpflitv),
      .rnf_rxsnppend        (icn_rnf_rxsnppend),
      .rnf_rxsnpflit        (rnf_rxsnpflit),
      .rnf_rxsnplcrdv       (rnf_rxsnplcrdv),

      .rnf_rxrspflitv       (rnf_rxrspflitv),
      .rnf_rxrsppend        (icn_rnf_rxrsppend),
      .rnf_rxrspflit        (rnf_rxrspflit),
      .rnf_rxrsplcrdv       (rnf_rxrsplcrdv),

      .rnf_rxdatflitv       (rnf_rxdatflitv),
      .rnf_rxdatpend        (icn_rnf_rxdatpend),
      .rnf_rxdatflit        (rnf_rxdatflit),
      .rnf_rxdatlcrdv       (rnf_rxdatlcrdv),


      // --- HNF INTERFACE (Connected via your Arbiter/Mux) ---
      .hnf_rxreqflitv       (icn_hnf_rxreqflitv), // Internal wires from arbiter
      .hnf_rxreqflit        (icn_hnf_rxreqflit),
      .hnf_rxreqpend        (icn_hnf_rxreqpend),
      .hnf_rxreqlcrdv       (hnf_rxreqlcrdv),

      .hnf_rxrspflitv       (icn_hnf_rxrspflitv),
      .hnf_rxrspflit        (icn_hnf_rxrspflit),
      .hnf_rxrsppend        (icn_hnf_rxrsppend),
      .hnf_rxrsplcrdv       (hnf_rxrsplcrdv),

      .hnf_rxdatflitv       (icn_hnf_rxdatflitv),
      .hnf_rxdatflit        (icn_hnf_rxdatflit),
      .hnf_rxdatpend        (icn_hnf_rxdatpend),
      .hnf_rxdatlcrdv       (hnf_rxdatlcrdv),

      .hnf_txreqflitv       (hnf_txreqflitv),
      .hnf_txreqflit        (hnf_txreqflit),
      .hnf_txreqpend        (hnf_txreqpend),
      .hnf_txreqlcrdv       (hnf_txreqlcrdv),

      .hnf_txsnpflitv       (hnf_txsnpflitv),
      .hnf_txsnpflit        (hnf_txsnpflit),
      .hnf_txsnppend        (hnf_txsnppend),
      .hnf_txsnplcrdv       (hnf_txsnplcrdv),

      .hnf_txrspflitv       (hnf_txrspflitv),
      .hnf_txrspflit        (hnf_txrspflit),
      .hnf_txrsppend        (hnf_txrsppend),
      .hnf_txrsplcrdv       (hnf_txrsplcrdv),

      .hnf_txdatflitv       (hnf_txdatflitv),
      .hnf_txdatflit        (hnf_txdatflit),
      .hnf_txdatpend        (hnf_txdatpend),
      .hnf_txdatlcrdv       (hnf_txdatlcrdv),

      // --- SNF INTERFACE (Slave Node / Memory) ---
      .snf_rxreqflitv       (icn_snf_rxreqflitv),
      .snf_rxreqflit        (icn_snf_rxreqflit),
      .snf_rxreqlcrdv       (snf_rxreqlcrdv),

      .snf_rxdatflitv       (icn_snf_rxdatflitv),
      .snf_rxdatflit        (icn_snf_rxdatflit),
      .snf_rxdatlcrdv       (snf_rxdatlcrdv),

      .snf_txrspflitv       (snf_txrspflitv),
      .snf_txrspflit        (snf_txrspflit),
      .snf_txrsplcrdv       (icn_snf_txrsplcrdv),

      .snf_txdatflitv       (snf_txdatflitv),
      .snf_txdatflit        (snf_txdatflit),
      .snf_txdatlcrdv       (icn_snf_txdatlcrdv)

    );
  `endif

  task automatic chi_write_mem512(
    input [43:0]  addr,
    input [511:0] data
  );
    logic[`CHIE_RSP_FLIT_DBID_WIDTH-1:0] dbid;

    tb_snf_rxreqflit[`CHIE_REQ_FLIT_RANGE] = '0; // Clear

    // HN-F to SN-F WriteNoSnpFull Request Population
    tb_snf_rxreqflit[`CHIE_REQ_FLIT_QOS_RANGE]     = 4'b0000;              // Default priority
    tb_snf_rxreqflit[`CHIE_REQ_FLIT_TGTID_RANGE]   = SNF_NID_PARAM;           // The NodeID of the Memory Controller/SN-F
    tb_snf_rxreqflit[`CHIE_REQ_FLIT_SRCID_RANGE]   = HNF_NID_PARAM;           // The NodeID of your HN-F
    tb_snf_rxreqflit[`CHIE_REQ_FLIT_TXNID_RANGE]   = 12'hfab;     // Unique ID for tracking this specific write

    // --- The Command ---
    tb_snf_rxreqflit[`CHIE_REQ_FLIT_OPCODE_RANGE]  = `CHIE_WRITENOSNPFULL; // Opcode: 6'b011101 (Typical for Issue E)

    // --- Address and Attributes ---
    tb_snf_rxreqflit[`CHIE_REQ_FLIT_ADDR_RANGE]    = addr;
    tb_snf_rxreqflit[`CHIE_REQ_FLIT_NS_RANGE]      = 1'b1;                 // Usually Non-Secure for OpenPiton

    // Order: Usually 2'b00 (None) or 2'b10 (Endpoint Order)
    tb_snf_rxreqflit[`CHIE_REQ_FLIT_ORDER_RANGE]   = 2'b00;

    // Size: 3'b110 represents 64 Bytes (a full OpenPiton cache line)
    tb_snf_rxreqflit[`CHIE_REQ_FLIT_SIZE_RANGE]    = 3'b110;

    // MemAttr: Describes memory type (Device vs Normal, Cacheable vs Non-cacheable)
    // For SN-F writes, this is usually 4'b1111 (Write-back, Read/Write Allocate)
    tb_snf_rxreqflit[`CHIE_REQ_FLIT_MEMATTR_RANGE] = 4'b1111;

    tb_snf_rxreqflitv = 1'b1;

    @(posedge clk);
    tb_snf_rxreqflitv = 1'b0;

    wait(snf_txrspflitv && (snf_txrspflit[`CHIE_RSP_FLIT_OPCODE_RANGE] == `CHIE_COMPDBIDRESP) && (snf_txrspflit[`CHIE_REQ_FLIT_TGTID_RANGE] == HNF_NID_PARAM) && (snf_txrspflit[`CHIE_REQ_FLIT_TXNID_RANGE] == 12'hfab));

    // store the value of response DBID to be used with the upcoming data message
    dbid = snf_txrspflit[`CHIE_RSP_FLIT_DBID_RANGE];

    @(posedge clk);  // wait for a clock cycle and initiate data transfer on SNF_RXDAT, first SNF_RXDAT flit

    tb_snf_rxdatflit[`CHIE_DAT_FLIT_OPCODE_RANGE]   = `CHIE_NONCOPYBACKWRDATA;   // DAT Opcode: NONCOPYBACKWRDATA
    tb_snf_rxdatflit[`CHIE_DAT_FLIT_SRCID_RANGE]  = HNF_NID_PARAM;
    tb_snf_rxdatflit[`CHIE_DAT_FLIT_TGTID_RANGE]  = SNF_NID_PARAM;
    tb_snf_rxdatflit[`CHIE_DAT_FLIT_HOMENID_RANGE] = HNF_NID_PARAM;
    tb_snf_rxdatflit[`CHIE_DAT_FLIT_TXNID_RANGE]  = dbid;
    tb_snf_rxdatflit[`CHIE_DAT_FLIT_QOS_RANGE]  = `CHIE_DAT_FLIT_QOS_WIDTH'hf;
    tb_snf_rxdatflit[`CHIE_DAT_FLIT_RESPERR_RANGE]  = {`CHIE_DAT_FLIT_RESPERR_WIDTH{1'b0}};
    tb_snf_rxdatflit[`CHIE_DAT_FLIT_RESP_RANGE]     = {`CHIE_DAT_FLIT_RESP_WIDTH{1'b0}};
    tb_snf_rxdatflit[`CHIE_DAT_FLIT_FWDSTATE_RANGE] = {`CHIE_DAT_FLIT_FWDSTATE_WIDTH{1'b0}};
    tb_snf_rxdatflit[`CHIE_DAT_FLIT_CBUSY_RANGE]    = {`CHIE_DAT_FLIT_CBUSY_WIDTH{1'b0}};
    tb_snf_rxdatflit[`CHIE_DAT_FLIT_DBID_RANGE]     = dbid;
    tb_snf_rxdatflit[`CHIE_DAT_FLIT_CCID_RANGE]     = {`CHIE_DAT_FLIT_CCID_WIDTH{1'b0}};
    tb_snf_rxdatflit[`CHIE_DAT_FLIT_DATAID_RANGE]   = 2'b00;
    tb_snf_rxdatflit[`CHIE_DAT_FLIT_TAGOP_RANGE]    = {`CHIE_DAT_FLIT_TAGOP_WIDTH{1'b0}};
    tb_snf_rxdatflit[`CHIE_DAT_FLIT_TAG_RANGE]      = {`CHIE_DAT_FLIT_TAG_WIDTH{1'b0}};
    tb_snf_rxdatflit[`CHIE_DAT_FLIT_TU_RANGE]       = {`CHIE_DAT_FLIT_TU_WIDTH{1'b0}};
    tb_snf_rxdatflit[`CHIE_DAT_FLIT_TRACETAG_RANGE] = {`CHIE_DAT_FLIT_TRACETAG_WIDTH{1'b0}};
    tb_snf_rxdatflit[`CHIE_DAT_FLIT_BE_RANGE]       = {`CHIE_DAT_FLIT_BE_WIDTH{1'b1}};
    //tb_snf_rxdatflit[`CHIE_DAT_FLIT_POISON_RANGE]   = 0;
    //tb_snf_rxdatflit[`CHIE_DAT_FLIT_DATACHECK_RANGE]= 0;
    tb_snf_rxdatflit[`CHIE_DAT_FLIT_DATA_RANGE]     = data[255:0];
    tb_snf_rxdatflitv = 1'b1;

    @(posedge clk); // Second SNF_RXDAT flit

    tb_snf_rxdatflit[`CHIE_DAT_FLIT_OPCODE_RANGE]   = `CHIE_NONCOPYBACKWRDATA;   // DAT Opcode: NONCOPYBACKWRDATA
    tb_snf_rxdatflit[`CHIE_DAT_FLIT_SRCID_RANGE]  = HNF_NID_PARAM;
    tb_snf_rxdatflit[`CHIE_DAT_FLIT_TGTID_RANGE]  = SNF_NID_PARAM;
    tb_snf_rxdatflit[`CHIE_DAT_FLIT_HOMENID_RANGE] = HNF_NID_PARAM;
    tb_snf_rxdatflit[`CHIE_DAT_FLIT_TXNID_RANGE]  = dbid;
    tb_snf_rxdatflit[`CHIE_DAT_FLIT_QOS_RANGE]  = `CHIE_DAT_FLIT_QOS_WIDTH'hf;
    tb_snf_rxdatflit[`CHIE_DAT_FLIT_RESPERR_RANGE]  = {`CHIE_DAT_FLIT_RESPERR_WIDTH{1'b0}};
    tb_snf_rxdatflit[`CHIE_DAT_FLIT_RESP_RANGE]     = {`CHIE_DAT_FLIT_RESP_WIDTH{1'b0}};
    tb_snf_rxdatflit[`CHIE_DAT_FLIT_FWDSTATE_RANGE] = {`CHIE_DAT_FLIT_FWDSTATE_WIDTH{1'b0}};
    tb_snf_rxdatflit[`CHIE_DAT_FLIT_CBUSY_RANGE]    = {`CHIE_DAT_FLIT_CBUSY_WIDTH{1'b0}};
    tb_snf_rxdatflit[`CHIE_DAT_FLIT_DBID_RANGE]     = dbid;
    tb_snf_rxdatflit[`CHIE_DAT_FLIT_CCID_RANGE]     = {`CHIE_DAT_FLIT_CCID_WIDTH{1'b0}};
    tb_snf_rxdatflit[`CHIE_DAT_FLIT_DATAID_RANGE]   = 2'b10;
    tb_snf_rxdatflit[`CHIE_DAT_FLIT_TAGOP_RANGE]    = {`CHIE_DAT_FLIT_TAGOP_WIDTH{1'b0}};
    tb_snf_rxdatflit[`CHIE_DAT_FLIT_TAG_RANGE]      = {`CHIE_DAT_FLIT_TAG_WIDTH{1'b0}};
    tb_snf_rxdatflit[`CHIE_DAT_FLIT_TU_RANGE]       = {`CHIE_DAT_FLIT_TU_WIDTH{1'b0}};
    tb_snf_rxdatflit[`CHIE_DAT_FLIT_TRACETAG_RANGE] = {`CHIE_DAT_FLIT_TRACETAG_WIDTH{1'b0}};
    tb_snf_rxdatflit[`CHIE_DAT_FLIT_BE_RANGE]       = {`CHIE_DAT_FLIT_BE_WIDTH{1'b1}};
    //tb_snf_rxdatflit[`CHIE_DAT_FLIT_POISON_RANGE]   = 0;
    //tb_snf_rxdatflit[`CHIE_DAT_FLIT_DATACHECK_RANGE]= 0;
    tb_snf_rxdatflit[`CHIE_DAT_FLIT_DATA_RANGE]     = data[511:256];
    tb_snf_rxdatflitv = 1'b1;

    @(posedge clk);  // wait for one clock cycle and end the data transactions
    tb_snf_rxdatflitv = 1'b0;

    @(posedge clk);

    `ifdef TB_DEBUG
      $display("TB: Time: %0t | Writing 512-bit BLOCK 0x%h to   ADDR: 0x%h", $time, data, addr);
    `endif;
  endtask


  task automatic chi_read_mem512(
    input  [43:0]  addr,
    output logic[511:0] readback_data
  );
    logic [255:0] data_chunk0;
    logic [255:0] data_chunk1;
    logic [511:0] data;
    bit flit0_received, flit1_received;

    tb_snf_rxreqflit[`CHIE_REQ_FLIT_RANGE] = '0;

    // --- Request Phase (ReadNoSnp) ---
    tb_snf_rxreqflit[`CHIE_REQ_FLIT_QOS_RANGE]     = 4'b0000;
    tb_snf_rxreqflit[`CHIE_REQ_FLIT_TGTID_RANGE]   = SNF_NID_PARAM;
    tb_snf_rxreqflit[`CHIE_REQ_FLIT_SRCID_RANGE]   = HNF_NID_PARAM;
    tb_snf_rxreqflit[`CHIE_REQ_FLIT_TXNID_RANGE]   = 12'hace;           // Unique ID for this read
    tb_snf_rxreqflit[`CHIE_REQ_FLIT_OPCODE_RANGE]  = `CHIE_READNOSNP;   // Opcode for Read
    tb_snf_rxreqflit[`CHIE_REQ_FLIT_ADDR_RANGE]    = addr;
    tb_snf_rxreqflit[`CHIE_REQ_FLIT_NS_RANGE]      = 1'b1;
    tb_snf_rxreqflit[`CHIE_REQ_FLIT_ORDER_RANGE]   = 2'b00;
    tb_snf_rxreqflit[`CHIE_REQ_FLIT_SIZE_RANGE]    = 3'b110;            // 64 Bytes
    tb_snf_rxreqflit[`CHIE_REQ_FLIT_MEMATTR_RANGE] = 4'b1111;
    tb_snf_rxreqflit[`CHIE_REQ_FLIT_RETURNTXNID_RANGE] = 12'hace;

    tb_snf_rxreqflitv = 1'b1;

    @(posedge clk);
    tb_snf_rxreqflitv = 1'b0;

    // --- Data Response Phase ---
    // We expect 2 flits. We use a while loop to handle potential interleaved
    // or out-of-order DataIDs if the interconnect/slave supports it.
    flit0_received = 0;
    flit1_received = 0;

    while (!(flit0_received && flit1_received)) begin
      @(posedge clk);
      // Wait for valid data flit from SNF
      if (snf_txdatflitv && (snf_txdatflit[`CHIE_DAT_FLIT_TXNID_RANGE] == 12'hace)) begin

        // Check DataID to see which half of the 512-bit line arrived
        case (snf_txdatflit[`CHIE_DAT_FLIT_DATAID_RANGE])
          2'b00: begin
            data_chunk0 = snf_txdatflit[`CHIE_DAT_FLIT_DATA_RANGE];
            flit0_received = 1;
          end
          2'b10: begin // Typically 10 or 01 depending on your specific alignment
            data_chunk1 = snf_txdatflit[`CHIE_DAT_FLIT_DATA_RANGE];
            flit1_received = 1;
          end
        endcase
      end
    end

    // Combine chunks into output
    data = {data_chunk1, data_chunk0};
    readback_data = data;

    @(posedge clk);

    `ifdef TB_DEBUG
      $display("TB: Time: %0t | Reading 512-bit BLOCK 0x%h from ADDR: 0x%h", $time, data, addr);
    `endif
  endtask


  // --- Preload Hex Task ---
  task automatic preload_hex_file(
      input string         file_path,
      input logic [43:0]   start_addr
  );
    int fd;
    int status;
    int count;
    int instr_count;

    logic [31:0]  instr;
    logic [511:0] data;
    logic [511:0] readback_data;
    logic [43:0]  current_addr;

    // Initialize
    current_addr = start_addr;
    count        = 0;
    instr_count  = 0;
    data         = '0;

    fd = $fopen(file_path, "r");
    if (!fd) begin
        $error("[TB] Error: Could not open hex file: %s", file_path);
        $finish;
    end

    $display("[TB] Starting preload from %s to Addr %h", file_path, start_addr);

    while (!$feof(fd)) begin
        status = $fscanf(fd, "%h\n", instr);

        if (status == 1) begin
            // Pack 32-bit instruction into 512-bit line
            data[(count * 32) +: 32] = instr;
            count++;
            instr_count++;

            // Every 16 instructions = 512 bits (64 bytes)
            if (count == 16) begin
                chi_write_mem512(current_addr, data);

                // Verification Readback
                chi_read_mem512(current_addr, readback_data);
                if (readback_data !== data) begin
                    $error("[TB] Mismatch at Addr %h! Sent: %h, Recv: %h",
                            current_addr, data, readback_data);
                end

                // Reset for next block
                count = 0;
                data  = '0;
                current_addr += 44'd64; // Move 64 bytes forward
            end
        end
    end

    // Handle remaining instructions (Partial 512-bit block)
    if (count > 0) begin
        $display("[TB] Writing final partial block (%0d instrs)", count);
        chi_write_mem512(current_addr, data);
    end

    $fclose(fd);
    $display("[TB] Preload complete. Total instructions: %0d", instr_count);

  endtask

  initial begin
    int fd;
    integer status;
    int count; // Track how many instructions are packed
    logic [31:0] instr;
    logic [511:0] data;
    logic [511:0] readback_data;

    string dram_hex_path;
    string rom_hex_path;

    static logic [43:0] dram_base_addr = 44'h000080000000;
    static logic [43:0] rom_base_addr  = 44'h00fff1010000;

    // 1. Get DRAM path from command line. Use default if not provided.
    if (!$value$plusargs("DRAM_HEX=%s", dram_hex_path)) begin
        dram_hex_path = "./build/readshared.hex"; // Fallback default
    end

    // 2. Get ROM path from command line.
    if (!$value$plusargs("ROM_HEX=%s", rom_hex_path)) begin
        rom_hex_path = "./sw/bootrom.hex"; // Fallback default
    end


    $display("TB: Loading DRAM from: %s", dram_hex_path);
    $display("TB: Loading ROM from:  %s", rom_hex_path);

    program_load_done = 1'b0;

    tb_snf_rxdatflitv = 1'b0;
    tb_snf_rxreqflitv = 1'b0;

    wait(rst_n === 1'b1);


    preload_hex_file(dram_hex_path, dram_base_addr);

    preload_hex_file(rom_hex_path, rom_base_addr);

    // Wait for the L1.5's bram_1rw_wrapper BIST-clear to finish before
    // releasing program_load_done -- otherwise the RN-F reset rises at
    // the same edge as CVA6 starts fetching, and the first cache-fill
    // writes get silently redirected to bist_index (~ADDR_WIDTH cycles
    // of the L1.5 SRAMs, worst case 512).  Wait 2000 cycles (~4x BIST
    // duration) to be safely past init on every configuration.
    repeat (2000) @(posedge clk);

    program_load_done = 1'b1;
    $display("TB: Program Preload + L1.5 BIST clear complete!!");

    while(1);
  end


  endmodule