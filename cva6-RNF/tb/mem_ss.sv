/*
 * Copyright (c) 2026 Customized Parallel Computing (CPC) Group Tampere University
 *
 * SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
 *
 * Licensed under the Solderpad Hardware License v2.1 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at:
 *
 *     https://solderpad.org/licenses/SHL-2.1/
 *
 * Unless required by applicable law or agreed to in writing, any work
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
 * implied.  See the License for the specific language governing
 * permissions and limitations under the License.
 *
 * Author:
 * Abdesattar Kalache <abdesattar.kalache@tuni.fi>
 */



`include "snf_param.v"
`include "snf_defines.v"

`include "chie_defines.v"

module mem_ss #(
    // --- CHI Parameter Pass-through ---
    parameter int CHIE_REQ_ADDR_WIDTH_PARAM    = 64,
    parameter int CHIE_SNP_ADDR_WIDTH_PARAM    = 64,
    parameter int CHIE_NID_WIDTH_PARAM         = 7,
    parameter int CHIE_DATA_WIDTH_PARAM        = 512,
    parameter int CHIE_BE_WIDTH_PARAM          = 64,
    parameter int CHIE_DATACHECK_WIDTH_PARAM   = 64,
    parameter int CHIE_POISON_WIDTH_PARAM      = 1,
    parameter int CHIE_REQ_RSVDC_WIDTH_PARAM   = 1,
    parameter int CHIE_DAT_RSVDC_WIDTH_PARAM   = 1,
    parameter int HNF_MSHR_RNF_NUM_PARAM       = 4,
    parameter int HNF_MSHR_RNI_NUM_PARAM       = 1,
    parameter int RNF_NID_LIST_PARAM           = 0,
    parameter int RNI_NID_LIST_PARAM           = 0,
    parameter int HNF_NID_PARAM                = 0,
    parameter int SNF_NID_PARAM                = 0,
    parameter int XP_LCRD_NUM_PARAM            = 4,
    parameter int HNF_SF_ENTRIES_NUM_PARAM     = 1024,
    parameter int HNF_SF_WAY_NUM_PARAM         = 4,
    parameter int HNF_MSHR_EXCL_RN_NUM_PARAM   = 4,
    parameter int HNF_MSHR_EXCL_RN_WIDTH_PARAM = 2,
    parameter int HNF_MSHR_ENTRIES_NUM_PARAM   = 8,
    parameter int HNF_MSHR_ENTRIES_WIDTH_PARAM = 3,
    parameter int HNF_L3_CACHE_SIZE_PARAM      = 1024,
    parameter int HNF_L3_WAY_NUM_PARAM         = 8,

    parameter int AXI_DATA_WIDTH               = -1,
    parameter int AXI_ADDR_WIDTH               = -1,
    parameter int AXI_ID_WIDTH                 = -1,
    parameter int AXI_USER_WIDTH               = -1
)(
    input  wire                                 CLK,
    input  wire                                 RST,

    // CHI Link Control
    output wire                                 TXLINKACTIVEREQ,
    input  wire                                 TXLINKACTIVEACK,
    input  wire                                 RXLINKACTIVEREQ,
    output wire                                 RXLINKACTIVEACK,
    output wire                                 TXSACTIVE,
    input  wire                                 RXSACTIVE,

    // CHI RX Channels (From Interconnect/HN-I)
    input  wire                                 RXREQFLITV,
    input  wire [`CHIE_REQ_FLIT_RANGE]          RXREQFLIT,
    input  wire                                 RXREQFLITPEND,
    output wire                                 RXREQLCRDV,

    input  wire                                 RXDATFLITV,
    input  wire [`CHIE_DAT_FLIT_RANGE]          RXDATFLIT,
    input  wire                                 RXDATFLITPEND,
    output wire                                 RXDATLCRDV,

    // CHI TX Channels (To Interconnect/HN-I)
    output wire                                 TXRSPFLITV,
    output wire [`CHIE_RSP_FLIT_RANGE]          TXRSPFLIT,
    output wire                                 TXRSPFLITPEND,
    input  wire                                 TXRSPLCRDV,

    output wire                                 TXDATFLITV,
    output wire [`CHIE_DAT_FLIT_RANGE]          TXDATFLIT,
    output wire                                 TXDATFLITPEND,
    input  wire                                 TXDATLCRDV
);

    // Use the AXI_BUS interface to bundle signals for axi2mem
    AXI_BUS #(
        .AXI_ADDR_WIDTH ( AXI_ADDR_WIDTH ),
        .AXI_DATA_WIDTH ( AXI_DATA_WIDTH ),
        .AXI_ID_WIDTH   ( AXI_ID_WIDTH   ),
        .AXI_USER_WIDTH ( AXI_USER_WIDTH )
    ) snf_axi_bus();

    // ========================================================================
    // 2. SNF Node
    // ========================================================================
    // Note: Discrete ports from bridge are mapped into the Interface bundle
    snf #(
        .AXI4_AXDATA_WIDTH_PARAM            (AXI_DATA_WIDTH                    ),
        .AXI4_PA_WIDTH_PARAM                (AXI_ADDR_WIDTH                    ),
        .CHIE_REQ_ADDR_WIDTH_PARAM          (CHIE_REQ_ADDR_WIDTH_PARAM         ),
        .CHIE_NID_WIDTH_PARAM               (CHIE_NID_WIDTH_PARAM              ),
        .CHIE_DATA_WIDTH_PARAM              (CHIE_DATA_WIDTH_PARAM             ),
        .CHIE_BE_WIDTH_PARAM                (CHIE_BE_WIDTH_PARAM               ),
        .CHIE_DATACHECK_WIDTH_PARAM         (CHIE_DATACHECK_WIDTH_PARAM        ),
        .CHIE_POISON_WIDTH_PARAM            (CHIE_POISON_WIDTH_PARAM           ),
        .CHIE_REQ_RSVDC_WIDTH_PARAM         (CHIE_REQ_RSVDC_WIDTH_PARAM        ),
        .CHIE_DAT_RSVDC_WIDTH_PARAM         (CHIE_DAT_RSVDC_WIDTH_PARAM        ),
        .SNF_MSHR_HNF_NUM_PARAM             (4            ),
        .XP_LCRD_NUM_PARAM                  (XP_LCRD_NUM_PARAM                 ),
        .SNF_NID_PARAM                      (SNF_NID_PARAM                     ),
        .SNF_MSHR_ENTRIES_NUM_PARAM         (32        ),
        .SNF_MSHR_ENTRIES_WIDTH_PARAM       (5      )
    ) i_snf (
        .CLK                (CLK),
        .RST                (RST),
        .TXLINKACTIVEREQ    (TXLINKACTIVEREQ),
        .TXLINKACTIVEACK    (TXLINKACTIVEACK),
        .RXLINKACTIVEREQ    (RXLINKACTIVEREQ),
        .RXLINKACTIVEACK    (RXLINKACTIVEACK),
        .TXSACTIVE          (TXSACTIVE),
        .RXSACTIVE          (RXSACTIVE),
        .RXREQFLITV         (RXREQFLITV),
        .RXREQFLIT          (RXREQFLIT),
        .RXREQFLITPEND      (RXREQFLITPEND),
        .RXREQLCRDV         (RXREQLCRDV),
        .RXDATFLITV         (RXDATFLITV),
        .RXDATFLIT          (RXDATFLIT),
        .RXDATFLITPEND      (RXDATFLITPEND),
        .RXDATLCRDV         (RXDATLCRDV),
        .TXRSPFLITV         (TXRSPFLITV),
        .TXRSPFLIT          (TXRSPFLIT),
        .TXRSPFLITPEND      (TXRSPFLITPEND),
        .TXRSPLCRDV         (TXRSPLCRDV),
        .TXDATFLITV         (TXDATFLITV),
        .TXDATFLIT          (TXDATFLIT),
        .TXDATFLITPEND      (TXDATFLITPEND),
        .TXDATLCRDV         (TXDATLCRDV),

        // AXI interface — full master-side signal list. snf is the AXI master;
        // snf_axi_bus is the slave side that axi2mem will consume.
        // Previously missing: ARQOS, ARREGION, AWQOS, AWREGION, AWLOCK, AWCACHE,
        // AWPROT — left dangling, caused TFMPC "Missing connection" warnings.
        .ARID     (snf_axi_bus.ar_id),
        .ARADDR   (snf_axi_bus.ar_addr),
        .ARLEN    (snf_axi_bus.ar_len),
        .ARSIZE   (snf_axi_bus.ar_size),
        .ARBURST  (snf_axi_bus.ar_burst),
        .ARLOCK   (snf_axi_bus.ar_lock),
        .ARCACHE  (snf_axi_bus.ar_cache),
        .ARPROT   (snf_axi_bus.ar_prot),
        .ARQOS    (snf_axi_bus.ar_qos),
        .ARREGION (snf_axi_bus.ar_region),
        .ARVALID  (snf_axi_bus.ar_valid),
        .ARREADY  (snf_axi_bus.ar_ready),
        .RID      (snf_axi_bus.r_id),
        .RDATA    (snf_axi_bus.r_data),
        .RRESP    (snf_axi_bus.r_resp),
        .RLAST    (snf_axi_bus.r_last),
        .RVALID   (snf_axi_bus.r_valid),
        .RREADY   (snf_axi_bus.r_ready),
        .AWID     (snf_axi_bus.aw_id),
        .AWADDR   (snf_axi_bus.aw_addr),
        .AWLEN    (snf_axi_bus.aw_len),
        .AWSIZE   (snf_axi_bus.aw_size),
        .AWBURST  (snf_axi_bus.aw_burst),
        .AWLOCK   (snf_axi_bus.aw_lock),
        .AWCACHE  (snf_axi_bus.aw_cache),
        .AWPROT   (snf_axi_bus.aw_prot),
        .AWQOS    (snf_axi_bus.aw_qos),
        .AWREGION (snf_axi_bus.aw_region),
        .AWVALID  (snf_axi_bus.aw_valid),
        .AWREADY  (snf_axi_bus.aw_ready),
        .WDATA    (snf_axi_bus.w_data),
        .WSTRB    (snf_axi_bus.w_strb),
        .WLAST    (snf_axi_bus.w_last),
        .WVALID   (snf_axi_bus.w_valid),
        .WREADY   (snf_axi_bus.w_ready),
        .BID      (snf_axi_bus.b_id),
        .BRESP    (snf_axi_bus.b_resp),
        .BVALID   (snf_axi_bus.b_valid),
        .BREADY   (snf_axi_bus.b_ready)
    );

    // ========================================================================
    // 3. AXI-to-Memory Adapter (axi2mem)
    // ========================================================================
    wire                           mem_req;
    wire                           mem_we;
    wire [AXI_ADDR_WIDTH-1:0]      mem_addr;
    wire [(AXI_DATA_WIDTH/8)-1:0]  mem_be;
    wire [AXI_DATA_WIDTH-1:0]      mem_wdata;
    wire [AXI_DATA_WIDTH-1:0]      mem_rdata;

    axi2mem #(
        .AXI_ID_WIDTH   ( AXI_ID_WIDTH   ),
        .AXI_ADDR_WIDTH ( AXI_ADDR_WIDTH ),
        .AXI_DATA_WIDTH ( AXI_DATA_WIDTH ),
        .AXI_USER_WIDTH ( AXI_USER_WIDTH )
    ) i_axi2mem (
        .clk_i   ( CLK    ),
        .rst_ni  ( ~RST   ),
        .slave   ( snf_axi_bus.Slave ),
        .req_o   ( mem_req ),
        .we_o    ( mem_we  ),
        .addr_o  ( mem_addr),
        .be_o    ( mem_be  ),
        .user_o  ( ),
        .data_o  ( mem_wdata),
        .user_i  ( '0 ),
        .data_i  ( mem_rdata )
    );

    // ========================================================================
    // 4. SRAM Memory Model — width-matched (AXI_DATA_WIDTH-wide)
    // ========================================================================
    // The old design instantiated tb_snf_sram which is hardcoded to 512-bit
    // words & 26-bit addr. With AXI_DATA_WIDTH=256, axi2mem emits 256-bit
    // beats — zero-padding into the 512-bit SRAM port discarded the upper
    // half of every memory line. Replaced with an inline parameterised
    // SRAM sized to (AXI_DATA_WIDTH × MEM_DEPTH).
    //
    // Indexing: AXI byte-address bits above the beat width.
    //   AXI 256-bit → 32-byte beats → drop addr[4:0] → index = addr[*:5]
    //   AXI 512-bit → 64-byte beats → drop addr[5:0] → index = addr[*:6]
    localparam int BEAT_BYTES   = AXI_DATA_WIDTH / 8;
    localparam int BEAT_BYTES_W = $clog2(BEAT_BYTES);
    localparam int MEM_DEPTH    = 1 << 20;          // 1 M beats = sized for tests
    localparam int IDX_W        = $clog2(MEM_DEPTH);

    reg [AXI_DATA_WIDTH-1:0] mem [0:MEM_DEPTH-1];
    reg [AXI_DATA_WIDTH-1:0] mem_rdata_q;
    wire [IDX_W-1:0]         mem_idx = mem_addr[BEAT_BYTES_W +: IDX_W];

    // Byte-enable-aware write; full-word read (latched by 1 cycle).
    always @(posedge CLK) begin
        if (mem_req && mem_we) begin
            for (int b = 0; b < BEAT_BYTES; b++) begin
                if (mem_be[b]) mem[mem_idx][b*8 +: 8] <= mem_wdata[b*8 +: 8];
            end
        end
        if (mem_req && !mem_we) mem_rdata_q <= mem[mem_idx];
    end
    assign mem_rdata = mem_rdata_q;

endmodule