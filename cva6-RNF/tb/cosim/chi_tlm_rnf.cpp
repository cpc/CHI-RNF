/*
 * Copyright (c) 2026 Customized Parallel Computing (CPC) Group Tampere University
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
 *
 * Author: Abdesattar Kalache <abdesattar.kalache@tuni.fi>
 *
 * chi_tlm_rnf.cpp — CHI-E TLM RN-F packet injector implementation.
 *
 * Packet-injector model with CHI cache state tracking.  Maintains a
 * CACHE_SETS×CACHE_WAYS set-associative tag array.  State transitions:
 *   WriteUniqueFull -> I (write-and-evict)
 *   ReadClean       -> SC
 *   CleanUnique     -> UC
 *   SnpClean on SC/UC -> SC (downgrade, no dirty data)
 *   SnpMakeInvalid  -> I
 *
 * Two instances are created (one per RNF NID), differentiated by a static
 * elaboration counter.  RNF0 (nid=0) writes data then notifies RNF1 via
 * g_rnf0_write_done so that RNF1's coherency read exercises the snoop path.
 */

#include "chi_tlm_rnf.h"
#include <systemc/mti_integration.h>
#include <cstdio>
#include <cstring>
#include <cstdlib>
#include <cassert>
#ifdef RNF_REPLAY_DEMO
#include "../testgen/replay_vector.h"
#endif

// Global SC event used to synchronise RNF0->RNF1 test sequencing
sc_event g_rnf0_write_done;

// Interleaved-test polling barriers (see chi_tlm_rnf.h for usage pattern).
volatile bool g_rnf1_phases_done = false;
volatile bool g_rnf0_at_il1 = false, g_rnf1_at_il1 = false;
volatile bool g_rnf0_at_il2 = false, g_rnf1_at_il2 = false;
volatile bool g_rnf0_at_il3 = false, g_rnf1_at_il3 = false;
volatile bool g_rnf0_at_il4 = false, g_rnf1_at_il4 = false;
volatile bool g_rnf0_at_il5 = false, g_rnf1_at_il5 = false;
volatile bool g_rnf0_at_il6 = false, g_rnf1_at_il6 = false;
volatile bool g_rnf0_at_il7 = false, g_rnf1_at_il7 = false;
volatile bool g_rnf0_at_il8 = false, g_rnf1_at_il8 = false;
volatile bool g_rnf0_at_il9 = false, g_rnf1_at_il9 = false;
volatile bool g_rnf0_at_il10 = false, g_rnf1_at_il10 = false;
volatile bool g_rnf0_at_il11 = false, g_rnf1_at_il11 = false;
volatile bool g_rnf0_at_il12 = false, g_rnf1_at_il12 = false;
volatile bool g_rnf0_at_il13 = false, g_rnf1_at_il13 = false;
volatile bool g_rnf0_at_il14 = false, g_rnf1_at_il14 = false;
volatile bool g_rnf0_at_il15 = false, g_rnf1_at_il15 = false;
volatile bool g_rnf0_at_il16 = false, g_rnf1_at_il16 = false;
volatile bool g_rnf0_at_il17 = false, g_rnf1_at_il17 = false;
volatile bool g_rnf0_at_il18 = false, g_rnf1_at_il18 = false;
volatile bool g_rnf0_at_il19 = false, g_rnf1_at_il19 = false;
volatile bool g_rnf0_at_il20 = false, g_rnf1_at_il20 = false;

// Set true by chi_set_rnf_verbose() — a DPI-C function called from SV when
// +rnf_verbose is detected via $test$plusargs.  (sc_main's argc/argv do not
// carry vsim plusargs in Questa SV+SC co-simulation mode.)
bool g_rnf_verbose = false;

extern "C" void chi_set_rnf_verbose() { g_rnf_verbose = true; }

// ─── Opcode name helpers (always-on flit trace) ───────────────────────────────
static const char* snp_opc_name(int opc) {
    switch (opc) {
    case 0x00: return "SnpLCrdReturn";
    case 0x01: return "SnpShared";
    case 0x02: return "SnpClean";
    case 0x03: return "SnpOnce";
    case 0x04: return "SnpNotSharedDirty";
    case 0x05: return "SnpUniqueStash";
    case 0x06: return "SnpMakeInvalidStash";
    case 0x07: return "SnpUnique";
    case 0x08: return "SnpCleanShared";
    case 0x09: return "SnpCleanInvalid";
    case 0x0a: return "SnpMakeInvalid";
    case 0x0b: return "SnpStashUnique";
    case 0x0c: return "SnpStashShared";
    case 0x0d: return "SnpDVMOp";
    case 0x10: return "SnpQuery";
    case 0x11: return "SnpSharedFwd";
    case 0x12: return "SnpCleanFwd";
    case 0x13: return "SnpOnceFwd";
    case 0x14: return "SnpNotSharedDirtyFwd";
    case 0x15: return "SnpPreferUnique";
    case 0x16: return "SnpPreferUniqueFwd";
    case 0x17: return "SnpUniqueFwd";
    default:   return "SnpUnk";
    }
}
static const char* req_opc_name(int opc) {
    switch (opc) {
    case 0x00: return "ReqLCrdReturn";
    case 0x01: return "ReadShared";
    case 0x02: return "ReadClean";
    case 0x03: return "ReadOnce";
    case 0x04: return "ReadNoSnp";
    case 0x05: return "PCrdReturn";
    case 0x07: return "ReadUnique";
    case 0x08: return "CleanShared";
    case 0x09: return "CleanInvalid";
    case 0x0a: return "MakeInvalid";
    case 0x0b: return "CleanUnique";
    case 0x0c: return "MakeUnique";
    case 0x0d: return "Evict";
    case 0x11: return "ReadNoSnpSep";
    case 0x13: return "CleanSharedPersistSep";
    case 0x14: return "DVMOp";
    case 0x15: return "WriteEvictFull";
    case 0x17: return "WriteCleanFull";
    case 0x18: return "WriteUniquePtl";
    case 0x19: return "WriteUniqueFull";
    case 0x1a: return "WriteBackPtl";
    case 0x1b: return "WriteBackFull";
    case 0x1c: return "WriteNoSnpPtl";
    case 0x1d: return "WriteNoSnpFull";
    case 0x20: return "WriteUniqueFullStash";
    case 0x21: return "WriteUniquePtlStash";
    case 0x22: return "StashOnceShared";
    case 0x23: return "StashOnceUnique";
    case 0x24: return "ReadOnceCleanInvalid";
    case 0x25: return "ReadOnceMakeInvalid";
    case 0x26: return "ReadNotSharedDirty";
    case 0x27: return "CleanSharedPersist";
    case 0x28: return "AtomicStore_ADD";
    case 0x29: return "AtomicStore_CLR";
    case 0x2a: return "AtomicStore_EOR";
    case 0x2b: return "AtomicStore_SET";
    case 0x2c: return "AtomicStore_SMAX";
    case 0x2d: return "AtomicStore_SMIN";
    case 0x2e: return "AtomicStore_UMAX";
    case 0x2f: return "AtomicStore_UMIN";
    case 0x30: return "AtomicLoad_ADD";
    case 0x31: return "AtomicLoad_CLR";
    case 0x32: return "AtomicLoad_EOR";
    case 0x33: return "AtomicLoad_SET";
    case 0x34: return "AtomicLoad_SMAX";
    case 0x35: return "AtomicLoad_SMIN";
    case 0x36: return "AtomicLoad_UMAX";
    case 0x37: return "AtomicLoad_UMIN";
    case 0x38: return "AtomicSwap";
    case 0x39: return "AtomicCompare";
    case 0x41: return "MakeReadUnique";
    case 0x42: return "WriteEvictOrEvict";
    case 0x43: return "WriteUniqueZero";
    case 0x44: return "WriteNoSnpZero";
    case 0x47: return "StashOnceSepShared";
    case 0x48: return "StashOnceSepUnique";
    case 0x4c: return "ReadPreferUnique";
    case 0x50: return "WriteNoSnpFullCleanSh";
    case 0x51: return "WriteNoSnpFullCleanInv";
    case 0x52: return "WriteNoSnpFullCleanShPerSep";
    case 0x54: return "WriteUniqueFullCleanSh";
    case 0x56: return "WriteUniqueFullCleanShPerSep";
    case 0x58: return "WriteBackFullCleanSh";
    case 0x59: return "WriteBackFullCleanInv";
    case 0x5a: return "WriteBackFullCleanShPerSep";
    case 0x5c: return "WriteCleanFullCleanSh";
    case 0x5e: return "WriteCleanFullCleanShPerSep";
    case 0x60: return "WriteNoSnpPtlCleanSh";
    case 0x61: return "WriteNoSnpPtlCleanInv";
    case 0x62: return "WriteNoSnpPtlCleanShPerSep";
    case 0x64: return "WriteUniquePtlCleanSh";
    case 0x66: return "WriteUniquePtlCleanShPerSep";
    default:   return "REQUnk";
    }
}
static const char* rsp_opc_name(int opc) {
    switch (opc) {
    case 0x00: return "RspLCrdReturn";
    case 0x01: return "SnpResp";
    case 0x02: return "CompAck";
    case 0x03: return "RetryAck";
    case 0x04: return "Comp";
    case 0x05: return "CompDBIDResp";
    case 0x06: return "DBIDResp";
    case 0x07: return "PCrdGrant";
    case 0x08: return "ReadReceipt";
    case 0x09: return "SnpRespFwded";
    case 0x0c: return "Persist";
    case 0x0d: return "CompPersist";
    case 0x0e: return "DBIDRespOrd";
    case 0x10: return "StashDone";
    case 0x11: return "CompStashDone";
    case 0x14: return "CompCMO";
    default:   return "RSPUnk";
    }
}
static const char* dat_opc_name(int opc) {
    switch (opc) {
    case 0x0: return "DatLCrdReturn";
    case 0x1: return "SnpRespData";
    case 0x2: return "CopyBackWrData";
    case 0x3: return "NonCopyBackWrData";
    case 0x4: return "CompData";
    case 0x5: return "SnpRespDataPtl";
    case 0x6: return "SnpRespDataFwded";
    case 0x7: return "WriteDataCancel";
    case 0xb: return "DataSepResp";
    case 0xc: return "NCBWrDataCompAck";
    default:  return "DATUnk";
    }
}

// ─── Bit-field helpers ────────────────────────────────────────────────────────
// Set bits [hi:lo] of an sc_bv<W> to val (max 64-bit value).
template<int W>
static void fset(sc_bv<W>& f, int hi, int lo, uint64_t val) {
    for (int i = lo; i <= hi; i++)
        f[i] = (int)((val >> (i - lo)) & 1u);
}

// Extract bits [hi:lo] of an sc_bv<W> as a uint64_t.
template<int W>
static uint64_t fget(const sc_bv<W>& f, int hi, int lo) {
    uint64_t r = 0;
    for (int i = lo; i <= hi; i++)
        if (f[i].to_bool()) r |= 1ULL << (i - lo);
    return r;
}

// ─── Constructor ──────────────────────────────────────────────────────────────
chi_tlm_rnf::chi_tlm_rnf(::sc_core::sc_module_name nm) : sc_module(nm) {
    SC_HAS_PROCESS(chi_tlm_rnf);
    if (g_rnf_verbose) { printf("[chi_tlm_rnf] constructor called nm=%s\n", (const char*)nm); fflush(stdout); }

    // Assign NID from elaboration order (first instance=0, second=1)
    static int s_count = 0;
    rnf_nid = s_count++;
    // HNF_NID default 2 for chi_icn_beh; override via -DHNF_NID_DEFAULT
    // (mesh: 16, encoded {X=1,Y=0,P=0}) or env HNF_NID at runtime.
#ifndef HNF_NID_DEFAULT
#define HNF_NID_DEFAULT 2
#endif
    { const char* env = getenv("HNF_NID");
      hnf_nid = env ? atoi(env) : HNF_NID_DEFAULT; }

    static char s_labels[2][8];
    snprintf(s_labels[rnf_nid], sizeof(s_labels[0]), "RNF%d", rnf_nid);
    label = s_labels[rnf_nid];

    m_req_crd = 0; m_rsp_crd = 0; m_dat_crd = 0;
    m_next_txnid = 0;
    m_snp_head = 0; m_snp_tail = 0;
    m_rx_rsp_grants = 0; m_rx_dat_grants = 0; m_rx_snp_grants = 0;
    m_lru_tick = 0;
    memset(m_pend,  0, sizeof(m_pend));
    memset(m_snp_q, 0, sizeof(m_snp_q));
    memset(m_cache, 0, sizeof(m_cache));

    SC_THREAD(run);
    sensitive << clk.pos();
}

// ─── tick ─────────────────────────────────────────────────────────────────────
// Advance n clock cycles.  At each edge: collect credits/flits, send pending
// RSPs, drive RX credit return signals.
void chi_tlm_rnf::tick(int n) {
    for (int i = 0; i < n; i++) {
        wait();           // posedge clk
        process_rx();
        drain_pending_rsp();
        drive_rx_credits();
    }
}

// ─── process_rx ───────────────────────────────────────────────────────────────
void chi_tlm_rnf::process_rx() {
    // Accumulate TX credits granted by ICN
    if (txreq_lcrdv.read()) m_req_crd++;
    if (txrsp_lcrdv.read()) m_rsp_crd++;
    if (txdat_lcrdv.read()) m_dat_crd++;

    // ── RXRSP ────────────────────────────────────────────────────────────────
    if (rxrsp_flitv.read()) {
        sc_bv<CHI_RSP_W> f = rxrsp_flit.read();
        int tgt   = (int)fget(f, 10,  4);
        int srcid = (int)fget(f, 17, 11);
        int opc   = (int)fget(f, 34, 30);
        int txnid = (int)fget(f, 29, 18) & 63;
        int dbid  = (int)fget(f, 57, 46);

        if (tgt == rnf_nid) {
            switch (opc) {
            case CHI_OP_COMP:
                printf("[%s] RX RSP  Comp               txnid=%02d  dbid=%02d\n", label, txnid, dbid);
                if (m_pend[txnid].active) {
                    m_pend[txnid].comp_rcvd = true;
                    m_pend[txnid].dbid = dbid;
                }
                break;
            case CHI_OP_COMPDBIDRESP:
                printf("[%s] RX RSP  CompDBIDResp       txnid=%02d  dbid=%02d  src=%02d\n", label, txnid, dbid, srcid);
                if (m_pend[txnid].active) {
                    m_pend[txnid].comp_rcvd  = true;
                    m_pend[txnid].dbid_rcvd  = true;
                    m_pend[txnid].dbid       = dbid;
                    m_pend[txnid].dat_tgt    = srcid;
                }
                break;
            case CHI_OP_DBIDRESP:
                printf("[%s] RX RSP  DBIDResp           txnid=%02d  dbid=%02d  src=%02d\n", label, txnid, dbid, srcid);
                if (m_pend[txnid].active) {
                    m_pend[txnid].dbid_rcvd = true;
                    m_pend[txnid].dbid      = dbid;
                    m_pend[txnid].dat_tgt   = srcid;
                }
                break;
            case CHI_OP_RETRYACK:
                printf("[%s] RX RSP  RetryAck           txnid=%02d\n", label, txnid);
                if (m_pend[txnid].active) {
                    m_pend[txnid].retry_rcvd = true;
                    m_pend[txnid].pcrdtype   = (int)fget(f, 61, 58);
                }
                break;
            case CHI_OP_PCRDGRANT:
                printf("[%s] RX RSP  PCrdGrant          txnid=%02d\n", label, txnid);
                break;
            default:
                break;
            }
        }
        m_rx_rsp_grants++;  // return one credit to ICN
    }

    // ── RXDAT ────────────────────────────────────────────────────────────────
    if (rxdat_flitv.read()) {
        sc_bv<CHI_DAT_W> f = rxdat_flit.read();
        int tgt    = (int)fget(f, 10,  4);
        int opc    = (int)fget(f, 40, 37);
        int txnid  = (int)fget(f, 29, 18) & 63;
        int dataid = (int)fget(f, 68, 67);
        int hnid   = (int)fget(f, 36, 30);
        int dbid   = (int)fget(f, 64, 53);

        if (tgt == rnf_nid && opc == CHI_OP_COMPDATA && m_pend[txnid].active) {
            // Beat index = DataID / DATAID_STEP.  128b beats use IDs
            // {0,1,2,3}; 256b beats use {0,2}; 512b uses {0}.  Each beat
            // covers CHI_DATA_BEAT_BYTES bytes at offset beat*bytes.
            int beat   = dataid / DATAID_STEP;
            int base_b = beat * CHI_DATA_BEAT_BYTES;
            if (beat < 0 || beat >= BEATS_PER_LINE) {
                printf("[%s] RX DAT  bad DataID=%d for %d-beat/line mode\n",
                       label, dataid, BEATS_PER_LINE);
            } else {
                m_pend[txnid].dat_rcvd[beat] = true;
                m_pend[txnid].homenid        = hnid;
                m_pend[txnid].dbid           = dbid;

                // Copy beat payload from DATA field.  Positions
                // (DAT_DATA_LSB..MSB) shift with CHI_DATA_BEAT_BITS.
                for (int b = 0; b < CHI_DATA_BEAT_BYTES; b++) {
                    m_pend[txnid].data[base_b + b] =
                        (uint8_t)fget(f, DAT_DATA_LSB + b*8 + 7,
                                         DAT_DATA_LSB + b*8);
                }

                printf("[%s] RX DAT  CompData           txnid=%02d  dataid=%d  beat=%d/%d  data[0]=0x%02x\n",
                       label, txnid, dataid, beat + 1, BEATS_PER_LINE,
                       m_pend[txnid].data[base_b]);

                // Full line arrives when every beat slot has fired.
                bool full = true;
                for (int i = 0; i < BEATS_PER_LINE; i++)
                    if (!m_pend[txnid].dat_rcvd[i]) { full = false; break; }
                if (full) {
                    m_pend[txnid].comp_rcvd = true;
                    if (m_pend[txnid].needs_compack) {
                        m_pend[txnid].compack_needed = true;
                        m_pend[txnid].compack_tgtid  = hnid;
                        m_pend[txnid].compack_dbid   = dbid;
                    }
                }
            }
        }
        m_rx_dat_grants++;
    }

    // ── RXSNP ────────────────────────────────────────────────────────────────
    if (rxsnp_flitv.read()) {
        handle_snoop(rxsnp_flit.read());
        m_rx_snp_grants++;
    }
}

