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
//  Filename        : response_encoder (original noc3encoder)
//  Original Author : Tri Nguyen, trin@princeton.edu, Princeton University
//  Modified        : Teemu Rinne, Tampere University
//
//  Description     : Response encoder of AMBA CHI based RN-F coherent cache
//
//==================================================================================================


`include "l15.tmp.h"
`include "define.tmp.h"

`include "rnf_param.v"
`include "rnf_defines.v"
`include "chie_defines.v"

`ifdef DEFAULT_NETTYPE_NONE
`default_nettype none // DEFAULT_NETTYPE_NONE
`endif
module response_encoder import wt_cache_pkg::*; `RNF_PARAM (
    input wire clk,
    input wire rst_n,

    input wire l15_noc3encoder_req_val_i,
    input wire [`L15_NOC3_REQTYPE_WIDTH-1:0] l15_noc3encoder_req_type_i,
    // Modified 64B L15 pipeline delivers the full 512b writeback/snoop-data
    // line in a single request; replaces the prior 2x64b sub-block delivery.
    input wire [511:0] l15_noc3encoder_req_data_i,
    input wire [`L15_MSHR_ID_WIDTH-1:0] l15_noc3encoder_req_mshrid_i,
    input wire [`L15_THREADID_MASK] l15_noc3encoder_req_threadid_i,
    input wire [1:0] l15_noc3encoder_req_sequenceid_i,
    input wire [39:0] l15_noc3encoder_req_address_i,
    input wire l15_noc3encoder_req_with_data_i,
    input wire l15_noc3encoder_req_was_inval_i,
    input wire [3:0] l15_noc3encoder_req_fwdack_vector_i,
    input wire [`PACKET_HOME_ID_WIDTH-1:0] l15_noc3encoder_req_homeid_i,
    input wire [`L15_MESI_STATE_WIDTH-1:0] l15_noc3buffer_req_prev_mesi_i,
    input wire [`CHIE_SNP_FLIT_TXNID_WIDTH-1:0] l15_noc3buffer_req_rxsnp_txnid_i,

    output reg noc3encoder_l15_req_ack,


    // TXDAT
    output wire                                         dbf_txdat_valid_sx1,
    output wire [`CHIE_DAT_FLIT_QOS_WIDTH-1:0]          encoder_txdat_qos,
    output wire [`CHIE_DAT_FLIT_SRCID_WIDTH-1:0]        encoder_txdat_srcid,
    output wire [`CHIE_DAT_FLIT_HOMENID_WIDTH-1:0]      encoder_txdat_homenid,
    output wire [`CHIE_DAT_FLIT_FWDSTATE_WIDTH-1:0]     encoder_txdat_fwdstate,
    output wire [`CHIE_DAT_FLIT_CCID_WIDTH-1:0]         encoder_txdat_ccid,
    output wire [`CHIE_DAT_FLIT_TGTID_WIDTH-1:0]        mshr_txdat_tgtid_sx2,
    output wire [`CHIE_DAT_FLIT_TXNID_WIDTH-1:0]        mshr_txdat_txnid_sx2,
    output wire [`CHIE_DAT_FLIT_OPCODE_WIDTH-1:0]       mshr_txdat_opcode_sx2,
    output wire [`CHIE_DAT_FLIT_RESP_WIDTH-1:0]         mshr_txdat_resp_sx2,
    output wire [`CHIE_DAT_FLIT_RESPERR_WIDTH-1:0]      mshr_txdat_resperr_sx2,
    output wire [`CHIE_DAT_FLIT_DBID_WIDTH-1:0]         mshr_txdat_dbid_sx2,
    output wire [`CHI_CACHE_LINE_WIDTH-1:0]             dbf_txdat_data_sx1,
    output wire [2-1:0]                                 dbf_txdat_idx_sx1,
    output wire [1:0]                                   dbf_txdat_pe_sx1,
    output wire [`CHI_CACHE_BE_WIDTH-1:0]               dbf_txdat_be_sx1,
    input wire                                          txdat_mshr_clr_dbf_busy_valid_sx3,  // assigned when entry is being deallocated
    input wire [2-1:0]                                  txdat_mshr_clr_dbf_busy_idx_sx3,    // the index of mshr entry that is being deallocated
    input wire [2-1:0]                                  txdat_mshr_rd_idx_sx2,              // idx of ent2_ns or ent1, if they are valid
    input wire                                          txdat_mshr_busy_sx,                 // IF both entries are valid (txdat is full)
    // TXRSP
    output wire                                        encoder_txrsp_bypass_valid_s1,
    output wire [`CHIE_RSP_FLIT_QOS_WIDTH-1:0]         encoder_txrsp_bypass_qos_s1,
    output wire [`CHIE_RSP_FLIT_TGTID_WIDTH-1:0]       encoder_txrsp_bypass_tgtid_s1,
    output wire [`CHIE_RSP_FLIT_TXNID_WIDTH-1:0]       encoder_txrsp_bypass_txnid_s1,
    output wire [`CHIE_RSP_FLIT_OPCODE_WIDTH-1:0]      encoder_txrsp_bypass_opcode_s1,
    output wire [`CHIE_RSP_FLIT_RESP_WIDTH-1:0]        encoder_txrsp_bypass_resp,
    output wire [`CHIE_RSP_FLIT_RESPERR_WIDTH-1:0]     encoder_txrsp_bypass_resperr_s1,
    output wire [`CHIE_RSP_FLIT_DBID_WIDTH-1:0]        encoder_txrsp_bypass_dbid_s1,
    output wire [`CHIE_RSP_FLIT_TRACETAG_WIDTH-1:0]    encoder_txrsp_bypass_tracetag_s1,
    input wire                                         txrsp_encoder_bypass_won_s1,
    // TXDAT from rx_buffer ()
    input wire                                         rxbuf_rspenc_txdat_valid,
    input wire [`CHIE_DAT_FLIT_QOS_WIDTH-1:0]          rxbuf_rspenc_txdat_qos,
    input wire [`CHIE_DAT_FLIT_SRCID_WIDTH-1:0]        rxbuf_rspenc_txdat_srcid,
    input wire [`CHIE_DAT_FLIT_TXNID_WIDTH-1:0]        rxbuf_rspenc_txdat_txnid,
    input wire [`CHIE_DAT_FLIT_OPCODE_WIDTH-1:0]       rxbuf_rspenc_txdat_opcode,
    input wire [`CHIE_DAT_FLIT_RESP_WIDTH-1:0]         rxbuf_rspenc_txdat_resp,
    input wire [`CHIE_DAT_FLIT_RESPERR_WIDTH-1:0]      rxbuf_rspenc_txdat_resperr,
    input wire [`CHIE_DAT_FLIT_FWDSTATE_WIDTH-1:0]     rxbuf_rspenc_txdat_fwdstate,
    input wire [`CHIE_DAT_FLIT_DATAID_WIDTH-1:0]       rxbuf_rspenc_txdat_dataid,
    input wire [`CHIE_DAT_FLIT_HOMENID_WIDTH-1:0]      rxbuf_rspenc_txdat_homenid,
    input wire [`CHIE_DAT_FLIT_CCID_WIDTH-1:0]         rxbuf_rspenc_txdat_ccid,
    input wire [`CHIE_DAT_FLIT_TGTID_WIDTH-1:0]        rxbuf_rspenc_txdat_tgtid,
    input wire [`CHIE_DAT_FLIT_DBID_WIDTH-1:0]         rxbuf_rspenc_txdat_dbid,
    input wire [`CHI_CACHE_BE_WIDTH-1:0]               rxbuf_rspenc_txdat_be,
    input wire [`CHI_CACHE_LINE_WIDTH-1:0]             rxbuf_rspenc_txdat_data,

    output reg                                         rspenc_rxbuf_ack,   

    output reg                                         writeback_pending,

    // WriteBack TXREQ 
    output reg                                         rspenc_rxctrl_txreq_valid,
    output reg [`CHIE_REQ_FLIT_TXNID_WIDTH-1:0]        rspenc_rxctrl_txreq_txnid,
    output reg [`CHIE_REQ_FLIT_OPCODE_WIDTH-1:0]       rspenc_rxctrl_txreq_opcode,
    output reg [`CHIE_REQ_FLIT_SIZE_WIDTH-1:0]         rspenc_rxctrl_txreq_size,
    output reg [`CHIE_REQ_FLIT_ADDR_WIDTH-1:0]         rspenc_rxctrl_txreq_addr,
    output reg [`CHIE_REQ_FLIT_TGTID_WIDTH-1:0]        rspenc_rxctrl_txreq_tgtid,
    output reg [`CHIE_REQ_FLIT_SRCID_WIDTH-1:0]        rspenc_rxctrl_txreq_srcid,
    output reg [`CHIE_REQ_FLIT_DODWT_WIDTH-1:0]        rspenc_rxctrl_txreq_snpattr,
    output reg [`CHIE_REQ_FLIT_LIKELYSHARED_WIDTH-1:0] rspenc_rxctrl_txreq_likelyshared,
    output reg [`CHIE_REQ_FLIT_QOS_WIDTH-1:0]          rspenc_rxctrl_txreq_qos,
    output reg [`CHIE_REQ_FLIT_RETURNNID_WIDTH-1:0]    rspenc_rxctrl_txreq_returnnid,
    output reg [`CHIE_REQ_FLIT_RETURNTXNID_WIDTH-1:0]  rspenc_rxctrl_txreq_returntxnid,
    output reg [`CHIE_REQ_FLIT_NS_WIDTH-1:0]           rspenc_rxctrl_txreq_ns,
    output reg [`CHIE_REQ_FLIT_ALLOWRETRY_WIDTH-1:0]   rspenc_rxctrl_txreq_allowretry,
    output reg [`CHIE_REQ_FLIT_ORDER_WIDTH-1:0]        rspenc_rxctrl_txreq_order,
    output reg [`CHIE_REQ_FLIT_PCRDTYPE_WIDTH-1:0]     rspenc_rxctrl_txreq_pcrdtype,
    output reg [`CHIE_REQ_FLIT_MEMATTR_WIDTH-1:0]      rspenc_rxctrl_txreq_memattr,
    output reg [`CHIE_REQ_FLIT_TRACETAG_WIDTH-1:0]     rspenc_rxctrl_txreq_tracetag,     
    output reg [`CHIE_REQ_FLIT_EXCL_WIDTH-1:0]         rspenc_rxctrl_txreq_exclusive,  
    output reg [`CHIE_REQ_FLIT_ENDIAN_WIDTH-1:0]       rspenc_rxctrl_txreq_endian,
    output reg [`CHIE_REQ_FLIT_LPID_WIDTH-1:0]         rspenc_rxctrl_txreq_lpid,
    output reg [`CHIE_REQ_FLIT_EXPCOMPACK_WIDTH-1:0]   rspenc_rxctrl_txreq_expcompack,
    output reg [`CHI_CACHE_BE_WIDTH-1:0]               rspenc_rxctrl_txreq_be,     // 64bit BE
    output reg [`CHI_CACHE_LINE_WIDTH-1:0]             rspenc_rxctrl_txreq_data,   // 512bit data
    input wire                                         rspenc_txreq_won
   );



reg l15_noc3encoder_req_val;
reg [`L15_NOC3_REQTYPE_WIDTH-1:0] l15_noc3encoder_req_type;
// Single 512b flop for the full-line request payload, replacing the prior 2x64b regs.
reg [511:0] l15_noc3encoder_req_data;
reg [`L15_MSHR_ID_WIDTH-1:0] l15_noc3encoder_req_mshrid;
reg [`L15_THREADID_MASK] l15_noc3encoder_req_threadid;
reg [1:0] l15_noc3encoder_req_sequenceid;
reg [39:0] l15_noc3encoder_req_address;
reg l15_noc3encoder_req_with_data;
reg l15_noc3encoder_req_was_inval;
reg [3:0] l15_noc3encoder_req_fwdack_vector;
reg [`PACKET_HOME_ID_WIDTH-1:0] l15_noc3encoder_req_homeid;
reg [`L15_MESI_STATE_WIDTH-1:0] l15_noc3buffer_req_prev_mesi;
reg [`CHIE_SNP_FLIT_TXNID_WIDTH-1:0] l15_noc3buffer_req_rxsnp_txnid;


reg [`PHY_ADDR_WIDTH-1:0] address;
reg [`NOC_CHIPID_WIDTH-1:0] dest_chipid;
reg [`MSG_LENGTH_WIDTH-1:0] msg_length;
reg [`MSG_TYPE_WIDTH-1:0] msg_type;
reg [`MSG_MSHRID_WIDTH-1:0] msg_mshrid;
reg [`MSG_LAST_SUBLINE_WIDTH-1:0] msg_last_subline;

// CHI RNF
reg encoder_in_rdy;

// 64byte cacheline to be returned 
reg [`CHI_CACHE_LINE_WIDTH-1:0]        data_reg;
reg                                    data_rdy;
reg                                    data_sent;
reg                                    cb_data_sent;
reg                                    response_detected;
reg                                    response_rdy;
reg                                    wb_data_sent;
reg [3:0]                              chunks_received; 
reg [3:0]                              chunks_received_last; 
reg [3:0]                              received_chunk;
reg [2:0]                              data_msg_watchdog;

