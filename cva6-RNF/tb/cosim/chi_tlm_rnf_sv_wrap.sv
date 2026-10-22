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
// SV port stub for chi_tlm_rnf SC module.
// Questa maps SV instances of this module to the SC chi_tlm_rnf class
// loaded from work/systemc.so at elaboration time.  The body is empty;
// all behaviour comes from the compiled SystemC model.
//
// Port widths are computed via `CHIE_*_FLIT_WIDTH macros so the stub
// tracks the TB's `CHIE_DATA_WIDTH_PARAM` setting (128/256/512).  For a
// binding to succeed, the SC bridge must be compiled with a matching
// `-DCHI_DATA_BEAT_BITS=<width>` (see cva6-RNF/tb/cosim/chi_tlm_rnf.h — the
// header derives CHI_DAT_W from CHI_DATA_BEAT_BITS with the same formula
// the RTL uses for CHIE_DAT_FLIT_WIDTH).  The Makefile target `sc`
// forwards SCCOM_DEFS so `make SCCOM_DEFS='-DCHI_DATA_BEAT_BITS=128'`
// keeps them coherent.
module chi_tlm_rnf #(
    parameter CHIE_REQ_ADDR_WIDTH_PARAM  = 44,
    parameter CHIE_SNP_ADDR_WIDTH_PARAM  = 41,
    parameter CHIE_NID_WIDTH_PARAM       = 7,
    parameter CHIE_DATA_WIDTH_PARAM      = 256,
    parameter CHIE_BE_WIDTH_PARAM        = 32,
    parameter CHIE_DATACHECK_WIDTH_PARAM = 0,
    parameter CHIE_POISON_WIDTH_PARAM    = 0,
    parameter CHIE_REQ_RSVDC_WIDTH_PARAM = 0,
    parameter CHIE_DAT_RSVDC_WIDTH_PARAM = 0
) (
    input  logic                              clk,
    input  logic                              rstn,

    output logic                              txreq_flitv,
    output logic                              txreq_flitpend,
    output logic [`CHIE_REQ_FLIT_WIDTH-1:0]   txreq_flit,
    input  logic                              txreq_lcrdv,

    output logic                              txrsp_flitv,
    output logic                              txrsp_flitpend,
    output logic [`CHIE_RSP_FLIT_WIDTH-1:0]   txrsp_flit,
    input  logic                              txrsp_lcrdv,

    output logic                              txdat_flitv,
    output logic                              txdat_flitpend,
    output logic [`CHIE_DAT_FLIT_WIDTH-1:0]   txdat_flit,
    input  logic                              txdat_lcrdv,

    input  logic                              rxrsp_flitv,
    input  logic                              rxrsp_flitpend,
    input  logic [`CHIE_RSP_FLIT_WIDTH-1:0]   rxrsp_flit,
    output logic                              rxrsp_lcrdv,

    input  logic                              rxdat_flitv,
    input  logic                              rxdat_flitpend,
    input  logic [`CHIE_DAT_FLIT_WIDTH-1:0]   rxdat_flit,
    output logic                              rxdat_lcrdv,

    input  logic                              rxsnp_flitv,
    input  logic                              rxsnp_flitpend,
    input  logic [`CHIE_SNP_FLIT_WIDTH-1:0]   rxsnp_flit,
    output logic                              rxsnp_lcrdv,

    output logic                              txlinkactivereq,
    input  logic                              txlinkactiveack,
    input  logic                              rxlinkactivereq,
    output logic                              rxlinkactiveack
);
endmodule
