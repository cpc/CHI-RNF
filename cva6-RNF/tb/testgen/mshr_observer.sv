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
// mshr_observer.sv
//
// Step-3 of the HN-F test-case generator: a non-invasive observer that
// taps the HN-F MSHR state and emits machine-readable trace lines for
// the test-gen oracle. Designed to be attached via SV `bind` so neither
// chi_monitor.sv nor any HNF RTL is modified.
//
// Trace format (one line per event, parseable):
//   [MSHR_OBS] t=<ns> ALLOC  slot=<n> op=0x<hex> src=<n> txn=<hex> addr=<hex> compack=<0|1>
//   [MSHR_OBS] t=<ns> SNPRSP slot=<n>                          # entered transient: waiting for SnpResp
//   [MSHR_OBS] t=<ns> SNPDAT slot=<n>                          # waiting for SnpRespData
//   [MSHR_OBS] t=<ns> DATWAT slot=<n>                          # waiting for DAT (write/read fill)
//   [MSHR_OBS] t=<ns> RETIRE slot=<n>
//
// The transient-state lines fire on the rising edge of the corresponding
// per-slot vector bit, so each slot emits at most one line per phase.
//
// Hook-up (in tlm_rnf_hnf_tb.sv top, NOT in chi_monitor):
//
//     bind hnf_mshr_ctl mshr_observer #(.N(32)) u_obs (
//         .clk                          (clk),
//         .rst                          (rst),
//         .mshr_alloc_en_s1_q           (mshr_alloc_en_s1_q),
//         .mshr_entry_idx_alloc_s1_q    (mshr_entry_idx_alloc_s1_q),
//         .mshr_dbf_retired_valid_sx1_q (mshr_dbf_retired_valid_sx1_q),
//         .mshr_dbf_retired_idx_sx1_q   (mshr_dbf_retired_idx_sx1_q),
//         .mshr_opcode_s1_q             (mshr_opcode_s1_q),
//         .mshr_srcid_s1_q              (mshr_srcid_s1_q),
//         .mshr_txnid_s1_q              (mshr_txnid_s1_q),
//         .mshr_addr_s1_q               (mshr_addr_s1_q),
//         .mshr_compack_s1_q            (mshr_compack_s1_q),
//         .mshr_snprsp_entry_vec_s1_q   (mshr_snprsp_entry_vec_s1_q),
//         .mshr_snpdat_entry_vec_s1_q   (mshr_snpdat_entry_vec_s1_q),
//         .mshr_dat_entry_vec_s1_q      (mshr_dat_entry_vec_s1_q)
//     );