// ─── drain_pending_rsp ────────────────────────────────────────────────────────
// Send at most one TX RSP per cycle.  Priority: CompAck > SnpResp.
void chi_tlm_rnf::drain_pending_rsp() {
    if (m_rsp_crd <= 0) {
        txrsp_flitv.write(false);
        return;
    }

    // CompAcks
    for (int i = 0; i < 64; i++) {
        if (m_pend[i].compack_needed) {
            m_rsp_crd--;
            txrsp_flitv.write(true);
            txrsp_flitpend.write(false);
            txrsp_flit.write(mk_rsp(CHI_OP_COMPACK,
                                    m_pend[i].compack_tgtid,
                                    m_pend[i].compack_dbid));
            printf("[%s] TX RSP  CompAck            tgtid=%d  dbid=%02d\n",
                   label, m_pend[i].compack_tgtid, m_pend[i].compack_dbid);
            m_pend[i].compack_needed = false;
            return;
        }
    }

    // SnpResps
    if (m_snp_head != m_snp_tail) {
        auto& e = m_snp_q[m_snp_head & 15];
        m_rsp_crd--;
        txrsp_flitv.write(true);
        txrsp_flitpend.write(false);
        txrsp_flit.write(mk_rsp(CHI_OP_SNPRESP, e.tgtid, e.txnid, e.resp));
        printf("[%s] TX RSP  SnpResp(%s)        tgtid=%d  txnid=%02d\n",
               label, chi_state_str((ChiState)e.resp), e.tgtid, e.txnid);
        e.valid = false;
        m_snp_head++;
        return;
    }

    txrsp_flitv.write(false);
}

// ─── drive_rx_credits ─────────────────────────────────────────────────────────
// Pulse rxXxx_lcrdv for one cycle per pending credit grant.
void chi_tlm_rnf::drive_rx_credits() {
    rxrsp_lcrdv.write(m_rx_rsp_grants > 0);
    if (m_rx_rsp_grants > 0) m_rx_rsp_grants--;

    rxdat_lcrdv.write(m_rx_dat_grants > 0);
    if (m_rx_dat_grants > 0) m_rx_dat_grants--;

    rxsnp_lcrdv.write(m_rx_snp_grants > 0);
    if (m_rx_snp_grants > 0) m_rx_snp_grants--;
}

// ─── Cache helpers ─────────────────────────────────────────────────────────────
static inline int  cache_set_idx(uint64_t addr) {
    return (int)((addr >> CACHE_BLOCK_BITS) & (CACHE_SETS - 1));
}
static inline uint64_t cache_tag_val(uint64_t addr) {
    return addr >> (CACHE_BLOCK_BITS + CACHE_SET_BITS);
}

int chi_tlm_rnf::cache_find(uint64_t addr) {
    int set = cache_set_idx(addr);
    uint64_t tag = cache_tag_val(addr);
    for (int w = 0; w < CACHE_WAYS; w++)
        if (m_cache[set][w].valid && m_cache[set][w].tag == tag)
            return w;
    return -1;
}

int chi_tlm_rnf::cache_alloc(uint64_t addr) {
    int set = cache_set_idx(addr);
    uint64_t tag = cache_tag_val(addr);
    for (int w = 0; w < CACHE_WAYS; w++) {
        if (!m_cache[set][w].valid) {
            m_cache[set][w].valid = true;
            m_cache[set][w].tag   = tag;
            m_cache[set][w].state = ChiState::I;
            m_cache[set][w].lru_tick = 0;
            return w;
        }
    }
    // LRU eviction
    int lru_way = 0;
    for (int w = 1; w < CACHE_WAYS; w++)
        if (m_cache[set][w].lru_tick < m_cache[set][lru_way].lru_tick)
            lru_way = w;
    m_cache[set][lru_way].tag   = tag;
    m_cache[set][lru_way].state = ChiState::I;
    return lru_way;
}

ChiState chi_tlm_rnf::cache_state(uint64_t addr) {
    int w = cache_find(addr);
    return (w >= 0) ? m_cache[cache_set_idx(addr)][w].state : ChiState::I;
}

void chi_tlm_rnf::cache_update(uint64_t addr, ChiState new_state) {
    int set = cache_set_idx(addr);
    int w   = cache_find(addr);
    if (new_state == ChiState::I) {
        if (w >= 0) m_cache[set][w].valid = false;
        return;
    }
    if (w < 0) w = cache_alloc(addr);
    m_cache[set][w].state    = new_state;
    m_cache[set][w].lru_tick = m_lru_tick++;
}

// ─── handle_snoop ─────────────────────────────────────────────────────────────
void chi_tlm_rnf::handle_snoop(sc_bv<CHI_SNP_W> f) {
    int srcid = (int)fget(f, 10,  4);
    int txnid = (int)fget(f, 22, 11);
    int opc   = (int)fget(f, 46, 42);
    // SNP addr field [87:47] = addr[43:3]; shift left 3 to get byte address
    uint64_t line_addr = (fget(f, 87, 47) << 3) & ~63ULL;

    ChiState cur  = cache_state(line_addr);
    ChiState next = ChiState::I;
    int resp = CHI_RESP_I;

    switch (opc) {
    // ── Invalidating snoops (target line -> I) ───────────────────────────────
    case CHI_SNP_OP_SNPUNIQUESTASH:
    case CHI_SNP_OP_SNPMAKEINVALIDSTASH:
    case CHI_SNP_OP_SNPUNIQUE:
    case CHI_SNP_OP_SNPCLEANINVALID:
    case CHI_SNP_OP_SNPMAKEINVALID:
    case CHI_SNP_OP_SNPPREFERUNIQUE:
    case CHI_SNP_OP_SNPPREFERUNIQUEFWD:
    case CHI_SNP_OP_SNPUNIQUEFWD:
        next = ChiState::I;
        resp = CHI_RESP_I;
        break;

    // ── Downgrading snoops (UC/UCE/UD/SD -> SC, SC stays SC, I stays I) ──────
    case CHI_SNP_OP_SNPSHARED:
    case CHI_SNP_OP_SNPCLEAN:
    case CHI_SNP_OP_SNPNOTSHAREDDIRTY:
    case CHI_SNP_OP_SNPCLEANSHARED:
    case CHI_SNP_OP_SNPSHAREDFWD:
    case CHI_SNP_OP_SNPCLEANFWD:
    case CHI_SNP_OP_SNPNOTSHAREDDIRTYFWD:
        if (cur != ChiState::I) {
            next = ChiState::SC;
            resp = CHI_RESP_SC;
        }
        break;

    // ── Non-modifying snoops (state unchanged, report current Resp) ─────────
    case CHI_SNP_OP_SNPONCE:
    case CHI_SNP_OP_SNPONCEFWD:
    case CHI_SNP_OP_SNPQUERY:
    case CHI_SNP_OP_SNPDVMOP:
    case CHI_SNP_OP_SNPSTASHUNIQUE:   // stash hint — no state change
    case CHI_SNP_OP_SNPSTASHSHARED:   // stash hint — no state change
        next = cur;
        resp = (cur == ChiState::I)  ? CHI_RESP_I
             : (cur == ChiState::SC) ? CHI_RESP_SC
             :                         CHI_RESP_UC;
        break;

    // ── Unknown / link-credit return (must not reach here) ──────────────────
    default:
        next = ChiState::I;
        resp = CHI_RESP_I;
        break;
    }

    printf("[%s]   Snoop %-12s   0x%016lx  [%-3s -> %-3s]\n",
           label, snp_opc_name(opc), (unsigned long)line_addr,
           chi_state_str(cur), chi_state_str(next));

    cache_update(line_addr, next);
    enqueue_snp_rsp(srcid, txnid, resp);
}

void chi_tlm_rnf::enqueue_snp_rsp(int tgtid, int txnid, int resp) {
    int idx = m_snp_tail & 15;
    m_snp_q[idx].valid = true;
    m_snp_q[idx].tgtid = tgtid;
    m_snp_q[idx].txnid = txnid;
    m_snp_q[idx].resp  = resp;
    m_snp_tail++;
}

// ─── link_activate ────────────────────────────────────────────────────────────
void chi_tlm_rnf::link_activate() {
    // CHI link-activation handshake:
    //   RNF: assert txlinkactivereq
    //   ICN: assert rxlinkactivereq, then waits for rxlinkactiveack && txlinkactivereq
    //   RNF: wait for rxlinkactivereq, assert rxlinkactiveack
    //   ICN: asserts txlinkactiveack (RNF condition satisfied)
    //   RNF: wait for txlinkactiveack -> link up
    txlinkactivereq.write(true);
    while (!rxlinkactivereq.read())  tick();
    rxlinkactiveack.write(true);
    while (!txlinkactiveack.read())  tick();
    tick(2);

    printf("[%s] Link activated\n", label);
}

// ─── grant_initial_rx_credits ─────────────────────────────────────────────────
// Queue 15 credit-grant pulses for each RX channel.  drive_rx_credits() will
// spread them over 15 consecutive clock cycles.
void chi_tlm_rnf::grant_initial_rx_credits() {
    m_rx_rsp_grants += 15;
    m_rx_dat_grants += 15;
    m_rx_snp_grants += 15;
    tick(15);   // let the credit pulses propagate
    printf("[%s] Granted initial RX credits\n", label);
}

// ─── Flit builders ────────────────────────────────────────────────────────────

sc_bv<CHI_REQ_W> chi_tlm_rnf::mk_req(int opc, uint64_t addr, int txnid,
                                       bool exp_compack, int order) {
    sc_bv<CHI_REQ_W> f = 0;
    fset(f, 10,   4, hnf_nid);           // TgtID
    fset(f, 17,  11, rnf_nid);           // SrcID
    fset(f, 29,  18, txnid);             // TxnID
    fset(f, 56,  50, opc);               // Opcode
    fset(f, 59,  57, 6);                 // Size = 6 -> 64 bytes (cache-line)
    fset(f,103,  60, addr);              // Addr
    fset(f,106, 106, 1);                 // AllowRetry
    fset(f,108, 107, order);             // Order
    fset(f,116, 113, 0xCu);              // MemAttr: Cacheable=1, Allocate=1
    if (exp_compack)
        fset(f, 127, 127, 1);            // ExpCompAck
    return f;
}

sc_bv<CHI_RSP_W> chi_tlm_rnf::mk_rsp(int opc, int tgtid, int txnid, int resp) {
    sc_bv<CHI_RSP_W> f = 0;
    fset(f, 10,  4, tgtid);
    fset(f, 17, 11, rnf_nid);
    fset(f, 29, 18, txnid);
    fset(f, 34, 30, opc);
    fset(f, 39, 37, resp);    // Resp: 0=I, 1=SC, 2=UC
    return f;
}

// Build a NonCopyBackWrData / CopyBackWrData DAT flit.
// dptr points to CHI_DATA_BEAT_BYTES bytes of payload — one beat of the
// configured beat width (16, 32, or 64 bytes).  DataID indexes the beat
// within the 64B cacheline (spec §2.3.1: DataID granularity is 128b, so
// dataid = beat * DATAID_STEP).  The wire flit's DATA field [369:114]
// holds up to 256 bits; a 512b beat overruns it and requires widening
// CHI_DAT_W beyond the current fixed 370 bits.
sc_bv<CHI_DAT_W> chi_tlm_rnf::mk_dat(int opc, int tgtid, int txnid,
                                       int dataid, const uint8_t* dptr, uint32_t be, int resp) {
    sc_bv<CHI_DAT_W> f = 0;
    fset(f, 10,  4, tgtid);
    fset(f, 17, 11, rnf_nid);
    fset(f, 29, 18, txnid);
    fset(f, 36, 30, hnf_nid);              // HomeNID
    fset(f, 40, 37, opc);                  // Opcode
    fset(f, 45, 43, resp);                 // Resp (state of line being returned)
    fset(f, 68, 67, dataid);               // DataID
    fset(f, DAT_BE_MSB, DAT_BE_LSB, (uint64_t)be);   // BE
    // DATA field — CHI_DATA_BEAT_BITS wide; entire beat payload
    // populated (bytes beyond CHI_DATA_BEAT_BYTES don't exist in the
    // caller's beat buffer).
    for (int b = 0; b < CHI_DATA_BEAT_BYTES; b++)
        fset(f, DAT_DATA_LSB + b*8 + 7, DAT_DATA_LSB + b*8, dptr[b]);
    return f;
}

// ─── Transaction helpers ──────────────────────────────────────────────────────

// Block until there is at least one TX REQ credit.
static void wait_req_crd(chi_tlm_rnf* m) {
    while (m->m_req_crd == 0) m->tick();
    m->m_req_crd--;
}
static void wait_rsp_crd(chi_tlm_rnf* m) {
    while (m->m_rsp_crd == 0) m->tick();
    m->m_rsp_crd--;
}
static void wait_dat_crd(chi_tlm_rnf* m) {
    while (m->m_dat_crd == 0) m->tick();
    m->m_dat_crd--;
}

// ─── do_write ─────────────────────────────────────────────────────────────────
// WriteUniqueFull: inject REQ -> wait DBIDResp/CompDBIDResp ->
//                  send 2×NonCopyBackWrData -> wait Comp.
void chi_tlm_rnf::do_write(uint64_t addr, const uint8_t* data64) {
    tick(20);   // inter-transaction gap (CompAck propagation, MSHR retire)
    int txnid = (m_next_txnid++) & 63;
    m_pend[txnid] = PendTxn{};
    m_pend[txnid].active = true;

    wait_req_crd(this);
    txreq_flitv.write(true);
    txreq_flitpend.write(false);
    txreq_flit.write(mk_req(CHI_OP_WRITEUNIQUEFULL, addr, txnid, /*exp_compack*/ false));
    tick();
    txreq_flitv.write(false);
    printf("[%s] TX REQ  WriteUniqueFull (0x%02x)    0x%016lx  txnid=%02d\n",
           label, CHI_OP_WRITEUNIQUEFULL, (unsigned long)addr, txnid);

    int timeout = 20000;
    while (!m_pend[txnid].dbid_rcvd && timeout-- > 0) tick();
    if (timeout <= 0) {
        printf("[%s] TIMEOUT: no DBIDResp for WriteUniqueFull addr=0x%lx\n",
               label, (unsigned long)addr);
        sc_stop(); return;
    }

    int dbid = m_pend[txnid].dbid;
    // Send BEATS_PER_LINE 64B-cacheline beats (DataID = i*DATAID_STEP)
    for (int beat = 0; beat < BEATS_PER_LINE; beat++) {
        wait_dat_crd(this);
        txdat_flitv.write(true);
        txdat_flitpend.write(false);
        txdat_flit.write(mk_dat(CHI_OP_NONCOPYBKWRDATA, hnf_nid, dbid,
                                beat * DATAID_STEP,
                                data64 + beat * CHI_DATA_BEAT_BYTES));
        tick();
        txdat_flitv.write(false);
        printf("[%s] TX DAT  NonCopyBkWrData   txnid=%02d  dataid=%d  beat=%d/%d\n",
               label, dbid, beat * DATAID_STEP, beat + 1, BEATS_PER_LINE);
    }

    timeout = 20000;
    while (!m_pend[txnid].comp_rcvd && timeout-- > 0) tick();
    if (timeout <= 0) {
        printf("[%s] TIMEOUT: no Comp for WriteUniqueFull addr=0x%lx\n",
               label, (unsigned long)addr);
        sc_stop(); return;
    }

    ChiState old_ws = cache_state(addr);
    cache_update(addr, ChiState::I);
    m_pend[txnid].active = false;
    printf("[%s]   WriteUniqueFull     0x%016lx  [%-3s -> I  ]\n",
           label, (unsigned long)addr, chi_state_str(old_ws));
}

