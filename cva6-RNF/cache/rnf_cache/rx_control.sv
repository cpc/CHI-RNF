/*
 * Copyright (c) 2026 Tampere University
 * Licensed under the Solderpad Hardware License v 2.1, see LICENSE for details.
 * SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
 */

//==================================================================================================
//  Filename   : rx_control
//  Author     : Teemu Rinne, Tampere University
//
//  Description     : RX-interface controller of AMBA CHI based RN-F coherent cache. 
//                      - Buffers for inbound RX-packets, intermediate request-register("MSHR"), 
//                         transaction control registers(FSM), TXREQ-bypass-multiplex 
//
//==================================================================================================



//`include "iop.h"
`include "l15.tmp.h"
`include "define.tmp.h"

`include "rnf_param.v"
`include "rnf_defines.v"
`include "chie_defines.v"

//`default_nettype none
module rx_control import wt_cache_pkg::*; `RNF_PARAM (
   input wire clk,
   input wire rst_n,
   input wire msg_ack,
   input wire msg_header_ack,
   // Widened to 576b: bits [63:0] hold OP message-info; bits [575:64] hold the
   // full 512b cacheline forwarded to the modified 64B L15 pipeline in one shot.
   output reg [575:0] msg,
   output reg msg_val,
   // Full-width CHI txnid of the snoop currently driving msg, forwarded
   // separately from msg so downstream stages don't have to recover it
   // from the truncated MSG_MSHRID field.
   output reg [`CHIE_SNP_FLIT_TXNID_WIDTH-1:0] rxctrl_l15_txnid,


// CHI
   // inputs from rxdat channel
   input wire                                       li_mshr_rxdat_valid_s0,
   input wire [`CHIE_DAT_FLIT_TXNID_WIDTH-1:0]      li_mshr_rxdat_txnid_s0,
   input wire [`CHIE_DAT_FLIT_OPCODE_WIDTH-1:0]     li_mshr_rxdat_opcode_s0,
   input wire [`CHIE_DAT_FLIT_RESP_WIDTH-1:0]       li_mshr_rxdat_resp_s0,
   input wire [`CHIE_DAT_FLIT_FWDSTATE_WIDTH-1:0]   li_mshr_rxdat_fwdstate_s0,
   input wire [`CHIE_DAT_FLIT_DATAID_WIDTH-1:0]     li_mshr_rxdat_dataid_s0,
   input wire [`CHIE_DAT_FLIT_HOMENID_WIDTH-1:0]    li_decoder_rxdat_homenid,
   input wire [`CHIE_DAT_FLIT_CCID_WIDTH-1:0]       li_decoder_rxdat_ccid,
   input wire [`CHIE_DAT_FLIT_DBID_WIDTH-1:0]       li_decoder_rxdat_dbid,
   input wire                                       li_dbf_rxdat_valid_s0,
   input wire [`CHIE_DAT_FLIT_TXNID_WIDTH-1:0]      li_dbf_rxdat_txnid_s0,
   input wire [`CHIE_DAT_FLIT_OPCODE_WIDTH-1:0]     li_dbf_rxdat_opcode_s0,
   input wire [`CHIE_DAT_FLIT_DATAID_WIDTH-1:0]     li_dbf_rxdat_dataid_s0,
   input wire [`CHIE_DAT_FLIT_BE_WIDTH-1:0]         li_dbf_rxdat_be_s0,
   input wire [`CHIE_DAT_FLIT_DATA_WIDTH-1:0]       li_dbf_rxdat_data_s0,
   // rxdat link control
   output wire                                      rxdat_buf_ready,
   
   // outputs to txrsp channel
   output wire                                        noc2buffer_txrsp_valid_sx1_q,
   output wire [`CHIE_RSP_FLIT_QOS_WIDTH-1:0]         noc2buffer_txrsp_qos_sx1,
   output wire [`CHIE_RSP_FLIT_TGTID_WIDTH-1:0]       noc2buffer_txrsp_tgtid_sx1,
   output wire [`CHIE_RSP_FLIT_TXNID_WIDTH-1:0]       noc2buffer_txrsp_txnid_sx1_q,
   output wire [`CHIE_RSP_FLIT_OPCODE_WIDTH-1:0]      noc2buffer_txrsp_opcode_sx1,
   output wire [`CHIE_RSP_FLIT_RESPERR_WIDTH-1:0]     noc2buffer_txrsp_resperr_sx1,
   output wire [`CHIE_RSP_FLIT_RESP_WIDTH-1:0]        noc2buffer_txrsp_resp_sx1,
   output wire [`CHIE_RSP_FLIT_DBID_WIDTH-1:0]        noc2buffer_txrsp_dbid_sx1,
   output wire [`CHIE_RSP_FLIT_TRACETAG_WIDTH-1:0]    noc2buffer_txrsp_tracetag_sx1,
   // txrsp link control
   input wire                                         txrsp_cache_crd_avail,
   input wire                                         txrsp_rxdat_buf_won_sx1,

   // rxsnp
   input wire                                         rxsnp_decoder_valid_sx,
   input wire [`CHIE_SNP_FLIT_QOS_WIDTH-1:0]          rxsnp_decoder_qos,
   input wire [`CHIE_SNP_FLIT_SRCID_WIDTH-1:0]        rxsnp_decoder_srcid,
   input wire [`CHIE_SNP_FLIT_TXNID_WIDTH-1:0]        rxsnp_decoder_txnid,
   input wire [`CHIE_SNP_FLIT_FWDNID_WIDTH-1:0]       rxsnp_decoder_fwdnid,
   input wire [`CHIE_SNP_FLIT_FWDTXNID_WIDTH-1:0]     rxsnp_decoder_fwdtxnid,
   input wire [`CHIE_SNP_FLIT_OPCODE_WIDTH-1:0]       rxsnp_decoder_opcode,
   input wire [`CHIE_SNP_FLIT_ADDR_WIDTH-1:0]         rxsnp_decoder_addr,
   input wire [`CHIE_SNP_FLIT_NS_WIDTH-1:0]           rxsnp_decoder_ns,
   input wire [`CHIE_SNP_FLIT_DONOTGOTOSD_WIDTH-1:0]  rxsnp_decoder_donotgotosd,
   input wire [`CHIE_SNP_FLIT_RETTOSRC_WIDTH-1:0]     rxsnp_decoder_rettosrc,
   input wire [`CHIE_SNP_FLIT_TRACETAG_WIDTH-1:0]     rxsnp_decoder_tracetag,
   // rxsnp link control
   output wire                                        rxsnp_buf_ready,

   // txreq
   output wire                                         rxbuf_txreq_bypass_valid,
   output wire [`CHIE_REQ_FLIT_QOS_WIDTH-1:0]          rxbuf_txreq_bypass_qos,
   output wire [`CHIE_REQ_FLIT_TXNID_WIDTH-1:0]        rxbuf_txreq_bypass_txnid,
   output wire [`CHIE_REQ_FLIT_RETURNNID_WIDTH-1:0]    rxbuf_txreq_bypass_returnnid,
   output wire [`CHIE_REQ_FLIT_RETURNTXNID_WIDTH-1:0]  rxbuf_txreq_bypass_returntxnid,
   output wire [`CHIE_REQ_FLIT_OPCODE_WIDTH-1:0]       rxbuf_txreq_bypass_opcode,
   output wire [`CHIE_REQ_FLIT_SIZE_WIDTH-1:0]         rxbuf_txreq_bypass_size,
   output wire [`CHIE_REQ_FLIT_ADDR_WIDTH-1:0]         rxbuf_txreq_bypass_addr,
   output wire [`CHIE_REQ_FLIT_NS_WIDTH-1:0]           rxbuf_txreq_bypass_ns,
   output wire [`CHIE_REQ_FLIT_ALLOWRETRY_WIDTH-1:0]   rxbuf_txreq_bypass_allowretry,
   output wire [`CHIE_REQ_FLIT_ORDER_WIDTH-1:0]        rxbuf_txreq_bypass_order,
   output wire [`CHIE_REQ_FLIT_PCRDTYPE_WIDTH-1:0]     rxbuf_txreq_bypass_pcrdtype,
   output wire [`CHIE_REQ_FLIT_MEMATTR_WIDTH-1:0]      rxbuf_txreq_bypass_memattr,
   output wire [`CHIE_REQ_FLIT_DODWT_WIDTH-1:0]        rxbuf_txreq_bypass_dodwt,
   output wire [`CHIE_REQ_FLIT_TRACETAG_WIDTH-1:0]     rxbuf_txreq_bypass_tracetag,
   output wire [`CHIE_REQ_FLIT_TGTID_WIDTH-1:0]        rxbuf_txreq_bypass_tgtid,
   output wire [`CHIE_REQ_FLIT_SRCID_WIDTH-1:0]        rxbuf_txreq_bypass_srcid,
   output wire [`CHIE_REQ_FLIT_LIKELYSHARED_WIDTH-1:0] rxbuf_txreq_bypass_likelyshared,
   output wire [`CHIE_REQ_FLIT_EXCL_WIDTH-1:0]         rxbuf_txreq_bypass_exclusive,
   output wire [`CHIE_REQ_FLIT_ENDIAN_WIDTH-1:0]       rxbuf_txreq_bypass_endian,
   output wire [`CHIE_REQ_FLIT_LPID_WIDTH-1:0]         rxbuf_txreq_bypass_lpid,
   output wire [`CHIE_REQ_FLIT_EXPCOMPACK_WIDTH-1:0]   rxbuf_txreq_bypass_expcompack,

   input wire                                          txreq_rxbuf_bypass_won,

   // rxrsp
   input wire                                         li_rxbuf_rxrsp_valid_s0,
   input wire [`CHIE_RSP_FLIT_SRCID_WIDTH-1:0]        li_rxbuf_rxrsp_srcid_s0,
   input wire [`CHIE_RSP_FLIT_TXNID_WIDTH-1:0]        li_rxbuf_rxrsp_txnid_s0,
   input wire [`CHIE_RSP_FLIT_OPCODE_WIDTH-1:0]       li_rxbuf_rxrsp_opcode_s0,
   input wire [`CHIE_RSP_FLIT_RESP_WIDTH-1:0]         li_rxbuf_rxrsp_resp_s0,
   input wire [`CHIE_RSP_FLIT_FWDSTATE_WIDTH-1:0]     li_rxbuf_rxrsp_fwdstate_s0,
   input wire [`CHIE_RSP_FLIT_DBID_WIDTH-1:0]         li_rxbuf_rxrsp_dbid_s0,
   input wire [`CHIE_RSP_FLIT_PCRDTYPE_WIDTH-1:0]     li_rxbuf_rxrsp_pcrdtype_s0,
   // rxrsp link control
   output wire                                         rxrsp_buf_ready,

   // txdat
   output wire                                         rxbuf_rspenc_txdat_valid,
   output wire [`CHIE_DAT_FLIT_QOS_WIDTH-1:0]          rxbuf_rspenc_txdat_qos,
   output wire [`CHIE_DAT_FLIT_SRCID_WIDTH-1:0]        rxbuf_rspenc_txdat_srcid,
   output wire [`CHIE_DAT_FLIT_TXNID_WIDTH-1:0]        rxbuf_rspenc_txdat_txnid,
   output wire [`CHIE_DAT_FLIT_OPCODE_WIDTH-1:0]       rxbuf_rspenc_txdat_opcode,
   output wire [`CHIE_DAT_FLIT_RESP_WIDTH-1:0]         rxbuf_rspenc_txdat_resp,
   output wire [`CHIE_DAT_FLIT_RESPERR_WIDTH-1:0]      rxbuf_rspenc_txdat_resperr,
   output wire [`CHIE_DAT_FLIT_FWDSTATE_WIDTH-1:0]     rxbuf_rspenc_txdat_fwdstate,
   output wire [`CHIE_DAT_FLIT_DATAID_WIDTH-1:0]       rxbuf_rspenc_txdat_dataid,
   output wire [`CHIE_DAT_FLIT_HOMENID_WIDTH-1:0]      rxbuf_rspenc_txdat_homenid,
   output wire [`CHIE_DAT_FLIT_CCID_WIDTH-1:0]         rxbuf_rspenc_txdat_ccid,
   output wire [`CHIE_DAT_FLIT_TGTID_WIDTH-1:0]        rxbuf_rspenc_txdat_tgtid,
   output wire [`CHIE_DAT_FLIT_DBID_WIDTH-1:0]         rxbuf_rspenc_txdat_dbid,
   output wire [`CHI_CACHE_BE_WIDTH-1:0]               rxbuf_rspenc_txdat_be,     // 512bit BE
   output wire [`CHI_CACHE_LINE_WIDTH-1:0]             rxbuf_rspenc_txdat_data,   // 512bit data
   input wire                                          rspenc_rxbuf_ack,

   // TXREQ to register
   input wire [127:0]                                 atomic_data,
   input wire                                         reqenc_txreq_valid,
   input wire [`CHIE_REQ_FLIT_TXNID_WIDTH-1:0]        reqenc_txreq_txnid,
   input wire [`CHIE_REQ_FLIT_OPCODE_WIDTH-1:0]       reqenc_txreq_opcode,
   input wire [`CHIE_REQ_FLIT_SIZE_WIDTH-1:0]         reqenc_txreq_size,
   input wire [`CHIE_REQ_FLIT_ADDR_WIDTH-1:0]         reqenc_txreq_addr,
   input wire [`CHIE_REQ_FLIT_TGTID_WIDTH-1:0]        reqenc_txreq_tgtid,
   input wire [`CHIE_REQ_FLIT_SRCID_WIDTH-1:0]        reqenc_txreq_srcid,
   input wire [`CHIE_REQ_FLIT_DODWT_WIDTH-1:0]        reqenc_txreq_snpattr,
   input wire [`CHIE_REQ_FLIT_LIKELYSHARED_WIDTH-1:0] reqenc_txreq_likelyshared,
   input wire [`CHIE_REQ_FLIT_QOS_WIDTH-1:0]          reqenc_txreq_qos,
   input wire [`CHIE_REQ_FLIT_RETURNNID_WIDTH-1:0]    reqenc_txreq_returnnid,
   input wire [`CHIE_REQ_FLIT_RETURNTXNID_WIDTH-1:0]  reqenc_txreq_returntxnid,
   input wire [`CHIE_REQ_FLIT_NS_WIDTH-1:0]           reqenc_txreq_ns,
   input wire [`CHIE_REQ_FLIT_ALLOWRETRY_WIDTH-1:0]   reqenc_txreq_allowretry,
   input wire [`CHIE_REQ_FLIT_ORDER_WIDTH-1:0]        reqenc_txreq_order,
   input wire [`CHIE_REQ_FLIT_PCRDTYPE_WIDTH-1:0]     reqenc_txreq_pcrdtype,
   input wire [`CHIE_REQ_FLIT_MEMATTR_WIDTH-1:0]      reqenc_txreq_memattr,
   input wire [`CHIE_REQ_FLIT_TRACETAG_WIDTH-1:0]     reqenc_txreq_tracetag,
   input wire [`CHIE_REQ_FLIT_EXCL_WIDTH-1:0]         reqenc_txreq_exclusive,
   input wire [`CHIE_REQ_FLIT_ENDIAN_WIDTH-1:0]       reqenc_txreq_endian,
   input wire [`CHIE_REQ_FLIT_LPID_WIDTH-1:0]         reqenc_txreq_lpid,
   input wire [`CHIE_REQ_FLIT_EXPCOMPACK_WIDTH-1:0]   reqenc_txreq_expcompack,
   input wire                                         reqenc_txreq_reg_icache,
   input wire                                         txreq_enc_won,
   output reg                                         receipt_received,
   output reg                                         requestregister_rdy,

   input wire                                         writeback_pending,
    // WriteBack TXREQ 
   input wire                                         rspenc_rxctrl_txreq_valid,
   input wire [`CHIE_REQ_FLIT_TXNID_WIDTH-1:0]        rspenc_rxctrl_txreq_txnid,
   input wire [`CHIE_REQ_FLIT_OPCODE_WIDTH-1:0]       rspenc_rxctrl_txreq_opcode,
   input wire [`CHIE_REQ_FLIT_SIZE_WIDTH-1:0]         rspenc_rxctrl_txreq_size,
   input wire [`CHIE_REQ_FLIT_ADDR_WIDTH-1:0]         rspenc_rxctrl_txreq_addr,
   input wire [`CHIE_REQ_FLIT_TGTID_WIDTH-1:0]        rspenc_rxctrl_txreq_tgtid,
   input wire [`CHIE_REQ_FLIT_SRCID_WIDTH-1:0]        rspenc_rxctrl_txreq_srcid,
   input wire [`CHIE_REQ_FLIT_DODWT_WIDTH-1:0]        rspenc_rxctrl_txreq_snpattr,
   input wire [`CHIE_REQ_FLIT_LIKELYSHARED_WIDTH-1:0] rspenc_rxctrl_txreq_likelyshared,
   input wire [`CHIE_REQ_FLIT_QOS_WIDTH-1:0]          rspenc_rxctrl_txreq_qos,
   input wire [`CHIE_REQ_FLIT_RETURNNID_WIDTH-1:0]    rspenc_rxctrl_txreq_returnnid,
   input wire [`CHIE_REQ_FLIT_RETURNTXNID_WIDTH-1:0]  rspenc_rxctrl_txreq_returntxnid,
   input wire [`CHIE_REQ_FLIT_NS_WIDTH-1:0]           rspenc_rxctrl_txreq_ns,
   input wire [`CHIE_REQ_FLIT_ALLOWRETRY_WIDTH-1:0]   rspenc_rxctrl_txreq_allowretry,
   input wire [`CHIE_REQ_FLIT_ORDER_WIDTH-1:0]        rspenc_rxctrl_txreq_order,
   input wire [`CHIE_REQ_FLIT_PCRDTYPE_WIDTH-1:0]     rspenc_rxctrl_txreq_pcrdtype,
   input wire [`CHIE_REQ_FLIT_MEMATTR_WIDTH-1:0]      rspenc_rxctrl_txreq_memattr,
   input wire [`CHIE_REQ_FLIT_TRACETAG_WIDTH-1:0]     rspenc_rxctrl_txreq_tracetag,  
   input wire [`CHIE_REQ_FLIT_EXCL_WIDTH-1:0]         rspenc_rxctrl_txreq_exclusive,     
   input wire [`CHIE_REQ_FLIT_ENDIAN_WIDTH-1:0]       rspenc_rxctrl_txreq_endian,
   input wire [`CHIE_REQ_FLIT_LPID_WIDTH-1:0]         rspenc_rxctrl_txreq_lpid,
   input wire [`CHIE_REQ_FLIT_EXPCOMPACK_WIDTH-1:0]   rspenc_rxctrl_txreq_expcompack,
   input wire [`CHI_CACHE_BE_WIDTH-1:0]               rspenc_rxctrl_txreq_be,     // 512bit BE
   input wire [`CHI_CACHE_LINE_WIDTH-1:0]             rspenc_rxctrl_txreq_data,   // 512bit data
   output reg                                         rspenc_txreq_won

   );