reg sending;
reg is_request;
reg is_response;
reg [1:0] last_subcacheline_id;

reg [`RESP_FLIT_STATE_WIDTH-1:0]            state;
reg [`RESP_FLIT_STATE_WIDTH-1:0]            state_next;
reg                                         rxbuf_txdat_pending;
reg                                         snprsp_pending;


// CHI RNF 
// TXDAT
reg                                        msg_valid;
reg [`CHIE_DAT_FLIT_QOS_WIDTH-1:0]         msg_qos;
reg [`CHIE_DAT_FLIT_SRCID_WIDTH-1:0]       msg_srcid;
reg [`CHIE_DAT_FLIT_HOMENID_WIDTH-1:0]     msg_homenid;
reg [`CHIE_DAT_FLIT_FWDSTATE_WIDTH-1:0]    msg_fwdstate;
reg [`CHIE_DAT_FLIT_CCID_WIDTH-1:0]        msg_ccid;
reg [`CHIE_DAT_FLIT_TGTID_WIDTH-1:0]       msg_tgtid;
reg [`CHIE_DAT_FLIT_TXNID_WIDTH-1:0]       msg_txnid;
reg [`CHIE_DAT_FLIT_OPCODE_WIDTH-1:0]      msg_opcode;
reg [`CHIE_DAT_FLIT_RESP_WIDTH-1:0]        msg_resp;
reg [`CHIE_DAT_FLIT_RESPERR_WIDTH-1:0]     msg_resperr;
reg [`CHIE_DAT_FLIT_DBID_WIDTH-1:0]        msg_dbid;
reg [`CHI_CACHE_LINE_WIDTH-1:0]            msg_data;
reg [2-1:0]                                msg_idx; 
reg [1:0]                                  msg_pe; // DataID for 512bit cacheline: "11", txdat_wrap determines then the dataid for 2x256bit flits
reg [`CHI_CACHE_BE_WIDTH-1:0]              msg_be;

reg                                        msg_rxbuf_valid;

// TXRSP
reg                                         msg_rsp_valid;
reg [`CHIE_RSP_FLIT_OPCODE_WIDTH-1:0]       msg_rsp_opcode;

