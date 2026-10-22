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
 * tlm_rnf_hnf_tb.sv — Top-level testbench for RTL HN-F with TLM RN-F packet
 * injectors.  Replaces the CVA6 RTL RN-Fs used in riscv_rnf_hnf_tb.sv with
 * two SystemC/TLM chi_tlm_rnf instances (pure Questa SV+SC co-simulation —
 * no gem5, no IPC bridge).
 *
 * Compile flow (from cva6-RNF/ directory):
 *
 *   export QUESTA=/path/to/questa_24.x
 *   export PROJ_ROOT=$(pwd)/..
 *   source setup_piton.sh
 *
 *   vlib questa_build/work
 *   cd questa_build
 *
 *   # 1. Compile the SC TLM RNF model
 *   sccom -suppress sccom-94 -O2 -std=c++14 -I../tb \
 *       ../tb/cosim/chi_tlm_rnf.cpp
 *
 *   # 2. Link the shared library  (replace <ver> with sccom-generated gcc version suffix)
 *   g++ -std=c++14 -shared -fPIC -o work/systemc.so \
 *       work/_sc/linux_x86_64_gcc-<ver>/chi_tlm_rnf.o \
 *       $QUESTA/linux_x86_64/libsystemc_gcc103.a -lrt
 *
 *   # 3. Compile all SV/RTL sources
 *   vlog -sv -work work -mfcu -suppress 2583 -f ../tb/cosim/chi_tlm_flist
 *
 *   # 4. Run (add -vopt for optimised elaboration)
 *   vsim -c work.tlm_rnf_hnf_tb -do "run -all; quit"
 *
 * NOTE on Questa sc_bv port widths:
 *   Questa's SC→SV bridge handles sc_bv<N> (2-state) correctly for any N.
 *   The known ">32 bit" propagation bug affects sc_lv (4-state) only.
 *   If unusually wide ports appear broken, see the DPI bypass pattern in
 *   tb/questa_top_ipc_wrap.sv.
 */

`timescale 1ns/1ps

`include "rnf_defines.v"
`include "hnf_defines.v"
`include "snf_defines.v"
`include "chie_defines.v"

// `define TB_SNF       // Uncomment to use lightweight tb_snf instead of mem_ss
// `define TB_NO_MONITOR