// ─── do_read ──────────────────────────────────────────────────────────────────
// ReadClean: inject REQ (ExpCompAck=1) -> wait 2×CompData -> CompAck sent
//            automatically by drain_pending_rsp when both halves arrive.
void chi_tlm_rnf::do_read(uint64_t addr, uint8_t* out64) {
    tick(20);   // inter-transaction gap (CompAck propagation, MSHR retire)
    int txnid = (m_next_txnid++) & 63;
    m_pend[txnid] = PendTxn{};
    m_pend[txnid].active        = true;
    m_pend[txnid].needs_compack = true;

    wait_req_crd(this);
    txreq_flitv.write(true);
    txreq_flitpend.write(false);
    txreq_flit.write(mk_req(CHI_OP_READCLEAN, addr, txnid, /*exp_compack=*/true));
    tick();
    txreq_flitv.write(false);
    printf("[%s] TX REQ  ReadClean (0x%02x)          0x%016lx  txnid=%02d\n",
           label, CHI_OP_READCLEAN, (unsigned long)addr, txnid);

    // comp_rcvd is set by process_rx once both CompData halves arrive
    int timeout = 20000;
    while (!m_pend[txnid].comp_rcvd && timeout-- > 0) tick();
    if (timeout <= 0) {
        printf("[%s] TIMEOUT: no CompData for ReadClean addr=0x%lx\n",
               label, (unsigned long)addr);
        sc_stop(); return;
    }

    if (out64) memcpy(out64, m_pend[txnid].data, 64);
    ChiState old_rs = cache_state(addr);
    cache_update(addr, ChiState::SC);
    { // store data in cache line
        int set = cache_set_idx(addr); int way = cache_find(addr);
        if (way >= 0) { memcpy(m_cache[set][way].data, m_pend[txnid].data, 64);
                        m_cache[set][way].data_valid = true; }
    }
    m_pend[txnid].active = false;
    printf("[%s]   ReadClean           0x%016lx  [%-3s -> SC ]  data[0]=0x%02x\n",
           label, (unsigned long)addr, chi_state_str(old_rs), m_pend[txnid].data[0]);
}

// ─── do_read_unique ───────────────────────────────────────────────────────────
// ReadUnique (ExpCompAck=1): read for exclusive ownership.
// HNF snoops other caches with SnpMakeInvalid; CompData returns UC state.
void chi_tlm_rnf::do_read_unique(uint64_t addr, uint8_t* out64) {
    tick(20);   // inter-transaction gap (CompAck propagation, MSHR retire)
    int txnid = (m_next_txnid++) & 63;
    m_pend[txnid] = PendTxn{};
    m_pend[txnid].active        = true;
    m_pend[txnid].needs_compack = true;

    wait_req_crd(this);
    txreq_flitv.write(true);
    txreq_flitpend.write(false);
    txreq_flit.write(mk_req(CHI_OP_READUNIQUE, addr, txnid, /*exp_compack=*/true));
    tick();
    txreq_flitv.write(false);
    printf("[%s] TX REQ  ReadUnique (0x%02x)         0x%016lx  txnid=%02d\n",
           label, CHI_OP_READUNIQUE, (unsigned long)addr, txnid);

    int timeout = 20000;
    while (!m_pend[txnid].comp_rcvd && timeout-- > 0) tick();
    if (timeout <= 0) {
        printf("[%s] TIMEOUT: no CompData for ReadUnique addr=0x%lx\n",
               label, (unsigned long)addr);
        sc_stop(); return;
    }

    if (out64) memcpy(out64, m_pend[txnid].data, 64);
    ChiState old_ru = cache_state(addr);
    cache_update(addr, ChiState::UC);
    { // store data in cache line (needed for subsequent WriteBackFull)
        int set = cache_set_idx(addr); int way = cache_find(addr);
        if (way >= 0) { memcpy(m_cache[set][way].data, m_pend[txnid].data, 64);
                        m_cache[set][way].data_valid = true; }
    }
    m_pend[txnid].active = false;
    printf("[%s]   ReadUnique          0x%016lx  [%-3s -> UC ]  data[0]=0x%02x\n",
           label, (unsigned long)addr, chi_state_str(old_ru), m_pend[txnid].data[0]);
}

// ─── do_write_back_full ───────────────────────────────────────────────────────
// WriteBackFull: write a clean/dirty cached copy back to the home node.
// Requires a valid copy in the local cache (from a prior Read).
// Flow: REQ -> CompDBIDResp -> 2×CopyBackWrData -> (Comp, if not already in CompDBIDResp)
// No CompAck — HNF does not issue ExpCompAck for write-back transactions.
void chi_tlm_rnf::do_write_back_full(uint64_t addr) {
    tick(20);   // inter-transaction gap (CompAck propagation, MSHR retire)
    int set = cache_set_idx(addr);
    int way = cache_find(addr);
    if (way < 0 || !m_cache[set][way].data_valid) {
        printf("[%s] ERROR: WriteBackFull addr=0x%lx — no valid data in cache\n",
               label, (unsigned long)addr);
        sc_stop(); return;
    }
    uint8_t data64[64];
    memcpy(data64, m_cache[set][way].data, 64);

    int txnid = (m_next_txnid++) & 63;
    m_pend[txnid] = PendTxn{};
    m_pend[txnid].active = true;

    wait_req_crd(this);
    txreq_flitv.write(true);
    txreq_flitpend.write(false);
    txreq_flit.write(mk_req(CHI_OP_WRITEBACKFULL, addr, txnid));
    tick();
    txreq_flitv.write(false);
    printf("[%s] TX REQ  WriteBackFull (0x%02x)      0x%016lx  txnid=%02d\n",
           label, CHI_OP_WRITEBACKFULL, (unsigned long)addr, txnid);

    int timeout = 20000;
    while (!m_pend[txnid].dbid_rcvd && timeout-- > 0) tick();
    if (timeout <= 0) {
        printf("[%s] TIMEOUT: no DBIDResp for WriteBackFull addr=0x%lx\n",
               label, (unsigned long)addr);
        sc_stop(); return;
    }

    int dbid = m_pend[txnid].dbid;
    for (int beat = 0; beat < BEATS_PER_LINE; beat++) {
        wait_dat_crd(this);
        txdat_flitv.write(true);
        txdat_flitpend.write(false);
        txdat_flit.write(mk_dat(CHI_OP_COPYBKWRDATA, hnf_nid, dbid,
                                beat * DATAID_STEP,
                                data64 + beat * CHI_DATA_BEAT_BYTES,
                                BE_FULL_BEAT, CHI_RESP_UC));
        tick();
        txdat_flitv.write(false);
        printf("[%s] TX DAT  CopyBkWrData      txnid=%02d  dataid=%d  beat=%d/%d  data[0]=0x%02x\n",
               label, dbid, beat * DATAID_STEP, beat + 1, BEATS_PER_LINE,
               data64[beat * CHI_DATA_BEAT_BYTES]);
    }

    timeout = 20000;
    while (!m_pend[txnid].comp_rcvd && timeout-- > 0) tick();
    if (timeout <= 0) {
        printf("[%s] TIMEOUT: no Comp for WriteBackFull addr=0x%lx\n",
               label, (unsigned long)addr);
        sc_stop(); return;
    }

    ChiState old_wb = cache_state(addr);
    cache_update(addr, ChiState::I);
    m_pend[txnid].active = false;
    printf("[%s]   WriteBackFull       0x%016lx  [%-3s -> I  ]\n",
           label, (unsigned long)addr, chi_state_str(old_wb));
}

// ─── Shared read-completion helper ────────────────────────────────────────────
// Issues a REQ, waits for 2×CompData, optionally queues CompAck, updates state.
// end_state=I means non-allocating (no cache_update, no data stored).
static void do_read_generic(chi_tlm_rnf* m, int opc, uint64_t addr,
                             bool exp_compack, ChiState end_state, uint8_t* out64) {
    int txnid = (m->m_next_txnid++) & 63;
    m->m_pend[txnid] = chi_tlm_rnf::PendTxn{};
    m->m_pend[txnid].active        = true;
    m->m_pend[txnid].needs_compack = exp_compack;

    wait_req_crd(m);
    m->txreq_flitv.write(true); m->txreq_flitpend.write(false);
    m->txreq_flit.write(m->mk_req(opc, addr, txnid, exp_compack));
    m->tick(); m->txreq_flitv.write(false);
    printf("[%s] TX REQ  %s (0x%02x)  0x%016lx  txnid=%02d\n",
           m->label, req_opc_name(opc), opc, (unsigned long)addr, txnid);

    int timeout = 20000;
    while (!m->m_pend[txnid].comp_rcvd && timeout-- > 0) m->tick();
    if (timeout <= 0) {
        printf("[%s] TIMEOUT opc=0x%02x addr=0x%lx\n",
               m->label, opc, (unsigned long)addr);
        sc_stop(); return;
    }

    // drain_pending_rsp may have already sent CompAck in the same tick; only
    // send inline if it hasn't (credit was unavailable that cycle).
    if (m->m_pend[txnid].compack_needed) {
        wait_rsp_crd(m);
        m->txrsp_flitv.write(true); m->txrsp_flitpend.write(false);
        m->txrsp_flit.write(m->mk_rsp(CHI_OP_COMPACK,
                                       m->m_pend[txnid].compack_tgtid,
                                       m->m_pend[txnid].compack_dbid));
        m->tick(); m->txrsp_flitv.write(false);
        printf("[%s] TX RSP  CompAck            tgt=%02d  txnid=%02d\n",
               m->label, m->m_pend[txnid].compack_tgtid, m->m_pend[txnid].compack_dbid);
        m->m_pend[txnid].compack_needed = false;
    }

    if (out64) memcpy(out64, m->m_pend[txnid].data, 64);

    if (end_state != ChiState::I) {
        m->cache_update(addr, end_state);
        int set = cache_set_idx(addr); int way = m->cache_find(addr);
        if (way >= 0) {
            memcpy(m->m_cache[set][way].data, m->m_pend[txnid].data, 64);
            m->m_cache[set][way].data_valid = true;
        }
    }
    m->m_pend[txnid].active = false;
}

// ─── do_read_not_shared_dirty ─────────────────────────────────────────────────
// ReadNotSharedDirty (ExpCompAck=1): read that accepts SC but not UD/SD.
// HNF ensures it returns a clean copy; result state = SC.
void chi_tlm_rnf::do_read_not_shared_dirty(uint64_t addr, uint8_t* out64) {
    tick(20);   // inter-transaction gap (CompAck propagation, MSHR retire)
    ChiState old = cache_state(addr);
    do_read_generic(this, CHI_OP_READNOTSHAREDIRTY, addr,
                    /*exp_compack=*/true, ChiState::SC, out64);
    printf("[%s]   ReadNotSharedDirty  0x%016lx  [%-3s -> SC ]\n",
           label, (unsigned long)addr, chi_state_str(old));
}

// ─── do_read_once ─────────────────────────────────────────────────────────────
// ReadOnce (ExpCompAck=1): non-allocating read — data returned, cache stays I.
void chi_tlm_rnf::do_read_once(uint64_t addr, uint8_t* out64) {
    tick(20);   // inter-transaction gap (CompAck propagation, MSHR retire)
    do_read_generic(this, CHI_OP_READONCE, addr,
                    /*exp_compack=*/true, ChiState::I, out64);
    printf("[%s]   ReadOnce            0x%016lx  [I   -> I  ]  data[0]=0x%02x\n",
           label, (unsigned long)addr, out64 ? out64[0] : 0);
}

// ─── do_read_no_snp ───────────────────────────────────────────────────────────
// ReadNoSnp (ExpCompAck=0): non-coherent read — no snoop filter update, no CompAck.
void chi_tlm_rnf::do_read_no_snp(uint64_t addr, uint8_t* out64, bool expcompack) {
    tick(20);   // inter-transaction gap (CompAck propagation, MSHR retire)
    do_read_generic(this, CHI_OP_READNOSNP, addr,
                    expcompack, ChiState::I, out64);
    printf("[%s]   ReadNoSnp           0x%016lx  [I   -> I  ]  data[0]=0x%02x\n",
           label, (unsigned long)addr, out64 ? out64[0] : 0);
}

// ─── do_write_no_snp_full ─────────────────────────────────────────────────────
// WriteNoSnpFull: non-coherent write — same protocol as WriteUniqueFull,
// but HNF does not update the snoop filter.
void chi_tlm_rnf::do_write_no_snp_full(uint64_t addr, const uint8_t* data64) {
    tick(20);   // inter-transaction gap (CompAck propagation, MSHR retire)
    int txnid = (m_next_txnid++) & 63;
    m_pend[txnid] = PendTxn{}; m_pend[txnid].active = true;

    wait_req_crd(this);
    txreq_flitv.write(true); txreq_flitpend.write(false);
    txreq_flit.write(mk_req(CHI_OP_WRITENOSNPFULL, addr, txnid, true, 0x2));
    tick(); txreq_flitv.write(false);
    printf("[%s] TX REQ  WriteNoSnpFull (0x%02x)     0x%016lx  txnid=%02d\n",
           label, CHI_OP_WRITENOSNPFULL, (unsigned long)addr, txnid);

    int timeout = 20000;
    while (!m_pend[txnid].dbid_rcvd && timeout-- > 0) tick();
    if (timeout <= 0) { printf("[%s] TIMEOUT WriteNoSnpFull DBIDResp addr=0x%lx\n",
                                label, (unsigned long)addr); sc_stop(); return; }

    int dbid     = m_pend[txnid].dbid;
    int dat_tgt  = m_pend[txnid].dat_tgt;  // hnf_nid normally; snf_nid in DWT
    for (int beat = 0; beat < BEATS_PER_LINE; beat++) {
        wait_dat_crd(this);
        txdat_flitv.write(true); txdat_flitpend.write(false);
        txdat_flit.write(mk_dat(CHI_OP_NONCOPYBKWRDATA, dat_tgt, dbid,
                                beat * DATAID_STEP,
                                data64 + beat * CHI_DATA_BEAT_BYTES));
        tick(); txdat_flitv.write(false);
        printf("[%s] TX DAT  NonCopyBkWrData   txnid=%02d  dataid=%d  beat=%d/%d  tgt=%02d\n",
               label, dbid, beat * DATAID_STEP, beat + 1, BEATS_PER_LINE, dat_tgt);
    }

    timeout = 20000;
    while (!m_pend[txnid].comp_rcvd && timeout-- > 0) tick();
    if (timeout <= 0) { printf("[%s] TIMEOUT WriteNoSnpFull Comp addr=0x%lx\n",
                                label, (unsigned long)addr); sc_stop(); return; }

    // ExpCompAck=1 in the REQ causes HNF to set compack_busy on its MSHR entry.
    // Send CompAck so the HNF can retire the entry.
    wait_rsp_crd(this);
    txrsp_flitv.write(true); txrsp_flitpend.write(false);
    txrsp_flit.write(mk_rsp(CHI_OP_COMPACK, dat_tgt, dbid));
    tick(); txrsp_flitv.write(false);
    printf("[%s] TX RSP  CompAck            tgt=%02d  txnid=%02d\n", label, dat_tgt, dbid);

    // Non-coherent: no cache state change
    m_pend[txnid].active = false;
    printf("[%s]   WriteNoSnpFull      0x%016lx  [I   -> I  ]\n",
           label, (unsigned long)addr);
}

// ─── do_atomic_load_add ───────────────────────────────────────────────────────
// AtomicLoad_ADD: 8-byte ADD that returns the pre-modification value via
// CompData.  Requester:
//   1. TX REQ  AtomicLoad_ADD, ExpCompAck=0, Size=3 (8B)
//   2. RX RSP  DBIDResp
//   3. TX DAT  NonCopyBkWrData with operand at bytes [0:7]
//   4. RX DAT  CompData with old value
// No CompAck loops back.
void chi_tlm_rnf::do_atomic_load_add(uint64_t addr, uint64_t operand,
                                       uint64_t* out_old) {
    tick(20);
    int txnid = (m_next_txnid++) & 63;
    m_pend[txnid] = PendTxn{}; m_pend[txnid].active = true;

    wait_req_crd(this);
    txreq_flitv.write(true); txreq_flitpend.write(false);
    sc_bv<CHI_REQ_W> f = mk_req(CHI_OP_ATOMICLOAD_ADD, addr, txnid,
                                /*exp_compack*/ false);
    fset(f, 59, 57, 3);  // Size = 3 -> 8 bytes (mk_req defaults to 6 = 64B)
    txreq_flit.write(f);
    tick(); txreq_flitv.write(false);
    printf("[%s] TX REQ  AtomicLoad_ADD (0x%02x)  0x%016lx  txnid=%02d  operand=0x%016lx\n",
           label, CHI_OP_ATOMICLOAD_ADD, (unsigned long)addr, txnid,
           (unsigned long)operand);

    int timeout = 20000;
    while (!m_pend[txnid].dbid_rcvd && timeout-- > 0) tick();
    if (timeout <= 0) {
        printf("[%s] TIMEOUT AtomicLoad_ADD DBIDResp addr=0x%lx\n",
               label, (unsigned long)addr); sc_stop(); return;
    }

    int dbid    = m_pend[txnid].dbid;
    int dat_tgt = m_pend[txnid].dat_tgt;

    uint8_t payload[32] = {0};
    memcpy(payload, &operand, 8);  // operand at bytes [0:7] of beat 0
    wait_dat_crd(this);
    txdat_flitv.write(true); txdat_flitpend.write(false);
    txdat_flit.write(mk_dat(CHI_OP_NONCOPYBKWRDATA, dat_tgt, dbid, 0, payload));
    tick(); txdat_flitv.write(false);
    printf("[%s] TX DAT  Operand              txnid=%02d  tgt=%02d\n",
           label, dbid, dat_tgt);

    // Atomic CompData is single-beat (8 bytes at DataID=0).  The shared RX
    // DAT handler waits for BOTH dataid=0 and dataid=2 before setting
    // comp_rcvd, so we poll dat_rcvd[0] directly.
    timeout = 20000;
    while (!m_pend[txnid].dat_rcvd[0] && timeout-- > 0) tick();
    if (timeout <= 0) {
        printf("[%s] TIMEOUT AtomicLoad_ADD CompData addr=0x%lx\n",
               label, (unsigned long)addr); sc_stop(); return;
    }

    uint64_t old_val = 0;
    memcpy(&old_val, m_pend[txnid].data, 8);
    if (out_old) *out_old = old_val;

    m_pend[txnid].active = false;
    printf("[%s]   AtomicLoad_ADD      0x%016lx  old=0x%016lx  expected_new=0x%016lx\n",
           label, (unsigned long)addr, (unsigned long)old_val,
           (unsigned long)(old_val + operand));
}

