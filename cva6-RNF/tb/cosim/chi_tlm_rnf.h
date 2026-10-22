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
 * chi_tlm_rnf.h — CHI-E TLM RN-F packet injector for pure Questa SV+SC co-simulation.
 *
 * Fixed parameters (must match rnf_param.v defaults):
 *   NID_W=7  TXNID_W=12  ADDR_W=44  SNP_ADDR_W=41
 *   DATA_W=256  BE_W=32  DATACHECK=0  POISON=0  RSVDC=0
 *
 * Flit widths:
 *   REQ = ADDR_W + NID_W*3 + 66         = 44+21+66 = 131
 *   RSP = NID_W*2 + 51                  = 14+51    =  65
 *   DAT = NID_W*3 + DATA_W + BE_W
 *         + DATA_W/32 + DATA_W/128 + 51 = 21+256+32+8+2+51 = 370
 *   SNP = SNP_ADDR_W + NID_W*3 + 37     = 41+21+37 =  99
 *
 * Compile flow (from cva6-RNF/ directory):
 *
 *   QUESTA=/path/to/questa
 *   vlib questa_build/work
 *   cd questa_build
 *
 *   sccom -suppress sccom-94 -O2 -std=c++14 -I../tb \
 *       ../tb/cosim/chi_tlm_rnf.cpp
 *
 *   g++ -std=c++14 -shared -fPIC -o work/systemc.so \
 *       work/_sc/linux_x86_64_gcc-<ver>/chi_tlm_rnf.o \
 *       $QUESTA/linux_x86_64/libsystemc_gcc103.a -lrt
 *   (replace <ver> with the gcc version suffix sccom created, or use $(...) shell glob)
 *
 *   vlog -work work -mfcu -suppress 2583 -f ../tb/cosim/chi_tlm_flist
 *   vsim -c work.tlm_rnf_hnf_tb -do "run -all"
 */

#pragma once
#include <systemc.h>
#include <cstdint>
#include <cstring>

// ── CHI cache states ──────────────────────────────────────────────────────────
enum class ChiState { I, SC, UC, UD, SD, UCE };

inline const char* chi_state_str(ChiState s) {
    switch (s) {
    case ChiState::I:   return "I";
    case ChiState::SC:  return "SC";
    case ChiState::UC:  return "UC";
    case ChiState::UD:  return "UD";
    case ChiState::SD:  return "SD";
    case ChiState::UCE: return "UCE";
    }
    return "?";
}

// ── Cache geometry ─────────────────────────────────────────────────────────────
static constexpr int CACHE_SETS       = 64;
static constexpr int CACHE_WAYS       = 4;
static constexpr int CACHE_BLOCK_BITS = 6;    // 64-byte lines
static constexpr int CACHE_SET_BITS   = 6;    // log2(CACHE_SETS)

// ── Data-beat width (bridge-adapter config) ──────────────────────────────────
// The CHI-E link's DAT-channel data field is configurable per SoC
// (spec §10.1.4).  Setting CHI_DATA_BEAT_BITS re-derives every flit
// field position so the entire SC bridge, the SV port stub, and the
// downstream ICN/monitor/HN-F all agree on the wire shape — matching
// the RTL's own CHIE_DATA_WIDTH_PARAM knob.
//
// Supported values: 128, 256 (default), 512.  A 64-byte cacheline is
// assembled from BEATS_PER_LINE consecutive beats:
//   128b beat → 4 beats/line, DataID stride 1 → {0,1,2,3}
//   256b beat → 2 beats/line, DataID stride 2 → {0,2}     (current)
//   512b beat → 1 beat/line,  DataID stride 4 → {0}
#ifndef CHI_DATA_BEAT_BITS
#define CHI_DATA_BEAT_BITS 256
#endif
static_assert(CHI_DATA_BEAT_BITS == 128 ||
              CHI_DATA_BEAT_BITS == 256 ||
              CHI_DATA_BEAT_BITS == 512,
              "CHI_DATA_BEAT_BITS must be 128, 256, or 512");
