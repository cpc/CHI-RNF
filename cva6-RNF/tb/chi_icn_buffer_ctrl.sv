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


module chi_icn_buffer_ctrl #(
    parameter int RX_NUM_CRDTS = 8,
    parameter int TX_NUM_CRDTS = 15
)(

    input  logic clk,
    input  logic rst,

    input  logic                       rxflitv,
    // input  logic [FLIT_DATA_WIDTH-1:0] rxflit,
    output logic                       rxlcrdv,

    input  logic [1:0]                 rx_link_state,

    output logic                       fifo_pop_o,

    output logic                       txflitv,

    // input  logic [FLIT_DATA_WIDTH-1:0] rxflit,
    input  logic                       txlcrdv,

    input  logic [1:0]                 tx_link_state,

    output logic                       fifo_push_o,

    input  logic                       fifo_full_i,
    input  logic                       fifo_empty_i
);

    logic [$clog2(RX_NUM_CRDTS):0] rx_crdt_count_val;
    logic rx_has_credits;
    logic rx_crdt_count_give, rx_crdt_count_take;

    logic [$clog2(TX_NUM_CRDTS):0] tx_crdt_count_val;
    logic tx_has_credits;
    logic tx_crdt_count_give, tx_crdt_count_take;

    logic rx_reclaim_crdt;


    credit_counter #(
        .NumCredits      (RX_NUM_CRDTS),
        .InitCreditEmpty (1'b0),
        .InitNumCredits  (RX_NUM_CRDTS)
    ) u_rx_credit_cnt (
        .clk_i           (clk),
        .rst_ni          (~rst),

        .credit_o        (rx_crdt_count_val),

        // In CHI, receiving an LCRDV "gives" us a credit to use
        .credit_give_i   (rx_crdt_count_give),

        // Sending a FLITV "takes" (consumes) one credit
        .credit_take_i   (rx_crdt_count_take),

        .credit_init_i   (1'b0), // Tie to 0 unless you need a soft-reset trigger

        .credit_left_o   (rx_has_credits), // This gates your arbiter/valid logic
        .credit_crit_o   (),                    // Unused
        .credit_full_o   ()                     // Unused
    );


    credit_counter #(
        .NumCredits      (TX_NUM_CRDTS),
        .InitCreditEmpty (1'b1) // CHI links start with 0 credits until seeding happens
    ) u_tx_credit_cnt (
        .clk_i           (clk),
        .rst_ni          (~rst),

        .credit_o        (tx_crdt_count_val),

        // In CHI, receiving an LCRDV "gives" us a credit to use
        .credit_give_i   (tx_crdt_count_give),

        // Sending a FLITV "takes" (consumes) one credit
        .credit_take_i   (tx_crdt_count_take),

        .credit_init_i   (1'b0), // Tie to 0 unless you need a soft-reset trigger

        .credit_left_o   (tx_has_credits),      // This gates your arbiter/valid logic
        .credit_crit_o   (),                    // Unused
        .credit_full_o   ()                     // Unused
    );


    always_comb begin
        tx_crdt_count_give = 1'b0;
        rx_crdt_count_give = 1'b0;

        tx_crdt_count_take = 1'b0;
        rx_crdt_count_take = 1'b0;

        fifo_push_o = 1'b0;
        fifo_pop_o  = 1'b0;

        txflitv = 1'b0;
        rxlcrdv = 1'b0;

        case(tx_link_state)
            2'b11: begin
                if(~fifo_empty_i & tx_has_credits) begin  // Exhaust the credits and stream the TX Flits
                    txflitv = 1'b1;
                    tx_crdt_count_take = 1'b1;

                    rx_reclaim_crdt = 1'b1;  // give-back a credit to the RX side

                    fifo_pop_o = 1'b1;   // TODO: This works only for a fall-through FIFO
                end

                if(txlcrdv) begin
                    tx_crdt_count_give = 1'b1;
                end
            end
            default: begin
                ;
            end
        endcase

        case(rx_link_state)
            2'b11: begin
                if(rxflitv) begin
                    fifo_push_o = 1'b1;

                    rx_crdt_count_take = 1'b1;
                end

                if(rx_has_credits) begin
                    rxlcrdv = 1'b1;
                end

                if(rx_reclaim_crdt) begin
                    rx_crdt_count_give = 1'b1;
                end

            end
            default: begin
                ;
            end
        endcase
    end


endmodule