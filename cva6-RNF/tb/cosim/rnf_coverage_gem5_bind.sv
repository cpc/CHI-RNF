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
/*
 * rnf_coverage_gem5_bind.sv
 *
 * Binds rnf_coverage into the gem5 co-sim testbench (tb_chi_system in
 * tb/cosim/riscv_rnf_gem5_tb.sv), so the same functional coverage model that
 * measures the Murphi-derived IP-level sweep also measures full-system
 * traffic.  Same covergroups, same phase tracker, same bins -- only the
 * stimulus differs, which is the point: it makes IP-level and
 * full-system coverage directly comparable.
 *
 * Two differences from the IP-level bind (rnf_coverage_bind.sv):
 *
 *   1. The CHI wires are ARRAYED per core (rnf_txreqflit[i] etc.), so
 *      one coverage instance is bound per RN-F.  Questa merges the
 *      covergroup TYPES across instances in the report, so the totals
 *      are per-design not per-core; per-core detail is still available
 *      in the instance sections.
 *
 *   2. sample_enable is tied high.  The IP-level bind gates it with
 *      !probing to suppress samples during the write-visibility probe;
 *      the gem5 TB has no such probe, every cycle is real traffic.
 *
 * The L1-state probe path is
 *   u_rnf_wrap.RNF_GEN[i].u_rnf.l15.l15.pipeline
 * (rnf_wrapper -> generate RNF_GEN -> rnf_top u_rnf -> l15_wrap l15 ->
 *  l15 l15 -> l15_pipeline pipeline).  Note the doubled `l15.l15`: the
 * wrapper instance and the module inside it share a name.
 *
 * CORE_COUNT is 2 in this TB.  Binds are written out explicitly rather
 * than generated because a bind target path cannot be built from a
 * genvar.
 */

