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
// mshr_coverage_bind.sv
//
// SV `bind` directives that attach functional coverage observers to
// the HNF non-invasively (same pattern as mshr_observer_bind.sv).
// Compile alongside the matching coverage SV files when COVERAGE=1.

// ── MSHR allocation + transient-phase coverage ───────────────────────────
bind hnf_mshr_ctl mshr_coverage u_cov (
    .clk                          (clk),
    .rst                          (rst),
    .mshr_alloc_en_s1_q           (mshr_alloc_en_s1_q),
    .mshr_entry_idx_alloc_s1_q    (mshr_entry_idx_alloc_s1_q),
    .mshr_opcode_s1_q             (mshr_opcode_s1_q),
    .mshr_srcid_s1_q              (mshr_srcid_s1_q),
    .mshr_txnid_s1_q              (mshr_txnid_s1_q),
    .mshr_addr_s1_q               (mshr_addr_s1_q),
    .mshr_compack_s1_q            (mshr_compack_s1_q),
    .mshr_snprsp_entry_vec_s1_q   (mshr_snprsp_entry_vec_s1_q),
    .mshr_snpdat_entry_vec_s1_q   (mshr_snpdat_entry_vec_s1_q),
    .mshr_dat_entry_vec_s1_q      (mshr_dat_entry_vec_s1_q)
);

// ── Coherence FSM (per-line SF state) coverage ───────────────────────────
// Sampled at SX4 inside the cache pipeline. Defaults match the current
// HNF parameters (RNF_NUM=4, OPCODE_WIDTH=7, NID_WIDTH=7, CPL_STAGE=7).
bind hnf_cache_pipeline coherence_coverage u_coh_cov (
    .clk                          (clk),
    .rst                          (rst),
    .pipe_req_valid_sx_q          (pipe_req_valid_sx_q),
    .pipe_sf_match_state_sx4_q    (pipe_sf_match_state_sx4_q),
    .pipe_tag_match_sx4_q         (pipe_tag_match_sx4_q),
    .pipe_opcode_sx_q             (pipe_opcode_sx_q),
    .pipe_rnf_idx_sx_q            (pipe_rnf_idx_sx_q)
);
