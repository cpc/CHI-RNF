
// Original work: 
/*
Copyright (c) 2015 Princeton University
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:
    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of Princeton University nor the
      names of its contributors may be used to endorse or promote products
      derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY PRINCETON UNIVERSITY "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL PRINCETON UNIVERSITY BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/


// Modifications: 
/*
 * Copyright (c) 2026 Tampere University
 * Licensed under the Solderpad Hardware License v 2.1, see LICENSE for details.
 * SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
 */

//==================================================================================================
//  Filename        : rnf_cache (original l15)
//  Original Author : Tri Nguyen, trin@princeton.edu, Princeton University
//  Modified        : Teemu Rinne, Tampere University
//
//  Description     : AMBA CHI based RN-F coherent cache
//
//==================================================================================================



`include "l15.tmp.h"
`include "rnf_param.v"
`include "rnf_defines.v"
`include "chie_defines.v"

`ifdef DEFAULT_NETTYPE_NONE
`default_nettype none
`endif
module rnf_cache `RNF_PARAM (
    input                                   clk,
    input                                   rst_n,
    
    input [4:0]                             transducer_l15_rqtype,
    input [`L15_AMO_OP_WIDTH-1:0]           transducer_l15_amo_op,
    input                                   transducer_l15_nc,
    input [2:0]                             transducer_l15_size,
    input [`L15_THREADID_MASK]              transducer_l15_threadid,
    input                                   transducer_l15_prefetch,
    input                                   transducer_l15_invalidate_cacheline,
    input                                   transducer_l15_blockstore,
    input                                   transducer_l15_blockinitstore,
    input [`L1D_WAY_MASK]                   transducer_l15_l1rplway,
    input                                   transducer_l15_val,
    input [39:0]                            transducer_l15_address,
    input [63:0]                            transducer_l15_data,
    input [63:0]                            transducer_l15_data_next_entry,
    input [`TLB_CSM_WIDTH-1:0]              transducer_l15_csm_data,

    output                                  l15_transducer_ack,
    output                                  l15_transducer_header_ack,

    output                                  l15_transducer_val,
    output [3:0]                            l15_transducer_returntype,
    output                                  l15_transducer_l2miss,
    output [1:0]                            l15_transducer_error,
    output                                  l15_transducer_noncacheable,
    output                                  l15_transducer_atomic,
    output [`L15_THREADID_MASK]             l15_transducer_threadid,
    output                                  l15_transducer_prefetch,
    output                                  l15_transducer_f4b,
    output [63:0]                           l15_transducer_data_0,
    output [63:0]                           l15_transducer_data_1,
    output [63:0]                           l15_transducer_data_2,
    output [63:0]                           l15_transducer_data_3,
    output                                  l15_transducer_inval_icache_all_way,
    output                                  l15_transducer_inval_dcache_all_way,
    output [15:4]                           l15_transducer_inval_address_15_4,
    output                                  l15_transducer_cross_invalidate,
    output [`L1D_WAY_MASK]                  l15_transducer_cross_invalidate_way,
    output                                  l15_transducer_inval_dcache_inval,
    output                                  l15_transducer_inval_icache_inval,
    output [`L1D_WAY_MASK]                  l15_transducer_inval_way,
    output                                  l15_transducer_blockinitstore,

    input                                   transducer_l15_req_ack,


    // sram interface
    output [`SRAM_WRAPPER_BUS_WIDTH-1:0]    srams_rtap_data,
    input  [`BIST_OP_WIDTH-1:0]             rtap_srams_bist_command,
    input  [`SRAM_WRAPPER_BUS_WIDTH-1:0]    rtap_srams_bist_data,



    // CHI interface

    // INPUTS
    // from response channel
    input RXRSPFLITV,
    input [`CHIE_RSP_FLIT_RANGE] RXRSPFLIT,
    input RXRSPFLITPEND,
    // from data channel
    input RXDATFLITV,
    input [`CHIE_DAT_FLIT_RANGE] RXDATFLIT,
    input RXDATFLITPEND,
    // to snoop channel
    input RXSNPFLITV,
    input [`CHIE_SNP_FLIT_RANGE] RXSNPFLIT,
    input RXSNPFLITPEND,

    input TXREQLCRDV,
    input TXRSPLCRDV,
    input TXDATLCRDV,

    // OUTPUTS
    // Credits to requestor
    output RXRSPLCRDV,
    output RXDATLCRDV,
    output RXSNPLCRDV,
    // to request channel
    output TXREQFLITV,
    output [`CHIE_REQ_FLIT_RANGE] TXREQFLIT,
    output TXREQFLITPEND,
    // response channel
    output TXRSPFLITV,
    output [`CHIE_RSP_FLIT_RANGE] TXRSPFLIT,
    output TXRSPFLITPEND,
    // to data channel
    output TXDATFLITV,
    output [`CHIE_DAT_FLIT_RANGE] TXDATFLIT,
    output TXDATFLITPEND,


    output  TXLINKACTIVEREQ,
    input   TXLINKACTIVEACK,
    input   RXLINKACTIVEREQ,
    output  RXLINKACTIVEACK,
    output  TXACTIVE,
    input   RXACTIVE

);

// assigning sram return data
wire [`SRAM_WRAPPER_BUS_WIDTH-1:0] dtag_rtap_data;
wire [`SRAM_WRAPPER_BUS_WIDTH-1:0] dcache_rtap_data;

`ifndef NO_RTL_CSM
wire [`SRAM_WRAPPER_BUS_WIDTH-1:0] hmt_rtap_data;
assign srams_rtap_data = dtag_rtap_data
                            | dcache_rtap_data
                            | hmt_rtap_data;
`else
assign srams_rtap_data = dtag_rtap_data
                            | dcache_rtap_data;
`endif

wire [`PHY_ADDR_WIDTH-1:0] l15_csm_req_address_s2;
wire l15_csm_req_val_s2;
wire l15_csm_stall_s3;
wire [`L15_CSM_NUM_TICKETS_LOG2-1:0] l15_csm_req_ticket_s2;
// wire [`HOME_ID_WIDTH-1:0] l15_csm_clump_tile_count_s2;
wire  l15_csm_req_type_s2;
wire [127:0] l15_csm_req_data_s2;
wire  [`TLB_CSM_WIDTH-1:0] l15_csm_req_pcx_data_s2;
wire csm_l15_res_val_s3;
wire [63:0] csm_l15_res_data_s3;

// read port in case of a cache miss
wire [`L15_CSM_NUM_TICKETS_LOG2-1:0] l15_csm_read_ticket;
wire [`L15_CSM_NUM_TICKETS_LOG2-1:0] l15_csm_clear_ticket;
wire l15_csm_clear_ticket_val;
wire [`PACKET_HOME_ID_WIDTH-1:0] csm_l15_read_res_data;
wire csm_l15_read_res_val;

// with noc1
wire noc1encoder_csm_req_ack;
wire csm_noc1encoder_req_val;
wire [`L15_NOC1_REQTYPE_WIDTH-1:0] csm_noc1encoder_req_type;
wire [`L15_CSM_NUM_TICKETS_LOG2-1:0] csm_noc1encoder_req_mshrid;
wire [`PHY_ADDR_WIDTH-1:0] csm_noc1encoder_req_address;
wire csm_noc1encoder_req_non_cacheable;
wire  [`PCX_SIZE_WIDTH-1:0] csm_noc1encoder_req_size;


// OpenPiton CSM wires tied to zero
assign csm_l15_read_res_data = 0;
assign csm_l15_read_res_val = 0;
assign csm_l15_res_val_s3 = 0;
assign csm_l15_res_data_s3 = 0;
assign csm_noc1encoder_req_val = 0;
assign csm_noc1encoder_req_type = 0;
assign csm_noc1encoder_req_mshrid = 0;
assign csm_noc1encoder_req_address = 0;
assign csm_noc1encoder_req_non_cacheable = 0;
assign csm_noc1encoder_req_size = 0;


// Widened to 576b: bits [63:0] carry the OP message-info word, bits [575:64]
// carry the full 512b cacheline delivered by rx_control to noc2decoder.
wire [575:0] noc2_data;
wire noc2_data_val;
// Full-width CHI txnid of the snoop carried by noc2_data, forwarded separately
// (see rx_control.rxctrl_l15_txnid) all the way to response_encoder.
wire [`CHIE_SNP_FLIT_TXNID_WIDTH-1:0] rxctrl_l15_txnid;
wire noc2_data_ack;



wire [`CHIE_DAT_FLIT_HOMENID_WIDTH-1:0]    li_decoder_rxdat_homenid;
wire [`CHIE_DAT_FLIT_CCID_WIDTH-1:0]       li_decoder_rxdat_ccid;
wire [`CHIE_DAT_FLIT_DBID_WIDTH-1:0]       li_decoder_rxdat_dbid;
wire                                       rxdat_buf_ready;

wire                                       li_mshr_rxdat_valid_s0;
wire [`CHIE_DAT_FLIT_TXNID_WIDTH-1:0]      li_mshr_rxdat_txnid_s0;
wire [`CHIE_DAT_FLIT_OPCODE_WIDTH-1:0]     li_mshr_rxdat_opcode_s0;
wire [`CHIE_DAT_FLIT_RESP_WIDTH-1:0]       li_mshr_rxdat_resp_s0;
wire [`CHIE_DAT_FLIT_FWDSTATE_WIDTH-1:0]   li_mshr_rxdat_fwdstate_s0;
wire [`CHIE_DAT_FLIT_DATAID_WIDTH-1:0]     li_mshr_rxdat_dataid_s0;
wire                                       li_dbf_rxdat_valid_s0;
wire [`CHIE_DAT_FLIT_TXNID_WIDTH-1:0]      li_dbf_rxdat_txnid_s0;
wire [`CHIE_DAT_FLIT_OPCODE_WIDTH-1:0]     li_dbf_rxdat_opcode_s0;
wire [`CHIE_DAT_FLIT_DATAID_WIDTH-1:0]     li_dbf_rxdat_dataid_s0;
wire [`CHIE_DAT_FLIT_BE_WIDTH-1:0]         li_dbf_rxdat_be_s0;
wire [`CHIE_DAT_FLIT_DATA_WIDTH-1:0]       li_dbf_rxdat_data_s0;

wire                                        noc2buffer_txrsp_valid_sx1_q;
wire [`CHIE_RSP_FLIT_QOS_WIDTH-1:0]         noc2buffer_txrsp_qos_sx1;
wire [`CHIE_RSP_FLIT_TGTID_WIDTH-1:0]       noc2buffer_txrsp_tgtid_sx1;
wire [`CHIE_RSP_FLIT_TXNID_WIDTH-1:0]       noc2buffer_txrsp_txnid_sx1_q;
wire [`CHIE_RSP_FLIT_OPCODE_WIDTH-1:0]      noc2buffer_txrsp_opcode_sx1;
wire [`CHIE_RSP_FLIT_RESPERR_WIDTH-1:0]     noc2buffer_txrsp_resperr_sx1;
wire [`CHIE_RSP_FLIT_RESP_WIDTH-1:0]        noc2buffer_txrsp_resp_sx1;
wire [`CHIE_RSP_FLIT_DBID_WIDTH-1:0]        noc2buffer_txrsp_dbid_sx1;
wire [`CHIE_RSP_FLIT_TRACETAG_WIDTH-1:0]    noc2buffer_txrsp_tracetag_sx1;

wire                                        txrsp_cache_crd_avail;
wire                                        txrsp_rxdat_buf_won_sx1;

wire                                        rxsnp_buf_ready;                  

wire                                         rxsnp_decoder_valid_sx;
wire [`CHIE_SNP_FLIT_QOS_WIDTH-1:0]          rxsnp_decoder_qos;
wire [`CHIE_SNP_FLIT_SRCID_WIDTH-1:0]        rxsnp_decoder_srcid;
wire [`CHIE_SNP_FLIT_TXNID_WIDTH-1:0]        rxsnp_decoder_txnid;
wire [`CHIE_SNP_FLIT_FWDNID_WIDTH-1:0]       rxsnp_decoder_fwdnid;
wire [`CHIE_SNP_FLIT_FWDTXNID_WIDTH-1:0]     rxsnp_decoder_fwdtxnid;
wire [`CHIE_SNP_FLIT_OPCODE_WIDTH-1:0]       rxsnp_decoder_opcode;
wire [`CHIE_SNP_FLIT_ADDR_WIDTH-1:0]         rxsnp_decoder_addr;
wire [`CHIE_SNP_FLIT_NS_WIDTH-1:0]           rxsnp_decoder_ns;
wire [`CHIE_SNP_FLIT_DONOTGOTOSD_WIDTH-1:0]  rxsnp_decoder_donotgotosd;
wire [`CHIE_SNP_FLIT_RETTOSRC_WIDTH-1:0]     rxsnp_decoder_rettosrc;
wire [`CHIE_SNP_FLIT_TRACETAG_WIDTH-1:0]     rxsnp_decoder_tracetag;

wire                                         rxbuf_txreq_bypass_valid_s1;
wire [`CHIE_REQ_FLIT_QOS_WIDTH-1:0]          rxbuf_txreq_bypass_qos_s1;
wire [`CHIE_REQ_FLIT_TXNID_WIDTH-1:0]        rxbuf_txreq_bypass_txnid_s1;
wire [`CHIE_REQ_FLIT_RETURNNID_WIDTH-1:0]    rxbuf_txreq_bypass_returnnid_s1;
wire [`CHIE_REQ_FLIT_RETURNTXNID_WIDTH-1:0]  rxbuf_txreq_bypass_returntxnid_s1;
wire [`CHIE_REQ_FLIT_OPCODE_WIDTH-1:0]       rxbuf_txreq_bypass_opcode_s1;
wire [`CHIE_REQ_FLIT_SIZE_WIDTH-1:0]         rxbuf_txreq_bypass_size_s1;
wire [`CHIE_REQ_FLIT_ADDR_WIDTH-1:0]         rxbuf_txreq_bypass_addr_s1;
wire [`CHIE_REQ_FLIT_NS_WIDTH-1:0]           rxbuf_txreq_bypass_ns_s1;
wire [`CHIE_REQ_FLIT_ALLOWRETRY_WIDTH-1:0]   rxbuf_txreq_bypass_allowretry_s1;
wire [`CHIE_REQ_FLIT_ORDER_WIDTH-1:0]        rxbuf_txreq_bypass_order_s1;
wire [`CHIE_REQ_FLIT_PCRDTYPE_WIDTH-1:0]     rxbuf_txreq_bypass_pcrdtype_s1;
wire [`CHIE_REQ_FLIT_MEMATTR_WIDTH-1:0]      rxbuf_txreq_bypass_memattr_s1;
wire [`CHIE_REQ_FLIT_DODWT_WIDTH-1:0]        rxbuf_txreq_bypass_dodwt_s1;
wire [`CHIE_REQ_FLIT_TRACETAG_WIDTH-1:0]     rxbuf_txreq_bypass_tracetag_s1;
wire [`CHIE_REQ_FLIT_TGTID_WIDTH-1:0]        rxbuf_txreq_bypass_tgtid;
wire [`CHIE_REQ_FLIT_SRCID_WIDTH-1:0]        rxbuf_txreq_bypass_srcid;
wire [`CHIE_REQ_FLIT_LIKELYSHARED_WIDTH-1:0] rxbuf_txreq_bypass_likelyshared;
wire [`CHIE_REQ_FLIT_EXCL_WIDTH-1:0]         rxbuf_txreq_bypass_exclusive;
wire [`CHIE_REQ_FLIT_ENDIAN_WIDTH-1:0]       txreq_bypass_endian;
wire [`CHIE_REQ_FLIT_LPID_WIDTH-1:0]         txreq_bypass_lpid;
wire [`CHIE_REQ_FLIT_EXPCOMPACK_WIDTH-1:0]   txreq_bypass_expcompack;
wire                                         txreq_rxbuf_bypass_won_s1;

