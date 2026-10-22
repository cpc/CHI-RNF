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


// RNF Wrapper in SystemVerilog
`include "rnf_param.v"
`include "rnf_defines.v"
`include "chie_defines.v"


module rnf_wrapper #(
    parameter int corecount_g = 2,

    parameter int CHIE_REQ_ADDR_WIDTH_PARAM     = 44,
    parameter int CHIE_SNP_ADDR_WIDTH_PARAM     = 41,
    parameter int CHIE_NID_WIDTH_PARAM          = 7,
    parameter int CHIE_DATA_WIDTH_PARAM         = 256,
    parameter int CHIE_BE_WIDTH_PARAM           = 32,
    parameter int CHIE_DATACHECK_WIDTH_PARAM    = 32,
    parameter int CHIE_POISON_WIDTH_PARAM       = 4,
    parameter int CHIE_REQ_RSVDC_WIDTH_PARAM    = 0,
    parameter int CHIE_DAT_RSVDC_WIDTH_PARAM    = 0,
    parameter int HNF_NID_PARAM                 = 0,
    parameter int XP_LCRD_NUM_PARAM             = 15,
    parameter int RNF_NID                       = 0
)(
    input  logic                                     clk,
    input  logic                                     rst_n,
    input  logic                                     clk_en,

    // Per-core RISC-V Debug Module halt request (async).  Tie to 0 to disable.
    input  logic [corecount_g-1:0]                   debug_req_i,

    // --- RX Path (ICN -> RNF) ---
    // Transitioned to [CORE][WIDTH] packed arrays
    input  logic [corecount_g-1:0]                          rxrspflitv,
    input  logic [corecount_g-1:0][`CHIE_RSP_FLIT_WIDTH-1:0] rxrspflit,
    input  logic [corecount_g-1:0]                          rxrspflitpend,

    input  logic [corecount_g-1:0]                          rxdatflitv,
    input  logic [corecount_g-1:0][`CHIE_DAT_FLIT_WIDTH-1:0] rxdatflit,
    input  logic [corecount_g-1:0]                          rxdatflitpend,

    input  logic [corecount_g-1:0]                          rxsnpflitv,
    input  logic [corecount_g-1:0][`CHIE_SNP_FLIT_WIDTH-1:0] rxsnpflit,
    input  logic [corecount_g-1:0]                          rxsnpflitpend,

    // Credits from responder
    input  logic [corecount_g-1:0]                          txreqlcrdv,
    input  logic [corecount_g-1:0]                          txrsplcrdv,
    input  logic [corecount_g-1:0]                          txdatlcrdv,

    // OUTPUTS - Credits to requestor
    output logic [corecount_g-1:0]                          rxrsplcrdv,
    output logic [corecount_g-1:0]                          rxdatlcrdv,
    output logic [corecount_g-1:0]                          rxsnplcrdv,

    // to request channel
    output logic [corecount_g-1:0]                          txreqflitv,
    output logic [corecount_g-1:0][`CHIE_REQ_FLIT_WIDTH-1:0] txreqflit,
    output logic [corecount_g-1:0]                          txreqflitpend,

    // response channel
    output logic [corecount_g-1:0]                          txrspflitv,
    output logic [corecount_g-1:0][`CHIE_RSP_FLIT_WIDTH-1:0] txrspflit,
    output logic [corecount_g-1:0]                          txrspflitpend,

    // to data channel
    output logic [corecount_g-1:0]                          txdatflitv,
    output logic [corecount_g-1:0][`CHIE_DAT_FLIT_WIDTH-1:0] txdatflit,
    output logic [corecount_g-1:0]                          txdatflitpend,

    // Link layer handshake
    output logic [corecount_g-1:0]                          txlinkactivereq,
    input  logic [corecount_g-1:0]                          txlinkactiveack,
    input  logic [corecount_g-1:0]                          rxlinkactivereq,
    output logic [corecount_g-1:0]                          rxlinkactiveack,
    output logic [corecount_g-1:0]                          txactive,
    input  logic [corecount_g-1:0]                          rxactive
);

    // --- Core Generation Loop ---
    generate
        for (genvar i = 0; i < corecount_g; i++) begin : RNF_GEN
            rnf_top #(
                .CHIE_REQ_ADDR_WIDTH_PARAM     (CHIE_REQ_ADDR_WIDTH_PARAM),
                .CHIE_SNP_ADDR_WIDTH_PARAM     (CHIE_SNP_ADDR_WIDTH_PARAM),
                .CHIE_NID_WIDTH_PARAM          (CHIE_NID_WIDTH_PARAM),
                .CHIE_DATA_WIDTH_PARAM         (CHIE_DATA_WIDTH_PARAM),
                .CHIE_BE_WIDTH_PARAM           (CHIE_BE_WIDTH_PARAM),
                .CHIE_DATACHECK_WIDTH_PARAM    (CHIE_DATACHECK_WIDTH_PARAM),
                .CHIE_POISON_WIDTH_PARAM       (CHIE_POISON_WIDTH_PARAM),
                .CHIE_REQ_RSVDC_WIDTH_PARAM    (CHIE_REQ_RSVDC_WIDTH_PARAM),
                .CHIE_DAT_RSVDC_WIDTH_PARAM    (CHIE_DAT_RSVDC_WIDTH_PARAM),
                .HNF_NID_PARAM                 (HNF_NID_PARAM),
                .XP_LCRD_NUM_PARAM             (XP_LCRD_NUM_PARAM),
                .RNF_NID                       (i)   // Assign core ID based on loop index
            ) u_rnf (
                .clk             (clk),
                .rst_n           (rst_n),
                .clk_en          (clk_en),
                //.debug_req_i     (debug_req_i[i]),

                .RXRSPFLITV      (rxrspflitv[i]),
                .RXRSPFLIT       (rxrspflit[i]),
                .RXRSPFLITPEND   (rxrspflitpend[i]),

                .RXDATFLITV      (rxdatflitv[i]),
                .RXDATFLIT       (rxdatflit[i]),
                .RXDATFLITPEND   (rxdatflitpend[i]),

                .RXSNPFLITV      (rxsnpflitv[i]),
                .RXSNPFLIT       (rxsnpflit[i]),
                .RXSNPFLITPEND   (rxsnpflitpend[i]),

                // Credit Inputs
                .TXREQLCRDV      (txreqlcrdv[i]),
                .TXRSPLCRDV      (txrsplcrdv[i]),
                .TXDATLCRDV      (txdatlcrdv[i]),

                // Credit Outputs
                .RXRSPLCRDV      (rxrsplcrdv[i]),
                .RXDATLCRDV      (rxdatlcrdv[i]),
                .RXSNPLCRDV      (rxsnplcrdv[i]),

                // TX CHI Signals
                .TXREQFLITV      (txreqflitv[i]),
                .TXREQFLIT       (txreqflit[i]),
                .TXREQFLITPEND   (txreqflitpend[i]),

                .TXRSPFLITV      (txrspflitv[i]),
                .TXRSPFLIT       (txrspflit[i]),
                .TXRSPFLITPEND   (txrspflitpend[i]),

                .TXDATFLITV      (txdatflitv[i]),
                .TXDATFLIT       (txdatflit[i]),
                .TXDATFLITPEND   (txdatflitpend[i]),

                // Handshake
                .TXLINKACTIVEREQ (txlinkactivereq[i]),
                .TXLINKACTIVEACK (txlinkactiveack[i]),
                .RXLINKACTIVEREQ (rxlinkactivereq[i]),
                .RXLINKACTIVEACK (rxlinkactiveack[i]),
                .TXACTIVE        (txactive[i]),
                .RXACTIVE        (rxactive[i])
            );
        end
    endgenerate

endmodule