static constexpr int CHI_DATA_BEAT_BYTES = CHI_DATA_BEAT_BITS / 8;
static constexpr int CHI_LINE_BYTES      = 64;
static constexpr int BEATS_PER_LINE      = CHI_LINE_BYTES / CHI_DATA_BEAT_BYTES;
static constexpr int DATAID_STEP         = 4 / BEATS_PER_LINE;
// BE field width is CHIE_BE_WIDTH_PARAM = 32 bits in this TB.  Beats
// narrower than 32B only use the low CHI_DATA_BEAT_BYTES BE bits; a
// 512b beat needs 64 BE bits and the RTL matches the beat width — see
// mk_dat / do_write_unique_ptl handling.
static constexpr uint32_t BE_FULL_BEAT   =
    (CHI_DATA_BEAT_BYTES >= 32) ? 0xFFFF'FFFFu
                                : ((1u << CHI_DATA_BEAT_BYTES) - 1u);

// ── Flit widths ───────────────────────────────────────────────────────────────
// Match chie_defines.v macros (TB config: NID=7, POISON=DATACHECK=RSVDC=0,
// BE=32, ADDR=44, SNPADDR=41).  REQ/RSP/SNP don't depend on DATA_WIDTH.
static constexpr int CHI_REQ_W = 131;
static constexpr int CHI_RSP_W =  65;
static constexpr int CHI_SNP_W =  99;
// CHIE_DAT_FLIT_WIDTH = NID*3 + POISON + DATACHECK + DATA + BE
//                     + DATA/32 + DATA/128 + RSVDC + 51
//                   = 21 + 0 + 0 + D + 32 + D/32 + D/128 + 0 + 51
//                   = 104 + D + D/32 + D/128
// Verify:  D=128 → 237,  D=256 → 370,  D=512 → 636.
static constexpr int CHI_DAT_W =
    104 + CHI_DATA_BEAT_BITS
        + CHI_DATA_BEAT_BITS / 32
        + CHI_DATA_BEAT_BITS / 128;

// Field bit positions in the DAT flit (all shift as DATA_WIDTH scales).
// CHIE_DAT_FLIT_BE_LSB = NID*3 + DATA/32 + DATA/128 + RSVDC + 51
static constexpr int DAT_BE_LSB   =
    21 + CHI_DATA_BEAT_BITS / 32 + CHI_DATA_BEAT_BITS / 128 + 51;
static constexpr int DAT_BE_MSB   = DAT_BE_LSB + 32 - 1;
static constexpr int DAT_DATA_LSB = DAT_BE_MSB + 1;
static constexpr int DAT_DATA_MSB = DAT_DATA_LSB + CHI_DATA_BEAT_BITS - 1;

// ── REQ field bit positions (NID_W=7, ADDR_W=44) ─────────────────────────────
// [3:0]     QOS          [10:4]    TgtID        [17:11]   SrcID
// [29:18]   TxnID        [36:30]   ReturnNID    [37]      StashNIDValid
// [49:38]   ReturnTxnID  [56:50]   Opcode       [59:57]   Size
// [103:60]  Addr         [104]     NS           [105]     LikelyShared
// [106]     AllowRetry   [108:107] Order        [112:109] PCrdType
// [116:113] MemAttr      [117]     SnpAttr      [125:118] LPID
// [126]     Excl         [127]     ExpCompAck   [129:128] TagOp
// [130]     TraceTag

// ── RSP field bit positions (NID_W=7) ─────────────────────────────────────────
// [3:0]   QOS      [10:4]  TgtID    [17:11] SrcID   [29:18] TxnID
// [34:30] Opcode   [36:35] RespErr  [39:37] Resp    [42:40] FwdState
// [45:43] CBusy    [57:46] DBID     [61:58] PCrdType [63:62] TagOp  [64] TraceTag

