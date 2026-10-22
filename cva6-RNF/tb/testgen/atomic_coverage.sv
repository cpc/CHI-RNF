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
// atomic_coverage.sv
//
// Functional coverage observer for the HN-F atomic RMW data path.
//
// Atomic transactions deliberately bypass the L3 cache pipeline + snoop
// filter in this minimum-viable implementation, so coherence_coverage.sv
// never samples them at SX4.  This module instead binds into hnf_mshr_ctl
// and samples the atomic-specific signals that govern the RMW lifecycle.
//
// Covergroups:
//   cg_atomic_alloc     — per-opcode allocate (ADD-store, ADD-load, Swap)
//                         × ALU op-code captured into mshr_atomic_op_s1_q
//   cg_atomic_lifecycle — milestone events: operand pulse, sn_data_busy
//                         set/clear, memwr_fired, sn_dat_queued, terminal
//                         flit emitted (atomic_busy clear).  Captures
//                         that each event actually fires for at least one
//                         atomic of each type.
//
// Bound by atomic_coverage_bind.sv to hnf_mshr_ctl; the bind passes all
// the per-entry vectors used by the RMW path.
//

`ifndef ATOMIC_COVERAGE_V
`define ATOMIC_COVERAGE_V

module atomic_coverage #(
    parameter int N             = 32,        // MSHR_ENTRIES_NUM in HN-F
    parameter int OPCODE_WIDTH  = 7,
    parameter int ATOMIC_OPCODE_WIDTH = 4
) (
    input wire                                  clk,
    input wire                                  rst,
    // Allocate stage
    input wire                                  mshr_alloc_en_s1_q,
    input wire [$clog2(N)-1:0]                  mshr_entry_idx_alloc_s1_q,
    input wire [OPCODE_WIDTH-1:0]               mshr_opcode_s1_q [0:N-1],
    // Per-entry atomic-active vec + ALU op vec
    input wire [N-1:0]                          mshr_atomic_active_vec_sx1_q,
    input wire [N*ATOMIC_OPCODE_WIDTH-1:0]      mshr_atomic_op_vec_sx1_q,
    // Atomic lifecycle indicators
    input wire [N-1:0]                          mshr_atomic_busy_sx_q,
    input wire [N-1:0]                          mshr_atomic_operand_pulse_s1_q,
    input wire [N-1:0]                          mshr_atomic_operand_arr_s1_q,
    input wire [N-1:0]                          mshr_atomic_memwr_fired_s1_q,
    input wire [N-1:0]                          mshr_atomic_sn_dat_queued_s1_q,
    input wire [N-1:0]                          mshr_dat_old_get_s1_q,
    input wire [N-1:0]                          mshr_atomicld_s1_q,
    input wire [N-1:0]                          mshr_atomicst_s1_q
);

    // ── canonical CHI-E atomic REQ opcodes ───────────────────────────────
    `define ATOMIC_ALLOC_BINS \
        bins AtomicStore_ADD = { 7'h28 }; \
        bins AtomicLoad_ADD  = { 7'h30 }; \
        bins AtomicSwap      = { 7'h38 }

    // ── per-event scratch state ──────────────────────────────────────────
    bit [OPCODE_WIDTH-1:0]               s_op;
    bit [ATOMIC_OPCODE_WIDTH-1:0]        s_alu_op;
    bit [$clog2(N)-1:0]                  s_slot;
    bit                                  s_is_ld;
    bit                                  s_is_st;
    bit                                  s_is_sw;

    // Lifecycle event tag (one per cycle, mutually exclusive)
    typedef enum bit [2:0] {
        EV_ALLOC          = 3'd0,   // atomic_busy 0->1
        EV_OPERAND_PULSE  = 3'd1,   // operand DAT landed
        EV_MEMWR_FIRED    = 3'd2,   // memwr TX REQ won
        EV_SN_DAT_QUEUED  = 3'd3,   // SN-F-bound TX DAT queued
        EV_OLD_LATCHED    = 3'd4,   // dat_old_get 0->1 (SN-F CompData done)
        EV_RETIRE         = 3'd5    // atomic_busy 1->0 (terminal flit out)
    } atomic_event_e;
    atomic_event_e s_event;
    bit            s_event_atomic_kind;  // 0 = ld/sw, 1 = st

    // ── covergroup #1 — allocation × ALU op ──────────────────────────────
    covergroup cg_atomic_alloc;
        option.per_instance = 1;
        cp_op:     coverpoint s_op {
            `ATOMIC_ALLOC_BINS;
            // Non-atomic opcodes don't reach the sample point (gated by
            // op-in-{0x28,0x30,0x38} below), but be explicit:
            bins other = { 7'h00, 7'h01, [7'h02:7'h27],
                           [7'h29:7'h2f], [7'h31:7'h37],
                           [7'h39:7'h7f] };
        }
        cp_alu_op: coverpoint s_alu_op {
            bins ADD  = { 4'h0 };
            bins SWAP = { 4'h8 };
            // CLR/EOR/SET/SMAX/SMIN/UMAX/UMIN/COMPARE — not yet wired
            ignore_bins reserved = { 4'h1, 4'h2, 4'h3, 4'h4,
                                     4'h5, 4'h6, 4'h7, 4'h9,
                                     [4'ha:4'hf] };
        }
        cp_slot:   coverpoint s_slot { bins all[] = { [0:N-1] }; }
        x_op_alu:  cross cp_op, cp_alu_op {
            // ATOMICSTORE_ADD must always pair with ALU ADD.
            // AtomicSwap must always pair with ALU SWAP.
            // AtomicLoad_ADD must always pair with ALU ADD.
            ignore_bins mismatched =
                (binsof(cp_op.AtomicStore_ADD) && binsof(cp_alu_op.SWAP)) ||
                (binsof(cp_op.AtomicLoad_ADD)  && binsof(cp_alu_op.SWAP)) ||
                (binsof(cp_op.AtomicSwap)      && binsof(cp_alu_op.ADD));
        }
        x_op_slot: cross cp_op, cp_slot;
    endgroup
    cg_atomic_alloc cov_alloc = new();

    // ── covergroup #2 — lifecycle events × atomic kind ───────────────────
    covergroup cg_atomic_lifecycle;
        option.per_instance = 1;
        cp_event: coverpoint s_event {
            bins alloc          = { EV_ALLOC };
            bins operand_pulse  = { EV_OPERAND_PULSE };
            bins memwr_fired    = { EV_MEMWR_FIRED };
            bins sn_dat_queued  = { EV_SN_DAT_QUEUED };
            bins old_latched    = { EV_OLD_LATCHED };
            bins retire         = { EV_RETIRE };
        }
        cp_kind: coverpoint s_event_atomic_kind {
            bins ld_or_sw = { 1'b0 };   // CompData-returning atomics
            bins st       = { 1'b1 };   // Comp-only atomics
        }
        x_event_kind: cross cp_event, cp_kind {
            // AtomicStore doesn't produce CompData -> no "old_latched"
            // event tagged as st.  Actually atomicst DOES fire memrd
            // (to fetch OLD for the ADD lane), so it does latch.
            // Keep this cross unrestricted.
        }
    endgroup
    cg_atomic_lifecycle cov_life = new();

    // ── edge detectors for sticky / vec signals ──────────────────────────
    reg [N-1:0] busy_d, dat_old_d, memwr_fired_d, sn_dat_queued_d;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            busy_d           <= '0;
            dat_old_d        <= '0;
            memwr_fired_d    <= '0;
            sn_dat_queued_d  <= '0;
        end else begin
            busy_d           <= mshr_atomic_busy_sx_q;
            dat_old_d        <= mshr_dat_old_get_s1_q;
            memwr_fired_d    <= mshr_atomic_memwr_fired_s1_q;
            sn_dat_queued_d  <= mshr_atomic_sn_dat_queued_s1_q;
        end
    end
    wire [N-1:0] busy_rise         = mshr_atomic_busy_sx_q          & ~busy_d;
    wire [N-1:0] busy_fall         = ~mshr_atomic_busy_sx_q         &  busy_d;
    wire [N-1:0] dat_old_rise      = mshr_dat_old_get_s1_q          & ~dat_old_d;
    wire [N-1:0] memwr_fired_rise  = mshr_atomic_memwr_fired_s1_q   & ~memwr_fired_d;
    wire [N-1:0] sn_dat_queued_rise= mshr_atomic_sn_dat_queued_s1_q & ~sn_dat_queued_d;

    // ── sample ────────────────────────────────────────────────────────────
    always @(posedge clk) begin
        if (!rst) begin
            // allocation event -- only for atomic entries
            if (mshr_alloc_en_s1_q) begin
                automatic int i = mshr_entry_idx_alloc_s1_q;
                automatic logic [OPCODE_WIDTH-1:0] op = mshr_opcode_s1_q[i];
                if (op == 7'h28 || op == 7'h30 || op == 7'h38) begin
                    s_op     = op;
                    s_alu_op = mshr_atomic_op_vec_sx1_q[i*ATOMIC_OPCODE_WIDTH +: ATOMIC_OPCODE_WIDTH];
                    s_slot   = mshr_entry_idx_alloc_s1_q;
                    cov_alloc.sample();
                end
            end
            // per-entry lifecycle events
            for (int i = 0; i < N; i++) begin
                s_event_atomic_kind = mshr_atomicst_s1_q[i];
                if (busy_rise[i] &
                    (mshr_atomicld_s1_q[i] | mshr_atomicst_s1_q[i])) begin
                    s_event = EV_ALLOC;
                    cov_life.sample();
                end
                if (mshr_atomic_operand_pulse_s1_q[i]) begin
                    s_event = EV_OPERAND_PULSE;
                    cov_life.sample();
                end
                if (memwr_fired_rise[i]) begin
                    s_event = EV_MEMWR_FIRED;
                    cov_life.sample();
                end
                if (sn_dat_queued_rise[i]) begin
                    s_event = EV_SN_DAT_QUEUED;
                    cov_life.sample();
                end
                if (dat_old_rise[i] &
                    (mshr_atomicld_s1_q[i] | mshr_atomicst_s1_q[i])) begin
                    s_event = EV_OLD_LATCHED;
                    cov_life.sample();
                end
                if (busy_fall[i] &
                    // sample only when an atomic was indeed active prior
                    (busy_d[i])) begin
                    s_event = EV_RETIRE;
                    cov_life.sample();
                end
            end
        end
    end

    `undef ATOMIC_ALLOC_BINS

endmodule

`endif /* ATOMIC_COVERAGE_V */
