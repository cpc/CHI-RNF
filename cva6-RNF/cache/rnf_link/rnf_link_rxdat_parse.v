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
*    Li Zhao <lizhao@bosc.ac.cn>
*/


// Modifications: 
/*
 * Copyright (c) 2026 Tampere University
 * Licensed under the Solderpad Hardware License v 2.1, see LICENSE for details.
 * SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
 */

//==================================================================================================
//  Filename        : rnf_link_rxdat_parse (original hnf_link_rxdat_parse)
//  Modified        : Teemu Rinne, Tampere University
//
//  Description     : RXDAT channel interface of AMBA CHI based RN-F link layer interface 
//
//==================================================================================================


`include "chie_defines.v"
`include "rnf_defines.v"
`include "rnf_param.v"

module rnf_link_rxdat_parse `RNF_PARAM
    (
        //global inputs
        clk,
        rst,

        rxdatflitv,
        rxdatflit,
        rxdatflitpend,

        rxdat_lcrdv,

        li_mshr_rxdat_valid_s0,
        li_mshr_rxdat_txnid_s0,
        li_mshr_rxdat_opcode_s0,
        li_mshr_rxdat_resp_s0,
        li_mshr_rxdat_fwdstate_s0,
        li_mshr_rxdat_dataid_s0,
        li_decoder_rxdat_homenid,
        li_decoder_rxdat_ccid,
        li_decoder_rxdat_dbid,

        li_dbf_rxdat_valid_s0,
        li_dbf_rxdat_txnid_s0,
        li_dbf_rxdat_opcode_s0,
        li_dbf_rxdat_dataid_s0,
        li_dbf_rxdat_be_s0,
        li_dbf_rxdat_data_s0,
        rxdat_buf_ready,

        rx_ready,
        rx_lcredits_returned
    );

    //global inputs
    input wire                                      clk;
    input wire                                      rst;

    input wire                                      rxdatflitv;
    input wire [`CHIE_DAT_FLIT_RANGE]               rxdatflit;
    input wire                                      rxdatflitpend;

    input wire                                      rxdat_buf_ready;

    output wire                                     rxdat_lcrdv;

    output wire                                     li_mshr_rxdat_valid_s0;
    output wire [`CHIE_DAT_FLIT_TXNID_WIDTH-1:0]    li_mshr_rxdat_txnid_s0;
    output wire [`CHIE_DAT_FLIT_OPCODE_WIDTH-1:0]   li_mshr_rxdat_opcode_s0;
    output wire [`CHIE_DAT_FLIT_RESP_WIDTH-1:0]     li_mshr_rxdat_resp_s0;
    output wire [`CHIE_DAT_FLIT_FWDSTATE_WIDTH-1:0] li_mshr_rxdat_fwdstate_s0;
    output wire [`CHIE_DAT_FLIT_DATAID_WIDTH-1:0]   li_mshr_rxdat_dataid_s0;

    output wire [`CHIE_DAT_FLIT_HOMENID_WIDTH-1:0]  li_decoder_rxdat_homenid;
    output wire [`CHIE_DAT_FLIT_CCID_WIDTH-1:0]     li_decoder_rxdat_ccid;
    output wire [`CHIE_DAT_FLIT_DBID_WIDTH-1:0]     li_decoder_rxdat_dbid;

    output wire                                     li_dbf_rxdat_valid_s0;
    output wire [`CHIE_DAT_FLIT_TXNID_WIDTH-1:0]    li_dbf_rxdat_txnid_s0;
    output wire [`CHIE_DAT_FLIT_OPCODE_WIDTH-1:0]   li_dbf_rxdat_opcode_s0;
    output wire [`CHIE_DAT_FLIT_DATAID_WIDTH-1:0]   li_dbf_rxdat_dataid_s0;
    output wire [`CHIE_DAT_FLIT_BE_WIDTH-1:0]       li_dbf_rxdat_be_s0;
    output wire [`CHIE_DAT_FLIT_DATA_WIDTH-1:0]     li_dbf_rxdat_data_s0;

    input wire rx_ready;                       // signal for IFs that L-credits can be given
    output wire rx_lcredits_returned;      // if all L-credits are returned when transmitter entering lowpower

    //internal reg signals
    reg                                             rxdatflitv_en_q;
    reg  [`RNF_LCRD_DAT_CNT_WIDTH-1:0]            rxdat_crd_cnt_s1_q;
    reg  [3:0]                                      rxdat_crd_sm_out;
    reg                                             rxdatcrdv_s1_q;

    //internal wire signals
    wire [`CHIE_DAT_FLIT_TXNID_WIDTH-1:0]           li_dbf_rxdat_txnid_s0_raw;
    wire                                            rxcrd_enable_s0;
    wire                                            rxdat_crd_cnt_zero;
    wire [2:0]                                      rxdat_crd_sm_in;
    wire                                            rxdat_crd_cnt_upd_s0;
    wire                                            rxdat_crd_cnt_inc1_s0;
    wire                                            rxdat_crd_cnt_dec1_s0;
    wire [`RNF_LCRD_DAT_CNT_WIDTH-1:0]            rxdat_crd_cnt_dec1_val_s0;
    wire [`RNF_LCRD_DAT_CNT_WIDTH-1:0]            rxdat_crd_cnt_inc1_val_s0;
    wire [`RNF_LCRD_DAT_CNT_RANGE]                rxdat_crd_cnt_nxt_s0;
    wire                                            rxdatcrdv_ns_s0;

    //main function
    always @(posedge clk or posedge rst) begin:rxdatflitv_en_q_logic_t
        if(rst == 1'b1)
            rxdatflitv_en_q <= 1'b0;
        else if(rxdatflitpend == 1'b1)
            rxdatflitv_en_q <= 1'b1;
        else
            rxdatflitv_en_q <= 1'b0;
    end



    //rxdat decode
    assign li_mshr_rxdat_valid_s0    = (rxdatflitv == 1'b1);
    assign li_mshr_rxdat_txnid_s0    = (rxdatflitv == 1'b1)? rxdatflit[`CHIE_DAT_FLIT_TXNID_RANGE]    : {`CHIE_DAT_FLIT_TXNID_WIDTH{1'b0}};
    assign li_mshr_rxdat_opcode_s0   = (rxdatflitv == 1'b1)? rxdatflit[`CHIE_DAT_FLIT_OPCODE_RANGE]   : {`CHIE_DAT_FLIT_OPCODE_WIDTH{1'b0}};
    assign li_mshr_rxdat_resp_s0     = (rxdatflitv == 1'b1)? rxdatflit[`CHIE_DAT_FLIT_RESP_RANGE]     : {`CHIE_DAT_FLIT_RESP_WIDTH{1'b0}};
    assign li_mshr_rxdat_fwdstate_s0 = (rxdatflitv == 1'b1)? rxdatflit[`CHIE_DAT_FLIT_FWDSTATE_RANGE] : {`CHIE_DAT_FLIT_FWDSTATE_WIDTH{1'b0}};
    assign li_mshr_rxdat_dataid_s0   = (rxdatflitv == 1'b1)? rxdatflit[`CHIE_DAT_FLIT_DATAID_RANGE]   : {`CHIE_DAT_FLIT_DATAID_WIDTH{1'b0}};

    assign li_dbf_rxdat_valid_s0     = (rxdatflitv == 1'b1);
    assign li_dbf_rxdat_txnid_s0_raw = (rxdatflitv == 1'b1)? rxdatflit[`CHIE_DAT_FLIT_TXNID_RANGE]    : {`CHIE_DAT_FLIT_TXNID_WIDTH{1'b0}};
    assign li_dbf_rxdat_txnid_s0     = li_dbf_rxdat_txnid_s0_raw[`CHIE_DAT_FLIT_TXNID_WIDTH-1:0];
    assign li_dbf_rxdat_opcode_s0    = (rxdatflitv == 1'b1 && ((|rxdatflit[`CHIE_DAT_FLIT_BE_RANGE]) || (rxdatflit[`CHIE_DAT_FLIT_OPCODE_RANGE] == `CHIE_COMPDATA)))? rxdatflit[`CHIE_DAT_FLIT_OPCODE_RANGE] :`CHIE_WRITEDATACANCEL;
    assign li_dbf_rxdat_dataid_s0    = (rxdatflitv == 1'b1)? rxdatflit[`CHIE_DAT_FLIT_DATAID_RANGE]   : {`CHIE_DAT_FLIT_DATAID_WIDTH{1'b0}};
    assign li_dbf_rxdat_be_s0        = (rxdatflitv == 1'b1)? rxdatflit[`CHIE_DAT_FLIT_BE_RANGE]       : {`CHIE_DAT_FLIT_BE_WIDTH{1'b0}};
    assign li_dbf_rxdat_data_s0      = (rxdatflitv == 1'b1)? rxdatflit[`CHIE_DAT_FLIT_DATA_RANGE]     : {`CHIE_DAT_FLIT_DATA_WIDTH{1'b0}};


    assign li_decoder_rxdat_homenid  = (rxdatflitv == 1'b1)? rxdatflit[`CHIE_DAT_FLIT_HOMENID_RANGE] : {`CHIE_DAT_FLIT_HOMENID_WIDTH{1'b0}};
    assign li_decoder_rxdat_ccid     = (rxdatflitv == 1'b1)? rxdatflit[`CHIE_DAT_FLIT_CCID_RANGE] : {`CHIE_DAT_FLIT_CCID_WIDTH{1'b0}};
    assign li_decoder_rxdat_dbid     = (rxdatflitv == 1'b1)? rxdatflit[`CHIE_DAT_FLIT_DBID_RANGE] : {`CHIE_DAT_FLIT_DBID_WIDTH{1'b0}};



    //rx lcrd enable
    //assign rxcrd_enable_s0 = 1'b1;
    assign rxcrd_enable_s0 = rxdat_buf_ready && rx_ready;


    //if lcrd is zero
    assign rxdat_crd_cnt_zero = (rxdat_crd_cnt_s1_q == `RNF_LCRD_RXDAT_CNT_LIMIT);   //(rxdat_crd_cnt_s1_q == `RNF_LCRD_DAT_CNT_WIDTH'b01); // max dat crdt cnt = 2        

    assign rx_lcredits_returned = (rxdat_crd_cnt_s1_q == {`RNF_LCRD_RXDAT_CNT_WIDTH{1'b1}});


    //rxdat_crd state maching input
    //enable sending crd
    assign rxdat_crd_sm_in[2] = rxcrd_enable_s0;

    //crd count == 0
    assign rxdat_crd_sm_in[1] = rxdat_crd_cnt_zero;

    //receive responses except DataLCrdReturn
    assign rxdat_crd_sm_in[0] = li_mshr_rxdat_valid_s0;

    //rxdatlcrdv logic
    // ---------------------------- input ---------------------------- // // ---------- output ------------//
    // rxcrd_enable_s0 rxdat_crd_cnt_zero dat_flitv // // lcrdupdate crdv inc1 dec1//
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
    //              - The credit count here means that how many credits there is to be sent, if 0, all credits are sent

    //sm outputs
    always @(*) begin:rxdatlcrdv_logic_t
        casez (rxdat_crd_sm_in)
            3'b100:
                rxdat_crd_sm_out[3:0] = 4'hd;
            3'b101:
                rxdat_crd_sm_out[3:0] = 4'b1010;    //OLD: 4'h4;
            3'b110:
                rxdat_crd_sm_out[3:0] = 4'h0;
            3'b111:
                rxdat_crd_sm_out[3:0] = 4'b1010;    //OLD: 4'h4;
            3'b011:
                rxdat_crd_sm_out[3:0] = 4'b1010;
            3'b001:
                rxdat_crd_sm_out[3:0] = 4'b1010;
            default:
                rxdat_crd_sm_out[3:0] = 4'h0;
        endcase
    end

    assign rxdat_crd_cnt_upd_s0  = rxdat_crd_sm_out[3];
    assign rxdatcrdv_ns_s0       = rxdat_crd_sm_out[2];
    assign rxdat_crd_cnt_inc1_s0 = rxdat_crd_sm_out[1];
    assign rxdat_crd_cnt_dec1_s0 = rxdat_crd_sm_out[0];

    assign rxdat_crd_cnt_dec1_val_s0 = rxdat_crd_cnt_s1_q - `RNF_LCRD_INCDEC_ONE;
    assign rxdat_crd_cnt_inc1_val_s0 = rxdat_crd_cnt_s1_q + `RNF_LCRD_INCDEC_ONE;

    //update next credit value
    assign rxdat_crd_cnt_nxt_s0 = rxdat_crd_cnt_dec1_s0 ? rxdat_crd_cnt_dec1_val_s0:
           rxdat_crd_cnt_inc1_val_s0;

    always @(posedge clk or posedge rst) begin: rxdat_crd_cnt_s1_q_logic_t
        if (rst == 1'b1)
            rxdat_crd_cnt_s1_q <= XP_LCRD_NUM_PARAM;
        else if (rxdat_crd_cnt_upd_s0 == 1'b1)
            rxdat_crd_cnt_s1_q <= rxdat_crd_cnt_nxt_s0;
    end

    always @(posedge clk or posedge rst) begin: rxdatcrdv_s1_q_logic_t
        if (rst == 1'b1)
            rxdatcrdv_s1_q <= 1'b0;
        else
            rxdatcrdv_s1_q <= rxdatcrdv_ns_s0;
    end

    assign rxdat_lcrdv = rxdatcrdv_s1_q;

endmodule
