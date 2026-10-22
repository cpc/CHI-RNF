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

`include "define.tmp.h"
`include "dmbr_define.v"
`include "l15.tmp.h"
`include "jtag.vh"
// /home/teri/Desktop/Work/DARE-projekti/chi-rnf/cva6-RNF/openpiton/piton/verif/env/manycore/devices_ariane.xml


module op_top #(
     parameter TILE_TYPE = `ARIANE_RV64_TILE
) (
    input                               clk,
    input                               rst_n,    // trin: assumed to be synchronous
    input                               clk_en,   // trin: assumed to be asynchronous
    input wire [`JTAG_FLATID_WIDTH-1:0] flat_tileid,

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
    output [`DMBR_TAG_WIDTH-1:0]            l15_dmbr_l1missTag




`ifdef PITON_RV64_PLATFORM
`ifdef PITON_RV64_DEBUGUNIT
    // Debug
,   input                               debug_req_i    // async debug request
`endif // ifdef PITON_RV64_DEBUGUNIT

`ifdef PITON_RV64_CLINT
    // CLINT
,   input                               timer_irq_i    // Timer interrupts
,   input                               ipi_i          // software interrupt (a.k.a inter-process-interrupt)
`endif // ifdef PITON_RV64_CLINT

`ifdef PITON_RV64_PLIC
    // PLIC
,   input   [1:0]                       irq_i          // level sensitive IR lines, mip & sip (async)
`endif // ifdef PITON_RV64_PLIC
`endif // ifdef PITON_RV64_PLATFORM
);
    // clock gating
    wire clk_gated;
    // clk_gating_latch clk_gating_latch(
    //     .clk(clk),
    //     .clk_en(clk_en),
    //     .clk_out(clk_gated)
    // );
    assign clk_gated = clk;

    // flop reset signal
    reg rst_n_f;
    always @ (posedge clk)
    begin
      rst_n_f <= rst_n;
    end

    // configured X/Y/CHIPID
    wire [`NOC_CHIPID_WIDTH-1:0]        config_chipid;
    wire [`NOC_X_WIDTH-1:0]             config_coreid_x;
    wire [`NOC_Y_WIDTH-1:0]             config_coreid_y;

    wire [`DATA_WIDTH-1:0]              buffer_processor_data_noc2;

    wire                                buffer_processor_valid_noc2;
    wire                                processor_router_ready_noc2;

    wire                                router_processor_ready_noc1;
    wire                                router_processor_ready_noc3;

    // Processor val/rdy interface

    wire [`NOC_DATA_WIDTH-1:0]          processor_router_data_noc1;
    wire                                processor_router_valid_noc1;

    wire [`NOC_DATA_WIDTH-1:0]          buffer_router_data_noc1;
    wire                                buffer_router_valid_noc1;


    wire                                buffer_router_yummy_noc2;


    wire [`NOC_DATA_WIDTH-1:0]          processor_router_data_noc3;
    wire                                processor_router_valid_noc3;

    wire [`NOC_DATA_WIDTH-1:0]          buffer_router_data_noc3;
    wire                                buffer_router_valid_noc3;

    wire                                router_buffer_consumed_noc1;

    wire [`NOC_DATA_WIDTH-1:0]          router_buffer_data_noc2;
    wire                                router_buffer_data_val_noc2;


    wire                                router_buffer_consumed_noc3;

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

    wire [`CORE_JTAG_BUS_WIDTH-1:0] core_rtap_data;
    wire rtap_core_val;
    wire [1:0] rtap_core_threadid;
    wire [`JTAG_CORE_ID_WIDTH-1:0]  rtap_core_id;
    wire [`CORE_JTAG_BUS_WIDTH-1:0] rtap_core_data;

    wire                                l15_dmbr_l1missIn;
    wire [`DMBR_TAG_WIDTH-1:0]          l15_dmbr_l1missTag;
    wire                                l15_dmbr_l2responseIn;
    wire                                l15_dmbr_l2missIn;
    wire [`DMBR_TAG_WIDTH-1:0]          l15_dmbr_l2missTag;
    wire                                dmbr_l15_stall; // outgoing signal stalling L1.5

    wire                                l15_config_req_val_s2;
    wire                                l15_config_req_rw_s2;
    wire [63:0]                         l15_config_write_req_data_s2;
    wire [`CONFIG_REG_ADDRESS_MASK]     l15_config_req_address_s2;
    wire [63:0]                         config_l15_read_res_data_s3;



    wire                                config_csm_en;
    wire [31:0]                         config_system_tile_count;
    wire [`HOME_ALLOC_METHOD_WIDTH-1:0] config_home_alloc_method;
    wire [`L15_HMT_BASE_ADDR_WIDTH-1:0] config_hmt_base;


    // SRAM wrapper interfaces
    wire [`SRAM_WRAPPER_BUS_WIDTH-1:0] srams_rtap_data;
    wire [`BIST_OP_WIDTH-1:0] rtap_srams_bist_command;
    wire [`SRAM_WRAPPER_BUS_WIDTH-1:0] rtap_srams_bist_data;
    wire [`SRAM_WRAPPER_BUS_WIDTH-1:0] l15_rtap_data;
    wire [`SRAM_WRAPPER_BUS_WIDTH-1:0] sparc_rtap_data;





    ////////////////////////////////////////////
    // Credit - Val/Rdy Interface Transducers //
    ///////////////////////////////////////////

    valrdy_to_credit #(16, 5) cgno_blk1(
        .clk(clk_gated),
        .reset(~rst_n_f),
        .data_in(processor_router_data_noc1),
        .valid_in(processor_router_valid_noc1),
        .ready_in(router_processor_ready_noc1),

        .data_out(buffer_router_data_noc1),           // Data
        .valid_out(buffer_router_valid_noc1),       // Val signal
        .yummy_out(router_buffer_consumed_noc1)    // Yummy signal
    );

    valrdy_to_credit #(16, 5) cgno_blk3(
        .clk(clk_gated),
        .reset(~rst_n_f),
        .data_in(processor_router_data_noc3),
        .valid_in(processor_router_valid_noc3),
        .ready_in(router_processor_ready_noc3),

        .data_out(buffer_router_data_noc3),           // Data
        .valid_out(buffer_router_valid_noc3),       // Val signal
        .yummy_out(router_buffer_consumed_noc3)    // Yummy signal
    );

    credit_to_valrdy cgni_blk2(
        .clk(clk_gated),
        .reset(~rst_n_f),
        .data_in(router_buffer_data_noc2),
        .valid_in(router_buffer_data_val_noc2),
        .yummy_in(buffer_router_yummy_noc2),

        .data_out(buffer_processor_data_noc2),           // Data
        .valid_out(buffer_processor_valid_noc2),       // Val signal from dynamic network to processor
        .ready_out(processor_router_ready_noc2)    // Rdy signal from processor to dynamic network
    );


///////////////////////
// Instantiate Cores //
///////////////////////
generate
if (TILE_TYPE == `ARIANE_RV64_TILE) begin : g_ariane_core
    //////////////////////
    // Ariane RV64 Core //
    //////////////////////