// ── DAT field bit positions (NID_W=7, DATA_W=256, BE_W=32) ───────────────────
// [3:0]   QOS      [10:4]  TgtID    [17:11] SrcID    [29:18] TxnID
// [36:30] HomeNID  [40:37] Opcode   [42:41] RespErr   [45:43] Resp
// [49:46] DataSrc  [52:50] CBusy    [64:53] DBID      [66:65] CCID
// [68:67] DataID   [70:69] TagOp    [78:71] Tag(8b)   [80:79] TU(2b)
// [81]    TraceTag [113:82] BE(32b) [369:114] Data(256b)

// ── SNP field bit positions (NID_W=7, SNP_ADDR_W=41) ─────────────────────────
// [3:0]   QOS      [10:4]  SrcID    [22:11] TxnID    [29:23] FwdNID
// [41:30] FwdTxnID [46:42] Opcode   [87:47] Addr(41b) [88] NS
// [89]    DoNotGoToSD [90] RetToSrc [91] TraceTag    [98:92] TgtID

// ── REQ opcodes ──────────────────────────────────────────────────────────────
// Values match cva6-RNF/cache/include/chie_defines.v (HNF parser is authoritative).
// The 7-bit opcode field is opcode[6:0]; opcodes with bit[6]=1 are CHI-E extensions.
// "supported" = listed in the HNF rxreq parser allow-list.
static constexpr int CHI_OP_REQLCRDRETURN              = 0x00;
static constexpr int CHI_OP_READSHARED                 = 0x01;  // NOT supported by HNF
static constexpr int CHI_OP_READCLEAN                  = 0x02;
static constexpr int CHI_OP_READONCE                   = 0x03;
static constexpr int CHI_OP_READNOSNP                  = 0x04;
static constexpr int CHI_OP_PCRDRETURN                 = 0x05;
static constexpr int CHI_OP_READUNIQUE                 = 0x07;
static constexpr int CHI_OP_CLEANSHARED                = 0x08;  // dataless
static constexpr int CHI_OP_CLEANINVALID               = 0x09;  // dataless
static constexpr int CHI_OP_MAKEINVALID                = 0x0a;  // dataless
static constexpr int CHI_OP_CLEANUNIQUE                = 0x0b;  // dataless
static constexpr int CHI_OP_MAKEUNIQUE                 = 0x0c;  // dataless
static constexpr int CHI_OP_EVICT                      = 0x0d;
static constexpr int CHI_OP_READNOSNPSEP               = 0x11;
static constexpr int CHI_OP_CLEANSHAREDPERSISTSEP      = 0x13;
static constexpr int CHI_OP_DVMOP                      = 0x14;
static constexpr int CHI_OP_WRITEEVICTFULL             = 0x15;
static constexpr int CHI_OP_WRITECLEANFULL             = 0x17;
static constexpr int CHI_OP_WRITEUNIQUEPTL             = 0x18;
static constexpr int CHI_OP_WRITEUNIQUEFULL            = 0x19;
static constexpr int CHI_OP_WRITEBACKPTL               = 0x1a;
static constexpr int CHI_OP_WRITEBACKFULL              = 0x1b;
static constexpr int CHI_OP_WRITENOSNPPTL              = 0x1c;
static constexpr int CHI_OP_WRITENOSNPFULL             = 0x1d;
static constexpr int CHI_OP_WRITEUNIQUEFULLSTASH       = 0x20;
static constexpr int CHI_OP_WRITEUNIQUEPTLSTASH        = 0x21;
static constexpr int CHI_OP_STASHONCESHARED            = 0x22;
static constexpr int CHI_OP_STASHONCEUNIQUE            = 0x23;
static constexpr int CHI_OP_READONCECLEANINVALID       = 0x24;
static constexpr int CHI_OP_READONCEMAKEINVALID        = 0x25;
static constexpr int CHI_OP_READNOTSHAREDDIRTY         = 0x26;
static constexpr int CHI_OP_CLEANSHAREDPERSIST         = 0x27;
static constexpr int CHI_OP_ATOMICSTORE_ADD            = 0x28;
static constexpr int CHI_OP_ATOMICSTORE_CLR            = 0x29;
static constexpr int CHI_OP_ATOMICSTORE_EOR            = 0x2a;
static constexpr int CHI_OP_ATOMICSTORE_SET            = 0x2b;
static constexpr int CHI_OP_ATOMICSTORE_SMAX           = 0x2c;
static constexpr int CHI_OP_ATOMICSTORE_SMIN           = 0x2d;
static constexpr int CHI_OP_ATOMICSTORE_UMAX           = 0x2e;
static constexpr int CHI_OP_ATOMICSTORE_UMIN           = 0x2f;
static constexpr int CHI_OP_ATOMICLOAD_ADD             = 0x30;
static constexpr int CHI_OP_ATOMICLOAD_CLR             = 0x31;
static constexpr int CHI_OP_ATOMICLOAD_EOR             = 0x32;
static constexpr int CHI_OP_ATOMICLOAD_SET             = 0x33;
static constexpr int CHI_OP_ATOMICLOAD_SMAX            = 0x34;
static constexpr int CHI_OP_ATOMICLOAD_SMIN            = 0x35;
static constexpr int CHI_OP_ATOMICLOAD_UMAX            = 0x36;
static constexpr int CHI_OP_ATOMICLOAD_UMIN            = 0x37;
static constexpr int CHI_OP_ATOMICSWAP                 = 0x38;
static constexpr int CHI_OP_ATOMICCOMPARE              = 0x39;
// Extended opcodes (bit[6]=1)
static constexpr int CHI_OP_MAKEREADUNIQUE             = 0x41;
static constexpr int CHI_OP_WRITEEVICTOREVICT          = 0x42;
static constexpr int CHI_OP_WRITEUNIQUEZERO            = 0x43;
static constexpr int CHI_OP_WRITENOSNPZERO             = 0x44;
static constexpr int CHI_OP_STASHONCESEPSHARED         = 0x47;
static constexpr int CHI_OP_STASHONCESEPUNIQUE         = 0x48;
static constexpr int CHI_OP_READPREFERUNIQUE           = 0x4c;
static constexpr int CHI_OP_WRITENOSNPFULLCLEANSH      = 0x50;
static constexpr int CHI_OP_WRITENOSNPFULLCLEANINV     = 0x51;
static constexpr int CHI_OP_WRITENOSNPFULLCLEANSHPERSEP= 0x52;
static constexpr int CHI_OP_WRITEUNIQUEFULLCLEANSH     = 0x54;
static constexpr int CHI_OP_WRITEUNIQUEFULLCLEANSHPERSEP=0x56;
static constexpr int CHI_OP_WRITEBACKFULLCLEANSH       = 0x58;
static constexpr int CHI_OP_WRITEBACKFULLCLEANINV      = 0x59;
static constexpr int CHI_OP_WRITEBACKFULLCLEANSHPERSEP = 0x5a;
static constexpr int CHI_OP_WRITECLEANFULLCLEANSH      = 0x5c;
static constexpr int CHI_OP_WRITECLEANFULLCLEANSHPERSEP= 0x5e;
static constexpr int CHI_OP_WRITENOSNPPTLCLEANSH       = 0x60;
static constexpr int CHI_OP_WRITENOSNPPTLCLEANINV      = 0x61;
static constexpr int CHI_OP_WRITENOSNPPTLCLEANSHPERSEP = 0x62;
static constexpr int CHI_OP_WRITEUNIQUEPTLCLEANSH      = 0x64;
static constexpr int CHI_OP_WRITEUNIQUEPTLCLEANSHPERSEP= 0x66;
// Back-compat aliases (legacy name with typo and dropped "D")
static constexpr int CHI_OP_READNOTSHAREDIRTY          = CHI_OP_READNOTSHAREDDIRTY;

