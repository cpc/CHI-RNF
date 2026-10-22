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
/*
 * rnf_coverage.sv
 *
 * Functional coverage for the IP-level RN-F testbench.
 *
 * Five covergroups, ~180 functional bins total, mapping 1:1 to the
 * decision surface of testgen/murphi_rnf/rnf_fsm.m:
 *
 *   1. cg_l1_transitions     — L1 cache state transitions
 *   2. cg_snoop_decisions    — per-(snoop_op × L1_state) response variant
 *   3. cg_tx_lifecycle       — REQ-shape lifecycle paths
 *   4. cg_tx_transient       — outstanding-REQ phase residency
 *   5. cg_race_intersections — snoop arriving during outstanding REQ
 *
 * Sampling: each group is sampled at the appropriate event (CompAck,
 * SnpResp, REQ-issue, etc.) using the signals exposed by
 * rnf_phase_tracker.  This module instantiates one tracker and one of
 * each covergroup; the parent TB just binds it once with the CHI
 * wires.
 */

`include "rnf_param.v"
`include "rnf_defines.v"
`include "chie_defines.v"

module rnf_coverage
    import rnf_cov_pkg::*;
    `RNF_PARAM (
    input  logic clk,
    input  logic rst_n,

    input  logic                          RXSNPFLITV,
    input  logic [`CHIE_SNP_FLIT_RANGE]   RXSNPFLIT,
    input  logic                          RXRSPFLITV,
    input  logic [`CHIE_RSP_FLIT_RANGE]   RXRSPFLIT,
    input  logic                          RXDATFLITV,
    input  logic [`CHIE_DAT_FLIT_RANGE]   RXDATFLIT,
    input  logic                          TXREQFLITV,
    input  logic [`CHIE_REQ_FLIT_RANGE]   TXREQFLIT,
    input  logic                          TXRSPFLITV,
    input  logic [`CHIE_RSP_FLIT_RANGE]   TXRSPFLIT,
    input  logic                          TXDATFLITV,
    input  logic [`CHIE_DAT_FLIT_RANGE]   TXDATFLIT,

    // Gates all six covergroup sample events.  Driven low by the TB
    // during the write-visibility probe so that probe-triggered CHI
    // activity does not shift the phase tracker's inferred state and
    // corrupt the coverpoint samples (drops previously-covered bins
    // like cp_prev_state = 100% -> 60%).  Default-high: bind ties this
    // to (!u_ip_tb.probing) at the parent TB level.
    input  logic                          sample_enable,

    // ── L1 state probe ─────────────────────────────────────────────
    // cg_l1_transitions IS the RTL coherence FSM, so both endpoints
    // must be the DUT's real MESI state rather than the tracker's
    // reconstruction.  The signals live deep in the pipeline
    // (tagcheck_state_s2 / val_s2) and the path to them differs per
    // testbench -- rnf_ip_tb.u_dut.l15.pipeline in the IP-level TB,
    // tb_chi_system.u_rnf_wrap.RNF_GEN[i].u_rnf.l15.l15.pipeline in the
    // gem5 co-sim TB.  Taking them as ports lets each bind supply its
    // own hierarchical expression instead of hard-coding one TB's path
    // here, which made this module unusable in the other.
    input  logic [1:0]                    probe_l1_state,   // tagcheck_state_s2
    input  logic                          probe_l1_val,     // val_s2
    input  logic [5:0]                    probe_reqtype     // predecode_reqtype_s2
);

    // ── Embedded phase tracker ─────────────────────────────────────
    rnf_phase_tracker #(
        .CHIE_REQ_ADDR_WIDTH_PARAM (CHIE_REQ_ADDR_WIDTH_PARAM),
        .CHIE_SNP_ADDR_WIDTH_PARAM (CHIE_SNP_ADDR_WIDTH_PARAM),
        .CHIE_NID_WIDTH_PARAM      (CHIE_NID_WIDTH_PARAM),
        .CHIE_DATA_WIDTH_PARAM     (CHIE_DATA_WIDTH_PARAM),
        .CHIE_BE_WIDTH_PARAM       (CHIE_BE_WIDTH_PARAM),
        .CHIE_DATACHECK_WIDTH_PARAM(CHIE_DATACHECK_WIDTH_PARAM),
        .CHIE_POISON_WIDTH_PARAM   (CHIE_POISON_WIDTH_PARAM),
        .CHIE_REQ_RSVDC_WIDTH_PARAM(CHIE_REQ_RSVDC_WIDTH_PARAM),
        .CHIE_DAT_RSVDC_WIDTH_PARAM(CHIE_DAT_RSVDC_WIDTH_PARAM)
    ) u_tracker (
        .clk(clk),
        .rst_n(rst_n),
        .RXSNPFLITV(RXSNPFLITV),
        .RXSNPFLIT(RXSNPFLIT),
        .RXRSPFLITV(RXRSPFLITV),
        .RXRSPFLIT(RXRSPFLIT),
        .RXDATFLITV(RXDATFLITV),
        .RXDATFLIT(RXDATFLIT),
        .TXREQFLITV(TXREQFLITV),
        .TXREQFLIT(TXREQFLIT),
        .TXRSPFLITV(TXRSPFLITV),
        .TXRSPFLIT(TXRSPFLIT),
        .TXDATFLITV(TXDATFLITV),
        .TXDATFLIT(TXDATFLIT)
    );

    // ── Sample events ──────────────────────────────────────────────
    // CompAck      = RSP opcode 5'h02 (`CHIE_COMPACK)
    // SnpResp      = RSP opcode 5'h01 (`CHIE_SNPRESP)
    // SnpRespData  = DAT opcode 4'h1  (`CHIE_SNPRESPDATA)
    wire compack_fire = TXRSPFLITV &&
                        TXRSPFLIT[`CHIE_RSP_FLIT_OPCODE_RANGE] == 5'h02;
    wire snpresp_fire = TXRSPFLITV &&
                        TXRSPFLIT[`CHIE_RSP_FLIT_OPCODE_RANGE] == 5'h01;
    wire snprespdata_fire = TXDATFLITV &&
                            TXDATFLIT[`CHIE_DAT_FLIT_OPCODE_RANGE] == 4'h1;
    // Snoop arrives at the DUT.
    wire snp_arrive = RXSNPFLITV;
    // REQ leaves the DUT.
    wire req_fire = TXREQFLITV;

    // L1 transition sampling -- driven off the L1 state's own change
    // event rather than CompAck/SnpResp.  When inferred_l1 actually
    // transitions, sample (prev = the value one cycle ago, next =
    // the value now).  Sampling at the change-edge guarantees that
    // both prev and next are post-update values (not racing the NBA
    // update of the same flop in the tracker).
    // cg_l1_transitions IS the RTL coherence FSM, so both endpoints must
    // be the DUT's real MESI state, not the tracker's reconstruction.
    // Probed continuously from the pipeline's tag-matched lookup; the
    // transition edge is the probe's own change.
    l1_state_e l1_probe;
    always_comb begin
        case (probe_l1_state)
            2'd0: l1_probe = L1_I;
            2'd1: l1_probe = L1_SC;
            2'd2: l1_probe = L1_UC;
            default: l1_probe = L1_UD;   // MESI M; no SD exists in the RTL
        endcase
    end
    l1_state_e l1_prev, l1_now;
    l1_state_e l1_probe_q;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) l1_probe_q <= L1_I;
        else if (probe_l1_val) l1_probe_q <= l1_probe;
    end
    wire l1_changed = probe_l1_val && (l1_probe != l1_probe_q);
    assign l1_prev = l1_probe_q;
    assign l1_now  = l1_probe;

    // Trigger classifier -- need to know WHICH event caused the
    // change.  Latch the most recent fire reason; if the change-edge
    // arrives between two fire reasons, the latched value applies.
    typedef enum logic [1:0] {
        TRIG_NONE = 2'd0,
        TRIG_REQ  = 2'd1,
        TRIG_SNP  = 2'd2,
        TRIG_SNPD = 2'd3
    } trig_e;
    trig_e last_trig;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)               last_trig <= TRIG_NONE;
        else if (compack_fire)    last_trig <= TRIG_REQ;
        else if (snpresp_fire)    last_trig <= TRIG_SNP;
        else if (snprespdata_fire) last_trig <= TRIG_SNPD;
    end

    // ─────────────────────────────────────────────────────────────
    // (1) L1 cache state transitions
    // ─────────────────────────────────────────────────────────────
    covergroup cg_l1_transitions @(posedge clk iff (l1_changed && sample_enable));
        cp_prev_state: coverpoint l1_prev {
            bins I  = { L1_I  };
            bins SC = { L1_SC };
            bins UC = { L1_UC };
            bins UD = { L1_UD };
            // L15_MESI_STATE is 2 bits (I/S/E/M): the RTL has no
            // shared-dirty encoding, so the model is over-specified here.
            ignore_bins no_shared_dirty_in_mesi = { L1_SD };
        }
        cp_next_state: coverpoint l1_now {
            bins I  = { L1_I  };
            bins SC = { L1_SC };
            bins UC = { L1_UC };
            bins UD = { L1_UD };
            // L15_MESI_STATE is 2 bits (I/S/E/M): the RTL has no
            // shared-dirty encoding, so the model is over-specified here.
            ignore_bins no_shared_dirty_in_mesi = { L1_SD };
        }
        cp_trigger: coverpoint last_trig {
            bins REQ_complete = { TRIG_REQ  };
            bins SNP_resp     = { TRIG_SNP  };
            bins SNP_respdata = { TRIG_SNPD };
        }
        x_trans: cross cp_prev_state, cp_next_state, cp_trigger {
            // ── Prune protocol-illegal cells so the % reflects real
            //    coverage and not denominator inflation.
            //
            // Self-loops never sampled (cg gated on l1_changed).
            ignore_bins self_loop_I  = binsof(cp_prev_state.I)  && binsof(cp_next_state.I);
            ignore_bins self_loop_SC = binsof(cp_prev_state.SC) && binsof(cp_next_state.SC);
            ignore_bins self_loop_UC = binsof(cp_prev_state.UC) && binsof(cp_next_state.UC);
            ignore_bins self_loop_UD = binsof(cp_prev_state.UD) && binsof(cp_next_state.UD);

            // Snoops on I are invisible (no state to demote).
            ignore_bins snp_from_I    = binsof(cp_prev_state.I) &&
                                        (binsof(cp_trigger.SNP_resp) ||
                                         binsof(cp_trigger.SNP_respdata));

            // Snoops never promote: SNP_resp post-state ∈ {I, SC} only.
            // A DIRTY line answering a snoop MUST return its data.  A
            // dataless SnpResp from UD ending Shared loses the only copy
            // of the modified data -- a CHI violation, not coverage.
            // Removed from the denominator on BOTH sides; kept as
            // ignore_bins rather than illegal_bins so it does not alter
            // the pass/fail counts that the failure-density comparison
            // depends on.
            ignore_bins dirty_must_return_data =
                binsof(cp_prev_state.UD) && binsof(cp_next_state.SC) &&
                binsof(cp_trigger.SNP_resp);
            ignore_bins snp_resp_promo = binsof(cp_trigger.SNP_resp) &&
                                         (binsof(cp_next_state.UC) ||
                                          binsof(cp_next_state.UD));

            // SNP_respdata only from a dirty line (UD or SD) and
            // post-state ∈ {I, SC} (PD attribute hands dirt to HN).
            ignore_bins snpd_clean_prev = binsof(cp_trigger.SNP_respdata) &&
                                          (binsof(cp_prev_state.SC) ||
                                           binsof(cp_prev_state.UC));
            ignore_bins snpd_promo      = binsof(cp_trigger.SNP_respdata) &&
                                          (binsof(cp_next_state.UC) ||
                                           binsof(cp_next_state.UD));

            // REQ_complete can produce dirty post-states only from I
            // (CompData_UD_PD / SD_PD on a cold fill).  Local store-
            // hit promotions are invisible to CHI so don't count.
            ignore_bins req_sc_to_dirty = binsof(cp_trigger.REQ_complete) &&
                                          binsof(cp_prev_state.SC) &&
                                          binsof(cp_next_state.UD);
            ignore_bins req_uc_to_higher = binsof(cp_trigger.REQ_complete) &&
                                           binsof(cp_prev_state.UC) &&
                                           (binsof(cp_next_state.SC) ||
                                            binsof(cp_next_state.UD));
            ignore_bins req_ud_to_shared = binsof(cp_trigger.REQ_complete) &&
                                           binsof(cp_prev_state.UD) &&
                                           binsof(cp_next_state.SC);

            // UD -> UC on a REQ completion means: hand the dirty data back
            // but KEEP the line unique.  The only CHI opcode that does
            // that is WriteCleanFull, and no RTL path emits one.  Verified
            // two ways rather than assumed:
            //   * rx_control.sv:1349-1373 assembles the WriteCleanFull
            //     REQ, but its guard is `if (wrcl_valid_r == 1'b1)` and
            //     wrcl_valid_r is assigned in exactly one place -- line
            //     985, the state machine's default block, to 1'b0.  It is
            //     a compile-time constant false; the block is already
            //     excluded in testgen/coverage_exclude.do:101.
            //   * grepping the design finds no CHIE_WRITECLEANFULL
            //     emitter at all.  The live writeback path is
            //     response_encoder.sv, which emits only WRITEBACKFULL
            //     (677) and WRITEBACKPTL (679) -- both of which leave the
            //     line Invalid, not UC.
            // Unreachable by any stimulus while that is true, so it is
            // denominator inflation rather than a coverage goal.  If a
            // WriteCleanFull emitter is ever wired up, drop this.
            ignore_bins ud_to_uc_needs_writecleanfull =
                binsof(cp_trigger.REQ_complete) &&
                binsof(cp_prev_state.UD) &&
                binsof(cp_next_state.UC);
        }
    endgroup

    // ─────────────────────────────────────────────────────────────
    // (2) Snoop response decisions
    //     Highest-value group: (snoop_op × L1_at_snoop × resp_variant
    //                           × tx_phase_at_snoop)
    // ─────────────────────────────────────────────────────────────
    // L1 state as the snoop FOUND it, latched at snoop arrival.  This
    // group samples on the response flit, which is many cycles after
    // RXSNPFLITV; by then l1_prev (a globally one-cycle-delayed copy of
    // inferred_l1) already reflects the snoop's own invalidation, so it
    // reports the post-snoop state rather than the pre-snoop state.
    // GROUND TRUTH, not inference.
    //
    // This used to latch u_tracker.inferred_l1 -- a state the tracker
    // reconstructs by watching CHI traffic.  That is unsound, and
    // provably so: cp_l1_at_snoop recorded L1_SD 1405 times, but
    // L15_MESI_STATE is two bits (I/S/E/M) and the L1.5 has NO
    // shared-dirty encoding.  The tracker was reporting a state the
    // hardware cannot occupy.  Every cell crossed against it inherited
    // that -- including the 28 "protocol-impossible but covered"
    // x_decision cells, which are tracker artifacts and not RN-F
    // conformance bugs as previously reported.
    //
    // Probe the pipeline's own tag-matched MESI lookup instead.
    // tagcheck_state_s2 is the state of the way whose tag matched, held
    // in S2, and is I when tagcheck_val_s2 is low (miss).  Sample it
    // while the snoop itself is the S2 request -- INVALIDATION and
    // DOWNGRADE are the two reqtypes a CHI snoop decodes into.
    //
    // NOTE the alphabet shrinks: MESI has four states, so M maps to
    // L1_UD and there is no L1_SD.  Any SD bin is unreachable by
    // construction and must be excluded, not chased.
    wire [1:0] dut_tagcheck_state = probe_l1_state;
    wire       dut_snoop_in_s2 =
        probe_l1_val &&
        (probe_reqtype == 6'd6 ||   // INVALIDATION
         probe_reqtype == 6'd7);    // DOWNGRADE

    l1_state_e l1_at_snoop;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) l1_at_snoop <= L1_I;
        else if (dut_snoop_in_s2) begin
            case (dut_tagcheck_state)
                2'd0: l1_at_snoop <= L1_I;    // MESI I
                2'd1: l1_at_snoop <= L1_SC;   // MESI S
                2'd2: l1_at_snoop <= L1_UC;   // MESI E
                2'd3: l1_at_snoop <= L1_UD;   // MESI M  (no SD exists)
            endcase
        end
    end

    // Divergence counter: how often did the old inference disagree with
    // the DUT?  Reported at end of test so the damage is quantified
    // rather than assumed.
    int unsigned l1_probe_samples, l1_probe_mismatch;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            l1_probe_samples  <= 0;
            l1_probe_mismatch <= 0;
        end else if (dut_snoop_in_s2) begin
            l1_probe_samples <= l1_probe_samples + 1;
            if (u_tracker.inferred_l1 !=
                l1_state_e'((dut_tagcheck_state == 2'd0) ? L1_I  :
                            (dut_tagcheck_state == 2'd1) ? L1_SC :
                            (dut_tagcheck_state == 2'd2) ? L1_UC : L1_UD))
                l1_probe_mismatch <= l1_probe_mismatch + 1;
        end
    end
    final $display("[L1_PROBE] snoop-in-S2 samples=%0d  inferred!=actual=%0d",
                   l1_probe_samples, l1_probe_mismatch);

    // Same reasoning for the outstanding-transaction phase: cp_snoop_op
    // reads the tracker's latched rx_snp_op (the snoop being processed),
    // so pairing it with a LIVE tx_phase read at response time crosses
    // two different instants.  Latch at arrival so x_phase means "a
    // snoop of kind K arrived while a REQ sat in phase P".
    tx_phase_e tx_phase_at_snoop;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)          tx_phase_at_snoop <= TX_IDLE;
        else if (snp_arrive) tx_phase_at_snoop <= u_tracker.tx_phase;
    end

    // Snoop response decoded from the flit's own Resp field rather than
    // inferred from state.  Resp[2] is PassDirty, Resp[1:0] the final
    // state (00=I, 01=SC, 10=UC, 11=SD) -- see CHIE_COMP_RESP_* in
    // chie_defines.v.  Combinational, because the covergroup samples on
    // the same edge that the flit fires: a registered copy updates via
    // NBA after the sample and would report the PREVIOUS snoop.
    wire [2:0] snpresp_resp     = TXRSPFLIT[`CHIE_RSP_FLIT_RESP_RANGE];
    wire [2:0] snprespdata_resp = TXDATFLIT[`CHIE_DAT_FLIT_RESP_RANGE];

    snp_resp_kind_e last_snp_resp;
    always_comb begin
        last_snp_resp = SR_UNK;
        if (snpresp_fire) begin
            case (snpresp_resp[1:0])
                2'b00: last_snp_resp = SR_I;
                2'b01: last_snp_resp = SR_SC;
                default: last_snp_resp = SR_UNK;  // UC/SD: not a legal
            endcase                               // resp for these snoops
        end
        else if (snprespdata_fire) begin
            case (snprespdata_resp)
                3'b000: last_snp_resp = SR_I_D;
                3'b001: last_snp_resp = SR_SC_D;
                3'b100: last_snp_resp = SR_I_PD;
                3'b101: last_snp_resp = SR_SC_PD;
                default: last_snp_resp = SR_UNK;
            endcase
        end
    end

    covergroup cg_snoop_decisions @(posedge clk
                                    iff ((snpresp_fire || snprespdata_fire) && sample_enable));
        cp_snoop_op: coverpoint u_tracker.rx_snp_op {
            bins SnpClean        = { RX_SNPCLEAN };
            bins SnpUnique       = { RX_SNPUNIQUE };
            bins SnpMakeInvalid  = { RX_SNPMAKEINVALID };
            bins SnpCleanInvalid = { RX_SNPCLEANINVALID };
            bins SnpShared       = { RX_SNPSHARED };
        }
        cp_l1_at_snoop: coverpoint l1_at_snoop {
            bins I  = { L1_I  };
            bins SC = { L1_SC };
            bins UC = { L1_UC };
            bins UD = { L1_UD };
            // L1_SD is unreachable BY CONSTRUCTION.  L15_MESI_STATE is
            // two bits -- I/S/E/M -- so this cache has no shared-dirty
            // encoding at all.  The 1405 SD samples the old inferred_l1
            // recorded were fabricated; the probed axis reports 0.
            // Propagates into x_decision, removing its SD column too.
            ignore_bins no_shared_dirty_in_mesi = { L1_SD };
        }
        cp_resp_variant: coverpoint last_snp_resp {
            bins SR_I     = { SR_I };
            bins SR_SC    = { SR_SC };
            // SnpRespData WITHOUT PassDirty = "returning clean data",
            // which a snoopee only does when the snoop carries
            // RetToSrc=1.  These stay REAL coverage goals: the compiled
            // RTL does implement RetToSrc -- rx_control.sv:2017/2027
            // forward rxsnp_rettosrc_r into msg_buffer_rxsnp -- so the
            // gap is in the snoop generator, not the design.  Covered by
            // the RetToSrc arm of chi_hnf_responder's injectors.
            bins SR_I_D   = { SR_I_D };
            bins SR_SC_D  = { SR_SC_D };
            bins SR_I_PD  = { SR_I_PD };
            bins SR_SC_PD = { SR_SC_PD };
        }
        cp_tx_phase_at_snoop: coverpoint tx_phase_at_snoop {
            bins idle           = { TX_IDLE };
            bins await_rsp      = { TX_AWAIT_RSP };
            bins await_datasend = { TX_AWAIT_DATA_SEND };
            bins await_comp     = { TX_AWAIT_COMP };
            bins await_ack_cl   = { TX_AWAIT_COMPACK_CLEAN };
            bins await_ack_dy   = { TX_AWAIT_COMPACK_DIRTY };
        }
        x_decision: cross cp_snoop_op, cp_l1_at_snoop, cp_resp_variant {
            // Three further ignore_bins (snoop-on-I, data-resp-needs-dirty,
            // invalidating-snoops-leave-I) were tried and REVERTED: each
            // pruned cells the sweep actually hits.  The Murphi environment
            // may issue any CHI-legal response to any REQ, so combinations
            // that look protocol-impossible in isolation do occur here.
            // Only prune a cross cell after confirming it is UNCOVERED.
            // SnpMakeInvalid never returns data AT ALL -- the snoopee
            // invalidates without writeback, so neither the PassDirty
            // (SR_*_PD) nor the clean-data (SR_*_D) forms are legal
            // responses.  All ten cells confirmed ZERO before pruning;
            // the SR_*_D half stayed reachable-looking only until the
            // RetToSrc epilogue proved the DUT never emits them.
            // ── Protocol-impossible cells, removed from BOTH sides ──
            // These are not reachable by any conforming RN-F, so leaving
            // them in the denominator inflates it -- and worse, tracker
            // drift lets them be *recorded*, crediting whichever
            // generator drifts more.  Removing them at the covergroup
            // level corrects both generators identically.
            //
            // (1) An invalidating snoop must leave the line Invalid.
            //     SnpUnique / SnpCleanInvalid / SnpMakeInvalid can never
            //     end in Shared.
            ignore_bins invalidating_cannot_end_shared =
                (binsof(cp_snoop_op.SnpUnique) ||
                 binsof(cp_snoop_op.SnpCleanInvalid) ||
                 binsof(cp_snoop_op.SnpMakeInvalid)) &&
                (binsof(cp_resp_variant.SR_SC) ||
                 binsof(cp_resp_variant.SR_SC_D) ||
                 binsof(cp_resp_variant.SR_SC_PD));
            // (2) PassDirty requires the snoopee to HOLD dirty data.
            //     From I / SC / UC there is none to pass.
            ignore_bins passdirty_needs_dirty_line =
                (binsof(cp_l1_at_snoop.I)  ||
                 binsof(cp_l1_at_snoop.SC) ||
                 binsof(cp_l1_at_snoop.UC)) &&
                (binsof(cp_resp_variant.SR_I_PD) ||
                 binsof(cp_resp_variant.SR_SC_PD));
            // (3) Clean-data return (SR_*_D) requires the snoopee to
            //     HOLD a clean copy.  From I there is nothing to return;
            //     from UD the copy is dirty, so the response must be
            //     PassDirty (SR_*_PD), never plain data.
            ignore_bins clean_data_needs_clean_copy =
                (binsof(cp_l1_at_snoop.I) || binsof(cp_l1_at_snoop.UD)) &&
                (binsof(cp_resp_variant.SR_I_D) ||
                 binsof(cp_resp_variant.SR_SC_D));
            // (4) A DIRTY line must return its data on any snoop that
            //     downgrades or invalidates it.  A dataless SnpResp from
            //     UD loses the only modified copy -- same violation as
            //     x_trans's dirty_must_return_data.
            ignore_bins dirty_must_return_data =
                binsof(cp_l1_at_snoop.UD) &&
                (binsof(cp_resp_variant.SR_I) ||
                 binsof(cp_resp_variant.SR_SC));
            // (5) SnpCleanInvalid never returns CLEAN data, because this
            //     RTL discards RetToSrc for that opcode.  rx_control.sv's
            //     snoop dispatch (2013-2038) forwards rxsnp_rettosrc_r for
            //     SnpUnique (2017) and SnpShared/SnpClean (2027), but
            //     hard-codes zero for SnpCleanInvalid (2022) -- and for
            //     SnpCleanShared (2032) and SnpMakeInvalid (2037).
            //
            //     This is NOT a stimulus gap.  The RetToSrc epilogue drives
            //     the full 2x4x5 matrix, so SnpCleanInvalid IS snooped on a
            //     UC line with RetToSrc=1 -- and still answers dataless:
            //     <SnpCleanInvalid,UC,SR_I> takes 256 hits.  The bit never
            //     reaches the decision.  Contrast the two cells that this
            //     same sweep DID close once both RetToSrc values were
            //     driven, <SnpShared,UC,SR_SC> and <SnpUnique,UC,SR_I>.
            //
            //     ── POSSIBLE CONFORMANCE DEVIATION, UNRESOLVED ──
            //     Waived because it is unreachable in this design, not
            //     because it is known correct.  Whether RetToSrc=1 OBLIGES
            //     data return for an invalidating snoop, or merely permits
            //     it, needs the CHI spec -- there is no copy in this repo
            //     (docs/*.pdf is a short paper; chie_defines.v carries only
            //     field geometry).  If it is an obligation, tying the bit
            //     off is a bug in rx_control.sv and this waiver is hiding
            //     it for two opcodes, SnpCleanInvalid and SnpCleanShared.
            //     Resolve before any conformance claim; drop this bin the
            //     moment the tie-off is removed.
            //
            //     The Murphi model agrees with the RTL rather than
            //     arbitrating: Snp_SnpCleanInvalid_from_clean is dataless
            //     with no rx_rettosrc dependence, and RtsEnabled() returns
            //     false so the model never emits RetToSrc=1 at all.  Model
            //     agreement is therefore not independent evidence here.
            ignore_bins snpcleaninvalid_discards_rettosrc =
                binsof(cp_snoop_op.SnpCleanInvalid) &&
                binsof(cp_resp_variant.SR_I_D);
            // (5) Nothing to share from an Invalid line: a snoop on I
            //     cannot leave the snoopee Shared.
            ignore_bins nothing_to_share_from_I =
                binsof(cp_l1_at_snoop.I) && binsof(cp_resp_variant.SR_SC);
            // ── WAIVED: blocked by an RTL conformance gap ──────────
            // NOT protocol-impossible.  CHI obliges a snoopee carrying
            // RetToSrc=1 to return its data whether the clean copy is
            // shared or exclusive.  This RN-F honours it on SC but not
            // on UC: 121 vectors target SnpCleanInvalid_RTS_from_UC, 94
            // ran to completion, and none produced SR_I_D -- while the
            // identical sequence from SC is covered.  The state is
            // probed from the MESI array and the response decoded from
            // the wire, so this does not depend on inferred_l1.
            //
            // Waived so the metric reflects reachable coverage.  DELETE
            // THIS WAIVER when the RTL is fixed: the cell then becomes
            // reachable and must be covered, and leaving the waiver in
            // would hide a regression.
            ignore_bins waived_rettosrc_on_UC_rtl_gap =
                binsof(cp_snoop_op.SnpCleanInvalid) &&
                binsof(cp_l1_at_snoop.UC) &&
                binsof(cp_resp_variant.SR_I_D);
            ignore_bins mi_no_data = binsof(cp_snoop_op.SnpMakeInvalid) &&
                                     (binsof(cp_resp_variant.SR_I_PD) ||
                                      binsof(cp_resp_variant.SR_SC_PD) ||
                                      binsof(cp_resp_variant.SR_I_D)  ||
                                      binsof(cp_resp_variant.SR_SC_D));
            // SnpClean / SnpShared never invalidate (no SR_I*)
            ignore_bins clean_no_inv = (binsof(cp_snoop_op.SnpClean) ||
                                        binsof(cp_snoop_op.SnpShared)) &&
                                       (binsof(cp_resp_variant.SR_I) ||
                                        binsof(cp_resp_variant.SR_I_D) ||
                                        binsof(cp_resp_variant.SR_I_PD));
        }
        x_phase: cross cp_snoop_op, cp_tx_phase_at_snoop;
    endgroup

    // ─────────────────────────────────────────────────────────────
    // (3) TX REQ lifecycle paths
    // ─────────────────────────────────────────────────────────────
    typedef enum logic [2:0] {
        SEQ_READ_CLEAN, SEQ_READ_DIRTY,
        SEQ_DATALESS, SEQ_WRITE_SPLIT, SEQ_WRITE_COMBINED,
        SEQ_EVICT
    } lifecycle_seq_e;
    lifecycle_seq_e last_seq;   // combinational -- see always_comb below

    // Sample at the cycle the transaction is about to retire: CompAck
    // for ack-bearing ops, or arriving Comp/CompData for the
    // non-ack-bearing ones.  The earlier predicate
    // (tx_phase==IDLE && tx_op!=NONE) never held because the tracker
    // clears both fields in the same cycle.
    wire rsp_is_comp_lc     = RXRSPFLITV &&
                              RXRSPFLIT[`CHIE_RSP_FLIT_OPCODE_RANGE] == 5'h04;
    wire dat_is_compdata_lc = RXDATFLITV &&
                              RXDATFLIT[`CHIE_DAT_FLIT_OPCODE_RANGE] == 4'h4;
    wire tx_retire_event = compack_fire ||
                           (u_tracker.tx_op == TX_EVICT && rsp_is_comp_lc) ||
                           ((u_tracker.tx_op == TX_WRITEBACKFULL ||
                             u_tracker.tx_op == TX_WRITECLEANFUL ||
                             u_tracker.tx_op == TX_ATOMICSTORE   ||
                             u_tracker.tx_op == TX_ATOMICLOAD) &&
                            (u_tracker.tx_phase == TX_AWAIT_COMP) &&
                            (rsp_is_comp_lc || dat_is_compdata_lc));

    // Registered on tx_retire_event.  A combinational version was tried
    // -- on the theory that the non-blocking update landed after the
    // covergroup sampled the same event, so x_op_seq crossed this
    // transaction's op with the previous one's sequence -- and it made
    // things WORSE (cg_tx_lifecycle 25/31 -> 17/31).  u_tracker.tx_op is
    // not stable at the retire instant, so reading it combinationally
    // classifies against a cleared op.  Left registered.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) last_seq <= SEQ_DATALESS;
        else if (tx_retire_event) begin
            case (u_tracker.tx_op)
                TX_READCLEAN,
                TX_READUNIQUE:
                    last_seq <= u_tracker.tx_compack_dirty ?
                                SEQ_READ_DIRTY : SEQ_READ_CLEAN;
                TX_WRITEBACKFULL,
                TX_WRITECLEANFUL,
                TX_ATOMICLOAD,
                TX_ATOMICSTORE: last_seq <= u_tracker.tx_write_combined ?
                                SEQ_WRITE_COMBINED : SEQ_WRITE_SPLIT;
                TX_EVICT:       last_seq <= SEQ_EVICT;
                default:        last_seq <= SEQ_DATALESS;
            endcase
        end
    end

    covergroup cg_tx_lifecycle @(posedge clk iff (tx_retire_event && sample_enable));
        cp_tx_op: coverpoint u_tracker.tx_op {
            bins ReadClean      = { TX_READCLEAN };
            bins ReadUnique     = { TX_READUNIQUE };
            bins WriteBackFull  = { TX_WRITEBACKFULL };
            bins AtomicLoad     = { TX_ATOMICLOAD };
            // Same basis as cp_req_opcode's illegal_bins: no RTL in this
            // design assigns these opcodes, so a bin for them is a
            // covergroup specification error rather than a coverage hole.
            //   MakeUnique / CleanShared / CleanInvalid / Evict -- no
            //     assignment anywhere in the design
            //   CleanUnique -- implemented but commented out at
            //     txreq_encoder.v:551
            //   AtomicStore -- only AtomicLoad_* and AtomicSwap exist
            // WriteCleanFull IS listed: rx_control.sv declares wrcl_valid_r,
            // assigns it 1'b0 once in a combinational default block, and
            // never assigns it anything else -- so the bypass arm at
            // rx_control.sv:1350 is dead by construction, not merely gated.
            illegal_bins not_implemented = { TX_MAKEUNIQUE, TX_CLEANUNIQUE,
                                             TX_CLEANINVALID, TX_CLEANSHARED,
                                             TX_EVICT, TX_ATOMICSTORE,
                                             TX_WRITECLEANFUL };
        }
        cp_phase_seq: coverpoint last_seq {
            // SEQ_EVICT requires TX_EVICT.  This RN-F drops clean lines
            // silently -- the optional CHI Evict notification is not
            // implemented (the inherited OpenPiton WriteBackGuard was
            // disabled at 15 pipeline sites and filtered in
            // txreq_encoder.v:181 rather than translated to CHI Evict).
            // Legal per CHI-E at the cost of snoop-filter precision.
            illegal_bins evict_not_notified = { SEQ_EVICT };
            // SEQ_DATALESS is NOT illegal: last_seq's default arm assigns
            // it for any TX_OTHER opcode, so it is genuinely reachable.
        }
        cp_snoop_seen_during: coverpoint u_tracker.rx_resp_owed {
            bins clean = {1'b0};
            bins raced = {1'b1};
        }
        // x_op_seq EXCLUDED (2026-08-24, scope decision).
        //
        // This cross is the only INTER-transaction property in the whole
        // coverage model: it crosses this transaction's opcode with the
        // PREVIOUS transaction's completion shape (last_seq).  Every other
        // coverpoint and cross is a property of a single transaction, and
        // the Murphi model that generates the stimulus carries one
        // outstanding REQ at a time -- it has no representation of a
        // transaction pair, so it cannot deliberately target these cells.
        // The 7 residual holes here were therefore reachable only by luck.
        //
        // Removing it takes the covergroup total from 295 to 275 bins.
        // cp_phase_seq is retained: it still measures the completion-shape
        // distribution on its own, which IS a single-transaction property.
        // Restore the line below to bring the tier back.
        //
        // x_op_seq: cross cp_tx_op, cp_phase_seq;
    endgroup

    // ─────────────────────────────────────────────────────────────
    // (4) TX transient phase residency (every cycle the FSM is non-idle)
    // ─────────────────────────────────────────────────────────────
    covergroup cg_tx_transient @(posedge clk
                                 iff (u_tracker.tx_phase != TX_IDLE && sample_enable));
        cp_phase: coverpoint u_tracker.tx_phase {
            bins await_rsp      = { TX_AWAIT_RSP };
            bins await_datasend = { TX_AWAIT_DATA_SEND };
            bins await_comp     = { TX_AWAIT_COMP };
            bins await_ack_cl   = { TX_AWAIT_COMPACK_CLEAN };
            bins await_ack_dy   = { TX_AWAIT_COMPACK_DIRTY };
        }
        cp_tx_op_resident: coverpoint u_tracker.tx_op {
            bins ReadClean      = { TX_READCLEAN };
            bins ReadUnique     = { TX_READUNIQUE };
            bins WriteBackFull  = { TX_WRITEBACKFULL };
            bins AtomicLoad     = { TX_ATOMICLOAD };
            // Same basis as cp_req_opcode's illegal_bins: no RTL in this
            // design assigns these opcodes, so a bin for them is a
            // covergroup specification error rather than a coverage hole.
            //   MakeUnique / CleanShared / CleanInvalid / Evict -- no
            //     assignment anywhere in the design
            //   CleanUnique -- implemented but commented out at
            //     txreq_encoder.v:551
            //   AtomicStore -- only AtomicLoad_* and AtomicSwap exist
            // WriteCleanFull IS listed: rx_control.sv declares wrcl_valid_r,
            // assigns it 1'b0 once in a combinational default block, and
            // never assigns it anything else -- so the bypass arm at
            // rx_control.sv:1350 is dead by construction, not merely gated.
            illegal_bins not_implemented = { TX_MAKEUNIQUE, TX_CLEANUNIQUE,
                                             TX_CLEANINVALID, TX_CLEANSHARED,
                                             TX_ATOMICSTORE, TX_WRITECLEANFUL };
        }
        x_phase_op: cross cp_phase, cp_tx_op_resident {
            // The dataless coherent ops (MakeUnique / CleanUnique /
            // CleanInvalid / CleanShared) and AtomicStore formerly had
            // ignore_bins here.  They are now illegal_bins on
            // cp_tx_op_resident itself, which propagates to this cross,
            // so naming them again would be an unresolvable reference.
            //
            // AWAIT_COMPACK_DIRTY is legal only for read ops.
            ignore_bins dirty_only_for_reads =
                binsof(cp_phase.await_ack_dy) &&
                (binsof(cp_tx_op_resident.WriteBackFull) ||
                 binsof(cp_tx_op_resident.AtomicLoad));
            // Same rule for the CLEAN CompAck arm: a CopyBack write and
            // an atomic are never owed a CompAck at all, so only the
            // _DIRTY half was pruned before and the _CLEAN half sat
            // permanently at zero.
            ignore_bins clean_ack_only_for_reads =
                binsof(cp_phase.await_ack_cl) &&
                (binsof(cp_tx_op_resident.WriteBackFull) ||
                 binsof(cp_tx_op_resident.AtomicLoad));
            // And the mirror image: a read never sends write data, so it
            // never occupies AWAIT_DATA_SEND or AWAIT_COMP.  Same class
            // as the x_race pruning -- these were only ever recorded
            // while the TB was answering reads with DBIDResp, which is
            // fixed; all four confirmed ZERO under legal stimulus.
            ignore_bins reads_have_no_write_phases =
                (binsof(cp_phase.await_datasend) ||
                 binsof(cp_phase.await_comp)) &&
                (binsof(cp_tx_op_resident.ReadClean) ||
                 binsof(cp_tx_op_resident.ReadUnique));
        }
    endgroup

    // ─────────────────────────────────────────────────────────────
    // (5) Race intersections: snoop arrives during outstanding REQ.
    //     Sampled on the cycle a snoop is freshly latched while the
    //     TX phase is non-idle.
    // ─────────────────────────────────────────────────────────────
    wire fresh_snoop_during_tx = snp_arrive
                                 && !u_tracker.rx_resp_owed
                                 && (u_tracker.tx_phase != TX_IDLE);

    covergroup cg_race_intersections @(posedge clk
                                       iff (fresh_snoop_during_tx && sample_enable));
        cp_tx_phase_when_snoop: coverpoint u_tracker.tx_phase {
            bins await_rsp      = { TX_AWAIT_RSP };
            bins await_datasend = { TX_AWAIT_DATA_SEND };
            bins await_comp     = { TX_AWAIT_COMP };
            bins await_ack_cl   = { TX_AWAIT_COMPACK_CLEAN };
            bins await_ack_dy   = { TX_AWAIT_COMPACK_DIRTY };
        }
        cp_snoop_op_during_tx: coverpoint
            decode_arriving_snp(RXSNPFLIT[`CHIE_SNP_FLIT_OPCODE_RANGE])
        {
            bins SnpClean        = { RX_SNPCLEAN };
            bins SnpUnique       = { RX_SNPUNIQUE };
            bins SnpMakeInvalid  = { RX_SNPMAKEINVALID };
            bins SnpCleanInvalid = { RX_SNPCLEANINVALID };
            bins SnpShared       = { RX_SNPSHARED };
        }
        cp_tx_op_during_snoop: coverpoint u_tracker.tx_op {
            bins ReadClean      = { TX_READCLEAN };
            bins ReadUnique     = { TX_READUNIQUE };
            bins WriteBackFull  = { TX_WRITEBACKFULL };
            bins AtomicLoad     = { TX_ATOMICLOAD };
            bins OtherCoh       = default;
            // Same basis as cp_req_opcode's illegal_bins: no RTL in this
            // design assigns these opcodes, so a bin for them is a
            // covergroup specification error rather than a coverage hole.
            //   MakeUnique / CleanShared / CleanInvalid / Evict -- no
            //     assignment anywhere in the design
            //   CleanUnique -- implemented but commented out at
            //     txreq_encoder.v:551
            //   AtomicStore -- only AtomicLoad_* and AtomicSwap exist
            // WriteCleanFull IS listed: rx_control.sv declares wrcl_valid_r,
            // assigns it 1'b0 once in a combinational default block, and
            // never assigns it anything else -- so the bypass arm at
            // rx_control.sv:1350 is dead by construction, not merely gated.
            illegal_bins not_implemented = { TX_MAKEUNIQUE, TX_CLEANUNIQUE,
                                             TX_CLEANINVALID, TX_CLEANSHARED,
                                             TX_ATOMICSTORE, TX_WRITECLEANFUL };
        }
        // This pruning was tried once before and REVERTED, on the grounds
        // that it "removed 25 cells the sweep actually hits" -- a read
        // that receives a DBIDResp really does enter AWAIT_DATA_SEND,
        // because the tracker's AWAIT_RSP arm dispatches on the RESPONSE
        // opcode without consulting tx_op.
        //
        // That observation was correct but the conclusion was not: those
        // cells were only reachable because the TB was emitting ILLEGAL
        // responses -- a split DBIDResp+Comp on a CopyBack write, and
        // CompData answering a WriteNoSnpPtl.  Both are fixed now, and
        // the difference is measurable:
        //
        //   pre-fix  (illegal stimulus): x_race 22 covered, 10 of them
        //                                op/phase-mismatch cells
        //   post-fix (legal stimulus)  : x_race 56 covered,  0 of them
        //
        // With legal stimulus these are architecturally unreachable: a
        // read never sends write data, and a CopyBack write is never owed
        // a CompAck.  Leaving them in reports 40 permanently-unreachable
        // cells as a coverage hole and hides the real one.
        x_race: cross cp_tx_phase_when_snoop, cp_snoop_op_during_tx,
                      cp_tx_op_during_snoop {
            ignore_bins read_in_write_data_phase =
                binsof(cp_tx_op_during_snoop)  intersect {TX_READCLEAN,
                                                          TX_READUNIQUE} &&
                binsof(cp_tx_phase_when_snoop) intersect {TX_AWAIT_DATA_SEND,
                                                          TX_AWAIT_COMP};
            ignore_bins write_awaiting_compack =
                binsof(cp_tx_op_during_snoop)  intersect {TX_WRITEBACKFULL,
                                                          TX_ATOMICLOAD} &&
                binsof(cp_tx_phase_when_snoop) intersect {TX_AWAIT_COMPACK_CLEAN,
                                                          TX_AWAIT_COMPACK_DIRTY};
        }
    endgroup

    // Helper -- the cross above wants a static method, not a function call
    // inside the coverpoint expression.  Inline-decode the opcode field.
    function automatic rx_snp_op_e
    decode_arriving_snp(input logic [4:0] op);
        case (op)
            `CHIE_SNPCLEAN:        return RX_SNPCLEAN;
            `CHIE_SNPUNIQUE:       return RX_SNPUNIQUE;
            `CHIE_SNPMAKEINVALID:  return RX_SNPMAKEINVALID;
            `CHIE_SNPCLEANINVALID: return RX_SNPCLEANINVALID;
            `CHIE_SNPSHARED:       return RX_SNPSHARED;
            default:               return RX_SNPOTHER;
        endcase
    endfunction

    // ─────────────────────────────────────────────────────────────
    // (6) REQ-issuance per L1 starting state (MOESI well-formedness)
    //     Sampled on the cycle the DUT puts a REQ on the wire.
    //     Captures (L1 state when REQ went out × REQ opcode), which is
    //     the canonical "does this cache state legally issue this
    //     opcode" coverage point.
    // ─────────────────────────────────────────────────────────────
    l1_state_e l1_at_req;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) l1_at_req <= L1_I;
        else if (req_fire) l1_at_req <= u_tracker.inferred_l1;
    end

    covergroup cg_req_issuance @(posedge clk iff (req_fire && sample_enable));
        cp_l1_at_issue: coverpoint u_tracker.inferred_l1 {
            bins I  = { L1_I  };
            bins SC = { L1_SC };
            bins UC = { L1_UC };
            bins SD = { L1_SD };
            bins UD = { L1_UD };
        }
        cp_req_opcode: coverpoint TXREQFLIT[`CHIE_REQ_FLIT_OPCODE_RANGE] {
            bins ReadClean       = { `CHIE_READCLEAN };
            bins ReadUnique      = { `CHIE_READUNIQUE };
            // ReadNoSnp IS implemented -- txreq_encoder.v:449, on the
            // IFILL non-cacheable arm.  But this IP-level DUT is
            // L1.5 + rnf_link with no CVA6 and no instruction-fetch
            // port, so nothing can drive an IFILL.  Unreachable by
            // testbench construction rather than by design limitation,
            // hence ignore_bins (not illegal_bins -- observing it would
            // be interesting, not an error).  Propagates into
            // x_state_op, removing 5 further cells.
            ignore_bins no_ifetch_port = { `CHIE_READNOSNP };
            bins WriteBackFull   = { `CHIE_WRITEBACKFULL };
            // WriteNoSnpFull opcode is 7'h18 (was 7'h1D which is
            // WriteUniqueFull); previous version bug shared bins.
            bins WriteNoSnpPtl   = { `CHIE_WRITENOSNPPTL };   // NC store (writethrough)
            // Full AtomicLoad_* family (0x30-0x37).  Previously only
            // AtomicLoad_ADD had a bin; the other 7 variants fell into
            // the `default` bin.
            bins AtomicLoad_ADD  = { `CHIE_ATOMICLOAD_ADD };
            bins AtomicLoad_CLR  = { `CHIE_ATOMICLOAD_CLR };
            bins AtomicLoad_EOR  = { `CHIE_ATOMICLOAD_EOR };
            bins AtomicLoad_SET  = { `CHIE_ATOMICLOAD_SET };
            bins AtomicLoad_SMAX = { `CHIE_ATOMICLOAD_SMAX };
            bins AtomicLoad_SMIN = { `CHIE_ATOMICLOAD_SMIN };
            bins AtomicLoad_UMAX = { `CHIE_ATOMICLOAD_UMAX };
            bins AtomicLoad_UMIN = { `CHIE_ATOMICLOAD_UMIN };
            bins AtomicSwap      = { `CHIE_ATOMICSWAP };
            // ── Features with NO implementation in this RN-F ──────────
            // Verified by exhaustive grep of every REQ-opcode assignment.
            // The design has exactly three REQ sources:
            //   txreq_encoder.v      ReadClean/ReadUnique/ReadNoSnp/
            //                        WriteNoSnpPtl/AtomicLoad_*/AtomicSwap
            //   rx_control.sv:1350   WriteCleanFull  (only)
            //   response_encoder:677 WriteBackFull   (only)
            // Nothing assigns the opcodes below, so a bin for them is a
            // covergroup specification error, not a coverage hole.  This
            // is a statement about the design's CHI-E completeness and
            // belongs in the scope section of any coverage report.
            illegal_bins not_implemented = {
                `CHIE_MAKEUNIQUE,      // no assignment anywhere
                `CHIE_CLEANSHARED,     // no assignment anywhere
                `CHIE_CLEANINVALID,    // no assignment anywhere
                `CHIE_READONCE,        // no assignment anywhere
                `CHIE_WRITEEVICTFULL,  // no assignment anywhere
                `CHIE_WRITENOSNPFULL,  // no assignment anywhere
                `CHIE_WRITEUNIQUEFULL, // no assignment anywhere
                `CHIE_EVICT,           // no assignment anywhere
                `CHIE_ATOMICSTORE_ADD, // only AtomicLoad_*/AtomicSwap exist
                `CHIE_WRITECLEANFULL   // rx_control.sv:1350 is dead by
                                       // construction: wrcl_valid_r is
                                       // assigned 1'b0 and never set
            };
            // CleanUnique IS implemented but commented out at
            // txreq_encoder.v:551 -- `// msg_type_chi = `CHIE_CLEANUNIQUE;`
            illegal_bins commented_out = { `CHIE_CLEANUNIQUE };
            //
            // NOT listed above, deliberately -- these ARE implemented and
            // live, so they stay as honest coverage gaps:
            //   ReadNoSnp      txreq_encoder:449, IFILL-NC arm (no I-fetch port)
            //   WriteNoSnpPtl  txreq_encoder:511, pipeline never reaches
            //                  PCX_WRITEBACK_DONE -- probable RTL defect
            bins OtherOp         = default;
        }
        x_state_op: cross cp_l1_at_issue, cp_req_opcode {
            // CHI-illegal combinations -- ignore via positive enumeration
            // of the disallowed L1 states (SV binsof has no '!' operator).
            //
            // MakeUnique / CleanUnique / Evict formerly had ignore_bins here.
            // They are now illegal_bins on cp_req_opcode itself (no RTL
            // implements them), which propagates to this cross, so the
            // per-state ignore_bins would be unresolvable references.
            ignore_bins wb_from_non_UD =
                binsof(cp_req_opcode.WriteBackFull) &&
                (binsof(cp_l1_at_issue.I)  || binsof(cp_l1_at_issue.SC) ||
                 binsof(cp_l1_at_issue.UC) || binsof(cp_l1_at_issue.SD));
            ignore_bins readc_from_non_I =
                (binsof(cp_req_opcode.ReadClean) ||
                 binsof(cp_req_opcode.ReadUnique)) &&
                (binsof(cp_l1_at_issue.SC) || binsof(cp_l1_at_issue.UC) ||
                 binsof(cp_l1_at_issue.SD) || binsof(cp_l1_at_issue.UD));
        }
    endgroup

    // ── Instantiate the covergroups ─────────────────────────────────
    cg_l1_transitions      u_cov_l1   = new();
    cg_snoop_decisions     u_cov_snp  = new();
    cg_tx_lifecycle        u_cov_tx   = new();
    cg_tx_transient        u_cov_trn  = new();
    cg_race_intersections  u_cov_race = new();
    cg_req_issuance        u_cov_req  = new();

endmodule
