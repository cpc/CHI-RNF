/*
 * Copyright (c) 2026 Customized Parallel Computing (CPC) Group, Tampere University
 * Author: Abdesattar Kalache <abdesattar.kalache@tuni.fi>
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
 */
// GENERIC LINK


module chi_icn_link #(
    parameter int CHIE_REQ_FLIT_WIDTH = 64,
    parameter int CHIE_RSP_FLIT_WIDTH = 64,
    parameter int CHIE_DAT_FLIT_WIDTH = 64,
    parameter int CHIE_SNP_FLIT_WIDTH = 64
)(

    input  logic clk,
    input  logic rst,

    input  logic                       txreqflitv,
    input  logic [CHIE_REQ_FLIT_WIDTH-1:0] txreqflit,
    output logic                       txreqlcrdv,

    input  logic                       txrspflitv,
    input  logic [CHIE_RSP_FLIT_WIDTH-1:0] txrspflit,
    output logic                       txrsplcrdv,

    input  logic                      txdatflitv,
    input  logic [CHIE_DAT_FLIT_WIDTH-1:0] txdatflit,
    output logic                      txdatlcrdv,

    input  logic                      txsnpflitv,
    input  logic [CHIE_SNP_FLIT_WIDTH-1:0] txsnpflit,
    output logic                      txsnplcrdv,


    output logic                       rxsnpflitv,
    output logic [CHIE_SNP_FLIT_WIDTH-1:0] rxsnpflit,
    input  logic                       rxsnplcrdv,

    output logic                       rxrspflitv,
    output logic [CHIE_RSP_FLIT_WIDTH-1:0] rxrspflit,
    input  logic                       rxrsplcrdv,

    output logic                       rxdatflitv,
    output logic [CHIE_DAT_FLIT_WIDTH-1:0] rxdatflit,
    input  logic                       rxdatlcrdv,

    output logic                       rxsnpflitv,
    output logic [CHIE_SNP_FLIT_WIDTH-1:0] rxsnpflit,
    input  logic                       rxsnplcrdv,

    // Link layer handshake
    input  logic                      txlinkactivereq,
    output logic                      txlinkactiveack,
    output logic                      rxlinkactivereq,
    input  logic                      rxlinkactiveack,
    input  logic                      txactive,
    output logic                      rxactive
);

    parameter int NUM_CHANNELS = 4;
endmodule