// ─── do_atomic_store_add ──────────────────────────────────────────────────────
// AtomicStore_ADD: 8-byte ADD without returning the old value.  Requester:
//   1. TX REQ  AtomicStore_ADD, ExpCompAck=0, Size=3 (8B)
//   2. RX RSP  DBIDResp
//   3. TX DAT  NonCopyBkWrData with operand at bytes [0:7]
//   4. RX RSP  Comp
void chi_tlm_rnf::do_atomic_store_add(uint64_t addr, uint64_t operand) {
    tick(20);
    int txnid = (m_next_txnid++) & 63;
    m_pend[txnid] = PendTxn{}; m_pend[txnid].active = true;

    wait_req_crd(this);
    txreq_flitv.write(true); txreq_flitpend.write(false);
    sc_bv<CHI_REQ_W> f = mk_req(CHI_OP_ATOMICSTORE_ADD, addr, txnid,
                                /*exp_compack*/ false);
    fset(f, 59, 57, 3);
    txreq_flit.write(f);
    tick(); txreq_flitv.write(false);
    printf("[%s] TX REQ  AtomicStore_ADD (0x%02x) 0x%016lx  txnid=%02d  operand=0x%016lx\n",
           label, CHI_OP_ATOMICSTORE_ADD, (unsigned long)addr, txnid,
           (unsigned long)operand);

    int timeout = 20000;
    while (!m_pend[txnid].dbid_rcvd && timeout-- > 0) tick();
    if (timeout <= 0) {
        printf("[%s] TIMEOUT AtomicStore_ADD DBIDResp addr=0x%lx\n",
               label, (unsigned long)addr); sc_stop(); return;
    }

    int dbid    = m_pend[txnid].dbid;
    int dat_tgt = m_pend[txnid].dat_tgt;

    uint8_t payload[32] = {0};
    memcpy(payload, &operand, 8);
    wait_dat_crd(this);
    txdat_flitv.write(true); txdat_flitpend.write(false);
    txdat_flit.write(mk_dat(CHI_OP_NONCOPYBKWRDATA, dat_tgt, dbid, 0, payload));
    tick(); txdat_flitv.write(false);
    printf("[%s] TX DAT  Operand              txnid=%02d  tgt=%02d\n",
           label, dbid, dat_tgt);

    timeout = 20000;
    while (!m_pend[txnid].comp_rcvd && timeout-- > 0) tick();
    if (timeout <= 0) {
        printf("[%s] TIMEOUT AtomicStore_ADD Comp addr=0x%lx\n",
               label, (unsigned long)addr); sc_stop(); return;
    }

    m_pend[txnid].active = false;
    printf("[%s]   AtomicStore_ADD     0x%016lx  operand=0x%016lx (fire-and-forget)\n",
           label, (unsigned long)addr, (unsigned long)operand);
}

// ─── do_atomic_swap ───────────────────────────────────────────────────────────
// AtomicSwap (CHI-E opcode 0x38): unconditionally writes the operand to the
// addressed 8-byte lane and returns the previous value via CompData.  Same
// protocol shape as AtomicLoad_ADD; only the ALU op differs at the HN-F.
//   1. TX REQ  AtomicSwap, ExpCompAck=0, Size=3 (8B)
//   2. RX RSP  DBIDResp
//   3. TX DAT  NonCopyBkWrData with swap_val at bytes [0:7]
//   4. RX DAT  CompData with old value
void chi_tlm_rnf::do_atomic_swap(uint64_t addr, uint64_t swap_val,
                                   uint64_t* out_old) {
    tick(20);
    int txnid = (m_next_txnid++) & 63;
    m_pend[txnid] = PendTxn{}; m_pend[txnid].active = true;

    wait_req_crd(this);
    txreq_flitv.write(true); txreq_flitpend.write(false);
    sc_bv<CHI_REQ_W> f = mk_req(CHI_OP_ATOMICSWAP, addr, txnid,
                                /*exp_compack*/ false);
    fset(f, 59, 57, 3);  // Size = 3 -> 8 bytes
    txreq_flit.write(f);
    tick(); txreq_flitv.write(false);
    printf("[%s] TX REQ  AtomicSwap (0x%02x)        0x%016lx  txnid=%02d  swap_val=0x%016lx\n",
           label, CHI_OP_ATOMICSWAP, (unsigned long)addr, txnid,
           (unsigned long)swap_val);

    int timeout = 20000;
    while (!m_pend[txnid].dbid_rcvd && timeout-- > 0) tick();
    if (timeout <= 0) {
        printf("[%s] TIMEOUT AtomicSwap DBIDResp addr=0x%lx\n",
               label, (unsigned long)addr); sc_stop(); return;
    }

    int dbid    = m_pend[txnid].dbid;
    int dat_tgt = m_pend[txnid].dat_tgt;

    uint8_t payload[32] = {0};
    memcpy(payload, &swap_val, 8);
    wait_dat_crd(this);
    txdat_flitv.write(true); txdat_flitpend.write(false);
    txdat_flit.write(mk_dat(CHI_OP_NONCOPYBKWRDATA, dat_tgt, dbid, 0, payload));
    tick(); txdat_flitv.write(false);
    printf("[%s] TX DAT  SwapVal              txnid=%02d  tgt=%02d\n",
           label, dbid, dat_tgt);

    timeout = 20000;
    while (!m_pend[txnid].dat_rcvd[0] && timeout-- > 0) tick();
    if (timeout <= 0) {
        printf("[%s] TIMEOUT AtomicSwap CompData addr=0x%lx\n",
               label, (unsigned long)addr); sc_stop(); return;
    }

    uint64_t old_val = 0;
    memcpy(&old_val, m_pend[txnid].data, 8);
    if (out_old) *out_old = old_val;

    m_pend[txnid].active = false;
    printf("[%s]   AtomicSwap          0x%016lx  old=0x%016lx  new=0x%016lx\n",
           label, (unsigned long)addr, (unsigned long)old_val,
           (unsigned long)swap_val);
}

// ─── do_write_unique_ptl ──────────────────────────────────────────────────────
// WriteUniquePtl: partial-byte write.  be0/be1 are the 32-bit byte-enables
// for beat 0 (bytes 0–31) and beat 1 (bytes 32–63) respectively.
// HNF performs a read-modify-write to merge the partial write with memory.
void chi_tlm_rnf::do_write_unique_ptl(uint64_t addr, const uint8_t* data64,
                                       uint32_t be0, uint32_t be1) {
    tick(20);   // inter-transaction gap (CompAck propagation, MSHR retire)
    int txnid = (m_next_txnid++) & 63;
    m_pend[txnid] = PendTxn{}; m_pend[txnid].active = true;

    wait_req_crd(this);
    txreq_flitv.write(true); txreq_flitpend.write(false);
    txreq_flit.write(mk_req(CHI_OP_WRITEUNIQUEPTL, addr, txnid));
    tick(); txreq_flitv.write(false);
    printf("[%s] TX REQ  WriteUniquePtl (0x%02x)     0x%016lx  txnid=%02d  be0=0x%08x  be1=0x%08x\n",
           label, CHI_OP_WRITEUNIQUEPTL, (unsigned long)addr, txnid, be0, be1);

    int timeout = 20000;
    while (!m_pend[txnid].dbid_rcvd && timeout-- > 0) tick();
    if (timeout <= 0) { printf("[%s] TIMEOUT WriteUniquePtl DBIDResp addr=0x%lx\n",
                                label, (unsigned long)addr); sc_stop(); return; }

    int dbid = m_pend[txnid].dbid;
    // Re-slice the caller's (be0, be1) 32-byte-half byte-enables across
    // BEATS_PER_LINE beats.  For 256b beats the mapping is identity; for
    // 128b beats each half is split into a low/high 16-byte quarter.
    uint32_t be_by_beat[4] = {0, 0, 0, 0};
    if (BEATS_PER_LINE == 2) {
        be_by_beat[0] = be0; be_by_beat[1] = be1;
    } else if (BEATS_PER_LINE == 4) {
        be_by_beat[0] = be0 & 0xFFFFu;
        be_by_beat[1] = (be0 >> 16) & 0xFFFFu;
        be_by_beat[2] = be1 & 0xFFFFu;
        be_by_beat[3] = (be1 >> 16) & 0xFFFFu;
    } else if (BEATS_PER_LINE == 1) {
        // 512b beat covers all 64B; mk_dat's BE field is only 32 bits
        // wide, so we approximate by ORing the halves (the HN-F BFM
        // reads the low 32 bits).  A true 512b flit would need a wider
        // BE field alongside the wider DAT.
        be_by_beat[0] = be0 | be1;
    }
    for (int beat = 0; beat < BEATS_PER_LINE; beat++) {
        wait_dat_crd(this);
        txdat_flitv.write(true); txdat_flitpend.write(false);
        txdat_flit.write(mk_dat(CHI_OP_NONCOPYBKWRDATA, hnf_nid, dbid,
                                beat * DATAID_STEP,
                                data64 + beat * CHI_DATA_BEAT_BYTES,
                                be_by_beat[beat]));
        tick(); txdat_flitv.write(false);
        printf("[%s] TX DAT  NonCopyBkWrData   txnid=%02d  dataid=%d  beat=%d/%d  be=0x%08x\n",
               label, dbid, beat * DATAID_STEP, beat + 1, BEATS_PER_LINE,
               be_by_beat[beat]);
    }

    timeout = 20000;
    while (!m_pend[txnid].comp_rcvd && timeout-- > 0) tick();
    if (timeout <= 0) { printf("[%s] TIMEOUT WriteUniquePtl Comp addr=0x%lx\n",
                                label, (unsigned long)addr); sc_stop(); return; }

    ChiState old = cache_state(addr);
    cache_update(addr, ChiState::I);
    m_pend[txnid].active = false;
    printf("[%s]   WriteUniquePtl      0x%016lx  [%-3s -> I  ]\n",
           label, (unsigned long)addr, chi_state_str(old));
}

// ─── do_clean_shared ──────────────────────────────────────────────────────────
// CleanShared: hint to clean any dirty copy of the line in other caches.
// No data transfer from requester; HNF sends Comp when done.  No CompAck.
// Requester's own cache state is unchanged.
void chi_tlm_rnf::do_clean_shared(uint64_t addr) {
    tick(20);   // inter-transaction gap (CompAck propagation, MSHR retire)
    ChiState cur_cs = cache_state(addr);
    int txnid = (m_next_txnid++) & 63;
    m_pend[txnid] = PendTxn{}; m_pend[txnid].active = true;

    wait_req_crd(this);
    txreq_flitv.write(true); txreq_flitpend.write(false);
    txreq_flit.write(mk_req(CHI_OP_CLEANSHARED, addr, txnid, /*exp_compack=*/false));
    tick(); txreq_flitv.write(false);
    printf("[%s] TX REQ  CleanShared (0x%02x)        0x%016lx  txnid=%02d\n",
           label, CHI_OP_CLEANSHARED, (unsigned long)addr, txnid);

    int timeout = 20000;
    while (!m_pend[txnid].comp_rcvd && timeout-- > 0) tick();
    if (timeout <= 0) { printf("[%s] TIMEOUT CleanShared addr=0x%lx\n",
                                label, (unsigned long)addr); sc_stop(); return; }

    // State unchanged — requester keeps its copy as-is
    m_pend[txnid].active = false;
    printf("[%s]   CleanShared         0x%016lx  [%-3s -> %-3s]\n",
           label, (unsigned long)addr, chi_state_str(cur_cs), chi_state_str(cur_cs));
}

// ─── do_clean_unique ──────────────────────────────────────────────────────────
// CleanUnique (ExpCompAck=1): acquire exclusive ownership.
// HNF may send snoops to other RNFs first; those are handled by handle_snoop().
void chi_tlm_rnf::do_clean_unique(uint64_t addr) {
    tick(20);   // inter-transaction gap (CompAck propagation, MSHR retire)
    int txnid = (m_next_txnid++) & 63;
    m_pend[txnid] = PendTxn{};
    m_pend[txnid].active = true;

    wait_req_crd(this);
    txreq_flitv.write(true);
    txreq_flitpend.write(false);
    txreq_flit.write(mk_req(CHI_OP_CLEANUNIQUE, addr, txnid, /*exp_compack=*/true));
    tick();
    txreq_flitv.write(false);
    printf("[%s] TX REQ  CleanUnique (0x%02x)        0x%016lx  txnid=%02d\n",
           label, CHI_OP_CLEANUNIQUE, (unsigned long)addr, txnid);

    int timeout = 20000;
    while (!m_pend[txnid].comp_rcvd && timeout-- > 0) tick();
    if (timeout <= 0) {
        printf("[%s] TIMEOUT: no Comp for CleanUnique addr=0x%lx\n",
               label, (unsigned long)addr);
        sc_stop(); return;
    }

    // Send CompAck for the Comp response
    wait_rsp_crd(this);
    txrsp_flitv.write(true);
    txrsp_flitpend.write(false);
    txrsp_flit.write(mk_rsp(CHI_OP_COMPACK, hnf_nid, m_pend[txnid].dbid));
    tick();
    txrsp_flitv.write(false);
    printf("[%s] TX RSP  CompAck            tgtid=%d  dbid=%02d\n",
           label, hnf_nid, m_pend[txnid].dbid);

    ChiState old_cu = cache_state(addr);
    cache_update(addr, ChiState::UC);
    m_pend[txnid].active = false;
    printf("[%s]   CleanUnique         0x%016lx  [%-3s -> UC ]\n",
           label, (unsigned long)addr, chi_state_str(old_cu));
}

// ─── do_clean_invalid ─────────────────────────────────────────────────────────
// CleanInvalid (no ExpCompAck): invalidate and clean.
// HNF snoops other caches if needed, then sends Comp.  No CompAck required.
void chi_tlm_rnf::do_clean_invalid(uint64_t addr) {
    tick(20);   // inter-transaction gap (CompAck propagation, MSHR retire)
    int txnid = (m_next_txnid++) & 63;
    m_pend[txnid] = PendTxn{};
    m_pend[txnid].active = true;

    wait_req_crd(this);
    txreq_flitv.write(true);
    txreq_flitpend.write(false);
    txreq_flit.write(mk_req(CHI_OP_CLEANINVALID, addr, txnid, /*exp_compack=*/false));
    tick();
    txreq_flitv.write(false);
    printf("[%s] TX REQ  CleanInvalid (0x%02x)       0x%016lx  txnid=%02d\n",
           label, CHI_OP_CLEANINVALID, (unsigned long)addr, txnid);

    int timeout = 20000;
    while (!m_pend[txnid].comp_rcvd && timeout-- > 0) tick();
    if (timeout <= 0) {
        printf("[%s] TIMEOUT: no Comp for CleanInvalid addr=0x%lx\n",
               label, (unsigned long)addr);
        sc_stop(); return;
    }

    ChiState old_ci = cache_state(addr);
    cache_update(addr, ChiState::I);
    m_pend[txnid].active = false;
    printf("[%s]   CleanInvalid        0x%016lx  [%-3s -> I  ]\n",
           label, (unsigned long)addr, chi_state_str(old_ci));
}