wire                                         li_rxbuf_rxrsp_valid_s0;
wire [`CHIE_RSP_FLIT_SRCID_WIDTH-1:0]        li_rxbuf_rxrsp_srcid_s0;
wire [`CHIE_RSP_FLIT_TXNID_WIDTH-1:0]        li_rxbuf_rxrsp_txnid_s0;
wire [`CHIE_RSP_FLIT_OPCODE_WIDTH-1:0]       li_rxbuf_rxrsp_opcode_s0;
wire [`CHIE_RSP_FLIT_RESP_WIDTH-1:0]         li_rxbuf_rxrsp_resp_s0;
wire [`CHIE_RSP_FLIT_FWDSTATE_WIDTH-1:0]     li_rxbuf_rxrsp_fwdstate_s0;
wire [`CHIE_RSP_FLIT_DBID_WIDTH-1:0]         li_rxbuf_rxrsp_dbid_s0;
wire [`CHIE_RSP_FLIT_PCRDTYPE_WIDTH-1:0]     li_rxbuf_rxrsp_pcrdtype_s0;
wire                                         rxrsp_buf_ready;

wire                                         rxbuf_rspenc_txdat_valid;
wire [`CHIE_DAT_FLIT_QOS_WIDTH-1:0]          rxbuf_rspenc_txdat_qos;
wire [`CHIE_DAT_FLIT_SRCID_WIDTH-1:0]        rxbuf_rspenc_txdat_srcid;
wire [`CHIE_DAT_FLIT_TXNID_WIDTH-1:0]        rxbuf_rspenc_txdat_txnid;
wire [`CHIE_DAT_FLIT_OPCODE_WIDTH-1:0]       rxbuf_rspenc_txdat_opcode;
wire [`CHIE_DAT_FLIT_RESP_WIDTH-1:0]         rxbuf_rspenc_txdat_resp;
wire [`CHIE_DAT_FLIT_RESPERR_WIDTH-1:0]      rxbuf_rspenc_txdat_resperr;
wire [`CHIE_DAT_FLIT_FWDSTATE_WIDTH-1:0]     rxbuf_rspenc_txdat_fwdstate;
wire [`CHIE_DAT_FLIT_DATAID_WIDTH-1:0]       rxbuf_rspenc_txdat_dataid;
wire [`CHIE_DAT_FLIT_HOMENID_WIDTH-1:0]      rxbuf_rspenc_txdat_homenid;
wire [`CHIE_DAT_FLIT_CCID_WIDTH-1:0]         rxbuf_rspenc_txdat_ccid;
wire [`CHIE_DAT_FLIT_TGTID_WIDTH-1:0]        rxbuf_rspenc_txdat_tgtid;
wire [`CHIE_DAT_FLIT_DBID_WIDTH-1:0]         rxbuf_rspenc_txdat_dbid;
wire [`CHI_CACHE_BE_WIDTH-1:0]               rxbuf_rspenc_txdat_be;
wire [`CHI_CACHE_LINE_WIDTH-1:0]             rxbuf_rspenc_txdat_data;
wire                                         rspenc_rxbuf_ack;
wire                                         writeback_pending;



wire [127:0]                                        txreq_enc_rxctrl_atomic_data;
wire                                                mshr_txreq_valid_sx1_q;     //connected
wire                                                txreq_encoder_crd_avail_s1;
// Flit fields from encoder to txreq_wrap
wire [`CHIE_REQ_FLIT_QOS_WIDTH-1:0]                 mshr_txreq_qos_sx1;          
wire [`CHIE_REQ_FLIT_TXNID_WIDTH-1:0]               mshr_txreq_txnid_sx1_q;     //connected
wire [`CHIE_REQ_FLIT_RETURNNID_WIDTH-1:0]           mshr_txreq_returnnid_sx1;       // not needed when sending req
wire [`CHIE_REQ_FLIT_RETURNTXNID_WIDTH-1:0]         mshr_txreq_returntxnid_sx1;     // not needed when sending req
wire [`CHIE_REQ_FLIT_OPCODE_WIDTH-1:0]              mshr_txreq_opcode_sx1;      //connected
wire [`CHIE_REQ_FLIT_SIZE_WIDTH-1:0]                mshr_txreq_size_sx1;        //connected
wire [`CHIE_REQ_FLIT_ADDR_WIDTH-1:0]                mshr_txreq_addr_sx1;        //connected
wire [`CHIE_REQ_FLIT_NS_WIDTH-1:0]                  mshr_txreq_ns_sx1;          // need logic, zero
wire [`CHIE_REQ_FLIT_ALLOWRETRY_WIDTH-1:0]          mshr_txreq_allowretry_sx1;  // need logic, zero
wire [`CHIE_REQ_FLIT_ORDER_WIDTH-1:0]               mshr_txreq_order_sx1;       // need logic, zero, for specific chi txs set no non-zero(eg atomics)
wire [`CHIE_REQ_FLIT_PCRDTYPE_WIDTH-1:0]            mshr_txreq_pcrdtype_sx1;        // just zero should be enough
wire [`CHIE_REQ_FLIT_MEMATTR_WIDTH-1:0]             mshr_txreq_memattr_sx1;     // 
wire [`CHIE_REQ_FLIT_DODWT_WIDTH-1:0]               mshr_txreq_dodwt_sx1;           // this is also SnpAttr
wire [`CHIE_REQ_FLIT_TRACETAG_WIDTH-1:0]            mshr_txreq_tracetag_sx1;        // zero should be okay 
wire [`CHIE_REQ_FLIT_TGTID_WIDTH-1:0]               mshr_txreq_tgtid;           // connected
wire [`CHIE_REQ_FLIT_SRCID_WIDTH-1:0]               mshr_txreq_srcid;           // connected
wire [`CHIE_REQ_FLIT_LIKELYSHARED_WIDTH-1:0]        encoder_txreq_likelyshared;
wire [`CHIE_REQ_FLIT_EXCL_WIDTH-1:0]                encoder_txreq_exclusive;
wire [`CHIE_REQ_FLIT_ENDIAN_WIDTH-1:0]              encoder_txreq_endian;
wire [`CHIE_REQ_FLIT_LPID_WIDTH-1:0]                encoder_txreq_lpid;
wire [`CHIE_REQ_FLIT_EXPCOMPACK_WIDTH-1:0]          encoder_txreq_expcompack;
wire                                                encoder_txreq_reg_icache;
wire                                                txreq_enc_won_sx1;
wire                                                receipt_received;
wire                                                requestregister_rdy;

