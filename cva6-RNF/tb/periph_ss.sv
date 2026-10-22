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

`include "hnf_param.v"
`include "hnf_defines.v"

`include "chie_defines.v"


module periph_ss #(
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

    // CHI Link Control (HN-I Interface)
    output wire                                 TXLINKACTIVEREQ,
    input  wire                                 TXLINKACTIVEACK,
    input  wire                                 RXLINKACTIVEREQ,
    output wire                                 RXLINKACTIVEACK,
    output wire                                 TXSACTIVE,
    input  wire                                 RXSACTIVE,

    // CHI RX Channels (From RN-F/ICN)
    input  wire                                 RXREQFLITV,
    input  wire [`CHIE_REQ_FLIT_RANGE]          RXREQFLIT,
    input  wire                                 RXREQFLITPEND,
    output wire                                 RXREQLCRDV,

    input  wire                                 RXDATFLITV,
    input  wire [`CHIE_DAT_FLIT_RANGE]          RXDATFLIT,
    input  wire                                 RXDATFLITPEND,
    output wire                                 RXDATLCRDV,

    // CHI TX Channels (To RN-F/ICN)
    output wire                                 TXRSPFLITV,
    output wire [`CHIE_RSP_FLIT_RANGE]          TXRSPFLIT,
    output wire                                 TXRSPFLITPEND,
    input  wire                                 TXRSPLCRDV,

    output wire                                 TXDATFLITV,
    output wire [`CHIE_DAT_FLIT_RANGE]          TXDATFLIT,
    output wire                                 TXDATFLITPEND,
    input  wire                                 TXDATLCRDV
);



endmodule