// ── RSP opcodes ──────────────────────────────────────────────────────────────
static constexpr int CHI_OP_RSPLCRDRETURN              = 0x00;
static constexpr int CHI_OP_SNPRESP                    = 0x01;
static constexpr int CHI_OP_COMPACK                    = 0x02;
static constexpr int CHI_OP_RETRYACK                   = 0x03;
static constexpr int CHI_OP_COMP                       = 0x04;
static constexpr int CHI_OP_COMPDBIDRESP               = 0x05;
static constexpr int CHI_OP_DBIDRESP                   = 0x06;
static constexpr int CHI_OP_PCRDGRANT                  = 0x07;
static constexpr int CHI_OP_READRECEIPT                = 0x08;
static constexpr int CHI_OP_SNPRESPFWDED               = 0x09;
static constexpr int CHI_OP_PERSIST                    = 0x0c;
static constexpr int CHI_OP_COMPPERSIST                = 0x0d;
static constexpr int CHI_OP_DBIDRESPORD                = 0x0e;
static constexpr int CHI_OP_STASHDONE                  = 0x10;
static constexpr int CHI_OP_COMPSTASHDONE              = 0x11;
static constexpr int CHI_OP_COMPCMO                    = 0x14;

// ── DAT opcodes ──────────────────────────────────────────────────────────────
static constexpr int CHI_OP_DATLCRDRETURN              = 0x0;
static constexpr int CHI_OP_SNPRESPDATA                = 0x1;
static constexpr int CHI_OP_COPYBACKWRDATA             = 0x2;
static constexpr int CHI_OP_NONCOPYBACKWRDATA          = 0x3;
static constexpr int CHI_OP_COMPDATA                   = 0x4;
static constexpr int CHI_OP_SNPRESPDATAPTL             = 0x5;
static constexpr int CHI_OP_SNPRESPDATAFWDED           = 0x6;
static constexpr int CHI_OP_WRITEDATACANCEL            = 0x7;
static constexpr int CHI_OP_DATASEPRESP                = 0xb;
static constexpr int CHI_OP_NCBWRDATACOMPACK           = 0xc;
// Back-compat aliases (legacy short names)
static constexpr int CHI_OP_COPYBKWRDATA               = CHI_OP_COPYBACKWRDATA;
static constexpr int CHI_OP_NONCOPYBKWRDATA            = CHI_OP_NONCOPYBACKWRDATA;

