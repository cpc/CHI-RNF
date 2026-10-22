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
 * rnf_phase_tracker.sv
 *
 * Reconstructs the Murphi-level RN-F state (tx_phase, tx_op,
 * rx_snp_op, l1_state-as-inferred) by observing CHI flits at the TB
 * boundary.  No invasive bind into the L1.5 internals.
 *
 * Drives clean output signals the covergroups can sample:
 *   tx_phase      : enum mirroring rnf_fsm.m's TxPhase
 *   tx_op         : the in-flight CHI REQ opcode (or tx_None)
 *   rx_snp_op     : the in-flight RX snoop opcode (or rx_None)
 *   rx_resp_owed  : bool, is a SnpResp pending from RN-F
 *   tx_compack_dirty : bool, true when the just-received CompData
 *                      carried dirty (PD) data
 *
 * The L1 cache state itself can only be inferred from the wire
 * traffic (CompData_UC vs _UD_PD, etc.).  We expose `inferred_l1`
 * which tracks what the RN-F *should* hold based on CHI responses
 * seen.  Useful as a sanity-check delta against any future bind into
 * the real L1.5 MESI register.
 *
 * Intended use: instantiated inside rnf_ip_tb and tapped into the CHI
 * wires that connect the DUT to chi_hnf_responder.
 */

