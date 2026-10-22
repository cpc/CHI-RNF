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
// coherence_coverage.sv
//
// Tier-1 functional coverage for the HN-F *coherence* state machine
// — the per-RN-F snoop-filter state of the line a transaction is
// touching. Bound to hnf_cache_pipeline; samples once per request at
// pipeline stage SX4, where pipe_sf_match_state_sx4_q + pipe_tag_match_sx4_q
// + pipe_opcode_sx_q[SX4] + pipe_rnf_idx_sx_q[SX4] are all valid.
//
// What we cover
// ─────────────
//   cp_abstract_state  — per-line coherence state derived from SF bits.
//                        bins: I, U_A, U_B, U_other, S_A, S_B, S_AB,
//                              S_multi, ILLEGAL
//   cp_l3_hit          — 0/1, did the L3 directory hit
//   cp_op              — incoming REQ opcode (chie_defines tracked set)
//   cp_initiator       — requester RN-F SrcID
//   x_state_op         — state × opcode  (key coverage cross)
//   x_state_initiator  — state × initiator
//   x_l3_state         — L3 hit/miss × abstract state
//
// SF encoding per RN-F (hnf_defines.v:85-87): I=2'b00, U=2'b01, S=2'b11.
// 2'b10 is illegal — HNF $fatal-s on it under DISPLAY_FATAL. Coverage
// includes an ILLEGAL bin so we notice if hitting the illegal state
// somehow.