wire                                                rspenc_rxctrl_txreq_valid;
wire [`CHIE_REQ_FLIT_TXNID_WIDTH-1:0]               rspenc_rxctrl_txreq_txnid;
wire [`CHIE_REQ_FLIT_OPCODE_WIDTH-1:0]              rspenc_rxctrl_txreq_opcode;
wire [`CHIE_REQ_FLIT_SIZE_WIDTH-1:0]                rspenc_rxctrl_txreq_size;
wire [`CHIE_REQ_FLIT_ADDR_WIDTH-1:0]                rspenc_rxctrl_txreq_addr;
wire [`CHIE_REQ_FLIT_TGTID_WIDTH-1:0]               rspenc_rxctrl_txreq_tgtid;
wire [`CHIE_REQ_FLIT_SRCID_WIDTH-1:0]               rspenc_rxctrl_txreq_srcid;
wire [`CHIE_REQ_FLIT_DODWT_WIDTH-1:0]               rspenc_rxctrl_txreq_snpattr;
wire [`CHIE_REQ_FLIT_LIKELYSHARED_WIDTH-1:0]        rspenc_rxctrl_txreq_likelyshared;
wire [`CHIE_REQ_FLIT_QOS_WIDTH-1:0]                 rspenc_rxctrl_txreq_qos;
wire [`CHIE_REQ_FLIT_RETURNNID_WIDTH-1:0]           rspenc_rxctrl_txreq_returnnid;
wire [`CHIE_REQ_FLIT_RETURNTXNID_WIDTH-1:0]         rspenc_rxctrl_txreq_returntxnid;
wire [`CHIE_REQ_FLIT_NS_WIDTH-1:0]                  rspenc_rxctrl_txreq_ns;
wire [`CHIE_REQ_FLIT_ALLOWRETRY_WIDTH-1:0]          rspenc_rxctrl_txreq_allowretry;
wire [`CHIE_REQ_FLIT_ORDER_WIDTH-1:0]               rspenc_rxctrl_txreq_order;
wire [`CHIE_REQ_FLIT_PCRDTYPE_WIDTH-1:0]            rspenc_rxctrl_txreq_pcrdtype;
wire [`CHIE_REQ_FLIT_MEMATTR_WIDTH-1:0]             rspenc_rxctrl_txreq_memattr;
wire [`CHIE_REQ_FLIT_TRACETAG_WIDTH-1:0]            rspenc_rxctrl_txreq_tracetag;     
wire [`CHIE_REQ_FLIT_EXCL_WIDTH-1:0]                rspenc_rxctrl_txreq_exclusive;  
wire [`CHIE_REQ_FLIT_ENDIAN_WIDTH-1:0]              rspenc_rxctrl_txreq_endian;
wire [`CHIE_REQ_FLIT_LPID_WIDTH-1:0]                rspenc_rxctrl_txreq_lpid;
wire [`CHIE_REQ_FLIT_EXPCOMPACK_WIDTH-1:0]          rspenc_rxctrl_txreq_expcompack;
wire [`CHI_CACHE_BE_WIDTH-1:0]                      rspenc_rxctrl_txreq_be;     // 512bit BE
wire [`CHI_CACHE_LINE_WIDTH-1:0]                    rspenc_rxctrl_txreq_data;   // 512bit data
wire                                                rspenc_txreq_won;

wire l15_noc2decoder_header_ack;

/////////////////////////////////////////////////////////////////////////////////////////////////////////
// RXDAT to noc2encoder
// translates CHI message to noc2 message
rx_control `RNF_PARAM_INST rx_control(
    .clk(clk),
    .rst_n(rst_n),
    // noc2decoder 
    .msg_ack(noc2_data_ack),
    .msg_header_ack(l15_noc2decoder_header_ack),
    .msg(noc2_data),
    .msg_val(noc2_data_val),
    .rxctrl_l15_txnid(rxctrl_l15_txnid),
    // rxdat_parse
    .li_mshr_rxdat_valid_s0                       (li_mshr_rxdat_valid_s0            ),
    .li_mshr_rxdat_txnid_s0                       (li_mshr_rxdat_txnid_s0            ),
    .li_mshr_rxdat_opcode_s0                      (li_mshr_rxdat_opcode_s0           ),
    .li_mshr_rxdat_resp_s0                        (li_mshr_rxdat_resp_s0             ),
    .li_mshr_rxdat_fwdstate_s0                    (li_mshr_rxdat_fwdstate_s0         ),
    .li_mshr_rxdat_dataid_s0                      (li_mshr_rxdat_dataid_s0           ),
    .li_decoder_rxdat_homenid                     (li_decoder_rxdat_homenid),        // added for RNF
    .li_decoder_rxdat_ccid                        (li_decoder_rxdat_ccid),           // added for RNF
    .li_decoder_rxdat_dbid                        (li_decoder_rxdat_dbid),           // added for RNF
    .li_dbf_rxdat_valid_s0                        (li_dbf_rxdat_valid_s0             ),
    .li_dbf_rxdat_txnid_s0                        (li_dbf_rxdat_txnid_s0             ),
    .li_dbf_rxdat_opcode_s0                       (li_dbf_rxdat_opcode_s0            ),
    .li_dbf_rxdat_dataid_s0                       (li_dbf_rxdat_dataid_s0            ),
    .li_dbf_rxdat_be_s0                           (li_dbf_rxdat_be_s0                ),
    .li_dbf_rxdat_data_s0                         (li_dbf_rxdat_data_s0              ),
    .rxdat_buf_ready                               (rxdat_buf_ready),
    // txrsp
    .noc2buffer_txrsp_valid_sx1_q                 (noc2buffer_txrsp_valid_sx1_q            ),
    .noc2buffer_txrsp_qos_sx1                     (noc2buffer_txrsp_qos_sx1                ),
    .noc2buffer_txrsp_tgtid_sx1                   (noc2buffer_txrsp_tgtid_sx1              ),
    .noc2buffer_txrsp_txnid_sx1_q                 (noc2buffer_txrsp_txnid_sx1_q            ),
    .noc2buffer_txrsp_opcode_sx1                  (noc2buffer_txrsp_opcode_sx1             ),
    .noc2buffer_txrsp_resperr_sx1                 (noc2buffer_txrsp_resperr_sx1            ),
    .noc2buffer_txrsp_resp_sx1                    (noc2buffer_txrsp_resp_sx1               ),
    .noc2buffer_txrsp_dbid_sx1                    (noc2buffer_txrsp_dbid_sx1               ),
    .noc2buffer_txrsp_tracetag_sx1                (noc2buffer_txrsp_tracetag_sx1           ),
    .txrsp_cache_crd_avail                        (txrsp_cache_crd_avail                   ),
    .txrsp_rxdat_buf_won_sx1                      (txrsp_rxdat_buf_won_sx1                 ),
    // RXSNP
    .rxsnp_decoder_valid_sx                         (rxsnp_decoder_valid_sx             ),
    .rxsnp_decoder_qos                              (rxsnp_decoder_qos                  ),
    .rxsnp_decoder_srcid                            (rxsnp_decoder_srcid                ),
    .rxsnp_decoder_txnid                            (rxsnp_decoder_txnid                ),
    .rxsnp_decoder_fwdnid                           (rxsnp_decoder_fwdnid               ),
    .rxsnp_decoder_fwdtxnid                         (rxsnp_decoder_fwdtxnid             ),
    .rxsnp_decoder_opcode                           (rxsnp_decoder_opcode               ),
    .rxsnp_decoder_addr                             (rxsnp_decoder_addr                 ),
    .rxsnp_decoder_ns                               (rxsnp_decoder_ns                   ),
    .rxsnp_decoder_donotgotosd                      (rxsnp_decoder_donotgotosd          ),
    .rxsnp_decoder_rettosrc                         (rxsnp_decoder_rettosrc             ),
    .rxsnp_decoder_tracetag                         (rxsnp_decoder_tracetag             ),
    .rxsnp_buf_ready                                 (rxsnp_buf_ready                     ),
    // TXREQ bypass
    .rxbuf_txreq_bypass_valid                          (rxbuf_txreq_bypass_valid_s1            ),
    .rxbuf_txreq_bypass_qos                            (rxbuf_txreq_bypass_qos_s1              ),
    .rxbuf_txreq_bypass_txnid                          (rxbuf_txreq_bypass_txnid_s1            ),
    .rxbuf_txreq_bypass_returnnid                      (rxbuf_txreq_bypass_returnnid_s1        ),
    .rxbuf_txreq_bypass_returntxnid                    (rxbuf_txreq_bypass_returntxnid_s1      ),
    .rxbuf_txreq_bypass_opcode                         (rxbuf_txreq_bypass_opcode_s1           ),
    .rxbuf_txreq_bypass_size                           (rxbuf_txreq_bypass_size_s1             ),
    .rxbuf_txreq_bypass_addr                           (rxbuf_txreq_bypass_addr_s1             ),
    .rxbuf_txreq_bypass_ns                             (rxbuf_txreq_bypass_ns_s1               ),
    .rxbuf_txreq_bypass_allowretry                     (rxbuf_txreq_bypass_allowretry_s1       ),
    .rxbuf_txreq_bypass_order                          (rxbuf_txreq_bypass_order_s1            ),
    .rxbuf_txreq_bypass_pcrdtype                       (rxbuf_txreq_bypass_pcrdtype_s1         ),
    .rxbuf_txreq_bypass_memattr                        (rxbuf_txreq_bypass_memattr_s1          ),
    .rxbuf_txreq_bypass_dodwt                          (rxbuf_txreq_bypass_dodwt_s1            ),
    .rxbuf_txreq_bypass_tracetag                       (rxbuf_txreq_bypass_tracetag_s1         ),
    .rxbuf_txreq_bypass_tgtid                          (rxbuf_txreq_bypass_tgtid            ),
    .rxbuf_txreq_bypass_srcid                          (rxbuf_txreq_bypass_srcid            ),
    .rxbuf_txreq_bypass_likelyshared                   (rxbuf_txreq_bypass_likelyshared          ),
    .rxbuf_txreq_bypass_exclusive                      (rxbuf_txreq_bypass_exclusive             ),
    .rxbuf_txreq_bypass_endian                           (txreq_bypass_endian           ),
    .rxbuf_txreq_bypass_lpid                             (txreq_bypass_lpid             ),
    .rxbuf_txreq_bypass_expcompack                       (txreq_bypass_expcompack       ),
    .txreq_rxbuf_bypass_won                            (txreq_rxbuf_bypass_won_s1              ),
    // RXRSP
    .li_rxbuf_rxrsp_valid_s0                            (li_rxbuf_rxrsp_valid_s0                 ),
    .li_rxbuf_rxrsp_srcid_s0                            (li_rxbuf_rxrsp_srcid_s0                 ),
    .li_rxbuf_rxrsp_txnid_s0                            (li_rxbuf_rxrsp_txnid_s0                 ),
    .li_rxbuf_rxrsp_opcode_s0                           (li_rxbuf_rxrsp_opcode_s0                ),
    .li_rxbuf_rxrsp_resp_s0                             (li_rxbuf_rxrsp_resp_s0                  ),
    .li_rxbuf_rxrsp_fwdstate_s0                         (li_rxbuf_rxrsp_fwdstate_s0              ),
    .li_rxbuf_rxrsp_dbid_s0                             (li_rxbuf_rxrsp_dbid_s0                  ),
    .li_rxbuf_rxrsp_pcrdtype_s0                         (li_rxbuf_rxrsp_pcrdtype_s0              ),
    .rxrsp_buf_ready                                     (rxrsp_buf_ready                          ),
    // TXDAT to response_encoder
    .rxbuf_rspenc_txdat_valid                           (rxbuf_rspenc_txdat_valid                      ),
    .rxbuf_rspenc_txdat_qos                             (rxbuf_rspenc_txdat_qos                         ),
    .rxbuf_rspenc_txdat_srcid                           (rxbuf_rspenc_txdat_srcid                           ),
    .rxbuf_rspenc_txdat_txnid                           (rxbuf_rspenc_txdat_txnid                      ),
    .rxbuf_rspenc_txdat_opcode                          (rxbuf_rspenc_txdat_opcode                     ),    
    .rxbuf_rspenc_txdat_resp                            (rxbuf_rspenc_txdat_resp                       ),
    .rxbuf_rspenc_txdat_resperr                         (rxbuf_rspenc_txdat_resperr                          ),
    .rxbuf_rspenc_txdat_fwdstate                        (rxbuf_rspenc_txdat_fwdstate                   ),    
    .rxbuf_rspenc_txdat_dataid                          (rxbuf_rspenc_txdat_dataid                     ),    
    .rxbuf_rspenc_txdat_homenid                         (rxbuf_rspenc_txdat_homenid                    ),    
    .rxbuf_rspenc_txdat_ccid                            (rxbuf_rspenc_txdat_ccid                       ),
    .rxbuf_rspenc_txdat_tgtid                           (rxbuf_rspenc_txdat_tgtid                            ),
    .rxbuf_rspenc_txdat_dbid                            (rxbuf_rspenc_txdat_dbid                       ),
    .rxbuf_rspenc_txdat_be                              (rxbuf_rspenc_txdat_be                         ),
    .rxbuf_rspenc_txdat_data                            (rxbuf_rspenc_txdat_data                       ),
    .rspenc_rxbuf_ack                                   (rspenc_rxbuf_ack                              ),
    // from txreq_encoder
    .atomic_data                                        (txreq_enc_rxctrl_atomic_data),
    .reqenc_txreq_valid                                 (mshr_txreq_valid_sx1_q),
    .reqenc_txreq_txnid                                 (mshr_txreq_txnid_sx1_q),
    .reqenc_txreq_opcode                                (mshr_txreq_opcode_sx1),
    .reqenc_txreq_size                                  (mshr_txreq_size_sx1),
    .reqenc_txreq_addr                                  (mshr_txreq_addr_sx1),
    .reqenc_txreq_tgtid                                 (mshr_txreq_tgtid),
    .reqenc_txreq_srcid                                 (mshr_txreq_srcid),
    .reqenc_txreq_snpattr                               (mshr_txreq_dodwt_sx1),                         // used as SnpAttr here
    .reqenc_txreq_likelyshared                          (encoder_txreq_likelyshared),                    // 
    .reqenc_txreq_exclusive                             (encoder_txreq_exclusive),
    .reqenc_txreq_qos                                   (mshr_txreq_qos_sx1),
    .reqenc_txreq_returnnid                             (mshr_txreq_returnnid_sx1),
    .reqenc_txreq_returntxnid                           (mshr_txreq_returntxnid_sx1),
    .reqenc_txreq_ns                                    (mshr_txreq_ns_sx1),         
    .reqenc_txreq_allowretry                            (mshr_txreq_allowretry_sx1),
    .reqenc_txreq_order                                 (mshr_txreq_order_sx1),
    .reqenc_txreq_pcrdtype                              (mshr_txreq_pcrdtype_sx1),
    .reqenc_txreq_memattr                               (mshr_txreq_memattr_sx1),
    .reqenc_txreq_tracetag                              (mshr_txreq_tracetag_sx1),
    .reqenc_txreq_endian                                (encoder_txreq_endian           ),
    .reqenc_txreq_lpid                                  (encoder_txreq_lpid             ),
    .reqenc_txreq_expcompack                            (encoder_txreq_expcompack       ),
    .reqenc_txreq_reg_icache                            (encoder_txreq_reg_icache),
    .receipt_received                                   (receipt_received),
    .requestregister_rdy                                (requestregister_rdy),
    .txreq_enc_won                                      (txreq_enc_won_sx1),
    .writeback_pending                                  (writeback_pending),
    .rspenc_rxctrl_txreq_valid                          (rspenc_rxctrl_txreq_valid),                            
    .rspenc_rxctrl_txreq_txnid                          (rspenc_rxctrl_txreq_txnid),                  
    .rspenc_rxctrl_txreq_opcode                         (rspenc_rxctrl_txreq_opcode),                  
    .rspenc_rxctrl_txreq_size                           (rspenc_rxctrl_txreq_size),                  
    .rspenc_rxctrl_txreq_addr                           (rspenc_rxctrl_txreq_addr),                  
    .rspenc_rxctrl_txreq_tgtid                          (rspenc_rxctrl_txreq_tgtid),                  
    .rspenc_rxctrl_txreq_srcid                          (rspenc_rxctrl_txreq_srcid),                  
    .rspenc_rxctrl_txreq_snpattr                        (rspenc_rxctrl_txreq_snpattr),                      
    .rspenc_rxctrl_txreq_likelyshared                   (rspenc_rxctrl_txreq_likelyshared),                          
    .rspenc_rxctrl_txreq_qos                            (rspenc_rxctrl_txreq_qos),                  
    .rspenc_rxctrl_txreq_returnnid                      (rspenc_rxctrl_txreq_returnnid),                      
    .rspenc_rxctrl_txreq_returntxnid                    (rspenc_rxctrl_txreq_returntxnid),                          
    .rspenc_rxctrl_txreq_ns                             (rspenc_rxctrl_txreq_ns),              
    .rspenc_rxctrl_txreq_allowretry                     (rspenc_rxctrl_txreq_allowretry),                      
    .rspenc_rxctrl_txreq_order                          (rspenc_rxctrl_txreq_order),                  
    .rspenc_rxctrl_txreq_pcrdtype                       (rspenc_rxctrl_txreq_pcrdtype),                      
    .rspenc_rxctrl_txreq_memattr                        (rspenc_rxctrl_txreq_memattr),                      
    .rspenc_rxctrl_txreq_tracetag                       (rspenc_rxctrl_txreq_tracetag),       
    .rspenc_rxctrl_txreq_exclusive                      (rspenc_rxctrl_txreq_exclusive),     
    .rspenc_rxctrl_txreq_endian                         (rspenc_rxctrl_txreq_endian),
    .rspenc_rxctrl_txreq_lpid                           (rspenc_rxctrl_txreq_lpid),
    .rspenc_rxctrl_txreq_expcompack                     (rspenc_rxctrl_txreq_expcompack),       
    .rspenc_rxctrl_txreq_be                             (rspenc_rxctrl_txreq_be), 
    .rspenc_rxctrl_txreq_data                           (rspenc_rxctrl_txreq_data),    
    .rspenc_txreq_won                                   (rspenc_txreq_won)
);



wire l15_noc2decoder_ack;
wire noc2decoder_l15_val;
wire [`L15_MSHR_ID_WIDTH-1:0] noc2decoder_l15_mshrid;
wire noc2decoder_l15_l2miss;
wire noc2decoder_l15_icache_type;
wire noc2decoder_l15_f4b;
wire [`MSG_TYPE_WIDTH-1:0] noc2decoder_l15_reqtype;
wire [`L15_MESI_STATE_WIDTH-1:0] noc2decoder_l15_ack_state;
// Single 512b NOC2 data aggregate consumed by the modified 64B L15 pipeline,
// replacing the previous 4x64b partial delivery (data_0..3).
wire [511:0] noc2decoder_l15_data;
wire [`L15_PADDR_HI:0] noc2decoder_l15_address;
wire [3:0] noc2decoder_l15_fwd_subcacheline_vector;
wire [`PACKET_HOME_ID_WIDTH-1:0] noc2decoder_l15_src_homeid;

wire [`L15_CSM_NUM_TICKETS_LOG2-1:0] noc2decoder_l15_csm_mshrid;
wire [`L15_THREADID_MASK] noc2decoder_l15_threadid;
wire noc2decoder_l15_hmc_fill;
wire [`CHIE_SNP_FLIT_TXNID_WIDTH-1:0] noc2decoder_l15_txnid;


/////////////////////////////////////////////////////////////////////////////////////////////////////////
// NOC2 DECODER
/////////////////////////////////////////////////////////////////////////////////////////////////////////
/*
    noc2decoder takes the data from the buffer and decode it to meaningful signals
    to the l15
*/
rx_decoder rx_decoder(
    .clk(clk),
    .rst_n(rst_n),
    .noc2_data(noc2_data),
    .noc2_data_val(noc2_data_val),
    .rxctrl_l15_txnid(rxctrl_l15_txnid),
    .l15_noc2decoder_ack(l15_noc2decoder_ack),
    .l15_noc2decoder_header_ack(l15_noc2decoder_header_ack),
    .noc2_data_ack(noc2_data_ack),
    .noc2decoder_l15_val(noc2decoder_l15_val),
    .noc2decoder_l15_mshrid(noc2decoder_l15_mshrid),
    .noc2decoder_l15_l2miss(noc2decoder_l15_l2miss),
    .noc2decoder_l15_icache_type(noc2decoder_l15_icache_type),
    .noc2decoder_l15_f4b(noc2decoder_l15_f4b),
    .noc2decoder_l15_reqtype(noc2decoder_l15_reqtype),
    .noc2decoder_l15_ack_state(noc2decoder_l15_ack_state),
    // Single 512b NOC2 data port replacing data_0..3.
    .noc2decoder_l15_data(noc2decoder_l15_data),
    .noc2decoder_l15_address(noc2decoder_l15_address),
    .noc2decoder_l15_fwd_subcacheline_vector(noc2decoder_l15_fwd_subcacheline_vector),
    .noc2decoder_l15_src_homeid(noc2decoder_l15_src_homeid),
    .noc2decoder_l15_csm_mshrid(noc2decoder_l15_csm_mshrid),
    .noc2decoder_l15_threadid(noc2decoder_l15_threadid),
    .noc2decoder_l15_hmc_fill(noc2decoder_l15_hmc_fill),
    .noc2decoder_l15_txnid(noc2decoder_l15_txnid)
);

// noc1 signal declarations
wire noc1encoder_l15_req_ack;
wire noc1encoder_l15_req_sent;
wire l15_noc1buffer_req_val;
wire [`NOC1_BUFFER_ACK_DATA_WIDTH-1:0] noc1encoder_l15_req_data_sent;

wire [`L15_NOC1_REQTYPE_WIDTH-1:0] l15_noc1buffer_req_type;
wire [`L15_THREADID_MASK] l15_noc1buffer_req_threadid;
wire [`L15_MSHR_ID_WIDTH-1:0] l15_noc1buffer_req_mshrid;
wire [`L15_PADDR_HI:0] l15_noc1buffer_req_address;
wire l15_noc1buffer_req_non_cacheable;
wire [2:0] l15_noc1buffer_req_size;
wire l15_noc1buffer_req_prefetch;
// wire l15_noc1buffer_req_blkstore;
// wire l15_noc1buffer_req_blkinitstore;
wire [63:0] l15_noc1buffer_req_data_0;
wire [63:0] l15_noc1buffer_req_data_1;
wire [`TLB_CSM_WIDTH-1:0] l15_noc1buffer_req_csm_data;
// csm
wire [`L15_CSM_NUM_TICKETS_LOG2-1:0] l15_noc1buffer_req_csm_ticket;
wire [`PACKET_HOME_ID_WIDTH-1:0] l15_noc1buffer_req_homeid;
wire l15_noc1buffer_req_homeid_val;
wire [`MSG_SDID_WIDTH-1:0] noc1buffer_noc1encoder_req_csm_sdid;
wire [`MSG_LSID_WIDTH-1:0] noc1buffer_noc1encoder_req_csm_lsid;

wire [`L15_NOC1_REQTYPE_WIDTH-1:0] noc1buffer_noc1encoder_req_type;
wire [`L15_THREADID_MASK] noc1buffer_noc1encoder_req_threadid;
wire [`L15_MSHR_ID_WIDTH-1:0] noc1buffer_noc1encoder_req_mshrid;
wire [`L15_PADDR_HI:0] noc1buffer_noc1encoder_req_address;
wire noc1buffer_noc1encoder_req_non_cacheable;
wire [2:0] noc1buffer_noc1encoder_req_size;
wire noc1buffer_noc1encoder_req_prefetch;
// wire noc1buffer_noc1encoder_req_blkstore;
// wire noc1buffer_noc1encoder_req_blkinitstore;
wire [63:0] noc1buffer_noc1encoder_req_data_0;
wire [63:0] noc1buffer_noc1encoder_req_data_1;
wire [`PACKET_HOME_ID_WIDTH-1:0] noc1buffer_noc1encoder_req_homeid;

wire noc1encoder_noc1buffer_req_ack;
wire noc1buffer_noc1encoder_req_val;


// noc3 signal declarations
wire noc3encoder_l15_req_ack;
wire noc3encoder_noc3buffer_req_ack;

wire l15_noc3encoder_req_val;
wire noc3buffer_noc3encoder_req_val;
wire [`L15_NOC3_REQTYPE_WIDTH-1:0] l15_noc3encoder_req_type;
// Single 512b writeback/snoop-data aggregate from the modified 64B L15 pipeline,
// replacing the prior 2x64b sub-block interface.
wire [511:0] l15_noc3encoder_req_data;
wire [`L15_MSHR_ID_WIDTH-1:0] l15_noc3encoder_req_mshrid;
wire [1:0] l15_noc3encoder_req_sequenceid;
wire [`L15_THREADID_MASK] l15_noc3encoder_req_threadid;
wire [`L15_PADDR_HI:0] l15_noc3encoder_req_address;
wire l15_noc3encoder_req_with_data;
wire l15_noc3encoder_req_was_inval;
wire [3:0] l15_noc3encoder_req_fwdack_vector;
wire [`PACKET_HOME_ID_WIDTH-1:0] l15_noc3encoder_req_homeid;
wire [`L15_MESI_STATE_WIDTH-1:0] l15_noc3buffer_req_prev_mesi;
wire [`L15_MESI_STATE_WIDTH-1:0] noc3buffer_rspencoder_req_prev_mesi;
wire [`CHIE_SNP_FLIT_TXNID_WIDTH-1:0] l15_noc3encoder_req_rxsnp_txnid;
wire [`CHIE_SNP_FLIT_TXNID_WIDTH-1:0] noc3buffer_noc3encoder_req_rxsnp_txnid;

wire [`L15_NOC3_REQTYPE_WIDTH-1:0] noc3buffer_noc3encoder_req_type;
// noc3buffer also exposes a single 512b aggregate to the response_encoder.
wire [511:0] noc3buffer_noc3encoder_req_data;
wire [`L15_MSHR_ID_WIDTH-1:0] noc3buffer_noc3encoder_req_mshrid;
wire [1:0] noc3buffer_noc3encoder_req_sequenceid;
wire [`L15_THREADID_MASK] noc3buffer_noc3encoder_req_threadid;
wire [`L15_PADDR_HI:0] noc3buffer_noc3encoder_req_address;
wire noc3buffer_noc3encoder_req_with_data;
wire noc3buffer_noc3encoder_req_was_inval;
wire [3:0] noc3buffer_noc3encoder_req_fwdack_vector;
wire [`PACKET_HOME_ID_WIDTH-1:0] noc3buffer_noc3encoder_req_homeid;



// DTAG
wire l15_dtag_val_s1;
wire l15_dtag_rw_s1;
wire [`L15_CACHE_INDEX_WIDTH-1:0] l15_dtag_index_s1;
wire [`L15_CACHE_TAG_RAW_SRAM_WIDTH-1:0] l15_dtag_write_data_s1;
wire [`L15_CACHE_TAG_RAW_SRAM_WIDTH-1:0] l15_dtag_write_mask_s1;
wire [`L15_CACHE_TAG_RAW_SRAM_WIDTH-1:0] dtag_l15_dout_s2;

/////////////////////////////////////////////////////////////////////////////////////////////////////////
// DTAG, DCACHE
/////////////////////////////////////////////////////////////////////////////////////////////////////////
sram_rnf_tag dtag(
    .MEMCLK(clk),
    .RESET_N(rst_n),
    .CE(l15_dtag_val_s1),
    .A(l15_dtag_index_s1),
    .DIN(l15_dtag_write_data_s1),
    .BW(l15_dtag_write_mask_s1),
    .RDWEN(l15_dtag_rw_s1),
    .DOUT(dtag_l15_dout_s2),
    .BIST_COMMAND(rtap_srams_bist_command),
    .BIST_DIN(rtap_srams_bist_data),
    .BIST_DOUT(dtag_rtap_data),
    .SRAMID(`BIST_ID_L15_DTAG)
);

