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
// mshr_coverage.sv
//
// Tier-1 functional-coverage observer for the HN-F MSHR. Same non-
// invasive pattern as mshr_observer.sv: bound to every hnf_mshr_ctl
// instance via mshr_coverage_bind.sv; samples covergroups on
// allocation events and transient-state entries. No edits to any
// HNF RTL, no edits to chi_monitor / chi_icn_beh / tlm_rnf_hnf_tb.
//
// Coverage points
// ───────────────
//   cg_alloc (sampled on mshr_alloc_en_s1_q rising edge):
//     cp_slot       — every MSHR slot (0..N-1) allocated at least once
//     cp_op         — every tracked CHI REQ opcode allocated at least once
//     cp_src        — every RN-F SrcID seen as allocator
//     cp_compack    — both ExpCompAck values (0 and 1)
//     x_slot_op     — slot × opcode cross (alloc spreads ops across slots)
//     x_op_src      — opcode × srcid cross (both RN-Fs use each op)
//     x_op_compack  — opcode × ExpCompAck cross
//
//   cg_transient (sampled on rising edge of snprsp/snpdat/datwait per slot):
//     cp_phase      — three transient phases reached
//     cp_op_for_phase — the opcode of the slot when the transient entered
//     x_phase_op    — phase × opcode cross
//
// The default parameter values (N=32, OPCODE_WIDTH=7, ...) match the
// current HNF build (hnf_param.v / chie_defines.v). The bind directive
// can override if those change.

