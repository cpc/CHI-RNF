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
// chi_flit_dbg.svh -- one packed struct per CHI channel, for waveform debug.
//
// Mirrors the chie_*_s types and parse_*_flit helpers in chi_icn_beh.sv.
// Duplicated rather than shared because those live inside the ICN module,
// and the IP-level TB instantiates chi_hnf_responder instead.  Field
// order and names match the ICN so a trace reads the same either side.
//
// Each struct carries its own `valid`, so one signal in the wave window
// tells you whether the flit is real and what it contains -- no pairing
// a separate *FLITV with a pile of decoded fields.
//
// Include inside the TB module (needs the CHIE_*_PARAM parameters in scope).

// --- REQ Channel ---
typedef struct packed {
    logic                                 valid;
    logic                                 tracetag;
    logic [1:0]                           tagop;
    logic                                 expcompack;
    logic                                 excl;
    logic                                 snoopme;
    logic [7:0]                           lpid;
    logic                                 snpattr;
    logic                                 DoDWT;
    logic [3:0]                           memattr;
    logic [3:0]                           pcrdtype;
    logic [1:0]                           order;
    logic                                 allowretry;
    logic                                 likelyshared;
    logic                                 ns;
    logic [CHIE_REQ_ADDR_WIDTH_PARAM-1:0] addr;
    logic [2:0]                           size;
    logic [6:0]                           opcode;
    logic [11:0]                          returntxnid;
    logic                                 stshv_endian;
    logic [CHIE_NID_WIDTH_PARAM-1:0]      return_stsh_nid;
    logic [11:0]                          txnid;
    logic [CHIE_NID_WIDTH_PARAM-1:0]      srcid;
    logic [CHIE_NID_WIDTH_PARAM-1:0]      tgtid;
    logic [3:0]                           qos;
} chie_req_s;

// --- DAT Channel ---
typedef struct packed {
    logic                                 valid;
    logic [CHIE_DATA_WIDTH_PARAM-1:0]     data;
    logic [CHIE_BE_WIDTH_PARAM-1:0]       be;
    logic                                 tracetag;
    logic [1:0]                           dataid;
    logic [1:0]                           ccid;
    logic [11:0]                          dbid;
    logic [2:0]                           cbusy;
    logic [2:0]                           resp;
    logic [1:0]                           resperr;
    logic [3:0]                           opcode;
    logic [CHIE_NID_WIDTH_PARAM-1:0]      homenid;
    logic [11:0]                          txnid;
    logic [CHIE_NID_WIDTH_PARAM-1:0]      srcid;
    logic [CHIE_NID_WIDTH_PARAM-1:0]      tgtid;
    logic [3:0]                           qos;
} chie_dat_s;

// --- RSP Channel ---
typedef struct packed {
    logic                                 valid;
    logic                                 tracetag;
    logic [1:0]                           tagop;
    logic [3:0]                           pcrdtype;
    logic [11:0]                          dbid;
    logic [2:0]                           cbusy;
    logic [2:0]                           resp;
    logic [1:0]                           resperr;
    logic [4:0]                           opcode;
    logic [11:0]                          txnid;
    logic [CHIE_NID_WIDTH_PARAM-1:0]      srcid;
    logic [CHIE_NID_WIDTH_PARAM-1:0]      tgtid;
    logic [3:0]                           qos;
} chie_rsp_s;

// --- SNP Channel ---
typedef struct packed {
    logic                                 valid;
    logic                                 tracetag;
    logic [1:0]                           tagop;
    logic                                 do_not_goto_sd;
    logic                                 ret_to_src;
    logic [11:0]                          fwdtxnid;
    logic [CHIE_NID_WIDTH_PARAM-1:0]      fwdnid;
    logic                                 ns;
    logic [CHIE_SNP_ADDR_WIDTH_PARAM-1:0] addr;
    logic [4:0]                           opcode;
    logic [11:0]                          txnid;
    logic [CHIE_NID_WIDTH_PARAM-1:0]      srcid;
    logic [CHIE_NID_WIDTH_PARAM-1:0]      tgtid;
    logic [3:0]                           qos;
} chie_snp_s;

