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
//  Filename        : rnf_cache_wrap (original l15_wrap)
//  Original Author : Princeton University
//  Modified        : Teemu Rinne, Tampere University
//
//  Description     : Top-level wrapper of AMBA CHI based RN-F coherent cache
//
//==================================================================================================


`include "l15.tmp.h"

`include "rnf_param.v"
`include "rnf_defines.v"
`include "chie_defines.v"

module rnf_cache_wrap `RNF_PARAM (
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

    rnf_cache `RNF_PARAM_INST rnf_cache(
        .clk(clk),
        .rst_n(rst_n),

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

        // sram interfaces
        .srams_rtap_data (srams_rtap_data),
        .rtap_srams_bist_command (rtap_srams_bist_command),
        .rtap_srams_bist_data (rtap_srams_bist_data),

        // CHI interface
        .RXRSPFLITV (RXRSPFLITV),
        .RXRSPFLIT (RXRSPFLIT),
        .RXRSPFLITPEND (RXRSPFLITPEND),
        // from data channel
        .RXDATFLITV (RXDATFLITV),
        .RXDATFLIT (RXDATFLIT),
        .RXDATFLITPEND (RXDATFLITPEND),
        // to snoop channel         TODO
        .RXSNPFLITV (RXSNPFLITV),
        .RXSNPFLIT (RXSNPFLIT),
        .RXSNPFLITPEND (RXSNPFLITPEND),

        // Credits back from responder?
        .TXREQLCRDV (TXREQLCRDV),
        .TXRSPLCRDV (TXRSPLCRDV),
        .TXDATLCRDV (TXDATLCRDV),

        // OUTPUTS
        // Credits to requestor
        .RXRSPLCRDV (RXRSPLCRDV),
        .RXDATLCRDV (RXDATLCRDV),
        .RXSNPLCRDV (RXSNPLCRDV),
        // to request channel
        .TXREQFLITV (TXREQFLITV),
        .TXREQFLIT (TXREQFLIT),
        .TXREQFLITPEND (TXREQFLITPEND),
        // response channel
        .TXRSPFLITV (TXRSPFLITV),
        .TXRSPFLIT (TXRSPFLIT),
        .TXRSPFLITPEND (TXRSPFLITPEND),
        // to data channel
        .TXDATFLITV (TXDATFLITV),
        .TXDATFLIT (TXDATFLIT),
        .TXDATFLITPEND (TXDATFLITPEND),

        .TXLINKACTIVEREQ                                (TXLINKACTIVEREQ),
        .TXLINKACTIVEACK                                (TXLINKACTIVEACK),
        .RXLINKACTIVEREQ                                (RXLINKACTIVEREQ),
        .RXLINKACTIVEACK                                (RXLINKACTIVEACK),
        .TXACTIVE                                       (TXACTIVE),
        .RXACTIVE                                       (RXACTIVE)
    );

endmodule
