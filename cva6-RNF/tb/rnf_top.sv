// Original work:
// Copyright (c) 2015 Princeton University
// All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//     * Redistributions of source code must retain the above copyright
//       notice, this list of conditions and the following disclaimer.
//     * Redistributions in binary form must reproduce the above copyright
//       notice, this list of conditions and the following disclaimer in the
//       documentation and/or other materials provided with the distribution.
//     * Neither the name of Princeton University nor the
//       names of its contributors may be used to endorse or promote products
//       derived from this software without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY PRINCETON UNIVERSITY "AS IS" AND
// ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
// WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
// DISCLAIMED. IN NO EVENT SHALL PRINCETON UNIVERSITY BE LIABLE FOR ANY
// DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
// (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
// LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
// ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
// SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

// Modifications: 
/*
 * Copyright (c) 2026 Tampere University
 * Licensed under the Solderpad Hardware License v 2.1, see LICENSE for details.
 * SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
 */

//==================================================================================================
//  Filename        : rnf_top (original tile)
//  Original Author : Princeton University
//  Modified        : Teemu Rinne, Tampere University
//
//  Description     : Top-level for AMBA CHI based RN-F coherent cache used with CVA6-RISC-V core
//
//==================================================================================================



`include "define.tmp.h"
`include "l15.tmp.h"