module mshr_coverage #(
    parameter int N             = 32,
    parameter int OPCODE_WIDTH  = 7,
    parameter int SRCID_WIDTH   = 7,
    parameter int TXNID_WIDTH   = 12,
    parameter int ADDR_WIDTH    = 44
) (
    input wire                          clk,
    input wire                          rst,

    input wire                          mshr_alloc_en_s1_q,
    input wire [$clog2(N)-1:0]          mshr_entry_idx_alloc_s1_q,

    input wire [OPCODE_WIDTH-1:0]       mshr_opcode_s1_q [0:N-1],
    input wire [SRCID_WIDTH-1:0]        mshr_srcid_s1_q  [0:N-1],
    input wire [TXNID_WIDTH-1:0]        mshr_txnid_s1_q  [0:N-1],
    input wire [ADDR_WIDTH-1:0]         mshr_addr_s1_q   [0:N-1],

    input wire [N-1:0]                  mshr_compack_s1_q,
    input wire [N-1:0]                  mshr_snprsp_entry_vec_s1_q,
    input wire [N-1:0]                  mshr_snpdat_entry_vec_s1_q,
    input wire [N-1:0]                  mshr_dat_entry_vec_s1_q
);

    // ── canonical CHI-E REQ opcode values (chie_defines.v) ───────────────
    // Tracked-by-MSHR set per hnf_mshr_ctl.v's mshr_<op>_s1_q flags +
    // bypass-class ops that re-enter the MSHR on CAM hazard.
    `define OPCODE_BINS \
        bins ReadClean          = { 7'h02 }; \
        bins ReadOnce           = { 7'h03 }; \
        bins ReadNoSnp          = { 7'h04 }; \
        bins ReadUnique         = { 7'h07 }; \
        bins CleanShared        = { 7'h08 }; \
        bins CleanInvalid       = { 7'h09 }; \
        bins CleanUnique        = { 7'h0b }; \
        bins MakeUnique         = { 7'h0c }; \
        bins Evict              = { 7'h0d }; \
        bins WriteEvictFull     = { 7'h15 }; \
        bins WriteCleanFull     = { 7'h17 }; \
        bins WriteUniquePtl     = { 7'h18 }; \
        bins WriteUniqueFull    = { 7'h19 }; \
        bins WriteBackPtl       = { 7'h1a }; \
        bins WriteBackFull      = { 7'h1b }; \
        bins WriteNoSnpPtl      = { 7'h1c }; \
        bins WriteNoSnpFull     = { 7'h1d }; \
        bins ReadNotSharedDirty = { 7'h26 }; \
        bins AtomicStore_ADD    = { 7'h28 }; \
        bins AtomicLoad_ADD     = { 7'h30 }; \
        bins AtomicSwap         = { 7'h38 }; \
        bins other              = default

    // ── per-event scratch values (sampled into covergroups) ──────────────
    bit [OPCODE_WIDTH-1:0] s_op;
    bit [SRCID_WIDTH-1:0]  s_src;
    bit                    s_compack;
    bit [$clog2(N)-1:0]    s_slot;

    // Transient phase encoding (single covergroup, three triggers)
    typedef enum bit [1:0] {
        PH_SNPRSP  = 2'd0,    // waiting for SnpResp from a peer RN-F
        PH_SNPDAT  = 2'd1,    // waiting for SnpRespData
        PH_DATWAIT = 2'd2     // waiting for write / fill data
    } phase_e;
    phase_e t_phase;

    // ── covergroup #1 — allocation ───────────────────────────────────────
    covergroup cg_alloc;
        option.per_instance = 1;
        cp_slot:    coverpoint s_slot    { bins all_slots[] = { [0:N-1] }; }
        cp_op:      coverpoint s_op      {
            `OPCODE_BINS;
            // Denied + BYPASS-class ops that never allocate the regular
            // MSHR (they take hnf_mshr_bypass.v fast paths instead).
            ignore_bins denied = {
                7'h03,  // ReadOnce                        — denied
                7'h26,  // ReadNotSharedDirty              — denied
                7'h1c,  // WriteNoSnpPtl                   — denied
                7'h15,  // WriteEvictFull                  — denied
                7'h1a,  // WriteBackPtl                    — denied
                7'h0d,  // Evict                           — denied
                7'h19,  // WriteUniqueFull                 — denied
                7'h18,  // WriteUniquePtl                  — denied
                7'h1b,  // WriteBackFull   — BYPASS, no MSHR alloc
                7'h17   // WriteCleanFull  — BYPASS, no MSHR alloc
            };
        }
        cp_src:     coverpoint s_src     {
            bins rnf0 = { 0 };
            bins rnf1 = { 1 };
            ignore_bins unused = { [2:$] };
        }
        cp_compack: coverpoint s_compack { bins no  = { 1'b0 };
                                           bins yes = { 1'b1 }; }
        x_slot_op:    cross cp_slot, cp_op;
        x_op_src:     cross cp_op,   cp_src;
        x_op_compack: cross cp_op,   cp_compack;
    endgroup
    cg_alloc cov_alloc = new();

    // ── covergroup #2 — transient phases ─────────────────────────────────
    covergroup cg_transient;
        option.per_instance = 1;
        cp_phase:        coverpoint t_phase {
                             bins snprsp   = { PH_SNPRSP };
                             bins snpdat   = { PH_SNPDAT };
                             bins datwait  = { PH_DATWAIT }; }
        cp_op_for_phase: coverpoint s_op   { `OPCODE_BINS; }
        x_phase_op:      cross cp_phase, cp_op_for_phase;
    endgroup
    cg_transient cov_transient = new();

    // ── edge-detection for transient vectors ─────────────────────────────
    reg [N-1:0] snprsp_d, snpdat_d, datwait_d;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            snprsp_d  <= '0;
            snpdat_d  <= '0;
            datwait_d <= '0;
        end else begin
            snprsp_d  <= mshr_snprsp_entry_vec_s1_q;
            snpdat_d  <= mshr_snpdat_entry_vec_s1_q;
            datwait_d <= mshr_dat_entry_vec_s1_q;
        end
    end
    wire [N-1:0] snprsp_rise  = mshr_snprsp_entry_vec_s1_q  & ~snprsp_d;
    wire [N-1:0] snpdat_rise  = mshr_snpdat_entry_vec_s1_q  & ~snpdat_d;
    wire [N-1:0] datwait_rise = mshr_dat_entry_vec_s1_q     & ~datwait_d;

    // ── sample covergroups ───────────────────────────────────────────────
    always @(posedge clk) begin
        if (!rst) begin
            // allocation event
            if (mshr_alloc_en_s1_q) begin
                automatic int i = mshr_entry_idx_alloc_s1_q;
                s_slot    = mshr_entry_idx_alloc_s1_q;
                s_op      = mshr_opcode_s1_q[i];
                s_src     = mshr_srcid_s1_q[i];
                s_compack = mshr_compack_s1_q[i];
                cov_alloc.sample();
            end
            // transient phase entries (rising edge of per-slot bitmap)
            for (int i = 0; i < N; i++) begin
                if (snprsp_rise[i]) begin
                    s_op   = mshr_opcode_s1_q[i];
                    t_phase = PH_SNPRSP;
                    cov_transient.sample();
                end
                if (snpdat_rise[i]) begin
                    s_op   = mshr_opcode_s1_q[i];
                    t_phase = PH_SNPDAT;
                    cov_transient.sample();
                end
                if (datwait_rise[i]) begin
                    s_op   = mshr_opcode_s1_q[i];
                    t_phase = PH_DATWAIT;
                    cov_transient.sample();
                end
            end
        end
    end

    `undef OPCODE_BINS

endmodule