// ─── do_make_unique ───────────────────────────────────────────────────────────
// MakeUnique (ExpCompAck=1): claim exclusive empty ownership without fetching
// data.  Used when the requester will overwrite the entire line.
// State after: UCE (Unique Clean Empty — valid owner, data not yet written).
void chi_tlm_rnf::do_make_unique(uint64_t addr) {
    tick(20);   // inter-transaction gap (CompAck propagation, MSHR retire)
    int txnid = (m_next_txnid++) & 63;
    m_pend[txnid] = PendTxn{};
    m_pend[txnid].active = true;

    wait_req_crd(this);
    txreq_flitv.write(true);
    txreq_flitpend.write(false);
    txreq_flit.write(mk_req(CHI_OP_MAKEUNIQUE, addr, txnid, /*exp_compack=*/true));
    tick();
    txreq_flitv.write(false);
    printf("[%s] TX REQ  MakeUnique (0x%02x)         0x%016lx  txnid=%02d\n",
           label, CHI_OP_MAKEUNIQUE, (unsigned long)addr, txnid);

    int timeout = 20000;
    while (!m_pend[txnid].comp_rcvd && timeout-- > 0) tick();
    if (timeout <= 0) {
        printf("[%s] TIMEOUT: no Comp for MakeUnique addr=0x%lx\n",
               label, (unsigned long)addr);
        sc_stop(); return;
    }

    wait_rsp_crd(this);
    txrsp_flitv.write(true);
    txrsp_flitpend.write(false);
    txrsp_flit.write(mk_rsp(CHI_OP_COMPACK, hnf_nid, m_pend[txnid].dbid));
    tick();
    txrsp_flitv.write(false);
    printf("[%s] TX RSP  CompAck            tgtid=%d  dbid=%02d\n",
           label, hnf_nid, m_pend[txnid].dbid);

    ChiState old_mu = cache_state(addr);
    cache_update(addr, ChiState::UCE);
    m_pend[txnid].active = false;
    printf("[%s]   MakeUnique          0x%016lx  [%-3s -> UCE]\n",
           label, (unsigned long)addr, chi_state_str(old_mu));
}

// ─── do_write_no_snp_ptl ──────────────────────────────────────────────────────
// WriteNoSnpPtl: partial-byte non-coherent write.  Same protocol as
// WriteNoSnpFull (order=2/expcompack=1 -> DWT disabled, HNF sends CompDBIDResp,
// RNF sends 2× NonCopyBkWrData with byte enables, then CompAck).
void chi_tlm_rnf::do_write_no_snp_ptl(uint64_t addr, const uint8_t* data64,
                                       uint32_t be0, uint32_t be1) {
    tick(20);   // inter-transaction gap (CompAck propagation, MSHR retire)
    int txnid = (m_next_txnid++) & 63;
    m_pend[txnid] = PendTxn{}; m_pend[txnid].active = true;

    wait_req_crd(this);
    txreq_flitv.write(true); txreq_flitpend.write(false);
    txreq_flit.write(mk_req(CHI_OP_WRITENOSNPPTL, addr, txnid, true, 0x2));
    tick(); txreq_flitv.write(false);
    printf("[%s] TX REQ  WriteNoSnpPtl (0x%02x)    0x%016lx  txnid=%02d  be0=0x%08x  be1=0x%08x\n",
           label, CHI_OP_WRITENOSNPPTL, (unsigned long)addr, txnid, be0, be1);

    int timeout = 20000;
    while (!m_pend[txnid].dbid_rcvd && timeout-- > 0) tick();
    if (timeout <= 0) { printf("[%s] TIMEOUT WriteNoSnpPtl DBIDResp addr=0x%lx\n",
                                label, (unsigned long)addr); sc_stop(); return; }

    int dbid    = m_pend[txnid].dbid;
    int dat_tgt = m_pend[txnid].dat_tgt;
    // Same BE-slicing as do_write_unique_ptl: (be0, be1) are 32B-half
    // byte enables from the caller; redistribute across BEATS_PER_LINE.
    uint32_t be_by_beat[4] = {0, 0, 0, 0};
    if (BEATS_PER_LINE == 2) {
        be_by_beat[0] = be0; be_by_beat[1] = be1;
    } else if (BEATS_PER_LINE == 4) {
        be_by_beat[0] = be0 & 0xFFFFu;
        be_by_beat[1] = (be0 >> 16) & 0xFFFFu;
        be_by_beat[2] = be1 & 0xFFFFu;
        be_by_beat[3] = (be1 >> 16) & 0xFFFFu;
    } else if (BEATS_PER_LINE == 1) {
        be_by_beat[0] = be0 | be1;   // 32-bit BE cannot express full 64B mask
    }
    for (int beat = 0; beat < BEATS_PER_LINE; beat++) {
        wait_dat_crd(this);
        txdat_flitv.write(true); txdat_flitpend.write(false);
        txdat_flit.write(mk_dat(CHI_OP_NONCOPYBKWRDATA, dat_tgt, dbid,
                                beat * DATAID_STEP,
                                data64 + beat * CHI_DATA_BEAT_BYTES,
                                be_by_beat[beat]));
        tick(); txdat_flitv.write(false);
        printf("[%s] TX DAT  NonCopyBkWrData   txnid=%02d  dataid=%d  beat=%d/%d  be=0x%08x\n",
               label, dbid, beat * DATAID_STEP, beat + 1, BEATS_PER_LINE,
               be_by_beat[beat]);
    }

    timeout = 20000;
    while (!m_pend[txnid].comp_rcvd && timeout-- > 0) tick();
    if (timeout <= 0) { printf("[%s] TIMEOUT WriteNoSnpPtl Comp addr=0x%lx\n",
                                label, (unsigned long)addr); sc_stop(); return; }

    // ExpCompAck=1 in the REQ — HNF set compack_busy.  Send CompAck.
    wait_rsp_crd(this);
    txrsp_flitv.write(true); txrsp_flitpend.write(false);
    txrsp_flit.write(mk_rsp(CHI_OP_COMPACK, dat_tgt, dbid));
    tick(); txrsp_flitv.write(false);
    printf("[%s] TX RSP  CompAck            tgt=%02d  txnid=%02d\n", label, dat_tgt, dbid);

    m_pend[txnid].active = false;
    printf("[%s]   WriteNoSnpPtl       0x%016lx  [I   -> I  ]\n",
           label, (unsigned long)addr);
}

// ─── do_evict ─────────────────────────────────────────────────────────────────
// Evict: dataless eviction hint.  RN-F informs HNF that it is silently
// dropping a clean line (e.g., on capacity eviction).  HNF updates its snoop
// filter and returns Comp.  No CompAck required (ExpCompAck=0).
void chi_tlm_rnf::do_evict(uint64_t addr) {
    tick(20);   // inter-transaction gap (CompAck propagation, MSHR retire)
    int txnid = (m_next_txnid++) & 63;
    m_pend[txnid] = PendTxn{}; m_pend[txnid].active = true;

    wait_req_crd(this);
    txreq_flitv.write(true); txreq_flitpend.write(false);
    txreq_flit.write(mk_req(CHI_OP_EVICT, addr, txnid, /*exp_compack=*/false));
    tick(); txreq_flitv.write(false);
    printf("[%s] TX REQ  Evict (0x%02x)             0x%016lx  txnid=%02d\n",
           label, CHI_OP_EVICT, (unsigned long)addr, txnid);

    int timeout = 20000;
    while (!m_pend[txnid].comp_rcvd && timeout-- > 0) tick();
    if (timeout <= 0) { printf("[%s] TIMEOUT Evict Comp addr=0x%lx\n",
                                label, (unsigned long)addr); sc_stop(); return; }

    ChiState old_ev = cache_state(addr);
    cache_update(addr, ChiState::I);
    m_pend[txnid].active = false;
    printf("[%s]   Evict               0x%016lx  [%-3s -> I  ]\n",
           label, (unsigned long)addr, chi_state_str(old_ev));
}