// DCACHE
wire l15_dcache_val_s2;
wire l15_dcache_rw_s2;
wire [(`L15_CACHE_INDEX_WIDTH+`L15_WAY_WIDTH)-1:0] l15_dcache_index_s2;
// 64B L15 cacheline: dcache data/mask/dout widened from 128b to 512b.
wire [511:0] l15_dcache_write_data_s2;
wire [511:0] l15_dcache_write_mask_s2;
wire [511:0] dcache_l15_dout_s3;


`ifndef NO_RTL_CSM
wire [`L15_CSM_GHID_WIDTH-1:0] l15_hmt_write_data_s2;
wire [`L15_CSM_GHID_WIDTH-1:0] l15_hmt_write_mask_s2;
wire [`L15_CSM_GHID_WIDTH-1:0] hmt_l15_dout_s3;
`endif

// sram_1rw_512x128 dcache(
sram_rnf_data dcache(
    .MEMCLK(clk),
    .RESET_N(rst_n),
    .CE(l15_dcache_val_s2),
    .A(l15_dcache_index_s2),
    .DIN({l15_dcache_write_data_s2}),
    .BW({l15_dcache_write_mask_s2}),
    .RDWEN(l15_dcache_rw_s2),
    .DOUT({dcache_l15_dout_s3}),
    .BIST_COMMAND(rtap_srams_bist_command),
    .BIST_DIN(rtap_srams_bist_data),
    .BIST_DOUT(dcache_rtap_data),
    .SRAMID(`BIST_ID_L15_DCACHE)
);


/////////////////////////////////////////////////////////////////////////////////////////////////////////
// MISS STATUS HANDLING REGISTER
/////////////////////////////////////////////////////////////////////////////////////////////////////////

// MSHR
wire pipe_mshr_writereq_val_s1;
wire [`L15_MSHR_WRITE_TYPE_WIDTH-1:0] pipe_mshr_writereq_op_s1;
wire [`L15_PADDR_HI:0] pipe_mshr_writereq_address_s1;
// 64B L15: write buffer data widened 128b->512b, byte mask 16b->64b.
wire [511:0] pipe_mshr_writereq_write_buffer_data_s1;
wire [63:0] pipe_mshr_writereq_write_buffer_byte_mask_s1;
wire [`L15_CONTROL_WIDTH-1:0] pipe_mshr_writereq_control_s1;
wire [`L15_MSHR_ID_WIDTH-1:0] pipe_mshr_writereq_mshrid_s1;
wire [`L15_THREADID_MASK] pipe_mshr_writereq_threadid_s1;
wire [`L15_THREADID_MASK] pipe_mshr_readreq_threadid_s1;
wire [`L15_MSHR_ID_WIDTH-1:0] pipe_mshr_readreq_mshrid_s1;
wire [`L15_CONTROL_WIDTH-1:0] mshr_pipe_readres_control_s1;
wire [`PACKET_HOME_ID_WIDTH-1:0] mshr_pipe_readres_homeid_s1;
wire [(`L15_NUM_MSHRID_PER_THREAD*`L15_NUM_THREADS)-1:0] mshr_pipe_vals_s1;
wire [(`L15_PADDR_WIDTH*`L15_NUM_THREADS)-1:0] mshr_pipe_ld_address;
wire [(`L15_PADDR_WIDTH*`L15_NUM_THREADS)-1:0] mshr_pipe_st_address;
wire [(`L15_WAY_WIDTH*`L15_NUM_THREADS)-1:0] mshr_pipe_st_way_s1;
wire [(`L15_MESI_TRANS_STATE_WIDTH*`L15_NUM_THREADS)-1:0] mshr_pipe_st_state_s1;
wire pipe_mshr_write_buffer_rd_en_s2;
wire [`L15_THREADID_MASK] pipe_mshr_threadid_s2;
// 64B L15: write buffer data widened 128b->512b, byte mask 16b->64b.
wire [511:0] mshr_pipe_write_buffer_s2;
wire [63:0] mshr_pipe_write_buffer_byte_mask_s2;
wire pipe_mshr_val_s3;
wire [`L15_MSHR_WRITE_TYPE_WIDTH-1:0] pipe_mshr_op_s3;
wire [`L15_MSHR_ID_WIDTH-1:0] pipe_mshr_mshrid_s3;
wire [`L15_THREADID_MASK] pipe_mshr_threadid_s3;
wire [`L15_MESI_TRANS_STATE_WIDTH-1:0] pipe_mshr_write_update_state_s3;
wire [`L15_WAY_MASK] pipe_mshr_write_update_way_s3;

wire noc1buffer_mshr_homeid_write_val_s4;
wire [`L15_MSHR_ID_WIDTH-1:0] noc1buffer_mshr_homeid_write_mshrid_s4;
wire [`PACKET_HOME_ID_WIDTH-1:0] noc1buffer_mshr_homeid_write_data_s4;
wire [`L15_THREADID_MASK] noc1buffer_mshr_homeid_write_threadid_s4;

rnf_mshr mshr(
    .clk(clk),
    .rst_n(rst_n),
    .pipe_mshr_writereq_val_s1(pipe_mshr_writereq_val_s1),
    .pipe_mshr_writereq_op_s1(pipe_mshr_writereq_op_s1),
    .pipe_mshr_writereq_address_s1(pipe_mshr_writereq_address_s1),
    .pipe_mshr_writereq_write_buffer_data_s1(pipe_mshr_writereq_write_buffer_data_s1),
    .pipe_mshr_writereq_write_buffer_byte_mask_s1(pipe_mshr_writereq_write_buffer_byte_mask_s1),
    .pipe_mshr_writereq_control_s1(pipe_mshr_writereq_control_s1),
    .pipe_mshr_writereq_mshrid_s1(pipe_mshr_writereq_mshrid_s1),
    .pipe_mshr_writereq_threadid_s1(pipe_mshr_writereq_threadid_s1),
    .pipe_mshr_readreq_threadid_s1(pipe_mshr_readreq_threadid_s1),
    .pipe_mshr_readreq_mshrid_s1(pipe_mshr_readreq_mshrid_s1),
    .mshr_pipe_readres_control_s1(mshr_pipe_readres_control_s1),
    .mshr_pipe_readres_homeid_s1(mshr_pipe_readres_homeid_s1),
    .mshr_pipe_vals_s1(mshr_pipe_vals_s1),
    .mshr_pipe_ld_address(mshr_pipe_ld_address),
    .mshr_pipe_st_address(mshr_pipe_st_address),
    .mshr_pipe_st_way_s1(mshr_pipe_st_way_s1),
    .mshr_pipe_st_state_s1(mshr_pipe_st_state_s1),
    .pipe_mshr_write_buffer_rd_en_s2(pipe_mshr_write_buffer_rd_en_s2),
    .pipe_mshr_threadid_s2(pipe_mshr_threadid_s2),
    .mshr_pipe_write_buffer_s2(mshr_pipe_write_buffer_s2),
    .mshr_pipe_write_buffer_byte_mask_s2(mshr_pipe_write_buffer_byte_mask_s2),
    .pipe_mshr_val_s3(pipe_mshr_val_s3),
    .pipe_mshr_op_s3(pipe_mshr_op_s3),
    .pipe_mshr_mshrid_s3(pipe_mshr_mshrid_s3),
    .pipe_mshr_threadid_s3(pipe_mshr_threadid_s3),
    .pipe_mshr_write_update_state_s3(pipe_mshr_write_update_state_s3),
    .pipe_mshr_write_update_way_s3(pipe_mshr_write_update_way_s3),
    
    .noc1buffer_mshr_homeid_write_threadid_s4(noc1buffer_mshr_homeid_write_threadid_s4),
    .noc1buffer_mshr_homeid_write_val_s4(noc1buffer_mshr_homeid_write_val_s4),
    .noc1buffer_mshr_homeid_write_mshrid_s4(noc1buffer_mshr_homeid_write_mshrid_s4),
    .noc1buffer_mshr_homeid_write_data_s4(noc1buffer_mshr_homeid_write_data_s4)
);


/////////////////////////////////////////////////////////////////////////////////////////////////////////
// MESI ARRAY AND LRSC (load reserved/store conditional)
/////////////////////////////////////////////////////////////////////////////////////////////////////////

// MESI array
wire l15_mesi_read_val_s1;
wire [`L15_CACHE_INDEX_WIDTH-1:0] l15_mesi_read_index_s1;
wire l15_mesi_write_val_s2;
wire [`L15_CACHE_INDEX_WIDTH-1:0] l15_mesi_write_index_s2;
wire [`L15_MESI_STATE_WIDTH*`L15_WAY_COUNT-1:0] l15_mesi_write_mask_s2;
wire [`L15_MESI_STATE_WIDTH*`L15_WAY_COUNT-1:0] l15_mesi_write_data_s2;
wire [`L15_MESI_STATE_WIDTH*`L15_WAY_COUNT-1:0] mesi_l15_dout_s2;

rf_rnf_mesi mesi(
    .clk(clk),
    .rst_n(rst_n),
    .read_valid(l15_mesi_read_val_s1),
    .read_index(l15_mesi_read_index_s1),
    .write_valid(l15_mesi_write_val_s2),
    .write_index(l15_mesi_write_index_s2),
    .write_mask(l15_mesi_write_mask_s2),
    .write_data(l15_mesi_write_data_s2),
    .read_data(mesi_l15_dout_s2)
);

