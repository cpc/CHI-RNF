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
//  Filename        : rx_decoder (original noc2decoder)
//  Original Author : Princeton University
//  Modified        : Teemu Rinne, Tampere University
//
//  Description     : Inbound response decoder of AMBA CHI based RN-F coherent cache
//
//==================================================================================================



`include "l15.tmp.h"
`include "chie_defines.v"

`ifdef DEFAULT_NETTYPE_NONE
`default_nettype none
`endif
module rx_decoder (
    input wire clk,
    input wire rst_n,

    // Message-info header carried in bits [63:0]; 512b cacheline payload in bits [575:64].
    input wire [575:0] noc2_data,
    input wire noc2_data_val,
    input wire l15_noc2decoder_ack,
    input wire l15_noc2decoder_header_ack,
    // Full-width CHI txnid of the snoop carried by noc2_data, forwarded
    // separately from noc2_data (see rx_control.rxctrl_l15_txnid).
    input wire [`CHIE_SNP_FLIT_TXNID_WIDTH-1:0] rxctrl_l15_txnid,
    output reg noc2_data_ack,
    output reg noc2decoder_l15_val,
    output reg [`L15_MSHR_ID_WIDTH-1:0] noc2decoder_l15_mshrid,
    output reg [`L15_THREADID_MASK] noc2decoder_l15_threadid,
    output reg noc2decoder_l15_hmc_fill,
    output reg noc2decoder_l15_l2miss,
    output reg noc2decoder_l15_icache_type,
    output reg noc2decoder_l15_f4b,
    output reg [`MSG_TYPE_WIDTH-1:0] noc2decoder_l15_reqtype,
    output reg [`L15_MESI_STATE_WIDTH-1:0] noc2decoder_l15_ack_state,
    output reg [511:0] noc2decoder_l15_data,
    output reg [39:0] noc2decoder_l15_address,
    output reg [3:0] noc2decoder_l15_fwd_subcacheline_vector,
    output reg [`L15_CSM_NUM_TICKETS_LOG2-1:0] noc2decoder_l15_csm_mshrid,
    output reg [`PACKET_HOME_ID_WIDTH-1:0] noc2decoder_l15_src_homeid,
    output reg [`CHIE_SNP_FLIT_TXNID_WIDTH-1:0] noc2decoder_l15_txnid
    );


reg is_message_new;
reg is_message_new_next;
always @ (posedge clk)
begin
    if (!rst_n)
      is_message_new <= 1'b1;
    else
      is_message_new <= is_message_new_next;
end

reg [`MSG_MSHRID_WIDTH-1:0] noc2_mshrid;
reg [`MSG_LENGTH_WIDTH-1:0] msg_len;
always @ *
begin
    noc2_data_ack = l15_noc2decoder_ack;
    noc2decoder_l15_val = noc2_data_val && is_message_new;
    noc2decoder_l15_txnid = rxctrl_l15_txnid;

    // these are shared by both requests and replies from L2
    noc2decoder_l15_reqtype = noc2_data[`MSG_TYPE];
    msg_len = noc2_data[`MSG_LENGTH];
    
    noc2_mshrid = noc2_data[`MSG_MSHRID];
    noc2decoder_l15_mshrid = noc2_mshrid[`L15_MSHR_ID_WIDTH-1:0];
    noc2decoder_l15_csm_mshrid = noc2_mshrid[`L15_CSM_NUM_TICKETS_LOG2-1:0];
    // the threadid is encoded in the mshrid sent to L2, is the next L15_THREADID_WIDTH bits after the first L15_MSHR_ID_WIDTH bits
    noc2decoder_l15_threadid = noc2_mshrid[`L15_MSHR_ID_WIDTH+`L15_THREADID_WIDTH -1 -: `L15_THREADID_WIDTH];
    noc2decoder_l15_hmc_fill = noc2_mshrid[`MSG_MSHRID_WIDTH-1];

    noc2decoder_l15_l2miss = noc2_data[`MSG_L2_MISS];
    noc2decoder_l15_icache_type = noc2_data[`MSG_CACHE_TYPE];
    noc2decoder_l15_f4b = 0;
    noc2decoder_l15_ack_state = noc2_data[`MSG_MESI];
    noc2decoder_l15_fwd_subcacheline_vector = noc2_data[`MSG_SUBLINE_VECTOR];
    noc2decoder_l15_address = noc2_data[`MSG_ADDR];

    // Native 64B NOC: the 512b cacheline is carried as a single contiguous field
    // at noc2_data[575:64]. Slicing mirrors the prior 8x64b concat so that the
    // pipeline sees the lowest-address 8B of the line at noc2decoder_l15_data[511:448]
    // and the highest-address 8B at [63:0].
    //
    // For single-flit messages (msg_len == 1, e.g. non-cacheable replies) the one
    // data flit at noc2_data[2*64-1 -: 64] is cloned across the first 4x64b chunks
    // of the data port (top 256b)
    if (msg_len == `MSG_LENGTH_WIDTH'd1) begin
        noc2decoder_l15_data = {
            noc2_data[2*64 - 1 -: 64],
            noc2_data[2*64 - 1 -: 64],
            noc2_data[2*64 - 1 -: 64],
            noc2_data[2*64 - 1 -: 64],
            noc2_data[6*64 - 1 -: 64],
            noc2_data[7*64 - 1 -: 64],
            noc2_data[8*64 - 1 -: 64],
            noc2_data[9*64 - 1 -: 64]
        };
    end
    else begin
        noc2decoder_l15_data = {
            noc2_data[2*64 - 1 -: 64],
            noc2_data[3*64 - 1 -: 64],
            noc2_data[4*64 - 1 -: 64],
            noc2_data[5*64 - 1 -: 64],
            noc2_data[6*64 - 1 -: 64],
            noc2_data[7*64 - 1 -: 64],
            noc2_data[8*64 - 1 -: 64],
            noc2_data[9*64 - 1 -: 64]
        };
    end

    noc2decoder_l15_src_homeid = 0;
    noc2decoder_l15_src_homeid[`PACKET_HOME_ID_Y_MASK] = noc2_data[`MSG_SRC_Y];
    noc2decoder_l15_src_homeid[`PACKET_HOME_ID_X_MASK] = noc2_data[`MSG_SRC_X];
    noc2decoder_l15_src_homeid[`PACKET_HOME_ID_CHIP_MASK] = noc2_data[`MSG_SRC_CHIPID];

    // is_message_new is 1 on a new message, even if it's not valid yet
    // when header ack is received, it becomes 0 until the next "new" message
    // otherwise retain the newness value
    is_message_new_next = l15_noc2decoder_ack ? 1'b1 :
                                 l15_noc2decoder_header_ack ? 1'b0 : is_message_new;
end


endmodule