module tlm_rnf_hnf_tb;

  // ── DPI-C bridge for SC plusargs ─────────────────────────────────────────────
  // sc_main's argc/argv do not carry vsim plusargs in Questa SV+SC co-sim.
  // SV reads the flags and pokes the SC globals via these DPI-C functions.
  import "DPI-C" function void chi_set_rnf_verbose();

  // ── Parameters ──────────────────────────────────────────────────────────────
  parameter int  CORE_COUNT = 2;
  parameter real CLK_PERIOD = 10.0;

  parameter CHIE_REQ_ADDR_WIDTH_PARAM  = 44;
  parameter CHIE_SNP_ADDR_WIDTH_PARAM  = 41;
  parameter CHIE_NID_WIDTH_PARAM       = 7;
  parameter CHIE_DATA_WIDTH_PARAM      = 256;
  parameter CHIE_BE_WIDTH_PARAM        = 32;
  parameter CHIE_DATACHECK_WIDTH_PARAM = 0;
  parameter CHIE_POISON_WIDTH_PARAM    = 0;
  parameter CHIE_REQ_RSVDC_WIDTH_PARAM = 0;
  parameter CHIE_DAT_RSVDC_WIDTH_PARAM = 0;
  parameter HNF_MSHR_RNF_NUM_PARAM     = 4;
  parameter HNF_MSHR_RNI_NUM_PARAM     = 0;
  // HNF_MSHR_RNF_NUM_PARAM=4 -> NID list is 4*7=28 bits.  The testbench
  // only instantiates 2 RN-Fs (NID 0 and 1).  The remaining 2 list slots
  // must contain NIDs that NO actual RN-F will ever use, otherwise the
  // cache_pipeline's nodeid-to-physical-position search (lines 850-859 of
  // hnf_cache_pipeline.v) finds spurious matches at the padded positions
  // and resolves `pipe_physical_nodeid_sx2` to the wrong slot.  This
  // miswires `pipe_sf_self_mask_sx3_q`, which is supposed to exclude the
  // requester from the snoop-target vector -- with a wrong mask, the
  // requester gets self-snooped, deadlocking the MSHR for atomic ops
  // where the requester is also a current SF holder.  Pad with 7'd126
  // and 7'd127 (reserved, no RN-F uses these NIDs).
  parameter RNF_NID_LIST_PARAM         = {7'd127, 7'd126, 7'd1, 7'd0};
  parameter RNI_NID_LIST_PARAM         = {7'd64};
`ifdef ICN_MESH
  // OpenNoC mesh uses NID = {X[2:0], Y[2:0], port[0]} (7 bits) — X in
  // the upper 3 bits per chi_xp_channel.v route_xy() decode.
  // HNF at XP(1,0)/P0 → 7'b001_000_0 = 16 (was 2; wrong encoding
  // routed to XP(0,1) — an unused corner — causing deadlock).
  // SNF at XP(1,1)/P0 → 7'b001_001_0 = 18.
  parameter HNF_NID_PARAM              = 16;
  parameter SNF_NID_PARAM              = 18;
`else
  parameter HNF_NID_PARAM              = 2;
  parameter SNF_NID_PARAM              = 32;
`endif
  parameter XP_LCRD_NUM_PARAM          = 15;
  parameter HNF_SF_ENTRIES_NUM_PARAM   = 131072;
  parameter HNF_SF_WAY_NUM_PARAM       = 16;
  parameter HNF_MSHR_EXCL_RN_NUM_PARAM = 32;
  parameter HNF_MSHR_EXCL_RN_WIDTH_PARAM = 5;
  parameter HNF_MSHR_ENTRIES_NUM_PARAM = 32;
  parameter HNF_MSHR_ENTRIES_WIDTH_PARAM = 5;
  parameter HNF_L3_CACHE_SIZE_PARAM    = 4096;
  parameter HNF_L3_WAY_NUM_PARAM       = 16;

  // ── Clock & Reset ────────────────────────────────────────────────────────────
  logic clk, rst_n;

  initial clk = 0;
  always #(CLK_PERIOD/2.0) clk = ~clk;

  initial begin
    rst_n = 1'b0;
    #(CLK_PERIOD * 10) rst_n = 1'b1;
  end

  // Hard simulation timeout — SC model should call sc_stop() before this fires.
  // Budget: 10000-cycle HNF init + 12000-cycle SC wait + transaction latency.
  initial begin
    #2_000_000;   // 2 ms at 1 ns timescale (200000 cycles)
    $display("[TB] TIMEOUT at %0t — simulation did not finish in time", $time);
    $finish;
  end

  // Propagate vsim plusargs into the SC domain via DPI-C.
  // Must run before the SC threads wake up (time 0, before any clock edge).
  initial begin
    if ($test$plusargs("rnf_verbose")) chi_set_rnf_verbose();
  end

  // ── Per-RNF scalar wires (SC module ↔ TB) ───────────────────────────────────
  // RNF0
  logic                                rnf0_txreq_flitv,  rnf0_txreq_flitpend;
  logic [`CHIE_REQ_FLIT_WIDTH-1:0]     rnf0_txreq_flit;
  logic                                rnf0_txreq_lcrdv;

  logic                                rnf0_txrsp_flitv,  rnf0_txrsp_flitpend;
  logic [`CHIE_RSP_FLIT_WIDTH-1:0]     rnf0_txrsp_flit;
  logic                                rnf0_txrsp_lcrdv;

  logic                                rnf0_txdat_flitv,  rnf0_txdat_flitpend;
  logic [`CHIE_DAT_FLIT_WIDTH-1:0]     rnf0_txdat_flit;
  logic                                rnf0_txdat_lcrdv;

  logic                                rnf0_rxrsp_flitv,  rnf0_rxrsp_flitpend;
  logic [`CHIE_RSP_FLIT_WIDTH-1:0]     rnf0_rxrsp_flit;
  logic                                rnf0_rxrsp_lcrdv;

  logic                                rnf0_rxdat_flitv,  rnf0_rxdat_flitpend;
  logic [`CHIE_DAT_FLIT_WIDTH-1:0]     rnf0_rxdat_flit;
  logic                                rnf0_rxdat_lcrdv;

  logic                                rnf0_rxsnp_flitv,  rnf0_rxsnp_flitpend;
  logic [`CHIE_SNP_FLIT_WIDTH-1:0]     rnf0_rxsnp_flit;
  logic                                rnf0_rxsnp_lcrdv;

  logic                                rnf0_txlinkactivereq, rnf0_txlinkactiveack;
  logic                                rnf0_rxlinkactivereq, rnf0_rxlinkactiveack;

  // RNF1
  logic                                rnf1_txreq_flitv,  rnf1_txreq_flitpend;
  logic [`CHIE_REQ_FLIT_WIDTH-1:0]     rnf1_txreq_flit;
  logic                                rnf1_txreq_lcrdv;

  logic                                rnf1_txrsp_flitv,  rnf1_txrsp_flitpend;
  logic [`CHIE_RSP_FLIT_WIDTH-1:0]     rnf1_txrsp_flit;
  logic                                rnf1_txrsp_lcrdv;

  logic                                rnf1_txdat_flitv,  rnf1_txdat_flitpend;
  logic [`CHIE_DAT_FLIT_WIDTH-1:0]     rnf1_txdat_flit;
  logic                                rnf1_txdat_lcrdv;

  logic                                rnf1_rxrsp_flitv,  rnf1_rxrsp_flitpend;
  logic [`CHIE_RSP_FLIT_WIDTH-1:0]     rnf1_rxrsp_flit;
  logic                                rnf1_rxrsp_lcrdv;

  logic                                rnf1_rxdat_flitv,  rnf1_rxdat_flitpend;
  logic [`CHIE_DAT_FLIT_WIDTH-1:0]     rnf1_rxdat_flit;
  logic                                rnf1_rxdat_lcrdv;

  logic                                rnf1_rxsnp_flitv,  rnf1_rxsnp_flitpend;
  logic [`CHIE_SNP_FLIT_WIDTH-1:0]     rnf1_rxsnp_flit;
  logic                                rnf1_rxsnp_lcrdv;

  logic                                rnf1_txlinkactivereq, rnf1_txlinkactiveack;
  logic                                rnf1_rxlinkactivereq, rnf1_rxlinkactiveack;

  // ── Vectorised RNF arrays for ICN / monitor ──────────────────────────────────
  // TX (RNF → ICN)
  logic [CORE_COUNT-1:0]                         rnf_txreqflitv, rnf_txreqflitpend;
  logic [CORE_COUNT-1:0][`CHIE_REQ_FLIT_WIDTH-1:0] rnf_txreqflit;
  logic [CORE_COUNT-1:0]                         rnf_txreqlcrdv;

  logic [CORE_COUNT-1:0]                         rnf_txrspflitv, rnf_txrspflitpend;
  logic [CORE_COUNT-1:0][`CHIE_RSP_FLIT_WIDTH-1:0] rnf_txrspflit;
  logic [CORE_COUNT-1:0]                         rnf_txrsplcrdv;

  logic [CORE_COUNT-1:0]                         rnf_txdatflitv, rnf_txdatflitpend;
  logic [CORE_COUNT-1:0][`CHIE_DAT_FLIT_WIDTH-1:0] rnf_txdatflit;
  logic [CORE_COUNT-1:0]                         rnf_txdatlcrdv;

  // RX (ICN → RNF)
  logic [CORE_COUNT-1:0]                         rnf_rxrspflitv;
  logic [CORE_COUNT-1:0]                         icn_rnf_rxrsppend;
  logic [CORE_COUNT-1:0][`CHIE_RSP_FLIT_WIDTH-1:0] rnf_rxrspflit;
  logic [CORE_COUNT-1:0]                         rnf_rxrsplcrdv;

  logic [CORE_COUNT-1:0]                         rnf_rxdatflitv;
  logic [CORE_COUNT-1:0]                         icn_rnf_rxdatpend;
  logic [CORE_COUNT-1:0][`CHIE_DAT_FLIT_WIDTH-1:0] rnf_rxdatflit;
  logic [CORE_COUNT-1:0]                         rnf_rxdatlcrdv;

  logic [CORE_COUNT-1:0]                         rnf_rxsnpflitv;
  logic [CORE_COUNT-1:0]                         icn_rnf_rxsnppend;
  logic [CORE_COUNT-1:0][`CHIE_SNP_FLIT_WIDTH-1:0] rnf_rxsnpflit;
  logic [CORE_COUNT-1:0]                         rnf_rxsnplcrdv;

  // Link activation (vectorised)
  logic [CORE_COUNT-1:0]                         rnf_txlinkactivereq, rnf_txlinkactiveack;
  logic [CORE_COUNT-1:0]                         rnf_rxlinkactivereq, rnf_rxlinkactiveack;
  logic [CORE_COUNT-1:0]                         rnf_txactive, rnf_rxactive;

  // ── Pack scalar → vectorised (TX: SC → ICN) ─────────────────────────────────
  assign rnf_txreqflitv[0]    = rnf0_txreq_flitv;
  assign rnf_txreqflitpend[0] = rnf0_txreq_flitpend;
  assign rnf_txreqflit[0]     = rnf0_txreq_flit;
  assign rnf_txrspflitv[0]    = rnf0_txrsp_flitv;
  assign rnf_txrspflitpend[0] = rnf0_txrsp_flitpend;
  assign rnf_txrspflit[0]     = rnf0_txrsp_flit;
  assign rnf_txdatflitv[0]    = rnf0_txdat_flitv;
  assign rnf_txdatflitpend[0] = rnf0_txdat_flitpend;
  assign rnf_txdatflit[0]     = rnf0_txdat_flit;
  assign rnf_rxrsplcrdv[0]    = rnf0_rxrsp_lcrdv;
  assign rnf_rxdatlcrdv[0]    = rnf0_rxdat_lcrdv;
  assign rnf_rxsnplcrdv[0]    = rnf0_rxsnp_lcrdv;
  assign rnf_txlinkactivereq[0] = rnf0_txlinkactivereq;
  assign rnf_rxlinkactiveack[0] = rnf0_rxlinkactiveack;
  assign rnf_txactive[0]      = rnf0_txlinkactivereq;  // proxy for txactive

  assign rnf_txreqflitv[1]    = rnf1_txreq_flitv;
  assign rnf_txreqflitpend[1] = rnf1_txreq_flitpend;
  assign rnf_txreqflit[1]     = rnf1_txreq_flit;
  assign rnf_txrspflitv[1]    = rnf1_txrsp_flitv;
  assign rnf_txrspflitpend[1] = rnf1_txrsp_flitpend;
  assign rnf_txrspflit[1]     = rnf1_txrsp_flit;
  assign rnf_txdatflitv[1]    = rnf1_txdat_flitv;
  assign rnf_txdatflitpend[1] = rnf1_txdat_flitpend;
  assign rnf_txdatflit[1]     = rnf1_txdat_flit;
  assign rnf_rxrsplcrdv[1]    = rnf1_rxrsp_lcrdv;
  assign rnf_rxdatlcrdv[1]    = rnf1_rxdat_lcrdv;
  assign rnf_rxsnplcrdv[1]    = rnf1_rxsnp_lcrdv;
  assign rnf_txlinkactivereq[1] = rnf1_txlinkactivereq;
  assign rnf_rxlinkactiveack[1] = rnf1_rxlinkactiveack;
  assign rnf_txactive[1]      = rnf1_txlinkactivereq;

  // ── Unpack vectorised → scalar (RX: ICN → SC) ────────────────────────────────
  assign rnf0_txreq_lcrdv     = rnf_txreqlcrdv[0];
  assign rnf0_txrsp_lcrdv     = rnf_txrsplcrdv[0];
  assign rnf0_txdat_lcrdv     = rnf_txdatlcrdv[0];
  assign rnf0_rxrsp_flitv     = rnf_rxrspflitv[0];
  assign rnf0_rxrsp_flitpend  = icn_rnf_rxrsppend[0];
  assign rnf0_rxrsp_flit      = rnf_rxrspflit[0];
  assign rnf0_rxdat_flitv     = rnf_rxdatflitv[0];
  assign rnf0_rxdat_flitpend  = icn_rnf_rxdatpend[0];
  assign rnf0_rxdat_flit      = rnf_rxdatflit[0];
  assign rnf0_rxsnp_flitv     = rnf_rxsnpflitv[0];
  assign rnf0_rxsnp_flitpend  = icn_rnf_rxsnppend[0];
  assign rnf0_rxsnp_flit      = rnf_rxsnpflit[0];
  assign rnf0_txlinkactiveack = rnf_txlinkactiveack[0];
  assign rnf0_rxlinkactivereq = rnf_rxlinkactivereq[0];

  assign rnf1_txreq_lcrdv     = rnf_txreqlcrdv[1];
  assign rnf1_txrsp_lcrdv     = rnf_txrsplcrdv[1];
  assign rnf1_txdat_lcrdv     = rnf_txdatlcrdv[1];
  assign rnf1_rxrsp_flitv     = rnf_rxrspflitv[1];
  assign rnf1_rxrsp_flitpend  = icn_rnf_rxrsppend[1];
  assign rnf1_rxrsp_flit      = rnf_rxrspflit[1];
  assign rnf1_rxdat_flitv     = rnf_rxdatflitv[1];
  assign rnf1_rxdat_flitpend  = icn_rnf_rxdatpend[1];
  assign rnf1_rxdat_flit      = rnf_rxdatflit[1];
  assign rnf1_rxsnp_flitv     = rnf_rxsnpflitv[1];
  assign rnf1_rxsnp_flitpend  = icn_rnf_rxsnppend[1];
  assign rnf1_rxsnp_flit      = rnf_rxsnpflit[1];
  assign rnf1_txlinkactiveack = rnf_txlinkactiveack[1];
  assign rnf1_rxlinkactivereq = rnf_rxlinkactivereq[1];

  // ── SC TLM RNF instances ─────────────────────────────────────────────────────
  // Questa discovers chi_tlm_rnf from work/systemc.so compiled by sccom.
  // The NID assignment (0 vs 1) is determined by elaboration order via the
  // static counter in chi_tlm_rnf::chi_tlm_rnf() — u_rnf0 gets NID=0 first.
  chi_tlm_rnf #(
    .CHIE_REQ_ADDR_WIDTH_PARAM (CHIE_REQ_ADDR_WIDTH_PARAM),
    .CHIE_SNP_ADDR_WIDTH_PARAM (CHIE_SNP_ADDR_WIDTH_PARAM),
    .CHIE_NID_WIDTH_PARAM      (CHIE_NID_WIDTH_PARAM),
    .CHIE_DATA_WIDTH_PARAM     (CHIE_DATA_WIDTH_PARAM),
    .CHIE_BE_WIDTH_PARAM       (CHIE_BE_WIDTH_PARAM),
    .CHIE_DATACHECK_WIDTH_PARAM(CHIE_DATACHECK_WIDTH_PARAM),
    .CHIE_POISON_WIDTH_PARAM   (CHIE_POISON_WIDTH_PARAM),
    .CHIE_REQ_RSVDC_WIDTH_PARAM(CHIE_REQ_RSVDC_WIDTH_PARAM),
    .CHIE_DAT_RSVDC_WIDTH_PARAM(CHIE_DAT_RSVDC_WIDTH_PARAM)
  ) u_rnf0 (
    .clk              (clk),
    .rstn             (rst_n),

    .txreq_flitv      (rnf0_txreq_flitv),
    .txreq_flitpend   (rnf0_txreq_flitpend),
    .txreq_flit       (rnf0_txreq_flit),
    .txreq_lcrdv      (rnf0_txreq_lcrdv),

    .txrsp_flitv      (rnf0_txrsp_flitv),
    .txrsp_flitpend   (rnf0_txrsp_flitpend),
    .txrsp_flit       (rnf0_txrsp_flit),
    .txrsp_lcrdv      (rnf0_txrsp_lcrdv),

    .txdat_flitv      (rnf0_txdat_flitv),
    .txdat_flitpend   (rnf0_txdat_flitpend),
    .txdat_flit       (rnf0_txdat_flit),
    .txdat_lcrdv      (rnf0_txdat_lcrdv),

    .rxrsp_flitv      (rnf0_rxrsp_flitv),
    .rxrsp_flitpend   (rnf0_rxrsp_flitpend),
    .rxrsp_flit       (rnf0_rxrsp_flit),
    .rxrsp_lcrdv      (rnf0_rxrsp_lcrdv),

    .rxdat_flitv      (rnf0_rxdat_flitv),
    .rxdat_flitpend   (rnf0_rxdat_flitpend),
    .rxdat_flit       (rnf0_rxdat_flit),
    .rxdat_lcrdv      (rnf0_rxdat_lcrdv),

    .rxsnp_flitv      (rnf0_rxsnp_flitv),
    .rxsnp_flitpend   (rnf0_rxsnp_flitpend),
    .rxsnp_flit       (rnf0_rxsnp_flit),
    .rxsnp_lcrdv      (rnf0_rxsnp_lcrdv),

    .txlinkactivereq  (rnf0_txlinkactivereq),
    .txlinkactiveack  (rnf0_txlinkactiveack),
    .rxlinkactivereq  (rnf0_rxlinkactivereq),
    .rxlinkactiveack  (rnf0_rxlinkactiveack)
  );

  chi_tlm_rnf #(
    .CHIE_REQ_ADDR_WIDTH_PARAM (CHIE_REQ_ADDR_WIDTH_PARAM),
    .CHIE_SNP_ADDR_WIDTH_PARAM (CHIE_SNP_ADDR_WIDTH_PARAM),
    .CHIE_NID_WIDTH_PARAM      (CHIE_NID_WIDTH_PARAM),
    .CHIE_DATA_WIDTH_PARAM     (CHIE_DATA_WIDTH_PARAM),
    .CHIE_BE_WIDTH_PARAM       (CHIE_BE_WIDTH_PARAM),
    .CHIE_DATACHECK_WIDTH_PARAM(CHIE_DATACHECK_WIDTH_PARAM),
    .CHIE_POISON_WIDTH_PARAM   (CHIE_POISON_WIDTH_PARAM),
    .CHIE_REQ_RSVDC_WIDTH_PARAM(CHIE_REQ_RSVDC_WIDTH_PARAM),
    .CHIE_DAT_RSVDC_WIDTH_PARAM(CHIE_DAT_RSVDC_WIDTH_PARAM)
  ) u_rnf1 (
    .clk              (clk),
    .rstn             (rst_n),

    .txreq_flitv      (rnf1_txreq_flitv),
    .txreq_flitpend   (rnf1_txreq_flitpend),
    .txreq_flit       (rnf1_txreq_flit),
    .txreq_lcrdv      (rnf1_txreq_lcrdv),

    .txrsp_flitv      (rnf1_txrsp_flitv),
    .txrsp_flitpend   (rnf1_txrsp_flitpend),
    .txrsp_flit       (rnf1_txrsp_flit),
    .txrsp_lcrdv      (rnf1_txrsp_lcrdv),

    .txdat_flitv      (rnf1_txdat_flitv),
    .txdat_flitpend   (rnf1_txdat_flitpend),
    .txdat_flit       (rnf1_txdat_flit),
    .txdat_lcrdv      (rnf1_txdat_lcrdv),

    .rxrsp_flitv      (rnf1_rxrsp_flitv),
    .rxrsp_flitpend   (rnf1_rxrsp_flitpend),
    .rxrsp_flit       (rnf1_rxrsp_flit),
    .rxrsp_lcrdv      (rnf1_rxrsp_lcrdv),

    .rxdat_flitv      (rnf1_rxdat_flitv),
    .rxdat_flitpend   (rnf1_rxdat_flitpend),
    .rxdat_flit       (rnf1_rxdat_flit),
    .rxdat_lcrdv      (rnf1_rxdat_lcrdv),

    .rxsnp_flitv      (rnf1_rxsnp_flitv),
    .rxsnp_flitpend   (rnf1_rxsnp_flitpend),
    .rxsnp_flit       (rnf1_rxsnp_flit),
    .rxsnp_lcrdv      (rnf1_rxsnp_lcrdv),

    .txlinkactivereq  (rnf1_txlinkactivereq),
    .txlinkactiveack  (rnf1_txlinkactiveack),
    .rxlinkactivereq  (rnf1_rxlinkactivereq),
    .rxlinkactiveack  (rnf1_rxlinkactiveack)
  );

  // ── HNF Bridge signals ───────────────────────────────────────────────────────
  logic                           hnf_txreqflitv, hnf_txreqpend;
  logic [`CHIE_REQ_FLIT_WIDTH-1:0] hnf_txreqflit;
  logic                           hnf_txrspflitv, hnf_txrspflitpend;
  logic [`CHIE_RSP_FLIT_WIDTH-1:0] hnf_txrspflit;
  logic                           hnf_txsnpflitv, hnf_txsnpflitpend;
  // HNF_SNP_FLIT_WIDTH = CHIE_SNP_FLIT_WIDTH + CHIE_NID_WIDTH (106 bits):
  // the upper 7 bits are the snoop target NID (set in hnf_link_txsnp_wrap.v
  // line 174). chi_icn_beh silently truncates them; chi_icn_mesh routes on them.
  logic [`HNF_SNP_FLIT_WIDTH-1:0] hnf_txsnpflit;
  logic                           hnf_txdatflitv, hnf_txdatflitpend;
  logic [`CHIE_DAT_FLIT_WIDTH-1:0] hnf_txdatflit;

  logic                           icn_hnf_rxreqflitv, icn_hnf_rxreqpend;
  logic [`CHIE_REQ_FLIT_WIDTH-1:0] icn_hnf_rxreqflit;
  logic                           icn_hnf_rxrspflitv, icn_hnf_rxrsppend;
  logic [`CHIE_RSP_FLIT_WIDTH-1:0] icn_hnf_rxrspflit;
  logic                           icn_hnf_rxdatflitv, icn_hnf_rxdatpend;
  logic [`CHIE_DAT_FLIT_WIDTH-1:0] icn_hnf_rxdatflit;

  logic  hnf_rxreqlcrdv, hnf_rxrsplcrdv, hnf_rxdatlcrdv;
  logic  hnf_txreqlcrdv, hnf_txrsplcrdv, hnf_txsnplcrdv, hnf_txdatlcrdv;
  logic [2:0] hnf_notify;

  // ── SNF / Memory Subsystem signals ──────────────────────────────────────────
  logic                           icn_snf_rxreqflitv;
  logic [`CHIE_REQ_FLIT_WIDTH-1:0] icn_snf_rxreqflit;
  logic                           icn_snf_rxdatflitv;
  logic [`CHIE_DAT_FLIT_WIDTH-1:0] icn_snf_rxdatflit;
  logic                           snf_txrspflitv;
  logic [`CHIE_RSP_FLIT_WIDTH-1:0] snf_txrspflit;
  logic                           snf_txrspflitpend;   // mem_ss only; tb_snf doesn't drive
  logic                           snf_txdatflitv;
  logic [`CHIE_DAT_FLIT_WIDTH-1:0] snf_txdatflit;
  logic                           snf_txdatflitpend;
  logic  icn_snf_txrsplcrdv, icn_snf_txdatlcrdv;
  logic  snf_rxreqlcrdv, snf_rxdatlcrdv;
  logic  snf_txlinkactivereq, snf_txlinkactiveack;
  logic  snf_rxlinkactivereq, snf_rxlinkactiveack;
  logic  snf_txactive, snf_rxactive;

