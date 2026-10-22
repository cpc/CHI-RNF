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
// mshr_observer_bind.sv
//
// SV `bind` directive that non-invasively attaches mshr_observer to every
// instance of hnf_mshr_ctl in the design. Put this file in the vlog
// command line alongside mshr_observer.sv; it does not require changes
// to chi_monitor.sv, chi_icn_beh.sv, tlm_rnf_hnf_tb.sv, or any HNF RTL.
//
// Effect: each hnf_mshr_ctl instance gets an internal u_obs that emits
// trace lines to stdout (see header of mshr_observer.sv for format).
//
// No `include directives — mshr_observer's defaults already match the
// HNF parameters used in this build (see comments in mshr_observer.sv).
// If the HNF is re-parameterised with a different CHIE_REQ_ADDR_WIDTH
// etc., add explicit parameter overrides below.

bind hnf_mshr_ctl mshr_observer u_obs (
    .clk                          (clk),
    .rst                          (rst),
    .mshr_alloc_en_s1_q           (mshr_alloc_en_s1_q),
    .mshr_entry_idx_alloc_s1_q    (mshr_entry_idx_alloc_s1_q),
    .mshr_dbf_retired_valid_sx1_q (mshr_dbf_retired_valid_sx1_q),
    .mshr_dbf_retired_idx_sx1_q   (mshr_dbf_retired_idx_sx1_q),
    .mshr_opcode_s1_q             (mshr_opcode_s1_q),
    .mshr_srcid_s1_q              (mshr_srcid_s1_q),
    .mshr_txnid_s1_q              (mshr_txnid_s1_q),
    .mshr_addr_s1_q               (mshr_addr_s1_q),
    .mshr_compack_s1_q            (mshr_compack_s1_q),
    .mshr_snprsp_entry_vec_s1_q   (mshr_snprsp_entry_vec_s1_q),
    .mshr_snpdat_entry_vec_s1_q   (mshr_snpdat_entry_vec_s1_q),
    .mshr_dat_entry_vec_s1_q      (mshr_dat_entry_vec_s1_q)
);