// ── SNP opcodes ──────────────────────────────────────────────────────────────
static constexpr int CHI_SNP_OP_SNPLCRDRETURN          = 0x00;
static constexpr int CHI_SNP_OP_SNPSHARED              = 0x01;
static constexpr int CHI_SNP_OP_SNPCLEAN               = 0x02;
static constexpr int CHI_SNP_OP_SNPONCE                = 0x03;
static constexpr int CHI_SNP_OP_SNPNOTSHAREDDIRTY      = 0x04;
static constexpr int CHI_SNP_OP_SNPUNIQUESTASH         = 0x05;
static constexpr int CHI_SNP_OP_SNPMAKEINVALIDSTASH    = 0x06;
static constexpr int CHI_SNP_OP_SNPUNIQUE              = 0x07;
static constexpr int CHI_SNP_OP_SNPCLEANSHARED         = 0x08;
static constexpr int CHI_SNP_OP_SNPCLEANINVALID        = 0x09;
static constexpr int CHI_SNP_OP_SNPMAKEINVALID         = 0x0a;
static constexpr int CHI_SNP_OP_SNPSTASHUNIQUE         = 0x0b;
static constexpr int CHI_SNP_OP_SNPSTASHSHARED         = 0x0c;
static constexpr int CHI_SNP_OP_SNPDVMOP               = 0x0d;
static constexpr int CHI_SNP_OP_SNPQUERY               = 0x10;
static constexpr int CHI_SNP_OP_SNPSHAREDFWD           = 0x11;
static constexpr int CHI_SNP_OP_SNPCLEANFWD            = 0x12;
static constexpr int CHI_SNP_OP_SNPONCEFWD             = 0x13;
static constexpr int CHI_SNP_OP_SNPNOTSHAREDDIRTYFWD   = 0x14;
static constexpr int CHI_SNP_OP_SNPPREFERUNIQUE        = 0x15;
static constexpr int CHI_SNP_OP_SNPPREFERUNIQUEFWD     = 0x16;
static constexpr int CHI_SNP_OP_SNPUNIQUEFWD           = 0x17;

