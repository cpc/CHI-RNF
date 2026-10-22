// Original work:
/*
* Copyright (c) 2024 Beijing Institute of Open Source Chip
* OpenNoC is licensed under Mulan PSL v2.
* You can use this software according to the terms and conditions of the Mulan PSL v2.
* You may obtain a copy of Mulan PSL v2 at:
*          http://license.coscl.org.cn/MulanPSL2
* THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
* EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
* MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
* See the Mulan PSL v2 for more details.
*
* Author:
*    Qichao Xie <xieqichao@bosc.ac.cn>
*    Chunyan Lin <linchunyan@bosc.ac.cn>
*/


// Modifications: 
/*
 * Copyright (c) 2026 Tampere University
 * Licensed under the Solderpad Hardware License v 2.1, see LICENSE for details.
 * SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
 */

//==================================================================================================
//  Filename        : rnf_link_rxrsp_parse (original hnf_link_rxrsp_parse)
//  Modified        : Teemu Rinne, Tampere University
//
//  Description     : RXRSP channel interface of AMBA CHI based RN-F link layer interface 
//
//==================================================================================================


`include "chie_defines.v"
`include "rnf_defines.v"
`include "rnf_param.v"

module rnf_link_rxrsp_parse `RNF_PARAM
    (
        //global inputs
        clk,
        rst,

        rxrspflitv,
        rxrspflit,
        rxrspflitpend,

        rxrsp_lcrdv,

        li_mshr_rxrsp_valid_s0,
        li_mshr_rxrsp_srcid_s0,
        li_mshr_rxrsp_txnid_s0,
        li_mshr_rxrsp_opcode_s0,
        li_mshr_rxrsp_resp_s0,
        li_mshr_rxrsp_fwdstate_s0,
        li_mshr_rxrsp_dbid_s0,
        li_mshr_rxrsp_pcrdtype_s0,
        rxrsp_buf_ready,
        
        rx_ready,
        rx_lcredits_returned
    );

    //global inputs
    input wire                                      clk;
    input wire                                      rst;

    input wire                                      rxrspflitv;
    input wire [`CHIE_RSP_FLIT_RANGE]               rxrspflit;
    input wire                                      rxrspflitpend;

    output wire                                     rxrsp_lcrdv;

    output wire                                     li_mshr_rxrsp_valid_s0;
    output wire [`CHIE_RSP_FLIT_SRCID_WIDTH-1:0]    li_mshr_rxrsp_srcid_s0;
    output wire [`CHIE_RSP_FLIT_TXNID_WIDTH-1:0]    li_mshr_rxrsp_txnid_s0;
    output wire [`CHIE_RSP_FLIT_OPCODE_WIDTH-1:0]   li_mshr_rxrsp_opcode_s0;
    output wire [`CHIE_RSP_FLIT_RESP_WIDTH-1:0]     li_mshr_rxrsp_resp_s0;
    output wire [`CHIE_RSP_FLIT_FWDSTATE_WIDTH-1:0] li_mshr_rxrsp_fwdstate_s0;
    output wire [`CHIE_RSP_FLIT_DBID_WIDTH-1:0]     li_mshr_rxrsp_dbid_s0;
    output wire [`CHIE_RSP_FLIT_PCRDTYPE_WIDTH-1:0] li_mshr_rxrsp_pcrdtype_s0;

    input wire                                      rxrsp_buf_ready;


    input wire rx_ready;                        // signal for IFs that L-credits can be given
    output wire rx_lcredits_returned;           // if all L-credits are returned when transmitter entering lowpower

    //internal reg signals
    reg                                             rxrspflitv_en_q;
    reg  [`RNF_LCRD_RXRSP_CNT_WIDTH-1:0]            rxrsp_crd_cnt_s1_q;
    reg  [3:0]                                      rxrsp_crd_sm_out;
    reg                                             rxrspcrdv_s1_q;

    //internal wire signals
    wire                                            rxcrd_enable_s0;
    wire                                            rxrsp_crd_cnt_zero;
    wire [2:0]                                      rxrsp_crd_sm_in;
    wire                                            rxrsp_crd_cnt_upd_s0;
    wire                                            rxrsp_crd_cnt_inc1_s0;
    wire                                            rxrsp_crd_cnt_dec1_s0;
    wire [`RNF_LCRD_RXRSP_CNT_WIDTH-1:0]            rxrsp_crd_cnt_dec1_val_s0;
    wire [`RNF_LCRD_RXRSP_CNT_WIDTH-1:0]            rxrsp_crd_cnt_inc1_val_s0;
    wire [`RNF_LCRD_RXRSP_CNT_RANGE]                rxrsp_crd_cnt_nxt_s0;
    wire                                            rxrspcrdv_ns_s0;

    //main function
    //receive rxrspflitpend
    always @(posedge clk or posedge rst)begin : rxrspflitv_en_q_logic_t
        if(rst == 1'b1)
            rxrspflitv_en_q <= 1'b0;
        else if (rxrspflitpend == 1'b1)
            rxrspflitv_en_q <= 1'b1;
        else
            rxrspflitv_en_q <= 1'b0;
    end

    //rxrsp decode
    assign li_mshr_rxrsp_valid_s0      = (rxrspflitv == 1'b1);
    assign li_mshr_rxrsp_srcid_s0      = (rxrspflitv == 1'b1)? rxrspflit[`CHIE_RSP_FLIT_SRCID_RANGE]     :{`CHIE_RSP_FLIT_SRCID_WIDTH{1'b0}};
    assign li_mshr_rxrsp_txnid_s0      = (rxrspflitv == 1'b1)? rxrspflit[`CHIE_RSP_FLIT_TXNID_RANGE]     :{`CHIE_RSP_FLIT_TXNID_WIDTH{1'b0}};
    assign li_mshr_rxrsp_opcode_s0     = (rxrspflitv == 1'b1)? rxrspflit[`CHIE_RSP_FLIT_OPCODE_RANGE]    :{`CHIE_RSP_FLIT_OPCODE_WIDTH{1'b0}};
    assign li_mshr_rxrsp_resp_s0       = (rxrspflitv == 1'b1)? rxrspflit[`CHIE_RSP_FLIT_RESP_RANGE]      :{`CHIE_RSP_FLIT_RESP_WIDTH{1'b0}};
    assign li_mshr_rxrsp_fwdstate_s0   = (rxrspflitv == 1'b1)? rxrspflit[`CHIE_RSP_FLIT_FWDSTATE_RANGE]  :{`CHIE_RSP_FLIT_FWDSTATE_WIDTH{1'b0}};
    assign li_mshr_rxrsp_dbid_s0       = (rxrspflitv == 1'b1)? rxrspflit[`CHIE_RSP_FLIT_DBID_RANGE]      :{`CHIE_RSP_FLIT_DBID_WIDTH{1'b0}};
    assign li_mshr_rxrsp_pcrdtype_s0   = (rxrspflitv == 1'b1)? rxrspflit[`CHIE_RSP_FLIT_PCRDTYPE_RANGE]  :{`CHIE_RSP_FLIT_PCRDTYPE_WIDTH{1'b0}};

    //rx lcrd enable
    assign rxcrd_enable_s0 = rxrsp_buf_ready && rx_ready; 


    //if lcrd is zero
    assign rxrsp_crd_cnt_zero = (rxrsp_crd_cnt_s1_q == `RNF_LCRD_RXRSP_CNT_WIDTH'd`RNF_LCRD_RXRSP_CNT_LIMIT);       // (rxrsp_crd_cnt_s1_q == {`RNF_LCRD_RXRSP_CNT_WIDTH{1'b0}});

    assign rx_lcredits_returned = (rxrsp_crd_cnt_s1_q == {`RNF_LCRD_RXRSP_CNT_WIDTH{1'b1}});

    //rxrsp_crd state maching input
    //enable sending crd
    assign rxrsp_crd_sm_in[2] = rxcrd_enable_s0;

    //crd count == 0
    assign rxrsp_crd_sm_in[1] = rxrsp_crd_cnt_zero;

    //receive responses except RespLCrdReturn
    assign rxrsp_crd_sm_in[0] = li_mshr_rxrsp_valid_s0;

    //rxrsplcrdv logic
    // ---------------------------- input ---------------------------- // // ---------- output ------------//
    // rxcrd_enable_s0 rxrsp_crd_cnt_zero rsp_flitv //      // lcrdupdate crdv inc1 dec1//
    //        1                      0            0                1       1    0    1      4'b1101   dec -1
    //        1                      0            1                1       0    1    0      4'b1010   inc +1     OLD: 0       1    0    0      4'b0100   no_change
    //        1                      1            0                0       0    0    0      4'b0000   no_change
    //        1                      1            1                1       0    1    0      4'b1010   inc +1     OLD: 0       1    0    0      4'b0100   no_change

    // TR: Update for OpenPiton integration, unenable credit if rxdat buffer is full (credit count might have to be set according buffer size)
    //        0                      1            1                1       0    1    0                inc +1
    //        0                      0            1                1       0    1    0                inc +1
    //        0                      0            0                0       0    0    0
    //
    // Other notes, TR: 
    //              - the credit count is lowered to size of 1 for the time of testing with the testbench

    //sm outputs
    always @(*) begin:rxrsplcrdv_logic_t
        casez (rxrsp_crd_sm_in)
            3'b100:
                rxrsp_crd_sm_out[3:0] = 4'hd;
            3'b101:
                rxrsp_crd_sm_out[3:0] = 4'b1010;    //OLD: 4'h4;
            3'b110:
                rxrsp_crd_sm_out[3:0] = 4'h0;
            3'b111:
                rxrsp_crd_sm_out[3:0] = 4'b1010;    //OLD: 4'h4;
            3'b011:
                rxrsp_crd_sm_out[3:0] = 4'b1010;
            3'b001:
                rxrsp_crd_sm_out[3:0] = 4'b1010;
            default:
                rxrsp_crd_sm_out[3:0] = 4'h0;
        endcase
    end

    assign rxrsp_crd_cnt_upd_s0  = rxrsp_crd_sm_out[3];
    assign rxrspcrdv_ns_s0       = rxrsp_crd_sm_out[2];
    assign rxrsp_crd_cnt_inc1_s0 = rxrsp_crd_sm_out[1];
    assign rxrsp_crd_cnt_dec1_s0 = rxrsp_crd_sm_out[0];

    assign rxrsp_crd_cnt_dec1_val_s0 = rxrsp_crd_cnt_s1_q - `RNF_LCRD_INCDEC_ONE;
    assign rxrsp_crd_cnt_inc1_val_s0 = rxrsp_crd_cnt_s1_q + `RNF_LCRD_INCDEC_ONE;

    //update next credit value
    assign rxrsp_crd_cnt_nxt_s0 = rxrsp_crd_cnt_dec1_s0 ? rxrsp_crd_cnt_dec1_val_s0:
           rxrsp_crd_cnt_inc1_val_s0;

    always @(posedge clk or posedge rst) begin: rxrsp_crd_cnt_s1_q_logic_t
        if (rst == 1'b1)
            rxrsp_crd_cnt_s1_q <= XP_LCRD_NUM_PARAM;
        else if (rxrsp_crd_cnt_upd_s0 == 1'b1)
            rxrsp_crd_cnt_s1_q <= rxrsp_crd_cnt_nxt_s0;
    end

    always @(posedge clk or posedge rst) begin: rxrspcrdv_s1_q_logic_t
        if (rst == 1'b1)
            rxrspcrdv_s1_q <= 1'b0;
        else
            rxrspcrdv_s1_q <= rxrspcrdv_ns_s0;
    end

    assign rxrsp_lcrdv = rxrspcrdv_s1_q;

endmodule