// This should be according to TXREQ-L-credits approved to be given for one RNF, meaning how many REQs RNF can do
   // For now 2xREQs=4x256bit RXDAT packets
localparam int datbufsize = `RNF_LCRD_RXDAT_MAX_VALUE;
localparam int datbufidx_w = $clog2(datbufsize);
localparam int rspbufsize = `RNF_LCRD_RXRSP_MAX_VALUE;
localparam int rspbufidx_w = $clog2(rspbufsize);
localparam int snpbufsize = `RNF_LCRD_RXSNP_MAX_VALUE;
localparam int snpbufidx_w = $clog2(snpbufsize);

// RXDAT buffer
reg [datbufidx_w-1:0]                     rxdat_buf_read_idx;
reg [datbufidx_w-1:0]                     rxdat_buf_store_idx;
reg                                       rxdat_consumed;
reg                                       rxdat_valid_buf [datbufsize-1:0];
reg [`CHIE_DAT_FLIT_TXNID_WIDTH-1:0]      rxdat_txnid_buf [datbufsize-1:0];
reg [`CHIE_DAT_FLIT_OPCODE_WIDTH-1:0]     rxdat_opcode_buf [datbufsize-1:0];
reg [`CHIE_DAT_FLIT_RESP_WIDTH-1:0]       rxdat_resp_buf [datbufsize-1:0];
reg [`CHIE_DAT_FLIT_FWDSTATE_WIDTH-1:0]   rxdat_fwdstate_buf [datbufsize-1:0];
reg [`CHIE_DAT_FLIT_DATAID_WIDTH-1:0]     rxdat_dataid_buf [datbufsize-1:0];
reg [`CHIE_DAT_FLIT_HOMENID_WIDTH-1:0]    rxdat_homenid_buf [datbufsize-1:0];
reg [`CHIE_DAT_FLIT_CCID_WIDTH-1:0]       rxdat_ccid_buf [datbufsize-1:0];
reg [`CHIE_DAT_FLIT_DBID_WIDTH-1:0]       rxdat_dbid_buf [datbufsize-1:0];
reg [`CHIE_DAT_FLIT_BE_WIDTH-1:0]         rxdat_be_buf [datbufsize-1:0];
reg [`CHIE_DAT_FLIT_DATA_WIDTH-1:0]       rxdat_data_buf [datbufsize-1:0];
// RXDAT register
reg                                       rxdat_valid_r;
reg [`CHIE_DAT_FLIT_TXNID_WIDTH-1:0]      rxdat_txnid_r;
reg [`CHIE_DAT_FLIT_OPCODE_WIDTH-1:0]     rxdat_opcode_r;
reg [`CHIE_DAT_FLIT_RESP_WIDTH-1:0]       rxdat_resp_r;
reg [`CHIE_DAT_FLIT_FWDSTATE_WIDTH-1:0]   rxdat_fwdstate_r;
reg [`CHIE_DAT_FLIT_DATAID_WIDTH-1:0]     rxdat_dataid_r;
reg [`CHIE_DAT_FLIT_HOMENID_WIDTH-1:0]    rxdat_homenid_r;
reg [`CHIE_DAT_FLIT_CCID_WIDTH-1:0]       rxdat_ccid_r;
reg [`CHIE_DAT_FLIT_DBID_WIDTH-1:0]       rxdat_dbid_r;
reg [`CHIE_DAT_FLIT_BE_WIDTH-1:0]         rxdat_be_r;
reg [`CHIE_DAT_FLIT_DATA_WIDTH-1:0]       rxdat_data_r;
// TXRSP
reg                                       txrsp_valid_r;
reg [`CHIE_RSP_FLIT_QOS_WIDTH-1:0]        txrsp_qos_r;
reg [`CHIE_RSP_FLIT_TGTID_WIDTH-1:0]      txrsp_tgtid_r;
reg [`CHIE_RSP_FLIT_TXNID_WIDTH-1:0]      txrsp_txnid_r;
reg [`CHIE_RSP_FLIT_OPCODE_WIDTH-1:0]     txrsp_opcode_r;
reg [`CHIE_RSP_FLIT_RESPERR_WIDTH-1:0]    txrsp_resperr_r;
reg [`CHIE_RSP_FLIT_RESP_WIDTH-1:0]       txrsp_resp_r;
reg [`CHIE_RSP_FLIT_DBID_WIDTH-1:0]       txrsp_dbid_r;
reg [`CHIE_RSP_FLIT_TRACETAG_WIDTH-1:0]   txrsp_tracetag_r;

// RXSNP buffer
reg [snpbufidx_w-1:0]                      rxsnp_buf_read_idx;
reg [snpbufidx_w-1:0]                      rxsnp_buf_store_idx;
reg                                        rxsnp_consumed;
reg                                        rxsnp_valid_buf [snpbufsize-1:0];
reg [`CHIE_SNP_FLIT_QOS_WIDTH-1:0]         rxsnp_qos_buf [snpbufsize-1:0];
reg [`CHIE_SNP_FLIT_SRCID_WIDTH-1:0]       rxsnp_srcid_buf[snpbufsize-1:0];
reg [`CHIE_SNP_FLIT_TXNID_WIDTH-1:0]       rxsnp_txnid_buf [snpbufsize-1:0];
reg [`CHIE_SNP_FLIT_FWDNID_WIDTH-1:0]      rxsnp_fwdnid_buf [snpbufsize-1:0];
reg [`CHIE_SNP_FLIT_FWDTXNID_WIDTH-1:0]    rxsnp_fwdtxnid_buf [snpbufsize-1:0];
reg [`CHIE_SNP_FLIT_OPCODE_WIDTH-1:0]      rxsnp_opcode_buf [snpbufsize-1:0];
reg [`CHIE_SNP_FLIT_ADDR_WIDTH-1:0]        rxsnp_addr_buf [snpbufsize-1:0];
reg [`CHIE_SNP_FLIT_NS_WIDTH-1:0]          rxsnp_ns_buf [snpbufsize-1:0];
reg [`CHIE_SNP_FLIT_DONOTGOTOSD_WIDTH-1:0] rxsnp_donotgotosd_buf [snpbufsize-1:0];
reg [`CHIE_SNP_FLIT_RETTOSRC_WIDTH-1:0]    rxsnp_rettosrc_buf [snpbufsize-1:0];
reg [`CHIE_SNP_FLIT_TRACETAG_WIDTH-1:0]    rxsnp_tracetag_buf [snpbufsize-1:0];
// RXSNP register
reg                                        rxsnp_valid_r;
reg [`CHIE_SNP_FLIT_QOS_WIDTH-1:0]         rxsnp_qos_r;
reg [`CHIE_SNP_FLIT_SRCID_WIDTH-1:0]       rxsnp_srcid_r;
reg [`CHIE_SNP_FLIT_TXNID_WIDTH-1:0]       rxsnp_txnid_r;
reg [`CHIE_SNP_FLIT_FWDNID_WIDTH-1:0]      rxsnp_fwdnid_r;
reg [`CHIE_SNP_FLIT_FWDTXNID_WIDTH-1:0]    rxsnp_fwdtxnid_r;
reg [`CHIE_SNP_FLIT_OPCODE_WIDTH-1:0]      rxsnp_opcode_r;
reg [`CHIE_SNP_FLIT_ADDR_WIDTH-1:0]        rxsnp_addr_r;
reg [`CHIE_SNP_FLIT_NS_WIDTH-1:0]          rxsnp_ns_r;
reg [`CHIE_SNP_FLIT_DONOTGOTOSD_WIDTH-1:0] rxsnp_donotgotosd_r;
reg [`CHIE_SNP_FLIT_RETTOSRC_WIDTH-1:0]    rxsnp_rettosrc_r;
reg [`CHIE_SNP_FLIT_TRACETAG_WIDTH-1:0]    rxsnp_tracetag_r;

// RXRSP buffer
reg [rspbufidx_w-1:0]                       rxrsp_buf_read_idx;
reg [rspbufidx_w-1:0]                       rxrsp_buf_store_idx;
reg                                         rxrsp_consumed;
reg                                         rxrsp_valid_buf[rspbufsize-1:0];
reg [`CHIE_RSP_FLIT_SRCID_WIDTH-1:0]        rxrsp_srcid_buf[rspbufsize-1:0];
reg [`CHIE_RSP_FLIT_TXNID_WIDTH-1:0]        rxrsp_txnid_buf[rspbufsize-1:0];
reg [`CHIE_RSP_FLIT_OPCODE_WIDTH-1:0]       rxrsp_opcode_buf[rspbufsize-1:0];
reg [`CHIE_RSP_FLIT_RESP_WIDTH-1:0]         rxrsp_resp_buf[rspbufsize-1:0];
reg [`CHIE_RSP_FLIT_FWDSTATE_WIDTH-1:0]     rxrsp_fwdstate_buf[rspbufsize-1:0];
reg [`CHIE_RSP_FLIT_DBID_WIDTH-1:0]         rxrsp_dbid_buf[rspbufsize-1:0];
reg [`CHIE_RSP_FLIT_PCRDTYPE_WIDTH-1:0]     rxrsp_pcrdtype_buf[rspbufsize-1:0];
// RXRSP register
reg                                         rxrsp_valid_r;
reg [`CHIE_RSP_FLIT_SRCID_WIDTH-1:0]        rxrsp_srcid_r;
reg [`CHIE_RSP_FLIT_TXNID_WIDTH-1:0]        rxrsp_txnid_r;
reg [`CHIE_RSP_FLIT_OPCODE_WIDTH-1:0]       rxrsp_opcode_r;
reg [`CHIE_RSP_FLIT_RESP_WIDTH-1:0]         rxrsp_resp_r;
reg [`CHIE_RSP_FLIT_FWDSTATE_WIDTH-1:0]     rxrsp_fwdstate_r;
reg [`CHIE_RSP_FLIT_DBID_WIDTH-1:0]         rxrsp_dbid_r;
reg [`CHIE_RSP_FLIT_PCRDTYPE_WIDTH-1:0]     rxrsp_pcrdtype_r;

// TXREQ bypass
reg                                         txreq_bypass_valid_r;
reg [`CHIE_REQ_FLIT_QOS_WIDTH-1:0]          txreq_bypass_qos_r;
reg [`CHIE_REQ_FLIT_TXNID_WIDTH-1:0]        txreq_bypass_txnid_r;
reg [`CHIE_REQ_FLIT_RETURNNID_WIDTH-1:0]    txreq_bypass_returnnid_r;
reg [`CHIE_REQ_FLIT_RETURNTXNID_WIDTH-1:0]  txreq_bypass_returntxnid_r;
reg [`CHIE_REQ_FLIT_OPCODE_WIDTH-1:0]       txreq_bypass_opcode_r;
reg [`CHIE_REQ_FLIT_SIZE_WIDTH-1:0]         txreq_bypass_size_r;
reg [`CHIE_REQ_FLIT_ADDR_WIDTH-1:0]         txreq_bypass_addr_r;
reg [`CHIE_REQ_FLIT_NS_WIDTH-1:0]           txreq_bypass_ns_r;
reg [`CHIE_REQ_FLIT_ALLOWRETRY_WIDTH-1:0]   txreq_bypass_allowretry_r;
reg [`CHIE_REQ_FLIT_ORDER_WIDTH-1:0]        txreq_bypass_order_r;
reg [`CHIE_REQ_FLIT_PCRDTYPE_WIDTH-1:0]     txreq_bypass_pcrdtype_r;
reg [`CHIE_REQ_FLIT_MEMATTR_WIDTH-1:0]      txreq_bypass_memattr_r;
reg [`CHIE_REQ_FLIT_DODWT_WIDTH-1:0]        txreq_bypass_dodwt_r;
reg [`CHIE_REQ_FLIT_TRACETAG_WIDTH-1:0]     txreq_bypass_tracetag_r;
reg [`CHIE_REQ_FLIT_TGTID_WIDTH-1:0]        txreq_bypass_tgtid_r;
reg [`CHIE_REQ_FLIT_SRCID_WIDTH-1:0]        txreq_bypass_srcid_r;
reg [`CHIE_REQ_FLIT_LIKELYSHARED_WIDTH-1:0] txreq_bypass_likelyshared_r;
reg [`CHIE_REQ_FLIT_EXCL_WIDTH-1:0]         txreq_bypass_exclusive_r;
reg [`CHIE_REQ_FLIT_ENDIAN_WIDTH-1:0]       txreq_bypass_endian_r;
reg [`CHIE_REQ_FLIT_LPID_WIDTH-1:0]         txreq_bypass_lpid_r;
reg [`CHIE_REQ_FLIT_EXPCOMPACK_WIDTH-1:0]   txreq_bypass_expcompack_r;
// TXDAT to response_encoder, for updating memory with received dirty data
reg                                         rxbuf_rspenc_txdat_valid_r;
reg [`CHIE_DAT_FLIT_QOS_WIDTH-1:0]          rxbuf_rspenc_txdat_qos_r;
reg [`CHIE_DAT_FLIT_SRCID_WIDTH-1:0]        rxbuf_rspenc_txdat_srcid_r;
reg [`CHIE_DAT_FLIT_TXNID_WIDTH-1:0]        rxbuf_rspenc_txdat_txnid_r;
reg [`CHIE_DAT_FLIT_OPCODE_WIDTH-1:0]       rxbuf_rspenc_txdat_opcode_r;
reg [`CHIE_DAT_FLIT_RESP_WIDTH-1:0]         rxbuf_rspenc_txdat_resp_r;
reg [`CHIE_DAT_FLIT_RESPERR_WIDTH-1:0]      rxbuf_rspenc_txdat_resperr_r;
reg [`CHIE_DAT_FLIT_FWDSTATE_WIDTH-1:0]     rxbuf_rspenc_txdat_fwdstate_r;
reg [`CHIE_DAT_FLIT_DATAID_WIDTH-1:0]       rxbuf_rspenc_txdat_dataid_r;
reg [`CHIE_DAT_FLIT_HOMENID_WIDTH-1:0]      rxbuf_rspenc_txdat_homenid_r;
reg [`CHIE_DAT_FLIT_CCID_WIDTH-1:0]         rxbuf_rspenc_txdat_ccid_r;
reg [`CHIE_DAT_FLIT_TGTID_WIDTH-1:0]        rxbuf_rspenc_txdat_tgtid_r;
reg [`CHIE_DAT_FLIT_DBID_WIDTH-1:0]         rxbuf_rspenc_txdat_dbid_r;    // added for RNF
reg [`CHI_CACHE_BE_WIDTH-1:0]               rxbuf_rspenc_txdat_be_r;
reg [`CHI_CACHE_LINE_WIDTH-1:0]             rxbuf_rspenc_txdat_data_r;

