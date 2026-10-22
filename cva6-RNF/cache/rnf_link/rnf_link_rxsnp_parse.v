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
//  Filename        : rnf_link_rxsnp_parse (original hnf_link_rxrsp_parse)
//  Modified        : Teemu Rinne, Tampere University
//
//  Description     : RXSNP channel interface of AMBA CHI based RN-F link layer interface 
//
//==================================================================================================


`include "chie_defines.v"
`include "rnf_defines.v"
`include "rnf_param.v"

module rnf_link_rxsnp_parse `RNF_PARAM
    (
        //global inputs
        clk,
        rst,


        rxsnpflitv,
        rxsnpflit,
        rxsnpflitpend,

        rxsnp_decoder_valid_sx,
        rxsnp_decoder_qos,
        rxsnp_decoder_srcid,
        rxsnp_decoder_txnid,
        rxsnp_decoder_fwdnid,
        rxsnp_decoder_fwdtxnid,
        rxsnp_decoder_opcode,
        rxsnp_decoder_addr,
        rxsnp_decoder_ns,
        rxsnp_decoder_donotgotosd,
        rxsnp_decoder_rettosrc,
        rxsnp_decoder_tracetag,
        rxsnp_buf_ready,

        rxsnp_lcrdv,
        
        rx_ready,
        rx_lcredits_returned



    );

    //global inputs
    input wire                                      clk;
    input wire                                      rst;


    output wire                                      rxsnp_lcrdv;

    //outputs to decoder
    output wire                                         rxsnp_decoder_valid_sx;
    output wire [`CHIE_SNP_FLIT_QOS_WIDTH-1:0]          rxsnp_decoder_qos;
    output wire [`CHIE_SNP_FLIT_SRCID_WIDTH-1:0]        rxsnp_decoder_srcid;
    output wire [`CHIE_SNP_FLIT_TXNID_WIDTH-1:0]        rxsnp_decoder_txnid;
    output wire [`CHIE_SNP_FLIT_FWDNID_WIDTH-1:0]       rxsnp_decoder_fwdnid;
    output wire [`CHIE_SNP_FLIT_FWDTXNID_WIDTH-1:0]     rxsnp_decoder_fwdtxnid;
    output wire [`CHIE_SNP_FLIT_OPCODE_WIDTH-1:0]       rxsnp_decoder_opcode;
    output wire [`CHIE_SNP_FLIT_ADDR_WIDTH-1:0]         rxsnp_decoder_addr;
    output wire [`CHIE_SNP_FLIT_NS_WIDTH-1:0]           rxsnp_decoder_ns;
    output wire [`CHIE_SNP_FLIT_DONOTGOTOSD_WIDTH-1:0]  rxsnp_decoder_donotgotosd;
    output wire [`CHIE_SNP_FLIT_RETTOSRC_WIDTH-1:0]     rxsnp_decoder_rettosrc;
    output wire [`CHIE_SNP_FLIT_TRACETAG_WIDTH-1:0]     rxsnp_decoder_tracetag;

    input wire                                      rxsnpflitv;
    input wire  [`RNF_SNP_FLIT_RANGE]               rxsnpflit;
    input wire                                     rxsnpflitpend;

    // inputs from decoder
    input wire                                     rxsnp_buf_ready;

    input wire rx_ready;                       // signal for IFs that L-credits can be given
    output wire rx_lcredits_returned;      // if all L-credits are returned when transmitter entering lowpower


    //internal reg signals
    reg                                             rxsnpflitv_en_q;
    reg  [`RNF_LCRD_RXSNP_CNT_WIDTH-1:0]            rxsnp_crd_cnt_s1_q;
    reg  [3:0]                                      rxsnp_crd_sm_out;
    reg                                             rxsnpcrdv_s1_q;

    //internal wire signals
    wire                                            rxcrd_enable_s0;
    wire                                            rxsnp_crd_cnt_zero;
    wire [2:0]                                      rxsnp_crd_sm_in;
    wire                                            rxsnp_crd_cnt_upd_s0;
    wire                                            rxsnp_crd_cnt_inc1_s0;
    wire                                            rxsnp_crd_cnt_dec1_s0;
    wire [`RNF_LCRD_RXSNP_CNT_WIDTH-1:0]              rxsnp_crd_cnt_dec1_val_s0;
    wire [`RNF_LCRD_RXSNP_CNT_WIDTH-1:0]              rxsnp_crd_cnt_inc1_val_s0;
    wire [`RNF_LCRD_RXSNP_CNT_RANGE]                  rxsnp_crd_cnt_nxt_s0;
    wire                                            rxsnpcrdv_ns_s0;

    //main function
    //receive rxsnpflitpend
    always @(posedge clk or posedge rst)begin : rxsnpflitv_en_q_logic_t
        if(rst == 1'b1)
            rxsnpflitv_en_q <= 1'b0;
        else if (rxsnpflitpend == 1'b1)
            rxsnpflitv_en_q <= 1'b1;
        else
            rxsnpflitv_en_q <= 1'b0;
    end

    //rxsnp decode
    assign rxsnp_decoder_valid_sx       = (rxsnpflitv == 1'b1);
    assign rxsnp_decoder_qos            = (rxsnpflitv == 1'b1)? rxsnpflit[`CHIE_SNP_FLIT_QOS_RANGE]             :{`CHIE_SNP_FLIT_QOS_WIDTH{1'b0}};
    assign rxsnp_decoder_srcid          = (rxsnpflitv == 1'b1)? rxsnpflit[`CHIE_SNP_FLIT_SRCID_RANGE]           :{`CHIE_SNP_FLIT_SRCID_WIDTH{1'b0}};
    assign rxsnp_decoder_txnid          = (rxsnpflitv == 1'b1)? rxsnpflit[`CHIE_SNP_FLIT_TXNID_RANGE]           :{`CHIE_SNP_FLIT_TXNID_WIDTH{1'b0}};
    assign rxsnp_decoder_fwdnid         = (rxsnpflitv == 1'b1)? rxsnpflit[`CHIE_SNP_FLIT_FWDNID_RANGE]          :{`CHIE_SNP_FLIT_FWDNID_WIDTH{1'b0}};
    assign rxsnp_decoder_fwdtxnid       = (rxsnpflitv == 1'b1)? rxsnpflit[`CHIE_SNP_FLIT_FWDTXNID_RANGE]        :{`CHIE_SNP_FLIT_FWDTXNID_WIDTH{1'b0}};
    assign rxsnp_decoder_opcode         = (rxsnpflitv == 1'b1)? rxsnpflit[`CHIE_SNP_FLIT_OPCODE_RANGE]          :{`CHIE_SNP_FLIT_OPCODE_WIDTH{1'b0}};
    assign rxsnp_decoder_addr           = (rxsnpflitv == 1'b1)? rxsnpflit[`CHIE_SNP_FLIT_ADDR_RANGE]            :{`CHIE_SNP_FLIT_ADDR_WIDTH{1'b0}};
    assign rxsnp_decoder_ns             = (rxsnpflitv == 1'b1)? rxsnpflit[`CHIE_SNP_FLIT_NS_RANGE]              :{`CHIE_SNP_FLIT_NS_WIDTH{1'b0}};
    assign rxsnp_decoder_donotgotosd    = (rxsnpflitv == 1'b1)? rxsnpflit[`CHIE_SNP_FLIT_DONOTGOTOSD_RANGE]     :{`CHIE_SNP_FLIT_DONOTGOTOSD_WIDTH{1'b0}};
    assign rxsnp_decoder_rettosrc       = (rxsnpflitv == 1'b1)? rxsnpflit[`CHIE_SNP_FLIT_RETTOSRC_RANGE]        :{`CHIE_SNP_FLIT_RETTOSRC_WIDTH{1'b0}};
    assign rxsnp_decoder_tracetag       = (rxsnpflitv == 1'b1)? rxsnpflit[`CHIE_SNP_FLIT_TRACETAG_RANGE]        :{`CHIE_SNP_FLIT_TRACETAG_WIDTH{1'b0}};


    //rx lcrd enable
    assign rxcrd_enable_s0 = rxsnp_buf_ready && rx_ready;


    //if lcrd is zero
    assign rxsnp_crd_cnt_zero = (rxsnp_crd_cnt_s1_q == `RNF_LCRD_RXSNP_CNT_WIDTH'd`RNF_LCRD_RXSNP_CNT_LIMIT); //(rxsnp_crd_cnt_s1_q == {`RNF_LCRD_RXSNP_CNT_WIDTH{1'b0}}); // max snp crdt count 1     //(rxsnp_crd_cnt_s1_q == {`RNF_LCRD_RXSNP_CNT_WIDTH{1'b0}});

    assign rx_lcredits_returned = (rxsnp_crd_cnt_s1_q == {`RNF_LCRD_RXSNP_CNT_WIDTH{1'b1}});

    //rxsnp_crd state maching input
    //enable sending crd
    assign rxsnp_crd_sm_in[2] = rxcrd_enable_s0;

    //crd count == 0
    assign rxsnp_crd_sm_in[1] = rxsnp_crd_cnt_zero;

    //receive responses except RespLCrdReturn
    assign rxsnp_crd_sm_in[0] = rxsnp_decoder_valid_sx;

    //rxsnplcrdv logic
    // ---------------------------- input ---------------------------- // // ---------- output ------------//
    // rxcrd_enable_s0 rxsnp_crd_cnt_zero rsp_flitv // // lcrdupdate crdv inc1 dec1//
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
    always @(*) begin:rxsnplcrdv_logic_t
        casez (rxsnp_crd_sm_in)
            3'b100:
                rxsnp_crd_sm_out[3:0] = 4'hd;
            3'b101:
                rxsnp_crd_sm_out[3:0] = 4'b1010;    //OLD: 4'h4;
            3'b110:
                rxsnp_crd_sm_out[3:0] = 4'h0;
            3'b111:
                rxsnp_crd_sm_out[3:0] = 4'b1010;    //OLD: 4'h4;
            3'b011:
                rxsnp_crd_sm_out[3:0] = 4'b1010;
            3'b001:
                rxsnp_crd_sm_out[3:0] = 4'b1010;
            default:
                rxsnp_crd_sm_out[3:0] = 4'h0;
        endcase
    end

    assign rxsnp_crd_cnt_upd_s0  = rxsnp_crd_sm_out[3];
    assign rxsnpcrdv_ns_s0       = rxsnp_crd_sm_out[2];
    assign rxsnp_crd_cnt_inc1_s0 = rxsnp_crd_sm_out[1];
    assign rxsnp_crd_cnt_dec1_s0 = rxsnp_crd_sm_out[0];

    assign rxsnp_crd_cnt_dec1_val_s0 = rxsnp_crd_cnt_s1_q - `RNF_LCRD_INCDEC_ONE;
    assign rxsnp_crd_cnt_inc1_val_s0 = rxsnp_crd_cnt_s1_q + `RNF_LCRD_INCDEC_ONE;

    //update next credit value
    assign rxsnp_crd_cnt_nxt_s0 = rxsnp_crd_cnt_dec1_s0 ? rxsnp_crd_cnt_dec1_val_s0:
           rxsnp_crd_cnt_inc1_val_s0;

    always @(posedge clk or posedge rst) begin: rxsnp_crd_cnt_s1_q_logic_t
        if (rst == 1'b1)
            rxsnp_crd_cnt_s1_q <= XP_LCRD_NUM_PARAM;
        else if (rxsnp_crd_cnt_upd_s0 == 1'b1)
            rxsnp_crd_cnt_s1_q <= rxsnp_crd_cnt_nxt_s0;
    end

    always @(posedge clk or posedge rst) begin: rxsnpcrdv_s1_q_logic_t
        if (rst == 1'b1)
            rxsnpcrdv_s1_q <= 1'b0;
        else
            rxsnpcrdv_s1_q <= rxsnpcrdv_ns_s0;
    end

    assign rxsnp_lcrdv = rxsnpcrdv_s1_q;

endmodule