// LRSC Flag array
wire l15_lrsc_flag_read_val_s1;
wire [`L15_CACHE_INDEX_WIDTH-1:0] l15_lrsc_flag_read_index_s1;
wire l15_lrsc_flag_write_val_s2;
wire [`L15_CACHE_INDEX_WIDTH-1:0] l15_lrsc_flag_write_index_s2;
// 64B L15: LRSC flag entry holds {sub_blk_id[1:0], flag} per way -> 12b (was 4b).
wire [`L15_LRSC_MASK] l15_lrsc_flag_write_mask_s2;
wire [`L15_LRSC_MASK] l15_lrsc_flag_write_data_s2;
wire [`L15_LRSC_MASK] lrsc_flag_l15_dout_s2;

rf_rnf_lrsc_flag lrsc_flag(
    .clk(clk),
    .rst_n(rst_n),
    .read_valid(l15_lrsc_flag_read_val_s1),
    .read_index(l15_lrsc_flag_read_index_s1),
    .write_valid(l15_lrsc_flag_write_val_s2),
    .write_index(l15_lrsc_flag_write_index_s2),
    .write_mask(l15_lrsc_flag_write_mask_s2),
    .write_data(l15_lrsc_flag_write_data_s2),
    .read_data(lrsc_flag_l15_dout_s2)
);


/////////////////////////////////////////////////////////////////////////////////////////////////////////
// WAY MAP TABLE AND LRU (least recently used) array
/////////////////////////////////////////////////////////////////////////////////////////////////////////

// way map table
wire l15_wmt_read_val_s2;
wire [`L1D_SET_IDX_MASK] l15_wmt_read_index_s2;
wire l15_wmt_write_val_s3;
wire [`L1D_SET_IDX_MASK] l15_wmt_write_index_s3;
wire [`L15_WMT_MASK] l15_wmt_write_mask_s3;
wire [`L15_WMT_MASK] l15_wmt_write_data_s3;
wire [`L15_WMT_MASK] wmt_l15_data_s3;
rf_rnf_wmt wmc(
    .clk(clk),
    .rst_n(rst_n),
    .read_valid(l15_wmt_read_val_s2),
    .read_index(l15_wmt_read_index_s2),
    .write_valid(l15_wmt_write_val_s3),
    .write_index(l15_wmt_write_index_s3),
    .write_mask(l15_wmt_write_mask_s3),
    .write_data(l15_wmt_write_data_s3),
    .read_data(wmt_l15_data_s3)
);

// lru array, psuedo
wire l15_lruarray_read_val_s1;
wire [`L15_CACHE_INDEX_WIDTH-1:0] l15_lruarray_read_index_s1;
wire l15_lruarray_write_val_s3;
wire [`L15_CACHE_INDEX_WIDTH-1:0] l15_lruarray_write_index_s3;
wire [`L15_LRUARRAY_MASK] l15_lruarray_write_mask_s3;
wire [`L15_LRUARRAY_MASK] l15_lruarray_write_data_s3;
wire [`L15_LRUARRAY_MASK] lruarray_l15_dout_s2;
rf_rnf_lruarray lruarray(
    .clk(clk),
    .rst_n(rst_n),
    .read_valid(l15_lruarray_read_val_s1),
    .read_index(l15_lruarray_read_index_s1),
    .write_valid(l15_lruarray_write_val_s3),
    .write_index(l15_lruarray_write_index_s3),
    .write_mask(l15_lruarray_write_mask_s3),
    .write_data(l15_lruarray_write_data_s3),
    .read_data(lruarray_l15_dout_s2)
);



/////////////////////////////////////////////////////////////////////////////////////////////////////////
// PIPELINE
/////////////////////////////////////////////////////////////////////////////////////////////////////////


// pipeline
rnf_pipeline pipeline(
    .clk(clk),
    .rst_n(rst_n),
    .dtag_l15_dout_s2(dtag_l15_dout_s2),
    .dcache_l15_dout_s3(dcache_l15_dout_s3),
    .mesi_l15_dout_s2(mesi_l15_dout_s2),
    .lrsc_flag_l15_dout_s2(lrsc_flag_l15_dout_s2),
    .lruarray_l15_dout_s2(lruarray_l15_dout_s2),
    .wmt_l15_data_s3(wmt_l15_data_s3),
    .pcxdecoder_l15_rqtype               (transducer_l15_rqtype),
    .pcxdecoder_l15_amo_op               (transducer_l15_amo_op),
    .pcxdecoder_l15_nc                   (transducer_l15_nc),
    .pcxdecoder_l15_size                 (transducer_l15_size),
    // .pcxdecoder_l15_invalall          (transducer_l15_invalall),
    .pcxdecoder_l15_threadid             (transducer_l15_threadid),
    .pcxdecoder_l15_prefetch             (transducer_l15_prefetch),
    .pcxdecoder_l15_blockstore           (transducer_l15_blockstore),
    .pcxdecoder_l15_blockinitstore       (transducer_l15_blockinitstore),
    .pcxdecoder_l15_l1rplway             (transducer_l15_l1rplway),
    .pcxdecoder_l15_val                  (transducer_l15_val),
    .pcxdecoder_l15_invalidate_cacheline (transducer_l15_invalidate_cacheline),
    .pcxdecoder_l15_address              (transducer_l15_address),
    .pcxdecoder_l15_data                 (transducer_l15_data),
    .pcxdecoder_l15_data_next_entry      (transducer_l15_data_next_entry),
    .pcxdecoder_l15_csm_data             (transducer_l15_csm_data),
    .noc2decoder_l15_val(noc2decoder_l15_val),
    .noc2decoder_l15_mshrid(noc2decoder_l15_mshrid),
    .noc2decoder_l15_l2miss(noc2decoder_l15_l2miss),
    .noc2decoder_l15_icache_type(noc2decoder_l15_icache_type),
    .noc2decoder_l15_f4b(noc2decoder_l15_f4b),
    .noc2decoder_l15_reqtype(noc2decoder_l15_reqtype),
    .noc2decoder_l15_ack_state(noc2decoder_l15_ack_state),
    // Single 512b NOC2 data port replacing data_0..3.
    .noc2decoder_l15_data(noc2decoder_l15_data),
    .noc2decoder_l15_address(noc2decoder_l15_address),
    .noc2decoder_l15_fwd_subcacheline_vector(noc2decoder_l15_fwd_subcacheline_vector),
    .noc2decoder_l15_src_homeid(noc2decoder_l15_src_homeid),
    .noc2decoder_l15_csm_mshrid(noc2decoder_l15_csm_mshrid),
    .noc2decoder_l15_threadid(noc2decoder_l15_threadid),
    .noc2decoder_l15_hmc_fill(noc2decoder_l15_hmc_fill),
    .noc2decoder_l15_txnid(noc2decoder_l15_txnid),
    .cpxencoder_l15_req_ack(transducer_l15_req_ack),
    // .noc1encoder_l15_req_ack(noc1encoder_l15_req_ack),
    .noc1encoder_l15_req_sent(noc1encoder_l15_req_sent),
    .noc1encoder_l15_req_data_sent(noc1encoder_l15_req_data_sent),
    .noc3encoder_l15_req_ack(noc3encoder_l15_req_ack),
    
    // OUTPUT
    .l15_dtag_val_s1(l15_dtag_val_s1),
    .l15_dtag_rw_s1(l15_dtag_rw_s1),
    .l15_dtag_index_s1(l15_dtag_index_s1),
    .l15_dtag_write_data_s1(l15_dtag_write_data_s1),
    .l15_dtag_write_mask_s1(l15_dtag_write_mask_s1),
    .l15_dcache_val_s2(l15_dcache_val_s2),
    .l15_dcache_rw_s2(l15_dcache_rw_s2),
    .l15_dcache_index_s2(l15_dcache_index_s2),
    .l15_dcache_write_data_s2(l15_dcache_write_data_s2),
    .l15_dcache_write_mask_s2(l15_dcache_write_mask_s2),
    .l15_mesi_read_val_s1(l15_mesi_read_val_s1),
    .l15_mesi_read_index_s1(l15_mesi_read_index_s1),
    .l15_mesi_write_val_s2(l15_mesi_write_val_s2),
    .l15_mesi_write_index_s2(l15_mesi_write_index_s2),
    .l15_mesi_write_mask_s2(l15_mesi_write_mask_s2),
    .l15_mesi_write_data_s2(l15_mesi_write_data_s2),
    .l15_lrsc_flag_read_val_s1(l15_lrsc_flag_read_val_s1),
    .l15_lrsc_flag_read_index_s1(l15_lrsc_flag_read_index_s1),
    .l15_lrsc_flag_write_val_s2(l15_lrsc_flag_write_val_s2),
    .l15_lrsc_flag_write_index_s2(l15_lrsc_flag_write_index_s2),
    .l15_lrsc_flag_write_mask_s2(l15_lrsc_flag_write_mask_s2),
    .l15_lrsc_flag_write_data_s2(l15_lrsc_flag_write_data_s2),
    .l15_wmt_read_val_s2(l15_wmt_read_val_s2),
    .l15_wmt_read_index_s2(l15_wmt_read_index_s2),
    .l15_wmt_write_val_s3(l15_wmt_write_val_s3),
    .l15_wmt_write_index_s3(l15_wmt_write_index_s3),
    .l15_wmt_write_mask_s3(l15_wmt_write_mask_s3),
    .l15_wmt_write_data_s3(l15_wmt_write_data_s3),
    .l15_lruarray_read_val_s1(l15_lruarray_read_val_s1),
    .l15_lruarray_read_index_s1(l15_lruarray_read_index_s1),
    .l15_lruarray_write_val_s3(l15_lruarray_write_val_s3),
    .l15_lruarray_write_index_s3(l15_lruarray_write_index_s3),
    .l15_lruarray_write_mask_s3(l15_lruarray_write_mask_s3),
    .l15_lruarray_write_data_s3(l15_lruarray_write_data_s3),
    .l15_cpxencoder_val                  (l15_transducer_val),
    .l15_cpxencoder_returntype           (l15_transducer_returntype),
    .l15_cpxencoder_l2miss               (l15_transducer_l2miss),
    .l15_cpxencoder_error                (l15_transducer_error),
    .l15_cpxencoder_noncacheable         (l15_transducer_noncacheable),
    .l15_cpxencoder_atomic               (l15_transducer_atomic),
    .l15_cpxencoder_threadid             (l15_transducer_threadid),
    .l15_cpxencoder_prefetch             (l15_transducer_prefetch),
    .l15_cpxencoder_f4b                  (l15_transducer_f4b),
    .l15_cpxencoder_data_0               (l15_transducer_data_0),
    .l15_cpxencoder_data_1               (l15_transducer_data_1),
    .l15_cpxencoder_data_2               (l15_transducer_data_2),
    .l15_cpxencoder_data_3               (l15_transducer_data_3),
    .l15_cpxencoder_inval_icache_all_way (l15_transducer_inval_icache_all_way),
    .l15_cpxencoder_inval_dcache_all_way (l15_transducer_inval_dcache_all_way),
    .l15_cpxencoder_inval_address_15_4   (l15_transducer_inval_address_15_4),
    .l15_cpxencoder_cross_invalidate     (l15_transducer_cross_invalidate),
    .l15_cpxencoder_cross_invalidate_way (l15_transducer_cross_invalidate_way),
    .l15_cpxencoder_inval_dcache_inval   (l15_transducer_inval_dcache_inval),
    .l15_cpxencoder_inval_icache_inval   (l15_transducer_inval_icache_inval),
    .l15_cpxencoder_inval_way            (l15_transducer_inval_way),
    .l15_cpxencoder_blockinitstore       (l15_transducer_blockinitstore),
    .l15_noc1buffer_req_val(l15_noc1buffer_req_val),
    .l15_noc1buffer_req_type(l15_noc1buffer_req_type),
    .l15_noc1buffer_req_threadid(l15_noc1buffer_req_threadid),
    .l15_noc1buffer_req_mshrid(l15_noc1buffer_req_mshrid),
    .l15_noc1buffer_req_address(l15_noc1buffer_req_address),
    .l15_noc1buffer_req_non_cacheable(l15_noc1buffer_req_non_cacheable),
    .l15_noc1buffer_req_size(l15_noc1buffer_req_size),
    .l15_noc1buffer_req_prefetch(l15_noc1buffer_req_prefetch),
    // .l15_noc1buffer_req_blkstore(l15_noc1buffer_req_blkstore),
    // .l15_noc1buffer_req_blkinitstore(l15_noc1buffer_req_blkinitstore),
    .l15_noc1buffer_req_data_0(l15_noc1buffer_req_data_0),
    .l15_noc1buffer_req_data_1(l15_noc1buffer_req_data_1),
    .l15_noc1buffer_req_csm_data(l15_noc1buffer_req_csm_data),
    .l15_noc3encoder_req_val(l15_noc3encoder_req_val),
    .l15_noc3encoder_req_type(l15_noc3encoder_req_type),
    // Single 512b NOC3 data port from the modified pipeline.
    .l15_noc3encoder_req_data(l15_noc3encoder_req_data),
    .l15_noc3encoder_req_mshrid(l15_noc3encoder_req_mshrid),
    .l15_noc3encoder_req_sequenceid(l15_noc3encoder_req_sequenceid),
    .l15_noc3encoder_req_threadid(l15_noc3encoder_req_threadid),
    .l15_noc3encoder_req_address(l15_noc3encoder_req_address),
    .l15_noc3encoder_req_with_data(l15_noc3encoder_req_with_data),
    .l15_noc3encoder_req_was_inval(l15_noc3encoder_req_was_inval),
    .l15_noc3encoder_req_fwdack_vector(l15_noc3encoder_req_fwdack_vector),
    .l15_noc3buffer_req_prev_mesi(l15_noc3buffer_req_prev_mesi),
    .l15_noc3encoder_req_rxsnp_txnid(l15_noc3encoder_req_rxsnp_txnid),
    .l15_noc3encoder_req_homeid(l15_noc3encoder_req_homeid),
    .l15_pcxdecoder_ack(l15_transducer_ack),
    .l15_noc2decoder_ack(l15_noc2decoder_ack),
    .l15_pcxdecoder_header_ack(l15_transducer_header_ack),
    .l15_noc2decoder_header_ack(l15_noc2decoder_header_ack),
    
    // CSM
    .l15_csm_req_address_s2(l15_csm_req_address_s2),
    .l15_csm_req_val_s2(l15_csm_req_val_s2),
    .l15_csm_stall_s3(l15_csm_stall_s3),
    .l15_csm_req_ticket_s2(l15_csm_req_ticket_s2),
    // .l15_csm_clump_tile_count_s2(l15_csm_clump_tile_count_s2),
    .l15_csm_req_type_s2(l15_csm_req_type_s2),
    .l15_csm_req_data_s2(l15_csm_req_data_s2),
    .l15_csm_req_pcx_data_s2(l15_csm_req_pcx_data_s2),
    .csm_l15_res_val_s3(csm_l15_res_val_s3),
    .csm_l15_res_data_s3(csm_l15_res_data_s3),
    
    .l15_noc1buffer_req_csm_ticket(l15_noc1buffer_req_csm_ticket),
    .l15_noc1buffer_req_homeid(l15_noc1buffer_req_homeid),
    .l15_noc1buffer_req_homeid_val(l15_noc1buffer_req_homeid_val),
    
    // .config_csm_en(config_csm_en),
    
    // hmt
     `ifndef NO_RTL_CSM
    .l15_hmt_write_data_s2(l15_hmt_write_data_s2),
    .l15_hmt_write_mask_s2(l15_hmt_write_mask_s2),
    .hmt_l15_dout_s3(hmt_l15_dout_s3),
     `endif
    
    // config registers
    .l15_config_req_val_s2(),
    .l15_config_req_rw_s2(),
    .l15_config_write_req_data_s2(),
    .l15_config_req_address_s2(),
    .config_l15_read_res_data_s3(),
    
    // MSHR
    .pipe_mshr_writereq_val_s1(pipe_mshr_writereq_val_s1),
    .pipe_mshr_writereq_op_s1(pipe_mshr_writereq_op_s1),
    .pipe_mshr_writereq_address_s1(pipe_mshr_writereq_address_s1),
    .pipe_mshr_writereq_write_buffer_data_s1(pipe_mshr_writereq_write_buffer_data_s1),
    .pipe_mshr_writereq_write_buffer_byte_mask_s1(pipe_mshr_writereq_write_buffer_byte_mask_s1),
    .pipe_mshr_writereq_control_s1(pipe_mshr_writereq_control_s1),
    .pipe_mshr_writereq_mshrid_s1(pipe_mshr_writereq_mshrid_s1),
    .pipe_mshr_writereq_threadid_s1(pipe_mshr_writereq_threadid_s1),
    .pipe_mshr_readreq_threadid_s1(pipe_mshr_readreq_threadid_s1),
    .pipe_mshr_readreq_mshrid_s1(pipe_mshr_readreq_mshrid_s1),
    .mshr_pipe_readres_control_s1(mshr_pipe_readres_control_s1),
    .mshr_pipe_readres_homeid_s1(mshr_pipe_readres_homeid_s1),
    .mshr_pipe_vals_s1(mshr_pipe_vals_s1),
    .mshr_pipe_ld_address(mshr_pipe_ld_address),
    .mshr_pipe_st_address(mshr_pipe_st_address),
    .mshr_pipe_st_way_s1(mshr_pipe_st_way_s1),
    .mshr_pipe_st_state_s1(mshr_pipe_st_state_s1),
    .pipe_mshr_write_buffer_rd_en_s2(pipe_mshr_write_buffer_rd_en_s2),
    .pipe_mshr_threadid_s2(pipe_mshr_threadid_s2),
    .mshr_pipe_write_buffer_s2(mshr_pipe_write_buffer_s2),
    .mshr_pipe_write_buffer_byte_mask_s2(mshr_pipe_write_buffer_byte_mask_s2),
    .pipe_mshr_val_s3(pipe_mshr_val_s3),
    .pipe_mshr_op_s3(pipe_mshr_op_s3),
    .pipe_mshr_mshrid_s3(pipe_mshr_mshrid_s3),
    .pipe_mshr_threadid_s3(pipe_mshr_threadid_s3),
    .pipe_mshr_write_update_state_s3(pipe_mshr_write_update_state_s3),
    .pipe_mshr_write_update_way_s3(pipe_mshr_write_update_way_s3)
);


/////////////////////////////////////////////////////////////////////////////////////////////////////////
// NOC1 AND NOC3 BUFFERS AND ENCODERS
/////////////////////////////////////////////////////////////////////////////////////////////////////////
req_buffer req_buffer(
    .clk(clk),
    .rst_n(rst_n),
    .l15_noc1buffer_req_data_0(l15_noc1buffer_req_data_0),
    .l15_noc1buffer_req_data_1(l15_noc1buffer_req_data_1),
    .l15_noc1buffer_req_val(l15_noc1buffer_req_val),
    .l15_noc1buffer_req_type(l15_noc1buffer_req_type),
    .l15_noc1buffer_req_threadid(l15_noc1buffer_req_threadid),
    .l15_noc1buffer_req_mshrid(l15_noc1buffer_req_mshrid),
    .l15_noc1buffer_req_address(l15_noc1buffer_req_address),
    .l15_noc1buffer_req_non_cacheable(l15_noc1buffer_req_non_cacheable),
    .l15_noc1buffer_req_size(l15_noc1buffer_req_size),
    .l15_noc1buffer_req_prefetch(l15_noc1buffer_req_prefetch),
    // .l15_noc1buffer_req_blkstore(l15_noc1buffer_req_blkstore),
    // .l15_noc1buffer_req_blkinitstore(l15_noc1buffer_req_blkinitstore),
    .l15_noc1buffer_req_csm_data(l15_noc1buffer_req_csm_data),
    
    .l15_noc1buffer_req_csm_ticket(l15_noc1buffer_req_csm_ticket),
    .l15_noc1buffer_req_homeid(l15_noc1buffer_req_homeid),
    .l15_noc1buffer_req_homeid_val(l15_noc1buffer_req_homeid_val),
    .noc1buffer_noc1encoder_req_csm_sdid(noc1buffer_noc1encoder_req_csm_sdid),
    .noc1buffer_noc1encoder_req_csm_lsid(noc1buffer_noc1encoder_req_csm_lsid),
    
    .noc1encoder_noc1buffer_req_ack(noc1encoder_noc1buffer_req_ack),
    
    .noc1buffer_noc1encoder_req_data_0(noc1buffer_noc1encoder_req_data_0),
    .noc1buffer_noc1encoder_req_data_1(noc1buffer_noc1encoder_req_data_1),
    .noc1buffer_noc1encoder_req_val(noc1buffer_noc1encoder_req_val),
    .noc1buffer_noc1encoder_req_type(noc1buffer_noc1encoder_req_type),
    .noc1buffer_noc1encoder_req_mshrid(noc1buffer_noc1encoder_req_mshrid),
    .noc1buffer_noc1encoder_req_threadid(noc1buffer_noc1encoder_req_threadid),
    .noc1buffer_noc1encoder_req_address(noc1buffer_noc1encoder_req_address),
    .noc1buffer_noc1encoder_req_non_cacheable(noc1buffer_noc1encoder_req_non_cacheable),
    .noc1buffer_noc1encoder_req_size(noc1buffer_noc1encoder_req_size),
    .noc1buffer_noc1encoder_req_prefetch(noc1buffer_noc1encoder_req_prefetch),
    // .noc1buffer_noc1encoder_req_blkstore(noc1buffer_noc1encoder_req_blkstore),
    // .noc1buffer_noc1encoder_req_blkinitstore(noc1buffer_noc1encoder_req_blkinitstore),
    
    // stall signal from dmbr prevents the encoder from sending requests to the L2
    // .l15_dmbr_l1missIn(l15_dmbr_l1missIn),
    // .l15_dmbr_l1missTag(l15_dmbr_l1missTag),
    // .dmbr_l15_stall(dmbr_l15_stall),
    
    // CSM
    .l15_csm_read_ticket(l15_csm_read_ticket),
    .l15_csm_clear_ticket(l15_csm_clear_ticket),
    .l15_csm_clear_ticket_val(l15_csm_clear_ticket_val),
    .csm_l15_read_res_data(csm_l15_read_res_data),
    .csm_l15_read_res_val(csm_l15_read_res_val),
    .noc1buffer_noc1encoder_req_homeid(noc1buffer_noc1encoder_req_homeid),
    
    // .noc1buffer_l15_req_ack(noc1encoder_l15_req_ack),
    .noc1buffer_l15_req_sent(noc1encoder_l15_req_sent),
    .noc1buffer_l15_req_data_sent(noc1encoder_l15_req_data_sent),
    
    // homeid
    .noc1buffer_mshr_homeid_write_threadid_s4(noc1buffer_mshr_homeid_write_threadid_s4),
    .noc1buffer_mshr_homeid_write_val_s4(noc1buffer_mshr_homeid_write_val_s4),
    .noc1buffer_mshr_homeid_write_mshrid_s4(noc1buffer_mshr_homeid_write_mshrid_s4),
    .noc1buffer_mshr_homeid_write_data_s4(noc1buffer_mshr_homeid_write_data_s4)
);

/*
   1 deep buffer for noc3 to improve performance and reduce timing pressure
*/
rx_buffer rx_buffer(
    .clk(clk),
    .rst_n(rst_n),
    .l15_noc3encoder_req_val(l15_noc3encoder_req_val),
    .l15_noc3encoder_req_type(l15_noc3encoder_req_type),
    // Single 512b NOC3 data port from the modified pipeline.
    .l15_noc3encoder_req_data(l15_noc3encoder_req_data),
    .l15_noc3encoder_req_mshrid(l15_noc3encoder_req_mshrid),
    .l15_noc3encoder_req_sequenceid(l15_noc3encoder_req_sequenceid),
    .l15_noc3encoder_req_threadid(l15_noc3encoder_req_threadid),
    .l15_noc3encoder_req_address(l15_noc3encoder_req_address),
    .l15_noc3encoder_req_with_data(l15_noc3encoder_req_with_data),
    .l15_noc3encoder_req_was_inval(l15_noc3encoder_req_was_inval),
    .l15_noc3encoder_req_fwdack_vector(l15_noc3encoder_req_fwdack_vector),
    .l15_noc3encoder_req_homeid(l15_noc3encoder_req_homeid),
    .l15_noc3buffer_req_prev_mesi(l15_noc3buffer_req_prev_mesi),
    .l15_noc3encoder_req_rxsnp_txnid(l15_noc3encoder_req_rxsnp_txnid),
    .noc3buffer_l15_req_ack(noc3encoder_l15_req_ack),
    
    // from buffer to encoder
    .noc3buffer_noc3encoder_req_val(noc3buffer_noc3encoder_req_val),
    .noc3buffer_noc3encoder_req_type(noc3buffer_noc3encoder_req_type),
    // Single 512b aggregate from noc3buffer to the response_encoder.
    .noc3buffer_noc3encoder_req_data(noc3buffer_noc3encoder_req_data),
    .noc3buffer_noc3encoder_req_mshrid(noc3buffer_noc3encoder_req_mshrid),
    .noc3buffer_noc3encoder_req_sequenceid(noc3buffer_noc3encoder_req_sequenceid),
    .noc3buffer_noc3encoder_req_threadid(noc3buffer_noc3encoder_req_threadid),
    .noc3buffer_noc3encoder_req_address(noc3buffer_noc3encoder_req_address),
    .noc3buffer_noc3encoder_req_with_data(noc3buffer_noc3encoder_req_with_data),
    .noc3buffer_noc3encoder_req_was_inval(noc3buffer_noc3encoder_req_was_inval),
    .noc3buffer_noc3encoder_req_fwdack_vector(noc3buffer_noc3encoder_req_fwdack_vector),
    .noc3buffer_noc3encoder_req_homeid(noc3buffer_noc3encoder_req_homeid),
    .noc3buffer_rspencoder_req_prev_mesi(noc3buffer_rspencoder_req_prev_mesi),
    .noc3buffer_noc3encoder_req_rxsnp_txnid(noc3buffer_noc3encoder_req_rxsnp_txnid),
    .noc3encoder_noc3buffer_req_ack(noc3encoder_noc3buffer_req_ack)
);


// TXDAT wires
    wire [`CHIE_DAT_FLIT_QOS_WIDTH-1:0]         encoder_txdat_qos;
    wire [`CHIE_DAT_FLIT_SRCID_WIDTH-1:0]       encoder_txdat_srcid;
    wire [`CHIE_DAT_FLIT_HOMENID_WIDTH-1:0]     encoder_txdat_homenid;
    wire [`CHIE_DAT_FLIT_FWDSTATE_WIDTH-1:0]    encoder_txdat_fwdstate;
    wire [`CHIE_DAT_FLIT_CCID_WIDTH-1:0]        encoder_txdat_ccid;
    wire [`CHIE_DAT_FLIT_TGTID_WIDTH-1:0]       mshr_txdat_tgtid_sx2;
    wire [`CHIE_DAT_FLIT_TXNID_WIDTH-1:0]       mshr_txdat_txnid_sx2;
    wire [`CHIE_DAT_FLIT_OPCODE_WIDTH-1:0]      mshr_txdat_opcode_sx2;
    wire [`CHIE_DAT_FLIT_RESP_WIDTH-1:0]        mshr_txdat_resp_sx2;
    wire [`CHIE_DAT_FLIT_RESPERR_WIDTH-1:0]     mshr_txdat_resperr_sx2;
    wire [`CHIE_DAT_FLIT_DBID_WIDTH-1:0]        mshr_txdat_dbid_sx2;
    wire [`CHI_CACHE_LINE_WIDTH-1:0]            dbf_txdat_data_sx1;
    wire [2-1:0]                                dbf_txdat_idx_sx1;
    wire [1:0]                                  dbf_txdat_pe_sx1;
    wire [`CHI_CACHE_BE_WIDTH-1:0]              dbf_txdat_be_sx1;
    wire                                        dbf_txdat_valid_sx1;
    wire                                        txdat_mshr_clr_dbf_busy_valid_sx3;
    wire [2-1:0]                                txdat_mshr_clr_dbf_busy_idx_sx3;
    wire [2-1:0]                                txdat_mshr_rd_idx_sx2;
    wire                                        txdat_mshr_busy_sx;

    wire                                        encoder_txrsp_bypass_valid_s1;
    wire [`CHIE_RSP_FLIT_QOS_WIDTH-1:0]         encoder_txrsp_bypass_qos_s1;
    wire [`CHIE_RSP_FLIT_TGTID_WIDTH-1:0]       encoder_txrsp_bypass_tgtid_s1;
    wire [`CHIE_RSP_FLIT_TXNID_WIDTH-1:0]       encoder_txrsp_bypass_txnid_s1;
    wire [`CHIE_RSP_FLIT_OPCODE_WIDTH-1:0]      encoder_txrsp_bypass_opcode_s1;
    wire [`CHIE_RSP_FLIT_RESP_WIDTH-1:0]        encoder_txrsp_bypass_resp;
    wire [`CHIE_RSP_FLIT_RESPERR_WIDTH-1:0]     encoder_txrsp_bypass_resperr_s1;
    wire [`CHIE_RSP_FLIT_DBID_WIDTH-1:0]        encoder_txrsp_bypass_dbid_s1;
    wire [`CHIE_RSP_FLIT_TRACETAG_WIDTH-1:0]    encoder_txrsp_bypass_tracetag_s1;
    wire                                        txrsp_encoder_bypass_won_s1;


