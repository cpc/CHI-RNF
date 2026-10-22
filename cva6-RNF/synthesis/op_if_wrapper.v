
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

//==================================================================================================
//  Filename      : l15.v
//  Created On    : 2014-01-31 12:52:57
//  Last Modified : 2015-01-22 17:39:39
//  Revision      :
//  Author        : Tri Nguyen
//  Company       : Princeton University
//  Email         : trin@princeton.edu
//
//  Description   : L1.5 top module
//
//
//==================================================================================================

//`timescale 1 ns / 10 ps
//`include "../../include/l15.tmp.h"
`include "l15_op.tmp.h"
//`include "../../include/lsu.tmp.h"
`include "lsu.tmp.h"
`include "define.tmp.h"
`include "dmbr_define.v"

`ifdef DEFAULT_NETTYPE_NONE
`default_nettype none
`endif
module op_if_wrapper (
    input                                   clk,
    input                                   rst_n,
    
    input                                   dmbr_l15_stall,
    input [`NOC_CHIPID_WIDTH-1:0]           chipid,
    input [`NOC_X_WIDTH-1:0]                coreid_x,
    input [`NOC_Y_WIDTH-1:0]                coreid_y,
    
    output [`NOC_DATA_WIDTH-1:0]          buffer_router_data_noc1,
    output                                buffer_router_valid_noc1,
    input                                router_buffer_consumed_noc1,
    output [`NOC_DATA_WIDTH-1:0]          buffer_router_data_noc3,
    output                                buffer_router_valid_noc3,
    input                                router_buffer_consumed_noc3,
    input [`NOC_DATA_WIDTH-1:0]          router_buffer_data_noc2,
    input                                router_buffer_data_val_noc2,
    output                                buffer_router_yummy_noc2,

    output                                  l15_dmbr_l1missIn,
    output [`DMBR_TAG_WIDTH-1:0]            l15_dmbr_l1missTag,


    // OP L1.5 to IF
    input [`MSG_SDID_WIDTH-1:0] noc1buffer_noc1encoder_req_csm_sdid,
    input [`MSG_LSID_WIDTH-1:0] noc1buffer_noc1encoder_req_csm_lsid,
    input [`L15_NOC1_REQTYPE_WIDTH-1:0] noc1buffer_noc1encoder_req_type,
    input [`L15_THREADID_MASK] noc1buffer_noc1encoder_req_threadid,
    input [`L15_MSHR_ID_WIDTH-1:0] noc1buffer_noc1encoder_req_mshrid,
    input [`L15_PADDR_HI:0] noc1buffer_noc1encoder_req_address,
    input noc1buffer_noc1encoder_req_non_cacheable,
    input [2:0] noc1buffer_noc1encoder_req_size,
    input noc1buffer_noc1encoder_req_prefetch,
    input [63:0] noc1buffer_noc1encoder_req_data_0,
    input [63:0] noc1buffer_noc1encoder_req_data_1,
    input [`PACKET_HOME_ID_WIDTH-1:0] noc1buffer_noc1encoder_req_homeid,
    output noc1encoder_noc1buffer_req_ack,
    input noc1buffer_noc1encoder_req_val,
    output noc1encoder_csm_req_ack,
    input csm_noc1encoder_req_val,
    input [`L15_NOC1_REQTYPE_WIDTH-1:0] csm_noc1encoder_req_type,
    input [`L15_CSM_NUM_TICKETS_LOG2-1:0] csm_noc1encoder_req_mshrid,
    input [`PHY_ADDR_WIDTH-1:0] csm_noc1encoder_req_address,
    input csm_noc1encoder_req_non_cacheable,
    input  [`PCX_SIZE_WIDTH-1:0] csm_noc1encoder_req_size,


    output noc3encoder_noc3buffer_req_ack,
    input noc3buffer_noc3encoder_req_val,
    input [`L15_NOC3_REQTYPE_WIDTH-1:0] noc3buffer_noc3encoder_req_type,
    input [63:0] noc3buffer_noc3encoder_req_data_0,
    input [63:0] noc3buffer_noc3encoder_req_data_1,
    input [`L15_MSHR_ID_WIDTH-1:0] noc3buffer_noc3encoder_req_mshrid,
    input [1:0] noc3buffer_noc3encoder_req_sequenceid,
    input [`L15_THREADID_MASK] noc3buffer_noc3encoder_req_threadid,
    input [`L15_PADDR_HI:0] noc3buffer_noc3encoder_req_address,
    input noc3buffer_noc3encoder_req_with_data,
    input noc3buffer_noc3encoder_req_was_inval,
    input [3:0] noc3buffer_noc3encoder_req_fwdack_vector,
    input [`PACKET_HOME_ID_WIDTH-1:0] noc3buffer_noc3encoder_req_homeid,

    output [511:0] noc2_data,
    output noc2_data_val,
    input noc2_data_ack

);

    wire                                   noc1_out_rdy;
    wire                                   noc2_in_val;
    wire [`NOC_DATA_WIDTH-1:0]             noc2_in_data;
    wire                                   noc3_out_rdy;
    wire                                  noc1_out_val;
    wire [`NOC_DATA_WIDTH-1:0]            noc1_out_data;
    wire                                  noc2_in_rdy;
    wire                                  noc3_out_val;
    wire [`NOC_DATA_WIDTH-1:0]            noc3_out_data;

    valrdy_to_credit #(16, 5) cgno_blk1(
        .clk(clk),
        .reset(~rst_n),
        .data_in(noc1_out_data),
        .valid_in(noc1_out_val),
        .ready_in(noc1_out_rdy),

        .data_out(buffer_router_data_noc1),           // Data
        .valid_out(buffer_router_valid_noc1),       // Val signal
        .yummy_out(router_buffer_consumed_noc1)    // Yummy signal
    );

    valrdy_to_credit #(16, 5) cgno_blk3(
        .clk(clk),
        .reset(~rst_n),
        .data_in(noc3_out_data),
        .valid_in(noc3_out_val),
        .ready_in(noc3_out_rdy),

        .data_out(buffer_router_data_noc3),           // Data
        .valid_out(buffer_router_valid_noc3),       // Val signal
        .yummy_out(router_buffer_consumed_noc3)    // Yummy signal
    );


    credit_to_valrdy cgni_blk2(
        .clk(clk),
        .reset(~rst_n),
        .data_in(router_buffer_data_noc2),
        .valid_in(router_buffer_data_val_noc2),
        .yummy_in(buffer_router_yummy_noc2),

        .data_out(noc2_in_data),           // Data
        .valid_out(noc2_in_val),       // Val signal from dynamic network to processor
        .ready_out(noc2_in_rdy)    // Rdy signal from processor to dynamic network
    );