// ── SnpResp Resp field encoding ───────────────────────────────────────────────
// Used in RSP[39:37] when Opcode=SnpResp:  0=I, 1=SC, 2=UC, 6=SD+PD, 7=UD+PD
static constexpr int CHI_RESP_I  = 0;
static constexpr int CHI_RESP_SC = 1;
static constexpr int CHI_RESP_UC = 2;

// ── Cross-instance synchronisation event (notified by RNF0 after first write) ─
extern sc_event g_rnf0_write_done;

// ── Interleaved-test sync ────────────────────────────────────────────────────
// Polled flags (volatile, ticked while waiting) so both RN-Fs keep servicing
// snoops/responses on every cycle.  Each barrier uses a pair: each side sets
// its own flag, then ticks until the other side's flag is set.
extern volatile bool g_rnf1_phases_done;        // RNF1 → RNF0 (Ph16–19 done)
extern volatile bool g_rnf0_at_il1, g_rnf1_at_il1;
extern volatile bool g_rnf0_at_il2, g_rnf1_at_il2;
extern volatile bool g_rnf0_at_il3, g_rnf1_at_il3;
extern volatile bool g_rnf0_at_il4, g_rnf1_at_il4;
extern volatile bool g_rnf0_at_il5, g_rnf1_at_il5;
extern volatile bool g_rnf0_at_il6, g_rnf1_at_il6;
extern volatile bool g_rnf0_at_il7, g_rnf1_at_il7;
extern volatile bool g_rnf0_at_il8, g_rnf1_at_il8;
extern volatile bool g_rnf0_at_il9, g_rnf1_at_il9;
extern volatile bool g_rnf0_at_il10, g_rnf1_at_il10;
extern volatile bool g_rnf0_at_il11, g_rnf1_at_il11;
extern volatile bool g_rnf0_at_il12, g_rnf1_at_il12;
extern volatile bool g_rnf0_at_il13, g_rnf1_at_il13;
extern volatile bool g_rnf0_at_il14, g_rnf1_at_il14;
extern volatile bool g_rnf0_at_il15, g_rnf1_at_il15;
extern volatile bool g_rnf0_at_il16, g_rnf1_at_il16;
extern volatile bool g_rnf0_at_il17, g_rnf1_at_il17;
extern volatile bool g_rnf0_at_il18, g_rnf1_at_il18;
extern volatile bool g_rnf0_at_il19, g_rnf1_at_il19;

// Set by chi_set_rnf_verbose() (DPI-C, called from SV) when +rnf_verbose is
// active.  Controls whether chi_tlm_rnf instances emit per-step printf output.
extern bool g_rnf_verbose;