// ─── run ──────────────────────────────────────────────────────────────────────
void chi_tlm_rnf::run() {
    printf("[RNF%d] run() started\n", rnf_nid); fflush(stdout);
    // Deassert all outputs
    txreq_flitv.write(false); txreq_flitpend.write(false); txreq_flit.write(0);
    txrsp_flitv.write(false); txrsp_flitpend.write(false); txrsp_flit.write(0);
    txdat_flitv.write(false); txdat_flitpend.write(false); txdat_flit.write(0);
    rxrsp_lcrdv.write(false);
    rxdat_lcrdv.write(false);
    rxsnp_lcrdv.write(false);
    txlinkactivereq.write(false);
    rxlinkactiveack.write(false);

    // Wait for reset to deassert
    while (!rstn.read()) tick();
    tick(5);

    link_activate();
    grant_initial_rx_credits();

    // HNF pipeline requires ~10000 clock cycles after reset before it can
    // complete transactions. Wait a safe margin before issuing the first REQ.
    tick(12000);

    // ── Non-interleaved test sequence ─────────────────────────────────────────
    // Every do_xxx call blocks until the transaction is fully retired
    // (Comp/CompData received + CompAck sent where required) before the next
    // REQ is issued.  The HNF never sees two concurrent transactions.
    static const uint64_t ADDR_A = 0x8000'0040ULL;
    static const uint64_t ADDR_B = 0x8000'0080ULL;
    static const uint64_t ADDR_C = 0x8000'00C0ULL;
    static const uint64_t ADDR_D = 0x8000'0100ULL;
    static const uint64_t ADDR_E = 0x8000'0140ULL;
    static const uint64_t ADDR_F = 0x8000'0180ULL;

    uint8_t data_a[64], data_b[64], data_c[64];
    uint8_t data_d[64], data_e[64], data_f[64], rbuf[64];
    for (int i = 0; i < 64; i++) {
        data_a[i] = (uint8_t)(0xAA + i);
        data_b[i] = (uint8_t)(0xBB + i);
        data_c[i] = (uint8_t)(0xCC + i);
        data_d[i] = (uint8_t)(0xDD + i);
        data_e[i] = (uint8_t)(0xEE + i);
        data_f[i] = (uint8_t)(0x11 + i);
    }

#define CHK(lbl_, tag_, got_, exp_) do { \
    bool _ok = (memcmp((got_), (exp_), 64) == 0); \
    printf("[%s] %s  %s\n", _ok ? "PASS" : "FAIL", lbl_, tag_); \
} while(0)
#define CHK_N(lbl_, tag_, got_, exp_, n_) do { \
    bool _ok = (memcmp((got_), (exp_), (n_)) == 0); \
    printf("[%s] %s  %s\n", _ok ? "PASS" : "FAIL", lbl_, tag_); \
} while(0)

    if (rnf_nid == 0) {

#ifdef RNF_REPLAY_DEMO
        // ── Test-gen replay demo (step 2 of HN-F testgen project) ────────────
        // Replays one BFS-generated vector instead of the hand-written phases.
        // Vector path and line address overridable via env vars:
        //   REPLAY_VECTOR=<path>     default: SC_AB__REQ_B_CleanUnique.txt
        //   REPLAY_ADDR=<hex>        default: 0x80000200
        // run_all.sh --sweep iterates REPLAY_ADDR over a list of addresses
        // with different L3/SF set indices for exhaustive coverage.
        {
            const char*    vp   = (getenv("REPLAY_VECTOR")
                                   ? getenv("REPLAY_VECTOR")
                                   : "../tb/testgen/vectors/SC_AB__REQ_B_CleanUnique.txt");
            const char*    addr_s = getenv("REPLAY_ADDR");
            const uint64_t addr   = addr_s ? std::strtoull(addr_s, nullptr, 0)
                                           : 0x80000200ULL;
            tick(50);
            testgen::replay_orchestrate(this, vp, addr);
            tick(200);
            return;
        }
#endif

        // ── Ph1: Write / Read / Upgrade / WriteBack ───────────────────────────
        printf("\n[%s] == Ph1 == WriteUniqueFull / ReadClean / CleanUnique / WriteBackFull\n", label);
        do_write          (ADDR_A, data_a);          // WriteUniqueFull  I->I
        do_read           (ADDR_A, rbuf);             // ReadClean        I->SC
        CHK(label, "Ph1 WriteUniqueFull+ReadClean", rbuf, data_a);

        do_clean_unique   (ADDR_A);                  // CleanUnique      SC->UC
        do_write_back_full(ADDR_A);                  // WriteBackFull    UC->I
        do_read           (ADDR_A, rbuf);             // ReadClean        I->SC
        CHK(label, "Ph1 CleanUnique+WriteBackFull", rbuf, data_a);
        do_clean_invalid  (ADDR_A);                  // CleanInvalid     SC->I

        // ── Ph2: ReadUnique / WriteBack / MakeUnique ──────────────────────────
        printf("\n[%s] == Ph2 == ReadUnique / WriteBackFull / MakeUnique\n", label);
        do_write          (ADDR_B, data_b);           // WriteUniqueFull  I->I
        do_read_unique    (ADDR_B, rbuf);             // ReadUnique       I->UC
        CHK(label, "Ph2 ReadUnique", rbuf, data_b);

        do_write_back_full(ADDR_B);                  // WriteBackFull    UC->I
        do_read           (ADDR_B, rbuf);             // ReadClean        I->SC
        CHK(label, "Ph2 WriteBackFull persists data", rbuf, data_b);
        do_make_unique    (ADDR_B);                  // MakeUnique       SC->UCE
        do_clean_invalid  (ADDR_B);                  // CleanInvalid     UCE->I

        // ── Ph3: Non-allocating reads ─────────────────────────────────────────
        printf("\n[%s] == Ph3 == ReadOnce / ReadNoSnp / ReadNotSharedDirty\n", label);
        do_write          (ADDR_A, data_a);          // seed data in memory
        do_read_once      (ADDR_A, rbuf);            // ReadOnce, state stays I
        CHK(label, "Ph3 ReadOnce", rbuf, data_a);
        do_read_no_snp    (ADDR_A, rbuf, false);            // ReadNoSnp, non-coherent
        CHK(label, "Ph3 ReadNoSnp", rbuf, data_a);
        do_read_not_shared_dirty(ADDR_A, rbuf);      // ReadNotSharedDirty   I->SC
        CHK(label, "Ph3 ReadNotSharedDirty", rbuf, data_a);
        do_clean_invalid  (ADDR_A);                  // SC->I

        // ── Ph4: Non-coherent write + read ────────────────────────────────────
        printf("\n[%s] == Ph4 == WriteNoSnpFull / ReadNoSnp\n", label);
        do_write_no_snp_full(ADDR_C, data_c);        // WriteNoSnpFull (no SF update)
        do_read_no_snp    (ADDR_C, rbuf, true);            // ReadNoSnp verify
        CHK(label, "Ph4 WriteNoSnpFull+ReadNoSnp", rbuf, data_c);

        // ── Ph5: Partial write (WriteUniquePtl) — DISABLED ────────────────────
        // WriteUniquePtl stress-test disabled pending partial-merge fix.
#if 0
        printf("\n[%s] == Ph5 == WriteUniquePtl (partial byte-enable, be1=0)\n", label);
        // Write full line with data_a, then overwrite first 32 bytes with data_c.
        // HNF must do RMW; verify only the explicitly written half.
        uint8_t ptl_data[64] = {};
        memcpy(ptl_data, data_c, 32);                // first half = data_c
        do_write          (ADDR_A, data_a);          // establish baseline
        do_write_unique_ptl(ADDR_A, ptl_data,
                            0xFFFF'FFFFu,             // beat0: all 32 bytes valid
                            0x0000'0000u);            // beat1: no bytes written
        do_read           (ADDR_A, rbuf);            // I->SC
        CHK_N(label, "Ph5 WriteUniquePtl first-32B", rbuf, data_c, 32);
        do_clean_invalid  (ADDR_A);                  // SC->I
#endif

        // ── Ph6: CleanShared ──────────────────────────────────────────────────
        printf("\n[%s] == Ph6 == CleanShared (dataless hint)\n", label);
        do_write          (ADDR_A, data_a);          // I->I
        do_read           (ADDR_A, nullptr);         // I->SC
        do_clean_unique   (ADDR_A);                  // SC->UC (no snoops, single node)
        do_clean_shared   (ADDR_A);                  // hint: clean dirty copies; UC unchanged
        do_clean_invalid  (ADDR_A);                  // UC->I
        printf("[PASS] %s  Ph6 CleanShared (no timeout)\n", label);

        // ── Ph7: Multi-line sequential writes/reads ───────────────────────────
        // Stresses HNF MSHR with serial back-to-back transactions on different
        // cache lines.  Each transaction is fully retired before the next REQ.
        printf("\n[%s] == Ph7 == Multi-line burst (writes + reads, 3 lines)\n", label);
        do_write          (ADDR_D, data_d);
        do_write          (ADDR_E, data_e);
        do_write          (ADDR_F, data_f);
        do_read           (ADDR_D, rbuf);    CHK(label, "Ph7 ADDR_D", rbuf, data_d);
        do_read           (ADDR_E, rbuf);    CHK(label, "Ph7 ADDR_E", rbuf, data_e);
        do_read           (ADDR_F, rbuf);    CHK(label, "Ph7 ADDR_F", rbuf, data_f);
        do_clean_invalid  (ADDR_D);
        do_clean_invalid  (ADDR_E);
        do_clean_invalid  (ADDR_F);

        // ── Ph8: WriteUniquePtl second-half — DISABLED ────────────────────────
        // WriteUniquePtl stress-test disabled pending partial-merge fix.
#if 0
        printf("\n[%s] == Ph8 == WriteUniquePtl (partial byte-enable, be0=0)\n", label);
        {
            uint8_t ptl2[64] = {};
            memcpy(ptl2 + 32, data_c, 32);   // beat-1 payload = data_c[0:31]
            do_write          (ADDR_A, data_a);          // baseline
            do_write_unique_ptl(ADDR_A, ptl2,
                                0x0000'0000u,             // beat0: no bytes
                                0xFFFF'FFFFu);            // beat1: all 32 bytes
            do_read           (ADDR_A, rbuf);
            // First 32 bytes should still be data_a, second 32 bytes should be
            // data_c[0:31].
            bool ok0 = (memcmp(rbuf,         data_a, 32) == 0);
            bool ok1 = (memcmp(rbuf + 32,    data_c, 32) == 0);
            printf("[%s] Ph8 WriteUniquePtl second-32B\n", (ok0 && ok1) ? "PASS" : "FAIL");
        }
        do_clean_invalid  (ADDR_A);
#endif

        // ── Ph9: Sequential overwrites to same line ───────────────────────────
        // Three back-to-back WriteUniqueFull to ADDR_A with different data,
        // each transaction fully retired before the next.  Final read must
        // return the last write.
        printf("\n[%s] == Ph9 == Three WriteUniqueFull to same line, last-wins\n", label);
        do_write          (ADDR_A, data_a);
        do_write          (ADDR_A, data_b);
        do_write          (ADDR_A, data_c);
        do_read           (ADDR_A, rbuf);
        CHK(label, "Ph9 last-write wins", rbuf, data_c);
        do_clean_invalid  (ADDR_A);

        // ── Ph10: ReadOnce / ReadNoSnp on locally-cached SC line ──────────────
        // Non-allocating reads must return correct data even when the local
        // cache already holds the line in SC.  Cache state stays SC after
        // ReadOnce/ReadNoSnp (they don't allocate).
        printf("\n[%s] == Ph10 == ReadOnce/ReadNoSnp on locally-cached SC line\n", label);
        do_write          (ADDR_B, data_b);
        do_read           (ADDR_B, rbuf);             // I->SC, cache holds data_b
        CHK(label, "Ph10 ReadClean", rbuf, data_b);
        do_read_once      (ADDR_B, rbuf);             // non-allocating
        CHK(label, "Ph10 ReadOnce on SC", rbuf, data_b);
        do_read_no_snp    (ADDR_B, rbuf, true);       // non-coherent
        CHK(label, "Ph10 ReadNoSnp on SC", rbuf, data_b);
        do_clean_invalid  (ADDR_B);

        // ── Ph11: WriteNoSnpPtl — partial non-coherent write ──────────────────
        // Lay down a known baseline via WriteNoSnpFull, then overwrite only the
        // first 32 bytes via WriteNoSnpPtl (be0=0xFFFFFFFF, be1=0).  Read back
        // and verify HNF/SNF merged correctly: first half = data_d, second half
        // = baseline data_c[32:63].
        printf("\n[%s] == Ph11 == WriteNoSnpPtl (first-half overwrite)\n", label);
        do_write_no_snp_full(ADDR_C, data_c);         // baseline
        do_write_no_snp_ptl (ADDR_C, data_d,
                             0xFFFF'FFFFu,             // beat0: all 32 bytes
                             0x0000'0000u);            // beat1: no bytes
        do_read_no_snp     (ADDR_C, rbuf, true);
        {
            bool ok0 = (memcmp(rbuf,         data_d,         32) == 0);
            bool ok1 = (memcmp(rbuf + 32,    data_c + 32,    32) == 0);
            printf("[%s] Ph11 WriteNoSnpPtl first-32B merged with baseline\n",
                   (ok0 && ok1) ? "PASS" : "FAIL");
        }

        // ── Ph12: Evict from UC state ─────────────────────────────────────────
        // Take ADDR_E from I->SC->UC, then Evict to tell HNF we dropped the line.
        // Re-read after to confirm memory still has the data and HNF accepts
        // the new request after the snoop-filter cleanup.
        printf("\n[%s] == Ph12 == Evict from UC, then re-fetch from memory\n", label);
        do_write          (ADDR_E, data_e);          // baseline in memory
        do_read           (ADDR_E, rbuf);            // I->SC
        do_clean_unique   (ADDR_E);                  // SC->UC
        do_evict          (ADDR_E);                  // UC->I (silent drop hint)
        do_read           (ADDR_E, rbuf);            // I->SC (re-fetch)
        CHK(label, "Ph12 data persists after Evict", rbuf, data_e);
        do_clean_invalid  (ADDR_E);

        // ── Ph13: WriteUniquePtl middle bytes — DISABLED ──────────────────────
        // WriteUniquePtl stress-test disabled pending partial-merge fix.
#if 0
        printf("\n[%s] == Ph13 == WriteUniquePtl middle bytes (be0=0x00FFFF00)\n", label);
        {
            uint8_t mid_data[64];
            memset(mid_data, 0x55, 64);              // arbitrary distinct value
            do_write          (ADDR_A, data_a);      // baseline
            do_write_unique_ptl(ADDR_A, mid_data,
                                0x00FF'FF00u,         // beat0: bytes [8:23]
                                0x0000'0000u);        // beat1: nothing
            do_read           (ADDR_A, rbuf);
            // Expected: bytes [0:7]=data_a, [8:23]=0x55, [24:63]=data_a
            bool ok_lo  = (memcmp(rbuf,         data_a,        8) == 0);
            bool ok_mid = true;
            for (int i = 8; i < 24; i++) ok_mid &= (rbuf[i] == 0x55);
            bool ok_hi  = (memcmp(rbuf + 24,    data_a + 24,  40) == 0);
            printf("[%s] Ph13 WriteUniquePtl byte-granular merge\n",
                   (ok_lo && ok_mid && ok_hi) ? "PASS" : "FAIL");
        }
        do_clean_invalid  (ADDR_A);
#endif

        // ── Ph14: State-cycle loop on one line ────────────────────────────────
        // I -> SC -> UC -> I -> SC -> UC -> I -> SC, three full WriteBack cycles.
        // Exercises the MSHR retire/realloc path repeatedly on the same line.
        printf("\n[%s] == Ph14 == Triple WriteBack cycle (I->SC->UC->I)x3\n", label);
        do_write          (ADDR_F, data_f);          // seed
        for (int cyc = 0; cyc < 3; cyc++) {
            do_read           (ADDR_F, rbuf);        // I->SC
            do_clean_unique   (ADDR_F);              // SC->UC
            do_write_back_full(ADDR_F);              // UC->I
        }
        do_read           (ADDR_F, rbuf);
        CHK(label, "Ph14 data survives 3 WB cycles", rbuf, data_f);
        do_clean_invalid  (ADDR_F);

        // ── Ph15: 6-line write burst then 6-line read burst ───────────────────
        // Writes all 6 addresses, then reads each in the same order.  Stresses
        // the HNF MSHR with rapid serial allocation across many lines.
        printf("\n[%s] == Ph15 == 6-line burst (writes then reads)\n", label);
        do_write          (ADDR_A, data_a);
        do_write          (ADDR_B, data_b);
        do_write          (ADDR_C, data_c);
        do_write          (ADDR_D, data_d);
        do_write          (ADDR_E, data_e);
        do_write          (ADDR_F, data_f);
        do_read           (ADDR_A, rbuf);   CHK(label, "Ph15 ADDR_A", rbuf, data_a);
        do_read           (ADDR_B, rbuf);   CHK(label, "Ph15 ADDR_B", rbuf, data_b);
        do_read           (ADDR_C, rbuf);   CHK(label, "Ph15 ADDR_C", rbuf, data_c);
        do_read           (ADDR_D, rbuf);   CHK(label, "Ph15 ADDR_D", rbuf, data_d);
        do_read           (ADDR_E, rbuf);   CHK(label, "Ph15 ADDR_E", rbuf, data_e);
        do_read           (ADDR_F, rbuf);   CHK(label, "Ph15 ADDR_F", rbuf, data_f);
        do_clean_invalid  (ADDR_A);
        do_clean_invalid  (ADDR_B);
        do_clean_invalid  (ADDR_C);
        do_clean_invalid  (ADDR_D);
        do_clean_invalid  (ADDR_E);
        do_clean_invalid  (ADDR_F);

        // ── Ph_AT: Atomics smoke test (P5/P6 first-functional ────────────────
        // Seed a non-zero L3 value, then AtomicLoad_ADD an operand and check
        // the returned old value.  Then AtomicStore_ADD and verify a follow-up
        // ReadClean reflects the sum.  Expected to break or hang in early P5
        // builds due to ALU mux-gate and operand-routing gaps; the 2 ms TB
        // timeout will catch.
        printf("\n[%s] == Ph_AT == Atomics (AtomicLoad_ADD, AtomicStore_ADD, AtomicSwap)\n", label);
        do_clean_invalid  (ADDR_F);              // ensure HNF L3 is clean
        // Seed via WriteNoSnpFull so the seed lands in SN-F memory directly.
        // The atomic RMW path fetches OLD from SN-F (the HN-F doesn't cache
        // the line for atomic ops in this minimum-viable wiring).
        do_write_no_snp_full(ADDR_F, data_f);    // seed bytes [0:7] with data_f
        do_clean_invalid  (ADDR_F);              // drop our copy

        uint64_t seed = 0;
        memcpy(&seed, data_f, 8);
        uint64_t op   = 0x11ull;
        uint64_t old_ret = 0;
        do_atomic_load_add(ADDR_F, op, &old_ret);
        printf("[%s] Ph_AT load_add  seed=0x%016lx op=0x%016lx ret=0x%016lx (expected seed)\n",
               label, (unsigned long)seed, (unsigned long)op, (unsigned long)old_ret);

        do_atomic_store_add(ADDR_F, 0x22ull);
        // Read-back to inspect the merged value (expect seed + op + 0x22 if the
        // ALU committed both atomics into the same lane).
        do_read           (ADDR_F, rbuf);
        uint64_t after = 0;
        memcpy(&after, rbuf, 8);
        printf("[%s] Ph_AT read_back  0x%016lx (expected seed+0x33 = 0x%016lx)\n",
               label, (unsigned long)after, (unsigned long)(seed + op + 0x22));

        // ── AtomicSwap: replace the lane with a marker value and verify
        // both the returned OLD and the post-swap memory state.
        do_clean_invalid  (ADDR_F);
        uint64_t before_swap = seed + op + 0x22;     // current value in mem
        uint64_t swap_val    = 0xDEADBEEFCAFEBABEull;
        uint64_t swap_old    = 0;
        do_atomic_swap    (ADDR_F, swap_val, &swap_old);
        printf("[%s] Ph_AT swap  before=0x%016lx swap_in=0x%016lx returned_old=0x%016lx\n",
               label, (unsigned long)before_swap, (unsigned long)swap_val,
               (unsigned long)swap_old);
        do_read           (ADDR_F, rbuf);
        uint64_t after_swap = 0;
        memcpy(&after_swap, rbuf, 8);
        printf("[%s] Ph_AT swap_read_back 0x%016lx (expected swap_val = 0x%016lx)\n",
               label, (unsigned long)after_swap, (unsigned long)swap_val);

        do_clean_invalid  (ADDR_F);

        // ── Ph_EV: Evict from every legal source state ────────────────────────
        // CHI spec says Evict is sent by the RN-F to inform the HN-F that it
        // has silently dropped a *clean* line.  Legal source states are SC, UC,
        // and UCE.  After Evict the line is I at the RN-F and the HN-F removes
        // the RN-F from its snoop filter for that line.  Subsequent ReadClean
        // from the same RN-F re-fetches from memory.
        printf("\n[%s] == Ph_EV == Evict from SC / UC / UCE\n", label);

        // (a) Evict from SC.
        do_write          (ADDR_A, data_a);          // baseline in memory
        do_read           (ADDR_A, rbuf);            // I->SC
        do_evict          (ADDR_A);                  // SC->I
        do_read           (ADDR_A, rbuf);            // re-fetch from memory
        CHK(label, "Ph_EV (SC) data persists", rbuf, data_a);
        do_clean_invalid  (ADDR_A);

        // (b) Evict from UC.
        do_write          (ADDR_B, data_b);          // baseline
        do_read           (ADDR_B, rbuf);            // I->SC
        do_clean_unique   (ADDR_B);                  // SC->UC
        do_evict          (ADDR_B);                  // UC->I
        do_read           (ADDR_B, rbuf);            // re-fetch
        CHK(label, "Ph_EV (UC) data persists", rbuf, data_b);
        do_clean_invalid  (ADDR_B);

        // (c) Evict from UCE (Unique Clean Empty — got via MakeUnique).
        // No data was written by this RN-F, so memory still holds the value
        // last written by the prior WriteUniqueFull on ADDR_C.
        do_write          (ADDR_C, data_c);          // memory baseline
        do_make_unique    (ADDR_C);                  // I->UCE (no data fetch)
        do_evict          (ADDR_C);                  // UCE->I
        do_read           (ADDR_C, rbuf);            // re-fetch
        CHK(label, "Ph_EV (UCE) memory persists", rbuf, data_c);
        do_clean_invalid  (ADDR_C);

        // ── Setup for RNF1: leave ADDR_A and ADDR_B in SC ─────────────────────
        printf("\n[%s] == Setup == Seed ADDR_A/B in SC, then signal RNF1\n", label);
        do_write          (ADDR_A, data_a);          // I->I
        do_read           (ADDR_A, nullptr);         // I->SC  (RNF1 ReadClean -> SnpClean)
        do_write          (ADDR_B, data_b);          // I->I
        do_read           (ADDR_B, nullptr);         // I->SC  (RNF1 ReadUnique -> SnpMakeInvalid)

        printf("[%s] Ph1-15 complete; ADDR_A/B in SC — signalling RNF1\n", label);
        g_rnf0_write_done.notify();

        // Stay alive to service snoops from RNF1's Ph16-Ph19.  Tick (servicing
        // snoops every cycle) until RNF1 signals it is done with the
        // non-interleaved phases.  Bounded by a safety timeout.
        for (int i = 0; i < 500000 && !g_rnf1_phases_done; i++) tick();

        // ════════════════════════════════════════════════════════════════════
        //  Interleaved tests — both RN-Fs issue concurrently after a barrier
        // ════════════════════════════════════════════════════════════════════

        // ── IL1: Concurrent WriteUniqueFull to *different* lines ──────────────
        // Exercises the HNF MSHR with two concurrent in-flight entries; no
        // coherence interaction (disjoint addresses).
        printf("\n[%s] == IL1 == Concurrent WriteUniqueFull (RNF0->E, RNF1->F)\n", label);
        g_rnf0_at_il1 = true;
        while (!g_rnf1_at_il1) tick();
        do_write          (ADDR_E, data_e);
        do_read           (ADDR_E, rbuf);
        CHK(label, "IL1 ADDR_E persisted", rbuf, data_e);
        do_clean_invalid  (ADDR_E);

        // ── IL2: Concurrent ReadClean to *same* line (read–read race) ─────────
        // Both RN-Fs read the same line at the same time.  HNF serialises via
        // the MSHR but both should receive CompData with the same value (no
        // snoops needed; line is in memory only, both end up in SC).
        printf("\n[%s] == IL2 == Concurrent ReadClean to ADDR_D (read-read race)\n", label);
        do_write          (ADDR_D, data_d);            // baseline in memory (RNF0 only)
        do_clean_invalid  (ADDR_D);                    // drop RNF0 cache, ensure I
        g_rnf0_at_il2 = true;
        while (!g_rnf1_at_il2) tick();
        do_read           (ADDR_D, rbuf);              // race the read
        CHK(label, "IL2 RNF0 ReadClean ADDR_D", rbuf, data_d);
        do_clean_invalid  (ADDR_D);

        // ── IL3: Concurrent CleanUnique to *same* line (upgrade race) ─────────
        // Both RN-Fs hold ADDR_A in SC and simultaneously request UC.  The HNF
        // must serialise: one allocates the MSHR first and snoops the other to
        // I; the second one then sees a CAM hazard, gets snooped data via the
        // cache pipeline path, and eventually also reaches UC.  Both helpers
        // should return without timing out.
        printf("\n[%s] == IL3 == Concurrent CleanUnique on ADDR_A (upgrade race)\n", label);
        do_write          (ADDR_A, data_a);            // baseline
        do_read           (ADDR_A, rbuf);              // I->SC on RNF0
        g_rnf0_at_il3 = true;
        while (!g_rnf1_at_il3) tick();
        do_clean_unique   (ADDR_A);                    // race CleanUnique
        do_clean_invalid  (ADDR_A);

        // ── IL4: Concurrent ReadUnique to *same* line (read-for-ownership race) ─
        // Both RN-Fs request UC ownership of an uncached line.  The HNF allocates
        // an MSHR for the first arrival; the second hits CAM hazard and proceeds
        // via cache pipeline after the first's snoop has invalidated this RN-F.
        printf("\n[%s] == IL4 == Concurrent ReadUnique to ADDR_B (R4O race)\n", label);
        do_write          (ADDR_B, data_b);            // seed memory
        g_rnf0_at_il4 = true;
        while (!g_rnf1_at_il4) tick();
        do_read_unique    (ADDR_B, rbuf);              // race ReadUnique
        // Whichever RNF wins last has UC; data must match.
        CHK(label, "IL4 RNF0 ReadUnique data", rbuf, data_b);
        do_clean_invalid  (ADDR_B);

        // ── IL5: Concurrent WriteUniqueFull to *same* address (last-writer wins) ─
        // Both RN-Fs issue WriteUniqueFull at the same instant; the HNF must
        // serialise the two via the MSHR.  Final memory value is whichever one
        // ran last.  Cannot CHK exact value — only that the read returns ONE of
        // the two written values, never a partial mix.
        printf("\n[%s] == IL5 == Concurrent WriteUniqueFull to ADDR_C (write-write race)\n", label);
        g_rnf0_at_il5 = true;
        while (!g_rnf1_at_il5) tick();
        do_write          (ADDR_C, data_a);            // RNF0 writes data_a
        do_clean_invalid  (ADDR_C);                    // ensure I before readback
        do_read           (ADDR_C, rbuf);              // see who won
        {
            bool ok = (memcmp(rbuf, data_a, 64) == 0) ||
                      (memcmp(rbuf, data_b, 64) == 0);
            printf("[%s] IL5 last-writer wins (RNF0 sees %s)\n",
                   ok ? "PASS" : "FAIL",
                   (memcmp(rbuf, data_a, 64) == 0) ? "data_a" :
                   (memcmp(rbuf, data_b, 64) == 0) ? "data_b" : "MIX");
        }
        do_clean_invalid  (ADDR_C);

        // ── IL6: Concurrent ReadOnce (non-allocating) to *same* line ──────────
        // Both RN-Fs issue ReadOnce.  Non-allocating, non-coherent at the L1
        // level; both go through the HNF to memory and get the same data.  No
        // snoops, no cache state changes.
        printf("\n[%s] == IL6 == Concurrent ReadOnce to ADDR_D (no-coherence race)\n", label);
        do_write          (ADDR_D, data_d);            // seed memory
        do_clean_invalid  (ADDR_D);                    // RNF0 in I
        g_rnf0_at_il6 = true;
        while (!g_rnf1_at_il6) tick();
        do_read_once      (ADDR_D, rbuf);              // race ReadOnce
        CHK(label, "IL6 RNF0 ReadOnce ADDR_D", rbuf, data_d);

        // ── IL7: Concurrent ReadClean (RNF0) + WriteUniqueFull (RNF1) same line ─
        // Mixed read/write race.  HNF must serialise; RNF0 gets either the
        // pre-write or post-write value (both valid), and the write must
        // ultimately reach memory.
        printf("\n[%s] == IL7 == ReadClean(RNF0) || WriteUniqueFull(RNF1) on ADDR_E\n", label);
        do_write          (ADDR_E, data_e);            // baseline
        do_clean_invalid  (ADDR_E);
        g_rnf0_at_il7 = true;
        while (!g_rnf1_at_il7) tick();
        do_read           (ADDR_E, rbuf);              // race the read
        {
            // RNF0 must see either the baseline (data_e) or RNF1's new write
            // (data_a) — never a partial mix.
            bool ok = (memcmp(rbuf, data_e, 64) == 0) ||
                      (memcmp(rbuf, data_a, 64) == 0);
            printf("[%s] IL7 RNF0 read mixed race (saw %s)\n",
                   ok ? "PASS" : "FAIL",
                   (memcmp(rbuf, data_e, 64) == 0) ? "baseline data_e" :
                   (memcmp(rbuf, data_a, 64) == 0) ? "post-write data_a" : "MIX");
        }
        do_clean_invalid  (ADDR_E);

        // ── IL8: Cross-address burst — no contention, maximum parallelism ─────
        // RNF0 writes/reads ADDR_A,B,C while RNF1 writes/reads ADDR_D,E,F.
        // No address overlap; HNF MSHR services both streams in parallel.
        printf("\n[%s] == IL8 == Cross-address burst (RNF0: A/B/C, RNF1: D/E/F)\n", label);
        g_rnf0_at_il8 = true;
        while (!g_rnf1_at_il8) tick();
        do_write          (ADDR_A, data_a);
        do_write          (ADDR_B, data_b);
        do_write          (ADDR_C, data_c);
        do_read           (ADDR_A, rbuf); CHK(label, "IL8 RNF0 ADDR_A", rbuf, data_a);
        do_read           (ADDR_B, rbuf); CHK(label, "IL8 RNF0 ADDR_B", rbuf, data_b);
        do_read           (ADDR_C, rbuf); CHK(label, "IL8 RNF0 ADDR_C", rbuf, data_c);
        do_clean_invalid  (ADDR_A);
        do_clean_invalid  (ADDR_B);
        do_clean_invalid  (ADDR_C);

        // ── IL9: Concurrent WriteBackFull(UC) + ReadClean to *same* line ──────
        // RNF0 holds ADDR_F in UC, writes it back.  RNF1 simultaneously issues
        // ReadClean to ADDR_F.  Two valid orderings:
        //   a) RNF1 first → HNF snoops RNF0 (UC→SC), RNF1 gets data via snoop
        //   b) RNF0 first → WB completes, memory updated; RNF1 reads from mem
        // Either way both end up with the same data value.
        printf("\n[%s] == IL9 == WriteBackFull(RNF0,UC) || ReadClean(RNF1) on ADDR_F\n", label);
        do_write          (ADDR_F, data_f);            // I (no allocate)
        do_read           (ADDR_F, rbuf);              // I→SC
        do_clean_unique   (ADDR_F);                    // SC→UC, RNF0 owns
        g_rnf0_at_il9 = true;
        while (!g_rnf1_at_il9) tick();
        do_write_back_full(ADDR_F);                    // UC→I, write data_f back
        do_read           (ADDR_F, rbuf);              // verify data persisted
        CHK(label, "IL9 RNF0 ADDR_F readback", rbuf, data_f);
        do_clean_invalid  (ADDR_F);

        // ── IL10: Concurrent WriteBackFull from BOTH RN-Fs (different lines) ──
        // RNF0 owns ADDR_D in UC, RNF1 owns ADDR_E in UC.  Both write back at
        // the same instant.  Disjoint MSHR entries, no snoop interaction.
        printf("\n[%s] == IL10 == Concurrent WriteBackFull (RNF0→D, RNF1→E)\n", label);
        do_write          (ADDR_D, data_d);            // baseline in memory
        do_read           (ADDR_D, rbuf);              // I→SC
        do_clean_unique   (ADDR_D);                    // SC→UC
        g_rnf0_at_il10 = true;
        while (!g_rnf1_at_il10) tick();
        do_write_back_full(ADDR_D);                    // UC→I (race WB)
        do_read           (ADDR_D, rbuf);
        CHK(label, "IL10 RNF0 ADDR_D persists", rbuf, data_d);
        do_clean_invalid  (ADDR_D);

        // ── IL11: Concurrent CleanInvalid to *same* address ───────────────────
        // Both RN-Fs hold ADDR_A in SC; both issue CleanInvalid simultaneously.
        // Either ordering: both eventually become I.  Tests serialised dataless
        // invalidation snoops.
        printf("\n[%s] == IL11 == Concurrent CleanInvalid to ADDR_A\n", label);
        do_write          (ADDR_A, data_a);            // baseline
        do_read           (ADDR_A, rbuf);              // I→SC on RNF0
        g_rnf0_at_il11 = true;
        while (!g_rnf1_at_il11) tick();
        do_clean_invalid  (ADDR_A);                    // race CleanInvalid

        // ── IL12: Concurrent Evict to *different* lines ───────────────────────
        // Both RN-Fs evict their UC copies of disjoint addresses (B, C).  Tests
        // snoop-filter cleanup under parallel evict pressure.
        printf("\n[%s] == IL12 == Concurrent Evict (RNF0→B, RNF1→C)\n", label);
        do_write          (ADDR_B, data_b);
        do_read           (ADDR_B, rbuf);
        do_clean_unique   (ADDR_B);                    // SC→UC
        g_rnf0_at_il12 = true;
        while (!g_rnf1_at_il12) tick();
        do_evict          (ADDR_B);                    // UC→I (race Evict)
        do_clean_invalid  (ADDR_B);

        // ── IL13: Pipelined burst race — alternating addresses ────────────────
        // Both RN-Fs run a 4-step micro-sequence on different addresses (RNF0:
        // ADDR_D, RNF1: ADDR_E).  All 8 transactions are in flight concurrently
        // via the HNF MSHR; no snoop interaction (disjoint lines).
        printf("\n[%s] == IL13 == Pipelined sequence (W/R/CU/CI) on disjoint lines\n", label);
        g_rnf0_at_il13 = true;
        while (!g_rnf1_at_il13) tick();
        do_write          (ADDR_D, data_d);
        do_read           (ADDR_D, rbuf); CHK(label, "IL13 RNF0 ADDR_D read", rbuf, data_d);
        do_clean_unique   (ADDR_D);
        do_clean_invalid  (ADDR_D);

        // ── IL14: Ping-pong ownership transfer ────────────────────────────────
        // RNF0 takes UC of ADDR_F, then RNF1 takes UC (snoops RNF0 to I), then
        // RNF0 takes UC back (snoops RNF1 to I), etc.  Stresses snoop-filter
        // owner tracking with alternating owners.  Each step is sequential
        // *within* a thread but the threads run interleaved at protocol level.
        printf("\n[%s] == IL14 == Ping-pong UC ownership on ADDR_F (RNF0 leg)\n", label);
        do_write          (ADDR_F, data_f);            // baseline
        g_rnf0_at_il14 = true;
        while (!g_rnf1_at_il14) tick();
        // RNF0 grabs UC three times, alternating with RNF1.
        for (int i = 0; i < 3; i++) {
            do_read_unique (ADDR_F, rbuf);             // I→UC (snoops RNF1 if it held)
        }
        do_clean_invalid  (ADDR_F);

        // ── IL15: Concurrent MakeUnique to same line (no data fetch race) ─────
        // MakeUnique asserts exclusive empty ownership without fetching data.
        // Both RN-Fs claim ADDR_A simultaneously; HNF must serialise — one wins
        // UCE, the other snoops it to I, then proceeds and also reaches UCE.
        printf("\n[%s] == IL15 == Concurrent MakeUnique to ADDR_A (UCE race)\n", label);
        g_rnf0_at_il15 = true;
        while (!g_rnf1_at_il15) tick();
        do_make_unique    (ADDR_A);                    // race MakeUnique
        do_clean_invalid  (ADDR_A);

        // ── IL16: Producer/consumer — RNF0 writes, RNF1 reads, repeated ──────
        // RNF0 writes data_b to ADDR_B 4 times; RNF1 reads ADDR_B 4 times in
        // parallel.  Each RNF1 read may see any of the in-flight writes plus
        // the baseline; must always be one *complete* value.
        printf("\n[%s] == IL16 == Producer(RNF0) / Consumer(RNF1) on ADDR_B (4x)\n", label);
        do_write          (ADDR_B, data_a);            // baseline = data_a
        g_rnf0_at_il16 = true;
        while (!g_rnf1_at_il16) tick();
        for (int i = 0; i < 4; i++) {
            do_write       (ADDR_B, data_b);           // produce data_b
        }
        do_clean_invalid  (ADDR_B);

        // ── IL17: Concurrent ReadClean to *different* lines (parallelism) ─────
        // Pure throughput test — both RN-Fs read disjoint addresses repeatedly.
        // No coherence interaction; the HNF MSHR should service both streams in
        // parallel.
        printf("\n[%s] == IL17 == Concurrent ReadClean to disjoint lines (3 rounds)\n", label);
        do_write          (ADDR_C, data_c);
        do_write          (ADDR_D, data_d);
        do_clean_invalid  (ADDR_C);
        do_clean_invalid  (ADDR_D);
        g_rnf0_at_il17 = true;
        while (!g_rnf1_at_il17) tick();
        for (int i = 0; i < 3; i++) {
            do_read         (ADDR_C, rbuf); CHK(label, "IL17 RNF0 ADDR_C", rbuf, data_c);
            do_clean_invalid(ADDR_C);
        }

        // ── IL18: Concurrent WriteUniquePtl — DISABLED ────────────────────────
        // WriteUniquePtl stress-test disabled pending partial-merge fix.
        // Barrier omitted on both sides so IL19 starts independently.
#if 0
        printf("\n[%s] == IL18 == Concurrent WriteUniquePtl (RNF0→E:first-half, RNF1→F:second-half)\n", label);
        do_write          (ADDR_E, data_a);            // baseline = data_a
        do_write          (ADDR_F, data_a);            // baseline = data_a
        do_clean_invalid  (ADDR_E);
        do_clean_invalid  (ADDR_F);
        g_rnf0_at_il18 = true;
        while (!g_rnf1_at_il18) tick();
        do_write_unique_ptl(ADDR_E, data_e, 0xFFFF'FFFFu, 0x0000'0000u);
        do_read           (ADDR_E, rbuf);
        {
            bool ok0 = (memcmp(rbuf,         data_e, 32) == 0);
            bool ok1 = (memcmp(rbuf + 32,    data_a + 32, 32) == 0);
            printf("[%s] IL18 RNF0 first-half merge ADDR_E\n", (ok0 && ok1) ? "PASS" : "FAIL");
        }
        do_clean_invalid  (ADDR_E);
#endif

        // ── IL19: Three-way snoop chain (UC → snooped → re-acquired) ──────────
        // RNF0 grabs UC of ADDR_D, RNF1 then reads (snoops RNF0 UC→SC), RNF0
        // then CleanUnique (snoops RNF1 SC→I).  Tests successive ownership
        // changes with intervening snoops.  Sequential within each thread, but
        // racing at the protocol level due to the barrier.
        printf("\n[%s] == IL19 == Ownership chain on ADDR_D (RNF0 leg)\n", label);
        do_write          (ADDR_D, data_d);
        do_read           (ADDR_D, rbuf);              // I→SC
        do_clean_unique   (ADDR_D);                    // SC→UC
        g_rnf0_at_il19 = true;
        while (!g_rnf1_at_il19) tick();
        // Wait a tick for RNF1's read to snoop, then re-acquire.
        tick(50);
        do_clean_unique   (ADDR_D);                    // snoops RNF1, back to UC
        do_clean_invalid  (ADDR_D);

        // ── IL20: CHI-E coherent atomic with peer-held line ───────────────────
        // RNF0 takes UC of ADDR_E and writes a known pattern locally; RNF1
        // then issues AtomicLoad_ADD.  The HN-F MUST snoop RNF0 (SnpUnique
        // because L3 miss), get RNF0's data (or invalidate it if clean),
        // run the ALU on the snoop-forwarded/SN-F-cached value, return OLD
        // to RNF1, and leave RNF0 invalidated.  After the atomic, RNF0
        // re-reading the line must miss its local cache and re-fetch from
        // the HN-F, observing the post-RMW value.
        printf("\n[%s] == IL20 == Coherent atomic with peer-held line\n", label);
        do_write_no_snp_full(ADDR_E, data_e);          // seed memory baseline
        do_clean_invalid    (ADDR_E);
        do_read_unique      (ADDR_E, rbuf);            // RNF0: I→UC, SF marks RNF0 holds
        CHK(label, "IL20 ReadUnique baseline", rbuf, data_e);
        g_rnf0_at_il20 = true;
        while (!g_rnf1_at_il20) tick();
        // RNF1 issues AtomicLoad on ADDR_E.  HN-F snoops RNF0 (we just
        // hold UC), our snoop service returns SnpResp(I); the atomic then
        // completes against SN-F memory (still the baseline).
        // Wait for RNF1's atomic to retire, then re-read ADDR_E -- since
        // we got invalidated, this is an I→SC miss and the value should
        // be the post-atomic-update.
        tick(500);
        do_read             (ADDR_E, rbuf);            // I→SC re-fetch
        uint64_t seedE = 0; memcpy(&seedE, data_e, 8);
        uint64_t got_lane0 = 0; memcpy(&got_lane0, rbuf, 8);
        const uint64_t expected_lane0 = seedE + 0x44ull;  // RNF1's IL20 operand
        printf("[%s] IL20 post-atomic readback: lane0=0x%016lx expected=0x%016lx %s\n",
               label, (unsigned long)got_lane0, (unsigned long)expected_lane0,
               (got_lane0 == expected_lane0) ? "PASS" : "FAIL");
        do_clean_invalid    (ADDR_E);

        printf("[%s] IL complete — interleaved tests done\n", label);

        // Drain a few hundred cycles so the last RSP/DAT settles before sc_stop.
        tick(200);

    } else { // ── RNF1 ─────────────────────────────────────────────────────────

#ifdef RNF_REPLAY_DEMO
        // ── Test-gen replay worker (peer for orchestrator on RNF0) ───────────
        {
            tick(50);
            testgen::replay_worker(this);
            tick(200);
            return;
        }
#endif

        wait(g_rnf0_write_done);
        tick(20);

        // ── Ph16: ReadClean + upgrade (ADDR_A) ────────────────────────────────
        printf("\n[%s] == Ph16 == Coherent ReadClean + CleanUnique  (RNF0 holds ADDR_A in SC)\n", label);
        // RNF0 holds ADDR_A in SC -> SnpClean issued on our ReadClean.
        do_read           (ADDR_A, rbuf);            // I->SC (SnpClean->RNF0: SC->SC)
        CHK(label, "Ph16 coherent ReadClean", rbuf, data_a);
        do_clean_unique   (ADDR_A);                  // SC->UC (SnpMakeInvalid->RNF0: SC->I)
        do_clean_invalid  (ADDR_A);                  // UC->I

        // ── Ph17: ReadUnique (ADDR_B) ─────────────────────────────────────────
        printf("\n[%s] == Ph17 == Coherent ReadUnique + WriteBackFull  (RNF0 holds ADDR_B in SC)\n", label);
        // RNF0 holds ADDR_B in SC -> SnpMakeInvalid issued on our ReadUnique.
        do_read_unique    (ADDR_B, rbuf);            // I->UC (SnpMakeInvalid->RNF0: SC->I)
        CHK(label, "Ph17 coherent ReadUnique", rbuf, data_b);
        do_write_back_full(ADDR_B);                  // UC->I (write back to memory)
        do_read           (ADDR_B, rbuf);            // I->SC (verify data persisted)
        CHK(label, "Ph17 WriteBackFull persists data", rbuf, data_b);
        do_clean_invalid  (ADDR_B);                  // SC->I

        // ── Ph18: Coherent ReadOnce on remote-cached line ─────────────────────
        // Re-seed ADDR_A from RNF1 side, then issue ReadOnce.  ReadOnce should
        // return data without touching the snoop filter (no snoop to RNF0).
        printf("\n[%s] == Ph18 == ReadOnce + ReadNoSnp (non-allocating reads)\n", label);
        do_write          (ADDR_C, data_b);          // seed at non-overlapping addr
        do_read_once      (ADDR_C, rbuf);
        CHK(label, "Ph18 ReadOnce", rbuf, data_b);
        do_read_no_snp    (ADDR_C, rbuf, true);
        CHK(label, "Ph18 ReadNoSnp", rbuf, data_b);
        do_clean_invalid  (ADDR_C);

        // ── Ph19: Coherent CleanInvalid on remote-cached line ─────────────────
        // RNF1 issues CleanInvalid on a line RNF0 still holds in some state.
        // HNF must snoop RNF0 (SnpCleanInvalid -> invalidate at remote) and
        // return Comp once the snoop response is back.  No CompAck required.
        printf("\n[%s] == Ph19 == CleanInvalid + Evict (snoop + drop)\n", label);
        do_write          (ADDR_C, data_c);          // baseline in memory
        do_read           (ADDR_C, rbuf);            // I->SC (RNF1 cached)
        CHK(label, "Ph19 ReadClean", rbuf, data_c);
        do_clean_unique   (ADDR_C);                  // SC->UC
        do_evict          (ADDR_C);                  // UC->I (RNF1 drops the line)
        do_read           (ADDR_C, rbuf);            // I->SC, re-fetch from memory
        CHK(label, "Ph19 data persists after Evict", rbuf, data_c);
        do_clean_invalid  (ADDR_C);

        printf("[%s] Ph16–19 complete — all non-interleaved tests done\n", label);

        // Tell RNF0 it can leave its snoop-service loop and join the
        // interleaved phases.
        g_rnf1_phases_done = true;

        // ════════════════════════════════════════════════════════════════════
        //  Interleaved tests — both RN-Fs issue concurrently after a barrier
        //  Each barrier uses a pair of polled flags; both sides tick while
        //  waiting so snoops and responses continue to be serviced.
        // ════════════════════════════════════════════════════════════════════

        // ── IL1: Concurrent WriteUniqueFull to *different* lines ──────────────
        printf("\n[%s] == IL1 == Concurrent WriteUniqueFull (RNF0->E, RNF1->F)\n", label);
        g_rnf1_at_il1 = true;
        while (!g_rnf0_at_il1) tick();
        do_write          (ADDR_F, data_f);
        do_read           (ADDR_F, rbuf);
        CHK(label, "IL1 ADDR_F persisted", rbuf, data_f);
        do_clean_invalid  (ADDR_F);

        // ── IL2: Concurrent ReadClean to *same* line (read–read race) ─────────
        // RNF0 seeds ADDR_D in memory and invalidates locally before the
        // barrier; both sides then race ReadClean.
        printf("\n[%s] == IL2 == Concurrent ReadClean to ADDR_D (read-read race)\n", label);
        g_rnf1_at_il2 = true;
        while (!g_rnf0_at_il2) tick();
        do_read           (ADDR_D, rbuf);
        CHK(label, "IL2 RNF1 ReadClean ADDR_D", rbuf, data_d);
        do_clean_invalid  (ADDR_D);

        // ── IL3: Concurrent CleanUnique to *same* line (upgrade race) ─────────
        // Take ADDR_A into SC before the barrier, then race the upgrade.
        // Whichever CleanUnique wins the MSHR allocation invalidates the other
        // via a snoop; the loser then proceeds through the cache-pipeline path
        // and also reaches UC at a later cycle.
        printf("\n[%s] == IL3 == Concurrent CleanUnique on ADDR_A (upgrade race)\n", label);
        do_read           (ADDR_A, rbuf);              // I->SC on RNF1
        g_rnf1_at_il3 = true;
        while (!g_rnf0_at_il3) tick();
        do_clean_unique   (ADDR_A);                    // race CleanUnique
        do_clean_invalid  (ADDR_A);

        // ── IL4: Concurrent ReadUnique to same line (ADDR_B) ──────────────────
        printf("\n[%s] == IL4 == Concurrent ReadUnique to ADDR_B (R4O race)\n", label);
        g_rnf1_at_il4 = true;
        while (!g_rnf0_at_il4) tick();
        do_read_unique    (ADDR_B, rbuf);              // race ReadUnique
        CHK(label, "IL4 RNF1 ReadUnique data", rbuf, data_b);
        do_clean_invalid  (ADDR_B);

        // ── IL5: Concurrent WriteUniqueFull to same address (ADDR_C) ──────────
        // RNF1 writes data_b; race against RNF0 writing data_a.  No readback
        // on this side — RNF0 verifies that the final value is one of {a, b}.
        printf("\n[%s] == IL5 == Concurrent WriteUniqueFull to ADDR_C (write-write race)\n", label);
        g_rnf1_at_il5 = true;
        while (!g_rnf0_at_il5) tick();
        do_write          (ADDR_C, data_b);            // RNF1 writes data_b

        // ── IL6: Concurrent ReadOnce to same line (ADDR_D) ────────────────────
        printf("\n[%s] == IL6 == Concurrent ReadOnce to ADDR_D (no-coherence race)\n", label);
        g_rnf1_at_il6 = true;
        while (!g_rnf0_at_il6) tick();
        do_read_once      (ADDR_D, rbuf);              // race ReadOnce
        CHK(label, "IL6 RNF1 ReadOnce ADDR_D", rbuf, data_d);

        // ── IL7: WriteUniqueFull(RNF1) racing RNF0 ReadClean on ADDR_E ────────
        // RNF1 writes data_a so the read on RNF0 may see either data_e or data_a.
        printf("\n[%s] == IL7 == ReadClean(RNF0) || WriteUniqueFull(RNF1) on ADDR_E\n", label);
        g_rnf1_at_il7 = true;
        while (!g_rnf0_at_il7) tick();
        do_write          (ADDR_E, data_a);            // RNF1 races the write

        // ── IL8: Cross-address burst — RNF1 writes/reads D/E/F ────────────────
        printf("\n[%s] == IL8 == Cross-address burst (RNF0: A/B/C, RNF1: D/E/F)\n", label);
        g_rnf1_at_il8 = true;
        while (!g_rnf0_at_il8) tick();
        do_write          (ADDR_D, data_d);
        do_write          (ADDR_E, data_e);
        do_write          (ADDR_F, data_f);
        do_read           (ADDR_D, rbuf); CHK(label, "IL8 RNF1 ADDR_D", rbuf, data_d);
        do_read           (ADDR_E, rbuf); CHK(label, "IL8 RNF1 ADDR_E", rbuf, data_e);
        do_read           (ADDR_F, rbuf); CHK(label, "IL8 RNF1 ADDR_F", rbuf, data_f);
        do_clean_invalid  (ADDR_D);
        do_clean_invalid  (ADDR_E);
        do_clean_invalid  (ADDR_F);

        // ── IL9: ReadClean(RNF1) racing RNF0 WriteBackFull on ADDR_F ──────────
        // Either RNF1 reads stale memory then RNF0 writes back, or RNF1's read
        // snoops RNF0 mid-WB.  Either way RNF1 must end up with data_f.
        printf("\n[%s] == IL9 == WriteBackFull(RNF0,UC) || ReadClean(RNF1) on ADDR_F\n", label);
        g_rnf1_at_il9 = true;
        while (!g_rnf0_at_il9) tick();
        do_read           (ADDR_F, rbuf);              // race the read
        CHK(label, "IL9 RNF1 ReadClean ADDR_F", rbuf, data_f);
        do_clean_invalid  (ADDR_F);

        // ── IL10: RNF1 WriteBackFull(ADDR_E) ──────────────────────────────────
        printf("\n[%s] == IL10 == Concurrent WriteBackFull (RNF0→D, RNF1→E)\n", label);
        do_write          (ADDR_E, data_e);
        do_read           (ADDR_E, rbuf);
        do_clean_unique   (ADDR_E);                    // SC→UC on RNF1
        g_rnf1_at_il10 = true;
        while (!g_rnf0_at_il10) tick();
        do_write_back_full(ADDR_E);                    // UC→I (race WB)
        do_read           (ADDR_E, rbuf);
        CHK(label, "IL10 RNF1 ADDR_E persists", rbuf, data_e);
        do_clean_invalid  (ADDR_E);

        // ── IL11: Concurrent CleanInvalid to ADDR_A ───────────────────────────
        printf("\n[%s] == IL11 == Concurrent CleanInvalid to ADDR_A\n", label);
        do_read           (ADDR_A, rbuf);              // I→SC on RNF1
        g_rnf1_at_il11 = true;
        while (!g_rnf0_at_il11) tick();
        do_clean_invalid  (ADDR_A);                    // race CleanInvalid

        // ── IL12: RNF1 Evict(ADDR_C) ──────────────────────────────────────────
        printf("\n[%s] == IL12 == Concurrent Evict (RNF0→B, RNF1→C)\n", label);
        do_write          (ADDR_C, data_c);
        do_read           (ADDR_C, rbuf);
        do_clean_unique   (ADDR_C);                    // SC→UC on RNF1
        g_rnf1_at_il12 = true;
        while (!g_rnf0_at_il12) tick();
        do_evict          (ADDR_C);                    // UC→I (race Evict)
        do_clean_invalid  (ADDR_C);

        // ── IL13: RNF1 pipelined sequence on ADDR_E ───────────────────────────
        printf("\n[%s] == IL13 == Pipelined sequence (W/R/CU/CI) on disjoint lines\n", label);
        g_rnf1_at_il13 = true;
        while (!g_rnf0_at_il13) tick();
        do_write          (ADDR_E, data_e);
        do_read           (ADDR_E, rbuf); CHK(label, "IL13 RNF1 ADDR_E read", rbuf, data_e);
        do_clean_unique   (ADDR_E);
        do_clean_invalid  (ADDR_E);

        // ── IL14: Ping-pong UC ownership on ADDR_F (RNF1 leg) ─────────────────
        // RNF1 grabs UC three times, alternating with RNF0.  Each ReadUnique
        // snoops the other RN-F if it holds the line in any non-I state.
        printf("\n[%s] == IL14 == Ping-pong UC ownership on ADDR_F (RNF1 leg)\n", label);
        g_rnf1_at_il14 = true;
        while (!g_rnf0_at_il14) tick();
        for (int i = 0; i < 3; i++) {
            do_read_unique (ADDR_F, rbuf);             // I→UC (snoops RNF0 if it held)
        }
        do_clean_invalid  (ADDR_F);

        // ── IL15: Concurrent MakeUnique to ADDR_A ─────────────────────────────
        printf("\n[%s] == IL15 == Concurrent MakeUnique to ADDR_A (UCE race)\n", label);
        g_rnf1_at_il15 = true;
        while (!g_rnf0_at_il15) tick();
        do_make_unique    (ADDR_A);                    // race MakeUnique
        do_clean_invalid  (ADDR_A);

        // ── IL16: Consumer side — repeated ReadClean to ADDR_B ────────────────
        // Each read must return a complete value of either data_a or data_b
        // (whichever write was last-committed at the HNF when the read fired).
        printf("\n[%s] == IL16 == Producer(RNF0) / Consumer(RNF1) on ADDR_B (4x)\n", label);
        g_rnf1_at_il16 = true;
        while (!g_rnf0_at_il16) tick();
        for (int i = 0; i < 4; i++) {
            do_read         (ADDR_B, rbuf);
            bool ok = (memcmp(rbuf, data_a, 64) == 0) ||
                      (memcmp(rbuf, data_b, 64) == 0);
            printf("[%s] IL16 RNF1 read %d (saw %s)\n",
                   ok ? "PASS" : "FAIL", i,
                   (memcmp(rbuf, data_a, 64) == 0) ? "data_a" :
                   (memcmp(rbuf, data_b, 64) == 0) ? "data_b" : "MIX");
            do_clean_invalid(ADDR_B);
        }

        // ── IL17: RNF1 reads ADDR_D in parallel with RNF0 reading ADDR_C ──────
        printf("\n[%s] == IL17 == Concurrent ReadClean to disjoint lines (3 rounds)\n", label);
        g_rnf1_at_il17 = true;
        while (!g_rnf0_at_il17) tick();
        for (int i = 0; i < 3; i++) {
            do_read         (ADDR_D, rbuf); CHK(label, "IL17 RNF1 ADDR_D", rbuf, data_d);
            do_clean_invalid(ADDR_D);
        }

        // ── IL18: RNF1 partial second-half write — DISABLED ───────────────────
        // WriteUniquePtl stress-test disabled pending partial-merge fix.
#if 0
        printf("\n[%s] == IL18 == Concurrent WriteUniquePtl (RNF0→E:first-half, RNF1→F:second-half)\n", label);
        g_rnf1_at_il18 = true;
        while (!g_rnf0_at_il18) tick();
        do_write_unique_ptl(ADDR_F, data_f, 0x0000'0000u, 0xFFFF'FFFFu);
        do_read           (ADDR_F, rbuf);
        {
            bool ok0 = (memcmp(rbuf,         data_a,        32) == 0);
            bool ok1 = (memcmp(rbuf + 32,    data_f + 32,   32) == 0);
            printf("[%s] IL18 RNF1 second-half merge ADDR_F\n", (ok0 && ok1) ? "PASS" : "FAIL");
        }
        do_clean_invalid  (ADDR_F);
#endif

        // ── IL19: Ownership chain on ADDR_D (RNF1 leg) ────────────────────────
        // RNF1 reads ADDR_D *after* RNF0 has taken UC; this generates a snoop
        // to RNF0 (UC→SC).  Then RNF0's later CleanUnique will snoop RNF1.

        printf("\n[%s] == IL19 == Ownership chain on ADDR_D (RNF1 leg)\n", label);
        g_rnf1_at_il19 = true;
        while (!g_rnf0_at_il19) tick();
        do_read           (ADDR_D, rbuf);              // I→SC (snoops RNF0 UC→SC)
        CHK(label, "IL19 RNF1 sees RNF0's data", rbuf, data_d);
        // Hold the line in SC; RNF0 will snoop us via its CleanUnique.
        tick(200);                                     // give RNF0 time to snoop
        do_clean_invalid  (ADDR_D);

        // ── IL20: AtomicLoad on a peer-held line (RNF1 leg) ───────────────────
        // RNF0 has ADDR_E in UC.  We issue AtomicLoad_ADD; the HN-F must
        // snoop RNF0 (SF reports a holder), then RMW against memory, then
        // return OLD to us.  OLD must match what RNF0 had cached, and
        // RNF0's local copy must be invalidated.
        printf("\n[%s] == IL20 == Coherent atomic on peer-held line (RNF1 leg)\n", label);
        g_rnf1_at_il20 = true;
        while (!g_rnf0_at_il20) tick();
        tick(50);
        {
            uint64_t old_ret = 0;
            const uint64_t op = 0x44ull;
            do_atomic_load_add(ADDR_E, op, &old_ret);
            uint64_t seedE = 0; memcpy(&seedE, data_e, 8);
            printf("[%s] IL20 atomic returned old=0x%016lx expected=0x%016lx %s\n",
                   label, (unsigned long)old_ret, (unsigned long)seedE,
                   (old_ret == seedE) ? "PASS" : "FAIL");
        }

        printf("[%s] IL1-20 complete - interleaved tests done\n", label);

        // Drain a few hundred cycles so any in-flight RSPs/DATs settle.
        tick(20000000);

        sc_stop();
    }

#undef CHK
#undef CHK_N
}

// Register with Questa's vsim elaboration engine so that SV hierarchy
// instances of "chi_tlm_rnf" are bound to this SC class at runtime.
SC_MODULE_EXPORT(chi_tlm_rnf);
