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
// replay_vector.cpp — see replay_vector.h for design notes.

#include "replay_vector.h"
#include "../cosim/chi_tlm_rnf.h"

#include <cstdio>
#include <cstring>
#include <fstream>
#include <sstream>
#include <map>
#include <array>

namespace testgen {

// ── command-queue globals ────────────────────────────────────────────────
volatile bool     g_replay_cmd_pending    = false;
volatile int      g_replay_cmd_target_rnf = -1;
volatile uint64_t g_replay_cmd_addr       = 0;
std::string       g_replay_cmd_opname;
volatile bool     g_replay_cmd_done       = false;
volatile bool     g_replay_finished       = false;

// ── data-shadow state ────────────────────────────────────────────────────
// Per-line {data, seq, valid} keyed by line address (addr & ~63).
// `seq` bumps on every write so successive WriteUniqueFull/WriteNoSnpFull
// on the same line produce distinct patterns (catches "stuck-old-value"
// bugs and DBID-reuse data corruption).
struct ShadowLine {
    std::array<uint8_t, 64> data{};
    int  seq   = 0;
    bool valid = false;        // true after first write to this line
};
static std::map<uint64_t, ShadowLine> g_shadow;
int g_data_checks_passed = 0;
int g_data_mismatches    = 0;

void generate_pattern(uint64_t line_addr, int seq, uint8_t out[64]) {
    // Address-derived deterministic pattern. (addr >> 4) gives line index,
    // mixed with byte index and per-line write sequence. Distinct (addr,
    // seq) → distinct full 64B payload.
    uint32_t base = (uint32_t)(line_addr >> 4);
    for (int i = 0; i < 64; i++) {
        out[i] = (uint8_t)(base + i * 0x91u + (uint32_t)seq * 0x37u);
    }
}

// ── tiny string helpers ──────────────────────────────────────────────────
static std::string trim(const std::string& s) {
    size_t b = s.find_first_not_of(" \t\r\n");
    size_t e = s.find_last_not_of(" \t\r\n");
    return (b == std::string::npos) ? "" : s.substr(b, e - b + 1);
}

static std::vector<std::string> split_bar(const std::string& s) {
    std::vector<std::string> out;
    std::string cur;
    std::istringstream iss(s);
    while (std::getline(iss, cur, '|')) out.push_back(trim(cur));
    return out;
}

// ── parser ───────────────────────────────────────────────────────────────
// Each data line has the form:
//   <step> | <kind> | <event> | <action> | <from> -> <to>
// Comment lines start with '#'. Blank lines are ignored.
std::vector<ReplayStep> parse_vector_file(const std::string& path) {
    std::vector<ReplayStep> steps;
    std::ifstream f(path);
    if (!f) {
        fprintf(stderr, "[REPLAY] cannot open vector: %s\n", path.c_str());
        return steps;
    }
    std::string line;
    while (std::getline(f, line)) {
        std::string t = trim(line);
        if (t.empty() || t[0] == '#') continue;
        auto cols = split_bar(t);
        if (cols.size() < 5) continue;
        // cols[0]=step, cols[1]=kind, cols[2]=event, cols[3]=action, cols[4]="from -> to"
        ReplayStep s;
        s.kind   = cols[1];
        s.event  = cols[2];
        s.action = cols[3];
        const std::string& arrow = cols[4];
        size_t arrow_pos = arrow.find("->");
        if (arrow_pos != std::string::npos) {
            s.from_state = trim(arrow.substr(0, arrow_pos));
            s.to_state   = trim(arrow.substr(arrow_pos + 2));
        }
        steps.push_back(s);
    }
    return steps;
}

// ── dispatch table ───────────────────────────────────────────────────────
//
// Data-integrity checking:
//   - Write ops generate an address-derived deterministic pattern and
//     update the line's shadow entry.
//   - Read ops capture the returned 64 bytes and compare against the
//     shadow. Only checked if the shadow is `valid` (i.e. someone wrote
//     this line earlier in this vector). Mismatches bump g_data_mismatches
//     and print a diagnostic.
//   - Dataless ops (Clean*, Make*, Evict) don't touch the shadow.
//   - WriteBackFull's data comes from the RN-F's local cache, which holds
//     whatever was last read/written — i.e. the current shadow value.
//     No shadow update needed.
bool dispatch_op(chi_tlm_rnf* rnf, const std::string& op, uint64_t addr) {
    const uint64_t line = addr & ~(uint64_t)63ULL;
    uint8_t rbuf[64];
    uint8_t wbuf[64];

    // ── reads with verification ─────────────────────────────────────────
    auto verify_read = [&](const char* op_name) {
        auto it = g_shadow.find(line);
        if (it == g_shadow.end() || !it->second.valid) return;  // never written
        if (memcmp(rbuf, it->second.data.data(), 64) != 0) {
            g_data_mismatches++;
            // Print first differing byte for diagnostic
            int i = 0;
            while (i < 64 && rbuf[i] == it->second.data[i]) i++;
            printf("[REPLAY] DATA_MISMATCH addr=0x%016lx op=%s rnf=%d "
                   "byte[%d] got=0x%02x exp=0x%02x (seq=%d)\n",
                   (unsigned long)line, op_name, rnf->rnf_nid,
                   i, rbuf[i], it->second.data[i], it->second.seq);
        } else {
            g_data_checks_passed++;
        }
    };

    if      (op == "ReadClean")          { rnf->do_read(addr, rbuf);                  verify_read("ReadClean");        }
    else if (op == "ReadUnique")         { rnf->do_read_unique(addr, rbuf);           verify_read("ReadUnique");       }
    else if (op == "ReadNotSharedDirty") { rnf->do_read_not_shared_dirty(addr, rbuf); verify_read("ReadNotSharedDirty");}
    else if (op == "ReadOnce")           { rnf->do_read_once(addr, rbuf);             verify_read("ReadOnce");         }
    else if (op == "ReadNoSnp")          { rnf->do_read_no_snp(addr, rbuf);           verify_read("ReadNoSnp");        }

    // ── writes that update the shadow ───────────────────────────────────
    else if (op == "WriteUniqueFull") {
        auto& s = g_shadow[line];
        s.seq++;
        generate_pattern(line, s.seq, wbuf);
        rnf->do_write(addr, wbuf);
        memcpy(s.data.data(), wbuf, 64);
        s.valid = true;
    }
    else if (op == "WriteNoSnpFull") {
        auto& s = g_shadow[line];
        s.seq++;
        generate_pattern(line, s.seq, wbuf);
        rnf->do_write_no_snp_full(addr, wbuf);
        memcpy(s.data.data(), wbuf, 64);
        s.valid = true;
    }

    // ── writes from local cache (data is whatever was last on this line) ─
    else if (op == "WriteBackFull")      { rnf->do_write_back_full(addr); }

    // ── dataless ops ────────────────────────────────────────────────────
    else if (op == "MakeUnique")         { rnf->do_make_unique(addr); }
    else if (op == "CleanUnique")        { rnf->do_clean_unique(addr); }
    else if (op == "CleanInvalid")       { rnf->do_clean_invalid(addr); }
    else if (op == "CleanShared")        { rnf->do_clean_shared(addr); }
    else if (op == "Evict")              { rnf->do_evict(addr); }

    // ── atomics ─────────────────────────────────────────────────────────
    // The Murphi model abstracts atomics as op_AtomicLoad / op_AtomicStore
    // (any atomic-op variant collapses to one of these two protocol shapes).
    // The replay drives the *_ADD variant for AtomicLoad/Store and the
    // dedicated AtomicSwap helper.  Choose a fixed lane-0 operand because
    // the Murphi event has no payload; the data-integrity oracle ignores
    // atomic side-effects on the shadow (a non-trivial extension; today
    // we record only the post-swap value).
    else if (op == "AtomicLoad") {
        // Murphi abstracts {AtomicLoad_*, AtomicSwap, AtomicCompare} as a
        // single "op_AtomicLoad" rule.  To cover both ALU paths we alternate
        // ADD and SWAP based on a static counter; AtomicSwap exercises the
        // `ATOMIC_OP_SWAP` ALU case + the dedicated TLM helper.
        static int s_atomic_load_seq = 0;
        const bool use_swap = (s_atomic_load_seq++ & 1) != 0;
        if (use_swap) {
            uint64_t old_val = 0;
            const uint64_t swap_val = 0xDEADBEEFCAFEBABEull;
            rnf->do_atomic_swap(addr, swap_val, &old_val);
            auto it = g_shadow.find(line);
            if (it != g_shadow.end() && it->second.valid) {
                memcpy(it->second.data.data(), &swap_val, 8);
                it->second.seq++;
            }
        } else {
            uint64_t old_val = 0;
            rnf->do_atomic_load_add(addr, /*operand*/ 0x11ull, &old_val);
            // Mutates lane 0 of the line.  Update shadow to reflect new
            // value (= old + operand) if we have a baseline.
            auto it = g_shadow.find(line);
            if (it != g_shadow.end() && it->second.valid) {
                uint64_t cur = 0;
                memcpy(&cur, it->second.data.data(), 8);
                uint64_t newv = cur + 0x11ull;
                memcpy(it->second.data.data(), &newv, 8);
                it->second.seq++;
            }
        }
    }
    else if (op == "AtomicStore") {
        rnf->do_atomic_store_add(addr, /*operand*/ 0x22ull);
        auto it = g_shadow.find(line);
        if (it != g_shadow.end() && it->second.valid) {
            uint64_t cur = 0;
            memcpy(&cur, it->second.data.data(), 8);
            uint64_t newv = cur + 0x22ull;
            memcpy(it->second.data.data(), &newv, 8);
            it->second.seq++;
        }
    }
    else if (op == "AtomicSwap") {
        uint64_t old_val = 0;
        uint64_t swap_val = 0xDEADBEEFCAFEBABEull;
        rnf->do_atomic_swap(addr, swap_val, &old_val);
        auto it = g_shadow.find(line);
        if (it != g_shadow.end() && it->second.valid) {
            memcpy(it->second.data.data(), &swap_val, 8);
            it->second.seq++;
        }
    }

    else {
        printf("[REPLAY] dispatch_op: unsupported op '%s'\n", op.c_str());
        return false;
    }
    return true;
}

// ── parse an FSM event string ────────────────────────────────────────────
// REQ_<X>_<op> → returns (rnf_id=0/1, opname)
// Anything else returns (-1, "")
static bool parse_req_event(const std::string& ev, int& rnf_id, std::string& opname) {
    if (ev.size() < 7 || ev.substr(0, 4) != "REQ_") return false;
    char letter = ev[4];
    if (letter != 'A' && letter != 'B') return false;
    if (ev[5] != '_') return false;
    rnf_id = letter - 'A';
    opname = ev.substr(6);
    return true;
}

// ── orchestrator ─────────────────────────────────────────────────────────
// Step kinds (cols[1] in the vector file):
//   DRIVE — synchronous: dispatch the REQ and block on completion before
//           moving to the next step. Default for BFS/burst vectors.
//   FORK  — fire-and-forget: enqueue the peer-targeted REQ (set the
//           command queue) WITHOUT waiting for done. Used to launch
//           cross-RN-F concurrent issues — the orchestrator continues
//           to the next step (typically a DRIVE on the local RN-F),
//           so both REQs hit the HNF in adjacent cycles. FORK on the
//           local RN-F is not supported (do_*() always blocks); the
//           generator should place self-targeted ops on DRIVE lines.
//   JOIN  — barrier: wait for any outstanding FORKed peer command to
//           drain (g_replay_cmd_done set by the worker).
void replay_orchestrate(chi_tlm_rnf* self,
                        const std::string& vector_path,
                        uint64_t addr) {
    auto steps = parse_vector_file(vector_path);
    printf("[%s] REPLAY begin: %s  (%zu steps, addr=0x%lx)\n",
           self->label, vector_path.c_str(),
           steps.size(), (unsigned long)addr);

    int step_idx = 0;
    for (auto& s : steps) {
        ++step_idx;

        // ── JOIN: drain any outstanding fire-and-forget peer command ────
        if (s.kind == "JOIN") {
            if (g_replay_cmd_pending) {
                int timeout = 200000;
                while (!g_replay_cmd_done && timeout-- > 0) self->tick();
                if (timeout <= 0) {
                    printf("[%s] REPLAY JOIN TIMEOUT (peer cmd never completed)\n",
                           self->label);
                    break;
                }
                g_replay_cmd_pending = false;
                printf("[%s] REPLAY step %d JOIN  (peer drained)\n",
                       self->label, step_idx);
            } else {
                printf("[%s] REPLAY step %d JOIN  (no pending)\n",
                       self->label, step_idx);
            }
            continue;
        }

        // Skip non-driving / non-fork lines (OBSRV, IMPLICIT, etc.)
        if (s.kind != "DRIVE" && s.kind != "FORK") {
            printf("[%s] REPLAY step %d skip non-DRIVE (%s)\n",
                   self->label, step_idx, s.event.c_str());
            continue;
        }

        int rnf_id = -1;
        std::string opname;
        if (!parse_req_event(s.event, rnf_id, opname)) {
            printf("[%s] REPLAY step %d implicit (%s)\n",
                   self->label, step_idx, s.event.c_str());
            continue;
        }

        printf("[%s] REPLAY step %d  %s rnf=%d  op=%s  (state %s -> %s)\n",
               self->label, step_idx, s.kind.c_str(),
               rnf_id, opname.c_str(),
               s.from_state.c_str(), s.to_state.c_str());

        if (rnf_id == self->rnf_nid) {
            // own step — always blocking via do_*() helpers
            if (s.kind == "FORK") {
                printf("[%s] REPLAY note: FORK on self degenerates to DRIVE\n",
                       self->label);
            }
            dispatch_op(self, opname, addr);
        } else {
            // peer step — enqueue. FORK doesn't wait; DRIVE does.
            g_replay_cmd_opname     = opname;
            g_replay_cmd_addr       = addr;
            g_replay_cmd_target_rnf = rnf_id;
            g_replay_cmd_done       = false;
            g_replay_cmd_pending    = true;
            if (s.kind == "FORK") {
                continue;        // continue to next step immediately
            }
            int timeout = 200000;
            while (!g_replay_cmd_done && timeout-- > 0) self->tick();
            if (timeout <= 0) {
                printf("[%s] REPLAY TIMEOUT waiting for peer rnf=%d op=%s\n",
                       self->label, rnf_id, opname.c_str());
                break;
            }
            g_replay_cmd_pending = false;
        }
    }

    // Drain any straggler (in case the vector ended on a FORK without JOIN)
    if (g_replay_cmd_pending) {
        int timeout = 200000;
        while (!g_replay_cmd_done && timeout-- > 0) self->tick();
        g_replay_cmd_pending = false;
    }

    // ── data-integrity summary ──────────────────────────────────────────
    // Emitted in a runner-grep-friendly format. PASS iff zero mismatches
    // (zero checks is also PASS — vector did no data-bearing ops).
    if (g_data_mismatches == 0) {
        printf("[REPLAY] DATA_CHECK_RESULT: PASS (%d checks)\n",
               g_data_checks_passed);
    } else {
        printf("[REPLAY] DATA_CHECK_RESULT: FAIL (%d mismatches, %d passed)\n",
               g_data_mismatches, g_data_checks_passed);
    }

    printf("[%s] REPLAY end\n", self->label);
    g_replay_finished = true;
}

// ── worker ───────────────────────────────────────────────────────────────
void replay_worker(chi_tlm_rnf* self) {
    printf("[%s] REPLAY worker ready\n", self->label);
    while (!g_replay_finished) {
        if (g_replay_cmd_pending && g_replay_cmd_target_rnf == self->rnf_nid && !g_replay_cmd_done) {
            std::string op   = g_replay_cmd_opname;
            uint64_t    addr = g_replay_cmd_addr;
            printf("[%s] REPLAY worker exec  op=%s  addr=0x%lx\n",
                   self->label, op.c_str(), (unsigned long)addr);
            dispatch_op(self, op, addr);
            g_replay_cmd_done = true;
        }
        self->tick();
    }
    printf("[%s] REPLAY worker exit\n", self->label);
}

} // namespace testgen