module mshr_observer #(
    // Defaults match the HNF's hnf_param.v / chie_defines.v values for the
    // current build (CHIE_REQ_ADDR_WIDTH_PARAM=44, CHIE_NID_WIDTH_PARAM=7,
    // HNF_MSHR_ENTRIES_NUM_PARAM=32). The bind directive may override.
    parameter int N             = 32,                 // MSHR entries
    parameter int OPCODE_WIDTH  = 7,
    parameter int SRCID_WIDTH   = 7,
    parameter int TXNID_WIDTH   = 12,
    parameter int ADDR_WIDTH    = 44,

    // Watchdog: if a slot stays allocated this long, print a STUCK line
    // *with* the issue timestamp (the thing chi_monitor's DEADLOCK output
    // omits). Default 50 µs is loose enough to never false-trigger on
    // healthy transactions in this TB. Set to 0 to disable.
    parameter time WATCHDOG_THRESHOLD_NS = 50000,
    parameter time WATCHDOG_REPEAT_NS    =  5000
) (
    input wire                          clk,
    input wire                          rst,

    // allocation
    input wire                          mshr_alloc_en_s1_q,
    input wire [$clog2(N)-1:0]          mshr_entry_idx_alloc_s1_q,

    // retirement (1-cycle pulse + slot index)
    input wire                          mshr_dbf_retired_valid_sx1_q,
    input wire [$clog2(N)-1:0]          mshr_dbf_retired_idx_sx1_q,

    // per-slot scalars (unpacked arrays — match RTL declaration)
    input wire [OPCODE_WIDTH-1:0]       mshr_opcode_s1_q [0:N-1],
    input wire [SRCID_WIDTH-1:0]        mshr_srcid_s1_q  [0:N-1],
    input wire [TXNID_WIDTH-1:0]        mshr_txnid_s1_q  [0:N-1],
    input wire [ADDR_WIDTH-1:0]         mshr_addr_s1_q   [0:N-1],

    // per-slot transient-state bits (packed bitmaps)
    input wire [N-1:0]                  mshr_compack_s1_q,
    input wire [N-1:0]                  mshr_snprsp_entry_vec_s1_q,
    input wire [N-1:0]                  mshr_snpdat_entry_vec_s1_q,
    input wire [N-1:0]                  mshr_dat_entry_vec_s1_q
);

    // ── per-slot issue-timestamp scoreboard ─────────────────────────────────
    // Recorded on ALLOC, cleared on RETIRE. The watchdog process below uses
    // this to print the *issue* time on a stuck slot, instead of just an Age
    // — which is what the user asked for: "I want it printed".
    time slot_alloc_time      [N];
    bit  slot_alloc_valid     [N];
    time slot_last_warn_time  [N];   // throttle repeat prints

    // ── edge-detection for transient-state vectors ──────────────────────────
    reg [N-1:0] snprsp_d, snpdat_d, datwait_d;

    integer i;
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

    // ── trace emission ──────────────────────────────────────────────────────
    always @(posedge clk) begin
        if (!rst) begin
            // alloc — sampled on the cycle the per-slot scalars are valid
            if (mshr_alloc_en_s1_q) begin
                automatic int s = mshr_entry_idx_alloc_s1_q;
                slot_alloc_time[s]     <= $time;
                slot_alloc_valid[s]    <= 1'b1;
                slot_last_warn_time[s] <= 0;
                $display("[MSHR_OBS] t=%0t ALLOC  slot=%0d op=0x%02h src=%0d txn=0x%03h addr=0x%016h compack=%0d",
                         $time, s,
                         mshr_opcode_s1_q[s],
                         mshr_srcid_s1_q[s],
                         mshr_txnid_s1_q[s],
                         mshr_addr_s1_q[s],
                         mshr_compack_s1_q[s]);
            end

            // transient-state enters
            for (i = 0; i < N; i = i + 1) begin
                if (snprsp_rise[i])
                    $display("[MSHR_OBS] t=%0t SNPRSP slot=%0d", $time, i);
                if (snpdat_rise[i])
                    $display("[MSHR_OBS] t=%0t SNPDAT slot=%0d", $time, i);
                if (datwait_rise[i])
                    $display("[MSHR_OBS] t=%0t DATWAT slot=%0d", $time, i);
            end

            // retire
            if (mshr_dbf_retired_valid_sx1_q) begin
                automatic int s = mshr_dbf_retired_idx_sx1_q;
                slot_alloc_valid[s] <= 1'b0;
                $display("[MSHR_OBS] t=%0t RETIRE slot=%0d",
                         $time, s);
            end
        end
    end

    // ── stuck-transaction watchdog ──────────────────────────────────────────
    // Periodically scans all slots. For each slot that's been allocated
    // longer than WATCHDOG_THRESHOLD_NS, prints a STUCK line containing
    // the *issue timestamp* (slot_alloc_time) plus the slot's full
    // context. Throttled by WATCHDOG_REPEAT_NS so one stuck slot doesn't
    // flood the log.
    initial begin : watchdog
        if (WATCHDOG_THRESHOLD_NS == 0) begin
            // disabled
            ;
        end else begin
            // poll every WATCHDOG_REPEAT_NS
            forever begin
                #(WATCHDOG_REPEAT_NS * 1ns);
                for (int s = 0; s < N; s++) begin
                    if (slot_alloc_valid[s]) begin
                        automatic time age = $time - slot_alloc_time[s];
                        if (age >= WATCHDOG_THRESHOLD_NS * 1ns) begin
                            // throttle: only re-print every WATCHDOG_REPEAT_NS
                            if (($time - slot_last_warn_time[s]) >=
                                 WATCHDOG_REPEAT_NS * 1ns ||
                                slot_last_warn_time[s] == 0) begin
                                $display("[MSHR_OBS] t=%0t STUCK  slot=%0d ISSUED_AT=%0t op=0x%02h src=%0d txn=0x%03h addr=0x%016h age=%0t",
                                         $time, s,
                                         slot_alloc_time[s],
                                         mshr_opcode_s1_q[s],
                                         mshr_srcid_s1_q[s],
                                         mshr_txnid_s1_q[s],
                                         mshr_addr_s1_q[s],
                                         age);
                                slot_last_warn_time[s] <= $time;
                            end
                        end
                    end
                end
            end
        end
    end

endmodule