`ifndef TB_MEM_SS
  // tb_snf doesn't drive link-activate signals — tie them on so the ICN
  // sees the SNF as always-active. mem_ss has real link-activate logic
  // and drives these itself, so skip the tie-off in that case.
  assign snf_txlinkactivereq = 1'b1;
  assign snf_rxlinkactiveack = 1'b1;
  assign snf_txactive        = 1'b1;
  assign snf_rxdatlcrdv      = 1'b1;
`endif

  // ── 1. RTL HN-F ──────────────────────────────────────────────────────────────
  hnf #(
    .CHIE_REQ_ADDR_WIDTH_PARAM    (CHIE_REQ_ADDR_WIDTH_PARAM),
    .CHIE_SNP_ADDR_WIDTH_PARAM    (CHIE_SNP_ADDR_WIDTH_PARAM),
    .CHIE_NID_WIDTH_PARAM         (CHIE_NID_WIDTH_PARAM),
    .CHIE_DATA_WIDTH_PARAM        (CHIE_DATA_WIDTH_PARAM),
    .CHIE_BE_WIDTH_PARAM          (CHIE_BE_WIDTH_PARAM),
    .CHIE_DATACHECK_WIDTH_PARAM   (CHIE_DATACHECK_WIDTH_PARAM),
    .CHIE_POISON_WIDTH_PARAM      (CHIE_POISON_WIDTH_PARAM),
    .CHIE_REQ_RSVDC_WIDTH_PARAM   (CHIE_REQ_RSVDC_WIDTH_PARAM),
    .CHIE_DAT_RSVDC_WIDTH_PARAM   (CHIE_DAT_RSVDC_WIDTH_PARAM),
    .HNF_MSHR_RNF_NUM_PARAM       (HNF_MSHR_RNF_NUM_PARAM),
    .HNF_MSHR_RNI_NUM_PARAM       (HNF_MSHR_RNI_NUM_PARAM),
    .RNF_NID_LIST_PARAM           (RNF_NID_LIST_PARAM),
    .RNI_NID_LIST_PARAM           (RNI_NID_LIST_PARAM),
    .HNF_NID_PARAM                (HNF_NID_PARAM),
    .SNF_NID_PARAM                (SNF_NID_PARAM),
    .XP_LCRD_NUM_PARAM            (XP_LCRD_NUM_PARAM),
    .HNF_SF_ENTRIES_NUM_PARAM     (HNF_SF_ENTRIES_NUM_PARAM),
    .HNF_SF_WAY_NUM_PARAM         (HNF_SF_WAY_NUM_PARAM),
    .HNF_MSHR_EXCL_RN_NUM_PARAM   (HNF_MSHR_EXCL_RN_NUM_PARAM),
    .HNF_MSHR_EXCL_RN_WIDTH_PARAM (HNF_MSHR_EXCL_RN_WIDTH_PARAM),
    .HNF_MSHR_ENTRIES_NUM_PARAM   (HNF_MSHR_ENTRIES_NUM_PARAM),
    .HNF_MSHR_ENTRIES_WIDTH_PARAM (HNF_MSHR_ENTRIES_WIDTH_PARAM),
    .HNF_L3_CACHE_SIZE_PARAM      (HNF_L3_CACHE_SIZE_PARAM),
    .HNF_L3_WAY_NUM_PARAM         (HNF_L3_WAY_NUM_PARAM)
  ) u_hnf (
    .CLK              (clk),
    .RST              (~rst_n),

    .RXREQFLITV       (icn_hnf_rxreqflitv),
    .RXREQFLIT        (icn_hnf_rxreqflit),
    .RXREQFLITPEND    (icn_hnf_rxreqpend),
    .RXRSPFLITV       (icn_hnf_rxrspflitv),
    .RXRSPFLIT        (icn_hnf_rxrspflit),
    .RXRSPFLITPEND    (icn_hnf_rxrsppend),
    .RXDATFLITV       (icn_hnf_rxdatflitv),
    .RXDATFLIT        (icn_hnf_rxdatflit),
    .RXDATFLITPEND    (icn_hnf_rxdatpend),

    .TXREQFLITV       (hnf_txreqflitv),
    .TXREQFLIT        (hnf_txreqflit),
    .TXREQFLITPEND    (hnf_txreqpend),
    .TXRSPFLITV       (hnf_txrspflitv),
    .TXRSPFLIT        (hnf_txrspflit),
    .TXRSPFLITPEND    (hnf_txrspflitpend),
    .TXSNPFLITV       (hnf_txsnpflitv),
    .TXSNPFLIT        (hnf_txsnpflit),
    .TXSNPFLITPEND    (hnf_txsnpflitpend),
    .TXDATFLITV       (hnf_txdatflitv),
    .TXDATFLIT        (hnf_txdatflit),
    .TXDATFLITPEND    (hnf_txdatflitpend),

    .RXREQLCRDV       (hnf_rxreqlcrdv),
    .RXRSPLCRDV       (hnf_rxrsplcrdv),
    .RXDATLCRDV       (hnf_rxdatlcrdv),
    .TXREQLCRDV       (hnf_txreqlcrdv),
    .TXRSPLCRDV       (hnf_txrsplcrdv),
    .TXSNPLCRDV       (hnf_txsnplcrdv),
    .TXDATLCRDV       (hnf_txdatlcrdv),

    .notify_reg       (hnf_notify)
  );

  // ── 2. Slave Node — lightweight RTL SN-F ─────────────────────────────────────
  // Use tb_snf (SystemVerilog behavioural SRAM + CHI slave) by default.
  // Define TB_MEM_SS to switch to the full mem_ss model.