`include "rnf_param.v"
`include "rnf_defines.v"
`include "chie_defines.v"

module rnf_phase_tracker
    import rnf_cov_pkg::*;
    `RNF_PARAM (
    input  logic clk,
    input  logic rst_n,

    // Snoop side from responder -> DUT
    input  logic                          RXSNPFLITV,
    input  logic [`CHIE_SNP_FLIT_RANGE]   RXSNPFLIT,

    // Response side from responder -> DUT
    input  logic                          RXRSPFLITV,
    input  logic [`CHIE_RSP_FLIT_RANGE]   RXRSPFLIT,
    input  logic                          RXDATFLITV,
    input  logic [`CHIE_DAT_FLIT_RANGE]   RXDATFLIT,

    // Request side from DUT -> responder
    input  logic                          TXREQFLITV,
    input  logic [`CHIE_REQ_FLIT_RANGE]   TXREQFLIT,
    input  logic                          TXRSPFLITV,
    input  logic [`CHIE_RSP_FLIT_RANGE]   TXRSPFLIT,
    input  logic                          TXDATFLITV,
    input  logic [`CHIE_DAT_FLIT_RANGE]   TXDATFLIT
);

    // Sampled / inferred signals -- public for covergroup binding.
    // Enums come from rnf_cov_pkg.
    tx_phase_e   tx_phase;
    tx_op_e      tx_op;
    rx_snp_op_e  rx_snp_op;
    logic        rx_resp_owed;
    logic        tx_compack_dirty;
    l1_state_e   inferred_l1;

    // ── Decode helpers ─────────────────────────────────────────────
    // Opcode constants come from chie_defines.v -- NEVER hand-written.
    // Previously 7'h0B/7'h0A/7'h00 were used for MakeUnique/CleanUnique/
    // Evict; those are CleanUnique/MakeUnique/ReqLCrdReturn respectively,
    // so the first two were swapped and Evict matched link-credit returns.
    // TX_ATOMICLOAD also matched only AtomicLoad_ADD, sending the other
    // seven variants and AtomicSwap to TX_OTHER -- which is why
    // cg_tx_lifecycle lagged every other covergroup.
    function automatic tx_op_e decode_req_opcode(input logic [6:0] op);
        case (op)
            `CHIE_READCLEAN:       return TX_READCLEAN;
            `CHIE_READUNIQUE:      return TX_READUNIQUE;
            `CHIE_MAKEUNIQUE:      return TX_MAKEUNIQUE;
            `CHIE_CLEANUNIQUE:     return TX_CLEANUNIQUE;
            `CHIE_CLEANINVALID:    return TX_CLEANINVALID;
            `CHIE_CLEANSHARED:     return TX_CLEANSHARED;
            `CHIE_EVICT:           return TX_EVICT;
            `CHIE_WRITEBACKFULL:   return TX_WRITEBACKFULL;
            `CHIE_WRITECLEANFULL:  return TX_WRITECLEANFUL;
            // All AtomicLoad_* variants plus AtomicSwap share the
            // load-shape lifecycle (CompData return), so they collapse
            // onto one tracker state.
            `CHIE_ATOMICLOAD_ADD,  `CHIE_ATOMICLOAD_CLR,
            `CHIE_ATOMICLOAD_EOR,  `CHIE_ATOMICLOAD_SET,
            `CHIE_ATOMICLOAD_SMAX, `CHIE_ATOMICLOAD_SMIN,
            `CHIE_ATOMICLOAD_UMAX, `CHIE_ATOMICLOAD_UMIN,
            `CHIE_ATOMICSWAP:      return TX_ATOMICLOAD;
            `CHIE_ATOMICSTORE_ADD: return TX_ATOMICSTORE;
            default:               return TX_OTHER;
        endcase
    endfunction

    function automatic rx_snp_op_e decode_snp_opcode(input logic [4:0] op);
        case (op)
            `CHIE_SNPCLEAN:        return RX_SNPCLEAN;
            `CHIE_SNPUNIQUE:       return RX_SNPUNIQUE;
            `CHIE_SNPMAKEINVALID:  return RX_SNPMAKEINVALID;
            `CHIE_SNPCLEANINVALID: return RX_SNPCLEANINVALID;
            `CHIE_SNPSHARED:       return RX_SNPSHARED;
            default:               return RX_SNPOTHER;
        endcase
    endfunction

    // ── TX phase reconstruction ────────────────────────────────────
    // Tracks the lifecycle of one outstanding REQ (MSHR depth = 1
    // assumption, matches the Murphi model's scope).  Multi-outstanding
    // extension requires per-TXNID tracking.
    logic        rsp_is_dbidresp;
    logic        rsp_is_compdbid;
    // Set when a write/atomic completes via the COMBINED
    // CompDBIDResp path rather than split DBIDResp->data->Comp.
    // Exposed so cg_tx_lifecycle can distinguish the two shapes.
    logic        tx_write_combined;
    logic        rsp_is_comp;
    logic        dat_is_compdata;
    logic        dat_carries_dirty;

    // CHI RSP opcode (5-bit) field
    wire [4:0] rsp_opcode_w = RXRSPFLIT[`CHIE_RSP_FLIT_OPCODE_RANGE];
    // CHI DAT opcode (4-bit) field
    wire [3:0] dat_opcode_w = RXDATFLIT[`CHIE_DAT_FLIT_OPCODE_RANGE];

    // Opcode constants come from chie_defines.v -- NEVER hand-written.
    // 5'h03 is RetryAck, not DBIDResp; using it here previously meant write
    // transactions never left TX_AWAIT_RSP, so cp_phase could not reach
    // await_datasend / await_comp and cp_phase_seq could not reach
    // SEQ_WRITE_COMBINED.
    assign rsp_is_dbidresp = RXRSPFLITV && (rsp_opcode_w == `CHIE_DBIDRESP);
    assign rsp_is_compdbid = RXRSPFLITV && (rsp_opcode_w == `CHIE_COMPDBIDRESP);
    assign rsp_is_comp     = RXRSPFLITV && (rsp_opcode_w == `CHIE_COMP);
    assign dat_is_compdata = RXDATFLITV && (dat_opcode_w == `CHIE_COMPDATA);

    // Snoop-retired event (forward-declared so the TX-FSM always_ff
    // below can use it for the L1 transition update).
    wire snoop_retired = rx_resp_owed &&
                         ((TXRSPFLITV &&
                           TXRSPFLIT[`CHIE_RSP_FLIT_OPCODE_RANGE] == 5'h01) ||
                          (TXDATFLITV &&
                           TXDATFLIT[`CHIE_DAT_FLIT_OPCODE_RANGE] == 4'h1));
    // CHI-E CompData Resp field is 3 bits at CHIE_DAT_FLIT_RESP_RANGE.
    // Encoding (CHI E.b table 4.10):
    //   3'b010 = UC,     3'b011 = UD (pass-dirty)
    //   3'b110 = SC,     3'b111 = SD (pass-dirty)
    // Bit 0 of Resp = PassDirty.  Earlier the tracker treated every
    // CompData as dirty, collapsing all clean/dirty arrivals into the
    // SD/UD bins.  Parsing the PD bit splits them correctly.
    wire [2:0] dat_resp = RXDATFLIT[`CHIE_DAT_FLIT_RESP_RANGE];
    // CHI E.b CompData Resp field is {PD, state[1:0]} (see
    // CHIE_COMP_RESP_* in chie_defines.v line 900+).  PD lives in
    // bit [2], not bit [0].  Used to identify Pass-Dirty responses
    // for phase classification.
    assign dat_carries_dirty = dat_is_compdata && dat_resp[2];

    // Latch the CompData Resp field so the post-CompAck L1 update can
    // use it directly.  CHI E.b CompData Resp encoding:
    //   010 = UC, 011 = UD, 110 = SC, 111 = SD.
    // last_resp_valid is set when CompData arrives and cleared inside
    // the main TX FSM always_ff (in the AWAIT_COMPACK case) -- kept
    // in one process to avoid multi-driver errors.
    logic [2:0] last_compdata_resp;
    logic       last_resp_valid;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_phase           <= TX_IDLE;
            tx_write_combined <= 1'b0;
            tx_op              <= TX_NONE;
            tx_compack_dirty   <= 1'b0;
            inferred_l1        <= L1_I;
            last_compdata_resp <= 3'b000;
            last_resp_valid    <= 1'b0;
        end
        else begin
            // Latch CompData Resp whenever a CompData arrives, in any
            // phase (covers TX_AWAIT_RSP + TX_AWAIT_COMP for atomics).
            if (dat_is_compdata) begin
                last_compdata_resp <= dat_resp;
                last_resp_valid    <= 1'b1;
            end
            // Snoop-driven L1 transition (e.g. SnpMakeInvalid -> I)
            // -- transition fires on the cycle the DUT retires the
            // snoop response.  Inline the post-state derivation
            // (function defined below) so we avoid forward refs.
            if (snoop_retired) begin
                case (rx_snp_op)
                    RX_SNPCLEAN: begin
                        if (inferred_l1 == L1_UD || inferred_l1 == L1_UC ||
                            inferred_l1 == L1_SD)
                            inferred_l1 <= L1_SC;
                    end
                    RX_SNPUNIQUE,
                    RX_SNPMAKEINVALID,
                    RX_SNPCLEANINVALID:
                        inferred_l1 <= L1_I;
                    RX_SNPSHARED: begin
                        if (inferred_l1 == L1_UD) inferred_l1 <= L1_SD;
                        else if (inferred_l1 == L1_UC) inferred_l1 <= L1_SC;
                    end
                    default: ;
                endcase
            end
            unique case (tx_phase)
                TX_IDLE: begin
                    if (TXREQFLITV) begin
                        tx_op    <= decode_req_opcode(
                                       TXREQFLIT[`CHIE_REQ_FLIT_OPCODE_RANGE]);
                        tx_phase <= TX_AWAIT_RSP;
                    end
                end
                TX_AWAIT_RSP: begin
                    // Reads -> CompData; dataless coherent -> Comp;
                    // writes/atomics -> DBIDResp.
                    if (dat_is_compdata) begin
                        tx_phase         <= dat_carries_dirty ?
                                            TX_AWAIT_COMPACK_DIRTY :
                                            TX_AWAIT_COMPACK_CLEAN;
                        tx_compack_dirty <= dat_carries_dirty;
                    end
                    else if (rsp_is_dbidresp || rsp_is_compdbid) begin
                        tx_phase <= TX_AWAIT_DATA_SEND;
                        tx_write_combined <= rsp_is_compdbid;
                    end
                    else if (rsp_is_comp) begin
                        // Dataless or Evict
                        if (tx_op == TX_EVICT) begin
                            tx_phase <= TX_IDLE;
                            tx_op    <= TX_NONE;
                        end else begin
                            tx_phase <= TX_AWAIT_COMPACK_CLEAN;
                        end
                    end
                end
                TX_AWAIT_DATA_SEND: begin
                    if (TXDATFLITV) tx_phase <= TX_AWAIT_COMP;
                end
                TX_AWAIT_COMP: begin
                    if (rsp_is_comp || dat_is_compdata) begin
                        // Writes/atomics complete here; no CompAck.
                        // Update inferred_l1 based on the op that
                        // just retired (no CompData Resp to consult).
                        case (tx_op)
                            TX_WRITEBACKFULL,
                            TX_EVICT:        inferred_l1 <= L1_I;
                            TX_WRITECLEANFUL: begin
                                // UD -> UC (WriteCleanFull keeps the
                                // line resident, just pushes dirty
                                // data back).  If the prior state
                                // wasn't dirty this is a no-op.
                                if (inferred_l1 == L1_UD) inferred_l1 <= L1_UC;
                                if (inferred_l1 == L1_SD) inferred_l1 <= L1_SC;
                            end
                            TX_ATOMICLOAD,
                            TX_ATOMICSTORE:  inferred_l1 <= inferred_l1; // unchanged
                            default: ;
                        endcase
                        tx_phase <= TX_IDLE;
                        tx_op    <= TX_NONE;
                    end
                end
                TX_AWAIT_COMPACK_CLEAN, TX_AWAIT_COMPACK_DIRTY: begin
                    // CompAck is RSP opcode 5'h02 (`CHIE_COMPACK).
                    if (TXRSPFLITV &&
                        TXRSPFLIT[`CHIE_RSP_FLIT_OPCODE_RANGE] == 5'h02) begin
                        // For data-bearing transactions (Read* + the
                        // few CompData-bearing variants) trust the
                        // CompData Resp field directly -- it's the
                        // canonical CHI source of post-state per
                        // E.b table 4.10.  For dataless completions
                        // (MakeUnique, CleanUnique, CleanInvalid) the
                        // L1 state is determined by tx_op alone.
                        if (last_resp_valid) begin
                            // Match CHIE_COMP_RESP_* encoding from
                            // chie_defines.v line 900+: {PD, state[1:0]}.
                            case (last_compdata_resp)
                                3'b001: inferred_l1 <= L1_SC;
                                3'b010: inferred_l1 <= L1_UC;
                                3'b110: inferred_l1 <= L1_UD;
                                3'b111: inferred_l1 <= L1_SD;
                                default: ; // unknown -- keep old
                            endcase
                        end else begin
                            unique case (tx_op)
                                TX_MAKEUNIQUE,
                                TX_CLEANUNIQUE:  inferred_l1 <= L1_UC;
                                TX_CLEANINVALID: inferred_l1 <= L1_I;
                                default: ; // CleanShared / others -- no change
                            endcase
                        end
                        tx_phase         <= TX_IDLE;
                        tx_op            <= TX_NONE;
                        tx_compack_dirty <= 1'b0;
                        last_resp_valid  <= 1'b0;
                    end
                end
                default: tx_phase <= TX_IDLE;
            endcase
        end
    end

    // ── RX snoop tracking ──────────────────────────────────────────
    // Updates rx_snp_op + rx_resp_owed for race-intersection coverage,
    // AND updates inferred_l1 when the snoop retires so cg_l1_transitions
    // sees snoop-driven L1 changes (e.g. UD -> I on SnpMakeInvalid).
    //
    // Post-snoop L1 derived from (snoop opcode x current L1 state),
    // mirroring the per-(snp_op x L1) decision table in rnf_fsm.m.
    function automatic l1_state_e snoop_post_state(input rx_snp_op_e op,
                                                   input l1_state_e l1);
        case (op)
            RX_SNPCLEAN: begin
                // Downgrade to SC; if was SD, stay SD-clean = SC
                if (l1 == L1_UD || l1 == L1_UC) snoop_post_state = L1_SC;
                else if (l1 == L1_SD)            snoop_post_state = L1_SC;
                else                             snoop_post_state = l1;
            end
            RX_SNPUNIQUE,
            RX_SNPMAKEINVALID,
            RX_SNPCLEANINVALID:                  snoop_post_state = L1_I;
            RX_SNPSHARED: begin
                if (l1 == L1_UD)                 snoop_post_state = L1_SD;
                else if (l1 == L1_UC)            snoop_post_state = L1_SC;
                else                             snoop_post_state = l1;
            end
            default:                             snoop_post_state = l1;
        endcase
    endfunction

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_snp_op    <= RX_NONE;
            rx_resp_owed <= 1'b0;
        end
        else begin
            // New snoop arriving
            if (RXSNPFLITV && !rx_resp_owed) begin
                rx_snp_op    <= decode_snp_opcode(
                                   RXSNPFLIT[`CHIE_SNP_FLIT_OPCODE_RANGE]);
                rx_resp_owed <= 1'b1;
            end
            // SnpResp (no data) or SnpRespData -- DUT just retired the
            // snoop.  Update inferred_l1 to the post-snoop state.
            else if (rx_resp_owed && ((TXRSPFLITV &&
                     TXRSPFLIT[`CHIE_RSP_FLIT_OPCODE_RANGE] == 5'h01) ||
                     (TXDATFLITV &&
                      TXDATFLIT[`CHIE_DAT_FLIT_OPCODE_RANGE] == 4'h1))) begin
                rx_snp_op    <= RX_NONE;
                rx_resp_owed <= 1'b0;
                // NB: inferred_l1 update happens in the main TX-FSM
                // always_ff (kept single-driver).  We hand it the
                // snoop completion via a single-cycle pulse.
            end
        end
    end

    // snoop_retired is declared up by the other opcode-decode wires
    // so the TX-FSM always_ff can reference it.

endmodule
