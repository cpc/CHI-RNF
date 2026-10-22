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
 * rnf_coverage_bind.sv
 *
 * Binds the rnf_coverage module into the rnf_ip_tb top level.  Keeps
 * the coverage attachment a single-line edit at the top scope -- the
 * cover module taps the CHI wires connecting the DUT (l15_wrap) to
 * the abstract responder (chi_hnf_responder).
 */

bind rnf_ip_tb rnf_coverage u_rnf_cov (
    .clk        (clk),
    .rst_n      (rst_n),
    .RXSNPFLITV (rxsnpflitv),
    .RXSNPFLIT  (rxsnpflit),
    .RXRSPFLITV (rxrspflitv),
    .RXRSPFLIT  (rxrspflit),
    .RXDATFLITV (rxdatflitv),
    .RXDATFLIT  (rxdatflit),
    .TXREQFLITV (txreqflitv),
    .TXREQFLIT  (txreqflit),
    .TXRSPFLITV (txrspflitv),
    .TXRSPFLIT  (txrspflit),
    .TXDATFLITV (txdatflitv),
    .TXDATFLIT  (txdatflit),
    // Suppress covergroup samples during the write-visibility probe
    // (probing==1).  The probe drives synthetic LDs/STs whose CHI
    // activity does not correspond to any Murphi-modelled transition
    // and would corrupt cp_prev_state / cp_l1_at_issue and the crosses.
    .sample_enable (!probing),
    // L1 state probe -- see the port comments in rnf_coverage.sv.  The
    // path used to be hard-coded inside that module, which made it
    // bindable to this testbench only.
    .probe_l1_state (u_dut.l15.pipeline.tagcheck_state_s2),
    .probe_l1_val   (u_dut.l15.pipeline.val_s2),
    .probe_reqtype  (u_dut.l15.pipeline.predecode_reqtype_s2)
);