// control signals
reg                                             noc_in_rdy;
// Widened to 576b to match the new msg layout (header in [63:0], full 512b line in [575:64]).
reg [575:0]                                     msg_buffer;
reg                                             data_rdy_r;
reg [`RX_STATE_WIDTH-1:0]                     state;
reg [`RX_STATE_WIDTH-1:0]                     state_next;
reg                                             is_dirty;  
// Temporal cacheline accumulation storage (used for both clean and dirty lines):
//   wait_line_flit : keep draining buffered RXDAT flits of the in-flight TXNID
//   line_txnid     : TXNID currently being accumulated
//   line_data      : 512b cacheline accumulator (OR-merged across flits)
reg                                             wait_line_flit;
reg [`CHIE_DAT_FLIT_TXNID_WIDTH-1:0]            line_txnid;
reg [`CHI_CACHE_LINE_WIDTH-1:0]                 line_data;
reg [`CHI_CACHE_BE_WIDTH-1:0]                   line_be;
reg [`CHI_CACHE_LINE_WIDTH-1:0]                 line_data_next;
reg [`CHI_CACHE_BE_WIDTH-1:0]                   line_be_next;
reg                                             is_last_beat;
reg                                             dbid_received;
reg                                             sending_copybackwrdata;
reg                                             sending_noncopybackwrdata;
reg                                             sending_snprespdata;
reg                                             amo_data_response;
// Widened to 576b; snoop messages only populate headers in [63:0], data bits [575:64] are 0.
reg [575:0]                                     msg_buffer_rxsnp;
reg [`CHI_CACHE_LINE_WIDTH-1:0]                 atomic_data_r;
reg [`CHI_CACHE_BE_WIDTH-1:0]                   atomic_be_r;


// request_register signals
reg                                           txreq_valid;
reg                                           get_request;
reg                                           respsepdata_received;
reg                                           datasepresp_received;
reg                                           update_entry;
reg                                           evict_entry;
reg                                           check_snp_match;
reg                                           invalidate_wb_data;
reg [`CHIE_REQ_FLIT_TXNID_WIDTH-1:0]          search_txnid;
reg [`CHIE_SNP_FLIT_ADDR_WIDTH-1:0]           snp_addr;
reg [`CHIE_REQ_FLIT_TXNID_WIDTH-1:0]          txreq_txnid;
reg [`CHIE_REQ_FLIT_OPCODE_WIDTH-1:0]         txreq_opcode;
reg [`CHIE_REQ_FLIT_SIZE_WIDTH-1:0]           txreq_size;
reg [`CHIE_REQ_FLIT_ADDR_WIDTH-1:0]           txreq_addr;
reg [`CHIE_REQ_FLIT_DODWT_WIDTH-1:0]          txreq_snpattr;
reg [`CHIE_REQ_FLIT_QOS_WIDTH-1:0]            txreq_qos;
reg [`CHIE_REQ_FLIT_RETURNNID_WIDTH-1:0]      txreq_returnnid;
reg [`CHIE_REQ_FLIT_RETURNTXNID_WIDTH-1:0]    txreq_returntxnid;
reg [`CHIE_REQ_FLIT_NS_WIDTH-1:0]             txreq_ns;
reg [`CHIE_REQ_FLIT_ALLOWRETRY_WIDTH-1:0]     txreq_allowretry;
reg [`CHIE_REQ_FLIT_ORDER_WIDTH-1:0]          txreq_order;
reg [`CHIE_REQ_FLIT_PCRDTYPE_WIDTH-1:0]       txreq_pcrdtype;
reg [`CHIE_REQ_FLIT_MEMATTR_WIDTH-1:0]        txreq_memattr;
reg [`CHIE_REQ_FLIT_TRACETAG_WIDTH-1:0]       txreq_tracetag;
reg [`CHIE_REQ_FLIT_EXCL_WIDTH-1:0]           txreq_exclusive;
reg [`CHIE_REQ_FLIT_TGTID_WIDTH-1:0]          txreq_tgtid;
reg [`CHIE_REQ_FLIT_SRCID_WIDTH-1:0]          txreq_srcid;
reg [`CHIE_REQ_FLIT_LIKELYSHARED_WIDTH-1:0]   txreq_likelyshared;
reg [`CHIE_REQ_FLIT_ENDIAN_WIDTH-1:0]         txreq_endian;
reg [`CHIE_REQ_FLIT_LPID_WIDTH-1:0]           txreq_lpid;
reg [`CHIE_REQ_FLIT_EXPCOMPACK_WIDTH-1:0]     txreq_expcompack;
reg [`CHI_CACHE_LINE_WIDTH-1:0]               txreq_amo_data;
reg [`CHI_CACHE_BE_WIDTH-1:0]                 txreq_amo_be;
reg                                           txreq_icache;
reg                                           txreq_respsepdata;
reg                                           txreq_datasepresp;
reg [`CHIE_REQ_FLIT_TXNID_WIDTH-1:0]          req_txnid;
reg [`CHIE_REQ_FLIT_OPCODE_WIDTH-1:0]         req_opcode;
reg [`CHIE_REQ_FLIT_SIZE_WIDTH-1:0]           req_size;
reg [`CHIE_REQ_FLIT_ADDR_WIDTH-1:0]           req_addr;
reg [`CHIE_REQ_FLIT_DODWT_WIDTH-1:0]          req_snpattr;
reg [`CHIE_REQ_FLIT_QOS_WIDTH-1:0]            req_qos;
reg [`CHIE_REQ_FLIT_RETURNNID_WIDTH-1:0]      req_returnnid;
reg [`CHIE_REQ_FLIT_RETURNTXNID_WIDTH-1:0]    req_returntxnid;
reg [`CHIE_REQ_FLIT_NS_WIDTH-1:0]             req_ns;
reg [`CHIE_REQ_FLIT_ALLOWRETRY_WIDTH-1:0]     req_allowretry;
reg [`CHIE_REQ_FLIT_ORDER_WIDTH-1:0]          req_order;
reg [`CHIE_REQ_FLIT_PCRDTYPE_WIDTH-1:0]       req_pcrdtype;
reg [`CHIE_REQ_FLIT_MEMATTR_WIDTH-1:0]        req_memattr;
reg [`CHIE_REQ_FLIT_TRACETAG_WIDTH-1:0]       req_tracetag;
reg [`CHIE_REQ_FLIT_EXCL_WIDTH-1:0]           req_exclusive;
reg [`CHIE_REQ_FLIT_ENDIAN_WIDTH-1:0]         req_endian;
reg [`CHIE_REQ_FLIT_LPID_WIDTH-1:0]           req_lpid;
reg [`CHIE_REQ_FLIT_EXPCOMPACK_WIDTH-1:0]     req_expcompack;
reg [`CHIE_REQ_FLIT_TGTID_WIDTH-1:0]          req_tgtid;
reg [`CHIE_REQ_FLIT_SRCID_WIDTH-1:0]          req_srcid;
reg [`CHIE_REQ_FLIT_LIKELYSHARED_WIDTH-1:0]   req_likelyshared;
reg [`CHI_CACHE_LINE_WIDTH-1:0]               req_data;
reg [`CHI_CACHE_BE_WIDTH-1:0]                 req_be;
reg                                           req_icache;
reg                                           req_respsepdata_received;
reg                                           req_datasepresp_received;
// associated with req-register
reg                                           update_req_data;
reg                                           wb_address_match;
reg                                           pending_wb_match;



// CompAck signals to TXRSP
assign noc2buffer_txrsp_valid_sx1_q   = txrsp_valid_r;
assign noc2buffer_txrsp_qos_sx1       = txrsp_qos_r;
assign noc2buffer_txrsp_tgtid_sx1     = txrsp_tgtid_r;
assign noc2buffer_txrsp_txnid_sx1_q   = txrsp_txnid_r;
assign noc2buffer_txrsp_opcode_sx1    = txrsp_opcode_r;
assign noc2buffer_txrsp_resperr_sx1   = txrsp_resperr_r;
assign noc2buffer_txrsp_resp_sx1      = txrsp_resp_r;
assign noc2buffer_txrsp_dbid_sx1      = txrsp_dbid_r;
assign noc2buffer_txrsp_tracetag_sx1  = txrsp_tracetag_r;

// Write signals to TXREQ
assign rxbuf_txreq_bypass_valid           = txreq_bypass_valid_r;
assign rxbuf_txreq_bypass_qos             = txreq_bypass_qos_r;
assign rxbuf_txreq_bypass_txnid           = txreq_bypass_txnid_r;
assign rxbuf_txreq_bypass_returnnid       = txreq_bypass_returnnid_r;
assign rxbuf_txreq_bypass_returntxnid     = txreq_bypass_returntxnid_r;
assign rxbuf_txreq_bypass_opcode          = txreq_bypass_opcode_r;
assign rxbuf_txreq_bypass_size            = txreq_bypass_size_r;
assign rxbuf_txreq_bypass_addr            = txreq_bypass_addr_r;
assign rxbuf_txreq_bypass_ns              = txreq_bypass_ns_r;
assign rxbuf_txreq_bypass_allowretry      = txreq_bypass_allowretry_r;
assign rxbuf_txreq_bypass_order           = txreq_bypass_order_r;
assign rxbuf_txreq_bypass_pcrdtype        = txreq_bypass_pcrdtype_r;
assign rxbuf_txreq_bypass_memattr         = txreq_bypass_memattr_r;
assign rxbuf_txreq_bypass_dodwt           = txreq_bypass_dodwt_r;
assign rxbuf_txreq_bypass_tracetag        = txreq_bypass_tracetag_r;
assign rxbuf_txreq_bypass_tgtid           = txreq_bypass_tgtid_r;
assign rxbuf_txreq_bypass_srcid           = txreq_bypass_srcid_r;
assign rxbuf_txreq_bypass_likelyshared    = txreq_bypass_likelyshared_r;
assign rxbuf_txreq_bypass_exclusive       = txreq_bypass_exclusive_r;
assign rxbuf_txreq_bypass_endian          = txreq_bypass_endian_r;
assign rxbuf_txreq_bypass_lpid            = txreq_bypass_lpid_r;
assign rxbuf_txreq_bypass_expcompack      = txreq_bypass_expcompack_r;

// WrClFull:CopyBackWrData to response_encoder(txdat)
assign rxbuf_rspenc_txdat_valid = rxbuf_rspenc_txdat_valid_r;
assign rxbuf_rspenc_txdat_qos = rxbuf_rspenc_txdat_qos_r;
assign rxbuf_rspenc_txdat_srcid = rxbuf_rspenc_txdat_srcid_r;
assign rxbuf_rspenc_txdat_txnid = rxbuf_rspenc_txdat_txnid_r;
assign rxbuf_rspenc_txdat_opcode = rxbuf_rspenc_txdat_opcode_r;
assign rxbuf_rspenc_txdat_resp = rxbuf_rspenc_txdat_resp_r;
assign rxbuf_rspenc_txdat_resperr = rxbuf_rspenc_txdat_resperr_r;
assign rxbuf_rspenc_txdat_fwdstate = rxbuf_rspenc_txdat_fwdstate_r;
assign rxbuf_rspenc_txdat_dataid = rxbuf_rspenc_txdat_dataid_r;
assign rxbuf_rspenc_txdat_homenid = rxbuf_rspenc_txdat_homenid_r;
assign rxbuf_rspenc_txdat_ccid = rxbuf_rspenc_txdat_ccid_r;
assign rxbuf_rspenc_txdat_tgtid = rxbuf_rspenc_txdat_tgtid_r;
assign rxbuf_rspenc_txdat_dbid = rxbuf_rspenc_txdat_dbid_r;
assign rxbuf_rspenc_txdat_be = rxbuf_rspenc_txdat_be_r;
assign rxbuf_rspenc_txdat_data = rxbuf_rspenc_txdat_data_r;

request_register `RNF_PARAM_INST request_register(
   .clk(clk),
   .rst_n(rst_n),

   .txreq_valid               (txreq_valid),
   .get_request               (get_request),
   .update_entry              (update_entry),
   .evict_entry               (evict_entry),
   .check_snp_match           (check_snp_match),
   .invalidate_wb_data        (invalidate_wb_data),
   .snp_addr                  (snp_addr),
   .search_txnid              (search_txnid),
   .txreq_txnid               (txreq_txnid),     
   .txreq_opcode              (txreq_opcode),      
   .txreq_size                (txreq_size),        
   .txreq_addr                (txreq_addr),        
   .txreq_snpattr             (txreq_snpattr),
   .txreq_tgtid               (txreq_tgtid),           
   .txreq_srcid               (txreq_srcid),           
   .txreq_likelyshared        (txreq_likelyshared),
   .txreq_qos                 (txreq_qos),
   .txreq_returnnid           (txreq_returnnid),
   .txreq_returntxnid         (txreq_returntxnid),
   .txreq_ns                  (txreq_ns),
   .txreq_allowretry          (txreq_allowretry),
   .txreq_order               (txreq_order),
   .txreq_pcrdtype            (txreq_pcrdtype),
   .txreq_memattr             (txreq_memattr),
   .txreq_tracetag            (txreq_tracetag),
   .txreq_exclusive           (txreq_exclusive),
   .txreq_endian              (txreq_endian),
   .txreq_lpid                (txreq_lpid),
   .txreq_expcompack          (txreq_expcompack),
   .txreq_amo_data            (txreq_amo_data),
   .txreq_amo_be              (txreq_amo_be),         
   .txreq_icache              (txreq_icache),
   .txreq_respsepdata         (txreq_respsepdata),
   .txreq_datasepresp         (txreq_datasepresp),
   .req_valid                 (req_valid),
   .req_txnid                 (req_txnid),     
   .req_opcode                (req_opcode),      
   .req_size                  (req_size),        
   .req_addr                  (req_addr),        
   .req_snpattr               (req_snpattr),
   .req_tgtid                 (req_tgtid),           
   .req_srcid                 (req_srcid),           
   .req_likelyshared          (req_likelyshared),
   .req_qos                   (req_qos),
   .req_returnnid             (req_returnnid),
   .req_returntxnid           (req_returntxnid),
   .req_ns                    (req_ns),
   .req_allowretry            (req_allowretry),
   .req_order                 (req_order),
   .req_pcrdtype              (req_pcrdtype),
   .req_memattr               (req_memattr),
   .req_tracetag              (req_tracetag),
   .req_exclusive             (req_exclusive),
   .req_endian                (req_endian),
   .req_lpid                  (req_lpid),
   .req_expcompack            (req_expcompack),
   .req_data                  (req_data),
   .req_be                    (req_be),         
   .req_icache                (req_icache),
   .req_respsepdata_received  (req_respsepdata_received),
   .req_datasepresp_received  (req_datasepresp_received),
   .snp_match_found           (snp_match_found),
   .txreq_enc_won             (txreq_enc_won)
);



/////////////////////////////////////////////////////////////////////////////////////////////////////////
// INPUT BUFFERS
/////////////////////////////////////////////////////////////////////////////////////////////////////////

// Buffer state signal
assign rxrsp_buf_ready = (rxrsp_buf_read_idx == rxrsp_buf_store_idx && rxrsp_valid_buf[rxrsp_buf_store_idx] == 1'b1) ? 1'b0 : 
                        (rxrsp_buf_read_idx == rxrsp_buf_store_idx && rxrsp_valid_buf[rxrsp_buf_store_idx] == 1'b0) ? 1'b1 : 
                        (rxrsp_consumed) ? 1'b1 : 1'b0;

// RXRSP circular buffer
always @ (posedge clk)
begin
   if (~rst_n)
   begin
      //
      for (int i=0; i<rspbufsize; i=i+1) begin
         rxrsp_valid_buf[i] <= 'b0;
         rxrsp_srcid_buf[i] <= 'b0;
         rxrsp_txnid_buf[i] <= 'b0;
         rxrsp_opcode_buf[i] <= 'b0;
         rxrsp_resp_buf[i] <= 'b0;
         rxrsp_fwdstate_buf[i] <= 'b0;
         rxrsp_dbid_buf[i] <= 'b0;
         rxrsp_pcrdtype_buf[i] <= 'b0;
      end

      rxrsp_buf_store_idx <= 'b0;
      rxrsp_buf_read_idx <= 'b0;
      rxrsp_consumed <= 1'b0;

      rxrsp_valid_r <= 'b0;
      rxrsp_srcid_r <= 'b0;
      rxrsp_txnid_r <= 'b0;
      rxrsp_opcode_r <= 'b0;
      rxrsp_resp_r <= 'b0;
      rxrsp_fwdstate_r <= 'b0;
      rxrsp_dbid_r <= 'b0;
      rxrsp_pcrdtype_r <= 'b0;

   end
   else
   begin
      // RSP in
      if (li_rxbuf_rxrsp_valid_s0 == 1'b1) begin 
         if ((rxrsp_valid_buf[rxrsp_buf_store_idx] == 1'b0) || 
            (rxrsp_buf_store_idx == rxrsp_buf_read_idx && (noc_in_rdy == 1'b1 && rxdat_valid_buf[rxdat_buf_read_idx] == 1'b0) ))  begin
            rxrsp_valid_buf[rxrsp_buf_store_idx] <= li_rxbuf_rxrsp_valid_s0;
            rxrsp_srcid_buf[rxrsp_buf_store_idx] <= li_rxbuf_rxrsp_srcid_s0;
            rxrsp_txnid_buf[rxrsp_buf_store_idx] <= li_rxbuf_rxrsp_txnid_s0;
            rxrsp_opcode_buf[rxrsp_buf_store_idx] <= li_rxbuf_rxrsp_opcode_s0;
            rxrsp_resp_buf[rxrsp_buf_store_idx] <= li_rxbuf_rxrsp_resp_s0;
            rxrsp_fwdstate_buf[rxrsp_buf_store_idx] <= li_rxbuf_rxrsp_fwdstate_s0;
            rxrsp_dbid_buf[rxrsp_buf_store_idx] <= li_rxbuf_rxrsp_dbid_s0;
            rxrsp_pcrdtype_buf[rxrsp_buf_store_idx] <= li_rxbuf_rxrsp_pcrdtype_s0;

            if (rxrsp_buf_store_idx == rspbufsize-1) begin
               rxrsp_buf_store_idx <= 'd0;
            end else begin
               rxrsp_buf_store_idx <= rxrsp_buf_store_idx + 'd1;
            end
         end
      end

      // Response in if there is no pending rxdat flits and noc2 channel is free, or there is waiting to be received CompDBIDResp
      if ((noc_in_rdy == 1'b1 && rxdat_valid_buf[rxdat_buf_read_idx] == 1'b0)) begin
         if (rxrsp_valid_buf[rxrsp_buf_read_idx] == 1'b1) begin   
            rxrsp_valid_r <= rxrsp_valid_buf[rxrsp_buf_read_idx];
            rxrsp_srcid_r <= rxrsp_srcid_buf[rxrsp_buf_read_idx];
            rxrsp_txnid_r <= rxrsp_txnid_buf[rxrsp_buf_read_idx];
            rxrsp_opcode_r <= rxrsp_opcode_buf[rxrsp_buf_read_idx];
            rxrsp_resp_r <= rxrsp_resp_buf[rxrsp_buf_read_idx];
            rxrsp_fwdstate_r <= rxrsp_fwdstate_buf[rxrsp_buf_read_idx];
            rxrsp_dbid_r <= rxrsp_dbid_buf[rxrsp_buf_read_idx];
            rxrsp_pcrdtype_r <= rxrsp_pcrdtype_buf[rxrsp_buf_read_idx];

            if (!(rxrsp_buf_store_idx == rxrsp_buf_read_idx && li_rxbuf_rxrsp_valid_s0 == 1'b1)) begin
               rxrsp_valid_buf[rxrsp_buf_read_idx] <= 'b0;
               rxrsp_srcid_buf[rxrsp_buf_read_idx] <= 'b0;
               rxrsp_txnid_buf[rxrsp_buf_read_idx] <= 'b0;
               rxrsp_opcode_buf[rxrsp_buf_read_idx] <= 'b0;
               rxrsp_resp_buf[rxrsp_buf_read_idx] <= 'b0;
               rxrsp_fwdstate_buf[rxrsp_buf_read_idx] <= 'b0;
               rxrsp_dbid_buf[rxrsp_buf_read_idx] <= 'b0;
               rxrsp_pcrdtype_buf[rxrsp_buf_read_idx] <= 'b0;
            end

            if (rxrsp_buf_read_idx == rspbufsize-1) begin
               rxrsp_buf_read_idx <= 'd0;
            end else begin
               rxrsp_buf_read_idx <= rxrsp_buf_read_idx + 'd1;
            end

            rxrsp_consumed <= 1'b1;

         end else begin
            rxrsp_valid_r <= 1'b0;
            rxrsp_consumed <= 1'b0;
         end
      end 
      else if ( (state != `RX_STATE_IDLE) && state_next == `RX_STATE_IDLE) begin
         rxrsp_valid_r <= 1'b0;
         rxrsp_consumed <= 1'b0;
      end 
      else begin
         rxrsp_consumed <= 1'b0;
      end
   end
end


// Buffer state signal
assign rxsnp_buf_ready = (rxsnp_buf_store_idx == rxsnp_buf_read_idx && rxsnp_valid_buf[rxsnp_buf_store_idx] == 1'b1) ? 1'b0 : 
                        (rxsnp_buf_store_idx == rxsnp_buf_read_idx && rxsnp_valid_buf[rxsnp_buf_store_idx] == 1'b0) ? 1'b1 :
                        (rxsnp_consumed) ? 1'b1 : 1'b0;

// RXSNP circular buffer
always @ (posedge clk)
begin
   if (~rst_n)
   begin
      //
      for (int i=0; i<snpbufsize; i=i+1) begin
         rxsnp_valid_buf[i] <= 'b0;
         rxsnp_qos_buf[i] <= 'b0;
         rxsnp_srcid_buf[i] <= 'b0;
         rxsnp_txnid_buf[i] <= 'b0;
         rxsnp_fwdnid_buf[i] <= 'b0;
         rxsnp_fwdtxnid_buf[i] <= 'b0;
         rxsnp_opcode_buf[i] <= 'b0;
         rxsnp_addr_buf[i] <= 'b0;
         rxsnp_ns_buf[i] <= 'b0;
         rxsnp_donotgotosd_buf[i] <= 'b0;
         rxsnp_rettosrc_buf[i] <= 'b0;
         rxsnp_tracetag_buf[i] <= 'b0;
      end

      rxsnp_buf_store_idx <= 'b0;
      rxsnp_buf_read_idx <= 'b0;
      rxsnp_consumed <= 1'b0;

      rxsnp_valid_r <= 'b0;
      rxsnp_qos_r <= 'b0;
      rxsnp_srcid_r <= 'b0;
      rxsnp_txnid_r <= 'b0;
      rxsnp_fwdnid_r <= 'b0;
      rxsnp_fwdtxnid_r <= 'b0;
      rxsnp_opcode_r <= 'b0;
      rxsnp_addr_r <= 'b0;
      rxsnp_ns_r <= 'b0;
      rxsnp_donotgotosd_r <= 'b0;
      rxsnp_rettosrc_r <= 'b0;
      rxsnp_tracetag_r <= 'b0;

   end
   else
   begin
      // 
      if (rxsnp_decoder_valid_sx == 1'b1 && rxsnp_valid_buf[rxsnp_buf_store_idx] == 1'b0)  begin
         rxsnp_valid_buf[rxsnp_buf_store_idx] <= rxsnp_decoder_valid_sx;
         rxsnp_qos_buf[rxsnp_buf_store_idx] <= rxsnp_decoder_qos;
         rxsnp_srcid_buf[rxsnp_buf_store_idx] <= rxsnp_decoder_srcid;
         rxsnp_txnid_buf[rxsnp_buf_store_idx] <= rxsnp_decoder_txnid;
         rxsnp_fwdnid_buf[rxsnp_buf_store_idx] <= rxsnp_decoder_fwdnid;
         rxsnp_fwdtxnid_buf[rxsnp_buf_store_idx] <= rxsnp_decoder_fwdtxnid;
         rxsnp_opcode_buf[rxsnp_buf_store_idx] <= rxsnp_decoder_opcode;
         rxsnp_addr_buf[rxsnp_buf_store_idx] <= rxsnp_decoder_addr;
         rxsnp_ns_buf[rxsnp_buf_store_idx] <= rxsnp_decoder_ns;
         rxsnp_donotgotosd_buf[rxsnp_buf_store_idx] <= rxsnp_decoder_donotgotosd;
         rxsnp_rettosrc_buf[rxsnp_buf_store_idx] <= rxsnp_decoder_rettosrc;
         rxsnp_tracetag_buf[rxsnp_buf_store_idx] <= rxsnp_decoder_tracetag;
         
         if (rxsnp_buf_store_idx == snpbufsize-1) begin
            rxsnp_buf_store_idx <= 'd0;
         end else begin
            rxsnp_buf_store_idx <= rxsnp_buf_store_idx + 'd1;
         end
      end

      // Snoop in if there is no pending rxdat/rxrsp flits and noc2 channel is free
      if (noc_in_rdy == 1'b1 && rxdat_valid_buf[rxdat_buf_read_idx] == 1'b0 && rxrsp_valid_buf[rxrsp_buf_read_idx] == 1'b0) begin
         if (rxsnp_valid_buf[rxsnp_buf_read_idx] == 1'b1) begin
            rxsnp_valid_r <= rxsnp_valid_buf[rxsnp_buf_read_idx];
            rxsnp_qos_r <= rxsnp_qos_buf[rxsnp_buf_read_idx];
            rxsnp_srcid_r <= rxsnp_srcid_buf[rxsnp_buf_read_idx];
            rxsnp_txnid_r <= rxsnp_txnid_buf[rxsnp_buf_read_idx];
            rxsnp_fwdnid_r <= rxsnp_fwdnid_buf[rxsnp_buf_read_idx];
            rxsnp_fwdtxnid_r <= rxsnp_fwdtxnid_buf[rxsnp_buf_read_idx];
            rxsnp_opcode_r <= rxsnp_opcode_buf[rxsnp_buf_read_idx];
            rxsnp_addr_r <= rxsnp_addr_buf[rxsnp_buf_read_idx];
            rxsnp_ns_r <= rxsnp_ns_buf[rxsnp_buf_read_idx];
            rxsnp_donotgotosd_r <= rxsnp_donotgotosd_buf[rxsnp_buf_read_idx];
            rxsnp_rettosrc_r <= rxsnp_rettosrc_buf[rxsnp_buf_read_idx];
            rxsnp_tracetag_r <= rxsnp_tracetag_buf[rxsnp_buf_read_idx];

            if (!(rxsnp_buf_store_idx == rxsnp_buf_read_idx && rxsnp_decoder_valid_sx == 1'b1)) begin
               rxsnp_valid_buf[rxsnp_buf_read_idx] <= 'b0;
               rxsnp_qos_buf[rxsnp_buf_read_idx] <= 'b0;
               rxsnp_srcid_buf[rxsnp_buf_read_idx] <= 'b0;
               rxsnp_txnid_buf[rxsnp_buf_read_idx] <= 'b0;
               rxsnp_fwdnid_buf[rxsnp_buf_read_idx] <= 'b0;
               rxsnp_fwdtxnid_buf[rxsnp_buf_read_idx] <= 'b0;
               rxsnp_opcode_buf[rxsnp_buf_read_idx] <= 'b0;
               rxsnp_addr_buf[rxsnp_buf_read_idx] <= 'b0;
               rxsnp_ns_buf[rxsnp_buf_read_idx] <= 'b0;
               rxsnp_donotgotosd_buf[rxsnp_buf_read_idx] <= 'b0;
               rxsnp_rettosrc_buf[rxsnp_buf_read_idx] <= 'b0;
               rxsnp_tracetag_buf[rxsnp_buf_read_idx] <= 'b0;
            end

            if (rxsnp_buf_read_idx == snpbufsize-1) begin
               rxsnp_buf_read_idx <= 'd0;
            end else begin
               rxsnp_buf_read_idx <= rxsnp_buf_read_idx + 'd1;
            end

            rxsnp_consumed <= 1'b1;

         end else begin
            rxsnp_valid_r <= 'b0;
            rxsnp_consumed <= 1'b0;
         end
      end 
      else if (state != `RX_STATE_IDLE && state_next == `RX_STATE_IDLE) begin
         rxsnp_valid_r <= 'b0;
         rxsnp_consumed <= 1'b0;
      end
      else begin
         rxsnp_consumed <= 1'b0; 
      end
   end
end


// Buffer state signal
assign rxdat_buf_ready = (rxdat_buf_read_idx == rxdat_buf_store_idx && rxdat_valid_buf[rxdat_buf_store_idx] == 1'b1) ? 1'b0 :
                        (rxdat_buf_read_idx == rxdat_buf_store_idx && rxdat_valid_buf[rxdat_buf_store_idx] == 1'b0) ? 1'b1 : 
                        (rxdat_consumed) ? 1'b1 : 1'b0;

// RXDAT circular flit buffer
always @ (posedge clk)
begin
   if (~rst_n)
   begin
      //
      for (int i=0; i<datbufsize; i=i+1) begin
         rxdat_valid_buf[i] <= 'b0;
         rxdat_txnid_buf[i] <= 'b0;
         rxdat_opcode_buf[i] <= 'b0;
         rxdat_resp_buf[i] <= 'b0;
         rxdat_fwdstate_buf[i] <= 'b0;
         rxdat_dataid_buf[i] <= 'b0;
         rxdat_homenid_buf[i] <= 'b0;
         rxdat_ccid_buf[i] <= 'b0;
         rxdat_dbid_buf[i] <= 'b0;
         rxdat_be_buf[i] <= 'b0;
         rxdat_data_buf[i] <= 'b0;
      end

      rxdat_buf_store_idx <= 'b0;
      rxdat_buf_read_idx <= 'b0;
      rxdat_consumed <= 1'b0;

      rxdat_valid_r <= 'b0;
      rxdat_txnid_r <= 'b0;
      rxdat_opcode_r <= 'b0;
      rxdat_resp_r <= 'b0;
      rxdat_fwdstate_r <= 'b0;
      rxdat_dataid_r <= 'b0;
      rxdat_homenid_r <= 'b0;
      rxdat_ccid_r <= 'b0;
      rxdat_dbid_r <= 'b0;
      rxdat_be_r <= 'b0;
      rxdat_data_r <= 'b0;

   end
   else
   begin
      // rxdat flit in if buffer empty and coming flit is valid
      if ( li_mshr_rxdat_valid_s0 == 1'b1 ) begin 
         // Take flit in if buffer is not full or it is read at the same time
         if ( rxdat_valid_buf[rxdat_buf_store_idx] == 1'b0 || 
               (rxdat_buf_store_idx == rxdat_buf_read_idx && noc_in_rdy == 1'b1 || wait_line_flit == 1'b1) ) begin

            rxdat_valid_buf[rxdat_buf_store_idx] <= li_mshr_rxdat_valid_s0;
            rxdat_txnid_buf[rxdat_buf_store_idx] <= li_mshr_rxdat_txnid_s0;
            rxdat_opcode_buf[rxdat_buf_store_idx] <= li_mshr_rxdat_opcode_s0;
            rxdat_resp_buf[rxdat_buf_store_idx] <= li_mshr_rxdat_resp_s0;
            rxdat_fwdstate_buf[rxdat_buf_store_idx] <= li_mshr_rxdat_fwdstate_s0;
            rxdat_dataid_buf[rxdat_buf_store_idx] <= li_mshr_rxdat_dataid_s0;
            rxdat_homenid_buf[rxdat_buf_store_idx] <= li_decoder_rxdat_homenid;
            rxdat_ccid_buf[rxdat_buf_store_idx] <= li_decoder_rxdat_ccid;
            rxdat_dbid_buf[rxdat_buf_store_idx] <= li_decoder_rxdat_dbid;
            rxdat_be_buf[rxdat_buf_store_idx] <= li_dbf_rxdat_be_s0;
            rxdat_data_buf[rxdat_buf_store_idx] <= li_dbf_rxdat_data_s0;

            if (rxdat_buf_store_idx == datbufsize-1) begin
               rxdat_buf_store_idx <= 'd0;
            end else begin
               rxdat_buf_store_idx <= rxdat_buf_store_idx + 'd1;
            end
         end
      end 

      // Take RXDAT flit from buffer if channel to decoder is free
      if ( (noc_in_rdy == 1'b1 || wait_line_flit == 1'b1) && rxsnp_valid_r == 1'b0 && rxrsp_valid_r == 1'b0) begin

         if ( (noc_in_rdy == 1'b1 || (wait_line_flit == 1'b1 && 
               (req_txnid == rxdat_txnid_buf[rxdat_buf_read_idx] || (rxdat_txnid_r == rxdat_txnid_buf[rxdat_buf_read_idx] && state == `RX_STATE_IDLE)))) && 
               rxdat_valid_buf[rxdat_buf_read_idx] == 1'b1) begin

            rxdat_valid_r <= rxdat_valid_buf[rxdat_buf_read_idx];
            rxdat_txnid_r <= rxdat_txnid_buf[rxdat_buf_read_idx];
            rxdat_opcode_r <= rxdat_opcode_buf[rxdat_buf_read_idx];
            rxdat_resp_r <= rxdat_resp_buf[rxdat_buf_read_idx];
            rxdat_fwdstate_r <= rxdat_fwdstate_buf[rxdat_buf_read_idx];
            rxdat_dataid_r <= rxdat_dataid_buf[rxdat_buf_read_idx];
            rxdat_homenid_r <= rxdat_homenid_buf[rxdat_buf_read_idx];
            rxdat_ccid_r <= rxdat_ccid_buf[rxdat_buf_read_idx];
            rxdat_dbid_r <= rxdat_dbid_buf[rxdat_buf_read_idx];
            rxdat_be_r <= rxdat_be_buf[rxdat_buf_read_idx];
            rxdat_data_r <= rxdat_data_buf[rxdat_buf_read_idx];

            if (!(rxdat_buf_store_idx == rxdat_buf_read_idx && li_mshr_rxdat_valid_s0 == 1'b1)) begin
               rxdat_valid_buf[rxdat_buf_read_idx] <= 'b0;
               rxdat_txnid_buf[rxdat_buf_read_idx] <= 'b0;
               rxdat_opcode_buf[rxdat_buf_read_idx] <= 'b0;
               rxdat_resp_buf[rxdat_buf_read_idx] <= 'b0;
               rxdat_fwdstate_buf[rxdat_buf_read_idx] <= 'b0;
               rxdat_dataid_buf[rxdat_buf_read_idx] <= 'b0;
               rxdat_homenid_buf[rxdat_buf_read_idx] <= 'b0;
               rxdat_ccid_buf[rxdat_buf_read_idx] <= 'b0;
               rxdat_dbid_buf[rxdat_buf_read_idx] <= 'b0;
               rxdat_be_buf[rxdat_buf_read_idx] <= 'b0;
               rxdat_data_buf[rxdat_buf_read_idx] <= 'b0;
            end

            if (rxdat_buf_read_idx == datbufsize-1) begin
               rxdat_buf_read_idx <= 'd0;
            end else begin
               rxdat_buf_read_idx <= rxdat_buf_read_idx + 'd1;
            end

            rxdat_consumed <= 1'b1;

         end 
         else begin  // 
            rxdat_consumed <= 1'b0;
         end
      end 
      else if (state != `RX_STATE_IDLE && state_next == `RX_STATE_IDLE) begin
         rxdat_valid_r <= 'b0;
         rxdat_consumed <= 1'b0;
      end
      else begin
         rxdat_consumed <= 1'b0;
      end


   end
end

reg msg_header_ack_received;
reg msg_header_ack_received_last;

// ack received from l15-pipeline for acknowledgement that msg is being processed
assign msg_header_ack_received = (msg_header_ack) ? 1'b1 : msg_header_ack_received_last;

always @ (posedge clk)
begin
   if (~rst_n)
   begin
      state <= 0;
      msg_header_ack_received_last <= 1'b0;
   end
   else
   begin
      state <= state_next;

      if (msg_ack) begin
         msg_header_ack_received_last <= 1'b0;
      end else begin
         msg_header_ack_received_last <= msg_header_ack_received;
      end
   end
end


assign search_txnid        = (rxdat_valid_r) ? rxdat_txnid_r : (rxrsp_valid_r) ? rxrsp_txnid_r : 'b0;
assign get_request         = ((rxdat_valid_r || rxrsp_valid_r) && !(state_next == `RX_STATE_IDLE)) ? 1'b1 : 1'b0;
assign check_snp_match     = (rxsnp_valid_r);
assign snp_addr            = (rxsnp_valid_r) ? rxsnp_addr_r : 'b0;

assign pending_wb_match    = (rxsnp_valid_r && writeback_pending && rspenc_rxctrl_txreq_addr[`CHIE_REQ_FLIT_ADDR_WIDTH-1:6] == rxsnp_addr_r[`CHIE_SNP_FLIT_ADDR_WIDTH-1:3]);

assign wb_address_match    = (check_snp_match && (snp_match_found || pending_wb_match));
assign invalidate_wb_data  = (check_snp_match && snp_match_found);

/////////////////////////////////////////////////////////////////////////////////////////////////////////
// STATE MACHINE
/////////////////////////////////////////////////////////////////////////////////////////////////////////

// State machine logic for incoming CHI RX-packets and propagating them to L1.5
always @ *
begin
   msg_val = 0;
   state_next = 0;
   noc_in_rdy = 1'b0;
   txrsp_valid_r = 1'b0; 
   wait_line_flit = 1'b0;
   rxbuf_rspenc_txdat_valid_r = 1'b0;
   evict_entry = 1'b0;
   sending_copybackwrdata = 1'b0;
   sending_noncopybackwrdata = 1'b0;
   sending_snprespdata = 1'b0;
   receipt_received = 1'b0;
   respsepdata_received = 1'b0;
   datasepresp_received = 1'b0;
   update_entry = 1'b0;
   update_req_data = 1'b0;

// IDLE: Check incoming RX-packets
   if (state == `RX_STATE_IDLE)
   begin
      noc_in_rdy = 1'b1;

      if (rxdat_valid_r) begin

         if (CHIE_DATA_WIDTH_PARAM == 'd128 || CHIE_DATA_WIDTH_PARAM == 'd256) begin
            // Move to gather rest of the cacheline
            state_next = `RX_STATE_RECEIVING_DATA;
            noc_in_rdy = 1'b0;
            wait_line_flit = 1'b1;
         end else begin
            // full cacheline received
            noc_in_rdy = 1'b0;
            state_next = `RX_STATE_WAITING_ACK;
         end

      end else if (rxrsp_valid_r) begin
         noc_in_rdy = 1'b0;
         state_next = `RX_STATE_REQ_CHECK;
      end else if (rxsnp_valid_r) begin
         noc_in_rdy = 1'b0;
         //state_next = `RX_STATE_WAITING_SNP_ACK;
         state_next = `RX_STATE_REQ_CHECK;    // check possibly conflictin WriteBacks
      end
   end

// REQ_CHECK: Check request information first for RSP-packets, also done with 128-bit DAT-packets
   else if (state == `RX_STATE_REQ_CHECK)
   begin
      noc_in_rdy = 1'b0;
      
      // If WB/address collision is found
      if (rxsnp_valid_r) begin
         if (wb_address_match) begin
            state_next = `RX_STATE_SEND_DATA; // send CHIE_SNPRESPDATA I_PD
         end else begin
            state_next = `RX_STATE_WAITING_SNP_ACK;
         end       
      end
      else if (rxrsp_valid_r) begin
         if (req_valid) begin
            if (dbid_received) begin
               // Check the REQ request-opcode for the DBID
               case (req_opcode)
                  `CHIE_WRITEBACKPTL, `CHIE_WRITEBACKFULL, `CHIE_WRITECLEANFULL:
                  begin
                     state_next = `RX_STATE_SEND_DATA;
                  end
                  `CHIE_ATOMICLOAD_ADD, `CHIE_ATOMICLOAD_CLR, `CHIE_ATOMICLOAD_EOR, 
                  `CHIE_ATOMICLOAD_SET, `CHIE_ATOMICLOAD_SMAX, `CHIE_ATOMICLOAD_UMAX, 
                  `CHIE_ATOMICLOAD_SMIN, `CHIE_ATOMICLOAD_UMIN, `CHIE_ATOMICSWAP, `CHIE_WRITENOSNPPTL:
                  begin
                     state_next = `RX_STATE_SEND_NC_DATA;
                  end
               endcase
               if (req_order != 'b0) begin
                  receipt_received = 1'b1;
               end
            end
            else if (rxrsp_opcode_r == `CHIE_COMP) begin
               if (req_opcode == `CHIE_CLEANUNIQUE || req_opcode == `CHIE_WRITENOSNPPTL) begin
                  state_next = `RX_STATE_WAITING_ACK;
               end
            end
            else if (rxrsp_opcode_r == `CHIE_READRECEIPT) begin
               if (req_order != 'b0) begin
                  receipt_received = 1'b1;
               end 
               state_next = `RX_STATE_IDLE;
            end
            else if (rxrsp_opcode_r == `CHIE_RESPSEPDATA) begin
               if (req_order != 'b0) begin
                  receipt_received = 1'b1;
               end 
               if (req_datasepresp_received == 1'b1) begin
                  state_next = `RX_STATE_WAIT_CHI_TXRSP;  // send CompAck
               end else begin
                  update_entry = 1'b1;
                  respsepdata_received = 1'b1;
                  state_next = `RX_STATE_IDLE;
               end
            end
         end 
         else begin
            // stuck here if req not found
            state_next = `RX_STATE_REQ_CHECK;
         end
      end 
   end

// RECEIVING DATA: Receive a DAT-packet and check if there is more for the same txnid in buffers
   else if (state == `RX_STATE_RECEIVING_DATA) begin
      noc_in_rdy = 1'b0;
      wait_line_flit = 1'b1;
      if (rxdat_valid_r)
      begin

         if (req_valid) begin
            if (is_last_beat) begin // if cacheline is fully received
               wait_line_flit = 1'b0;
               state_next = `RX_STATE_WAITING_ACK;
            end else if (rxdat_valid_buf[rxdat_buf_read_idx] && rxdat_txnid_buf[rxdat_buf_read_idx] == rxdat_txnid_r) begin // take in next packet if txnids match
               state_next = `RX_STATE_RECEIVING_DATA;
            end else begin // go to IDLE
               // Accumulate cacheline to registers
               update_entry = 1'b1;
               update_req_data = 1'b1;
               wait_line_flit = 1'b0;
               state_next = `RX_STATE_IDLE;
            end
         end else begin // wait for request to be fetched
               wait_line_flit = 1'b0;
               state_next = `RX_STATE_RECEIVING_DATA;
         end
         
      end else begin
         state_next = `RX_STATE_RECEIVING_DATA;
      end
   end

// WAITING ACK: Wait for acknowledgement to be receive from L1.5 for the sent message
   // Send CompAck response if the received data wasn't for AMO
   else if (state == `RX_STATE_WAITING_ACK)
   begin
      noc_in_rdy = 1'b0;
      state_next = `RX_STATE_WAITING_ACK;

      if (req_valid) begin 
         msg_val = 1'b1;
         if (msg_ack)
         begin

            if (rxdat_valid_r) begin
               // make CompAck after CompData, unless its REQ was Atomic
               if (!amo_data_response) begin

                  // Do not send CompAck if RESPSEPDATA is not received yet for the request
                  if (rxdat_opcode_r == `CHIE_DATASEPRESP && !req_respsepdata_received) begin 
                     update_entry = 1'b1;
                     datasepresp_received = 1'b1;
                     state_next = `RX_STATE_IDLE;
                  // TXRSP was not propagated from interface
                  end else begin
                     txrsp_valid_r = 1'b1;
                     if (!txrsp_rxdat_buf_won_sx1) begin     
                        state_next = `RX_STATE_WAIT_CHI_TXRSP;
                     // rsp was sent, evict REQ entry
                     end else begin         
                        evict_entry = 1'b1;
                        state_next = `RX_STATE_IDLE;
                     end
                  end 

               end else begin
                  // Evict atomic request when CompData is received
                  evict_entry = 1'b1;
                  state_next = `RX_STATE_IDLE;
               end

            end else if (rxrsp_valid_r) begin
               txrsp_valid_r = (req_opcode == `CHIE_WRITENOSNPPTL) ? 1'b0 : 1'b1;

               // TXRSP was not propagated from interface, and the response wasnt for WriteNoSnp (with CleanUnique CompAck is sent)
               if (!txrsp_rxdat_buf_won_sx1 && !(req_opcode == `CHIE_WRITENOSNPPTL)) begin     
                  state_next = `RX_STATE_WAIT_CHI_TXRSP;
               // rsp was sent, evict REQ entry
               end else begin         
                  evict_entry = 1'b1;
                  state_next = `RX_STATE_IDLE;
               end
            end

         end 
      end
   end


// WAITING ACK: Wait for acknowledgement to be receive from L1.5 for the sent message
   else if (state == `RX_STATE_WAITING_SNP_ACK)
   begin
      noc_in_rdy = 1'b0;
      msg_val = 1'b1;
      if (msg_ack)
      begin
        state_next = `RX_STATE_IDLE;
      end
      else if (pending_wb_match && !msg_header_ack_received) 
      begin
         msg_val = 1'b0;
         state_next = `RX_STATE_SEND_DATA;
      end
      else
         state_next = `RX_STATE_WAITING_SNP_ACK;
   end



// WAIT CHI TXRSP: Wait for acknowledgement for the sent CHI-CompAck message from the TXRSP interface
   else if (state == `RX_STATE_WAIT_CHI_TXRSP)
   begin
      noc_in_rdy = 1'b0;
      txrsp_valid_r = 1'b1;
      if (txrsp_rxdat_buf_won_sx1)
      begin
         // No need for buffer flush or dirty cacheline waits as all data is propagated to l15
         evict_entry = 1'b1;   
         state_next = `RX_STATE_IDLE;

      end 
      else begin
         state_next = `RX_STATE_WAIT_CHI_TXRSP;
      end
   end

// SEND COPYBACK DATA: Sends copyback data to the hnf when a DBID has been received
   // Send snprespdata if there is a SNP/WriteBack collision
   else if (state == `RX_STATE_SEND_DATA)
   begin
      noc_in_rdy = 1'b0;
      sending_copybackwrdata = rxrsp_valid_r;
      sending_snprespdata = rxsnp_valid_r;

      if ( ((rxrsp_valid_r || (rxsnp_valid_r && snp_match_found)) && req_valid) || 
            (rxsnp_valid_r && pending_wb_match) ) begin
         rxbuf_rspenc_txdat_valid_r = 1'b1;
         if (rspenc_rxbuf_ack) begin   
            evict_entry = (rxrsp_valid_r) ? 1'b1 : 1'b0;
            state_next = `RX_STATE_IDLE; 
         end else begin
            state_next = `RX_STATE_SEND_DATA;
         end
      end else begin
            state_next = `RX_STATE_SEND_DATA;
      end

   end


// SEND NON-COPYBACK DATA: Sends non-copyback data to the hnf when a DBID has been received
   else if (state == `RX_STATE_SEND_NC_DATA)
   begin
      noc_in_rdy = 1'b0;
      sending_noncopybackwrdata = 1'b1;

      if (req_valid) begin
         rxbuf_rspenc_txdat_valid_r = 1'b1;
         if (rspenc_rxbuf_ack) begin 
            state_next = `RX_STATE_IDLE; 
         end else begin
            state_next = `RX_STATE_SEND_NC_DATA;
         end
      end else begin
            state_next = `RX_STATE_SEND_NC_DATA;
      end

   end

end



/////////////////////////////////////////////////////////////////////////////////////////////////////////
// PACKETS TO CACHE
/////////////////////////////////////////////////////////////////////////////////////////////////////////

// Combinational
// Translated packet propagation in case of correct data
always @ *
begin

   txrsp_qos_r       = 'b0;
   txrsp_tgtid_r     = 'b0;
   txrsp_txnid_r     = 'b0;
   txrsp_resperr_r   = 'b0;
   txrsp_resp_r      = 'b0;
   txrsp_dbid_r      = 'b0;
   txrsp_tracetag_r  = 'b0;
   msg = 'b0;

   if (data_rdy_r == 1'b1 && rxdat_valid_r == 1'b1) begin
      // Forward the full 576b message: 64b header word + 512b cacheline ([575:64]).
      msg[(0+1)*64 - 1 -: 64] = msg_buffer[(0+1)*64 - 1 -: 64];
      msg[(1+1)*64 - 1 -: 64] = msg_buffer[(1+1)*64 - 1 -: 64];
      msg[(2+1)*64 - 1 -: 64] = msg_buffer[(2+1)*64 - 1 -: 64];
      msg[(3+1)*64 - 1 -: 64] = msg_buffer[(3+1)*64 - 1 -: 64];
      msg[(4+1)*64 - 1 -: 64] = msg_buffer[(4+1)*64 - 1 -: 64];
      msg[(5+1)*64 - 1 -: 64] = msg_buffer[(5+1)*64 - 1 -: 64];
      msg[(6+1)*64 - 1 -: 64] = msg_buffer[(6+1)*64 - 1 -: 64];
      msg[(7+1)*64 - 1 -: 64] = msg_buffer[(7+1)*64 - 1 -: 64];
      msg[(8+1)*64 - 1 -: 64] = msg_buffer[(8+1)*64 - 1 -: 64];

      txrsp_qos_r       = 0;
      txrsp_tgtid_r     = rxdat_homenid_r;
      txrsp_txnid_r     = rxdat_dbid_r;
      txrsp_resperr_r   = 2'b00;
      txrsp_resp_r      = {`CHIE_RSP_FLIT_RESP_WIDTH{1'b0}};
      txrsp_dbid_r      = {`CHIE_RSP_FLIT_DBID_WIDTH{1'b0}};
      txrsp_tracetag_r  = {`CHIE_RSP_FLIT_TRACETAG_WIDTH{1'b0}};
   end
   else if (rxdat_valid_r == 1'b0 && rxsnp_valid_r == 1'b1) begin
      // Snoop forward: headers only (bits [63:0]); data field [575:64] stays 0.
      msg[(0+1)*64 - 1 -: 64] = msg_buffer_rxsnp[(0+1)*64 - 1 -: 64];
      msg[(1+1)*64 - 1 -: 64] = msg_buffer_rxsnp[(1+1)*64 - 1 -: 64];
      msg[(2+1)*64 - 1 -: 64] = msg_buffer_rxsnp[(2+1)*64 - 1 -: 64];
      msg[(3+1)*64 - 1 -: 64] = msg_buffer_rxsnp[(3+1)*64 - 1 -: 64];
      msg[(4+1)*64 - 1 -: 64] = msg_buffer_rxsnp[(4+1)*64 - 1 -: 64];
      msg[(5+1)*64 - 1 -: 64] = msg_buffer_rxsnp[(5+1)*64 - 1 -: 64];
      msg[(6+1)*64 - 1 -: 64] = msg_buffer_rxsnp[(6+1)*64 - 1 -: 64];
      msg[(7+1)*64 - 1 -: 64] = msg_buffer_rxsnp[(7+1)*64 - 1 -: 64];
      msg[(8+1)*64 - 1 -: 64] = msg_buffer_rxsnp[(8+1)*64 - 1 -: 64];
   end else if (rxrsp_valid_r == 1'b1) begin
      // RXRSP (no data response): only header-word [63:0] carries content.
      msg[(0+1)*64 - 1 -: 64] = msg_buffer[(0+1)*64 - 1 -: 64];
      msg[(1+1)*64 - 1 -: 64] = msg_buffer[(1+1)*64 - 1 -: 64];
      msg[(2+1)*64 - 1 -: 64] = msg_buffer[(2+1)*64 - 1 -: 64];
      msg[(3+1)*64 - 1 -: 64] = msg_buffer[(3+1)*64 - 1 -: 64];
      msg[(4+1)*64 - 1 -: 64] = msg_buffer[(4+1)*64 - 1 -: 64];
      msg[(5+1)*64 - 1 -: 64] = msg_buffer[(5+1)*64 - 1 -: 64];
      msg[(6+1)*64 - 1 -: 64] = msg_buffer[(6+1)*64 - 1 -: 64];
      msg[(7+1)*64 - 1 -: 64] = msg_buffer[(7+1)*64 - 1 -: 64];
      msg[(8+1)*64 - 1 -: 64] = msg_buffer[(8+1)*64 - 1 -: 64];

      txrsp_qos_r       = 0;
      txrsp_tgtid_r     = HNF_NID_PARAM;
      txrsp_txnid_r     = rxrsp_txnid_r;
      txrsp_resperr_r   = 2'b00;
      txrsp_resp_r      = {`CHIE_RSP_FLIT_RESP_WIDTH{1'b0}};
      txrsp_dbid_r      = {`CHIE_RSP_FLIT_DBID_WIDTH{1'b0}};
      txrsp_tracetag_r  = {`CHIE_RSP_FLIT_TRACETAG_WIDTH{1'b0}};
   end

   
end


/////////////////////////////////////////////////////////////////////////////////////////////////////////
// MEMORY UPDATE PACKET PROPAGATION
/////////////////////////////////////////////////////////////////////////////////////////////////////////

// WriteCleanFull memory update logic
always @ *
begin

   rspenc_txreq_won = 1'b0;
   txreq_bypass_valid_r = 'b0;
   txreq_bypass_opcode_r = 'b0;
   txreq_bypass_qos_r = 'b0;
   txreq_bypass_txnid_r = 'b0;
   txreq_bypass_returnnid_r = 'b0;
   txreq_bypass_returntxnid_r = 'b0;
   txreq_bypass_size_r = 'b0;
   txreq_bypass_addr_r = 'b0;
   txreq_bypass_ns_r = 'b0;
   txreq_bypass_allowretry_r = 'b0;
   txreq_bypass_order_r = 'b0;
   txreq_bypass_pcrdtype_r = 'b0;
   txreq_bypass_memattr_r = 'b0;
   txreq_bypass_dodwt_r = 'b0;
   txreq_bypass_tracetag_r = 'b0;
   txreq_bypass_srcid_r = 'b0;
   txreq_bypass_tgtid_r = 'b0;
   txreq_bypass_likelyshared_r = 'b0;
   txreq_bypass_exclusive_r = 'b0;
   txreq_bypass_endian_r = 'b0;
   txreq_bypass_lpid_r = 'b0;
   txreq_bypass_expcompack_r = 'b0;

   // In case of received dirty data and it has to be updated back to next level cache
   if (rspenc_rxctrl_txreq_valid == 1'b1) begin
      // For WriteBack request from response_encoder(OP-NoC3)
      txreq_bypass_valid_r = (requestregister_rdy && !pending_wb_match) ? rspenc_rxctrl_txreq_valid : 'b0;
      txreq_bypass_opcode_r = rspenc_rxctrl_txreq_opcode;
      txreq_bypass_qos_r  = rspenc_rxctrl_txreq_qos;
      txreq_bypass_txnid_r = rspenc_rxctrl_txreq_txnid;
      txreq_bypass_returnnid_r   = rspenc_rxctrl_txreq_returnnid;
      txreq_bypass_returntxnid_r = rspenc_rxctrl_txreq_returntxnid;
      txreq_bypass_size_r  = rspenc_rxctrl_txreq_size;
      txreq_bypass_addr_r  = rspenc_rxctrl_txreq_addr;
      txreq_bypass_ns_r = rspenc_rxctrl_txreq_ns;
      txreq_bypass_allowretry_r  = rspenc_rxctrl_txreq_allowretry;
      txreq_bypass_order_r = rspenc_rxctrl_txreq_order;
      txreq_bypass_pcrdtype_r = rspenc_rxctrl_txreq_pcrdtype;
      txreq_bypass_memattr_r = rspenc_rxctrl_txreq_memattr;
      txreq_bypass_dodwt_r = 0;
      txreq_bypass_tracetag_r = rspenc_rxctrl_txreq_tracetag;
      txreq_bypass_srcid_r = rspenc_rxctrl_txreq_srcid;
      txreq_bypass_tgtid_r = rspenc_rxctrl_txreq_tgtid;
      txreq_bypass_likelyshared_r = rspenc_rxctrl_txreq_likelyshared;
      txreq_bypass_exclusive_r = rspenc_rxctrl_txreq_exclusive;
      txreq_bypass_endian_r = rspenc_rxctrl_txreq_endian;
      txreq_bypass_lpid_r = rspenc_rxctrl_txreq_lpid;
      txreq_bypass_expcompack_r = rspenc_rxctrl_txreq_expcompack;

      // Issue the writeback or "ack" it if there is collision with snoop
      if (txreq_rxbuf_bypass_won == 1'b1 || (rspenc_rxbuf_ack && rxsnp_valid_r && pending_wb_match)) begin
         rspenc_txreq_won = 1'b1;
      end else begin 
         rspenc_txreq_won = 1'b0;
      end
      
   end
end

always @ *
begin

    rxbuf_rspenc_txdat_qos_r      = 'b0;
    rxbuf_rspenc_txdat_srcid_r    = 'b0;
    rxbuf_rspenc_txdat_txnid_r    = 'b0;
    rxbuf_rspenc_txdat_opcode_r   = 'b0;
    rxbuf_rspenc_txdat_resp_r     = 'b0;
    rxbuf_rspenc_txdat_resperr_r  = 'b0;
    rxbuf_rspenc_txdat_fwdstate_r = 'b0;
    rxbuf_rspenc_txdat_dataid_r   = 'b0;
    rxbuf_rspenc_txdat_homenid_r  = 'b0;
    rxbuf_rspenc_txdat_ccid_r     = 'b0;
    rxbuf_rspenc_txdat_tgtid_r    = 'b0;
    rxbuf_rspenc_txdat_dbid_r     = 'b0;
    rxbuf_rspenc_txdat_be_r       = 'b0;
    rxbuf_rspenc_txdat_data_r     = 'b0;

   // Send data, initiated by Writes or AtomicLoad transactions
   if (rxbuf_rspenc_txdat_valid_r == 1'b1) begin  
      if (sending_copybackwrdata) begin  
         rxbuf_rspenc_txdat_qos_r      = 'h1;
         rxbuf_rspenc_txdat_srcid_r    = RNF_NID;
         rxbuf_rspenc_txdat_txnid_r    = rxrsp_dbid_r;
         rxbuf_rspenc_txdat_opcode_r   = `CHIE_COPYBACKWRDATA;
         rxbuf_rspenc_txdat_resp_r     = (|req_be) ? `CHIE_WRDATA_RESP_UD_PD : `CHIE_WRDATA_RESP_I;
         rxbuf_rspenc_txdat_resperr_r  = 'b0;
         rxbuf_rspenc_txdat_fwdstate_r = 3'b000;               // aplicable only in forwarded snp responses, otherwise must be 0
         rxbuf_rspenc_txdat_dataid_r   = 2'b11;                // txdat_wrap determines this correctly when sending different pieces of data
         rxbuf_rspenc_txdat_homenid_r  = HNF_NID_PARAM;
         rxbuf_rspenc_txdat_ccid_r     = req_addr[5:4];         // Critical Chunk ID, from txreq register
         rxbuf_rspenc_txdat_tgtid_r    = HNF_NID_PARAM;
         rxbuf_rspenc_txdat_dbid_r     = 'b0;                  // not sure about this as there is nothing about the case of CopyBackWrData   
         rxbuf_rspenc_txdat_be_r       = req_be;
         rxbuf_rspenc_txdat_data_r     = (|req_be) ? req_data : {`CHI_CACHE_LINE_WIDTH{1'b0}};
      end 
      else if (sending_noncopybackwrdata) begin
         rxbuf_rspenc_txdat_qos_r      = `RNF_QOS_CLASS_HIGH;
         rxbuf_rspenc_txdat_srcid_r    = RNF_NID;
         rxbuf_rspenc_txdat_txnid_r    = rxrsp_dbid_r;
         rxbuf_rspenc_txdat_opcode_r   = `CHIE_NONCOPYBACKWRDATA;
         rxbuf_rspenc_txdat_resp_r     = `CHIE_WRDATA_RESP_I;
         rxbuf_rspenc_txdat_resperr_r  = 'b0;
         rxbuf_rspenc_txdat_fwdstate_r = 3'b000;               // aplicable only in forwarded snp responses, otherwise must be 0
         rxbuf_rspenc_txdat_dataid_r   = 2'b11;                // txdat_wrap determines this correctly when sending different pieces of data
         rxbuf_rspenc_txdat_homenid_r  = HNF_NID_PARAM;
         rxbuf_rspenc_txdat_ccid_r     = req_addr[5:4];         // Critical Chunk ID, from txreq register
         rxbuf_rspenc_txdat_tgtid_r    = HNF_NID_PARAM;
         rxbuf_rspenc_txdat_dbid_r     = 'b0;  
         rxbuf_rspenc_txdat_be_r       = req_be;  
         rxbuf_rspenc_txdat_data_r     = req_data;             // GET FROM THE TXREQ_ENC
      end else if (sending_snprespdata) begin
         rxbuf_rspenc_txdat_qos_r      = `RNF_QOS_CLASS_HIGH;
         rxbuf_rspenc_txdat_srcid_r    = RNF_NID;
         rxbuf_rspenc_txdat_txnid_r    = rxsnp_txnid_r;
         rxbuf_rspenc_txdat_opcode_r   = `CHIE_SNPRESPDATA;
         rxbuf_rspenc_txdat_resp_r     = `CHIE_SNP_RESP_I_PD;
         rxbuf_rspenc_txdat_resperr_r  = 'b0;
         rxbuf_rspenc_txdat_fwdstate_r = 3'b000;               // aplicable only in forwarded snp responses, otherwise must be 0
         rxbuf_rspenc_txdat_dataid_r   = 2'b11;
         rxbuf_rspenc_txdat_homenid_r  = HNF_NID_PARAM;
         rxbuf_rspenc_txdat_ccid_r     = rxsnp_addr_r[2:1];    // snp-flit includes address[ADDRW-1 : 3]
         rxbuf_rspenc_txdat_tgtid_r    = HNF_NID_PARAM;
         rxbuf_rspenc_txdat_dbid_r     = 'b0;                  // No stash snoops enabled
         rxbuf_rspenc_txdat_be_r       = {`CHI_CACHE_BE_WIDTH{1'b1}};
         rxbuf_rspenc_txdat_data_r     = (pending_wb_match) ? line_data : req_data;       
            // ONGELMA: jos rspencistä wb tulossa => ei voida lähettää txdataa, koska logiikka samassa FSMssä... erillinenn mux rspenciin
      end
   end 

end


/////////////////////////////////////////////////////////////////////////////////////////////////////////
// TXREQ REGISTER
/////////////////////////////////////////////////////////////////////////////////////////////////////////

// TXREQ request registration
always @ *
begin

   txreq_respsepdata = 'b0;
   txreq_datasepresp = 'b0;

   requestregister_rdy = ~update_entry;

   // 
   if (update_entry) begin
      txreq_valid = 1'b0;
      txreq_txnid = req_txnid;
      txreq_opcode = req_opcode;
      txreq_size = req_size;
      txreq_addr = req_addr;
      txreq_tgtid = req_tgtid;
      txreq_srcid = req_srcid;
      txreq_snpattr = req_snpattr;
      txreq_likelyshared = req_likelyshared;
      txreq_qos = req_qos;
      txreq_returnnid = req_returnnid;
      txreq_returntxnid = req_returntxnid;
      txreq_ns = req_ns;
      txreq_allowretry = req_allowretry;
      txreq_order = req_order;
      txreq_pcrdtype = req_pcrdtype;
      txreq_memattr = req_memattr;
      txreq_tracetag = req_tracetag;
      txreq_exclusive = req_exclusive;
      txreq_endian = req_endian;
      txreq_lpid = req_lpid;
      txreq_expcompack = req_expcompack;
      txreq_amo_data = (update_req_data) ? line_data_next : req_data;
      txreq_amo_be = (update_req_data) ? line_be_next : req_be;
      txreq_icache = req_icache;
      txreq_respsepdata = (respsepdata_received) ? 1'b1 : req_respsepdata_received;
      txreq_datasepresp = (datasepresp_received) ? 1'b1 : req_datasepresp_received;



   end
   else if (reqenc_txreq_valid == 1'b1 && txreq_enc_won == 1'b1) begin
      txreq_valid = reqenc_txreq_valid;
      txreq_txnid = reqenc_txreq_txnid;
      txreq_opcode = reqenc_txreq_opcode;
      txreq_size = reqenc_txreq_size;
      txreq_addr = reqenc_txreq_addr;
      txreq_tgtid = reqenc_txreq_tgtid;
      txreq_srcid = reqenc_txreq_srcid;
      txreq_snpattr = reqenc_txreq_snpattr;
      txreq_likelyshared = reqenc_txreq_likelyshared;
      txreq_qos = reqenc_txreq_qos;
      txreq_returnnid = reqenc_txreq_returnnid;
      txreq_returntxnid = reqenc_txreq_returntxnid;
      txreq_ns = reqenc_txreq_ns;
      txreq_allowretry = reqenc_txreq_allowretry;
      txreq_order = reqenc_txreq_order;
      txreq_pcrdtype = reqenc_txreq_pcrdtype;
      txreq_memattr = reqenc_txreq_memattr;
      txreq_tracetag = reqenc_txreq_tracetag;
      txreq_exclusive = reqenc_txreq_exclusive;
      txreq_endian = reqenc_txreq_endian;
      txreq_lpid = reqenc_txreq_lpid;
      txreq_expcompack = reqenc_txreq_expcompack;
      txreq_amo_data = atomic_data_r;
      txreq_amo_be = atomic_be_r;
      txreq_icache = reqenc_txreq_reg_icache;


   end else if (rxbuf_txreq_bypass_valid == 1'b1 && txreq_rxbuf_bypass_won == 1'b1) begin 
      txreq_valid = rxbuf_txreq_bypass_valid;
      txreq_qos = rxbuf_txreq_bypass_qos;
      txreq_txnid = rxbuf_txreq_bypass_txnid;
      txreq_returnnid = rxbuf_txreq_bypass_returnnid;
      txreq_returntxnid = rxbuf_txreq_bypass_returntxnid;
      txreq_opcode = rxbuf_txreq_bypass_opcode;
      txreq_size = rxbuf_txreq_bypass_size;
      txreq_addr = rxbuf_txreq_bypass_addr;
      txreq_ns = rxbuf_txreq_bypass_ns;
      txreq_allowretry = rxbuf_txreq_bypass_allowretry;
      txreq_order = rxbuf_txreq_bypass_order;
      txreq_pcrdtype = rxbuf_txreq_bypass_pcrdtype;
      txreq_memattr = rxbuf_txreq_bypass_memattr;
      txreq_snpattr = rxbuf_txreq_bypass_dodwt;
      txreq_tracetag = rxbuf_txreq_bypass_tracetag;
      txreq_tgtid = rxbuf_txreq_bypass_tgtid;
      txreq_srcid = rxbuf_txreq_bypass_srcid;
      txreq_likelyshared = rxbuf_txreq_bypass_likelyshared;
      txreq_exclusive = rxbuf_txreq_bypass_exclusive;
      txreq_endian = rxbuf_txreq_bypass_endian;
      txreq_lpid = rxbuf_txreq_bypass_lpid;
      txreq_expcompack = rxbuf_txreq_bypass_expcompack;
      txreq_amo_data =  (rspenc_rxctrl_txreq_valid) ? rspenc_rxctrl_txreq_data : 'b0;
      txreq_amo_be =    (rspenc_rxctrl_txreq_valid) ? rspenc_rxctrl_txreq_be : 'b0;
      txreq_icache = 'b0;
   end else begin
      txreq_valid = 1'b0;
      txreq_qos = 'b0;
      txreq_txnid = 'b0;
      txreq_returnnid = 'b0;
      txreq_returntxnid = 'b0;
      txreq_opcode = 'b0;
      txreq_size = 'b0;
      txreq_addr = 'b0;
      txreq_ns = 'b0;
      txreq_allowretry = 'b0;
      txreq_order = 'b0;
      txreq_pcrdtype = 'b0;
      txreq_memattr = 'b0;
      txreq_snpattr = 'b0;
      txreq_tracetag = 'b0;
      txreq_tgtid = 'b0;
      txreq_srcid = 'b0;
      txreq_likelyshared = 'b0;
      txreq_exclusive = 'b0;
      txreq_endian = 'b0;
      txreq_lpid = 'b0;
      txreq_expcompack = 'b0;
      txreq_icache = 'b0;
      txreq_amo_data = 'b0;
      txreq_amo_be = 'b0;
   end

end


// Atomic or WriteNoSnp data to request registers
always @ *
begin

    atomic_data_r = 'b0;
    atomic_be_r = 'b0;

      // Register the atomic data in case AtomicLoad has been sent
      if (reqenc_txreq_valid == 1'b1 && txreq_enc_won == 1'b1) begin
         case (reqenc_txreq_opcode)
         `CHIE_ATOMICLOAD_ADD, `CHIE_ATOMICLOAD_CLR, `CHIE_ATOMICLOAD_SET, 
         `CHIE_ATOMICLOAD_EOR, `CHIE_ATOMICLOAD_SMAX, `CHIE_ATOMICLOAD_UMAX, 
         `CHIE_ATOMICLOAD_SMIN, `CHIE_ATOMICLOAD_UMIN, `CHIE_ATOMICSWAP, `CHIE_WRITENOSNPPTL:
         begin
            // L15 to CHI data alignment, L15 duplicates valid data over the first 8 bytes in AMOs and Writhroughs, AMO and writethrough data can be 1-8 bytes
            if (reqenc_txreq_opcode == `CHIE_ATOMICLOAD_CLR) begin
               // bitwise NOT for txndata (CHI spec)
               atomic_data_r = {{256{1'b0}}, swendian64(~atomic_data[127:64]), swendian64(~atomic_data[63:0])} << (reqenc_txreq_addr[5:0]*8);
            end else begin
               atomic_data_r = {{256{1'b0}}, swendian64(atomic_data[127:64]), swendian64(atomic_data[63:0])} << (reqenc_txreq_addr[5:0]*8);
            end


            case (reqenc_txreq_size)
            `CHIE_SIZE1B: 
               begin atomic_be_r = {{(64-1){1'b0}}, 1'b1} << (reqenc_txreq_addr[5:0]); end
            `CHIE_SIZE2B: 
               begin atomic_be_r = {{(64-2){1'b0}}, {2'b11}} << (reqenc_txreq_addr[5:0]); end
            `CHIE_SIZE4B: 
               begin atomic_be_r = {{(64-2**2){1'b0}}, {(2**2){1'b1}}} << (reqenc_txreq_addr[5:0]); end
            `CHIE_SIZE8B: 
               begin atomic_be_r = {{(64-2**3){1'b0}}, {(2**3){1'b1}}} << (reqenc_txreq_addr[5:0]); end
            `CHIE_SIZE16B: 
               begin atomic_be_r = {{(64-2**4){1'b0}}, {(2**4){1'b1}}} << (reqenc_txreq_addr[5:0]); end
            `CHIE_SIZE32B: 
               begin atomic_be_r = {{(64-2**5){1'b0}}, {(2**5){1'b1}}} << (reqenc_txreq_addr[5:0]); end
            `CHIE_SIZE64B: 
               begin atomic_be_r = {{(64-2**6){1'b0}}, {(2**6){1'b1}}} << (reqenc_txreq_addr[5:0]); end
            endcase

         end 
         endcase
      end
      else begin
         atomic_data_r = 'b0;
         atomic_be_r = 'b0;
      end

end




/////////////////////////////////////////////////////////////////////////////////////////////////////////
// INCOMING CHI TO OPENPITON OPCODE AND STATE TRANSLATION, AND DATA CONTROL
/////////////////////////////////////////////////////////////////////////////////////////////////////////

reg [CHIE_DATA_WIDTH_PARAM-1:0] data;

// CHI to OP response type translation
always @ *
begin
   
   is_dirty = 1'b0;
   amo_data_response = 'b0;
   txrsp_opcode_r = 'b0;
   msg_buffer = 'b0;
   data_rdy_r = 1'b0;
   dbid_received = 1'b0;
   data = 'b0;

   if (rxdat_valid_r) begin


   msg_buffer = 'b0;

      // RXDAT OPCODE
      case (rxdat_opcode_r)
         `CHIE_COMPDATA, `CHIE_DATASEPRESP:
         begin
            // data response
            msg_buffer[`MSG_TYPE] = `MSG_TYPE_DATA_ACK;
            msg_buffer[`MSG_MSHRID] = {{(`MSG_MSHRID_WIDTH-`L15_MSHR_ID_WIDTH-`L15_THREADID_WIDTH){1'b0}} ,rxdat_txnid_r[`L15_MSHR_ID_WIDTH+`L15_THREADID_WIDTH-1:0]};  // OP mshrW:8, CHI txnidW:12, there shouldnt be unnecessary msb bits set
            //msg_buffer[`MSG_MSHRID] = {4'h0, rxdat_txnid_r[3:0]};  // 

            msg_buffer[`MSG_L2_MISS] = 1'b0;

            // for noc2decoder to get correct data 
            if (req_icache && (req_opcode == `CHIE_READSHARED || req_opcode == `CHIE_READCLEAN) ) begin
               msg_buffer[`MSG_LENGTH] = 4;  // cacheable ifill      -- 32B / 4 flits 
            end
            else if (req_icache && req_opcode == `CHIE_READNOSNP) begin
               msg_buffer[`MSG_LENGTH] = 1;  // non-cacheable ifill  -- 8B / 1 flit
            end
            else if (req_opcode == `CHIE_ATOMICLOAD_ADD || req_opcode == `CHIE_ATOMICLOAD_CLR 
                  || req_opcode == `CHIE_ATOMICLOAD_EOR || req_opcode == `CHIE_ATOMICLOAD_SET 
                  || req_opcode == `CHIE_ATOMICLOAD_CLR || req_opcode == `CHIE_ATOMICLOAD_SMAX 
                  || req_opcode == `CHIE_ATOMICLOAD_UMAX || req_opcode == `CHIE_ATOMICLOAD_SMIN 
                  || req_opcode == `CHIE_ATOMICLOAD_UMIN || req_opcode == `CHIE_ATOMICSWAP) begin
               msg_buffer[`MSG_LENGTH] = 2;
               amo_data_response = 'b1;
            end
            else begin
               msg_buffer[`MSG_LENGTH] = 2;  // cacheable load data ack      -- 16B / 2 flit
            end

            txrsp_opcode_r = `CHIE_COMPACK;
         end
      endcase

   
      case (rxdat_resp_r)
         `CHIE_COMP_RESP_UD_PD:
         begin
            msg_buffer[`MSG_MESI] = `MSG_MESI_M;   
            is_dirty = 1'b1;
         end
         `CHIE_COMP_RESP_UC:  // [2]: PassDirty = 0, [1:0]: Cacheline state = 10=UniqueClean=Exclusive
         begin
            // Give the cacheline state to L15 according to initial request type.
            // Openpiton gives cacheline in M-state from L2 to L15, if the request has been to store to the line.
            if (req_opcode == `CHIE_READUNIQUE) begin
               msg_buffer[`MSG_MESI] = `MSG_MESI_M;
            end else begin
               msg_buffer[`MSG_MESI] = `MSG_MESI_E;
            end
         end
         `CHIE_COMP_RESP_SC:
         begin
            msg_buffer[`MSG_MESI] = `MSG_MESI_S;
         end
         `CHIE_COMP_RESP_I:
         begin
            msg_buffer[`MSG_MESI] = `MSG_MESI_I;
         end
      endcase


      // ===========================================================================
      // Unified line-completion drain for 128b / 256b CHI DAT widths.
      //
      // The pre-existing line_data (512b) + linedat_rdy (4-bit chunk-arrival
      // mask) infrastructure is reused to accumulate the full 64B cacheline
      // across multiple RXDAT flits. The TXNID-pick / wait_line_flit logic
      // (above) keeps draining buffered flits whose TXNID matches line_txnid
      // until every 16B sub-block has arrived (linedat_rdy == 4'b1111).
      //
      // Forwarding policy:
      //   - Dcache: the modified 64B L15 pipeline expects the full 512b line
      //     in msg_buffer[575:64]. Drive the entire line_data into the
      //     8 x 64b data slots once the line is complete.
      //   - Icache: the L1I still consumes a 32B subline. Wait for the full
      //     64B (so all rxdat-buf entries free up cleanly), but propagate
      //     only the requested 32B chunk selected by req_addr[5] (== CCID[1]).
      //   - Non-cacheable READNOSNP: sub-line read (<= 8B), single-flit;
      //     keep the existing single-flit gating without accumulator wait.
      // ===========================================================================
      if (CHIE_DATA_WIDTH_PARAM == 'd128 || CHIE_DATA_WIDTH_PARAM == 'd256) begin

         if (req_valid) begin
            if (req_icache) begin
               if (req_opcode == `CHIE_READSHARED || req_opcode == `CHIE_READCLEAN) begin
                  // Wait for the full 64B in line_data; propagate only the
                  // requested 32B subline (selected by req_addr[5]/CCID[1]).
                  case (rxdat_ccid_r[1])
                     1'b0: begin
                        msg_buffer[2*64 - 1 -: 64] = swendian64(line_data[1*64 - 1 -: 64]);
                        msg_buffer[3*64 - 1 -: 64] = swendian64(line_data[2*64 - 1 -: 64]);
                        msg_buffer[4*64 - 1 -: 64] = swendian64(line_data[3*64 - 1 -: 64]);
                        msg_buffer[5*64 - 1 -: 64] = swendian64(line_data[4*64 - 1 -: 64]);
                     end
                     1'b1: begin
                        msg_buffer[2*64 - 1 -: 64] = swendian64(line_data[5*64 - 1 -: 64]);
                        msg_buffer[3*64 - 1 -: 64] = swendian64(line_data[6*64 - 1 -: 64]);
                        msg_buffer[4*64 - 1 -: 64] = swendian64(line_data[7*64 - 1 -: 64]);
                        msg_buffer[5*64 - 1 -: 64] = swendian64(line_data[8*64 - 1 -: 64]);
                     end
                  endcase
                  // Line-complete signal: every sub-block has arrived.
                  data_rdy_r = is_last_beat;

               end else if (req_opcode == `CHIE_READNOSNP) begin
                  // Pass non-cachealbe ifill when the whole data is received
                  data = line_data >> (64*req_addr[5:3]);
                  msg_buffer[2*64 - 1 -: 64] = swendian64(data[63:0]);
                  data_rdy_r = is_last_beat;
               end
            end
            else begin
               // Dcache: forward the full 64B cacheline into msg_buffer[575:64]
               // once line_data has accumulated every sub-block. No CCID-based
               // gating and no req_addr[5:4] sub-block extraction; the modified
               // pipeline consumes the whole line and selects sub-blocks itself.
               msg_buffer[2*64 - 1 -: 64] = swendian64(line_data[1*64 - 1 -: 64]);
               msg_buffer[3*64 - 1 -: 64] = swendian64(line_data[2*64 - 1 -: 64]);
               msg_buffer[4*64 - 1 -: 64] = swendian64(line_data[3*64 - 1 -: 64]);
               msg_buffer[5*64 - 1 -: 64] = swendian64(line_data[4*64 - 1 -: 64]);
               msg_buffer[6*64 - 1 -: 64] = swendian64(line_data[5*64 - 1 -: 64]);
               msg_buffer[7*64 - 1 -: 64] = swendian64(line_data[6*64 - 1 -: 64]);
               msg_buffer[8*64 - 1 -: 64] = swendian64(line_data[7*64 - 1 -: 64]);
               msg_buffer[9*64 - 1 -: 64] = swendian64(line_data[8*64 - 1 -: 64]);
               data_rdy_r = is_last_beat;
            end
         end

      end else if (CHIE_DATA_WIDTH_PARAM == 'd512) begin

         if (req_icache) begin
            if (req_opcode == `CHIE_READSHARED || req_opcode == `CHIE_READCLEAN) begin
               // Requested 32 (cacheable) byte Instruction cacheline, Endianness swapped Little -> Big, (OP L1.5 is big-endian)
               data = rxdat_data_r >> (128*rxdat_ccid_r[1:0]);
               msg_buffer[2*64 - 1 -: 64] = swendian64(data[63:0]);
               msg_buffer[3*64 - 1 -: 64] = swendian64(data[127:64]);
               msg_buffer[4*64 - 1 -: 64] = swendian64(data[191:128]);
               msg_buffer[5*64 - 1 -: 64] = swendian64(data[255:192]);

            end else if (req_opcode == `CHIE_READNOSNP) begin
               data = rxdat_data_r >> (64*req_addr[5:3]);
               msg_buffer[2*64 - 1 -: 64] = swendian64(data[63:0]);
            end
         end
         else begin
               // Forward the full 64B cacheline into the data region msg_buffer[575:64];
               // the modified 64B L15 pipeline consumes the full line and selects the
               // requested sub-block internally. No shift by req_addr[5:4].
               msg_buffer[2*64 - 1 -: 64] = swendian64(rxdat_data_r[1*64 - 1 -: 64]);
               msg_buffer[3*64 - 1 -: 64] = swendian64(rxdat_data_r[2*64 - 1 -: 64]);
               msg_buffer[4*64 - 1 -: 64] = swendian64(rxdat_data_r[3*64 - 1 -: 64]);
               msg_buffer[5*64 - 1 -: 64] = swendian64(rxdat_data_r[4*64 - 1 -: 64]);
               msg_buffer[6*64 - 1 -: 64] = swendian64(rxdat_data_r[5*64 - 1 -: 64]);
               msg_buffer[7*64 - 1 -: 64] = swendian64(rxdat_data_r[6*64 - 1 -: 64]);
               msg_buffer[8*64 - 1 -: 64] = swendian64(rxdat_data_r[7*64 - 1 -: 64]);
               msg_buffer[9*64 - 1 -: 64] = swendian64(rxdat_data_r[8*64 - 1 -: 64]);
         end
         data_rdy_r = 1'b1;
      end
   end 


   if (rxrsp_valid_r) begin
      // RSP opcode
      case (rxrsp_opcode_r)
         `CHIE_COMPDBIDRESP, `CHIE_DBIDRESP, `CHIE_DBIDRESPORD:
         begin
            // send data to HNF
            dbid_received = 1'b1;
         end
         `CHIE_COMP:
         begin
            // dataless response, CHIE_CLEANUNIQUE 
            msg_buffer[`MSG_TYPE] = (req_opcode == `CHIE_WRITENOSNPPTL) ? `MSG_TYPE_NODATA_ACK : `MSG_TYPE_DATA_ACK;  // l15 expects DATA_ACK for STORE_UPGRADE-reqs, even though any data is not provided
            msg_buffer[`MSG_MSHRID] = {{(`MSG_MSHRID_WIDTH-`L15_MSHR_ID_WIDTH-`L15_THREADID_WIDTH){1'b0}} ,rxrsp_txnid_r[`L15_MSHR_ID_WIDTH+`L15_THREADID_WIDTH-1:0]};  // OP mshrW:8, CHI txnidW:12, there shouldnt be unnecessary lsb bits set
            //msg_buffer[`MSG_MSHRID] = {4'h0, rxrsp_txnid_r[3:0]};

            msg_buffer[`MSG_L2_MISS] = 1'b0;
            msg_buffer[`MSG_LENGTH] = (req_opcode == `CHIE_WRITENOSNPPTL) ? 0 : 2;  // cacheable load data ack      -- 16B / 2 flit

            txrsp_opcode_r = `CHIE_COMPACK;
         end
         `CHIE_READRECEIPT:
         begin
            //
         end
         `CHIE_RESPSEPDATA:
         begin
            txrsp_opcode_r = `CHIE_COMPACK;
         end
         `CHIE_RETRYACK:
         begin
            // Retry request
         end
      endcase

      // Cacheline state
      case (rxrsp_resp_r)
         `CHIE_COMP_RESP_UD_PD:
         begin
            msg_buffer[`MSG_MESI] = `MSG_MESI_M;   
            is_dirty = 1'b1;
         end
         `CHIE_COMP_RESP_UC:  // [2]: PassDirty = 0, [1:0]: Cacheline state = 10=UniqueClean=Exclusive
         begin
            // Give the cacheline state to L15 according to initial request type.
            // Openpiton gives cacheline in M-state from L2 to L15, if the request has been to store to the line.
            if (req_opcode == `CHIE_CLEANUNIQUE) begin
               msg_buffer[`MSG_MESI] = `MSG_MESI_M;
            end else begin
               msg_buffer[`MSG_MESI] = `MSG_MESI_E;
            end
            is_dirty = 1'b0;
         end
         `CHIE_COMP_RESP_SC:
         begin
            msg_buffer[`MSG_MESI] = `MSG_MESI_S;
            is_dirty = 1'b0;
         end
         `CHIE_COMP_RESP_I:
         begin
            msg_buffer[`MSG_MESI] = `MSG_MESI_I;
         end
      endcase
   end


end


reg [511:0] shift_data;
reg [63:0]  shift_be;
assign shift_data = (rxdat_valid_r) ? ({{(512-`CHIE_DAT_FLIT_DATA_WIDTH){1'b0}}, rxdat_data_r} << (128*rxdat_dataid_r)) : 'b0;
assign shift_be = (rxdat_valid_r) ? ({{(64-`CHIE_DAT_FLIT_BE_WIDTH){1'b0}}, {(CHIE_DATA_WIDTH_PARAM/128)*16{1'b1}}} << (16*rxdat_dataid_r)) : 'b0;

assign line_data_next = line_data | shift_data | (req_data & {512{!amo_data_response}});
assign line_be_next = line_be | shift_be | (req_be & {64{!amo_data_response}});
assign is_last_beat = &line_be_next;


// Temporarily store received data
always @ (posedge clk) begin
   if (~rst_n)
   begin
      line_txnid <= 'b0;
      line_data <= 'b0;
      line_be <= 'b0;
   end
   else 
   begin
      if (rxdat_valid_r) begin
         line_txnid <= rxdat_txnid_r;
         line_data <= line_data_next;
         line_be <= line_be_next;
         if (state_next == `RX_STATE_IDLE) begin
            line_data <= 'b0;
            line_txnid <= 'b0;
            line_be <= 'b0;
         end
      end else if (rxsnp_valid_r && pending_wb_match) begin
         line_data <= rspenc_rxctrl_txreq_data;
         if (state_next == `RX_STATE_IDLE) begin
            line_data <= 'b0;
            line_txnid <= 'b0;
            line_be <= 'b0;
         end
      end else if (state_next == `RX_STATE_IDLE) begin
         line_data <= 'b0;
         line_txnid <= 'b0;
         line_be <= 'b0;
      end
   end
end



always @ *
begin
   
   msg_buffer_rxsnp = 'b0;
   rxctrl_l15_txnid = 'b0;

   // RXSNP OPCODE
   if (rxsnp_valid_r) begin

      rxctrl_l15_txnid = rxsnp_txnid_r;

      msg_buffer_rxsnp[`MSG_MSHRID] = rxsnp_txnid_r[`MSG_MSHRID_WIDTH-1:0];
      msg_buffer_rxsnp[`MSG_ADDR] = {rxsnp_addr_r[`CHIE_SNP_FLIT_ADDR_WIDTH-2-3:0], 3'b000};   // in some places OP addr configured to 48 with macros, and in some it is hardcoded 40... OpenNoC addr is 41 (downto idx 3 of original addr) 
                                                                                                // For now here is done slicing to align the received address correctly, with matching configurations this should be done as in generic case
      msg_buffer_rxsnp[`MSG_SUBLINE_VECTOR] = (rxsnp_addr_r[2:1] == 2'b11) ? 4'b1000 :
                                                (rxsnp_addr_r[2:1] == 2'b10) ? 4'b0100 :
                                                (rxsnp_addr_r[2:1] == 2'b01) ? 4'b0010 : 4'b0001;         // one-hot vector, indicates the 16Byte portion from 64byte line, translated from addr_5_4 bits
                                                                        // OP-L2 64byte coherence granularity, subline_vec indicates which 16byte is in this cache, 
                                                                        // It doesn't matter what's the subline vector, the l15 will anyways check the whole 64Byte cacheline.
      msg_buffer_rxsnp[`MSG_CACHE_TYPE] = `MSG_CACHE_TYPE_DATA;  // for now, only data cache transactions
      msg_buffer_rxsnp[`MSG_LENGTH] = 2;
      msg_buffer_rxsnp[`MSG_SRC_CHIPID] = rxsnp_srcid_r;



      case (rxsnp_opcode_r)
         `CHIE_SNPUNIQUE:
         begin
            msg_buffer_rxsnp[`MSG_TYPE] = `MSG_TYPE_STORE_FWD;
            msg_buffer_rxsnp[`MSG_L2_MISS] = rxsnp_rettosrc_r;
         end
         `CHIE_SNPCLEANINVALID:
         begin
            msg_buffer_rxsnp[`MSG_TYPE] = `MSG_TYPE_STORE_FWD;
            msg_buffer_rxsnp[`MSG_L2_MISS] = 'b0;
         end
         `CHIE_SNPSHARED, `CHIE_SNPCLEAN:
         begin
            msg_buffer_rxsnp[`MSG_TYPE] = `MSG_TYPE_LOAD_FWD;
            msg_buffer_rxsnp[`MSG_L2_MISS] = rxsnp_rettosrc_r;
         end
         `CHIE_SNPCLEANSHARED:
         begin
            msg_buffer_rxsnp[`MSG_TYPE] = `MSG_TYPE_LOAD_FWD;
            msg_buffer_rxsnp[`MSG_L2_MISS] = 'b0;
         end
         `CHIE_SNPMAKEINVALID:      // invalidate and discard cline in any state
         begin
            msg_buffer_rxsnp[`MSG_TYPE] = `MSG_TYPE_INV_FWD;
            msg_buffer_rxsnp[`MSG_L2_MISS] = 'b0;
         end

      endcase
   end
end 



endmodule
