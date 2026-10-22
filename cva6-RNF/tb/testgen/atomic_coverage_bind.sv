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
// atomic_coverage_bind.sv
//
// SV `bind` directive for atomic_coverage.  Wires the per-entry atomic
// state vectors that drive the RMW data path so coverage can capture
// lifecycle events (operand received, memwr fired, OLD latched, retire).

bind hnf_mshr_ctl atomic_coverage u_atomic_cov (
    .clk                              (clk),
    .rst                              (rst),
    .mshr_alloc_en_s1_q               (mshr_alloc_en_s1_q),
    .mshr_entry_idx_alloc_s1_q        (mshr_entry_idx_alloc_s1_q),
    .mshr_opcode_s1_q                 (mshr_opcode_s1_q),
    .mshr_atomic_active_vec_sx1_q     (mshr_atomic_active_vec_sx1_q),
    .mshr_atomic_op_vec_sx1_q         (mshr_atomic_op_vec_sx1_q),
    .mshr_atomic_busy_sx_q            (mshr_atomic_busy_sx_q),
    .mshr_atomic_operand_pulse_s1_q   (mshr_atomic_operand_pulse_s1_q),
    .mshr_atomic_operand_arr_s1_q     (mshr_atomic_operand_arr_s1_q),
    .mshr_atomic_memwr_fired_s1_q     (mshr_atomic_memwr_fired_s1_q),
    .mshr_atomic_sn_dat_queued_s1_q   (mshr_atomic_sn_dat_queued_s1_q),
    .mshr_dat_old_get_s1_q            (mshr_dat_old_get_s1_q),
    .mshr_atomicld_s1_q               (mshr_atomicld_s1_q),
    .mshr_atomicst_s1_q               (mshr_atomicst_s1_q)
);