bind tb_chi_system rnf_coverage #(
    // MUST match the TB's CHI geometry.  rnf_coverage defaults to
    // CHIE_DATA_WIDTH_PARAM=256 (a 370-bit DAT flit); this TB runs 512
    // (668-bit).  Binding without these produced
    //   "Port size (370) does not match connection size (668)"
    // on RXDATFLIT/TXDATFLIT -- and because the module decodes opcode,
    // resp and dataid by BIT POSITION, a truncated connection reads the
    // wrong fields and yields confidently wrong coverage rather than an
    // error.  Passed through from the TB's parameters rather than
    // hard-coded, since the data width is overridable per run with
    // vsim -G <top>.CHIE_DATA_WIDTH_PARAM=<128|256|512>.
    .CHIE_REQ_ADDR_WIDTH_PARAM  (CHIE_REQ_ADDR_WIDTH_PARAM),
    .CHIE_SNP_ADDR_WIDTH_PARAM  (CHIE_SNP_ADDR_WIDTH_PARAM),
    .CHIE_NID_WIDTH_PARAM       (CHIE_NID_WIDTH_PARAM),
    .CHIE_DATA_WIDTH_PARAM      (CHIE_DATA_WIDTH_PARAM),
    .CHIE_BE_WIDTH_PARAM        (CHIE_BE_WIDTH_PARAM),
    .CHIE_DATACHECK_WIDTH_PARAM (CHIE_DATACHECK_WIDTH_PARAM),
    .CHIE_POISON_WIDTH_PARAM    (CHIE_POISON_WIDTH_PARAM),
    .CHIE_REQ_RSVDC_WIDTH_PARAM (CHIE_REQ_RSVDC_WIDTH_PARAM),
    .CHIE_DAT_RSVDC_WIDTH_PARAM (CHIE_DAT_RSVDC_WIDTH_PARAM)
) u_rnf_cov0 (
    .clk        (clk),
    .rst_n      (rst_n),
    .RXSNPFLITV (rnf_rxsnpflitv[0]),
    .RXSNPFLIT  (rnf_rxsnpflit[0]),
    .RXRSPFLITV (rnf_rxrspflitv[0]),
    .RXRSPFLIT  (rnf_rxrspflit[0]),
    .RXDATFLITV (rnf_rxdatflitv[0]),
    .RXDATFLIT  (rnf_rxdatflit[0]),
    .TXREQFLITV (rnf_txreqflitv[0]),
    .TXREQFLIT  (rnf_txreqflit[0]),
    .TXRSPFLITV (rnf_txrspflitv[0]),
    .TXRSPFLIT  (rnf_txrspflit[0]),
    .TXDATFLITV (rnf_txdatflitv[0]),
    .TXDATFLIT  (rnf_txdatflit[0]),
    .sample_enable  (1'b1),
    .probe_l1_state (u_rnf_wrap.RNF_GEN[0].u_rnf.l15.l15.pipeline.tagcheck_state_s2),
    .probe_l1_val   (u_rnf_wrap.RNF_GEN[0].u_rnf.l15.l15.pipeline.val_s2),
    .probe_reqtype  (u_rnf_wrap.RNF_GEN[0].u_rnf.l15.l15.pipeline.predecode_reqtype_s2)
);

bind tb_chi_system rnf_coverage #(
    // MUST match the TB's CHI geometry.  rnf_coverage defaults to
    // CHIE_DATA_WIDTH_PARAM=256 (a 370-bit DAT flit); this TB runs 512
    // (668-bit).  Binding without these produced
    //   "Port size (370) does not match connection size (668)"
    // on RXDATFLIT/TXDATFLIT -- and because the module decodes opcode,
    // resp and dataid by BIT POSITION, a truncated connection reads the
    // wrong fields and yields confidently wrong coverage rather than an
    // error.  Passed through from the TB's parameters rather than
    // hard-coded, since the data width is overridable per run with
    // vsim -G <top>.CHIE_DATA_WIDTH_PARAM=<128|256|512>.
    .CHIE_REQ_ADDR_WIDTH_PARAM  (CHIE_REQ_ADDR_WIDTH_PARAM),
    .CHIE_SNP_ADDR_WIDTH_PARAM  (CHIE_SNP_ADDR_WIDTH_PARAM),
    .CHIE_NID_WIDTH_PARAM       (CHIE_NID_WIDTH_PARAM),
    .CHIE_DATA_WIDTH_PARAM      (CHIE_DATA_WIDTH_PARAM),
    .CHIE_BE_WIDTH_PARAM        (CHIE_BE_WIDTH_PARAM),
    .CHIE_DATACHECK_WIDTH_PARAM (CHIE_DATACHECK_WIDTH_PARAM),
    .CHIE_POISON_WIDTH_PARAM    (CHIE_POISON_WIDTH_PARAM),
    .CHIE_REQ_RSVDC_WIDTH_PARAM (CHIE_REQ_RSVDC_WIDTH_PARAM),
    .CHIE_DAT_RSVDC_WIDTH_PARAM (CHIE_DAT_RSVDC_WIDTH_PARAM)
) u_rnf_cov1 (
    .clk        (clk),
    .rst_n      (rst_n),
    .RXSNPFLITV (rnf_rxsnpflitv[1]),
    .RXSNPFLIT  (rnf_rxsnpflit[1]),
    .RXRSPFLITV (rnf_rxrspflitv[1]),
    .RXRSPFLIT  (rnf_rxrspflit[1]),
    .RXDATFLITV (rnf_rxdatflitv[1]),
    .RXDATFLIT  (rnf_rxdatflit[1]),
    .TXREQFLITV (rnf_txreqflitv[1]),
    .TXREQFLIT  (rnf_txreqflit[1]),
    .TXRSPFLITV (rnf_txrspflitv[1]),
    .TXRSPFLIT  (rnf_txrspflit[1]),
    .TXDATFLITV (rnf_txdatflitv[1]),
    .TXDATFLIT  (rnf_txdatflit[1]),
    .sample_enable  (1'b1),
    .probe_l1_state (u_rnf_wrap.RNF_GEN[1].u_rnf.l15.l15.pipeline.tagcheck_state_s2),
    .probe_l1_val   (u_rnf_wrap.RNF_GEN[1].u_rnf.l15.l15.pipeline.val_s2),
    .probe_reqtype  (u_rnf_wrap.RNF_GEN[1].u_rnf.l15.l15.pipeline.predecode_reqtype_s2)
);
