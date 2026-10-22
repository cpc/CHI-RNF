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
// replay_vector.h
//
// Step-2 of the HN-F test-case generator: parses a vector .txt file
// emitted by gen_sequences.py and replays it across two chi_tlm_rnf
// instances (RNF0 = "A", RNF1 = "B").
//
// Granularity: the FSM is flit-level but the existing chi_tlm_rnf
// helpers are transaction-level (REQ + Comp + CompAck collapsed into
// one do_* call). The replayer therefore dispatches one full
// transaction per REQ_<X>_<op> edge and skips COMPACK/SNP_RESP/
// SNF_DATA/INT_* edges — they are emitted/consumed implicitly by the
// existing flit-level RX/TX paths in chi_tlm_rnf.
//
// Cross-RN-F coordination uses a tiny command queue (globals below):
// the orchestrator (RNF0) walks the vector; for own-RNF steps it
// dispatches locally, for peer-RNF steps it enqueues a command and
// waits for the peer worker to complete. RNF1 runs replay_worker()
// which polls the queue.

#pragma once

#include <string>
#include <vector>
#include <cstdint>

class chi_tlm_rnf;  // forward decl

namespace testgen {

struct ReplayStep {
    std::string kind;        // "DRIVE" / "OBSRV" / "OTHER"
    std::string event;       // e.g. "REQ_A_ReadClean"
    std::string action;
    std::string from_state;
    std::string to_state;
};

// Parse a vector file emitted by gen_sequences.py.
// Returns the list of steps in file order. Throws/exits on malformed input.
std::vector<ReplayStep> parse_vector_file(const std::string& path);

// Dispatch a single operation (no leading "REQ_X_" prefix — just the opname)
// onto the given RN-F. Returns true if the op was recognized and executed.
bool dispatch_op(chi_tlm_rnf* rnf, const std::string& opname, uint64_t addr);

// Orchestrator: walks the vector, dispatches own-RNF steps locally,
// hands peer-RNF steps to the worker via the global command queue.
// Call from RNF0's thread. `self` must be RNF0.
void replay_orchestrate(chi_tlm_rnf* self,
                        const std::string& vector_path,
                        uint64_t addr);

// Worker: polls the global command queue, executes peer-targeted ops.
// Call from RNF1's thread. Exits when g_replay_finished is set.
void replay_worker(chi_tlm_rnf* self);

// ── Cross-RN-F command queue ──────────────────────────────────────────────
// All access is from SystemC thread context (cooperative scheduling under
// SC_THREAD on the same clock edge); plain volatile bools suffice — same
// pattern as the existing g_rnf0_at_il* barriers.
extern volatile bool        g_replay_cmd_pending;
extern volatile int         g_replay_cmd_target_rnf;  // 0 or 1
extern volatile uint64_t    g_replay_cmd_addr;
extern std::string          g_replay_cmd_opname;      // touched under !pending
extern volatile bool        g_replay_cmd_done;
extern volatile bool        g_replay_finished;        // orchestrator → worker: exit

// ── Per-line data shadow (data-integrity checking) ───────────────────────
// Single global map shared by orchestrator + worker. SC threads are
// cooperatively scheduled and a single dispatch_op() invocation is
// atomic from a thread's perspective, so concurrent access is safe
// for the data values testgen vectors actually exercise (no concurrent
// writes to the same line — cross-burst gen filters bypass + write ops).
//
// Reset between vectors happens implicitly: every vsim invocation gets
// a fresh process, so the static map starts empty for each test.
extern int g_data_checks_passed;
extern int g_data_mismatches;

// Deterministic data pattern for a line. Same (addr, seq) always
// yields the same 64 bytes — used both for write generation and for
// read verification.
void generate_pattern(uint64_t line_addr, int seq, uint8_t out[64]);

} // namespace testgen