module coherence_coverage #(
    parameter int RNF_NUM      = 4,
    parameter int OPCODE_WIDTH = 7,
    parameter int NID_WIDTH    = 7,
    // hnf_cache_pipeline.v: localparam CPL_STAGE = SX7 = 6 (SX1=0..SX6=5,
    // SX7=6, so the array is declared [CPL_STAGE-1:0] = [5:0] = 6 entries).
    parameter int CPL_STAGE    = 6,
    parameter int SX4_INDEX    = 3        // 0-indexed: SX1=0..SX6=5
) (
    input wire                          clk,
    input wire                          rst,

    input wire [CPL_STAGE-1:0]          pipe_req_valid_sx_q,
    input wire [RNF_NUM*2-1:0]          pipe_sf_match_state_sx4_q,
    input wire                          pipe_tag_match_sx4_q,
    input wire [OPCODE_WIDTH-1:0]       pipe_opcode_sx_q [CPL_STAGE-1:0],
    input wire [NID_WIDTH-1:0]          pipe_rnf_idx_sx_q [CPL_STAGE-1:0]
);

    // ── abstract state derivation ────────────────────────────────────────
    // Structural binning by (n_unique, n_shared) — slot-agnostic so it
    // doesn't depend on the HNF's RNF_NID_LIST mapping (which maps test
    // NIDs to non-trivial SF slot indices). Bins are populated by how
    // *many* RN-Fs hold the line in each state, not by which slot.
    //
    //   I                 — no RN-F holds the line
    //   UC_1              — exactly one RN-F unique (could be UC or UD)
    //   UC_multi          — ≥2 RN-Fs report U  (protocol violation)
    //   SC_1              — exactly one RN-F shared
    //   SC_2              — exactly two RN-Fs shared (the dual-sharer case)
    //   SC_multi          — ≥3 RN-Fs shared
    //   MIXED             — at least one U and at least one S (illegal mix)
    //   ILLEGAL           — any RN-F encoded as 2'b10
    typedef enum bit [3:0] {
        ST_I         = 4'd0,
        ST_UC_1      = 4'd1,
        ST_UC_MULTI  = 4'd2,
        ST_SC_1      = 4'd3,
        ST_SC_2      = 4'd4,
        ST_SC_MULTI  = 4'd5,
        ST_MIXED     = 4'd6,
        ST_ILLEGAL   = 4'd7
    } abstract_state_e;

    function automatic abstract_state_e classify_state(
        input [RNF_NUM*2-1:0] sf);
        int n_u, n_s;
        bit [1:0] s;
        bit any_illegal;
        n_u = 0; n_s = 0; any_illegal = 1'b0;
        for (int i = 0; i < RNF_NUM; i++) begin
            s = sf[i*2 +: 2];
            case (s)
                2'b00: ;
                2'b01: n_u++;
                2'b11: n_s++;
                default: any_illegal = 1'b1;
            endcase
        end
        if (any_illegal)              return ST_ILLEGAL;
        if (n_u > 0 && n_s > 0)       return ST_MIXED;
        if (n_u == 0 && n_s == 0)     return ST_I;
        if (n_u == 1 && n_s == 0)     return ST_UC_1;
        if (n_u >= 2 && n_s == 0)     return ST_UC_MULTI;
        if (n_u == 0 && n_s == 1)     return ST_SC_1;
        if (n_u == 0 && n_s == 2)     return ST_SC_2;
        return ST_SC_MULTI;   // n_s ≥ 3
    endfunction

    // ── scratch sampling variables ───────────────────────────────────────
    abstract_state_e             s_state;
    bit                          s_l3_hit;
    bit [OPCODE_WIDTH-1:0]       s_op;
    bit [NID_WIDTH-1:0]          s_init;

    // ── covergroup ───────────────────────────────────────────────────────
    `define COHERENCE_OPCODE_BINS \
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

    covergroup cg_coherence;
        option.per_instance = 1;

        cp_abstract_state: coverpoint s_state {
            bins I        = { ST_I       };
            bins UC_1     = { ST_UC_1    };   // any single RN-F holds U
            bins SC_2     = { ST_SC_2    };   // dual-sharer (cross-RN-F case)
            // Unreachable in this HNF: the SF encodes a single holder as U
            // regardless of the RN-F's local SC/UC view. SF "S" only appears
            // when ≥2 RN-Fs actually hold the line concurrently.
            ignore_bins   SC_1     = { ST_SC_1     };
            // 2-RN-F TB: ≥3 sharers impossible
            ignore_bins   SC_multi = { ST_SC_MULTI };
            // Protocol violations — should never occur:
            illegal_bins  UC_multi   = { ST_UC_MULTI };
            illegal_bins  MIXED      = { ST_MIXED    };
            illegal_bins  illegal_sf = { ST_ILLEGAL  };
        }
        cp_l3_hit:     coverpoint s_l3_hit  { bins miss = { 1'b0 };
                                              bins hit  = { 1'b1 }; }
        cp_op:         coverpoint s_op      {
            `COHERENCE_OPCODE_BINS;
            // Opcodes excluded from the test pipeline OR that bypass the
            // cache pipeline entirely (no SX4 sample possible).
            ignore_bins denied = {
                7'h03,  // ReadOnce                        — denied
                7'h26,  // ReadNotSharedDirty              — denied
                7'h1c,  // WriteNoSnpPtl                   — denied
                7'h15,  // WriteEvictFull                  — denied
                7'h1a,  // WriteBackPtl                    — denied
                7'h0d,  // Evict                           — denied
                7'h19,  // WriteUniqueFull                 — denied
                7'h18,  // WriteUniquePtl                  — denied
                7'h04,  // ReadNoSnp        — BYPASS, no SX4 sample
                7'h1b,  // WriteBackFull    — BYPASS, no SX4 sample
                7'h17,  // WriteCleanFull   — BYPASS, no SX4 sample
                7'h1d   // WriteNoSnpFull   — BYPASS, no SX4 sample
                // NOTE: AtomicStore_ADD (0x28), AtomicLoad_ADD (0x30),
                // AtomicSwap (0x38) DO reach SX4 now that atomics engage
                // the L3+SF pipeline for CHI-E coherence -- removed from
                // the denied list 2026-06-16.
            };
        }
        cp_initiator:  coverpoint s_init    {
            bins rnf0 = { 0 };
            bins rnf1 = { 1 };
            // 2-RN-F TB; higher NIDs unreachable
            ignore_bins unused = { [2:$] };
        }

        x_state_op:        cross cp_abstract_state, cp_op;
        x_state_initiator: cross cp_abstract_state, cp_initiator;
        x_l3_state:        cross cp_l3_hit,         cp_abstract_state {
            // <hit, UC_1> is structurally unreachable: UC_1 in the SF is
            // only entered via ReadUnique / MakeUnique, neither of which
            // is in pipe_insert_slc_fill_sx4 (hnf_cache_pipeline.v:1307).
            // L3 therefore never holds a line concurrently with SF=UC_1.
            ignore_bins unreachable_hit_UC =
                binsof(cp_l3_hit.hit) && binsof(cp_abstract_state.UC_1);
        }
    endgroup
    cg_coherence cov_coh = new();

    // ── sample once per cycle when a request is valid at SX4 ─────────────
    always @(posedge clk) begin
        if (!rst && pipe_req_valid_sx_q[SX4_INDEX]) begin
            s_state  = classify_state(pipe_sf_match_state_sx4_q);
            s_l3_hit = pipe_tag_match_sx4_q;
            s_op     = pipe_opcode_sx_q[SX4_INDEX];
            s_init   = pipe_rnf_idx_sx_q[SX4_INDEX];
            cov_coh.sample();
        end
    end

    `undef COHERENCE_OPCODE_BINS

endmodule