`include "rnf_param.v"
`include "rnf_defines.v"
`include "chie_defines.v"

module rnf_top
import ariane_pkg::*;
import wt_cache_pkg::*;
#(
    parameter CHIE_REQ_ADDR_WIDTH_PARAM     = 44,
    parameter CHIE_SNP_ADDR_WIDTH_PARAM     = 41,
    parameter CHIE_NID_WIDTH_PARAM          = 7,
    parameter CHIE_DATA_WIDTH_PARAM         = 256,
    parameter CHIE_BE_WIDTH_PARAM           = 32,
    parameter CHIE_DATACHECK_WIDTH_PARAM    = 32,
    parameter CHIE_POISON_WIDTH_PARAM       = 4,
    parameter CHIE_REQ_RSVDC_WIDTH_PARAM    = 0,
    parameter CHIE_DAT_RSVDC_WIDTH_PARAM    = 0,
    parameter HNF_NID_PARAM                 = 0,
    parameter XP_LCRD_NUM_PARAM             = 15,
    parameter CACHED_REGION_BASE            = 64'h80000000,
    parameter CACHED_REGION_SIZE            = 64'h2000000,
    parameter BOOT_REGION_BASE              = 64'hFFF1010000,
    parameter BOOT_REGION_SIZE              = 64'h10000,
    parameter IO_REGION_BASE                = 64'hFFF0c2c000,
    parameter IO_REGION_SIZE                = 64'h3E4000,
    // parameter longint IO_REGION_BASE                = 64'hFFF1000000,   
    // parameter longint IO_REGION_SIZE                = 64'h1000, 
    parameter RNF_NID                       = 0
    ) (

    // IO
    input                               clk,
    input                               rst_n,
    input                               clk_en,

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

    // Credits back from responder?
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


    // clock gating
    wire clk_gated;
    clk_gating_latch clk_gating_latch(
        .clk(clk),
        .clk_en(clk_en),
        .clk_out(clk_gated)
    );

    // flop reset signal
    reg rst_n_f;
    always @ (posedge clk)
    begin
      rst_n_f <= rst_n;
    end


    wire                                spc_grst_l;

    wire [`PCX_REQTYPE_WIDTH-1:0]       transducer_l15_rqtype;
    wire [`L15_AMO_OP_WIDTH-1:0]        transducer_l15_amo_op;

    wire                                transducer_l15_nc;
    wire [`PCX_SIZE_FIELD_WIDTH-1:0]    transducer_l15_size;
    wire [`L15_THREADID_MASK]           transducer_l15_threadid;
    wire                                transducer_l15_prefetch;
    wire                                transducer_l15_invalidate_cacheline;
    wire                                transducer_l15_blockstore;
    wire                                transducer_l15_blockinitstore;
    wire [1:0]                          transducer_l15_l1rplway;
    wire                                transducer_l15_val;
    wire [`L15_PADDR_HI:0]              transducer_l15_address;
    wire [63:0]                         transducer_l15_data;
    wire [63:0]                         transducer_l15_data_next_entry;
    wire [`TLB_CSM_WIDTH-1:0]           transducer_l15_csm_data;

    wire                                l15_transducer_ack;
    wire                                l15_transducer_header_ack;

    wire                                l15_transducer_val;
    wire [3:0]                          l15_transducer_returntype;
    wire                                l15_transducer_l2miss;
    wire [1:0]                          l15_transducer_error;
    wire                                l15_transducer_noncacheable;
    wire                                l15_transducer_atomic;
    wire [`L15_THREADID_MASK]           l15_transducer_threadid;
    wire                                l15_transducer_prefetch;
    wire                                l15_transducer_f4b;
    wire [63:0]                         l15_transducer_data_0;
    wire [63:0]                         l15_transducer_data_1;
    wire [63:0]                         l15_transducer_data_2;
    wire [63:0]                         l15_transducer_data_3;
    wire                                l15_transducer_inval_icache_all_way;
    wire                                l15_transducer_inval_dcache_all_way;
    wire [15:4]                         l15_transducer_inval_address_15_4;
    wire                                l15_transducer_cross_invalidate;
    wire [1:0]                          l15_transducer_cross_invalidate_way;
    wire                                l15_transducer_inval_dcache_inval;
    wire                                l15_transducer_inval_icache_inval;
    wire [1:0]                          l15_transducer_inval_way;
    wire                                l15_transducer_blockinitstore;

    wire                                transducer_l15_req_ack;


    //////////////////////
    // Ariane RV64 Core //
    //////////////////////

    // native L15 interface, used in case of ARIANE_RV64, otherwise tied to zero
    wire [`L15_REQ_WIDTH-1:0]  l15_req;
    wire [`L15_RTRN_WIDTH-1:0] l15_rtrn;

    // see serpent_cache_pkg.sv for definition of the packed struct type "l15_rtrn_t",
    // note that the constants defined in l15.tmp.h and serpent_cache_pkg.sv need to coincide!
    assign l15_rtrn = { l15_transducer_ack,
                        l15_transducer_header_ack,
                        l15_transducer_val,
                        l15_transducer_returntype,
                        l15_transducer_l2miss,
                        l15_transducer_error,
                        l15_transducer_noncacheable,
                        l15_transducer_atomic,
                        l15_transducer_threadid,
                        l15_transducer_prefetch,
                        l15_transducer_f4b,
                        l15_transducer_data_0,
                        l15_transducer_data_1,
                        l15_transducer_data_2,
                        l15_transducer_data_3,
                        l15_transducer_inval_icache_all_way,
                        l15_transducer_inval_dcache_all_way,
                        l15_transducer_inval_address_15_4,
                        l15_transducer_cross_invalidate,
                        l15_transducer_cross_invalidate_way,
                        l15_transducer_inval_dcache_inval,
                        l15_transducer_inval_icache_inval,
                        l15_transducer_inval_way,
                        l15_transducer_blockinitstore };

    wire [2:0] transducer_l15_size_pcx_standard;
    // see serpent_cache_pkg.sv for definition of the packed struct type "l15_req_t",
    // note that the constants defined in l15.tmp.h and serpent_cache_pkg.sv need to coincide!
    assign { transducer_l15_val,
             transducer_l15_req_ack,
             transducer_l15_rqtype,
             transducer_l15_nc,
             transducer_l15_size_pcx_standard,
             transducer_l15_threadid,
             transducer_l15_prefetch,
             transducer_l15_invalidate_cacheline,
             transducer_l15_blockstore,
             transducer_l15_blockinitstore,
             transducer_l15_l1rplway,
             transducer_l15_address,
             transducer_l15_data,
             transducer_l15_data_next_entry,
             transducer_l15_csm_data,
             transducer_l15_amo_op} = l15_req;

    // Could remove this converter after Ariane is changed to send the
    // PMesh standard data size
    assign transducer_l15_size = (transducer_l15_size_pcx_standard == 3'b000) ? `MSG_DATA_SIZE_1B :
                                    (transducer_l15_size_pcx_standard == 3'b001) ? `MSG_DATA_SIZE_2B :
                                    (transducer_l15_size_pcx_standard == 3'b010) ? `MSG_DATA_SIZE_4B :
                                    (transducer_l15_size_pcx_standard == 3'b011) ? `MSG_DATA_SIZE_8B :
                                    (transducer_l15_size_pcx_standard == 3'b111 &&
                                     transducer_l15_rqtype == `PCX_REQTYPE_IFILL &&
                                    ~transducer_l15_invalidate_cacheline) ? `MSG_DATA_SIZE_32B : `MSG_DATA_SIZE_16B;

    wire [63:0] ariane_bootaddr;

    //assign ariane_bootaddr  =  64'hFFF1010000;
    assign ariane_bootaddr  =  BOOT_REGION_BASE;


    // The cached region length changed to 40000=262144B=4096x512bit
     // The cached region length changed to 80000=8192x512bit=8192x64B
    ariane_verilog_wrap #(
        
        // .NrPMPEntries           ( 4    ),
        // .DmBaseAddress          ( 64'hFFF1000000 ),      // Debug module
        // .SwapEndianess          ( 1'b1 ),
        // .NrExecuteRegionRules   ( 3   ),
        // .ExecuteRegionAddrBase  ( {64'h80000000, 64'hFFF1000000, 64'hFFF1010000}   ),
        // .ExecuteRegionLength    ( {64'h80000, 64'h1000, 64'h10000}   ),
        // .NrCachedRegionRules    (  1   ),
        // .CachedRegionAddrBase   ( {64'h80000000} ),
        // .CachedRegionLength     ( {64'h80000} )

        .NrPMPEntries           ( 4    ),
        .DmBaseAddress          ( IO_REGION_BASE ),
        .SwapEndianess          ( 1'b1 ),
        .NrExecuteRegionRules   ( 3   ),
        .ExecuteRegionAddrBase  ( {CACHED_REGION_BASE, IO_REGION_BASE, BOOT_REGION_BASE}   ),
        .ExecuteRegionLength    ( {CACHED_REGION_SIZE, IO_REGION_SIZE, BOOT_REGION_SIZE}   ),
        .NrCachedRegionRules    (  1   ),
        .CachedRegionAddrBase   ( {CACHED_REGION_BASE} ),
        .CachedRegionLength     ( {CACHED_REGION_SIZE} )

    ) core (
        .clk_i       ( clk_gated              ),
        .reset_l     ( rst_n_f                ),
        .spc_grst_l  ( spc_grst_l             ),
        .boot_addr_i ( ariane_bootaddr        ),
        .hart_id_i   ( {{32{1'b0}}, RNF_NID}  ),
        .irq_i       ( 'b0                    ),  //(irq_i),        // level senitive IR lines
        .ipi_i       ( 'b0                    ),  //(ipi_i),// software interrupt (a.k.a inter-process-interrupt)
        .time_irq_i  ( 'b0                    ),  // ( timer_irq_i ),
        .debug_req_i ( 'b0                    ),  //( debug_req_i ),// async debug request
        .l15_req_o   ( l15_req                ),
        .l15_rtrn_i  ( l15_rtrn               )
    );


    rnf_cache_wrap `RNF_PARAM_INST rnf_cache_wrap (
        .clk(clk_gated),
        //.rst_n(spc_grst_l),
        .rst_n(rst_n_f),

        .transducer_l15_rqtype              (transducer_l15_rqtype),
        .transducer_l15_amo_op              (transducer_l15_amo_op),
        .transducer_l15_nc                  (transducer_l15_nc),
        .transducer_l15_size                (transducer_l15_size),
        // .pcxdecoder_l15_invalall         (transducer_l15_invalall),
        .transducer_l15_threadid            (transducer_l15_threadid),
        .transducer_l15_prefetch            (transducer_l15_prefetch),
        .transducer_l15_blockstore          (transducer_l15_blockstore),
        .transducer_l15_blockinitstore      (transducer_l15_blockinitstore),
        .transducer_l15_l1rplway            (transducer_l15_l1rplway),
        .transducer_l15_val                 (transducer_l15_val),
        .transducer_l15_invalidate_cacheline(transducer_l15_invalidate_cacheline),
        .transducer_l15_address             (transducer_l15_address),
        .transducer_l15_csm_data            (transducer_l15_csm_data),
        .transducer_l15_data                (transducer_l15_data),
        .transducer_l15_data_next_entry     (transducer_l15_data_next_entry),

        .l15_transducer_ack                 (l15_transducer_ack),
        .l15_transducer_header_ack          (l15_transducer_header_ack),

        .l15_transducer_val                 (l15_transducer_val),
        .l15_transducer_returntype          (l15_transducer_returntype),
        .l15_transducer_l2miss              (l15_transducer_l2miss),
        .l15_transducer_error               (l15_transducer_error),
        .l15_transducer_noncacheable        (l15_transducer_noncacheable),
        .l15_transducer_atomic              (l15_transducer_atomic),
        .l15_transducer_threadid            (l15_transducer_threadid),
        .l15_transducer_prefetch            (l15_transducer_prefetch),
        .l15_transducer_f4b                 (l15_transducer_f4b),
        .l15_transducer_data_0              (l15_transducer_data_0),
        .l15_transducer_data_1              (l15_transducer_data_1),
        .l15_transducer_data_2              (l15_transducer_data_2),
        .l15_transducer_data_3              (l15_transducer_data_3),
        .l15_transducer_inval_icache_all_way(l15_transducer_inval_icache_all_way),
        .l15_transducer_inval_dcache_all_way(l15_transducer_inval_dcache_all_way),
        .l15_transducer_inval_address_15_4  (l15_transducer_inval_address_15_4),
        .l15_transducer_cross_invalidate    (l15_transducer_cross_invalidate),
        .l15_transducer_cross_invalidate_way(l15_transducer_cross_invalidate_way),
        .l15_transducer_inval_dcache_inval  (l15_transducer_inval_dcache_inval),
        .l15_transducer_inval_icache_inval  (l15_transducer_inval_icache_inval),
        .l15_transducer_inval_way           (l15_transducer_inval_way),
        .l15_transducer_blockinitstore      (l15_transducer_blockinitstore),

        .transducer_l15_req_ack             (transducer_l15_req_ack),

//////////////////////////////////////////////////////////////////////////////////////////
// CHI RNF IO

        .RXRSPLCRDV   (RXRSPLCRDV),
        .RXRSPFLITV   (RXRSPFLITV),
        .RXRSPFLIT    (RXRSPFLIT),
        .RXRSPFLITPEND(RXRSPFLITPEND),

        .RXSNPLCRDV   (RXSNPLCRDV),
        .RXSNPFLITV   (RXSNPFLITV),
        .RXSNPFLIT    (RXSNPFLIT),
        .RXSNPFLITPEND(RXSNPFLITPEND),

        .RXDATLCRDV   (RXDATLCRDV),
        .RXDATFLITV   (RXDATFLITV),
        .RXDATFLIT    (RXDATFLIT),
        .RXDATFLITPEND(RXDATFLITPEND),

        .TXREQLCRDV   (TXREQLCRDV),
        .TXREQFLITV   (TXREQFLITV),
        .TXREQFLIT    (TXREQFLIT),
        .TXREQFLITPEND(TXREQFLITPEND),

        .TXRSPLCRDV   (TXRSPLCRDV),
        .TXRSPFLITV   (TXRSPFLITV),
        .TXRSPFLIT    (TXRSPFLIT),
        .TXRSPFLITPEND(TXRSPFLITPEND),

        .TXDATLCRDV   (TXDATLCRDV),
        .TXDATFLITV   (TXDATFLITV),
        .TXDATFLIT    (TXDATFLIT),
        .TXDATFLITPEND(TXDATFLITPEND),

        .TXLINKACTIVEREQ                                (TXLINKACTIVEREQ),
        .TXLINKACTIVEACK                                (TXLINKACTIVEACK),
        .RXLINKACTIVEREQ                                (RXLINKACTIVEREQ),
        .RXLINKACTIVEACK                                (RXLINKACTIVEACK),
        .TXACTIVE                                       (TXACTIVE),
        .RXACTIVE                                       (RXACTIVE),

//////////////////////////////////////////////////////////////////////////////////////////

        // sram interfaces
        .srams_rtap_data (),
        .rtap_srams_bist_command ('b0),
        .rtap_srams_bist_data ('b0)
    );


endmodule