reg                                         msg_txreq_valid;
reg [`CHIE_REQ_FLIT_TXNID_WIDTH-1:0]        msg_txreq_txnid;
reg [`CHIE_REQ_FLIT_OPCODE_WIDTH-1:0]       msg_txreq_opcode;
reg [`CHIE_REQ_FLIT_SIZE_WIDTH-1:0]         msg_size;
reg [`CHIE_REQ_FLIT_ADDR_WIDTH-1:0]         msg_txreq_addr;
reg [`CHIE_REQ_FLIT_TGTID_WIDTH-1:0]        msg_txreq_tgtid;
reg [`CHIE_REQ_FLIT_SRCID_WIDTH-1:0]        msg_txreq_srcid;
reg [`CHIE_REQ_FLIT_DODWT_WIDTH-1:0]        msg_snpattr;
reg [`CHIE_REQ_FLIT_LIKELYSHARED_WIDTH-1:0] msg_likelyshared;
reg [`CHIE_REQ_FLIT_RETURNNID_WIDTH-1:0]    msg_returnnid;
reg [`CHIE_REQ_FLIT_RETURNTXNID_WIDTH-1:0]  msg_returntxnid;
reg [`CHIE_REQ_FLIT_NS_WIDTH-1:0]           msg_ns;
reg [`CHIE_REQ_FLIT_ALLOWRETRY_WIDTH-1:0]   msg_allowretry;
reg [`CHIE_REQ_FLIT_ORDER_WIDTH-1:0]        msg_order;
reg [`CHIE_REQ_FLIT_PCRDTYPE_WIDTH-1:0]     msg_pcrdtype;
reg [`CHIE_REQ_FLIT_MEMATTR_WIDTH-1:0]      msg_memattr;
reg [`CHIE_REQ_FLIT_TRACETAG_WIDTH-1:0]     msg_tracetag;
reg [`CHIE_REQ_FLIT_EXCL_WIDTH-1:0]         msg_exclusive;
reg [`CHIE_REQ_FLIT_ENDIAN_WIDTH-1:0]       msg_endian;
reg [`CHIE_REQ_FLIT_LPID_WIDTH-1:0]         msg_lpid;
reg [`CHIE_REQ_FLIT_EXPCOMPACK_WIDTH-1:0]   msg_expcompack;