response_encoder `RNF_PARAM_INST response_encoder(
    .clk(clk),
    .rst_n(rst_n),
    .l15_noc3encoder_req_val_i(noc3buffer_noc3encoder_req_val),
    .l15_noc3encoder_req_type_i(noc3buffer_noc3encoder_req_type),
    // Single 512b data port replaces the prior 2x64b sub-block ports.
    .l15_noc3encoder_req_data_i(noc3buffer_noc3encoder_req_data),
    .l15_noc3encoder_req_mshrid_i(noc3buffer_noc3encoder_req_mshrid),
    .l15_noc3encoder_req_sequenceid_i(noc3buffer_noc3encoder_req_sequenceid),
    .l15_noc3encoder_req_threadid_i(noc3buffer_noc3encoder_req_threadid),
    .l15_noc3encoder_req_address_i(noc3buffer_noc3encoder_req_address),
    .l15_noc3encoder_req_with_data_i(noc3buffer_noc3encoder_req_with_data),
    .l15_noc3encoder_req_was_inval_i(noc3buffer_noc3encoder_req_was_inval),
    .l15_noc3encoder_req_fwdack_vector_i(noc3buffer_noc3encoder_req_fwdack_vector),
    .l15_noc3encoder_req_homeid_i(noc3buffer_noc3encoder_req_homeid),
    .l15_noc3buffer_req_prev_mesi_i(noc3buffer_rspencoder_req_prev_mesi),
    .l15_noc3buffer_req_rxsnp_txnid_i(noc3buffer_noc3encoder_req_rxsnp_txnid),
    .noc3encoder_l15_req_ack(noc3encoder_noc3buffer_req_ack),


    .encoder_txdat_qos                            (encoder_txdat_qos                 ),
    .encoder_txdat_srcid                          (encoder_txdat_srcid               ),
    .encoder_txdat_homenid                        (encoder_txdat_homenid             ),
    .encoder_txdat_fwdstate                       (encoder_txdat_fwdstate            ),
    .encoder_txdat_ccid                           (encoder_txdat_ccid                ),
    .mshr_txdat_tgtid_sx2                         (mshr_txdat_tgtid_sx2              ),
    .mshr_txdat_txnid_sx2                         (mshr_txdat_txnid_sx2              ),
    .mshr_txdat_opcode_sx2                        (mshr_txdat_opcode_sx2             ),
    .mshr_txdat_resp_sx2                          (mshr_txdat_resp_sx2               ),
    .mshr_txdat_resperr_sx2                       (mshr_txdat_resperr_sx2            ),
    .mshr_txdat_dbid_sx2                          (mshr_txdat_dbid_sx2               ),
    .dbf_txdat_data_sx1                           (dbf_txdat_data_sx1                ),
    .dbf_txdat_idx_sx1                            (dbf_txdat_idx_sx1                 ),
    .dbf_txdat_be_sx1                             (dbf_txdat_be_sx1                  ),
    .dbf_txdat_pe_sx1                             (dbf_txdat_pe_sx1                  ),
    .dbf_txdat_valid_sx1                          (dbf_txdat_valid_sx1               ),
    .txdat_mshr_clr_dbf_busy_valid_sx3            (txdat_mshr_clr_dbf_busy_valid_sx3 ),
    .txdat_mshr_clr_dbf_busy_idx_sx3              (txdat_mshr_clr_dbf_busy_idx_sx3   ),
    .txdat_mshr_rd_idx_sx2                        (txdat_mshr_rd_idx_sx2             ),
    .txdat_mshr_busy_sx                           (txdat_mshr_busy_sx                ),
    .encoder_txrsp_bypass_valid_s1                (encoder_txrsp_bypass_valid_s1            ),
    .encoder_txrsp_bypass_qos_s1                  (encoder_txrsp_bypass_qos_s1              ),
    .encoder_txrsp_bypass_tgtid_s1                (encoder_txrsp_bypass_tgtid_s1            ),
    .encoder_txrsp_bypass_txnid_s1                (encoder_txrsp_bypass_txnid_s1            ),
    .encoder_txrsp_bypass_opcode_s1               (encoder_txrsp_bypass_opcode_s1           ),
    .encoder_txrsp_bypass_resp                    (encoder_txrsp_bypass_resp                ),
    .encoder_txrsp_bypass_resperr_s1              (encoder_txrsp_bypass_resperr_s1          ),
    .encoder_txrsp_bypass_dbid_s1                 (encoder_txrsp_bypass_dbid_s1             ),
    .encoder_txrsp_bypass_tracetag_s1             (encoder_txrsp_bypass_tracetag_s1         ),
    .txrsp_encoder_bypass_won_s1                  (txrsp_encoder_bypass_won_s1              ),
    .rxbuf_rspenc_txdat_valid                     (rxbuf_rspenc_txdat_valid                      ),
    .rxbuf_rspenc_txdat_qos                       (rxbuf_rspenc_txdat_qos                         ),
    .rxbuf_rspenc_txdat_srcid                     (rxbuf_rspenc_txdat_srcid                           ),
    .rxbuf_rspenc_txdat_txnid                     (rxbuf_rspenc_txdat_txnid                      ),
    .rxbuf_rspenc_txdat_opcode                    (rxbuf_rspenc_txdat_opcode                     ),    
    .rxbuf_rspenc_txdat_resp                      (rxbuf_rspenc_txdat_resp                       ),
    .rxbuf_rspenc_txdat_resperr                   (rxbuf_rspenc_txdat_resperr                          ),
    .rxbuf_rspenc_txdat_fwdstate                  (rxbuf_rspenc_txdat_fwdstate                   ),    
    .rxbuf_rspenc_txdat_dataid                    (rxbuf_rspenc_txdat_dataid                     ),    
    .rxbuf_rspenc_txdat_homenid                   (rxbuf_rspenc_txdat_homenid                    ),    
    .rxbuf_rspenc_txdat_ccid                      (rxbuf_rspenc_txdat_ccid                       ),
    .rxbuf_rspenc_txdat_tgtid                     (rxbuf_rspenc_txdat_tgtid                            ),
    .rxbuf_rspenc_txdat_dbid                      (rxbuf_rspenc_txdat_dbid                       ),
    .rxbuf_rspenc_txdat_be                        (rxbuf_rspenc_txdat_be                         ),
    .rxbuf_rspenc_txdat_data                      (rxbuf_rspenc_txdat_data                       ),
    .rspenc_rxbuf_ack                             (rspenc_rxbuf_ack                             ),
    .writeback_pending                            (writeback_pending),
    .rspenc_rxctrl_txreq_valid                    (rspenc_rxctrl_txreq_valid),                            
    .rspenc_rxctrl_txreq_txnid                    (rspenc_rxctrl_txreq_txnid),                  
    .rspenc_rxctrl_txreq_opcode                   (rspenc_rxctrl_txreq_opcode),                  
    .rspenc_rxctrl_txreq_size                     (rspenc_rxctrl_txreq_size),                  
    .rspenc_rxctrl_txreq_addr                     (rspenc_rxctrl_txreq_addr),                  
    .rspenc_rxctrl_txreq_tgtid                    (rspenc_rxctrl_txreq_tgtid),                  
    .rspenc_rxctrl_txreq_srcid                    (rspenc_rxctrl_txreq_srcid),                  
    .rspenc_rxctrl_txreq_snpattr                  (rspenc_rxctrl_txreq_snpattr),                      
    .rspenc_rxctrl_txreq_likelyshared             (rspenc_rxctrl_txreq_likelyshared),                          
    .rspenc_rxctrl_txreq_qos                      (rspenc_rxctrl_txreq_qos),                  
    .rspenc_rxctrl_txreq_returnnid                (rspenc_rxctrl_txreq_returnnid),                      
    .rspenc_rxctrl_txreq_returntxnid              (rspenc_rxctrl_txreq_returntxnid),                          
    .rspenc_rxctrl_txreq_ns                       (rspenc_rxctrl_txreq_ns),              
    .rspenc_rxctrl_txreq_allowretry               (rspenc_rxctrl_txreq_allowretry),                      
    .rspenc_rxctrl_txreq_order                    (rspenc_rxctrl_txreq_order),                  
    .rspenc_rxctrl_txreq_pcrdtype                 (rspenc_rxctrl_txreq_pcrdtype),                      
    .rspenc_rxctrl_txreq_memattr                  (rspenc_rxctrl_txreq_memattr),                      
    .rspenc_rxctrl_txreq_tracetag                 (rspenc_rxctrl_txreq_tracetag),      
    .rspenc_rxctrl_txreq_exclusive                (rspenc_rxctrl_txreq_exclusive), 
    .rspenc_rxctrl_txreq_endian                   (rspenc_rxctrl_txreq_endian),
    .rspenc_rxctrl_txreq_lpid                     (rspenc_rxctrl_txreq_lpid),
    .rspenc_rxctrl_txreq_expcompack               (rspenc_rxctrl_txreq_expcompack),   
    .rspenc_rxctrl_txreq_be                       (rspenc_rxctrl_txreq_be), 
    .rspenc_rxctrl_txreq_data                     (rspenc_rxctrl_txreq_data),               
    .rspenc_txreq_won                             (rspenc_txreq_won)  
);




// Translates cache requests to CHI-requests
txreq_encoder `RNF_PARAM_INST txreq_encoder(
    .clk(clk),
    .rst_n(rst_n),
    .noc1buffer_noc1encoder_req_data_0(noc1buffer_noc1encoder_req_data_0),
    .noc1buffer_noc1encoder_req_data_1(noc1buffer_noc1encoder_req_data_1),
    .noc1buffer_noc1encoder_req_val(noc1buffer_noc1encoder_req_val),
    .noc1buffer_noc1encoder_req_type(noc1buffer_noc1encoder_req_type),
    .noc1buffer_noc1encoder_req_mshrid(noc1buffer_noc1encoder_req_mshrid),
    .noc1buffer_noc1encoder_req_threadid(noc1buffer_noc1encoder_req_threadid),
    .noc1buffer_noc1encoder_req_address(noc1buffer_noc1encoder_req_address),
    .noc1buffer_noc1encoder_req_non_cacheable(noc1buffer_noc1encoder_req_non_cacheable),
    .noc1buffer_noc1encoder_req_size(noc1buffer_noc1encoder_req_size),
    .noc1buffer_noc1encoder_req_prefetch(noc1buffer_noc1encoder_req_prefetch),
    .noc1buffer_noc1encoder_req_csm_sdid(noc1buffer_noc1encoder_req_csm_sdid),
    .noc1buffer_noc1encoder_req_csm_lsid(noc1buffer_noc1encoder_req_csm_lsid),
    .noc1buffer_noc1encoder_req_homeid(noc1buffer_noc1encoder_req_homeid),
    
    .noc1encoder_noc1buffer_req_ack(noc1encoder_noc1buffer_req_ack),   

    // CHI
        // link protocol ports
    .noc1out_ready(txreq_encoder_crd_avail_s1),   
    .noc1encoder_noc1out_val(mshr_txreq_valid_sx1_q),  // noc packet valid to chi ports
    .atomic_data(txreq_enc_rxctrl_atomic_data),
        // flit fields
    .encoder_txreq_txnid_sx1_q       (mshr_txreq_txnid_sx1_q),
    .encoder_txreq_opcode_sx1        (mshr_txreq_opcode_sx1),
    .encoder_txreq_size_sx1          (mshr_txreq_size_sx1),
    .encoder_txreq_addr_sx1          (mshr_txreq_addr_sx1),
    .encoder_txreq_tgtid             (mshr_txreq_tgtid),
    .encoder_txreq_srcid             (mshr_txreq_srcid),
    .encoder_txreq_snpattr           (mshr_txreq_dodwt_sx1),                         // used as SnpAttr here
    .encoder_txreq_likelyshared      (encoder_txreq_likelyshared),                    // 
    .encoder_txreq_qos_sx1           (mshr_txreq_qos_sx1),
    .encoder_txreq_returnnid_sx1     (mshr_txreq_returnnid_sx1),
    .encoder_txreq_returntxnid_sx1   (mshr_txreq_returntxnid_sx1),
    .encoder_txreq_ns_sx1            (mshr_txreq_ns_sx1),         
    .encoder_txreq_allowretry_sx1    (mshr_txreq_allowretry_sx1),
    .encoder_txreq_order_sx1         (mshr_txreq_order_sx1),
    .encoder_txreq_pcrdtype_sx1      (mshr_txreq_pcrdtype_sx1),
    .encoder_txreq_memattr_sx1       (mshr_txreq_memattr_sx1),
    .encoder_txreq_tracetag_sx1      (mshr_txreq_tracetag_sx1),
    .encoder_txreq_reg_icache        (encoder_txreq_reg_icache),
    .encoder_txreq_exclusive         (encoder_txreq_exclusive),
    .encoder_txreq_endian            (encoder_txreq_endian           ),
    .encoder_txreq_lpid              (encoder_txreq_lpid             ),
    .encoder_txreq_expcompack        (encoder_txreq_expcompack       ),
    .txreq_enc_won_sx1               (txreq_enc_won_sx1),
    .receipt_received                (receipt_received),
    .requestregister_rdy             (requestregister_rdy)


);

