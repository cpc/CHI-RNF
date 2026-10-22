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
 * Author:
 * Abdesattar Kalache <abdesattar.kalache@tuni.fi>
 */


`timescale 1ns/1ps

//`include "rnf_param.v"
`include "rnf_defines.v"

//`include "hnf_param.v"
`include "hnf_defines.v"

//`include "snf_param.v"
`include "snf_defines.v"

`include "chie_defines.v"

// `define DEBUG 1
// `define TB_SNF 1
// `define TB_NO_MONITOR


module tb_chi_system;

  parameter int  CORE_COUNT = 2; //4;
  parameter real CLK_PERIOD = 10.0;

  parameter CHIE_REQ_ADDR_WIDTH_PARAM = 44;
  parameter CHIE_SNP_ADDR_WIDTH_PARAM = 41;
  parameter CHIE_NID_WIDTH_PARAM = 7;
  // Single RTL-side data-width knob. Drives BOTH the DUT (rnf_wrapper below) and
  // the beat adapter (BEATS_PER_LINE = 512/width, field offsets, chie_dat_s).
  // Override per-run with vsim -G <top>.CHIE_DATA_WIDTH_PARAM=<128|256|512>.
  parameter CHIE_DATA_WIDTH_PARAM = 512;
  // Byte-enables are 1 bit/byte, so BE MUST track DATA (width/8). Deriving it —
  // rather than a second hardcoded literal — is what keeps the two in lockstep:
  // a stale BE=32 against DATA=512 is exactly what misaligned every DAT field.
  parameter CHIE_BE_WIDTH_PARAM = CHIE_DATA_WIDTH_PARAM / 8;
  parameter CHIE_DATACHECK_WIDTH_PARAM = 0;
  parameter CHIE_POISON_WIDTH_PARAM = 0;
  parameter CHIE_REQ_RSVDC_WIDTH_PARAM = 0;
  parameter CHIE_DAT_RSVDC_WIDTH_PARAM = 0;
  parameter HNF_MSHR_RNF_NUM_PARAM = 4;
  parameter HNF_MSHR_RNI_NUM_PARAM = 0;
  parameter RNF_NID_LIST_PARAM = {7'd0, 7'd1, 7'd2, 7'd3};
  parameter RNI_NID_LIST_PARAM = {7'd64};
  parameter HNF_NID_PARAM = CORE_COUNT;
  parameter SNF_NID_PARAM = 32;
  parameter XP_LCRD_NUM_PARAM = 15;
  parameter HNF_SF_ENTRIES_NUM_PARAM = 131072;
  parameter HNF_SF_WAY_NUM_PARAM = 16;
  parameter HNF_MSHR_EXCL_RN_NUM_PARAM = 32;
  parameter HNF_MSHR_EXCL_RN_WIDTH_PARAM = 5;
  parameter HNF_MSHR_ENTRIES_NUM_PARAM = 32;
  parameter HNF_MSHR_ENTRIES_WIDTH_PARAM = 5;
  parameter HNF_L3_CACHE_SIZE_PARAM = 4096;
  parameter HNF_L3_WAY_NUM_PARAM = 16;

  // --- Global Signals ---
  logic clk;
  logic rst_n;
  logic clk_en;
  logic program_load_done;

  // --- Interconnect Wires (RNF side - Vectorized) ---
  // RX Path
  logic [CORE_COUNT-1:0]                      rnf_rxrspflitv, rnf_rxrspflitpend;
  logic [CORE_COUNT-1:0][`CHIE_RSP_FLIT_WIDTH-1:0] rnf_rxrspflit;
  logic [CORE_COUNT-1:0]                      rnf_rxdatflitv, rnf_rxdatflitpend;
  logic [CORE_COUNT-1:0][`CHIE_DAT_FLIT_WIDTH-1:0] rnf_rxdatflit;
  logic [CORE_COUNT-1:0]                      rnf_rxsnpflitv, rnf_rxsnpflitpend;
  logic [CORE_COUNT-1:0][`CHIE_SNP_FLIT_WIDTH-1:0] rnf_rxsnpflit;

  // TX Path
  logic [CORE_COUNT-1:0]                      rnf_txreqflitv, rnf_txreqflitpend;
  logic [CORE_COUNT-1:0][`CHIE_REQ_FLIT_WIDTH-1:0] rnf_txreqflit;
  logic [CORE_COUNT-1:0]                      rnf_txrspflitv, rnf_txrspflitpend;
  logic [CORE_COUNT-1:0][`CHIE_RSP_FLIT_WIDTH-1:0] rnf_txrspflit;
  logic [CORE_COUNT-1:0]                      rnf_txdatflitv, rnf_txdatflitpend;
  logic [CORE_COUNT-1:0][`CHIE_DAT_FLIT_WIDTH-1:0] rnf_txdatflit;

  // Link Credits
  logic [CORE_COUNT-1:0] rnf_txreqlcrdv, rnf_txrsplcrdv, rnf_txdatlcrdv;
  logic [CORE_COUNT-1:0] rnf_rxrsplcrdv, rnf_rxdatlcrdv, rnf_rxsnplcrdv;
  logic [CORE_COUNT-1:0] icn_rnf_rxsnppend, icn_rnf_rxdatpend, icn_rnf_rxrsppend;

  // --- Handshake Signals ---
  logic [CORE_COUNT-1:0] rnf_txlinkactivereq, rnf_txlinkactiveack;
  logic [CORE_COUNT-1:0] rnf_rxlinkactivereq, rnf_rxlinkactiveack;
  logic [CORE_COUNT-1:0] rnf_txactive, rnf_rxactive;


  // =========================================================================
  // HNF Bridge Signals — gem5 IPC co-simulation
  // ICN HNF port connects to questa_top_ipc_wrap via chi_flit_adapter.
  // Memory is internal to gem5; no SNF is instantiated.
  // =========================================================================

  // ICN → HNF direction (RNF requests forwarded by ICN to gem5 IPC)
  logic                        icn_hnf_rxreqflitv, icn_hnf_rxreqpend;
  logic [`CHIE_REQ_FLIT_RANGE] icn_hnf_rxreqflit;   // 131b RTL REQ
  logic                        icn_hnf_rxrspflitv, icn_hnf_rxrsppend;
  logic [`CHIE_RSP_FLIT_RANGE] icn_hnf_rxrspflit;   // 65b  RTL RSP
  logic                        icn_hnf_rxdatflitv, icn_hnf_rxdatpend;
  logic [`CHIE_DAT_FLIT_RANGE] icn_hnf_rxdatflit;   // 370b RTL DAT

  // HNF → ICN direction (gem5 IPC responses/snoops forwarded to ICN)
  // hnf_txreq* is tied off — gem5 has internal memory, no SNF ReadNoSnp needed
  logic                        hnf_txreqflitv, hnf_txreqpend;
  logic [`CHIE_REQ_FLIT_RANGE] hnf_txreqflit;
  logic                        hnf_txrspflitv, hnf_txrsppend;
  logic [`CHIE_RSP_FLIT_RANGE] hnf_txrspflit;       // 65b  RTL RSP (converted from IPC)
  logic                        hnf_txdatflitv, hnf_txdatpend;
  logic [`CHIE_DAT_FLIT_RANGE] hnf_txdatflit;       // 370b RTL DAT (split from IPC 512b)
  logic                        hnf_txsnpflitv, hnf_txsnppend;
  logic [`CHIE_SNP_FLIT_RANGE] hnf_txsnpflit;       // 92b  RTL SNP (converted from IPC)

  // Link credits
  logic hnf_rxreqlcrdv, hnf_rxrsplcrdv, hnf_rxdatlcrdv;  // IPC → ICN (TX credits)
  logic hnf_txreqlcrdv, hnf_txrsplcrdv, hnf_txdatlcrdv, hnf_txsnplcrdv; // ICN → IPC (RX credits)

  // ── IPC flit-width intermediates (gem5 side: 512-bit data, 12-bit TXNID) ──
  // These are FIXED by the gem5 chi_flit_cfg.hh contract — the SCC RN-F stub
  // and gem5's HN-F only speak 512b DAT flits regardless of the RTL side.
  localparam IPC_REQ_W = 117;
  localparam IPC_RSP_W =  64;
  localparam IPC_DAT_W = 645;
  localparam IPC_SNP_W = 103;  // SCC SNP flit: TGTID[102:96] TRACETAG[95] DONOTDATAPULL[94] RETTOSRC[93] DONOTGOTOSD[92] NS[91] ADDR[90:47] ...

  // ── RTL-side beat width derivations ─────────────────────────────────────
  // The RTL CHIE_DATA_WIDTH_PARAM (128/256/512) sets how many RTL DAT beats
  // the adapter must accumulate to form a full 64-byte (512-bit) cacheline
  // that the IPC side transports in one flit.
  //   RTL 128b → 4 beats/line, DataID stride 1 → {0,1,2,3}
  //   RTL 256b → 2 beats/line, DataID stride 2 → {0,2}     (baseline)
  //   RTL 512b → 1 beat/line,  DataID stride 4 → {0}
  localparam int BEATS_PER_LINE = 512 / CHIE_DATA_WIDTH_PARAM;
  localparam int DATAID_STEP    = 4   / BEATS_PER_LINE;
  // Field bit positions in the RTL DAT flit that shift with DATA_WIDTH.
  // Mirror the chie_defines.v macros so the adapter tracks the RTL layout.
  localparam int RTL_DAT_BE_LSB       = CHIE_NID_WIDTH_PARAM*3
                                      + CHIE_DATA_WIDTH_PARAM/32
                                      + CHIE_DATA_WIDTH_PARAM/128
                                      + CHIE_DAT_RSVDC_WIDTH_PARAM + 51;
  localparam int RTL_DAT_BE_MSB       = RTL_DAT_BE_LSB + CHIE_BE_WIDTH_PARAM - 1;
  localparam int RTL_DAT_DATA_LSB     = RTL_DAT_BE_MSB + 1;
  localparam int RTL_DAT_DATA_MSB     = RTL_DAT_DATA_LSB + CHIE_DATA_WIDTH_PARAM - 1;
  localparam int RTL_DAT_TRACETAG_LSB = CHIE_NID_WIDTH_PARAM*3
                                      + CHIE_DATA_WIDTH_PARAM/32
                                      + CHIE_DATA_WIDTH_PARAM/128 + 50;
  // Per-beat sizes (in bits) for the payload/BE slots inside the IPC flit.
  localparam int IPC_BEAT_DATA_BITS   = CHIE_DATA_WIDTH_PARAM;
  localparam int IPC_BEAT_BE_BITS     = CHIE_BE_WIDTH_PARAM;

  logic [IPC_REQ_W-1:0] ipc_txreq_flit;
  logic                 ipc_txreq_flitv, ipc_txreq_flitpend;
  logic [IPC_RSP_W-1:0] ipc_txrsp_flit;
  logic                 ipc_txrsp_flitv, ipc_txrsp_flitpend;
  logic [IPC_DAT_W-1:0] ipc_txdat_flit;
  logic                 ipc_txdat_flitv, ipc_txdat_flitpend;

  logic [IPC_RSP_W-1:0] ipc_rxrsp_flit;
  logic                 ipc_rxrsp_flitv, ipc_rxrsp_flitpend, ipc_rxrsp_lcrdv;
  logic [IPC_DAT_W-1:0] ipc_rxdat_flit;
  logic                 ipc_rxdat_flitv, ipc_rxdat_flitpend, ipc_rxdat_lcrdv;
  logic [IPC_SNP_W-1:0] ipc_rxsnp_flit;
  logic                 ipc_rxsnp_flitv, ipc_rxsnp_flitpend, ipc_rxsnp_lcrdv;

  // ── DAT TX buffer: BEATS_PER_LINE × RTL flits → 1 × 512b IPC flit ─────
  // Per-transaction: keyed by {srcid, txnid} so ICN reordering across
  // concurrent transactions is handled correctly.  Each slot accumulates
  // the DATA/BE bytes as beats arrive; when every beat_slot in the
  // BEATS_PER_LINE-bit mask has fired, the IPC flit is emitted.
  localparam DAT_TX_BUF_DEPTH = 16;
  logic [`CHIE_DAT_FLIT_WIDTH-1:0] dat_tx_first_hdr [DAT_TX_BUF_DEPTH];
  logic [511:0]                    dat_tx_data      [DAT_TX_BUF_DEPTH]; // accumulated 64B payload
  logic [63:0]                     dat_tx_be        [DAT_TX_BUF_DEPTH]; // accumulated 64-bit BE
  logic [18:0]                     dat_tx_keys      [DAT_TX_BUF_DEPTH]; // {srcid[6:0], txnid[11:0]}
  logic [BEATS_PER_LINE-1:0]       dat_tx_masks     [DAT_TX_BUF_DEPTH]; // beat-received mask
  logic [DAT_TX_BUF_DEPTH-1:0]     dat_tx_valids;                       // slot in use
  logic [IPC_DAT_W-1:0]            dat_tx_assembled;
  logic                             dat_tx_assembled_vld;

  // ── DAT RX split: 1 × 512b IPC flit → BEATS_PER_LINE × RTL flits ──────
  // Counter-based FSM: latch the IPC flit, then emit one RTL beat per
  // cycle for BEATS_PER_LINE cycles.  DataID = beat_idx * DATAID_STEP.
  logic [IPC_DAT_W-1:0]                    dat_rx_latch;
  logic                                    dat_rx_busy;
  logic [$clog2(BEATS_PER_LINE+1)-1:0]     dat_rx_beat_idx;

  // ── ICN SNF port tie-off (gem5 is memory; SNF never gets traffic) ───────
  logic icn_snf_rxreqflitv, icn_snf_rxdatflitv;
  logic [`CHIE_REQ_FLIT_RANGE] icn_snf_rxreqflit;
  logic [`CHIE_DAT_FLIT_RANGE] icn_snf_rxdatflit;
  logic icn_snf_txdatlcrdv, icn_snf_txrsplcrdv;
  logic snf_rxreqlcrdv, snf_rxdatlcrdv;
  logic snf_txrspflitv;  logic [`CHIE_RSP_FLIT_RANGE] snf_txrspflit;
  logic snf_txdatflitv;  logic [`CHIE_DAT_FLIT_RANGE] snf_txdatflit;
  logic snf_txlinkactivereq, snf_txlinkactiveack;
  logic snf_rxlinkactivereq, snf_rxlinkactiveack;
  logic snf_txactive, snf_rxactive;


  // --- REQ Channel (Request) ---
  typedef struct packed {
      logic [CHIE_REQ_RSVDC_WIDTH_PARAM-1:0]   rsvdc;         // Top MSB
      logic                                    tracetag;
      logic [1:0]                              tagop;
      logic                                    expcompack;
      logic                                    snoopme_excl;  // Shared Bit
      logic [7:0]                              lpid;
      logic                                    dodwt_snpattr; // Shared Bit
      logic [3:0]                              memattr;
      logic [3:0]                              pcrdtype;
      logic [1:0]                              order;
      logic                                    allowretry;
      logic                                    likelyshared;
      logic                                    ns;
      logic [CHIE_REQ_ADDR_WIDTH_PARAM-1:0]    addr;
      logic [2:0]                              size;
      logic [6:0]                              opcode;
      logic [11:0]                             returntxnid;
      logic                                    stshv_endian;  // Shared Bit
      logic [CHIE_NID_WIDTH_PARAM-1:0]         return_stsh_nid;
      logic [11:0]                             txnid;
      logic [CHIE_NID_WIDTH_PARAM-1:0]         srcid;
      logic [CHIE_NID_WIDTH_PARAM-1:0]         tgtid;
      logic [3:0]                              qos;           // LSB 0
  } chie_req_s;

  // --- DAT Channel (Data) ---
  typedef struct packed {
      logic [CHIE_POISON_WIDTH_PARAM-1:0]      poison;        // Absolute MSB
      logic [CHIE_DATACHECK_WIDTH_PARAM-1:0]   datacheck;
      logic [CHIE_DATA_WIDTH_PARAM-1:0]        data;
      logic [CHIE_BE_WIDTH_PARAM-1:0]          be;
      logic [CHIE_DAT_RSVDC_WIDTH_PARAM-1:0]   rsvdc;
      logic                                    tracetag;
      logic [(CHIE_DATA_WIDTH_PARAM/128)-1:0]  tu;
      logic [(CHIE_DATA_WIDTH_PARAM/32)-1:0]   tag;
      logic [1:0]                              tagop;
      logic [1:0]                              dataid;
      logic [1:0]                              ccid;
      logic [11:0]                             dbid;
      logic [2:0]                              cbusy;
      union packed {
          logic [3:0]                          datasource;
          logic [3:0]                          fwdstate;
          logic [3:0]                          datapull;
      } attr;
      logic [2:0]                              resp;
      logic [1:0]                              resperr;
      logic [3:0]                              opcode;
      logic [CHIE_NID_WIDTH_PARAM-1:0]         homenid;
      logic [11:0]                             txnid;
      logic [CHIE_NID_WIDTH_PARAM-1:0]         srcid;
      logic [CHIE_NID_WIDTH_PARAM-1:0]         tgtid;
      logic [3:0]                              qos;           // LSB 0
  } chie_dat_s;

  // --- RSP Channel (Response) ---
  typedef struct packed {
      logic                                    tracetag;      // MSB
      logic [1:0]                              tagop;
      logic [3:0]                              pcrdtype;
      logic [11:0]                             dbid;
      logic [2:0]                              cbusy;
      logic [2:0]                              fwd_pull;      // Shared Bits
      logic [2:0]                              resp;
      logic [1:0]                              resperr;
      logic [4:0]                              opcode;
      logic [11:0]                             txnid;
      logic [CHIE_NID_WIDTH_PARAM-1:0]         srcid;
      logic [CHIE_NID_WIDTH_PARAM-1:0]         tgtid;
      logic [3:0]                              qos;           // LSB 0
  } chie_rsp_s;


  // ============================================================================
  // CHANNEL PARSING FUNCTIONS
  // ============================================================================

  // --- REQ Channel Parser ---
  function automatic chie_req_s parse_req_flit(logic [`CHIE_REQ_FLIT_WIDTH-1:0] raw_flit);
      chie_req_s s;
      s.qos             = raw_flit[`CHIE_REQ_FLIT_QOS_RANGE];
      s.tgtid           = raw_flit[`CHIE_REQ_FLIT_TGTID_RANGE];
      s.srcid           = raw_flit[`CHIE_REQ_FLIT_SRCID_RANGE];
      s.txnid           = raw_flit[`CHIE_REQ_FLIT_TXNID_RANGE];
      s.return_stsh_nid = raw_flit[`CHIE_REQ_FLIT_RETURNNID_RANGE]; // Aliased with STASHNID
      s.stshv_endian    = raw_flit[`CHIE_REQ_FLIT_STASHNIDVALID_RANGE];
      s.returntxnid     = raw_flit[`CHIE_REQ_FLIT_RETURNTXNID_RANGE];
      s.opcode          = raw_flit[`CHIE_REQ_FLIT_OPCODE_RANGE];
      s.size            = raw_flit[`CHIE_REQ_FLIT_SIZE_RANGE];
      s.addr            = raw_flit[`CHIE_REQ_FLIT_ADDR_RANGE];
      s.ns              = raw_flit[`CHIE_REQ_FLIT_NS_RANGE];
      s.likelyshared    = raw_flit[`CHIE_REQ_FLIT_LIKELYSHARED_RANGE];
      s.allowretry      = raw_flit[`CHIE_REQ_FLIT_ALLOWRETRY_RANGE];
      s.order           = raw_flit[`CHIE_REQ_FLIT_ORDER_RANGE];
      s.pcrdtype        = raw_flit[`CHIE_REQ_FLIT_PCRDTYPE_RANGE];
      s.memattr         = raw_flit[`CHIE_REQ_FLIT_MEMATTR_RANGE];
      s.dodwt_snpattr   = raw_flit[`CHIE_REQ_FLIT_SNPATTR_RANGE];
      s.lpid            = raw_flit[`CHIE_REQ_FLIT_LPID_RANGE];
      s.snoopme_excl    = raw_flit[`CHIE_REQ_FLIT_EXCL_RANGE];
      s.expcompack      = raw_flit[`CHIE_REQ_FLIT_EXPCOMPACK_RANGE];
      s.tagop           = raw_flit[`CHIE_REQ_FLIT_TAGOP_RANGE];
      s.tracetag        = raw_flit[`CHIE_REQ_FLIT_TRACETAG_RANGE];
      return s;
  endfunction

  // --- DAT Channel Parser ---
  function automatic chie_dat_s parse_dat_flit(logic [`CHIE_DAT_FLIT_WIDTH-1:0] raw_flit);
      chie_dat_s s;
      s.qos             = raw_flit[`CHIE_DAT_FLIT_QOS_RANGE];
      s.tgtid           = raw_flit[`CHIE_DAT_FLIT_TGTID_RANGE];
      s.srcid           = raw_flit[`CHIE_DAT_FLIT_SRCID_RANGE];
      s.txnid           = raw_flit[`CHIE_DAT_FLIT_TXNID_RANGE];
      s.homenid         = raw_flit[`CHIE_DAT_FLIT_HOMENID_RANGE];
      s.opcode          = raw_flit[`CHIE_DAT_FLIT_OPCODE_RANGE];
      s.resperr         = raw_flit[`CHIE_DAT_FLIT_RESPERR_RANGE];
      s.resp            = raw_flit[`CHIE_DAT_FLIT_RESP_RANGE];
      s.attr.datasource = raw_flit[`CHIE_DAT_FLIT_DATASOURCE_RANGE];
      s.cbusy           = raw_flit[`CHIE_DAT_FLIT_CBUSY_RANGE];
      s.dbid            = raw_flit[`CHIE_DAT_FLIT_DBID_RANGE];
      s.ccid            = raw_flit[`CHIE_DAT_FLIT_CCID_RANGE];
      s.dataid          = raw_flit[`CHIE_DAT_FLIT_DATAID_RANGE];
      s.tagop           = raw_flit[`CHIE_DAT_FLIT_TAGOP_RANGE];
      s.tag             = raw_flit[`CHIE_DAT_FLIT_TAG_RANGE];
      s.tu              = raw_flit[`CHIE_DAT_FLIT_TU_RANGE];
      s.tracetag        = raw_flit[`CHIE_DAT_FLIT_TRACETAG_RANGE];
      //s.rsvdc           = raw_flit[`CHIE_DAT_FLIT_RSVDC_RANGE];
      s.be              = raw_flit[`CHIE_DAT_FLIT_BE_RANGE];
      s.data            = raw_flit[`CHIE_DAT_FLIT_DATA_RANGE];
      //s.datacheck       = raw_flit[`CHIE_DAT_FLIT_DATACHECK_RANGE];
      //s.poison          = raw_flit[`CHIE_DAT_FLIT_POISON_RANGE];
      return s;
  endfunction

  // --- RSP Channel Parser ---
  function automatic chie_rsp_s parse_rsp_flit(logic [`CHIE_RSP_FLIT_WIDTH-1:0] raw_flit);
      chie_rsp_s s;
      s.qos             = raw_flit[`CHIE_RSP_FLIT_QOS_RANGE];
      s.tgtid           = raw_flit[`CHIE_RSP_FLIT_TGTID_RANGE];
      s.srcid           = raw_flit[`CHIE_RSP_FLIT_SRCID_RANGE];
      s.txnid           = raw_flit[`CHIE_RSP_FLIT_TXNID_RANGE];
      s.opcode          = raw_flit[`CHIE_RSP_FLIT_OPCODE_RANGE];
      s.resperr         = raw_flit[`CHIE_RSP_FLIT_RESPERR_RANGE];
      s.resp            = raw_flit[`CHIE_RSP_FLIT_RESP_RANGE];
      s.fwd_pull        = raw_flit[`CHIE_RSP_FLIT_FWDSTATE_RANGE];
      s.cbusy           = raw_flit[`CHIE_RSP_FLIT_CBUSY_RANGE];
      s.dbid            = raw_flit[`CHIE_RSP_FLIT_DBID_RANGE];
      s.pcrdtype        = raw_flit[`CHIE_RSP_FLIT_PCRDTYPE_RANGE];
      s.tagop           = raw_flit[`CHIE_RSP_FLIT_TAGOP_RANGE];
      s.tracetag        = raw_flit[`CHIE_RSP_FLIT_TRACETAG_RANGE];
      return s;
  endfunction

    // --- 1. Clock and Reset Generation ---
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    initial begin
        rst_n  = 0;
        clk_en = 1;
        #100 rst_n = 1;
    end

    // --- 2. Instantiate RNF Wrapper ---
    rnf_wrapper #(
        .corecount_g(CORE_COUNT),
        .CHIE_REQ_ADDR_WIDTH_PARAM   (CHIE_REQ_ADDR_WIDTH_PARAM),
        .CHIE_SNP_ADDR_WIDTH_PARAM   (CHIE_SNP_ADDR_WIDTH_PARAM),
        .CHIE_NID_WIDTH_PARAM        (CHIE_NID_WIDTH_PARAM),
        .CHIE_DATA_WIDTH_PARAM       (CHIE_DATA_WIDTH_PARAM),
        .CHIE_BE_WIDTH_PARAM         (CHIE_BE_WIDTH_PARAM),
        .CHIE_DATACHECK_WIDTH_PARAM  (CHIE_DATACHECK_WIDTH_PARAM),
        .CHIE_POISON_WIDTH_PARAM     (CHIE_POISON_WIDTH_PARAM),
        .CHIE_REQ_RSVDC_WIDTH_PARAM  (CHIE_REQ_RSVDC_WIDTH_PARAM),
        .CHIE_DAT_RSVDC_WIDTH_PARAM  (CHIE_DAT_RSVDC_WIDTH_PARAM),
        .HNF_NID_PARAM               (HNF_NID_PARAM),
        .XP_LCRD_NUM_PARAM           (XP_LCRD_NUM_PARAM)
        ) u_rnf_wrap (
        .clk             (clk),
        .rst_n           (rst_n & program_load_done),
        .clk_en          (clk_en),
        .debug_req_i     ('0),

        // RX Interface
        .rxrspflitv      (rnf_rxrspflitv),
        .rxrspflit       (rnf_rxrspflit),
        .rxrspflitpend   (icn_rnf_rxrsppend),
        .rxdatflitv      (rnf_rxdatflitv),
        .rxdatflit       (rnf_rxdatflit),
        .rxdatflitpend   (icn_rnf_rxdatpend),
        .rxsnpflitv      (rnf_rxsnpflitv),
        .rxsnpflit       (rnf_rxsnpflit),
        .rxsnpflitpend   (icn_rnf_rxsnppend),

        // TX Interface
        .txreqflitv      (rnf_txreqflitv),
        .txreqflit       (rnf_txreqflit),
        .txreqflitpend   (rnf_txreqflitpend),
        .txrspflitv      (rnf_txrspflitv),
        .txrspflit       (rnf_txrspflit),
        .txrspflitpend   (rnf_txrspflitpend),
        .txdatflitv      (rnf_txdatflitv),
        .txdatflit       (rnf_txdatflit),
        .txdatflitpend   (rnf_txdatflitpend),

        // Credits
        .txreqlcrdv      (rnf_txreqlcrdv),
        .txrsplcrdv      (rnf_txrsplcrdv),
        .txdatlcrdv      (rnf_txdatlcrdv),
        .rxrsplcrdv      (rnf_rxrsplcrdv),
        .rxdatlcrdv      (rnf_rxdatlcrdv),
        .rxsnplcrdv      (rnf_rxsnplcrdv),

        // Handshake Ports
        .txlinkactivereq  (rnf_txlinkactivereq),
        .txlinkactiveack  (rnf_txlinkactiveack),
        .rxlinkactivereq  (rnf_rxlinkactivereq),
        .rxlinkactiveack  (rnf_rxlinkactiveack),
        .txactive         (rnf_txactive),
        .rxactive         (rnf_rxactive)
    );


    // ==========================================================================
    // 3. gem5 IPC HN-F Bridge  (replaces behavioral RTL HNF)
    // ==========================================================================
    // questa_top_ipc_wrap connects gem5's CHI HN-F via POSIX shared-memory IPC.
    // Flit format adapter converts between:
    //   RTL  : 256-bit data, 12-bit TXNID/DBID, 131/65/370/92-bit flits
    //   gem5 : 512-bit data, 12-bit TXNID/DBID, 117/64/645/93-bit flits
    //
    // Concrete RTL bit positions (NID_W=7, TXNID=12b, ADDR=44b, DATA=256b):
    //  REQ[130:0]:  qos[3:0] tgtid[10:4] srcid[17:11] txnid[29:18]
    //               rtn_nid[36:30] stashnidv[37] rtn_txnid[49:38]
    //               opcode[56:50] size[59:57] addr[103:60] ns[104]
    //               likely[105] allowretry[106] order[108:107]
    //               pcrdtype[112:109] memattr[116:113] snpattr[117]
    //               lpid[125:118] excl[126] expcompack[127]
    //               tagop[129:128] tracetag[130]
    //  RSP[64:0]:   qos[3:0] tgtid[10:4] srcid[17:11] txnid[29:18]
    //               opcode[34:30] resperr[36:35] resp[39:37]
    //               fwdstate[42:40] cbusy[45:43] dbid[57:46]
    //               pcrdtype[61:58] tagop[63:62] tracetag[64]
    //  DAT[369:0]:  qos[3:0] tgtid[10:4] srcid[17:11] txnid[29:18]
    //               homenid[36:30] opcode[40:37] resperr[42:41] resp[45:43]
    //               datasource[49:46] cbusy[52:50] dbid[64:53]
    //               ccid[66:65] dataid[68:67] tagop[70:69]
    //               tag[78:71] tu[80:79] tracetag[81]
    //               be[113:82] data[369:114]
    //  SNP[91:0]:   qos[3:0] srcid[10:4] txnid[22:11] fwdnid[29:23]
    //               fwdtxnid[41:30] opcode[46:42]
    //               addr[87:47] ns[88] donotgotosd[89] rettosrc[90] tracetag[91]
    //
    // IPC bit positions (NID_W=7, TXNID=12b, DATA=512b):
    //  REQ[116:0]:  qos[3:0] tgtid[10:4] srcid[17:11] txnid[29:18]
    //               rtnid[36:30] stashnidv[37] rtntxnid[41:38] stashlpidv[42]
    //               opcode[49:43] size[52:50] addr[96:53] ns[97]
    //               likely[98] allowretry[99] order[101:100]
    //               pcrdtype[105:102] memattr[109:106] snpattr[110]
    //               dwt[111] excl[112] expcompack[113]
    //               tagop[115:114] tracetag[116]
    //  RSP[63:0]:   qos[3:0] tgtid[10:4] srcid[17:11] txnid[29:18]
    //               opcode[35:30] resperr[37:36] resp[40:38]
    //               fwdstate[43:41] datapull[44] dbid[56:45]
    //               pcrdtype[60:57] tagop[62:61] tracetag[63]
    //  DAT[644:0]:  qos[3:0] tgtid[10:4] homeid[17:11] opcode[21:18]
    //               resperr[23:22] resp[26:24] fwdstate[29:27] datapull[30]
    //               dbid[42:31] ccid[44:43] dataid[46:45] tagop[48:47]
    //               txnid[60:49] srcid[67:61] tracetag[68]
    //               be[132:69] data[644:133]
    //  SNP[92:0]:   qos[3:0] srcid[10:4] txnid[22:11] fwdnid[29:23]
    //               fwdtxnid[41:30] opcode[46:42]
    //               ns[47] donotgotosd[48] rettosrc[49] donotdatapull[50]
    //               addr[91:51] tracetag[92]
    // ==========================================================================

    // ── REQ: ICN 131b RTL → IPC 117b ─────────────────────────────────────────
    always_comb begin : req_rtl2ipc
        ipc_txreq_flit          = '0;
        ipc_txreq_flit[3:0]     = icn_hnf_rxreqflit[3:0];      // qos
        ipc_txreq_flit[10:4]    = icn_hnf_rxreqflit[10:4];     // tgtid
        ipc_txreq_flit[17:11]   = icn_hnf_rxreqflit[17:11];    // srcid
        ipc_txreq_flit[29:18]   = icn_hnf_rxreqflit[29:18];           // txnid 12-bit
        ipc_txreq_flit[36:30]   = icn_hnf_rxreqflit[36:30];    // rtnid (+4)
        ipc_txreq_flit[37]      = icn_hnf_rxreqflit[37];       // stashnidv (+4)
        ipc_txreq_flit[41:38]   = icn_hnf_rxreqflit[41:38];    // rtntxnid[3:0] (+4)
        ipc_txreq_flit[49:43]   = icn_hnf_rxreqflit[56:50];    // opcode (+4)
        ipc_txreq_flit[52:50]   = icn_hnf_rxreqflit[59:57];    // size (+4)
        ipc_txreq_flit[96:53]   = icn_hnf_rxreqflit[103:60];   // addr (+4)
        ipc_txreq_flit[97]      = icn_hnf_rxreqflit[104];      // ns (+4)
        ipc_txreq_flit[98]      = icn_hnf_rxreqflit[105];      // likelyshared (+4)
        ipc_txreq_flit[99]      = icn_hnf_rxreqflit[106];      // allowretry (+4)
        ipc_txreq_flit[101:100] = icn_hnf_rxreqflit[108:107];  // order (+4)
        ipc_txreq_flit[105:102] = icn_hnf_rxreqflit[112:109];  // pcrdtype (+4)
        ipc_txreq_flit[109:106] = icn_hnf_rxreqflit[116:113];  // memattr (+4)
        ipc_txreq_flit[110]     = icn_hnf_rxreqflit[117];      // snpattr (+4)
        ipc_txreq_flit[112]     = icn_hnf_rxreqflit[126];      // excl/snoopme (+4)
        ipc_txreq_flit[113]     = icn_hnf_rxreqflit[127];      // expcompack (+4)
        ipc_txreq_flit[115:114] = icn_hnf_rxreqflit[129:128];  // tagop (+4)
        ipc_txreq_flit[116]     = icn_hnf_rxreqflit[130];      // tracetag (+4)
    end
    assign ipc_txreq_flitv    = icn_hnf_rxreqflitv;
    assign ipc_txreq_flitpend = icn_hnf_rxreqpend;

    // ── RSP: ICN 65b RTL → IPC 64b ───────────────────────────────────────────
    always_comb begin : rsp_rtl2ipc
        ipc_txrsp_flit        = '0;
        ipc_txrsp_flit[3:0]   = icn_hnf_rxrspflit[3:0];      // qos
        ipc_txrsp_flit[10:4]  = icn_hnf_rxrspflit[10:4];     // tgtid
        ipc_txrsp_flit[17:11] = icn_hnf_rxrspflit[17:11];    // srcid
        ipc_txrsp_flit[29:18] = icn_hnf_rxrspflit[29:18];           // txnid 12-bit
        ipc_txrsp_flit[35:30] = {1'b0, icn_hnf_rxrspflit[34:30]};  // opcode 5b→6b (+4)
        ipc_txrsp_flit[37:36] = icn_hnf_rxrspflit[36:35];    // resperr (+4)
        ipc_txrsp_flit[40:38] = icn_hnf_rxrspflit[39:37];    // resp (+4)
        ipc_txrsp_flit[43:41] = icn_hnf_rxrspflit[42:40];    // fwdstate (+4)
        ipc_txrsp_flit[56:45] = icn_hnf_rxrspflit[57:46];           // dbid 12-bit
        ipc_txrsp_flit[60:57] = icn_hnf_rxrspflit[61:58];    // pcrdtype (+8)
        ipc_txrsp_flit[62:61] = icn_hnf_rxrspflit[63:62];    // tagop (+8)
        ipc_txrsp_flit[63]    = icn_hnf_rxrspflit[64];       // tracetag (+8)
    end
    assign ipc_txrsp_flitv    = icn_hnf_rxrspflitv;
    assign ipc_txrsp_flitpend = icn_hnf_rxrsppend;
    // hnf_rxrsplcrdv driven by u_gem5_ipc.txrsp_lcrdv port connection

    // ── DAT TX: BEATS_PER_LINE × RTL flits → 1 × 512b IPC flit ─────────────
    // Per-{srcid, txnid} accumulator.  Each slot keeps the assembled 64-byte
    // payload + 64-bit BE + a beat-received bitmask.  The first beat also
    // snapshots the header for the eventual IPC-flit reassembly.  When
    // every bit of the BEATS_PER_LINE-wide mask is set the IPC flit is
    // emitted and the slot released — handles ICN reordering across
    // concurrent transactions regardless of beat width (1/2/4).
    always_ff @(posedge clk or negedge rst_n) begin : dat_tx_proc
        if (!rst_n) begin
            dat_tx_valids        <= '0;
            dat_tx_assembled     <= '0;
            dat_tx_assembled_vld <= 1'b0;
            for (int i = 0; i < DAT_TX_BUF_DEPTH; i++) begin
                dat_tx_first_hdr[i] <= '0;
                dat_tx_data[i]      <= '0;
                dat_tx_be[i]        <= '0;
                dat_tx_keys[i]      <= '0;
                dat_tx_masks[i]     <= '0;
            end
        end else begin
            dat_tx_assembled_vld <= 1'b0;
            if (icn_hnf_rxdatflitv) begin
                automatic logic [18:0] key      = {icn_hnf_rxdatflit[17:11],
                                                   icn_hnf_rxdatflit[29:18]};
                automatic logic [1:0]  dataid   = icn_hnf_rxdatflit[68:67];
                automatic int          beat_idx = dataid / DATAID_STEP;
                automatic int          slot     = -1;
                automatic logic [511:0] data_full;
                automatic logic [63:0]  be_full;
                automatic logic [BEATS_PER_LINE-1:0] mask_after;
                // DIAGNOSTIC: every DAT beat the adapter takes from the ICN HN-F
                // port.  op[40:37], txn[29:18], srcid[17:11].  Lets us confirm the
                // SnpRespData is received here and compare against the emit/bridge.
                $display("[ADAPT] TXDAT-in  t=%0t op=0x%01h txn=0x%03h src=%0d dataid=%0d beat_idx=%0d",
                         $realtime, icn_hnf_rxdatflit[40:37], icn_hnf_rxdatflit[29:18],
                         icn_hnf_rxdatflit[17:11], dataid, beat_idx);
                // Find existing accumulator slot for this key, else grab a free one.
                for (int i = 0; i < DAT_TX_BUF_DEPTH; i++)
                    if (dat_tx_valids[i] && dat_tx_keys[i] == key && slot < 0) slot = i;
                if (slot < 0)
                    for (int i = 0; i < DAT_TX_BUF_DEPTH; i++)
                        if (!dat_tx_valids[i] && slot < 0) slot = i;
                if (slot < 0) begin
                    $error("[DAT_TX] buffer full at t=%t — increase DAT_TX_BUF_DEPTH",
                           $realtime);
                end else begin
                    // Snapshot header from the first beat we see for this txn.
                    if (!dat_tx_valids[slot]) begin
                        dat_tx_first_hdr[slot] <= icn_hnf_rxdatflit;
                        dat_tx_data[slot]      <= '0;
                        dat_tx_be[slot]        <= '0;
                        dat_tx_masks[slot]     <= '0;
                        dat_tx_keys[slot]      <= key;
                        dat_tx_valids[slot]    <= 1'b1;
                    end
                    // Merge this beat's DATA and BE into the accumulator.
                    // Use variables so we can OR-in then decide to flush.
                    data_full = dat_tx_data[slot];
                    be_full   = dat_tx_be[slot];
                    for (int b = 0; b < IPC_BEAT_DATA_BITS; b++)
                        data_full[beat_idx*IPC_BEAT_DATA_BITS + b] =
                            icn_hnf_rxdatflit[RTL_DAT_DATA_LSB + b];
                    for (int b = 0; b < IPC_BEAT_BE_BITS; b++)
                        be_full[beat_idx*IPC_BEAT_BE_BITS + b] =
                            icn_hnf_rxdatflit[RTL_DAT_BE_LSB + b];
                    mask_after = dat_tx_masks[slot] | (1'b1 << beat_idx);
                    dat_tx_data[slot]  <= data_full;
                    dat_tx_be[slot]    <= be_full;
                    dat_tx_masks[slot] <= mask_after;
                    // If the whole line has been assembled, emit and free the slot.
                    if (&mask_after) begin
                        // Header source: dat_tx_first_hdr[slot] is written with a
                        // non-blocking assign on the FIRST beat, so it is NOT yet
                        // visible in the same cycle.  At BEATS_PER_LINE=1 the first
                        // beat is also the completing beat, so reading the slot here
                        // would return the STALE header of the slot's previous txn
                        // (TxnID/opcode swap between concurrent single-beat responses).
                        // Use the current flit when this is the slot's first beat.
                        automatic logic [`CHIE_DAT_FLIT_WIDTH-1:0] hdr =
                            (!dat_tx_valids[slot]) ? icn_hnf_rxdatflit
                                                   : dat_tx_first_hdr[slot];
                        dat_tx_valids[slot]       <= 1'b0;
                        dat_tx_masks[slot]        <= '0;
                        dat_tx_assembled          <= '0;
                        dat_tx_assembled[3:0]     <= hdr[3:0];         // qos
                        dat_tx_assembled[10:4]    <= hdr[10:4];        // tgtid
                        dat_tx_assembled[17:11]   <= hdr[36:30];       // homeid
                        dat_tx_assembled[21:18]   <= hdr[40:37];       // opcode
                        dat_tx_assembled[23:22]   <= hdr[42:41];       // resperr
                        dat_tx_assembled[26:24]   <= hdr[45:43];       // resp
                        dat_tx_assembled[29:27]   <= hdr[49:47];       // fwdstate[2:0]
                        dat_tx_assembled[30]      <= hdr[49];          // datapull
                        dat_tx_assembled[42:31]   <= hdr[64:53];       // dbid 12-bit
                        dat_tx_assembled[44:43]   <= hdr[66:65];       // ccid
                        dat_tx_assembled[46:45]   <= 2'b00;            // dataid=00 (IPC always full line)
                        dat_tx_assembled[48:47]   <= hdr[70:69];       // tagop
                        dat_tx_assembled[60:49]   <= hdr[29:18];       // txnid 12-bit
                        dat_tx_assembled[67:61]   <= hdr[17:11];       // srcid
                        dat_tx_assembled[68]      <= hdr[RTL_DAT_TRACETAG_LSB]; // tracetag
                        dat_tx_assembled[132:69]  <= be_full;          // BE 64b
                        dat_tx_assembled[644:133] <= data_full;        // DATA 512b
                        dat_tx_assembled_vld      <= 1'b1;
                        // DIAGNOSTIC: a full line was assembled and is being driven
                        // to the bridge on ipc_txdat this cycle.  Compare txn here
                        // against [ipc] Phase3 TXDAT (bridge) and gem5 makeDatMsg:
                        // a txn present here but absent downstream = the real drop.
                        $display("[ADAPT] TXDAT-emit t=%0t op=0x%01h txn=0x%03h",
                                 $realtime, hdr[40:37], hdr[29:18]);
                    end
                end
            end
        end
    end
    assign ipc_txdat_flit     = dat_tx_assembled;
    assign ipc_txdat_flitv    = dat_tx_assembled_vld;
    assign ipc_txdat_flitpend = dat_tx_assembled_vld;
    // hnf_rxdatlcrdv driven by u_gem5_ipc.txdat_lcrdv port connection

    // ── RSP: IPC 56b → ICN 65b RTL ───────────────────────────────────────────
    always_comb begin : rsp_ipc2rtl
        hnf_txrspflit        = '0;
        hnf_txrspflit[3:0]   = ipc_rxrsp_flit[3:0];
        hnf_txrspflit[10:4]  = ipc_rxrsp_flit[10:4];
        hnf_txrspflit[17:11] = ipc_rxrsp_flit[17:11];
        hnf_txrspflit[29:18] = ipc_rxrsp_flit[29:18];    // txnid 12-bit direct
        hnf_txrspflit[34:30] = ipc_rxrsp_flit[34:30];    // opcode[4:0] (low 5b of 6b IPC field)
        hnf_txrspflit[36:35] = ipc_rxrsp_flit[37:36];    // resperr (+4)
        hnf_txrspflit[39:37] = ipc_rxrsp_flit[40:38];    // resp (+4)
        hnf_txrspflit[42:40] = ipc_rxrsp_flit[43:41];    // fwdstate (+4)
        // cbusy[45:43] = 0
        hnf_txrspflit[57:46] = ipc_rxrsp_flit[56:45];    // dbid 12-bit direct
        hnf_txrspflit[61:58] = ipc_rxrsp_flit[60:57];    // pcrdtype (+8)
        hnf_txrspflit[63:62] = ipc_rxrsp_flit[62:61];    // tagop (+8)
        hnf_txrspflit[64]    = ipc_rxrsp_flit[63];       // tracetag (+8)
    end
    assign hnf_txrspflitv  = ipc_rxrsp_flitv;
    assign hnf_txrsppend   = ipc_rxrsp_flitpend;
    assign ipc_rxrsp_lcrdv = hnf_txrsplcrdv;

    // ── DAT RX: 1 × 512b IPC flit → BEATS_PER_LINE × RTL flits ─────────────
    // Counter-based FSM.  On the first beat we drive the full header from
    // the latched IPC flit; on every beat we drive DataID and slice the
    // matching DATA/BE bytes for that beat.  For BEATS_PER_LINE = 1 the
    // full 512b line is delivered in a single 512b RTL beat.
    always_ff @(posedge clk or negedge rst_n) begin : dat_rx_sm
        if (!rst_n) begin
            dat_rx_busy     <= 1'b0;
            dat_rx_beat_idx <= '0;
            dat_rx_latch    <= '0;
            hnf_txdatflitv  <= 1'b0;
            hnf_txdatpend   <= 1'b0;
            hnf_txdatflit   <= '0;
        end else begin
            hnf_txdatflitv <= 1'b0;
            hnf_txdatpend  <= 1'b0;
            if (!dat_rx_busy) begin
                if (ipc_rxdat_flitv) begin
                    dat_rx_latch    <= ipc_rxdat_flit;
                    dat_rx_beat_idx <= '0;
                    dat_rx_busy     <= 1'b1;
                end
            end else begin
                // Drive one RTL beat this cycle.  Header fields come from
                // the latched IPC flit; DATA and BE fields select the beat
                // slice.  Position them inside the RTL flit at the shift-
                // adjusted RTL_DAT_{DATA,BE}_LSB.
                hnf_txdatflitv <= 1'b1;
                hnf_txdatpend  <= 1'b1;
                hnf_txdatflit                <= '0;
                hnf_txdatflit[3:0]           <= dat_rx_latch[3:0];      // qos
                hnf_txdatflit[10:4]          <= dat_rx_latch[10:4];     // tgtid
                hnf_txdatflit[17:11]         <= dat_rx_latch[67:61];    // srcid
                hnf_txdatflit[29:18]         <= dat_rx_latch[60:49];    // txnid 12-bit
                hnf_txdatflit[36:30]         <= dat_rx_latch[17:11];    // homenid
                hnf_txdatflit[40:37]         <= dat_rx_latch[21:18];    // opcode
                hnf_txdatflit[42:41]         <= dat_rx_latch[23:22];    // resperr
                hnf_txdatflit[45:43]         <= dat_rx_latch[26:24];    // resp
                hnf_txdatflit[49:46]         <= {dat_rx_latch[30], dat_rx_latch[29:27]};
                hnf_txdatflit[64:53]         <= dat_rx_latch[42:31];    // dbid 12-bit
                hnf_txdatflit[66:65]         <= dat_rx_latch[44:43];    // ccid
                hnf_txdatflit[68:67]         <= dat_rx_beat_idx * DATAID_STEP;
                hnf_txdatflit[70:69]         <= dat_rx_latch[48:47];    // tagop
                hnf_txdatflit[RTL_DAT_TRACETAG_LSB] <= dat_rx_latch[68];
                for (int b = 0; b < IPC_BEAT_BE_BITS; b++)
                    hnf_txdatflit[RTL_DAT_BE_LSB + b]   <=
                        dat_rx_latch[69 + dat_rx_beat_idx*IPC_BEAT_BE_BITS + b];
                for (int b = 0; b < IPC_BEAT_DATA_BITS; b++)
                    hnf_txdatflit[RTL_DAT_DATA_LSB + b] <=
                        dat_rx_latch[133 + dat_rx_beat_idx*IPC_BEAT_DATA_BITS + b];
                if (dat_rx_beat_idx == BEATS_PER_LINE - 1) begin
                    dat_rx_busy     <= 1'b0;
                    dat_rx_beat_idx <= '0;
                end else begin
                    dat_rx_beat_idx <= dat_rx_beat_idx + 1;
                end
            end
        end
    end
    assign ipc_rxdat_lcrdv = hnf_txdatlcrdv;

    // ── SNP: IPC 102b (SCC format) → ICN 92b RTL ────────────────────────────
    // SCC chi_flit_pack.hh layout (chi_flit_cfg: ADDR_W=44, NODEID_W=7):
    //   [46:0]  qos/srcid/txnid/fwdnid/fwdtxnid/opcode  (bit-exact with RTL)
    //   [90:47] addr (44-bit field; byte_addr>>3; lower 41 bits map to RTL[87:47])
    //   [91]    NS
    //   [92]    DoNotGoToSD
    //   [93]    RetToSrc
    //   [94]    DoNotDataPull (not wired to RTL — CVA6 RN-F has no DoNotDataPull field)
    //   [95]    TraceTag
    //   [102:96] TgtID
    always_comb begin : snp_ipc2rtl
        hnf_txsnpflit        = '0;
        hnf_txsnpflit[3:0]   = ipc_rxsnp_flit[3:0];
        hnf_txsnpflit[10:4]  = ipc_rxsnp_flit[10:4];     // srcid
        hnf_txsnpflit[22:11] = ipc_rxsnp_flit[22:11];    // txnid 12-bit direct
        hnf_txsnpflit[29:23] = ipc_rxsnp_flit[29:23];    // fwdnid
        hnf_txsnpflit[41:30] = ipc_rxsnp_flit[41:30];    // fwdtxnid 12-bit direct
        hnf_txsnpflit[46:42] = ipc_rxsnp_flit[46:42];    // opcode
        hnf_txsnpflit[87:47] = ipc_rxsnp_flit[87:47];    // addr[43:3]: SCC packs addr>>3 so IPC[90:88]=0, IPC[87:47]=addr[43:3]
        hnf_txsnpflit[88]    = ipc_rxsnp_flit[91];       // NS
        hnf_txsnpflit[89]    = ipc_rxsnp_flit[92];       // DoNotGoToSD
        hnf_txsnpflit[90]    = ipc_rxsnp_flit[93];       // RetToSrc
        hnf_txsnpflit[91]    = ipc_rxsnp_flit[95];       // TraceTag
        hnf_txsnpflit[98:92] = ipc_rxsnp_flit[102:96];  // TgtID: route snoop to correct RTL core
    end
    assign hnf_txsnpflitv  = ipc_rxsnp_flitv;
    assign hnf_txsnppend   = ipc_rxsnp_flitpend;
    assign ipc_rxsnp_lcrdv = hnf_txsnplcrdv;

    // ── HNF TXREQ: tie off (gem5 has internal memory; no SNF ReadNoSnp needed)
    // hnf_txreq{flitv,pend,flit} are ICN inputs (HNF→ICN). Tie to 0.
    // hnf_txreqlcrdv is an ICN output (ICN credits HNF TX REQ). Do NOT drive it.
    assign hnf_txreqflitv = 1'b0;
    assign hnf_txreqpend  = 1'b0;
    assign hnf_txreqflit  = '0;

    // ── questa_top_ipc_wrap: gem5 IPC bridge ──────────────────────────────────
    questa_top_ipc_wrap u_gem5_ipc (
        .clk            (clk),
        .rstn           (rst_n & program_load_done),

        .txreq_flitv    (ipc_txreq_flitv),
        .txreq_flitpend (ipc_txreq_flitpend),
        .txreq_flit     (ipc_txreq_flit),
        .txreq_lcrdv    (hnf_rxreqlcrdv),   // IPC→ICN: credits for REQ channel

        .txrsp_flitv    (ipc_txrsp_flitv),
        .txrsp_flitpend (ipc_txrsp_flitpend),
        .txrsp_flit     (ipc_txrsp_flit),
        .txrsp_lcrdv    (hnf_rxrsplcrdv),   // IPC→ICN: credits for RSP channel

        .txdat_flitv    (ipc_txdat_flitv),
        .txdat_flitpend (ipc_txdat_flitpend),
        .txdat_flit     (ipc_txdat_flit),
        .txdat_lcrdv    (hnf_rxdatlcrdv),   // IPC→ICN: credits for DAT channel

        .rxrsp_flitv    (ipc_rxrsp_flitv),
        .rxrsp_flitpend (ipc_rxrsp_flitpend),
        .rxrsp_flit     (ipc_rxrsp_flit),
        .rxrsp_lcrdv    (ipc_rxrsp_lcrdv),

        .rxdat_flitv    (ipc_rxdat_flitv),
        .rxdat_flitpend (ipc_rxdat_flitpend),
        .rxdat_flit     (ipc_rxdat_flit),
        .rxdat_lcrdv    (ipc_rxdat_lcrdv),

        .rxsnp_flitv    (ipc_rxsnp_flitv),
        .rxsnp_flitpend (ipc_rxsnp_flitpend),
        .rxsnp_flit     (ipc_rxsnp_flit),
        .rxsnp_lcrdv    (ipc_rxsnp_lcrdv)
    );

    // ── ICN SNF port: tie off (gem5 handles all memory internally) ────────────
    // ICN INPUTS from SNF (we must drive these since there is no real SNF):
    assign snf_rxreqlcrdv      = 1'b0;   // SNF grants no REQ credits (not sending REQs)
    assign snf_rxdatlcrdv      = 1'b0;
    assign snf_txrspflitv      = 1'b0;
    assign snf_txrspflit       = '0;
    assign snf_txdatflitv      = 1'b0;
    assign snf_txdatflit       = '0;
    assign snf_txlinkactivereq = 1'b1;   // SNF claims TX link always active
    assign snf_rxlinkactiveack = 1'b1;   // SNF always acks ICN's RX link request
    assign snf_txactive        = 1'b1;
    // ICN OUTPUTS to SNF (icn_snf_rxreq*, icn_snf_rxdat*, icn_snf_txrsplcrdv,
    // icn_snf_txdatlcrdv, snf_txlinkactiveack, snf_rxlinkactivereq, snf_rxactive)
    // are driven by the ICN — do NOT assign them here.



  chi_icn_beh #(
    .CORE_COUNT (CORE_COUNT),

    .CHIE_REQ_ADDR_WIDTH_PARAM   (CHIE_REQ_ADDR_WIDTH_PARAM),
    .CHIE_SNP_ADDR_WIDTH_PARAM   (CHIE_SNP_ADDR_WIDTH_PARAM),
    .CHIE_NID_WIDTH_PARAM        (CHIE_NID_WIDTH_PARAM),
    .CHIE_DATA_WIDTH_PARAM       (CHIE_DATA_WIDTH_PARAM),
    .CHIE_BE_WIDTH_PARAM         (CHIE_BE_WIDTH_PARAM),
    .CHIE_DATACHECK_WIDTH_PARAM  (CHIE_DATACHECK_WIDTH_PARAM),
    .CHIE_POISON_WIDTH_PARAM     (CHIE_POISON_WIDTH_PARAM),
    .CHIE_REQ_RSVDC_WIDTH_PARAM  (CHIE_REQ_RSVDC_WIDTH_PARAM),
    .CHIE_DAT_RSVDC_WIDTH_PARAM  (CHIE_DAT_RSVDC_WIDTH_PARAM),
    .HNF_MSHR_RNF_NUM_PARAM      (HNF_MSHR_RNF_NUM_PARAM),
    .HNF_MSHR_RNI_NUM_PARAM      (HNF_MSHR_RNI_NUM_PARAM),
    .RNF_NID_LIST_PARAM          (RNF_NID_LIST_PARAM),
    .RNI_NID_LIST_PARAM          (RNI_NID_LIST_PARAM),
    .HNF_NID_PARAM               (HNF_NID_PARAM),
    .SNF_NID_PARAM               (SNF_NID_PARAM),
    .XP_LCRD_NUM_PARAM           (XP_LCRD_NUM_PARAM),
    .HNF_SF_ENTRIES_NUM_PARAM    (HNF_SF_ENTRIES_NUM_PARAM),
    .HNF_SF_WAY_NUM_PARAM        (HNF_SF_WAY_NUM_PARAM),
    .HNF_MSHR_EXCL_RN_NUM_PARAM  (HNF_MSHR_EXCL_RN_NUM_PARAM),
    .HNF_MSHR_EXCL_RN_WIDTH_PARAM(HNF_MSHR_EXCL_RN_WIDTH_PARAM),
    .HNF_MSHR_ENTRIES_NUM_PARAM  (HNF_MSHR_ENTRIES_NUM_PARAM),
    .HNF_MSHR_ENTRIES_WIDTH_PARAM(HNF_MSHR_ENTRIES_WIDTH_PARAM),
    .HNF_L3_CACHE_SIZE_PARAM     (HNF_L3_CACHE_SIZE_PARAM),
    .HNF_L3_WAY_NUM_PARAM        (HNF_L3_WAY_NUM_PARAM)
  ) u_chi_icn (
    .clk                  (clk),
    .rst                  (~(rst_n & program_load_done)),

    // --- RNF VECTORIZED INTERFACE ---
    // These connect to your arrayed signals from the cores
    .rnf_txreqflitv       (rnf_txreqflitv),
    .rnf_txreqflit        (rnf_txreqflit),
    .rnf_txreqlcrdv       (rnf_txreqlcrdv),

    .rnf_txrspflitv       (rnf_txrspflitv),
    .rnf_txrspflit        (rnf_txrspflit),
    .rnf_txrsplcrdv       (rnf_txrsplcrdv),

    .rnf_txdatflitv       (rnf_txdatflitv),
    .rnf_txdatflit        (rnf_txdatflit),
    .rnf_txdatlcrdv       (rnf_txdatlcrdv),

    .rnf_rxsnpflitv       (rnf_rxsnpflitv),
    .rnf_rxsnppend        (icn_rnf_rxsnppend),
    .rnf_rxsnpflit        (rnf_rxsnpflit),
    .rnf_rxsnplcrdv       (rnf_rxsnplcrdv),

    .rnf_rxrspflitv       (rnf_rxrspflitv),
    .rnf_rxrsppend        (icn_rnf_rxrsppend),
    .rnf_rxrspflit        (rnf_rxrspflit),
    .rnf_rxrsplcrdv       (rnf_rxrsplcrdv),

    .rnf_rxdatflitv       (rnf_rxdatflitv),
    .rnf_rxdatpend        (icn_rnf_rxdatpend),
    .rnf_rxdatflit        (rnf_rxdatflit),
    .rnf_rxdatlcrdv       (rnf_rxdatlcrdv),

    // Link layer handshakes (Vectorized)
    .rnf_txlinkactivereq  (rnf_txlinkactivereq),
    .rnf_txlinkactiveack  (rnf_txlinkactiveack),
    .rnf_rxlinkactivereq  (rnf_rxlinkactivereq),
    .rnf_rxlinkactiveack  (rnf_rxlinkactiveack),
    .rnf_txactive         (rnf_txactive),
    .rnf_rxactive         (rnf_rxactive),

    // --- HNF INTERFACE (Connected via your Arbiter/Mux) ---
    .hnf_rxreqflitv       (icn_hnf_rxreqflitv), // Internal wires from arbiter
    .hnf_rxreqflit        (icn_hnf_rxreqflit),
    .hnf_rxreqpend        (icn_hnf_rxreqpend),
    .hnf_rxreqlcrdv       (hnf_rxreqlcrdv),

    .hnf_rxrspflitv       (icn_hnf_rxrspflitv),
    .hnf_rxrspflit        (icn_hnf_rxrspflit),
    .hnf_rxrsppend        (icn_hnf_rxrsppend),
    .hnf_rxrsplcrdv       (hnf_rxrsplcrdv),

    .hnf_rxdatflitv       (icn_hnf_rxdatflitv),
    .hnf_rxdatflit        (icn_hnf_rxdatflit),
    .hnf_rxdatpend        (icn_hnf_rxdatpend),
    .hnf_rxdatlcrdv       (hnf_rxdatlcrdv),

    .hnf_txreqflitv       (hnf_txreqflitv),
    .hnf_txreqflit        (hnf_txreqflit),
    .hnf_txreqpend        (hnf_txreqpend),
    .hnf_txreqlcrdv       (hnf_txreqlcrdv),

    .hnf_txsnpflitv       (hnf_txsnpflitv),
    .hnf_txsnpflit        (hnf_txsnpflit),
    .hnf_txsnppend        (hnf_txsnppend),
    .hnf_txsnplcrdv       (hnf_txsnplcrdv),

    .hnf_txrspflitv       (hnf_txrspflitv),
    .hnf_txrspflit        (hnf_txrspflit),
    .hnf_txrsppend        (hnf_txrsppend),
    .hnf_txrsplcrdv       (hnf_txrsplcrdv),

    .hnf_txdatflitv       (hnf_txdatflitv),
    .hnf_txdatflit        (hnf_txdatflit),
    .hnf_txdatpend        (hnf_txdatpend),
    .hnf_txdatlcrdv       (hnf_txdatlcrdv),

    // --- SNF INTERFACE (Slave Node / Memory) ---
    .snf_rxreqflitv       (icn_snf_rxreqflitv),
    .snf_rxreqflit        (icn_snf_rxreqflit),
    .snf_rxreqlcrdv       (snf_rxreqlcrdv),

    .snf_rxdatflitv       (icn_snf_rxdatflitv),
    .snf_rxdatflit        (icn_snf_rxdatflit),
    .snf_rxdatlcrdv       (snf_rxdatlcrdv),

    .snf_txrspflitv       (snf_txrspflitv),
    .snf_txrspflit        (snf_txrspflit),
    .snf_txrsplcrdv       (icn_snf_txrsplcrdv),

    .snf_txdatflitv       (snf_txdatflitv),
    .snf_txdatflit        (snf_txdatflit),
    .snf_txdatlcrdv       (icn_snf_txdatlcrdv),

    .snf_txlinkactivereq  (snf_txlinkactivereq),
    .snf_txlinkactiveack  (snf_txlinkactiveack),
    .snf_rxlinkactivereq  (snf_rxlinkactivereq),
    .snf_rxlinkactiveack  (snf_rxlinkactiveack),
    .snf_txactive         (snf_txactive),
    .snf_rxactive         (snf_rxactive)
  );

  `ifndef TB_NO_MONITOR
    chi_monitor #(
      .CORE_COUNT (CORE_COUNT),

      .CHIE_REQ_ADDR_WIDTH_PARAM   (CHIE_REQ_ADDR_WIDTH_PARAM),
      .CHIE_SNP_ADDR_WIDTH_PARAM   (CHIE_SNP_ADDR_WIDTH_PARAM),
      .CHIE_NID_WIDTH_PARAM        (CHIE_NID_WIDTH_PARAM),
      .CHIE_DATA_WIDTH_PARAM       (CHIE_DATA_WIDTH_PARAM),
      .CHIE_BE_WIDTH_PARAM         (CHIE_BE_WIDTH_PARAM),
      .CHIE_DATACHECK_WIDTH_PARAM  (CHIE_DATACHECK_WIDTH_PARAM),
      .CHIE_POISON_WIDTH_PARAM     (CHIE_POISON_WIDTH_PARAM),
      .CHIE_REQ_RSVDC_WIDTH_PARAM  (CHIE_REQ_RSVDC_WIDTH_PARAM),
      .CHIE_DAT_RSVDC_WIDTH_PARAM  (CHIE_DAT_RSVDC_WIDTH_PARAM),
      .HNF_MSHR_RNF_NUM_PARAM      (HNF_MSHR_RNF_NUM_PARAM),
      .HNF_MSHR_RNI_NUM_PARAM      (HNF_MSHR_RNI_NUM_PARAM),
      .RNF_NID_LIST_PARAM          (RNF_NID_LIST_PARAM),
      .RNI_NID_LIST_PARAM          (RNI_NID_LIST_PARAM),
      .HNF_NID_PARAM               (HNF_NID_PARAM),
      .SNF_NID_PARAM               (SNF_NID_PARAM),
      .XP_LCRD_NUM_PARAM           (XP_LCRD_NUM_PARAM),
      .HNF_SF_ENTRIES_NUM_PARAM    (HNF_SF_ENTRIES_NUM_PARAM),
      .HNF_SF_WAY_NUM_PARAM        (HNF_SF_WAY_NUM_PARAM),
      .HNF_MSHR_EXCL_RN_NUM_PARAM  (HNF_MSHR_EXCL_RN_NUM_PARAM),
      .HNF_MSHR_EXCL_RN_WIDTH_PARAM(HNF_MSHR_EXCL_RN_WIDTH_PARAM),
      .HNF_MSHR_ENTRIES_NUM_PARAM  (HNF_MSHR_ENTRIES_NUM_PARAM),
      .HNF_MSHR_ENTRIES_WIDTH_PARAM(HNF_MSHR_ENTRIES_WIDTH_PARAM),
      .HNF_L3_CACHE_SIZE_PARAM     (HNF_L3_CACHE_SIZE_PARAM),
      .HNF_L3_WAY_NUM_PARAM        (HNF_L3_WAY_NUM_PARAM)
    ) u_chi_monitor (
      .clk                  (clk),
      .rst                  (~(rst_n & program_load_done)),

      // --- RNF VECTORIZED INTERFACE ---
      // These connect to your arrayed signals from the cores
      .rnf_txreqflitv       (rnf_txreqflitv),
      .rnf_txreqflit        (rnf_txreqflit),
      .rnf_txreqlcrdv       (rnf_txreqlcrdv),

      .rnf_txrspflitv       (rnf_txrspflitv),
      .rnf_txrspflit        (rnf_txrspflit),
      .rnf_txrsplcrdv       (rnf_txrsplcrdv),

      .rnf_txdatflitv       (rnf_txdatflitv),
      .rnf_txdatflit        (rnf_txdatflit),
      .rnf_txdatlcrdv       (rnf_txdatlcrdv),

      .rnf_rxsnpflitv       (rnf_rxsnpflitv),
      .rnf_rxsnppend        (icn_rnf_rxsnppend),
      .rnf_rxsnpflit        (rnf_rxsnpflit),
      .rnf_rxsnplcrdv       (rnf_rxsnplcrdv),

      .rnf_rxrspflitv       (rnf_rxrspflitv),
      .rnf_rxrsppend        (icn_rnf_rxrsppend),
      .rnf_rxrspflit        (rnf_rxrspflit),
      .rnf_rxrsplcrdv       (rnf_rxrsplcrdv),

      .rnf_rxdatflitv       (rnf_rxdatflitv),
      .rnf_rxdatpend        (icn_rnf_rxdatpend),
      .rnf_rxdatflit        (rnf_rxdatflit),
      .rnf_rxdatlcrdv       (rnf_rxdatlcrdv),


      // --- HNF INTERFACE (Connected via your Arbiter/Mux) ---
      .hnf_rxreqflitv       (icn_hnf_rxreqflitv), // Internal wires from arbiter
      .hnf_rxreqflit        (icn_hnf_rxreqflit),
      .hnf_rxreqpend        (icn_hnf_rxreqpend),
      .hnf_rxreqlcrdv       (hnf_rxreqlcrdv),

      .hnf_rxrspflitv       (icn_hnf_rxrspflitv),
      .hnf_rxrspflit        (icn_hnf_rxrspflit),
      .hnf_rxrsppend        (icn_hnf_rxrsppend),
      .hnf_rxrsplcrdv       (hnf_rxrsplcrdv),

      .hnf_rxdatflitv       (icn_hnf_rxdatflitv),
      .hnf_rxdatflit        (icn_hnf_rxdatflit),
      .hnf_rxdatpend        (icn_hnf_rxdatpend),
      .hnf_rxdatlcrdv       (hnf_rxdatlcrdv),

      .hnf_txreqflitv       (hnf_txreqflitv),
      .hnf_txreqflit        (hnf_txreqflit),
      .hnf_txreqpend        (hnf_txreqpend),
      .hnf_txreqlcrdv       (hnf_txreqlcrdv),

      .hnf_txsnpflitv       (hnf_txsnpflitv),
      .hnf_txsnpflit        (hnf_txsnpflit),
      .hnf_txsnppend        (hnf_txsnppend),
      .hnf_txsnplcrdv       (hnf_txsnplcrdv),

      .hnf_txrspflitv       (hnf_txrspflitv),
      .hnf_txrspflit        (hnf_txrspflit),
      .hnf_txrsppend        (hnf_txrsppend),
      .hnf_txrsplcrdv       (hnf_txrsplcrdv),

      .hnf_txdatflitv       (hnf_txdatflitv),
      .hnf_txdatflit        (hnf_txdatflit),
      .hnf_txdatpend        (hnf_txdatpend),
      .hnf_txdatlcrdv       (hnf_txdatlcrdv),

      // --- SNF INTERFACE (Slave Node / Memory) ---
      .snf_rxreqflitv       (icn_snf_rxreqflitv),
      .snf_rxreqflit        (icn_snf_rxreqflit),
      .snf_rxreqlcrdv       (snf_rxreqlcrdv),

      .snf_rxdatflitv       (icn_snf_rxdatflitv),
      .snf_rxdatflit        (icn_snf_rxdatflit),
      .snf_rxdatlcrdv       (snf_rxdatlcrdv),

      .snf_txrspflitv       (snf_txrspflitv),
      .snf_txrspflit        (snf_txrspflit),
      .snf_txrsplcrdv       (icn_snf_txrsplcrdv),

      .snf_txdatflitv       (snf_txdatflitv),
      .snf_txdatflit        (snf_txdatflit),
      .snf_txdatlcrdv       (icn_snf_txdatlcrdv)

    );
  `endif

  initial begin
    program_load_done = 1'b0;
    wait(rst_n === 1'b1);
    // Hold the RN-F cluster in reset while the L1.5's bram_1rw_wrapper
    // BIST-clear finishes.  The wrapper walks 2^ADDR_WIDTH addresses
    // (worst case 512 cycles on data + hmt SRAMs) writing zero, and
    // during that window any transducer write is redirected to
    // bist_index -- releasing rst too early lets CVA6's first fetch
    // land on corrupted SRAM state.  Wait 2000 cycles (~4x BIST
    // duration) to be safely past init on every configuration.
    repeat (2000) @(posedge clk);
    program_load_done = 1'b1;
    $display("TB: gem5 co-sim mode -- memory loaded by gem5, L1.5 BIST clear complete, starting RNF");
    while(1);
  end



  endmodule