function automatic chie_req_s parse_req_flit(
        input logic [`CHIE_REQ_FLIT_RANGE] f, input logic valid);
    chie_req_s s;
    s = '0;
    s.valid           = valid;
    s.qos             = f[`CHIE_REQ_FLIT_QOS_RANGE];
    s.tgtid           = f[`CHIE_REQ_FLIT_TGTID_RANGE];
    s.srcid           = f[`CHIE_REQ_FLIT_SRCID_RANGE];
    s.txnid           = f[`CHIE_REQ_FLIT_TXNID_RANGE];
    s.return_stsh_nid = f[`CHIE_REQ_FLIT_RETURNNID_RANGE];
    s.returntxnid     = f[`CHIE_REQ_FLIT_RETURNTXNID_RANGE];
    s.opcode          = f[`CHIE_REQ_FLIT_OPCODE_RANGE];
    s.size            = f[`CHIE_REQ_FLIT_SIZE_RANGE];
    s.addr            = f[`CHIE_REQ_FLIT_ADDR_RANGE];
    s.ns              = f[`CHIE_REQ_FLIT_NS_RANGE];
    s.likelyshared    = f[`CHIE_REQ_FLIT_LIKELYSHARED_RANGE];
    s.allowretry      = f[`CHIE_REQ_FLIT_ALLOWRETRY_RANGE];
    s.order           = f[`CHIE_REQ_FLIT_ORDER_RANGE];
    s.pcrdtype        = f[`CHIE_REQ_FLIT_PCRDTYPE_RANGE];
    s.memattr         = f[`CHIE_REQ_FLIT_MEMATTR_RANGE];
    s.expcompack      = f[`CHIE_REQ_FLIT_EXPCOMPACK_RANGE];
    s.tracetag        = f[`CHIE_REQ_FLIT_TRACETAG_RANGE];
    return s;
endfunction

function automatic chie_dat_s parse_dat_flit(
        input logic [`CHIE_DAT_FLIT_RANGE] f, input logic valid);
    chie_dat_s s;
    s = '0;
    s.valid    = valid;
    s.qos      = f[`CHIE_DAT_FLIT_QOS_RANGE];
    s.tgtid    = f[`CHIE_DAT_FLIT_TGTID_RANGE];
    s.srcid    = f[`CHIE_DAT_FLIT_SRCID_RANGE];
    s.txnid    = f[`CHIE_DAT_FLIT_TXNID_RANGE];
    s.homenid  = f[`CHIE_DAT_FLIT_HOMENID_RANGE];
    s.opcode   = f[`CHIE_DAT_FLIT_OPCODE_RANGE];
    s.resperr  = f[`CHIE_DAT_FLIT_RESPERR_RANGE];
    s.resp     = f[`CHIE_DAT_FLIT_RESP_RANGE];
    s.dbid     = f[`CHIE_DAT_FLIT_DBID_RANGE];
    s.ccid     = f[`CHIE_DAT_FLIT_CCID_RANGE];
    s.dataid   = f[`CHIE_DAT_FLIT_DATAID_RANGE];
    s.tracetag = f[`CHIE_DAT_FLIT_TRACETAG_RANGE];
    s.be       = f[`CHIE_DAT_FLIT_BE_RANGE];
    s.data     = f[`CHIE_DAT_FLIT_DATA_RANGE];
    return s;
endfunction

function automatic chie_rsp_s parse_rsp_flit(
        input logic [`CHIE_RSP_FLIT_RANGE] f, input logic valid);
    chie_rsp_s s;
    s = '0;
    s.valid    = valid;
    s.qos      = f[`CHIE_RSP_FLIT_QOS_RANGE];
    s.tgtid    = f[`CHIE_RSP_FLIT_TGTID_RANGE];
    s.srcid    = f[`CHIE_RSP_FLIT_SRCID_RANGE];
    s.txnid    = f[`CHIE_RSP_FLIT_TXNID_RANGE];
    s.opcode   = f[`CHIE_RSP_FLIT_OPCODE_RANGE];
    s.resperr  = f[`CHIE_RSP_FLIT_RESPERR_RANGE];
    s.resp     = f[`CHIE_RSP_FLIT_RESP_RANGE];
    s.dbid     = f[`CHIE_RSP_FLIT_DBID_RANGE];
    s.pcrdtype = f[`CHIE_RSP_FLIT_PCRDTYPE_RANGE];
    s.tracetag = f[`CHIE_RSP_FLIT_TRACETAG_RANGE];
    return s;
endfunction

function automatic chie_snp_s parse_snp_flit(
        input logic [`CHIE_SNP_FLIT_RANGE] f, input logic valid);
    chie_snp_s s;
    s = '0;
    s.valid          = valid;
    s.qos            = f[`CHIE_SNP_FLIT_QOS_RANGE];
    s.tgtid          = f[`CHIE_SNP_FLIT_TGTID_RANGE];
    s.srcid          = f[`CHIE_SNP_FLIT_SRCID_RANGE];
    s.txnid          = f[`CHIE_SNP_FLIT_TXNID_RANGE];
    s.fwdnid         = f[`CHIE_SNP_FLIT_FWDNID_RANGE];
    s.fwdtxnid       = f[`CHIE_SNP_FLIT_FWDTXNID_RANGE];
    s.opcode         = f[`CHIE_SNP_FLIT_OPCODE_RANGE];
    s.addr           = f[`CHIE_SNP_FLIT_ADDR_RANGE];
    s.ns             = f[`CHIE_SNP_FLIT_NS_RANGE];
    s.do_not_goto_sd = f[`CHIE_SNP_FLIT_DONOTGOTOSD_RANGE];
    s.ret_to_src     = f[`CHIE_SNP_FLIT_RETTOSRC_RANGE];
    s.tracetag       = f[`CHIE_SNP_FLIT_TRACETAG_RANGE];
    return s;
endfunction
