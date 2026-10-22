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
*    Wenhao Li <liwenhao@bosc.ac.cn>
*    Guo Bing <guobing@bosc.ac.cn>
*    Nana Cai <cainana@bosc.ac.cn>
*/


// Modifications: 
/*
 * Copyright (c) 2026 Tampere University
 * Licensed under the Solderpad Hardware License v 2.1, see LICENSE for details.
 * SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
 */

//==================================================================================================
//  Filename        : rnf_link_txdat_wrap (original hnf_link_txdat_wrap)
//  Modified        : Teemu Rinne, Tampere University
//
//  Description     : TXDAT channel interface of AMBA CHI based RN-F link layer interface 
//
//==================================================================================================


`include "chie_defines.v"
`include "rnf_defines.v"
`include "rnf_param.v"

module rnf_link_txdat_wrap `RNF_PARAM
    (
        //global inputs
        clk,
        rst,

        //inputs from link
        txdat_lcrdv,

        encoder_txdat_qos,
        mshr_txdat_tgtid_sx2,
        encoder_txdat_srcid,
        mshr_txdat_txnid_sx2,
        encoder_txdat_homenid,
        mshr_txdat_opcode_sx2,
        mshr_txdat_resperr_sx2,
        mshr_txdat_resp_sx2,
        encoder_txdat_fwdstate,
        mshr_txdat_dbid_sx2,
        encoder_txdat_ccid,

        dbf_txdat_valid_sx1,
        dbf_txdat_be_sx1,
        dbf_txdat_data_sx1,
        dbf_txdat_idx_sx1,
        dbf_txdat_pe_sx1,       // "dataid"

        txdatflitv,
        txdatflit,
        txdatflitpend,

        txdat_mshr_clr_dbf_busy_valid_sx3,
        txdat_mshr_clr_dbf_busy_idx_sx3,
        txdat_mshr_rd_idx_sx2,
        txdat_mshr_busy_sx,

        tx_ready,
        tx_lcredits_used
    );

    //global inputs
    input wire                                    clk;
    input wire                                    rst;

    input wire                                    txdat_lcrdv;

    input wire [`CHIE_DAT_FLIT_QOS_WIDTH-1:0]               encoder_txdat_qos;
    input wire [`CHIE_DAT_FLIT_SRCID_WIDTH-1:0]             encoder_txdat_srcid;
    input wire [`CHIE_DAT_FLIT_HOMENID_WIDTH-1:0]           encoder_txdat_homenid;
    input wire [`CHIE_DAT_FLIT_FWDSTATE_WIDTH-1:0]          encoder_txdat_fwdstate;
    input wire [`CHIE_DAT_FLIT_CCID_WIDTH-1:0]              encoder_txdat_ccid;
    input wire [`CHIE_DAT_FLIT_TGTID_WIDTH-1:0]             mshr_txdat_tgtid_sx2;
    input wire [`CHIE_DAT_FLIT_TXNID_WIDTH-1:0]             mshr_txdat_txnid_sx2;
    input wire [`CHIE_DAT_FLIT_OPCODE_WIDTH-1:0]            mshr_txdat_opcode_sx2;
    input wire [`CHIE_DAT_FLIT_RESP_WIDTH-1:0]              mshr_txdat_resp_sx2;
    input wire [`CHIE_DAT_FLIT_RESPERR_WIDTH-1:0]           mshr_txdat_resperr_sx2;
    input wire [`CHIE_DAT_FLIT_DBID_WIDTH-1:0]              mshr_txdat_dbid_sx2;

    input wire                                              dbf_txdat_valid_sx1;
    input wire [`CHI_CACHE_LINE_WIDTH-1:0]                  dbf_txdat_data_sx1;
    input wire [2-1:0]                                      dbf_txdat_idx_sx1;
    input wire [`CHI_CACHE_BE_WIDTH-1:0]                    dbf_txdat_be_sx1;
    input wire [1:0]                                        dbf_txdat_pe_sx1;

    output reg                                              txdat_mshr_clr_dbf_busy_valid_sx3;      // assigned when entry is being deallocated
    output reg  [2-1:0]                                     txdat_mshr_clr_dbf_busy_idx_sx3;        // the index of the entry that is being deallocated
    output wire [2-1:0]                                     txdat_mshr_rd_idx_sx2;                  // idx of ent2_ns or ent1, if they are valid
    output wire                                             txdat_mshr_busy_sx;                     // IF both entries are valid (txdat is full)

    output reg                                    txdatflitv;
    output reg  [`CHIE_DAT_FLIT_RANGE]            txdatflit;
    output wire                                   txdatflitpend;

    input wire tx_ready;                       // Indicate that TX flits can be sent   
    output wire tx_lcredits_used;          // if all L-credits are returned to receiver

    //internal reg signals
    reg [`CHIE_DAT_FLIT_RANGE]                    txdatflit_mshr_s0;
    reg                                           dbf_txdat_valid_entry1_sx;
    reg [`CHI_CACHE_LINE_WIDTH-1:0]               dbf_txdat_data_entry1_sx;
    reg [2-1:0]                                   dbf_txdat_idx_entry1_sx;
    reg [`CHI_CACHE_BE_WIDTH-1:0]                 dbf_txdat_be_entry1_sx;
    reg [1:0]                                     dbf_txdat_pe_entry1_sx;
    reg                                           dbf_txdat_valid_entry2_sx;
    reg [`CHI_CACHE_LINE_WIDTH-1:0]               dbf_txdat_data_entry2_sx;
    reg [2-1:0]                                   dbf_txdat_idx_entry2_sx;
    reg [`CHI_CACHE_BE_WIDTH-1:0]                 dbf_txdat_be_entry2_sx;
    reg [1:0]                                     dbf_txdat_pe_entry2_sx;
    reg [`RNF_LCRD_DAT_CNT_WIDTH-1:0]             txdat_crd_cnt_q;
    reg [`RNF_LCRD_DAT_CNT_WIDTH-1:0]             dat_crd_cnt_ns_s0;
    reg                                           dbf_txdat_valid_entry2_sx_ns; // 1 if entry2 is sent out
    wire [`CHIE_DAT_FLIT_DATAID_WIDTH-1:0]        mshr_txdat_dataid_sx_ns;
    reg [`CHIE_DAT_FLIT_BE_WIDTH-1:0]             mshr_txdat_be_sx_ns;
    reg [`CHIE_DAT_FLIT_DATA_WIDTH-1:0]           mshr_txdat_data_sx_ns;

    //internal wire signals
    wire                                            dat_crd_cnt_not_zero_sx;
    wire                                            txdat_crd_avail_s1;
    wire                                            txdat_busy_sx;
    wire                                            txdatcrdv_s0;
    wire                                            txdat_crd_cnt_inc_sx;
    wire                                            txdat_req_s0;
    wire [`CHIE_DAT_FLIT_RANGE]                     txdatflit_s0;
    wire                                            txdatflitv_s0;
    wire                                            txdat_crd_cnt_dec_sx;
    wire                                            update_dat_crd_cnt_s0;
    wire [`RNF_LCRD_DAT_CNT_WIDTH-1:0]              dat_crd_cnt_s1;
    wire [`RNF_LCRD_DAT_CNT_WIDTH-1:0]              dat_crd_cnt_inc_s0;
    wire [`RNF_LCRD_DAT_CNT_WIDTH-1:0]              dat_crd_cnt_dec_s0;
    wire                                            dbf_txdat_entry1_dealloc_sx;
    wire                                            dbf_txdat_entry2_dealloc_sx;

    //main function
    assign dat_crd_cnt_not_zero_sx = (txdat_crd_cnt_q != 'd0);
    assign txdat_crd_avail_s1      = (txdat_lcrdv | dat_crd_cnt_not_zero_sx);
    assign txdat_busy_sx           = ~txdat_crd_avail_s1 || ~tx_ready;

    assign txdatcrdv_s0            = txdat_lcrdv;
    assign txdat_crd_cnt_inc_sx    = txdatcrdv_s0;
    assign txdat_req_s0            = (dbf_txdat_valid_entry1_sx | dbf_txdat_valid_entry2_sx_ns);

    assign tx_lcredits_used = ~dat_crd_cnt_not_zero_sx;

    // PE of an entry to be sent is decreased so that when inverted, it's the data_id to be sent at that moment
        // PE is expected to be get in as "2'b11"
    assign mshr_txdat_dataid_sx_ns = (dbf_txdat_valid_entry2_sx_ns) ? ~dbf_txdat_pe_entry2_sx : ~dbf_txdat_pe_entry1_sx;


    always @* begin: txdat_be_sel_comb_logic
        mshr_txdat_be_sx_ns =   (dbf_txdat_valid_entry2_sx_ns) ? dbf_txdat_be_entry2_sx >> (mshr_txdat_dataid_sx_ns*16) :
                                (dbf_txdat_valid_entry1_sx) ? dbf_txdat_be_entry1_sx >> (mshr_txdat_dataid_sx_ns*16) : 
                                {`CHIE_DAT_FLIT_BE_WIDTH{1'b0}};
    end

    always @* begin: txdat_data_sel_comb_logic
        mshr_txdat_data_sx_ns = (dbf_txdat_valid_entry2_sx_ns) ? dbf_txdat_data_entry2_sx >> (mshr_txdat_dataid_sx_ns*128) :
                                (dbf_txdat_valid_entry1_sx) ? dbf_txdat_data_entry1_sx >> (mshr_txdat_dataid_sx_ns*128) : 
                                {`CHIE_DAT_FLIT_BE_WIDTH{1'b0}};        
    end

    generate
        if(CHIE_DAT_RSVDC_WIDTH_PARAM != 0)begin
            always @*begin
                txdatflit_mshr_s0[`CHIE_DAT_FLIT_RSVDC_RANGE] = {`CHIE_DAT_FLIT_RSVDC_WIDTH{1'b0}};
            end
        end
        if(CHIE_DATACHECK_WIDTH_PARAM != 0)begin
            always @*begin
                txdatflit_mshr_s0[`CHIE_DAT_FLIT_DATACHECK_RANGE] = {`CHIE_DAT_FLIT_DATACHECK_WIDTH{1'b0}};
            end
        end
        if(CHIE_POISON_WIDTH_PARAM != 0)begin
            always @*begin
                txdatflit_mshr_s0[`CHIE_DAT_FLIT_POISON_RANGE] = {`CHIE_DAT_FLIT_POISON_WIDTH{1'b0}};
            end
        end
    endgenerate

    always @*begin : combinational_logic1
        txdatflit_mshr_s0[`CHIE_DAT_FLIT_QOS_RANGE]       = encoder_txdat_qos;
        txdatflit_mshr_s0[`CHIE_DAT_FLIT_TGTID_RANGE]     = mshr_txdat_tgtid_sx2;
        txdatflit_mshr_s0[`CHIE_DAT_FLIT_SRCID_RANGE]     = encoder_txdat_srcid;
        txdatflit_mshr_s0[`CHIE_DAT_FLIT_TXNID_RANGE]     = mshr_txdat_txnid_sx2;
        txdatflit_mshr_s0[`CHIE_DAT_FLIT_HOMENID_RANGE]   = encoder_txdat_homenid;
        txdatflit_mshr_s0[`CHIE_DAT_FLIT_OPCODE_RANGE]    = mshr_txdat_opcode_sx2;
        txdatflit_mshr_s0[`CHIE_DAT_FLIT_RESPERR_RANGE]   = mshr_txdat_resperr_sx2;
        txdatflit_mshr_s0[`CHIE_DAT_FLIT_RESP_RANGE]      = mshr_txdat_resp_sx2;
        txdatflit_mshr_s0[`CHIE_DAT_FLIT_FWDSTATE_RANGE]  = encoder_txdat_fwdstate;
        txdatflit_mshr_s0[`CHIE_DAT_FLIT_CBUSY_RANGE]     = {`CHIE_DAT_FLIT_CBUSY_WIDTH{1'b0}};
        txdatflit_mshr_s0[`CHIE_DAT_FLIT_DBID_RANGE]      = mshr_txdat_dbid_sx2;
        txdatflit_mshr_s0[`CHIE_DAT_FLIT_CCID_RANGE]      = encoder_txdat_ccid;
        txdatflit_mshr_s0[`CHIE_DAT_FLIT_DATAID_RANGE]    = mshr_txdat_dataid_sx_ns;
        txdatflit_mshr_s0[`CHIE_DAT_FLIT_TAGOP_RANGE]     = {`CHIE_DAT_FLIT_TAGOP_WIDTH{1'b0}}; // not in CHI-B
        txdatflit_mshr_s0[`CHIE_DAT_FLIT_TAG_RANGE]       = {`CHIE_DAT_FLIT_TAG_WIDTH{1'b0}}; // not in CHI-B
        txdatflit_mshr_s0[`CHIE_DAT_FLIT_TU_RANGE]        = {`CHIE_DAT_FLIT_TU_WIDTH{1'b0}}; // not in CHI-B
        txdatflit_mshr_s0[`CHIE_DAT_FLIT_TRACETAG_RANGE]  = {`CHIE_DAT_FLIT_TRACETAG_WIDTH{1'b0}}; 
        txdatflit_mshr_s0[`CHIE_DAT_FLIT_BE_RANGE]        = mshr_txdat_be_sx_ns;
        txdatflit_mshr_s0[`CHIE_DAT_FLIT_DATA_RANGE]      = mshr_txdat_data_sx_ns;
    end

    assign txdatflit_s0            = txdatflit_mshr_s0;
    assign dat_crd_cnt_s1          = txdat_crd_cnt_q;
    assign txdatflitv_s0           = (txdat_req_s0 & ~txdat_busy_sx);
    assign txdat_crd_cnt_dec_sx    = (txdatflitv_s0 & txdat_crd_avail_s1); //lcrd - 1

    assign txdatflitpend = 1'b1;

    //txdatflit sending logic
    always @(posedge clk or posedge rst) begin: txdatflit_logic_t
        if(rst == 1'b1)begin
            txdatflit  <= {`CHIE_DAT_FLIT_WIDTH{1'b0}};
            txdatflitv <= 1'b0;
        end
        else if((txdatflitv_s0 == 1'b1) & (txdat_crd_avail_s1 == 1'b1))begin
            txdatflit  <= txdatflit_s0;
            txdatflitv <= 1'b1;
        end
        else begin
            txdatflit  <= txdatflit;
            txdatflitv <= 1'b0;
        end
    end


    //deallocate entry if data is sent
    assign dbf_txdat_entry1_dealloc_sx = (txdatflitv_s0 & txdat_crd_avail_s1) & dbf_txdat_valid_entry1_sx & (~dbf_txdat_valid_entry2_sx_ns) & ~dbf_txdat_entry2_dealloc_sx &
        (!(dbf_txdat_pe_entry1_sx) || (CHIE_DATA_WIDTH_PARAM == 256 && dbf_txdat_pe_entry1_sx == 2'b01) || (CHIE_DATA_WIDTH_PARAM == 512));

    assign dbf_txdat_entry2_dealloc_sx = (txdatflitv_s0 & txdat_crd_avail_s1) & dbf_txdat_valid_entry2_sx_ns &
        (!(dbf_txdat_pe_entry1_sx) || (CHIE_DATA_WIDTH_PARAM == 256 && dbf_txdat_pe_entry1_sx == 2'b01) || (CHIE_DATA_WIDTH_PARAM == 512));

    assign txdat_mshr_busy_sx = (dbf_txdat_valid_entry1_sx && dbf_txdat_valid_entry2_sx);

    //clr busy logic
    always @(posedge clk or posedge rst) begin: txdat_mshr_clr_dbf_busy_valid_sx3_logic_t
        if (rst == 1'b1)
            txdat_mshr_clr_dbf_busy_valid_sx3 <= 1'b0;
        else if(dbf_txdat_entry1_dealloc_sx | dbf_txdat_entry2_dealloc_sx)
            txdat_mshr_clr_dbf_busy_valid_sx3 <= 1'b1;
        else
            txdat_mshr_clr_dbf_busy_valid_sx3 <= 1'b0;
    end

    always @(posedge clk or posedge rst) begin: txdat_mshr_clr_dbf_busy_idx_sx3_logic_t
        if (rst == 1'b1)
            txdat_mshr_clr_dbf_busy_idx_sx3 <= {2{1'b0}};
        else if(dbf_txdat_entry1_dealloc_sx)
            txdat_mshr_clr_dbf_busy_idx_sx3 <= dbf_txdat_idx_entry1_sx;
        else if(dbf_txdat_entry2_dealloc_sx)
            txdat_mshr_clr_dbf_busy_idx_sx3 <= dbf_txdat_idx_entry2_sx;
        else
            txdat_mshr_clr_dbf_busy_idx_sx3 <= {2{1'b0}};
    end

    //receive dbf_txdat_valid_sx1, pass valid, allocate to entry1, or deallocate
    always @(posedge clk or posedge rst) begin: dbf_txdat_valid_entry1_sx_logic_t
        if(rst == 1'b1)
            dbf_txdat_valid_entry1_sx <= 1'b0;
        else if(dbf_txdat_valid_sx1 && !dbf_txdat_valid_entry1_sx)
            dbf_txdat_valid_entry1_sx <= 1'b1;
        else if(dbf_txdat_entry1_dealloc_sx)
            dbf_txdat_valid_entry1_sx <= 1'b0;
        else begin
        end
    end

    // allocate to entry2 (entry1 valid), or deallocate
    always @(posedge clk or posedge rst) begin: dbf_txdat_valid_entry2_sx_logic_t
        if(rst == 1'b1)
            dbf_txdat_valid_entry2_sx <= 1'b0;
        else if(dbf_txdat_valid_sx1 && dbf_txdat_valid_entry1_sx && !dbf_txdat_valid_entry2_sx)
            dbf_txdat_valid_entry2_sx <= 1'b1;
        else if(dbf_txdat_entry2_dealloc_sx)
            dbf_txdat_valid_entry2_sx <= 1'b0;
        else begin
        end
    end

    // Send entry2 out, (entry2 valid or (input valid, e1 valid and e2 not valid) and (e1 deallocated or invalid) and e2 !deallocated )
    always @(posedge clk or posedge rst) begin: dbf_txdat_valid_entry2_sx_ns_logic_t
        if(rst == 1'b1)
            dbf_txdat_valid_entry2_sx_ns <= 1'b0;
        else if((dbf_txdat_valid_entry2_sx || (dbf_txdat_valid_sx1 && dbf_txdat_valid_entry1_sx && !dbf_txdat_valid_entry2_sx)) 
                    && (dbf_txdat_entry1_dealloc_sx || !dbf_txdat_valid_entry1_sx) && !dbf_txdat_entry2_dealloc_sx)
            dbf_txdat_valid_entry2_sx_ns <= 1'b1;
        else if(dbf_txdat_entry2_dealloc_sx)
            dbf_txdat_valid_entry2_sx_ns <= 1'b0;
        else begin
        end
    end

    //receive dbf_txdat_valid_sx1, pass index to mshr
    // Entry1; allocate databuffer index (idx is optional in design, just one idx in RNF-CVA6)
    always @(posedge clk or posedge rst) begin: dbf_txdat_idx_entry1_sx_logic_t
        if(rst == 1'b1)
            dbf_txdat_idx_entry1_sx <= {2{1'b0}};
        else if(dbf_txdat_valid_sx1 && !dbf_txdat_valid_entry1_sx)
            dbf_txdat_idx_entry1_sx <= dbf_txdat_idx_sx1;
        else begin
        end
    end

    // Entry2; allocate databuffer index (idx is optional in design, just one idx in RNF-CVA6)
    always @(posedge clk or posedge rst) begin: dbf_txdat_idx_entry2_sx_logic_t
        if(rst == 1'b1)
            dbf_txdat_idx_entry2_sx <= {2{1'b0}};
        else if(dbf_txdat_valid_sx1 && dbf_txdat_valid_entry1_sx && !dbf_txdat_valid_entry2_sx)
            dbf_txdat_idx_entry2_sx <= dbf_txdat_idx_sx1;
        else begin
        end
    end

    assign txdat_mshr_rd_idx_sx2 = (dbf_txdat_valid_entry2_sx_ns) ? dbf_txdat_idx_entry2_sx : (dbf_txdat_valid_entry1_sx) ? dbf_txdat_idx_entry1_sx : {2{1'b0}};

    // E1, receive dbf_txdat_valid_sx1, pass data
    always @(posedge clk or posedge rst) begin: dbf_txdat_data_entry1_sx_logic_t
        if(rst == 1'b1)
            dbf_txdat_data_entry1_sx <= {`CHI_CACHE_LINE_WIDTH{1'b0}};
        else if(dbf_txdat_valid_sx1 && !dbf_txdat_valid_entry1_sx)
            dbf_txdat_data_entry1_sx <= dbf_txdat_data_sx1;
        else
            dbf_txdat_data_entry1_sx <= dbf_txdat_data_entry1_sx;
    end
    // E2 
    always @(posedge clk or posedge rst) begin: dbf_txdat_data_entry2_sx_logic_t
        if(rst == 1'b1)
            dbf_txdat_data_entry2_sx <= {`CHI_CACHE_LINE_WIDTH{1'b0}};
        else if(dbf_txdat_valid_sx1 && dbf_txdat_valid_entry1_sx && !dbf_txdat_valid_entry2_sx)
            dbf_txdat_data_entry2_sx <= dbf_txdat_data_sx1;
        else
            dbf_txdat_data_entry2_sx <= dbf_txdat_data_entry2_sx;
    end

    //receive dbf_txdat_valid_sx1, pass be
    always @(posedge clk or posedge rst) begin: dbf_txdat_be_entry1_sx_logic_t
        if(rst == 1'b1)
            dbf_txdat_be_entry1_sx <= {`CHI_CACHE_BE_WIDTH{1'b0}};
        else if(dbf_txdat_valid_sx1 && !dbf_txdat_valid_entry1_sx)
            dbf_txdat_be_entry1_sx <= dbf_txdat_be_sx1;
        else
            dbf_txdat_be_entry1_sx <= dbf_txdat_be_entry1_sx;
    end
    // E2 
    always @(posedge clk or posedge rst) begin: dbf_txdat_be_entry2_sx_logic_t
        if(rst == 1'b1)
            dbf_txdat_be_entry2_sx <= {`CHI_CACHE_BE_WIDTH{1'b0}};
        else if(dbf_txdat_valid_sx1 && dbf_txdat_valid_entry1_sx && !dbf_txdat_valid_entry2_sx)
            dbf_txdat_be_entry2_sx <= dbf_txdat_be_sx1;
        else
            dbf_txdat_be_entry2_sx <= dbf_txdat_be_entry2_sx;
    end

    //receive dbf_txdat_valid_sx1, pass pe
    // allocate incoming pe to entry1, or send/decrease pe
    always @(posedge clk or posedge rst) begin: dbf_txdat_pe_entry1_sx_logic_t
        if(rst == 1'b1)
            dbf_txdat_pe_entry1_sx <= {2{1'b0}};
        else if(dbf_txdat_valid_sx1 && !dbf_txdat_valid_entry1_sx)
            dbf_txdat_pe_entry1_sx <= dbf_txdat_pe_sx1;
        else if(dbf_txdat_valid_entry1_sx & (~dbf_txdat_valid_entry2_sx_ns) & txdat_crd_avail_s1)
            //dbf_txdat_pe_entry1_sx <= dbf_txdat_pe_entry1_sx[0]?{dbf_txdat_pe_entry1_sx[1],1'b0}:2'b00;
            case (CHIE_DATA_WIDTH_PARAM)
            128: begin
                dbf_txdat_pe_entry1_sx <= (dbf_txdat_pe_entry1_sx == 2'b11) ? 2'b10 : (dbf_txdat_pe_entry1_sx == 2'b10) ? 2'b01 : (dbf_txdat_pe_entry1_sx == 2'b01) ? 2'b00 : 2'b00;
            end 
            256: begin
                dbf_txdat_pe_entry1_sx <= (dbf_txdat_pe_entry1_sx == 2'b11) ? 2'b01 : (dbf_txdat_pe_entry1_sx == 2'b01) ? 2'b00 : 2'b00;
            end
            512: begin
                dbf_txdat_pe_entry1_sx <= (dbf_txdat_pe_entry1_sx == 2'b11) ? 2'b00 : 2'b00;
            end
            endcase
        else
            dbf_txdat_pe_entry1_sx <= dbf_txdat_pe_entry1_sx;
    end

    // allocate incoming pe to entry2, or send/decrease pe
    always @(posedge clk or posedge rst) begin: dbf_txdat_pe_entry2_sx_logic_t
        if(rst == 1'b1)
            dbf_txdat_pe_entry2_sx <= {2{1'b0}};
        else if(dbf_txdat_valid_sx1 && dbf_txdat_valid_entry1_sx && !dbf_txdat_valid_entry2_sx)
            dbf_txdat_pe_entry2_sx <= dbf_txdat_pe_sx1; // Should always get PE=2'b11
        else if( dbf_txdat_valid_entry2_sx_ns & txdat_crd_avail_s1)
            case (CHIE_DATA_WIDTH_PARAM)
            128: begin
                dbf_txdat_pe_entry2_sx <= (dbf_txdat_pe_entry2_sx == 2'b11) ? 2'b10 : (dbf_txdat_pe_entry2_sx == 2'b10) ? 2'b01 : (dbf_txdat_pe_entry2_sx == 2'b01) ? 2'b00 : 2'b00;
            end 
            256: begin
                dbf_txdat_pe_entry2_sx <= (dbf_txdat_pe_entry2_sx == 2'b11) ? 2'b01 : (dbf_txdat_pe_entry2_sx == 2'b01) ? 2'b00 : 2'b00;
            end
            512: begin
                dbf_txdat_pe_entry2_sx <= (dbf_txdat_pe_entry2_sx == 2'b11) ? 2'b00 : 2'b00;
            end
            endcase
        else
            dbf_txdat_pe_entry2_sx <= dbf_txdat_pe_entry2_sx;
    end

    //L-credit logic
    assign update_dat_crd_cnt_s0   = txdat_crd_cnt_inc_sx | txdat_crd_cnt_dec_sx;
    assign dat_crd_cnt_inc_s0      = (dat_crd_cnt_s1 + 1'b1);
    assign dat_crd_cnt_dec_s0      = (dat_crd_cnt_s1 - 1'b1);

    always @* begin: dat_crd_cnt_ns_s0_logic_c
        casez({txdat_crd_cnt_inc_sx, txdat_crd_cnt_dec_sx})
            2'b00:
                dat_crd_cnt_ns_s0 = txdat_crd_cnt_q;     // hold
            2'b01:
                dat_crd_cnt_ns_s0 = dat_crd_cnt_dec_s0;  // dec
            2'b10:
                dat_crd_cnt_ns_s0 = dat_crd_cnt_inc_s0;  // inc
            2'b11:
                dat_crd_cnt_ns_s0 = txdat_crd_cnt_q;     // hold
            default:
                dat_crd_cnt_ns_s0 = {`RNF_LCRD_DAT_CNT_WIDTH{1'b0}};
        endcase
    end

    always @(posedge clk or posedge rst)begin
        if (rst == 1'b1)
            txdat_crd_cnt_q <= {`RNF_LCRD_DAT_CNT_WIDTH{1'b0}};
        else if (update_dat_crd_cnt_s0 == 1'b1)
            txdat_crd_cnt_q <= dat_crd_cnt_ns_s0;
    end

endmodule