// ─────────────────────────────────────────────────────────────────────────────
SC_MODULE(chi_tlm_rnf) {

    // ── Ports ─────────────────────────────────────────────────────────────────
    sc_in<bool>              clk;
    sc_in<bool>              rstn;

    // TX channels (this RNF → HNF/ICN)
    sc_out<bool>             txreq_flitv,  txreq_flitpend;
    sc_out<sc_bv<CHI_REQ_W>> txreq_flit;
    sc_in<bool>              txreq_lcrdv;   // credit grant from ICN

    sc_out<bool>             txrsp_flitv,  txrsp_flitpend;
    sc_out<sc_bv<CHI_RSP_W>> txrsp_flit;
    sc_in<bool>              txrsp_lcrdv;

    sc_out<bool>             txdat_flitv,  txdat_flitpend;
    sc_out<sc_bv<CHI_DAT_W>> txdat_flit;
    sc_in<bool>              txdat_lcrdv;

    // RX channels (HNF/ICN → this RNF)
    sc_in<bool>              rxrsp_flitv,  rxrsp_flitpend;
    sc_in<sc_bv<CHI_RSP_W>>  rxrsp_flit;
    sc_out<bool>             rxrsp_lcrdv;  // credit grant to ICN

    sc_in<bool>              rxdat_flitv,  rxdat_flitpend;
    sc_in<sc_bv<CHI_DAT_W>>  rxdat_flit;
    sc_out<bool>             rxdat_lcrdv;

    sc_in<bool>              rxsnp_flitv,  rxsnp_flitpend;
    sc_in<sc_bv<CHI_SNP_W>>  rxsnp_flit;
    sc_out<bool>             rxsnp_lcrdv;

    // Link layer
    sc_out<bool>             txlinkactivereq;
    sc_in<bool>              txlinkactiveack;
    sc_in<bool>              rxlinkactivereq;
    sc_out<bool>             rxlinkactiveack;

    // ── Config (set in SC_CTOR via static counter) ────────────────────────────
    int         rnf_nid;
    int         hnf_nid;
    const char* label;

    // ── TX credit counters (incremented by ICN lcrdv pulses) ─────────────────
    int m_req_crd;
    int m_rsp_crd;
    int m_dat_crd;

    // ── Cache tag array ───────────────────────────────────────────────────────
    struct CacheLine {
        bool     valid;
        uint64_t tag;
        ChiState state;
        int      lru_tick;
        uint8_t  data[64];   // cached line data (valid when data_valid=true)
        bool     data_valid;
    };
    CacheLine m_cache[CACHE_SETS][CACHE_WAYS];
    int       m_lru_tick;

    // ── Pending transaction table ─────────────────────────────────────────────
    struct PendTxn {
        bool    active;
        bool    needs_compack; // set by issuer: queue CompAck when CompData arrives
        bool    dbid_rcvd;   // DBIDResp or CompDBIDResp received
        bool    comp_rcvd;   // Comp or CompDBIDResp received (or CompData complete)
        bool    retry_rcvd;  // RetryAck received
        int     dbid;        // DBID from DBIDResp/CompDBIDResp/Comp
        int     dat_tgt;    // target NID for write data (hnf_nid normally; snf_nid in DWT)
        int     homenid;     // HomeNID from CompData (for CompAck target)
        int     pcrdtype;    // from RetryAck (for PCrdReturn)
        // One flag per beat (up to 4).  Only slots [0..BEATS_PER_LINE-1]
        // are used at runtime; the array is oversized so the same layout
        // works for every supported beat width.
        bool    dat_rcvd[4];
        uint8_t data[CHI_LINE_BYTES];  // full assembled cacheline
        bool    compack_needed;
        int     compack_tgtid;
        int     compack_dbid;
    };
    PendTxn m_pend[64];  // indexed by txnid & 63
    int     m_next_txnid;

    // ── Pending snoop responses ───────────────────────────────────────────────
    struct SnpRspEntry { bool valid; int tgtid; int txnid; int resp; };
    SnpRspEntry m_snp_q[16];
    int         m_snp_head, m_snp_tail;

    // ── RX credit return counters ─────────────────────────────────────────────
    int m_rx_rsp_grants;
    int m_rx_dat_grants;
    int m_rx_snp_grants;

    // ── Methods ───────────────────────────────────────────────────────────────
    void run();
    void link_activate();
    void grant_initial_rx_credits();

    void tick(int n = 1);
    void process_rx();
    void drain_pending_rsp();
    void drive_rx_credits();

    void handle_snoop(sc_bv<CHI_SNP_W> f);
    void enqueue_snp_rsp(int tgtid, int txnid, int resp);

    sc_bv<CHI_REQ_W> mk_req(int opc, uint64_t addr, int txnid, bool exp_compack = false, int order = 0);
    sc_bv<CHI_RSP_W> mk_rsp(int opc, int tgtid, int txnid, int resp = 0);
    sc_bv<CHI_DAT_W> mk_dat(int opc, int tgtid, int txnid, int dataid, const uint8_t* d32,
                            uint32_t be = 0xFFFF'FFFFu, int resp = 0);

    // Cache management
    int      cache_find  (uint64_t addr);             // returns way or -1
    int      cache_alloc (uint64_t addr);             // LRU evict, return way
    ChiState cache_state (uint64_t addr);             // I if not present
    void     cache_update(uint64_t addr, ChiState s); // alloc on miss, invalidate on I

    // ── Test transactions (blocking) ──────────────────────────────────────────
    // Coherent reads
    void do_read                (uint64_t addr, uint8_t* out = nullptr); // ReadClean         → SC
    void do_read_unique         (uint64_t addr, uint8_t* out = nullptr); // ReadUnique        → UC
    void do_read_not_shared_dirty(uint64_t addr, uint8_t* out = nullptr);// ReadNotSharedDirty→ SC
    // Non-allocating / non-coherent reads (no cache state change)
    void do_read_once           (uint64_t addr, uint8_t* out = nullptr); // ReadOnce
    void do_read_no_snp         (uint64_t addr, uint8_t* out = nullptr, bool expcompack = false); // ReadNoSnp
    // Coherent writes
    void do_write               (uint64_t addr, const uint8_t* data64);  // WriteUniqueFull   → I
    void do_write_unique_ptl    (uint64_t addr, const uint8_t* data64,   // WriteUniquePtl    → I
                                 uint32_t be0, uint32_t be1);
    void do_write_back_full     (uint64_t addr);                         // WriteBackFull     → I
    // Non-coherent writes
    void do_write_no_snp_full   (uint64_t addr, const uint8_t* data64);  // WriteNoSnpFull
    void do_write_no_snp_ptl    (uint64_t addr, const uint8_t* data64,   // WriteNoSnpPtl
                                 uint32_t be0, uint32_t be1);
    // Atomics (8-byte granule; ExpCompAck=0).  Operand placed at bytes [0:7]
    // of the first DAT beat.  AtomicLoad returns the old value via CompData;
    // AtomicStore returns plain Comp.
    void do_atomic_load_add     (uint64_t addr, uint64_t operand,
                                 uint64_t* out_old = nullptr);  // AtomicLoad_ADD
    void do_atomic_store_add    (uint64_t addr, uint64_t operand); // AtomicStore_ADD
    void do_atomic_swap         (uint64_t addr, uint64_t swap_val,
                                 uint64_t* out_old = nullptr);  // AtomicSwap
    // Dataless
    void do_clean_unique        (uint64_t addr);  // SC→UC, ExpCompAck
    void do_clean_invalid       (uint64_t addr);  //  →I,   no CompAck
    void do_make_unique         (uint64_t addr);  // I→UCE, ExpCompAck
    void do_clean_shared        (uint64_t addr);  // hint: clean dirty copies, no CompAck
    void do_evict               (uint64_t addr);  // any→I, dataless evict hint to HNF

    // ── Constructor ───────────────────────────────────────────────────────────
    // Use explicit constructor (not SC_CTOR) so the body can live in .cpp
    // while SC_HAS_PROCESS can still register SC_THREAD there.
    explicit chi_tlm_rnf(::sc_core::sc_module_name nm);
};