simplenocbuffer simplenocbuffer(
    .clk(clk),
    .rst_n(rst_n),
    .noc_in_val(noc2_in_val),
    .noc_in_data(noc2_in_data),
    .msg_ack(noc2_data_ack),
    .noc_in_rdy(noc2_in_rdy),
    .msg(noc2_data),
    .msg_val(noc2_data_val)
);



noc1encoder noc1encoder(
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
    // .noc1buffer_noc1encoder_req_blkstore(noc1buffer_noc1encoder_req_blkstore),
    // .noc1buffer_noc1encoder_req_blkinitstore(noc1buffer_noc1encoder_req_blkinitstore),
    .noc1buffer_noc1encoder_req_csm_sdid(noc1buffer_noc1encoder_req_csm_sdid),
    .noc1buffer_noc1encoder_req_csm_lsid(noc1buffer_noc1encoder_req_csm_lsid),
    .noc1buffer_noc1encoder_req_homeid(noc1buffer_noc1encoder_req_homeid),
    
    .dmbr_l15_stall(dmbr_l15_stall),
    .chipid(chipid),
    .coreid_x(coreid_x),
    .coreid_y(coreid_y),
    .noc1out_ready(noc1_out_rdy),
    
    .l15_dmbr_l1missIn(l15_dmbr_l1missIn),
    .l15_dmbr_l1missTag(l15_dmbr_l1missTag),
    .noc1encoder_noc1buffer_req_ack(noc1encoder_noc1buffer_req_ack),
    .noc1encoder_noc1out_val(noc1_out_val),
    .noc1encoder_noc1out_data(noc1_out_data),
    
    // csm interface
    .noc1encoder_csm_req_ack(noc1encoder_csm_req_ack),
    .csm_noc1encoder_req_val(csm_noc1encoder_req_val),
    .csm_noc1encoder_req_type(csm_noc1encoder_req_type),
    .csm_noc1encoder_req_mshrid(csm_noc1encoder_req_mshrid),
    .csm_noc1encoder_req_address(csm_noc1encoder_req_address),
    .csm_noc1encoder_req_non_cacheable(csm_noc1encoder_req_non_cacheable),
    .csm_noc1encoder_req_size(csm_noc1encoder_req_size)
);



noc3encoder noc3encoder(
    .clk(clk),
    .rst_n(rst_n),
    .l15_noc3encoder_req_val(noc3buffer_noc3encoder_req_val),
    .l15_noc3encoder_req_type(noc3buffer_noc3encoder_req_type),
    .l15_noc3encoder_req_data_0(noc3buffer_noc3encoder_req_data_0),
    .l15_noc3encoder_req_data_1(noc3buffer_noc3encoder_req_data_1),
    .l15_noc3encoder_req_mshrid(noc3buffer_noc3encoder_req_mshrid),
    .l15_noc3encoder_req_sequenceid(noc3buffer_noc3encoder_req_sequenceid),
    .l15_noc3encoder_req_threadid(noc3buffer_noc3encoder_req_threadid),
    .l15_noc3encoder_req_address(noc3buffer_noc3encoder_req_address),
    .l15_noc3encoder_req_with_data(noc3buffer_noc3encoder_req_with_data),
    .l15_noc3encoder_req_was_inval(noc3buffer_noc3encoder_req_was_inval),
    .l15_noc3encoder_req_fwdack_vector(noc3buffer_noc3encoder_req_fwdack_vector),
    .l15_noc3encoder_req_homeid(noc3buffer_noc3encoder_req_homeid),
    .chipid(chipid),
    .coreid_x(coreid_x),
    .coreid_y(coreid_y),
    .noc3out_ready(noc3_out_rdy),
    .noc3encoder_l15_req_ack(noc3encoder_noc3buffer_req_ack),
    .noc3encoder_noc3out_val(noc3_out_val),
    .noc3encoder_noc3out_data(noc3_out_data)
);

endmodule