`ifndef TB_MEM_SS
  tb_snf #(
    .CHIE_REQ_ADDR_WIDTH_PARAM    (CHIE_REQ_ADDR_WIDTH_PARAM),
    .CHIE_SNP_ADDR_WIDTH_PARAM    (CHIE_SNP_ADDR_WIDTH_PARAM),
    .CHIE_NID_WIDTH_PARAM         (CHIE_NID_WIDTH_PARAM),
    .CHIE_DATA_WIDTH_PARAM        (CHIE_DATA_WIDTH_PARAM),
    .CHIE_BE_WIDTH_PARAM          (CHIE_BE_WIDTH_PARAM),
    .CHIE_DATACHECK_WIDTH_PARAM   (CHIE_DATACHECK_WIDTH_PARAM),
    .CHIE_POISON_WIDTH_PARAM      (CHIE_POISON_WIDTH_PARAM),
    .CHIE_REQ_RSVDC_WIDTH_PARAM   (CHIE_REQ_RSVDC_WIDTH_PARAM),
    .CHIE_DAT_RSVDC_WIDTH_PARAM   (CHIE_DAT_RSVDC_WIDTH_PARAM),
    .HNF_MSHR_RNF_NUM_PARAM       (HNF_MSHR_RNF_NUM_PARAM),
    .HNF_MSHR_RNI_NUM_PARAM       (HNF_MSHR_RNI_NUM_PARAM),
    .RNF_NID_LIST_PARAM           (RNF_NID_LIST_PARAM),
    .RNI_NID_LIST_PARAM           (RNI_NID_LIST_PARAM),
    .HNF_NID_PARAM                (HNF_NID_PARAM),
    .SNF_NID_PARAM                (SNF_NID_PARAM),
    .XP_LCRD_NUM_PARAM            (XP_LCRD_NUM_PARAM),
    .HNF_SF_ENTRIES_NUM_PARAM     (HNF_SF_ENTRIES_NUM_PARAM),
    .HNF_SF_WAY_NUM_PARAM         (HNF_SF_WAY_NUM_PARAM),
    .HNF_MSHR_EXCL_RN_NUM_PARAM   (HNF_MSHR_EXCL_RN_NUM_PARAM),
    .HNF_MSHR_EXCL_RN_WIDTH_PARAM (HNF_MSHR_EXCL_RN_WIDTH_PARAM),
    .HNF_MSHR_ENTRIES_NUM_PARAM   (HNF_MSHR_ENTRIES_NUM_PARAM),
    .HNF_MSHR_ENTRIES_WIDTH_PARAM (HNF_MSHR_ENTRIES_WIDTH_PARAM),
    .HNF_L3_CACHE_SIZE_PARAM      (HNF_L3_CACHE_SIZE_PARAM),
    .HNF_L3_WAY_NUM_PARAM         (HNF_L3_WAY_NUM_PARAM)
  ) u_tb_snf (
    .CLK             (clk),
    .RST             (~rst_n),

    .RXREQFLITV      (icn_snf_rxreqflitv),
    .RXREQFLIT       (icn_snf_rxreqflit),
    .RXREQLCRDTV     (snf_rxreqlcrdv),

    .RXDATFLITV      (icn_snf_rxdatflitv),
    .RXDATFLIT       (icn_snf_rxdatflit),

    .TXRSPFLITV      (snf_txrspflitv),
    .TXRSPFLIT       (snf_txrspflit),
    .TXDATFLITV      (snf_txdatflitv),
    .TXDATFLIT       (snf_txdatflit),

    .dbg_sn_wr_en    (1'b0),
    .dbg_sn_wr_data  ('0),
    .dbg_sn_addr     ('0),
    .dbg_sn_rd_en    (1'b0),
    .dbg_sn_rd_data  ()
  );
  // tb_snf has no FLITPEND outputs — tie to 0 so the signals don't float
  // (mem_ss drives them when SNF=memss; the ICN doesn't consume them yet).
  assign snf_txrspflitpend = 1'b0;
  assign snf_txdatflitpend = 1'b0;
`else
  // Full mem_ss (AXI-backed SRAM) — no preload needed for packet-injector tests
  mem_ss #(
    .CHIE_REQ_ADDR_WIDTH_PARAM    (CHIE_REQ_ADDR_WIDTH_PARAM),
    .CHIE_SNP_ADDR_WIDTH_PARAM    (CHIE_SNP_ADDR_WIDTH_PARAM),
    .CHIE_NID_WIDTH_PARAM         (CHIE_NID_WIDTH_PARAM),
    .CHIE_DATA_WIDTH_PARAM        (CHIE_DATA_WIDTH_PARAM),
    .CHIE_BE_WIDTH_PARAM          (CHIE_BE_WIDTH_PARAM),
    .CHIE_DATACHECK_WIDTH_PARAM   (CHIE_DATACHECK_WIDTH_PARAM),
    .CHIE_POISON_WIDTH_PARAM      (CHIE_POISON_WIDTH_PARAM),
    .CHIE_REQ_RSVDC_WIDTH_PARAM   (CHIE_REQ_RSVDC_WIDTH_PARAM),
    .CHIE_DAT_RSVDC_WIDTH_PARAM   (CHIE_DAT_RSVDC_WIDTH_PARAM),
    .HNF_MSHR_RNF_NUM_PARAM       (HNF_MSHR_RNF_NUM_PARAM),
    .HNF_MSHR_RNI_NUM_PARAM       (HNF_MSHR_RNI_NUM_PARAM),
    .RNF_NID_LIST_PARAM           (RNF_NID_LIST_PARAM),
    .RNI_NID_LIST_PARAM           (RNI_NID_LIST_PARAM),
    .HNF_NID_PARAM                (HNF_NID_PARAM),
    .SNF_NID_PARAM                (SNF_NID_PARAM),
    .XP_LCRD_NUM_PARAM            (XP_LCRD_NUM_PARAM),
    .HNF_SF_ENTRIES_NUM_PARAM     (HNF_SF_ENTRIES_NUM_PARAM),
    .HNF_SF_WAY_NUM_PARAM         (HNF_SF_WAY_NUM_PARAM),
    .HNF_MSHR_EXCL_RN_NUM_PARAM   (HNF_MSHR_EXCL_RN_NUM_PARAM),
    .HNF_MSHR_EXCL_RN_WIDTH_PARAM (HNF_MSHR_EXCL_RN_WIDTH_PARAM),
    .HNF_MSHR_ENTRIES_NUM_PARAM   (HNF_MSHR_ENTRIES_NUM_PARAM),
    .HNF_MSHR_ENTRIES_WIDTH_PARAM (HNF_MSHR_ENTRIES_WIDTH_PARAM),
    .HNF_L3_CACHE_SIZE_PARAM      (HNF_L3_CACHE_SIZE_PARAM),
    .HNF_L3_WAY_NUM_PARAM         (HNF_L3_WAY_NUM_PARAM),
    // AXI_DATA_WIDTH = CHIE link flit width (snf hardcodes 32-byte beats when
    //   AXI4_AXDATA_WIDTH != 128 — snf_mshr.v:619).
    // AXI_ID_WIDTH = 11 to match snf's hardcoded `AXI4_AXID_WIDTH = 11`
    //   (axi4_defines.v:24, snf_defines.v:116). 10 would silently truncate.
    .AXI_DATA_WIDTH               (CHIE_DATA_WIDTH_PARAM),
    .AXI_ADDR_WIDTH               (CHIE_REQ_ADDR_WIDTH_PARAM),
    .AXI_ID_WIDTH                 (11),
    .AXI_USER_WIDTH               (1)
  ) u_mem_ss (
    .CLK                (clk),
    .RST                (~rst_n),

    .TXLINKACTIVEREQ    (snf_txlinkactivereq),
    .TXLINKACTIVEACK    (snf_txlinkactiveack),
    .RXLINKACTIVEREQ    (snf_rxlinkactivereq),
    .RXLINKACTIVEACK    (snf_rxlinkactiveack),
    .TXSACTIVE          (snf_txactive),
    .RXSACTIVE          (snf_rxactive),

    .RXREQFLITV         (icn_snf_rxreqflitv),
    .RXREQFLIT          (icn_snf_rxreqflit),
    .RXREQFLITPEND      (1'b0),
    .RXREQLCRDV         (snf_rxreqlcrdv),

    .RXDATFLITV         (icn_snf_rxdatflitv),
    .RXDATFLIT          (icn_snf_rxdatflit),
    .RXDATFLITPEND      (1'b0),
    .RXDATLCRDV         (snf_rxdatlcrdv),

    .TXRSPFLITV         (snf_txrspflitv),
    .TXRSPFLIT          (snf_txrspflit),
    .TXRSPFLITPEND      (snf_txrspflitpend),
    .TXRSPLCRDV         (icn_snf_txrsplcrdv),

    .TXDATFLITV         (snf_txdatflitv),
    .TXDATFLIT          (snf_txdatflit),
    .TXDATFLITPEND      (snf_txdatflitpend),
    .TXDATLCRDV         (icn_snf_txdatlcrdv)
  );
`endif

  // ── 3. CHI Interconnect ──────────────────────────────────────────────────────
  // Default: chi_icn_beh (behavioral SV interconnect).
  // Set ICN=mesh in the Makefile (defines ICN_MESH) to swap in the OpenNoC
  // 2x2 mesh via the chi_icn_mesh adapter (same port list, different routing).
`ifdef ICN_MESH
  chi_icn_mesh #(
`else
  chi_icn_beh #(
`endif
    .CORE_COUNT                   (CORE_COUNT),
    .CHIE_REQ_ADDR_WIDTH_PARAM    (CHIE_REQ_ADDR_WIDTH_PARAM),
    .CHIE_SNP_ADDR_WIDTH_PARAM    (CHIE_SNP_ADDR_WIDTH_PARAM),
    .CHIE_NID_WIDTH_PARAM         (CHIE_NID_WIDTH_PARAM),
    .CHIE_DATA_WIDTH_PARAM        (CHIE_DATA_WIDTH_PARAM),
    .CHIE_BE_WIDTH_PARAM          (CHIE_BE_WIDTH_PARAM),
    .CHIE_DATACHECK_WIDTH_PARAM   (CHIE_DATACHECK_WIDTH_PARAM),
    .CHIE_POISON_WIDTH_PARAM      (CHIE_POISON_WIDTH_PARAM),
    .CHIE_REQ_RSVDC_WIDTH_PARAM   (CHIE_REQ_RSVDC_WIDTH_PARAM),
    .CHIE_DAT_RSVDC_WIDTH_PARAM   (CHIE_DAT_RSVDC_WIDTH_PARAM),
    .HNF_MSHR_RNF_NUM_PARAM       (HNF_MSHR_RNF_NUM_PARAM),
    .HNF_MSHR_RNI_NUM_PARAM       (HNF_MSHR_RNI_NUM_PARAM),
    .RNF_NID_LIST_PARAM           (RNF_NID_LIST_PARAM),
    .RNI_NID_LIST_PARAM           (RNI_NID_LIST_PARAM),
    .HNF_NID_PARAM                (HNF_NID_PARAM),
    .SNF_NID_PARAM                (SNF_NID_PARAM),
    .XP_LCRD_NUM_PARAM            (XP_LCRD_NUM_PARAM),
    .HNF_SF_ENTRIES_NUM_PARAM     (HNF_SF_ENTRIES_NUM_PARAM),
    .HNF_SF_WAY_NUM_PARAM         (HNF_SF_WAY_NUM_PARAM),
    .HNF_MSHR_EXCL_RN_NUM_PARAM   (HNF_MSHR_EXCL_RN_NUM_PARAM),
    .HNF_MSHR_EXCL_RN_WIDTH_PARAM (HNF_MSHR_EXCL_RN_WIDTH_PARAM),
    .HNF_MSHR_ENTRIES_NUM_PARAM   (HNF_MSHR_ENTRIES_NUM_PARAM),
    .HNF_MSHR_ENTRIES_WIDTH_PARAM (HNF_MSHR_ENTRIES_WIDTH_PARAM),
    .HNF_L3_CACHE_SIZE_PARAM      (HNF_L3_CACHE_SIZE_PARAM),
    .HNF_L3_WAY_NUM_PARAM         (HNF_L3_WAY_NUM_PARAM)
  ) u_chi_icn (
    .clk                  (clk),
    .rst                  (~rst_n),

    // RNF vectorised TX
    .rnf_txreqflitv       (rnf_txreqflitv),
    .rnf_txreqflit        (rnf_txreqflit),
    .rnf_txreqlcrdv       (rnf_txreqlcrdv),
    .rnf_txrspflitv       (rnf_txrspflitv),
    .rnf_txrspflit        (rnf_txrspflit),
    .rnf_txrsplcrdv       (rnf_txrsplcrdv),
    .rnf_txdatflitv       (rnf_txdatflitv),
    .rnf_txdatflit        (rnf_txdatflit),
    .rnf_txdatlcrdv       (rnf_txdatlcrdv),

    // RNF vectorised RX
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

    // Link activation (vectorised)
    .rnf_txlinkactivereq  (rnf_txlinkactivereq),
    .rnf_txlinkactiveack  (rnf_txlinkactiveack),
    .rnf_rxlinkactivereq  (rnf_rxlinkactivereq),
    .rnf_rxlinkactiveack  (rnf_rxlinkactiveack),
    .rnf_txactive         (rnf_txactive),
    .rnf_rxactive         (rnf_rxactive),

    // HNF RX
    .hnf_rxreqflitv       (icn_hnf_rxreqflitv),
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

    // HNF TX
    .hnf_txreqflitv       (hnf_txreqflitv),
    .hnf_txreqflit        (hnf_txreqflit),
    .hnf_txreqpend        (hnf_txreqpend),
    .hnf_txreqlcrdv       (hnf_txreqlcrdv),
    .hnf_txsnpflitv       (hnf_txsnpflitv),
    .hnf_txsnpflit        (hnf_txsnpflit),
    .hnf_txsnppend        (hnf_txsnpflitpend),
    .hnf_txsnplcrdv       (hnf_txsnplcrdv),
    .hnf_txrspflitv       (hnf_txrspflitv),
    .hnf_txrspflit        (hnf_txrspflit),
    .hnf_txrsppend        (hnf_txrspflitpend),
    .hnf_txrsplcrdv       (hnf_txrsplcrdv),
    .hnf_txdatflitv       (hnf_txdatflitv),
    .hnf_txdatflit        (hnf_txdatflit),
    .hnf_txdatpend        (hnf_txdatflitpend),
    .hnf_txdatlcrdv       (hnf_txdatlcrdv),

    // SNF
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

  // ── 4. CHI Protocol Monitor ──────────────────────────────────────────────────
`ifndef TB_NO_MONITOR
  chi_monitor #(
    .CORE_COUNT                   (CORE_COUNT),
    .CHIE_REQ_ADDR_WIDTH_PARAM    (CHIE_REQ_ADDR_WIDTH_PARAM),
    .CHIE_SNP_ADDR_WIDTH_PARAM    (CHIE_SNP_ADDR_WIDTH_PARAM),
    .CHIE_NID_WIDTH_PARAM         (CHIE_NID_WIDTH_PARAM),
    .CHIE_DATA_WIDTH_PARAM        (CHIE_DATA_WIDTH_PARAM),
    .CHIE_BE_WIDTH_PARAM          (CHIE_BE_WIDTH_PARAM),
    .CHIE_DATACHECK_WIDTH_PARAM   (CHIE_DATACHECK_WIDTH_PARAM),
    .CHIE_POISON_WIDTH_PARAM      (CHIE_POISON_WIDTH_PARAM),
    .CHIE_REQ_RSVDC_WIDTH_PARAM   (CHIE_REQ_RSVDC_WIDTH_PARAM),
    .CHIE_DAT_RSVDC_WIDTH_PARAM   (CHIE_DAT_RSVDC_WIDTH_PARAM),
    .HNF_MSHR_RNF_NUM_PARAM       (HNF_MSHR_RNF_NUM_PARAM),
    .HNF_MSHR_RNI_NUM_PARAM       (HNF_MSHR_RNI_NUM_PARAM),
    .RNF_NID_LIST_PARAM           (RNF_NID_LIST_PARAM),
    .RNI_NID_LIST_PARAM           (RNI_NID_LIST_PARAM),
    .HNF_NID_PARAM                (HNF_NID_PARAM),
    .SNF_NID_PARAM                (SNF_NID_PARAM),
    .XP_LCRD_NUM_PARAM            (XP_LCRD_NUM_PARAM),
    .HNF_SF_ENTRIES_NUM_PARAM     (HNF_SF_ENTRIES_NUM_PARAM),
    .HNF_SF_WAY_NUM_PARAM         (HNF_SF_WAY_NUM_PARAM),
    .HNF_MSHR_EXCL_RN_NUM_PARAM   (HNF_MSHR_EXCL_RN_NUM_PARAM),
    .HNF_MSHR_EXCL_RN_WIDTH_PARAM (HNF_MSHR_EXCL_RN_WIDTH_PARAM),
    .HNF_MSHR_ENTRIES_NUM_PARAM   (HNF_MSHR_ENTRIES_NUM_PARAM),
    .HNF_MSHR_ENTRIES_WIDTH_PARAM (HNF_MSHR_ENTRIES_WIDTH_PARAM),
    .HNF_L3_CACHE_SIZE_PARAM      (HNF_L3_CACHE_SIZE_PARAM),
    .HNF_L3_WAY_NUM_PARAM         (HNF_L3_WAY_NUM_PARAM)
  ) u_chi_monitor (
    .clk                  (clk),
    .rst                  (~rst_n),

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

    .hnf_rxreqflitv       (icn_hnf_rxreqflitv),
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
    .hnf_txsnppend        (hnf_txsnpflitpend),
    .hnf_txsnplcrdv       (hnf_txsnplcrdv),
    .hnf_txrspflitv       (hnf_txrspflitv),
    .hnf_txrspflit        (hnf_txrspflit),
    .hnf_txrsppend        (hnf_txrspflitpend),
    .hnf_txrsplcrdv       (hnf_txrsplcrdv),
    .hnf_txdatflitv       (hnf_txdatflitv),
    .hnf_txdatflit        (hnf_txdatflit),
    .hnf_txdatpend        (hnf_txdatflitpend),
    .hnf_txdatlcrdv       (hnf_txdatlcrdv)
  );
`endif  // TB_NO_MONITOR

endmodule : tlm_rnf_hnf_tb