always @ (posedge clk) begin

    if (!rst_n) begin
        l15_noc3encoder_req_val <= 'b0;
        l15_noc3encoder_req_type <= 'b0;
        // Single 512b flop replaces the prior 2x64b data regs.
        l15_noc3encoder_req_data <= 'b0;
        l15_noc3encoder_req_mshrid <= 'b0;
        l15_noc3encoder_req_threadid <= 'b0;
        l15_noc3encoder_req_sequenceid <= 'b0;
        l15_noc3encoder_req_address <= 'b0;
        l15_noc3encoder_req_with_data <= 'b0;
        l15_noc3encoder_req_was_inval <= 'b0;
        l15_noc3encoder_req_fwdack_vector <= 'b0;
        l15_noc3encoder_req_homeid <= 'b0;
        l15_noc3buffer_req_prev_mesi <= 'b0;
        l15_noc3buffer_req_rxsnp_txnid <= 'b0;
    end
    else
    begin
        if (encoder_in_rdy == 1'b1) begin
            l15_noc3encoder_req_val <= l15_noc3encoder_req_val_i;
            l15_noc3encoder_req_type <= l15_noc3encoder_req_type_i;
            // Latch full 512b line in one cycle (no sequenceid-driven sub-block merge).
            l15_noc3encoder_req_data <= l15_noc3encoder_req_data_i;
            l15_noc3encoder_req_mshrid <= l15_noc3encoder_req_mshrid_i;
            l15_noc3encoder_req_threadid <= l15_noc3encoder_req_threadid_i;
            l15_noc3encoder_req_sequenceid <= l15_noc3encoder_req_sequenceid_i;
            l15_noc3encoder_req_address <= l15_noc3encoder_req_address_i;
            l15_noc3encoder_req_with_data <= l15_noc3encoder_req_with_data_i;
            l15_noc3encoder_req_was_inval <= l15_noc3encoder_req_was_inval_i;
            l15_noc3encoder_req_fwdack_vector <= l15_noc3encoder_req_fwdack_vector_i;
            l15_noc3encoder_req_homeid <= l15_noc3encoder_req_homeid_i;
            l15_noc3buffer_req_prev_mesi <= l15_noc3buffer_req_prev_mesi_i;
            l15_noc3buffer_req_rxsnp_txnid <= l15_noc3buffer_req_rxsnp_txnid_i;
        end 
        else if (state_next == `RESP_STATE_IDLE) begin
            l15_noc3encoder_req_val <= 'b0;
            l15_noc3encoder_req_type <= 'b0;
            // Single 512b flop clear
            l15_noc3encoder_req_data <= 'b0;
            l15_noc3encoder_req_mshrid <= 'b0;
            l15_noc3encoder_req_threadid <= 'b0;
            l15_noc3encoder_req_sequenceid <= 'b0;
            l15_noc3encoder_req_address <= 'b0;
            l15_noc3encoder_req_with_data <= 'b0;
            l15_noc3encoder_req_was_inval <= 'b0;
            l15_noc3encoder_req_fwdack_vector <= 'b0;
            l15_noc3encoder_req_homeid <= 'b0;
            l15_noc3buffer_req_prev_mesi <= 'b0;
        end
    end
end


reg [1:0] txdat_state;
reg [1:0] txdat_state_next;

// state logic
always @ (posedge clk)
begin
    if (!rst_n)
    begin
        txdat_state <= 2'd0;
    end
    else
    begin
        txdat_state <= txdat_state_next;
    end
end

// TXDAT logic for DAT-packets coming from rx_control
always @ (*) begin

    txdat_state_next = 2'h0;
    rxbuf_txdat_pending = 1'b0;
    msg_rxbuf_valid = 1'b0;
    cb_data_sent = 1'b0;

    if (txdat_state == 2'h0) begin

        if (!snprsp_pending && !txdat_mshr_busy_sx && rxbuf_rspenc_txdat_valid) begin
            rxbuf_txdat_pending = 1'b1;
            msg_rxbuf_valid = 1'b1;
            txdat_state_next = 2'h1;
        end

    end
    else if (txdat_state == 2'h1) begin
        rxbuf_txdat_pending = 1'b1;
        txdat_state_next = 2'h1;

        if (txdat_mshr_clr_dbf_busy_valid_sx3) begin   
            cb_data_sent = 1'b1;
            txdat_state_next = 2'h0;
        end 

    end
    
end



// encoded TXDAT fields
assign dbf_txdat_valid_sx1      = (rxbuf_txdat_pending) ? msg_rxbuf_valid : msg_valid;
assign encoder_txdat_qos        = (rxbuf_txdat_pending) ? rxbuf_rspenc_txdat_qos : msg_qos;
assign encoder_txdat_srcid      = (rxbuf_txdat_pending) ? rxbuf_rspenc_txdat_srcid : msg_srcid;
assign encoder_txdat_homenid    = (rxbuf_txdat_pending) ? rxbuf_rspenc_txdat_homenid : msg_homenid;
assign encoder_txdat_fwdstate   = (rxbuf_txdat_pending) ? rxbuf_rspenc_txdat_fwdstate : msg_fwdstate;
assign encoder_txdat_ccid       = (rxbuf_txdat_pending) ? rxbuf_rspenc_txdat_ccid : msg_ccid;
assign mshr_txdat_tgtid_sx2     = (rxbuf_txdat_pending) ? rxbuf_rspenc_txdat_tgtid : msg_tgtid;
assign mshr_txdat_txnid_sx2     = (rxbuf_txdat_pending) ? rxbuf_rspenc_txdat_txnid : msg_txnid;
assign mshr_txdat_opcode_sx2    = (rxbuf_txdat_pending) ? rxbuf_rspenc_txdat_opcode : msg_opcode;
assign mshr_txdat_resp_sx2      = (rxbuf_txdat_pending) ? rxbuf_rspenc_txdat_resp : msg_resp;
assign mshr_txdat_resperr_sx2   = (rxbuf_txdat_pending) ? rxbuf_rspenc_txdat_resperr : msg_resperr;
assign mshr_txdat_dbid_sx2      = (rxbuf_txdat_pending) ? rxbuf_rspenc_txdat_dbid : msg_dbid;
assign dbf_txdat_data_sx1       = (rxbuf_txdat_pending) ? rxbuf_rspenc_txdat_data : msg_data;
assign dbf_txdat_idx_sx1        = (rxbuf_txdat_pending) ? 'b0 : msg_idx;
assign dbf_txdat_pe_sx1         = (rxbuf_txdat_pending) ? rxbuf_rspenc_txdat_dataid : msg_pe;
assign dbf_txdat_be_sx1         = (rxbuf_txdat_pending) ? rxbuf_rspenc_txdat_be : msg_be;

// encoded TXRSP fields
assign encoder_txrsp_bypass_valid_s1 = msg_rsp_valid;
assign encoder_txrsp_bypass_qos_s1 = msg_qos;
assign encoder_txrsp_bypass_tgtid_s1 = msg_tgtid;
assign encoder_txrsp_bypass_txnid_s1 = msg_txnid;
assign encoder_txrsp_bypass_opcode_s1 = msg_rsp_opcode;
assign encoder_txrsp_bypass_resp = msg_resp;
assign encoder_txrsp_bypass_resperr_s1 = msg_resperr;
assign encoder_txrsp_bypass_dbid_s1 = msg_dbid;
assign encoder_txrsp_bypass_tracetag_s1 = 0;



always @ (posedge clk) begin

    if (!rst_n) begin
        data_reg <= 'b0;
        msg_be <= 'b0;
    end
    else
    begin
        if (l15_noc3encoder_req_val && l15_noc3encoder_req_with_data && !data_rdy) begin
            data_reg[1*64 - 1 -: 64] <= swendian64(l15_noc3encoder_req_data[8*64 - 1 -: 64]);
            data_reg[2*64 - 1 -: 64] <= swendian64(l15_noc3encoder_req_data[7*64 - 1 -: 64]);
            data_reg[3*64 - 1 -: 64] <= swendian64(l15_noc3encoder_req_data[6*64 - 1 -: 64]);
            data_reg[4*64 - 1 -: 64] <= swendian64(l15_noc3encoder_req_data[5*64 - 1 -: 64]);
            data_reg[5*64 - 1 -: 64] <= swendian64(l15_noc3encoder_req_data[4*64 - 1 -: 64]);
            data_reg[6*64 - 1 -: 64] <= swendian64(l15_noc3encoder_req_data[3*64 - 1 -: 64]);
            data_reg[7*64 - 1 -: 64] <= swendian64(l15_noc3encoder_req_data[2*64 - 1 -: 64]);
            data_reg[8*64 - 1 -: 64] <= swendian64(l15_noc3encoder_req_data[1*64 - 1 -: 64]);
            msg_be                   <= {64{1'b1}};
        end else if (state_next == `RESP_STATE_IDLE) begin
            data_reg <= 'b0;
            msg_be <= 'b0;
        end

    end
end

assign writeback_pending = (l15_noc3encoder_req_val && is_request);

// State logic for DAT/RSP sending
always @ * 
begin

    encoder_in_rdy = 1'b0;
    state_next = `RESP_STATE_IDLE;

    msg_valid = 1'b0;
    msg_rsp_valid = 1'b0;
    data_sent = 1'b0;
    data_rdy = 1'b0;
    msg_txreq_valid = 1'b0;
    wb_data_sent = 1'b0;
    response_detected = 1'b0;
    snprsp_pending = 1'b0;

    if (state == `RESP_STATE_IDLE) begin
        
        encoder_in_rdy = 1'b1;
        
        // Receive message from L15
        if (l15_noc3encoder_req_val) begin
            encoder_in_rdy = 1'b0;
            if (is_response) begin
                snprsp_pending = 1'b1;
                state_next = `RESP_SEND_RSP;
            end else begin
                state_next = `RESP_SEND_WRBCK;  // initiate WriteBackPtl
            end 
        end
    end

    else if (state == `RESP_SEND_RSP) begin

        data_rdy = 1'b1;
        snprsp_pending = 1'b1;
        if (|msg_be && !l15_noc3encoder_req_was_inval) begin
            if (!txdat_mshr_busy_sx && !rxbuf_txdat_pending) begin
                msg_valid = 1'b1; // keep vld just 1 cycle, other packet fields longer
                state_next = `RESP_SEND_SNPDAT; 
            end else begin 
                state_next = `RESP_SEND_RSP;
            end
        end 
        // No data returned -> TXRSP
        else begin     
            msg_rsp_valid = 1'b1;
            if (txrsp_encoder_bypass_won_s1) begin
                state_next = `RESP_STATE_IDLE;
            end else begin
                state_next = `RESP_SEND_RSP;
            end
        end 
        
    end

    else if (state == `RESP_SEND_SNPDAT) begin
        data_rdy = 1'b1;
        snprsp_pending = 1'b1;
        // cacheline sent
        if (txdat_mshr_clr_dbf_busy_valid_sx3) begin
            state_next = `RESP_STATE_IDLE;
        end else begin
            state_next = `RESP_SEND_SNPDAT;
        end
    end

    else if (state == `RESP_SEND_WRBCK) begin
        msg_txreq_valid = 1'b1;
        data_rdy = 1'b1;            // 64B ??
        //response_detected = 1'b1; 
        if (rspenc_txreq_won) begin
            state_next = `RESP_STATE_IDLE;
            wb_data_sent = 1'b1;
        end else begin 
            state_next = `RESP_SEND_WRBCK;
        end
    end
end



// state logic
always @ (posedge clk)
begin
    if (!rst_n)
    begin
        state <= 0;
    end
    else
    begin
        state <= state_next;
    end
end


// WriteBack requests to rx_control
always @ (*)
begin

    rspenc_rxctrl_txreq_valid <= 'b0;
    rspenc_rxctrl_txreq_txnid <= 'b0;
    rspenc_rxctrl_txreq_opcode <= 'b0;
    rspenc_rxctrl_txreq_size <= 'b0;
    rspenc_rxctrl_txreq_addr <= 'b0;
    rspenc_rxctrl_txreq_tgtid <= 'b0;
    rspenc_rxctrl_txreq_srcid <= 'b0;
    rspenc_rxctrl_txreq_snpattr <= 'b0;
    rspenc_rxctrl_txreq_likelyshared <= 'b0;
    rspenc_rxctrl_txreq_qos <= 'b0;
    rspenc_rxctrl_txreq_returnnid <= 'b0;
    rspenc_rxctrl_txreq_returntxnid <= 'b0;
    rspenc_rxctrl_txreq_ns <= 'b0;
    rspenc_rxctrl_txreq_allowretry <= 'b0;
    rspenc_rxctrl_txreq_order <= 'b0;
    rspenc_rxctrl_txreq_pcrdtype <= 'b0;
    rspenc_rxctrl_txreq_memattr <= 'b0;
    rspenc_rxctrl_txreq_tracetag <= 'b0;
    rspenc_rxctrl_txreq_exclusive <= 'b0;
    rspenc_rxctrl_txreq_endian <= 'b0;
    rspenc_rxctrl_txreq_lpid <= 'b0;
    rspenc_rxctrl_txreq_expcompack <= 'b0;
    rspenc_rxctrl_txreq_be <= 'b0;
    rspenc_rxctrl_txreq_data <= 'b0;

    if (msg_txreq_valid) begin
        rspenc_rxctrl_txreq_valid <= msg_txreq_valid;
        rspenc_rxctrl_txreq_txnid <= msg_txreq_txnid;
        rspenc_rxctrl_txreq_opcode <= msg_txreq_opcode;
        rspenc_rxctrl_txreq_size <= msg_size;
        rspenc_rxctrl_txreq_addr <= address;
        rspenc_rxctrl_txreq_tgtid <= msg_tgtid;
        rspenc_rxctrl_txreq_srcid <= msg_srcid;
        rspenc_rxctrl_txreq_snpattr <= msg_snpattr;
        rspenc_rxctrl_txreq_likelyshared <= msg_likelyshared;
        rspenc_rxctrl_txreq_qos <= msg_qos;
        rspenc_rxctrl_txreq_returnnid <= msg_returnnid;
        rspenc_rxctrl_txreq_returntxnid <= msg_returntxnid;
        rspenc_rxctrl_txreq_ns <= msg_ns;
        rspenc_rxctrl_txreq_allowretry <= msg_allowretry;
        rspenc_rxctrl_txreq_order <= msg_order;
        rspenc_rxctrl_txreq_pcrdtype <= msg_pcrdtype;
        rspenc_rxctrl_txreq_memattr <= msg_memattr;
        rspenc_rxctrl_txreq_tracetag <= msg_tracetag;
        rspenc_rxctrl_txreq_exclusive <= msg_exclusive;
        rspenc_rxctrl_txreq_endian <= msg_endian;
        rspenc_rxctrl_txreq_lpid <= msg_lpid;
        rspenc_rxctrl_txreq_expcompack <= msg_expcompack;
        rspenc_rxctrl_txreq_be <= msg_be;
        rspenc_rxctrl_txreq_data <= data_reg;
    end else if (writeback_pending) begin
        // propagate address and data for snp/WB collision pre-check
        rspenc_rxctrl_txreq_addr <= address;
        rspenc_rxctrl_txreq_data[1*64 - 1 -: 64] <= swendian64(l15_noc3encoder_req_data[8*64 - 1 -: 64]);
        rspenc_rxctrl_txreq_data[2*64 - 1 -: 64] <= swendian64(l15_noc3encoder_req_data[7*64 - 1 -: 64]);
        rspenc_rxctrl_txreq_data[3*64 - 1 -: 64] <= swendian64(l15_noc3encoder_req_data[6*64 - 1 -: 64]);
        rspenc_rxctrl_txreq_data[4*64 - 1 -: 64] <= swendian64(l15_noc3encoder_req_data[5*64 - 1 -: 64]);
        rspenc_rxctrl_txreq_data[5*64 - 1 -: 64] <= swendian64(l15_noc3encoder_req_data[4*64 - 1 -: 64]);
        rspenc_rxctrl_txreq_data[6*64 - 1 -: 64] <= swendian64(l15_noc3encoder_req_data[3*64 - 1 -: 64]);
        rspenc_rxctrl_txreq_data[7*64 - 1 -: 64] <= swendian64(l15_noc3encoder_req_data[2*64 - 1 -: 64]);
        rspenc_rxctrl_txreq_data[8*64 - 1 -: 64] <= swendian64(l15_noc3encoder_req_data[1*64 - 1 -: 64]);
    end 
end



// OP to CHI encode logic
always @ *
begin
    is_request = (l15_noc3encoder_req_type == `L15_NOC3_REQTYPE_WRITEBACK);
    is_response = !is_request;

    last_subcacheline_id =  (l15_noc3encoder_req_fwdack_vector[3] == 1'b1) ? 2'b11 :
                            (l15_noc3encoder_req_fwdack_vector[2] == 1'b1) ? 2'b10 :
                            (l15_noc3encoder_req_fwdack_vector[1] == 1'b1) ? 2'b01 :
                                                                             2'b00 ;

    address = l15_noc3encoder_req_address;

    dest_chipid = l15_noc3encoder_req_homeid[`PACKET_HOME_ID_CHIP_MASK];

    msg_length = 0;
    msg_type = 0;
    msg_mshrid = {l15_noc3encoder_req_threadid, l15_noc3encoder_req_mshrid};

    msg_txnid = {l15_noc3encoder_req_threadid, l15_noc3encoder_req_mshrid};
    msg_dbid = 0;   // used with stashing responses
    msg_idx = 0;

    msg_txreq_txnid = 'b0;
    msg_txreq_opcode = 'b0;
    msg_size = 'b0;
    msg_tgtid = 'b0;
    msg_srcid = 'b0;
    msg_snpattr = 'b0;
    msg_likelyshared = 'b0;
    msg_qos = 'b0;
    msg_returnnid = 'b0;
    msg_returntxnid = 'b0;
    msg_ns = 'b0;
    msg_allowretry = 'b0;
    msg_order = 'b0;
    msg_pcrdtype = 'b0;
    msg_memattr = 'b0;
    msg_tracetag = 'b0;
    msg_exclusive = 'b0;
    msg_endian = 'b0;
    msg_lpid = 'b0;
    msg_expcompack = 'b0;
    msg_opcode = 'b0;
    msg_resp = 'b0;
    msg_homenid = 'b0;
    msg_resperr = 'b0;
    msg_fwdstate = 'b0;
    msg_ccid = 'b0;
    msg_pe = 'b0;
    msg_data = 'b0;
    msg_rsp_opcode = 'b0;

    noc3encoder_l15_req_ack = 1'b0;
    rspenc_rxbuf_ack = 1'b0;

    sending = l15_noc3encoder_req_val;


    case (l15_noc3encoder_req_type)
        `L15_NOC3_REQTYPE_WRITEBACK:
        begin

            // CHI WriteBackPtl
            //TXREQ fields
            
            if (&msg_be) begin
                msg_txreq_opcode = `CHIE_WRITEBACKFULL;
            end else begin
                msg_txreq_opcode = `CHIE_WRITEBACKPTL;
            end

            //msg_txreq_txnid = {1'b1, msg_mshrid};  // Add also data indication bit to WrBckPtl txnID as OP-l15 might do another req with the same mshrID e.g. AMO
            msg_txreq_txnid = msg_mshrid;
            msg_txreq_txnid[`L15_MSHR_ID_WIDTH+`L15_THREADID_WIDTH] = 1'b1; //just so there is no WB for same txnid as could be for another ongoing request (ld/st)
            msg_txreq_txnid[`CHIE_REQ_FLIT_TXNID_WIDTH-1 -: (`CHIE_REQ_FLIT_TXNID_WIDTH-`L15_MSHR_ID_WIDTH-`L15_THREADID_WIDTH-1)] = RNF_NID; // node-id to rest of the id

            msg_memattr = {1'b1, 1'b1, 1'b0, 1'b1}; // Allocate, Cacheable, Device(IO), EarlyWriteAck
            msg_likelyshared = 'b0;
            msg_allowretry = 1'b1;
            msg_snpattr = 1'b1;
            msg_returnnid = 'b0;
            msg_returntxnid = 'b0;
            msg_ns = 'b0;
            msg_order = 'b0;
            msg_pcrdtype = 'b0;
            msg_tracetag = 'b0;
            msg_exclusive = 'b0;
            msg_endian = 'b0;
            msg_lpid = 'b0;
            msg_expcompack = 'b0;
            msg_size = `CHIE_SIZE64B;
            msg_tgtid = HNF_NID_PARAM;
            msg_srcid = RNF_NID;
            msg_qos = 1;

        end
        `L15_NOC3_REQTYPE_DOWNGRADE_ACK:
        begin
            if (|msg_be == 1'b0) begin /*no data in response*/
                msg_rsp_opcode = `CHIE_SNPRESP;                                           // in this case, the response is sent to TXRSP!!!
            end
            else if (|msg_be) begin /*full data*/
                msg_opcode = `CHIE_SNPRESPDATA;
            end

            case (l15_noc3buffer_req_prev_mesi) 
                `L15_MESI_STATE_M:
                begin
                    msg_resp = `CHIE_SNP_RESP_SC_PD;
                end
                `L15_MESI_STATE_S, `L15_MESI_STATE_E:
                begin
                    msg_resp = `CHIE_SNP_RESP_SC;
                end
            endcase

            msg_qos = 1;
            msg_tgtid = HNF_NID_PARAM; //dest_chipid;  homenodeid
            msg_srcid = RNF_NID;
            //msg_txnid = msg_mshrid;
            msg_txnid = l15_noc3buffer_req_rxsnp_txnid;
            msg_homenid = HNF_NID_PARAM;
            msg_resperr = 'b0;
            msg_fwdstate = 3'b000; // In non-forwarding snp-responses this is datasource(implementation defined, default 000)
            msg_ccid = last_subcacheline_id;    // CriticalChunkID, addr_5_4
            msg_pe = 2'b11;     // txdat_wrap determines this as it sends the whole 512bit cacheline in two parts(2x256bit)
            msg_data = data_reg;



        end
        `L15_NOC3_REQTYPE_INVAL_ACK:
        begin
            // CHI

            if (|msg_be == 1'b0 || l15_noc3encoder_req_was_inval) begin  /*no data in response*/
                msg_rsp_opcode = `CHIE_SNPRESP;         // in this case, the response is sent through TXRSP!!!
                msg_resp = `CHIE_SNP_RESP_I;
            end
            else if (|msg_be) begin     /*full data*/
                msg_opcode = `CHIE_SNPRESPDATA;

                case (l15_noc3buffer_req_prev_mesi) 
                    `L15_MESI_STATE_M:
                    begin
                        msg_resp = `CHIE_SNP_RESP_I_PD;
                    end
                    `L15_MESI_STATE_S, `L15_MESI_STATE_E:
                    begin
                        msg_resp = `CHIE_SNP_RESP_I;
                    end
                endcase
            end


            msg_qos = 1;
            msg_tgtid = HNF_NID_PARAM; //dest_chipid;  homenodeid
            msg_srcid = RNF_NID;
            //msg_txnid = msg_mshrid;
            msg_txnid = l15_noc3buffer_req_rxsnp_txnid;
            msg_homenid = HNF_NID_PARAM;
            msg_resperr = 'b0;
            msg_fwdstate = 3'b000; // In non-forwarding snp-responses this is datasource(implementation defined, default 000)
            msg_ccid = last_subcacheline_id;    // CriticalChunkID, addr_5_4
            msg_pe = 2'b11;     // txdat_wrap determines this as it sends the whole 512bit cacheline in two parts(2x256bit)
            msg_data = data_reg;


        end
        `L15_NOC3_REQTYPE_ICACHE_INVAL_ACK:
        begin
            // specify sequence id + if is last
            msg_type = `MSG_TYPE_INV_FWDACK;
            msg_length = 0;
        end
    endcase



    // ACK logic to l15-pipeline
    if (l15_noc3encoder_req_val_i && !data_rdy) begin
        noc3encoder_l15_req_ack = 1'b1;
    end else begin
        noc3encoder_l15_req_ack = 1'b0;
    end

    // ACK to rx_control
    if (rxbuf_rspenc_txdat_valid && rxbuf_txdat_pending && cb_data_sent) begin     
        rspenc_rxbuf_ack = 1'b1;
    end else begin
        rspenc_rxbuf_ack = 1'b0;
    end


end
endmodule