wire tx_active_ready; 
reg tx_active_ready_r;

assign tx_active_ready = tx_active_ready_r;
// Assert the tx ready right after rst_n is lifted
always @ (posedge clk) begin
    if (~rst_n) 
        tx_active_ready_r <= 'b0;
    else 
        tx_active_ready_r <= 'b1;
        
end

/////////////////////////////////////////////////////////////////////////////////////////////////////////
// RNF link
/////////////////////////////////////////////////////////////////////////////////////////////////////////
// CHI TXRSP QoS retry-ack / credit-grant nets (driven by the MSHR QoS path).
// Declared at their CHIE flit-field widths to avoid implicit 1-bit nets.
wire [`CHIE_RSP_FLIT_QOS_WIDTH-1:0]      qos_txrsp_retryack_qos_s1;
wire [`CHIE_RSP_FLIT_TGTID_WIDTH-1:0]    qos_txrsp_retryack_tgtid_s1;
wire [`CHIE_RSP_FLIT_TXNID_WIDTH-1:0]    qos_txrsp_retryack_txnid_s1;
wire [`CHIE_RSP_FLIT_PCRDTYPE_WIDTH-1:0] qos_txrsp_retryack_pcrdtype_s1;
wire [`CHIE_RSP_FLIT_QOS_WIDTH-1:0]      qos_txrsp_pcrdgnt_qos_s2;
wire [`CHIE_RSP_FLIT_TGTID_WIDTH-1:0]    qos_txrsp_pcrdgnt_tgtid_s2;
wire [`CHIE_RSP_FLIT_PCRDTYPE_WIDTH-1:0] qos_txrsp_pcrdgnt_pcrdtype_s2;

    rnf_link `RNF_PARAM_INST rnf_link(
                 //inputs
                 .clk                                          (clk                               ),
                 .rst                                          (~rst_n                               ),
                 .rxrspflitv                                   (RXRSPFLITV                        ),
                 .rxrspflit                                    (RXRSPFLIT                         ),
                 .rxrspflitpend                                (RXRSPFLITPEND                     ),
                 .rxdatflitv                                   (RXDATFLITV                        ),
                 .rxdatflit                                    (RXDATFLIT                         ),
                 .rxdatflitpend                                (RXDATFLITPEND                     ),
                 .rxdat_buf_ready                               (rxdat_buf_ready),    // added for RNF
                 // TXREQ
                        // bypass ports
                 .txreq_lcrdv                                  (TXREQLCRDV                        ),
                 .mshr_txreq_bypass_valid_s1                       (rxbuf_txreq_bypass_valid_s1            ),
                 .mshr_txreq_bypass_qos_s1                         (rxbuf_txreq_bypass_qos_s1              ),
                 .mshr_txreq_bypass_txnid_s1                       (rxbuf_txreq_bypass_txnid_s1            ),
                 .mshr_txreq_bypass_returnnid_s1                   (rxbuf_txreq_bypass_returnnid_s1        ),
                 .mshr_txreq_bypass_returntxnid_s1                 (rxbuf_txreq_bypass_returntxnid_s1      ),
                 .mshr_txreq_bypass_opcode_s1                      (rxbuf_txreq_bypass_opcode_s1           ),
                 .mshr_txreq_bypass_size_s1                        (rxbuf_txreq_bypass_size_s1             ),
                 .mshr_txreq_bypass_addr_s1                        (rxbuf_txreq_bypass_addr_s1             ),
                 .mshr_txreq_bypass_ns_s1                          (rxbuf_txreq_bypass_ns_s1               ),
                 .mshr_txreq_bypass_allowretry_s1                  (rxbuf_txreq_bypass_allowretry_s1       ),
                 .mshr_txreq_bypass_order_s1                       (rxbuf_txreq_bypass_order_s1            ),
                 .mshr_txreq_bypass_pcrdtype_s1                    (rxbuf_txreq_bypass_pcrdtype_s1         ),
                 .mshr_txreq_bypass_memattr_s1                     (rxbuf_txreq_bypass_memattr_s1          ),
                 .mshr_txreq_bypass_dodwt_s1                       (rxbuf_txreq_bypass_dodwt_s1            ),
                 .mshr_txreq_bypass_tracetag_s1                    (rxbuf_txreq_bypass_tracetag_s1         ),
                 .mshr_txreq_bypass_tgtid                          (rxbuf_txreq_bypass_tgtid            ),
                 .mshr_txreq_bypass_srcid                          (rxbuf_txreq_bypass_srcid            ),
                 .txreq_bypass_likelyshared                        (rxbuf_txreq_bypass_likelyshared          ),
                 .txreq_bypass_exclusive                             (rxbuf_txreq_bypass_exclusive             ),
                 .txreq_bypass_endian                             (txreq_bypass_endian           ),
                 .txreq_bypass_lpid                               (txreq_bypass_lpid             ),
                 .txreq_bypass_expcompack                         (txreq_bypass_expcompack       ),
                        // general ports
                 .mshr_txreq_valid_sx1_q                       (mshr_txreq_valid_sx1_q            ),
                 .mshr_txreq_qos_sx1                           (mshr_txreq_qos_sx1),
                 .mshr_txreq_txnid_sx1_q                       (mshr_txreq_txnid_sx1_q),
                 .mshr_txreq_returnnid_sx1                     (mshr_txreq_returnnid_sx1),
                 .mshr_txreq_returntxnid_sx1                   (mshr_txreq_returntxnid_sx1),
                 .mshr_txreq_opcode_sx1                        (mshr_txreq_opcode_sx1             ),
                 .mshr_txreq_size_sx1                          (mshr_txreq_size_sx1               ),
                 .mshr_txreq_addr_sx1                          ( mshr_txreq_addr_sx1 ),
                 .mshr_txreq_ns_sx1                            (mshr_txreq_ns_sx1),               //atm there should not be nonsecure accesses             
                 .mshr_txreq_allowretry_sx1                    (mshr_txreq_allowretry_sx1),       //atm not supported
                 .mshr_txreq_order_sx1                         (mshr_txreq_order_sx1),            //this is required in specific CHI txs 
                 .mshr_txreq_pcrdtype_sx1                      (mshr_txreq_pcrdtype_sx1),                     
                 .mshr_txreq_memattr_sx1                       (mshr_txreq_memattr_sx1),
                 .mshr_txreq_dodwt_sx1                         (mshr_txreq_dodwt_sx1              ),    // This is also SnpAttr!!! No direct write transactions in CHI-B
                 .mshr_txreq_tracetag_sx1                      (mshr_txreq_tracetag_sx1),               
                 .mshr_txreq_tgtid                             (mshr_txreq_tgtid),                      // for RNF
                 .mshr_txreq_srcid                             (mshr_txreq_srcid),                      // for RNF
                 .encoder_txreq_likelyshared                   (encoder_txreq_likelyshared),            // for RNF
                 .encoder_txreq_exclusive                        (encoder_txreq_exclusive        ),
                 .encoder_txreq_endian                           (encoder_txreq_endian           ),
                 .encoder_txreq_lpid                             (encoder_txreq_lpid             ),
                 .encoder_txreq_expcompack                       (encoder_txreq_expcompack       ),
                 // TXRSP
                 .txrsp_lcrdv                                  (TXRSPLCRDV                        ),
                 .mshr_txrsp_bypass_valid_s1                       (encoder_txrsp_bypass_valid_s1            ),
                 .mshr_txrsp_bypass_qos_s1                         (encoder_txrsp_bypass_qos_s1              ),
                 .mshr_txrsp_bypass_tgtid_s1                       (encoder_txrsp_bypass_tgtid_s1            ),
                 .mshr_txrsp_bypass_txnid_s1                       (encoder_txrsp_bypass_txnid_s1            ),
                 .mshr_txrsp_bypass_opcode_s1                      (encoder_txrsp_bypass_opcode_s1           ),
                 .encoder_txrsp_bypass_resp                        (encoder_txrsp_bypass_resp                ),
                 .mshr_txrsp_bypass_resperr_s1                     (encoder_txrsp_bypass_resperr_s1          ),
                 .mshr_txrsp_bypass_dbid_s1                        (encoder_txrsp_bypass_dbid_s1             ),
                 .mshr_txrsp_bypass_tracetag_s1                    (encoder_txrsp_bypass_tracetag_s1         ),
                 .qos_txrsp_retryack_valid_s1                  (qos_txrsp_retryack_valid_s1       ),
                 .qos_txrsp_retryack_qos_s1                    (qos_txrsp_retryack_qos_s1         ),
                 .qos_txrsp_retryack_tgtid_s1                  (qos_txrsp_retryack_tgtid_s1       ),
                 .qos_txrsp_retryack_txnid_s1                  (qos_txrsp_retryack_txnid_s1       ),
                 .qos_txrsp_retryack_pcrdtype_s1               (qos_txrsp_retryack_pcrdtype_s1    ),
                 .qos_txrsp_retryack_tracetag_s1               (qos_txrsp_retryack_tracetag_s1    ),
                 .qos_txrsp_pcrdgnt_valid_s2                   (qos_txrsp_pcrdgnt_valid_s2        ),
                 .qos_txrsp_pcrdgnt_qos_s2                     (qos_txrsp_pcrdgnt_qos_s2          ),
                 .qos_txrsp_pcrdgnt_tgtid_s2                   (qos_txrsp_pcrdgnt_tgtid_s2        ),
                 .qos_txrsp_pcrdgnt_pcrdtype_s2                (qos_txrsp_pcrdgnt_pcrdtype_s2     ),
                 .mshr_txrsp_valid_sx1_q                       (noc2buffer_txrsp_valid_sx1_q            ),
                 .mshr_txrsp_qos_sx1                           (noc2buffer_txrsp_qos_sx1                ),
                 .mshr_txrsp_tgtid_sx1                         (noc2buffer_txrsp_tgtid_sx1              ),
                 .mshr_txrsp_txnid_sx1_q                       (noc2buffer_txrsp_txnid_sx1_q            ),
                 .mshr_txrsp_opcode_sx1                        (noc2buffer_txrsp_opcode_sx1             ),
                 .mshr_txrsp_resperr_sx1                       (noc2buffer_txrsp_resperr_sx1            ),
                 .mshr_txrsp_resp_sx1                          (noc2buffer_txrsp_resp_sx1               ),
                 .mshr_txrsp_dbid_sx1                          (noc2buffer_txrsp_dbid_sx1               ),
                 .mshr_txrsp_tracetag_sx1                      (noc2buffer_txrsp_tracetag_sx1           ),
                 // TXDAT
                 .txdat_lcrdv                                  (TXDATLCRDV                        ),
                 .encoder_txdat_qos                            (encoder_txdat_qos                 ),
                 .encoder_txdat_srcid                          (encoder_txdat_srcid               ),
                 .encoder_txdat_homenid                        (encoder_txdat_homenid             ),
                 .encoder_txdat_fwdstate                       (encoder_txdat_fwdstate            ),
                 .encoder_txdat_ccid                           (encoder_txdat_ccid                ),
                 .mshr_txdat_tgtid_sx2                         (mshr_txdat_tgtid_sx2              ),
                 .mshr_txdat_txnid_sx2                         (mshr_txdat_txnid_sx2              ),
                 .mshr_txdat_opcode_sx2                        (mshr_txdat_opcode_sx2             ),
                 .mshr_txdat_resp_sx2                          (mshr_txdat_resp_sx2               ),
                 .mshr_txdat_resperr_sx2                       (mshr_txdat_resperr_sx2            ),
                 .mshr_txdat_dbid_sx2                          (mshr_txdat_dbid_sx2               ),
                 .dbf_txdat_data_sx1                           (dbf_txdat_data_sx1                ),
                 .dbf_txdat_idx_sx1                            (dbf_txdat_idx_sx1                 ),
                 .dbf_txdat_be_sx1                             (dbf_txdat_be_sx1                  ),
                 .dbf_txdat_pe_sx1                             (dbf_txdat_pe_sx1                  ),
                 .dbf_txdat_valid_sx1                          (dbf_txdat_valid_sx1               ),

                 //outputs
                 // RXRSP
                 .rxrsp_lcrdv                                  (RXRSPLCRDV                        ),
                 .li_mshr_rxrsp_valid_s0                       (li_rxbuf_rxrsp_valid_s0            ),
                 .li_mshr_rxrsp_srcid_s0                       (li_rxbuf_rxrsp_srcid_s0            ),
                 .li_mshr_rxrsp_txnid_s0                       (li_rxbuf_rxrsp_txnid_s0            ),
                 .li_mshr_rxrsp_opcode_s0                      (li_rxbuf_rxrsp_opcode_s0           ),
                 .li_mshr_rxrsp_resp_s0                        (li_rxbuf_rxrsp_resp_s0             ),
                 .li_mshr_rxrsp_fwdstate_s0                    (li_rxbuf_rxrsp_fwdstate_s0         ),
                 .li_mshr_rxrsp_dbid_s0                        (li_rxbuf_rxrsp_dbid_s0             ),
                 .li_mshr_rxrsp_pcrdtype_s0                    (li_rxbuf_rxrsp_pcrdtype_s0         ),
                 .rxrsp_buf_ready                               (rxrsp_buf_ready                     ),
                 // RXDAT
                 .rxdat_lcrdv                                  (RXDATLCRDV                        ),
                 .li_mshr_rxdat_valid_s0                       (li_mshr_rxdat_valid_s0            ),
                 .li_mshr_rxdat_txnid_s0                       (li_mshr_rxdat_txnid_s0            ),
                 .li_mshr_rxdat_opcode_s0                      (li_mshr_rxdat_opcode_s0           ),
                 .li_mshr_rxdat_resp_s0                        (li_mshr_rxdat_resp_s0             ),
                 .li_mshr_rxdat_fwdstate_s0                    (li_mshr_rxdat_fwdstate_s0         ),
                 .li_mshr_rxdat_dataid_s0                      (li_mshr_rxdat_dataid_s0           ),
                 .li_dbf_rxdat_valid_s0                        (li_dbf_rxdat_valid_s0             ),
                 .li_dbf_rxdat_txnid_s0                        (li_dbf_rxdat_txnid_s0             ),
                 .li_dbf_rxdat_opcode_s0                       (li_dbf_rxdat_opcode_s0            ),
                 .li_dbf_rxdat_dataid_s0                       (li_dbf_rxdat_dataid_s0            ),
                 .li_dbf_rxdat_be_s0                           (li_dbf_rxdat_be_s0                ),
                 .li_dbf_rxdat_data_s0                         (li_dbf_rxdat_data_s0              ),
                 .li_decoder_rxdat_homenid                     (li_decoder_rxdat_homenid),        // added for RNF
                 .li_decoder_rxdat_ccid                        (li_decoder_rxdat_ccid),           // added for RNF
                 .li_decoder_rxdat_dbid                        (li_decoder_rxdat_dbid),           // added for RNF
                 // transmit channel signals
                 .txreqflitv                                   (TXREQFLITV                        ),
                 .txreqflit                                    (TXREQFLIT                         ),
                 .txreqflitpend                                (TXREQFLITPEND                     ),
                 .txrspflitv                                   (TXRSPFLITV                        ),
                 .txrspflit                                    (TXRSPFLIT                         ),
                 .txrspflitpend                                (TXRSPFLITPEND                     ),
                 .txrsp_mshr_retryack_won_s1                   (txrsp_mshr_retryack_won_s1        ),
                 .txrsp_mshr_pcrdgnt_won_s2                    (txrsp_mshr_pcrdgnt_won_s2         ),
                 .txrsp_cache_crd_avail                        (txrsp_cache_crd_avail),     // added for RNF 
                 .txrsp_mshr_won_sx1                           (txrsp_rxdat_buf_won_sx1           ),
                 .txreq_mshr_won_sx1                           (txreq_enc_won_sx1                ),
                 .txreq_encoder_crd_avail_s1                   (txreq_encoder_crd_avail_s1        ),
                 .txreq_mshr_bypass_won_s1                         (txreq_rxbuf_bypass_won_s1              ),
                 .txrsp_mshr_bypass_won_s1                         (txrsp_encoder_bypass_won_s1              ),
                 .txdatflitv                                   (TXDATFLITV                        ),
                 .txdatflit                                    (TXDATFLIT                         ),
                 .txdatflitpend                                (TXDATFLITPEND                     ),
                 .txdat_mshr_clr_dbf_busy_valid_sx3            (txdat_mshr_clr_dbf_busy_valid_sx3 ),
                 .txdat_mshr_clr_dbf_busy_idx_sx3              (txdat_mshr_clr_dbf_busy_idx_sx3   ),
                 .txdat_mshr_rd_idx_sx2                        (txdat_mshr_rd_idx_sx2             ),
                 .txdat_mshr_busy_sx                           (txdat_mshr_busy_sx                ),
                 // RXSNP I/O
                 .rxsnpflitv                                     (RXSNPFLITV                         ),
                 .rxsnpflit                                      (RXSNPFLIT                          ),
                 .rxsnpflitpend                                  (RXSNPFLITPEND                      ),
                 .rxsnp_decoder_valid_sx                         (rxsnp_decoder_valid_sx             ),
                 .rxsnp_decoder_qos                              (rxsnp_decoder_qos                  ),
                 .rxsnp_decoder_srcid                            (rxsnp_decoder_srcid                ),
                 .rxsnp_decoder_txnid                            (rxsnp_decoder_txnid                ),
                 .rxsnp_decoder_fwdnid                           (rxsnp_decoder_fwdnid               ),
                 .rxsnp_decoder_fwdtxnid                         (rxsnp_decoder_fwdtxnid             ),
                 .rxsnp_decoder_opcode                           (rxsnp_decoder_opcode               ),
                 .rxsnp_decoder_addr                             (rxsnp_decoder_addr                 ),
                 .rxsnp_decoder_ns                               (rxsnp_decoder_ns                   ),
                 .rxsnp_decoder_donotgotosd                      (rxsnp_decoder_donotgotosd          ),
                 .rxsnp_decoder_rettosrc                         (rxsnp_decoder_rettosrc             ),
                 .rxsnp_decoder_tracetag                         (rxsnp_decoder_tracetag             ),
                 .rxsnp_buf_ready                                 (rxsnp_buf_ready                     ),
                 .rxsnp_lcrdv                                    (RXSNPLCRDV                         ),

                // Link Layer handshake
                 .TXLINKACTIVEREQ                                (TXLINKACTIVEREQ),
                 .TXLINKACTIVEACK                                (TXLINKACTIVEACK),
                 .RXLINKACTIVEREQ                                (RXLINKACTIVEREQ),
                 .RXLINKACTIVEACK                                (RXLINKACTIVEACK),
                 .TXACTIVE                                       (TXACTIVE),
                 .RXACTIVE                                       (RXACTIVE),
                 .tx_active_ready                                (tx_active_ready)
             );


endmodule
