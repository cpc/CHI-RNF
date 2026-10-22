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


module chi_icn_beh #(
    parameter int CORE_COUNT = 2,
    parameter int ICN_RNF_REQ_CRDTS = 8,
    parameter int ICN_RNF_DAT_CRDTS = 8,
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
    parameter HNF_L3_WAY_NUM_PARAM = 16
)(
    input  logic clk,
    input  logic rst,

    // =====================================================
    // RNF VECTORIZED INTERFACE (Aggregated from N Cores)
    // =====================================================
    // TX Path (RNF -> ICN)
    input  logic [CORE_COUNT-1:0]                      rnf_txreqflitv,
    input  logic [CORE_COUNT-1:0][`CHIE_REQ_FLIT_WIDTH-1:0] rnf_txreqflit,
    output logic [CORE_COUNT-1:0]                      rnf_txreqlcrdv,

    input  logic [CORE_COUNT-1:0]                      rnf_txrspflitv,
    input  logic [CORE_COUNT-1:0][`CHIE_RSP_FLIT_WIDTH-1:0] rnf_txrspflit,
    output logic [CORE_COUNT-1:0]                      rnf_txrsplcrdv,

    input  logic [CORE_COUNT-1:0]                      rnf_txdatflitv,
    input  logic [CORE_COUNT-1:0][`CHIE_DAT_FLIT_WIDTH-1:0] rnf_txdatflit,
    output logic [CORE_COUNT-1:0]                      rnf_txdatlcrdv,

    // RX Path (ICN -> RNF)
    output logic [CORE_COUNT-1:0]                      rnf_rxsnpflitv,
    output logic [CORE_COUNT-1:0]                      rnf_rxsnppend,
    output logic [CORE_COUNT-1:0][`CHIE_SNP_FLIT_WIDTH-1:0] rnf_rxsnpflit,
    input  logic [CORE_COUNT-1:0]                      rnf_rxsnplcrdv,

    output logic [CORE_COUNT-1:0]                      rnf_rxrspflitv,
    output logic [CORE_COUNT-1:0]                      rnf_rxrsppend,
    output logic [CORE_COUNT-1:0][`CHIE_RSP_FLIT_WIDTH-1:0] rnf_rxrspflit,
    input  logic [CORE_COUNT-1:0]                      rnf_rxrsplcrdv,

    output logic [CORE_COUNT-1:0]                      rnf_rxdatflitv,
    output logic [CORE_COUNT-1:0]                      rnf_rxdatpend,
    output logic [CORE_COUNT-1:0][`CHIE_DAT_FLIT_WIDTH-1:0] rnf_rxdatflit,
    input  logic [CORE_COUNT-1:0]                      rnf_rxdatlcrdv,

    // Link layer handshake
    input  logic [CORE_COUNT-1:0]                      rnf_txlinkactivereq,
    output logic [CORE_COUNT-1:0]                      rnf_txlinkactiveack,
    output logic [CORE_COUNT-1:0]                      rnf_rxlinkactivereq,
    input  logic [CORE_COUNT-1:0]                      rnf_rxlinkactiveack,
    input  logic [CORE_COUNT-1:0]                      rnf_txactive,
    output logic [CORE_COUNT-1:0]                      rnf_rxactive,

    // =====================================================
    // HNF INTERFACE (Home Node)
    // =====================================================
    // HNF RX (Traffic coming into HNF)
    output logic                        hnf_rxreqflitv,
    output logic [`CHIE_REQ_FLIT_WIDTH-1:0] hnf_rxreqflit,
    output logic                        hnf_rxreqpend,   // Added REQ PEND
    input  logic                        hnf_rxreqlcrdv,

    output logic                        hnf_rxrspflitv,
    output logic [`CHIE_RSP_FLIT_WIDTH-1:0] hnf_rxrspflit,
    output logic                        hnf_rxrsppend,   // Added RSP PEND
    input  logic                        hnf_rxrsplcrdv,

    output logic                        hnf_rxdatflitv,
    output logic [`CHIE_DAT_FLIT_WIDTH-1:0] hnf_rxdatflit,
    output logic                        hnf_rxdatpend,   // Added DAT PEND
    input  logic                        hnf_rxdatlcrdv,

    // --- HNF TX (Traffic leaving HNF) ---
    input  logic                        hnf_txsnpflitv,
    input  logic [`CHIE_SNP_FLIT_WIDTH-1:0] hnf_txsnpflit,
    input  logic                        hnf_txsnppend,   // Added SNP PEND
    output logic                        hnf_txsnplcrdv,

    input  logic                        hnf_txreqflitv,
    input  logic [`CHIE_REQ_FLIT_WIDTH-1:0] hnf_txreqflit,
    input  logic                        hnf_txreqpend,   // Added SNP PEND
    output logic                        hnf_txreqlcrdv,

    input  logic                        hnf_txrspflitv,
    input  logic [`CHIE_RSP_FLIT_WIDTH-1:0] hnf_txrspflit,
    input  logic                        hnf_txrsppend,   // Added RSP PEND
    output logic                        hnf_txrsplcrdv,

    input  logic                        hnf_txdatflitv,
    input  logic [`CHIE_DAT_FLIT_WIDTH-1:0] hnf_txdatflit,
    input  logic                        hnf_txdatpend,   // Added DAT PEND
    output logic                        hnf_txdatlcrdv,

    // =====================================================
    // SNF INTERFACE (Slave Node / Memory)
    // =====================================================
    output logic                        snf_rxreqflitv,
    output logic [`CHIE_REQ_FLIT_WIDTH-1:0] snf_rxreqflit,
    input  logic                        snf_rxreqlcrdv,

    output logic                        snf_rxdatflitv,
    output logic [`CHIE_DAT_FLIT_WIDTH-1:0] snf_rxdatflit,
    input  logic                        snf_rxdatlcrdv,

    input  logic                        snf_txrspflitv,
    input  logic [`CHIE_RSP_FLIT_WIDTH-1:0] snf_txrspflit,
    output logic                        snf_txrsplcrdv,

    input  logic                        snf_txdatflitv,
    input  logic [`CHIE_DAT_FLIT_WIDTH-1:0] snf_txdatflit,
    output logic                        snf_txdatlcrdv,

    // Link layer handshake
    input  logic                        snf_txlinkactivereq,
    output logic                        snf_txlinkactiveack,
    output logic                        snf_rxlinkactivereq,
    input  logic                        snf_rxlinkactiveack,
    input  logic                        snf_txactive,
    output logic                        snf_rxactive
);


    // Parameters for the arbiter
    localparam int unsigned ARB_NUM_INPUTS = CORE_COUNT;
    localparam int unsigned ARB_DATA_WIDTH = `CHIE_REQ_FLIT_WIDTH;


    // Internal signals for arbiter ports
    logic [`CHIE_REQ_FLIT_WIDTH-1:0] arb_data_in [ARB_NUM_INPUTS];
    // int [CORE_COUNT-1:0] rnfdatcrdts, rnfsnpcrdts, rnfrspcrdts;

    // int [CORE_COUNT-1:0] rnfrspcrdts, rnfdatcrdts;

    // int [CORE_COUNT-1:0] icnrxreqcrdts, icnrspcrdts, icndatcrdts;

    int icnrxreqcrdts = CORE_COUNT; // one per core

    logic [`CHIE_REQ_FLIT_WIDTH-1:0] rnf_icn_reqflit[CORE_COUNT-1:0][$];
    logic                            rnf_icn_reqflitv[CORE_COUNT-1:0][$];

    logic [`CHIE_DAT_FLIT_WIDTH-1:0] rnf_icn_txdatflit[CORE_COUNT-1:0][$];
    logic                            rnf_icn_txdatflitv[CORE_COUNT-1:0][$];

    logic [`CHIE_DAT_FLIT_WIDTH-1:0] rnf_icn_rxdatflit[CORE_COUNT-1:0][$];
    logic                            rnf_icn_rxdatflitv[CORE_COUNT-1:0][$];

    logic [`CHIE_RSP_FLIT_WIDTH-1:0] rnf_icn_rspflit[CORE_COUNT-1:0][$];
    logic                            rnf_icn_rspflitv[CORE_COUNT-1:0][$];

    logic [`CHIE_RSP_FLIT_WIDTH-1:0] rnf_icn_rxrspflit[CORE_COUNT-1:0][$];
    logic                            rnf_icn_rxrspflitv[CORE_COUNT-1:0][$];

    logic [`CHIE_SNP_FLIT_WIDTH-1:0] rnf_icn_rxsnpflit[CORE_COUNT-1:0][$];
    logic                            rnf_icn_rxsnpflitv[CORE_COUNT-1:0][$];

    logic [`CHIE_DAT_FLIT_WIDTH-1:0] snf_icn_txdatflit[$];
    logic                            snf_icn_txdatflitv[$];

    logic [`CHIE_REQ_FLIT_WIDTH-1:0] hnf_icn_reqflit[$];
    logic                            hnf_icn_reqflitv[$];

    logic [`CHIE_SNP_FLIT_WIDTH-1:0] hnf_icn_snpflit[$];
    logic                            hnf_icn_snpflitv[$];


    logic icn_hnf_crdt_buf; // adds one cycle of latency so that credits are not used in the same cycle they are received (mandated by CHI specs)

    // Safety widths to prevent logic [-1:0] errors
    localparam int REQ_RSVDC_W = (CHIE_REQ_RSVDC_WIDTH_PARAM > 0) ? CHIE_REQ_RSVDC_WIDTH_PARAM : 1;
    localparam int DAT_RSVDC_W = (CHIE_DAT_RSVDC_WIDTH_PARAM > 0) ? CHIE_DAT_RSVDC_WIDTH_PARAM : 1;
    localparam int SNP_RSVDC_W = 1; // Default for SNP Reserved if not in params
    localparam int RSP_RSVDC_W = 1; // Default for RSP Reserved if not in params

    localparam int DAT_CHK_W   = (CHIE_DATACHECK_WIDTH_PARAM > 0) ? CHIE_DATACHECK_WIDTH_PARAM : 1;
    localparam int POISON_W    = (CHIE_POISON_WIDTH_PARAM > 0)    ? CHIE_POISON_WIDTH_PARAM    : 1;


    // --- REQ Channel (Request) ---
    typedef struct packed {
        //logic [CHIE_REQ_RSVDC_WIDTH_PARAM-1:0]   rsvdc;         // Top MSB
        logic                                    valid;
        logic                                    tracetag;
        logic [1:0]                              tagop;
        logic                                    expcompack;
        logic                                    excl;  
        logic                                    snoopme;  // Shared Bit
        logic [7:0]                              lpid;
        logic                                    snpattr; // Shared Bit
        logic                                    DoDWT; // Shared Bit
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
        //logic [CHIE_POISON_WIDTH_PARAM-1:0]      poison;        // Absolute MSB
        //logic [CHIE_DATACHECK_WIDTH_PARAM-1:0]   datacheck;
        logic                                    valid;
        logic [CHIE_DATA_WIDTH_PARAM-1:0]        data;
        logic [CHIE_BE_WIDTH_PARAM-1:0]          be;
        //logic [CHIE_DAT_RSVDC_WIDTH_PARAM-1:0]   rsvdc;
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
        logic                                    valid;
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

    // --- SNP Channel (Snoop) ---
    typedef struct packed {
        // logic [SNP_RSVDC_W-1:0]               rsvdc;         // Top MSB
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
        logic [3:0]                              qos;           // LSB 0
    } chie_snp_s;

    // ============================================================================
  // CHANNEL PARSING FUNCTIONS
  // These functions take a raw bit-vector and return a structured struct.
  // ============================================================================

  // --- REQ Channel Parser ---
  function automatic chie_req_s parse_req_flit(logic [`CHIE_REQ_FLIT_WIDTH-1:0] raw_flit, logic valid);
      chie_req_s s;
      s.valid           = valid;
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
      s.snpattr         = raw_flit[`CHIE_REQ_FLIT_SNPATTR_RANGE];
      s.DoDWT           = raw_flit[`CHIE_REQ_FLIT_DODWT_RANGE];
      s.lpid            = raw_flit[`CHIE_REQ_FLIT_LPID_RANGE];
      s.excl            = raw_flit[`CHIE_REQ_FLIT_EXCL_RANGE];
      s.snoopme            = raw_flit[`CHIE_REQ_FLIT_SNOOPME_RANGE];
      s.expcompack      = raw_flit[`CHIE_REQ_FLIT_EXPCOMPACK_RANGE];
      s.tagop           = raw_flit[`CHIE_REQ_FLIT_TAGOP_RANGE];
      s.tracetag        = raw_flit[`CHIE_REQ_FLIT_TRACETAG_RANGE];
      //s.rsvdc           = raw_flit[`CHIE_REQ_FLIT_RSVDC_RANGE];
      return s;
  endfunction

  // --- DAT Channel Parser ---
  function automatic chie_dat_s parse_dat_flit(logic [`CHIE_DAT_FLIT_WIDTH-1:0] raw_flit, valid);
      chie_dat_s s;
      s.valid           = valid;
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
  function automatic chie_rsp_s parse_rsp_flit(logic [`CHIE_RSP_FLIT_WIDTH-1:0] raw_flit, valid);
      chie_rsp_s s;
      s.valid           = valid;
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

  // --- SNP Channel Parser ---
  function automatic chie_snp_s parse_snp_flit(logic [`CHIE_SNP_FLIT_WIDTH-1:0] raw_flit, logic valid);
      chie_snp_s s;
      s.valid           = valid;
      s.qos             = raw_flit[`CHIE_SNP_FLIT_QOS_RANGE];
      s.srcid           = raw_flit[`CHIE_SNP_FLIT_SRCID_RANGE];
      s.tgtid           = raw_flit[`CHIE_SNP_FLIT_TGTID_RANGE];
      s.txnid           = raw_flit[`CHIE_SNP_FLIT_TXNID_RANGE];
      s.opcode          = raw_flit[`CHIE_SNP_FLIT_OPCODE_RANGE];
      s.addr            = raw_flit[`CHIE_SNP_FLIT_ADDR_RANGE];
      s.ns              = raw_flit[`CHIE_SNP_FLIT_NS_RANGE];
      s.fwdnid          = raw_flit[`CHIE_SNP_FLIT_FWDNID_RANGE];
      s.fwdtxnid        = raw_flit[`CHIE_SNP_FLIT_FWDTXNID_RANGE];
      s.ret_to_src      = raw_flit[`CHIE_SNP_FLIT_RETTOSRC_RANGE];
      s.do_not_goto_sd  = raw_flit[`CHIE_SNP_FLIT_DONOTGOTOSD_RANGE];
      //s.tagop           = raw_flit[`CHIE_SNP_FLIT_TAGOP_RANGE];
      s.tracetag        = raw_flit[`CHIE_SNP_FLIT_TRACETAG_RANGE];
      // s.rsvdc        = raw_flit[`CHIE_SNP_FLIT_RSVDC_RANGE];
      return s;
  endfunction

    // RNF -> ICN (TX)
    chie_req_s [CORE_COUNT-1:0] rnf_txreqflit_dbg;
    chie_rsp_s [CORE_COUNT-1:0] rnf_txrspflit_dbg;
    chie_dat_s [CORE_COUNT-1:0] rnf_txdatflit_dbg;

    // ICN -> RNF (RX)
    chie_rsp_s [CORE_COUNT-1:0] rnf_rxrspflit_dbg;
    chie_dat_s [CORE_COUNT-1:0] rnf_rxdatflit_dbg;

    // ICN -> HNF (RX)
    chie_req_s hnf_rxreqflit_dbg;
    chie_rsp_s hnf_rxrspflit_dbg;
    chie_dat_s hnf_rxdatflit_dbg;

    // HNF -> ICN (TX)
    chie_req_s hnf_txreqflit_dbg;
    chie_rsp_s hnf_txrspflit_dbg;
    chie_dat_s hnf_txdatflit_dbg;

    // ICN -> SNF (RX)
    chie_req_s snf_rxreqflit_dbg;
    chie_dat_s snf_rxdatflit_dbg;

    // SNF -> ICN (TX)
    chie_rsp_s snf_txrspflit_dbg;
    chie_dat_s snf_txdatflit_dbg;

    // ICN -> RNF (RX Snoop)
    chie_snp_s [CORE_COUNT-1:0] rnf_rxsnpflit_dbg;

    // HNF -> ICN (TX Snoop)
    chie_snp_s hnf_txsnpflit_dbg;


    always_comb begin
        // Parse RNF (Requester Node) vectorized signals
        for (int i = 0; i < CORE_COUNT; i++) begin
            rnf_txreqflit_dbg[i] = parse_req_flit(rnf_txreqflit[i], rnf_txreqflitv[i]);
            rnf_txrspflit_dbg[i] = parse_rsp_flit(rnf_txrspflit[i], rnf_txrspflitv[i]);
            rnf_txdatflit_dbg[i] = parse_dat_flit(rnf_txdatflit[i], rnf_txdatflitv[i]);

            // Assuming rnf_rxsnpflit exists in your debug signals
            rnf_rxrspflit_dbg[i] = parse_rsp_flit(rnf_rxrspflit[i], rnf_rxrspflitv[i]);
            rnf_rxdatflit_dbg[i] = parse_dat_flit(rnf_rxdatflit[i], rnf_rxdatflitv[i]);

            rnf_rxsnpflit_dbg[i] = parse_snp_flit(rnf_rxsnpflit[i], rnf_rxsnpflitv[i]);
        end

        // Parse HNF (Home Node) scalar signals
        hnf_rxreqflit_dbg = parse_req_flit(hnf_rxreqflit, hnf_rxreqflitv);
        hnf_rxrspflit_dbg = parse_rsp_flit(hnf_rxrspflit, hnf_rxrspflitv);
        hnf_rxdatflit_dbg = parse_dat_flit(hnf_rxdatflit, hnf_rxdatflitv);

        hnf_txreqflit_dbg = parse_req_flit(hnf_txreqflit, hnf_txreqflitv);
        hnf_txrspflit_dbg = parse_rsp_flit(hnf_txrspflit, hnf_txrspflitv);
        hnf_txdatflit_dbg = parse_dat_flit(hnf_txdatflit, hnf_txdatflitv);

        hnf_txsnpflit_dbg = parse_snp_flit(hnf_txsnpflit, hnf_txsnpflitv);

        // Parse SNF (Slave Node) scalar signals
        snf_rxreqflit_dbg = parse_req_flit(snf_rxreqflit, snf_rxreqflitv);
        snf_rxdatflit_dbg = parse_dat_flit(snf_rxdatflit, snf_rxdatflitv);
        snf_txrspflit_dbg = parse_rsp_flit(snf_txrspflit, snf_txrspflitv);
        snf_txdatflit_dbg = parse_dat_flit(snf_txdatflit, snf_txdatflitv);
    end


    task automatic activate_rnf_links(
        input int id
    );
       //$display("[CHI_LNK] Starting RN-F Link Activation at %t", $time);

       @(posedge clk);
       rnf_rxlinkactivereq[id] <= 1'b1;

       // Wait for the partner to acknowledge and request
       // Instead of a raw 'wait', check on every clock edge to avoid races
       do begin
           @(posedge clk);
       end while (!(rnf_rxlinkactiveack[id] === 1'b1 && rnf_txlinkactivereq[id] === 1'b1));

       rnf_txlinkactiveack[id] <= 1'b1;
       rnf_rxactive[id] <= 1'b1;


       @(posedge clk);
       //$display("[CHI_ICN] SN-F Link is now in RUN state at %t", $time);

       repeat(100) @(posedge clk);
    endtask


    task automatic activate_snf_links(
    );
       //$display("[CHI_LNK] Starting SN-F Link Activation at %t", $time);

       @(posedge clk);
       snf_rxlinkactivereq <= 1'b1;

       // Wait for the partner to acknowledge and request
       // Instead of a raw 'wait', check on every clock edge to avoid races
       do begin
           @(posedge clk);
       end while (!(snf_rxlinkactiveack === 1'b1 && snf_txlinkactivereq === 1'b1));

       snf_txlinkactiveack <= 1'b1;
       snf_rxactive <= 1'b1;


       @(posedge clk);
       //$display("[CHI_ICN] SN-F Link is now in RUN state at %t", $time);

       repeat(100) @(posedge clk);
    endtask


    task automatic activate_hni_links(
        input int id
    );
       //$display("[CHI_LNK] Starting Link Activation at %t", $time);

       @(posedge clk);
       rnf_rxlinkactivereq[id] <= 1'b1;

       // Wait for the partner to acknowledge and request
       // Instead of a raw 'wait', check on every clock edge to avoid races
       do begin
           @(posedge clk);
       end while (!(rnf_rxlinkactiveack[id] === 1'b1 && rnf_txlinkactivereq[id] === 1'b1));

       rnf_txlinkactiveack[id] <= 1'b1;
       rnf_rxactive[id] <= 1'b1;


       @(posedge clk);
       //$display("[CHI_ICN] Link is now in RUN state at %t", $time);

       repeat(100) @(posedge clk);
    endtask



    logic [`CHIE_RSP_FLIT_WIDTH-1:0] snf_icn_rxrspflit[$];
    logic                            snf_icn_rxrspflitv[$];

    task automatic hnf_rsp_link_manager();
        // Channel-specific credit and tracking
        int hnf_rxrsp_crdts = 32;
        int credit_return_candidates[$];
        int credit_return_candidate;

        // Reset/Initialize pulses
        hnf_rxrspflitv <= 1'b0;
        hnf_rxrsppend  <= 1'b0;
        hnf_rxrspflit  <= '0;
        snf_txrsplcrdv <= 1'b0;
        for (int core = 0; core < CORE_COUNT; core++) rnf_txrsplcrdv[core] <= 1'b0;

        // Wait for link activation (RNFs and SNF)
        while(~(&rnf_rxactive) || !snf_rxactive) @(posedge clk);

        // --- Credit Seeding Phase ---
        // Seed RN-Fs
        for (int _ = 0; _ < ICN_RNF_RSP_CRDTS; _++) begin
            for (int core = 0; core < CORE_COUNT; core++) rnf_txrsplcrdv[core] <= 1'b1;
            @(posedge clk);
        end
        rnf_txrsplcrdv <= '0;

        // Seed SN-F (Slave Node)
        // Using 4 credits as a default buffer for memory responses
        for (int _ = 0; _ < 4; _++) begin
            snf_txrsplcrdv <= 1'b1;
            @(posedge clk);
        end
        snf_txrsplcrdv <= 1'b0;

        @(posedge clk);

        // --- Main Arbitration & Relay Loop ---
        forever begin
            // 1. Buffer responses coming from RNFs
            for (int core = 0; core < CORE_COUNT; core++) begin
                if (rnf_txrspflitv[core]) begin
                    rnf_icn_rspflit[core].push_back(rnf_txrspflit[core]);
                    rnf_icn_rspflitv[core].push_back(1'b1);
                end
            end

            // 2. Buffer responses coming from SNF
            if (snf_txrspflitv) begin
                if ($test$plusargs("icn_debug"))
                    $display("[ICN_RSP] %0t: SNF sent RSP opc=0x%0h tgtId=%0d txnid=%0d",
                             $time,
                             snf_txrspflit[`CHIE_RSP_FLIT_OPCODE_RANGE],
                             int'(snf_txrspflit[`CHIE_RSP_FLIT_TGTID_RANGE]),
                             snf_txrspflit[`CHIE_RSP_FLIT_TXNID_RANGE]);
                snf_icn_rxrspflit.push_back(snf_txrspflit);
                snf_icn_rxrspflitv.push_back(1'b1);
            end

            // 3. Handle Credit Returns from HNF
            if (hnf_rxrsplcrdv) begin
                hnf_rxrsp_crdts++;
                if (credit_return_candidates.size() > 0) begin
                    credit_return_candidate = credit_return_candidates.pop_front();
                    // If the ID matches SNF, return credit to SNF, else to specific core
                    if (credit_return_candidate == SNF_NID_PARAM) begin
                        snf_txrsplcrdv <= 1'b1;
                    end else if (credit_return_candidate < CORE_COUNT) begin
                        rnf_txrsplcrdv[credit_return_candidate] <= 1'b1;
                    end
                end
            end

            @(posedge clk);

            // Clear pulses for next cycle
            hnf_rxrspflitv <= 1'b0;
            rnf_txrsplcrdv <= '0;
            snf_txrsplcrdv <= 1'b0;

            // 4. Arbitration Loop (Gate by HNF Credits)
            if (hnf_rxrsp_crdts > 0) begin
                bit sent = 0;

                // Priority A: Check SNF Queue (Memory responses often prioritize)
                if (snf_icn_rxrspflitv.size() > 0) begin
                    void'(snf_icn_rxrspflitv.pop_front());
                    hnf_rxrspflit <= snf_icn_rxrspflit.pop_front();
                    hnf_rxrspflitv <= 1'b1;

                    credit_return_candidates.push_back(SNF_NID_PARAM);
                    hnf_rxrsp_crdts--;
                    sent = 1;
                end

                // Priority B: Check RNF Queues (if SNF didn't send anything this cycle)
                if (!sent) begin
                    for (int core = 0; core < CORE_COUNT; core++) begin
                        if (rnf_icn_rspflitv[core].size() > 0) begin
                            void'(rnf_icn_rspflitv[core].pop_front());
                            hnf_rxrspflit <= rnf_icn_rspflit[core].pop_front();
                            hnf_rxrspflitv <= 1'b1;

                            credit_return_candidates.push_back(core);
                            hnf_rxrsp_crdts--;
                            break;
                        end
                    end
                end
            end
        end
    endtask


    task automatic snf_req_link_manager();
        // Channel-specific credit and tracking
        int snf_rxreq_crdts = 16;
        int credit_return_candidates[$];
        int credit_return_candidate;

        // Reset/Initialize HNF-facing signals
        snf_rxreqflitv <= 1'b0;
        //snf_rxreqpend  <= 1'b0;
        snf_rxreqflit  <= '0;

        begin hnf_txreqlcrdv <= 1'b1; repeat(ICN_HNF_REQ_CRDTS) @(posedge clk); hnf_txreqlcrdv <= 1'b0; end

        //

        @(posedge clk);

        forever begin
            if (hnf_txreqflitv) begin
                //$display("[CHI_ICN_RSP] Received Valid REQ Flit from HN-F at %t", $time);
                // Assuming these are queues declared at the module level
                hnf_icn_reqflit.push_back(hnf_txreqflit);
                hnf_icn_reqflitv.push_back(1'b1);
            end

            if (snf_rxreqlcrdv) begin
                snf_rxreq_crdts++;

                if (credit_return_candidates.size() > 0) begin
                    credit_return_candidate = credit_return_candidates.pop_front();
                    hnf_txreqlcrdv <= 1'b1;
                end
            end

            @(posedge clk);

            // Clear pulses for next cycle
            snf_rxreqflitv <= 1'b0;
            hnf_txreqlcrdv <= '0;

            // 3. Arbitration Loop (Gate by HNF Credits)
            if (snf_rxreq_crdts > 0) begin
                // Check if the internal buffer for this core has data
                if (hnf_icn_reqflitv.size() > 0) begin
                    // Remove valid bit and data from the core's internal queue
                    hnf_icn_reqflitv.pop_front();
                    snf_rxreqflit <= hnf_icn_reqflit.pop_front();

                    // Drive to HNF
                    snf_rxreqflitv <= 1'b1;

                    // Log the core for future credit return
                    credit_return_candidates.push_back(CORE_COUNT);

                    // Consume the credit
                    snf_rxreq_crdts--;
                end
            end
        end
    endtask


    task automatic hnf_dat_link_manager();
        // Channel-specific credit and tracking
        int hnfdatcrdts = 16;

        int credit_return_candidates[$];
        int credit_return_candidate;

        logic hnf_rxdat_locked = 1'b0;
        int   txdat_txn_counter = 0;
        int   owner = 0;

        int tgtId;

        // Reset/Initialize HNF-facing signals
        hnf_rxdatflitv <= 1'b0;
        //snf_rxreqpend  <= 1'b0;
        hnf_rxdatflit  <= '0;


        for (int core = 0; core < CORE_COUNT; core++) begin
            rnf_txreqlcrdv[core] <= 1'b0;
        end

        @(posedge clk);

        while(~(&rnf_rxactive));

        //$display("[CHI_ICN] Starting Link Credit Initialization for RNF REQ Channel at %t", $time);

        for (int _ = 0; _ < ICN_RNF_DAT_CRDTS; _++) begin   // credit initialization
            for (int core = 0; core < CORE_COUNT; core++) begin
                rnf_txdatlcrdv[core] <= 1'b1;
            end
            @(posedge clk);
        end

        for (int core = 0; core < CORE_COUNT; core++) begin
            rnf_txdatlcrdv[core] <= 1'b0;
        end

        @(posedge clk);

        while(1) begin
            for (int core = 0; core < CORE_COUNT; core++) begin // buffer requests coming from RNFs
                tgtId = (int'(rnf_txdatflit[core][`CHIE_DAT_FLIT_TGTID_RANGE]));

                if(rnf_txdatflitv[core] && tgtId==HNF_NID_PARAM) begin
                    //$display("[CHI_ICN_DAT] Received a Valid Flit from core_id %d at %t", core, $time);

                    rnf_icn_txdatflit[core].push_back(rnf_txdatflit[core]);
                    rnf_icn_txdatflitv[core].push_back(rnf_txdatflitv[core]);
                end
            end

            tgtId = (int'(snf_txdatflit[`CHIE_DAT_FLIT_TGTID_RANGE]));
            if(snf_txdatflitv && tgtId==HNF_NID_PARAM) begin
                //$display("[CHI_ICN_DAT] Received a Valid Flit from SNF at %t", $time);

                snf_icn_txdatflit.push_back(snf_txdatflit);
                snf_icn_txdatflitv.push_back(snf_txdatflitv);
            end

            // poping from the credit candidates is performed seperately
            // from pushing in order to avoid using the credit in the same clock cycles they are returned
            if(hnf_rxdatlcrdv) begin
                hnfdatcrdts++;

                if(credit_return_candidates.size() > 0) begin
                    credit_return_candidate = credit_return_candidates.pop_front();
                    if(credit_return_candidate < CORE_COUNT) begin
                        rnf_txdatlcrdv[credit_return_candidate] <= 1'b1;
                    end else begin
                        snf_txdatlcrdv <= 1'b1;
                    end
                end
            end

            @(posedge clk);
            hnf_rxdatflitv <= 1'b0;
            rnf_txdatlcrdv <= 1'b0;
            snf_txdatlcrdv <= 1'b0;

            if(hnfdatcrdts > 0) begin  // we have credits on the REQ to HNF channel so we execute the arbitration loop
                for (int core = 0; core < CORE_COUNT; core++) begin   // arbitrate one request from the buffered requests
                    if(rnf_icn_txdatflitv[core][0] && (~hnf_rxdat_locked || (owner == core))) begin
                        rnf_icn_txdatflitv[core].pop_front();   // remove the oldest transaction

                        hnf_rxdatflit <= rnf_icn_txdatflit[core].pop_front();
                        hnf_rxdatflitv <= 1'b1;

                        credit_return_candidates.push_back(core);

                        hnf_rxdat_locked = 1'b1;
                        owner = core;

                        hnfdatcrdts--;
                        txdat_txn_counter++;

                        break;
                    end
                end

                if((snf_icn_txdatflitv.size() > 0) && (~hnf_rxdat_locked || (owner == SNF_NID_PARAM))) begin  // TODO: change to SNF_ID
                    snf_icn_txdatflitv.pop_front();   // remove the oldest transaction

                    hnf_rxdatflit <= snf_icn_txdatflit.pop_front();
                    hnf_rxdatflitv <= 1'b1;

                    credit_return_candidates.push_back(SNF_NID_PARAM);

                    hnf_rxdat_locked = 1'b1;
                    owner = SNF_NID_PARAM;

                    hnfdatcrdts--;
                    txdat_txn_counter++;

                    //$display("======================[DEBUG] Received a Valid Flit from SNF at %t ==================", $time);
                end


                if(txdat_txn_counter == NUM_DATA_FLITS) begin
                    hnf_rxdat_locked = 1'b0;
                    txdat_txn_counter = 0;
                end
            end
        end

        @(posedge clk);
    endtask


    logic [`CHIE_DAT_FLIT_WIDTH-1:0] snf_to_hnf_dat_q[$];
    logic                            snf_to_hnf_dat_qv[$];

    task automatic consolidated_dat_manager();
        // Credits the ICN holds from sinks (ability to send)
        int rnf_out_crdts[CORE_COUNT];
        int hnf_rx_crdts = 512;
        int snf_rx_crdts = 512;

        int tgtId;

        // 1. Reset all local pulses/outputs
        hnf_txdatlcrdv <= 1'b0;
        snf_txdatlcrdv <= 1'b0;
        hnf_rxdatflitv <= 1'b0;
        snf_rxdatflitv <= 1'b0;
        for (int i=0; i<CORE_COUNT; i++) begin
            rnf_txdatlcrdv[i] <= 1'b0;
            rnf_rxdatflitv[i] <= 1'b0;
            rnf_out_crdts[i]  = 2;
        end

        // 2. INITIAL SEEDING
        @(posedge clk);
        hnf_txdatlcrdv <= 1'b1;
        snf_txdatlcrdv <= 1'b1;
        for (int i=0; i<CORE_COUNT; i++) rnf_txdatlcrdv[i] <= 1'b1;
        repeat(8) @(posedge clk);
        hnf_txdatlcrdv <= 1'b0;
        snf_txdatlcrdv <= 1'b0;
        rnf_txdatlcrdv <= '0;

        forever begin
            // =====================================================
            // PHASE 1: CAPTURE (Inbound to ICN)
            // =====================================================

            // From HNF: Route to RNF or SNF
            if (hnf_txdatflitv) begin
                tgtId = int'(hnf_txdatflit[`CHIE_DAT_FLIT_TGTID_RANGE]);
                if (tgtId < CORE_COUNT) begin
                    rnf_icn_rxdatflit[tgtId].push_back(hnf_txdatflit);
                    rnf_icn_rxdatflitv[tgtId].push_back(1'b1);
                end else if (tgtId == SNF_NID_PARAM) begin
                    snf_icn_txdatflit.push_back(hnf_txdatflit);
                    snf_icn_txdatflitv.push_back(1'b1);
                end
                hnf_txdatlcrdv <= 1'b1; // Unconditional return
            end

            // From SNF: Route to RNFs or HNF
            if (snf_txdatflitv) begin
                tgtId = int'(snf_txdatflit[`CHIE_DAT_FLIT_TGTID_RANGE]);
                if (tgtId < CORE_COUNT) begin
                    rnf_icn_rxdatflit[tgtId].push_back(snf_txdatflit);
                    rnf_icn_rxdatflitv[tgtId].push_back(1'b1);
                end else if (tgtId == HNF_NID_PARAM) begin
                    // FIX: Using dedicated queue for SNF -> HNF
                    snf_to_hnf_dat_q.push_back(snf_txdatflit);
                    snf_to_hnf_dat_qv.push_back(1'b1);
                end
                snf_txdatlcrdv <= 1'b1;
            end

            // From RNFs: Route to HNF
            for (int i=0; i<CORE_COUNT; i++) begin
                if (rnf_txdatflitv[i]) begin
                    if ($test$plusargs("icn_debug"))
                        $display("[ICN_DAT] %0t: captured DAT flit from RNF%0d (opc=0x%0h txnid=%0d tgt=%0d)",
                                 $time, i,
                                 rnf_txdatflit[i][`CHIE_DAT_FLIT_OPCODE_RANGE],
                                 rnf_txdatflit[i][`CHIE_DAT_FLIT_TXNID_RANGE],
                                 rnf_txdatflit[i][`CHIE_DAT_FLIT_TGTID_RANGE]);
                    rnf_icn_txdatflit[i].push_back(rnf_txdatflit[i]);
                    rnf_icn_txdatflitv[i].push_back(1'b1);
                    rnf_txdatlcrdv[i] <= 1'b1;
                end
            end

            // =====================================================
            // PHASE 2: TRACK OUTBOUND CREDITS (Credits from Sinks)
            // =====================================================
            for (int i=0; i<CORE_COUNT; i++) if (rnf_rxdatlcrdv[i]) rnf_out_crdts[i]++;
            if (hnf_rxdatlcrdv) hnf_rx_crdts++;
            if (snf_rxdatlcrdv) snf_rx_crdts++;

            @(posedge clk);

            // =====================================================
            // PHASE 3: TRANSMIT (Driving the Output Pins)
            // =====================================================
            hnf_txdatlcrdv <= 1'b0;
            snf_txdatlcrdv <= 1'b0;
            hnf_rxdatflitv <= 1'b0;
            snf_rxdatflitv <= 1'b0;
            for (int i=0; i<CORE_COUNT; i++) begin
                rnf_txdatlcrdv[i] <= 1'b0;
                rnf_rxdatflitv[i] <= 1'b0;
            end

            // --- Transmit to RNFs (Cores) ---
            for (int i=0; i<CORE_COUNT; i++) begin
                if (rnf_icn_rxdatflitv[i].size() > 0 && rnf_out_crdts[i] > 0) begin
                    void'(rnf_icn_rxdatflitv[i].pop_front());
                    rnf_rxdatflit[i]  <= rnf_icn_rxdatflit[i].pop_front();
                    rnf_rxdatflitv[i] <= 1'b1;
                    rnf_out_crdts[i]--;
                    break; // Drive one core per cycle
                end
            end

            // --- Transmit to HNF (Home Node) ---
            if (hnf_rx_crdts > 0) begin
                bit hnf_sent = 0;
                // Priority A: Data from Memory (SNF -> HNF)
                if (snf_to_hnf_dat_qv.size() > 0) begin
                    void'(snf_to_hnf_dat_qv.pop_front());
                    hnf_rxdatflit  <= snf_to_hnf_dat_q.pop_front();
                    hnf_rxdatflitv <= 1'b1;
                    hnf_rx_crdts--;
                    hnf_sent = 1;
                end
                // Priority B: Data from Cores (RNF -> HNF)
                if (!hnf_sent) begin
                    for (int i=0; i<CORE_COUNT; i++) begin
                        if (rnf_icn_txdatflitv[i].size() > 0) begin
                            automatic logic [`CHIE_DAT_FLIT_WIDTH-1:0] tmp_df;
                            void'(rnf_icn_txdatflitv[i].pop_front());
                            tmp_df = rnf_icn_txdatflit[i].pop_front();
                            if ($test$plusargs("icn_debug"))
                                $display("[ICN_DAT] %0t: forwarding DAT to HNF from RNF%0d (opc=0x%0h txnid=%0d hnf_rx_crdts=%0d)",
                                         $time, i,
                                         tmp_df[`CHIE_DAT_FLIT_OPCODE_RANGE],
                                         tmp_df[`CHIE_DAT_FLIT_TXNID_RANGE],
                                         hnf_rx_crdts);
                            hnf_rxdatflit  <= tmp_df;
                            hnf_rxdatflitv <= 1'b1;
                            hnf_rx_crdts--;
                            break;
                        end
                    end
                end
            end

            // --- Transmit to SNF (Slave Node) ---
            if (snf_icn_txdatflitv.size() > 0 && snf_rx_crdts > 0) begin
                void'(snf_icn_txdatflitv.pop_front());
                snf_rxdatflit  <= snf_icn_txdatflit.pop_front();
                snf_rxdatflitv <= 1'b1;
                snf_rx_crdts--;
            end
        end
    endtask

    
    task automatic consolidated_req_manager();
        // Credits the ICN holds from sinks (permission to drive pins)
        int hnf_rx_req_crdts = 32;
        int snf_rx_req_crdts = 32;

        int tgtId;

        // 1. Reset all REQ output pulses/signals
        hnf_rxreqflitv <= 1'b0;
        snf_rxreqflitv <= 1'b0;
        hnf_txreqlcrdv <= 1'b0;
        for (int i=0; i<CORE_COUNT; i++) rnf_txreqlcrdv[i] <= 1'b0;

        // 2. INITIAL SEEDING (The "Stupid" Fix)
        // Pulse the credits back to the sources so they can issue their first requests
        @(posedge clk);
        hnf_txreqlcrdv <= 1'b1;
        for (int i=0; i<CORE_COUNT; i++) rnf_txreqlcrdv[i] <= 1'b1;

        repeat(15) @(posedge clk);

        hnf_txreqlcrdv <= 1'b0;
        for (int i=0; i<CORE_COUNT; i++) rnf_txreqlcrdv[i] <= 1'b0;

        forever begin
            // =====================================================
            // PHASE 1: CAPTURE (Inbound to ICN)
            // =====================================================

            // From RNFs (Cores): Buffer and return credit immediately
            for (int i=0; i<CORE_COUNT; i++) begin
                if (rnf_txreqflitv[i]) begin
                    rnf_icn_reqflit[i].push_back(rnf_txreqflit[i]);
                    rnf_icn_reqflitv[i].push_back(1'b1);
                    // Pulse credit back to Core
                    rnf_txreqlcrdv[i] <= 1'b1;
                end
            end

            // From HNF: Buffer and return credit immediately
            if (hnf_txreqflitv) begin
                if ($test$plusargs("icn_debug"))
                    $display("[ICN_REQ] %0t: HNF sent REQ opc=0x%0h addr=0x%0h txnid=%0d tgt=%0d",
                             $time,
                             hnf_txreqflit[`CHIE_REQ_FLIT_OPCODE_RANGE],
                             hnf_txreqflit[`CHIE_REQ_FLIT_ADDR_RANGE],
                             hnf_txreqflit[`CHIE_REQ_FLIT_TXNID_RANGE],
                             hnf_txreqflit[`CHIE_REQ_FLIT_TGTID_RANGE]);
                hnf_icn_reqflit.push_back(hnf_txreqflit);
                hnf_icn_reqflitv.push_back(1'b1);
                // Pulse credit back to Home Node
                hnf_txreqlcrdv <= 1'b1;
            end

            // =====================================================
            // PHASE 2: TRACK OUTBOUND CREDITS (Wait for Sinks)
            // =====================================================
            if (hnf_rxreqlcrdv) hnf_rx_req_crdts++;
            if (snf_rxreqlcrdv) snf_rx_req_crdts++;

            @(posedge clk);

            // =====================================================
            // PHASE 3: TRANSMIT (Drive Output REQ Pins)
            // =====================================================
            // Reset pulses for this cycle
            hnf_rxreqflitv <= 1'b0;
            snf_rxreqflitv <= 1'b0;
            hnf_txreqlcrdv <= 1'b0;
            for (int i=0; i<CORE_COUNT; i++) rnf_txreqlcrdv[i] <= 1'b0;

            // --- Transmit to HNF (RNF -> HNF) ---
            if (hnf_rx_req_crdts > 0) begin
                for (int i=0; i<CORE_COUNT; i++) begin
                    if (rnf_icn_reqflitv[i].size() > 0) begin
                        automatic logic [`CHIE_REQ_FLIT_WIDTH-1:0] tmp_flit;

                        void'(rnf_icn_reqflitv[i].pop_front());
                        tmp_flit = rnf_icn_reqflit[i].pop_front();

                        // Protocol Transformation (matching your original logic)
                        if(tmp_flit[`CHIE_REQ_FLIT_OPCODE_RANGE] == `CHIE_READSHARED) begin
                            tmp_flit[`CHIE_REQ_FLIT_OPCODE_RANGE] =  `CHIE_READCLEAN;
                        end

                        hnf_rxreqflit  <= tmp_flit;
                        hnf_rxreqflitv <= 1'b1;
                        hnf_rx_req_crdts--;
                        break; // One request per cycle to HNF
                    end
                end
            end

            // --- Transmit to SNF (HNF -> SNF) ---
            if (snf_rx_req_crdts > 0 && hnf_icn_reqflitv.size() > 0) begin
                void'(hnf_icn_reqflitv.pop_front());
                snf_rxreqflit  <= hnf_icn_reqflit.pop_front();
                snf_rxreqflitv <= 1'b1;
                snf_rx_req_crdts--;
            end
        end
    endtask


    task automatic rnf_rsp_link_manager();
        // Channel-specific credit and tracking
        int rnfrspcrdts = 32;

        int credit_return_candidates[$];
        int credit_return_candidate;

        // logic rnf_rxrsp_locked = 1'b0; // RSP is single-cycle, no locking needed
        // int   txrsp_txn_counter = 0;
        int   owner = 0;

        int   tgtId_hnf, tgtId_snf, srcId;

        begin hnf_txrsplcrdv <= 1'b1; repeat(ICN_HNF_RSP_CRDTS) @(posedge clk); hnf_txrsplcrdv <= 1'b0; end

        for (int core = 0; core < CORE_COUNT; core++) begin
            rnf_rxrspflitv[core] <= 1'b0;
        end

        @(posedge clk);

        while(1) begin
            tgtId_hnf = (int'(hnf_txrspflit[`CHIE_RSP_FLIT_TGTID_RANGE]));
            tgtId_snf = (int'(snf_txrspflit[`CHIE_RSP_FLIT_TGTID_RANGE]));

            if(hnf_txrspflitv && tgtId_hnf<CORE_COUNT) begin
                if ($test$plusargs("icn_debug"))
                    $display("[ICN_RSP] %0t: HNF sent RSP opc=0x%0h tgtId=%0d txnid=%0d dbid=%0d",
                             $time,
                             hnf_txrspflit[`CHIE_RSP_FLIT_OPCODE_RANGE],
                             tgtId_hnf,
                             hnf_txrspflit[`CHIE_RSP_FLIT_TXNID_RANGE],
                             hnf_txrspflit[`CHIE_RSP_FLIT_DBID_RANGE]);
                rnf_icn_rxrspflit[tgtId_hnf].push_back(hnf_txrspflit);
                rnf_icn_rxrspflitv[tgtId_hnf].push_back(hnf_txrspflitv);
            end

            if(snf_txrspflitv && tgtId_snf<CORE_COUNT) begin
                rnf_icn_rxrspflit[tgtId_snf].push_back(snf_txrspflit);
                rnf_icn_rxrspflitv[tgtId_snf].push_back(snf_txrspflitv);
            end

            // poping from the credit candidates is performed seperately
            // from pushing in order to avoid using the credit in the same clock cycles they are returned
            for (int core = 0; core < CORE_COUNT; core++) begin
                if(rnf_rxrsplcrdv[core]) begin
                    rnfrspcrdts++;

                    if(credit_return_candidates.size() > 0) begin
                        credit_return_candidate = credit_return_candidates.pop_front();
                        if(credit_return_candidate == HNF_NID_PARAM) begin
                            hnf_txrsplcrdv <= 1'b1;
                        end else begin
                            snf_txrsplcrdv <= 1'b1;
                        end
                    end
                end
            end

            @(posedge clk);

            for (int core = 0; core < CORE_COUNT; core++) begin
                rnf_rxrspflitv[core] <= 1'b0;
            end

            hnf_txrsplcrdv <= 1'b0;
            snf_txrsplcrdv <= 1'b0;

            if(rnfrspcrdts > 0) begin  // we have credits on the REQ to HNF channel so we execute the arbitration loop
                for (int core = 0; core < CORE_COUNT; core++) begin   // arbitrate one request from the buffered requests
                    if(rnf_icn_rxrspflitv[core].size() > 0) begin
                        automatic logic [`CHIE_RSP_FLIT_WIDTH-1:0] tmp_flit;

                        void'(rnf_icn_rxrspflitv[core].pop_front());   // remove the oldest transaction

                        tmp_flit = rnf_icn_rxrspflit[core].pop_front();

                        if ($test$plusargs("icn_debug"))
                            $display("[ICN_RSP] %0t: forwarding RSP to RNF%0d opc=0x%0h txnid=%0d (rnfrspcrdts=%0d)",
                                     $time, core,
                                     tmp_flit[`CHIE_RSP_FLIT_OPCODE_RANGE],
                                     tmp_flit[`CHIE_RSP_FLIT_TXNID_RANGE],
                                     rnfrspcrdts);
                        rnf_rxrspflit[core] <= tmp_flit;
                        rnf_rxrspflitv[core] <= 1'b1;

                        // Use the module-level signal for bit-slicing to avoid timing races
                        srcId = (int'(tmp_flit[`CHIE_RSP_FLIT_SRCID_RANGE]));
                        credit_return_candidates.push_back(srcId);

                        // owner = core; // Optional for debug tracking
                        rnfrspcrdts--;
                        // txrsp_txn_counter++; // Removed as RSP is always 1 flit

                        break;
                    end
                end

                // RSP does not require a multi-flit counter check
            end
        end

        @(posedge clk);
    endtask


    task automatic rnf_snp_link_manager();
        // Credit tracking for the ICN -> RNF link
        // Typically, each RNF manages its own ingress snoop credits
        int rnf_snp_crdts[CORE_COUNT];
        
        // Queue to track which source (HNF) needs a credit back 
        // when an RNF consumes a flit
        int credit_return_candidates[$];
        int credit_return_candidate;

        int tgtId;

        // --- Initialization ---
        // 1. Initialize RNF local credits (adjust starting value as per spec)
        for (int i = 0; i < CORE_COUNT; i++) begin
            rnf_snp_crdts[i] = 1; 
            rnf_rxsnpflitv[i] <= 1'b0;
        end

        // 2. Give initial credits to HNF so it can begin transmitting
        begin 
            hnf_txsnplcrdv <= 1'b1; 
            repeat(ICN_HNF_SNP_CRDTS) @(posedge clk); 
            hnf_txsnplcrdv <= 1'b0; 
        end

        @(posedge clk);

        while(1) begin
            // --- Capture: Pull Snoops from HNF into ICN Buffers ---
            if(hnf_txsnpflitv) begin
                tgtId = int'(hnf_txsnpflit[`CHIE_SNP_FLIT_TGTID_RANGE]);
                
                if(tgtId < CORE_COUNT) begin
                    rnf_icn_rxsnpflit[tgtId].push_back(hnf_txsnpflit);
                    rnf_icn_rxsnpflitv[tgtId].push_back(1'b1);
                end
            end

            // --- Credit Return: Handle RNF -> ICN returns and signal back to HNF ---
            for (int core = 0; core < CORE_COUNT; core++) begin
                if(rnf_rxsnplcrdv[core]) begin
                    rnf_snp_crdts[core]++;

                    if(credit_return_candidates.size() > 0) begin
                        // Return credit to the original requester (HNF)
                        void'(credit_return_candidates.pop_front());
                        hnf_txsnplcrdv <= 1'b1; 
                    end
                end
            end

            @(posedge clk);

            // De-assert valids and credit returns from previous cycle
            for (int core = 0; core < CORE_COUNT; core++) begin
                rnf_rxsnpflitv[core] <= 1'b0;
            end
            hnf_txsnplcrdv <= 1'b0;

            // --- Egress: Forward buffered Snoops to RNFs ---
            // Simple Round-Robin or Fixed Priority arbitration across cores
            for (int core = 0; core < CORE_COUNT; core++) begin
                // If we have a buffered flit and a credit for this specific RNF
                if(rnf_icn_rxsnpflitv[core].size() > 0 && rnf_snp_crdts[core] > 0) begin
                    automatic logic [`CHIE_SNP_FLIT_WIDTH-1:0] tmp_flit;

                    // Remove from ICN buffer
                    void'(rnf_icn_rxsnpflitv[core].pop_front());
                    tmp_flit = rnf_icn_rxsnpflit[core].pop_front();

                    // Drive to RNF
                    rnf_rxsnpflit[core]  <= tmp_flit;
                    rnf_rxsnpflitv[core] <= 1'b1;

                    // Record that a flit was dispatched (to return credit to HNF later)
                    credit_return_candidates.push_back(HNF_NID_PARAM);

                    rnf_snp_crdts[core]--;
                    
                    // Limit to one snoop dispatch per clock cycle across the ICN switch fabric
                    break; 
                end
            end
        end
    endtask


    task automatic hnf_snp_link_manager();
        begin hnf_txsnplcrdv <= 1'b1; repeat(ICN_HNF_SNP_CRDTS) @(posedge clk); hnf_txsnplcrdv <= 1'b0; end

        while(1) begin
            @(posedge clk);
        end

    endtask


    initial begin
        rnf_rxactive = 0;
        rnf_rxlinkactivereq = 0;
        rnf_txlinkactiveack = 0;

        // Reset/Initialize RNF-facing signals
        rnf_rxrspflitv <= 1'b0;
        rnf_rxrsppend  <= 1'b0;
        rnf_rxrspflit  <= '0;

        rnf_rxdatflitv <= 1'b0;
        rnf_rxdatpend  <= 1'b0;
        rnf_rxdatflit  <= '0;

        rnf_rxsnpflitv <= 1'b0;
        rnf_rxsnppend  <= 1'b0;
        rnf_rxsnpflit  <= '0;

        //rnfdatcrdts = 0;
        //rnfrspcrdts = 0;
        //rnfsnpcrdts = 0;

        // SNF Link Activation is performed at the start of the simulation
        activate_snf_links();

        wait(rst == 0);

        fork
            for (int core = 0; core < CORE_COUNT; core++) begin
                automatic int core_id = core;
            fork
                activate_rnf_links(
                        core_id
                    );
            join_none
            end
        join

        fork
            hnf_rsp_link_manager();
            hnf_snp_link_manager();
            consolidated_dat_manager();
            consolidated_req_manager();

            rnf_rsp_link_manager();
            rnf_snp_link_manager();
        join

        while(1);
    end
endmodule