`ifdef PITON_ARIANE

    // TODO: add debug module and CLINT

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

    assign ariane_bootaddr  =  64'hFFF1010000;



    ariane_verilog_wrap #(

        .NrPMPEntries           ( 4    ),
        .DmBaseAddress          ( 64'hFFF1000000 ),
        .SwapEndianess          ( 1'b1 ),
        .NrExecuteRegionRules   ( 3   ),
        .ExecuteRegionAddrBase  ( {64'h80000000, 64'hFFF1000000, 64'hFFF1010000}   ),
        .ExecuteRegionLength    ( {64'h40000000, 64'h1000, 64'h10000}   ),
        .NrCachedRegionRules    (  1   ),
        .CachedRegionAddrBase   ( {64'h80000000} ),
        .CachedRegionLength     ( {64'h40000000} )

    ) core (
        .clk_i       ( clk_gated              ),
        .reset_l     ( rst_n_f                ),
        .spc_grst_l  ( spc_grst_l             ),
        .boot_addr_i ( ariane_bootaddr        ),
        .hart_id_i   ( {{64-`JTAG_FLATID_WIDTH{1'b0}}, flat_tileid} ),
        .irq_i       ( irq_i                  ),
        .ipi_i       ( ipi_i                  ),
        .time_irq_i  ( timer_irq_i            ),
        .debug_req_i ( debug_req_i            ),
        .l15_req_o   ( l15_req                ),
        .l15_rtrn_i  ( l15_rtrn               )
    );


`endif // ifdef PITON_ARIANE
  end
  endgenerate


    //////////
    // L1.5 //
    //////////

    l15_wrap l15(
        .clk(clk_gated),
        .rst_n(spc_grst_l),

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


        .noc1_out_rdy(router_processor_ready_noc1),
        .noc2_in_val(buffer_processor_valid_noc2),
        .noc2_in_data(buffer_processor_data_noc2),
        .noc3_out_rdy(router_processor_ready_noc3),
        .dmbr_l15_stall(dmbr_l15_stall),
        .chipid(config_chipid),
        .coreid_x(config_coreid_x),
        .coreid_y(config_coreid_y),

        .noc1_out_val(processor_router_valid_noc1),
        .noc1_out_data(processor_router_data_noc1),
        .noc2_in_rdy(processor_router_ready_noc2),
        .noc3_out_val(processor_router_valid_noc3),
        .noc3_out_data(processor_router_data_noc3),
        .l15_dmbr_l1missIn(l15_dmbr_l1missIn),
        .l15_dmbr_l1missTag(l15_dmbr_l1missTag),
        .l15_dmbr_l2missIn(l15_dmbr_l2missIn),
        .l15_dmbr_l2missTag(l15_dmbr_l2missTag),
        .l15_dmbr_l2responseIn(l15_dmbr_l2responseIn),

        // config registers
        .l15_config_req_val_s2(l15_config_req_val_s2),
        .l15_config_req_rw_s2(l15_config_req_rw_s2),
        .l15_config_write_req_data_s2(l15_config_write_req_data_s2),
        .l15_config_req_address_s2(l15_config_req_address_s2),
        .config_l15_read_res_data_s3(config_l15_read_res_data_s3),

        // config regs
        .config_csm_en(config_csm_en),
        .config_hmt_base(config_hmt_base),
        .config_system_tile_count(config_system_tile_count),
        .config_home_alloc_method(config_home_alloc_method),

        // sram interfaces
        .srams_rtap_data (l15_rtap_data),
        .rtap_srams_bist_command (rtap_srams_bist_command),
        .rtap_srams_bist_data (rtap_srams_bist_data)
    );


endmodule
