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



module chi_icn_buffer #(
    parameter int RX_NUM_CRDTS = 8,
    parameter int TX_NUM_CRDTS = 15,
    parameter int DATA_WIDTH = 128
)(

    input  logic clk,
    input  logic rst,

    input  logic                       rxflitv,
    input  logic [DATA_WIDTH-1:0] rxflit,
    output logic                       rxlcrdv,

    output logic                       txflitv,
    input  logic [DATA_WIDTH-1:0] txflit,
    input  logic                       txlcrdv,

    input  logic [1:0]            rx_link_state,
    input  logic [1:0]            tx_link_state
);

    // FIFO Interface Signals
    logic                            fifo_push;
    logic                            fifo_pop;
    logic                            fifo_full;
    logic                            fifo_empty;

    // Credit Logic Signals
    logic [3:0] tx_crdt_cnt; // Adjust based on TX_NUM_CRDTS


    // --- 1. Buffer Controller Instance ---
    chi_icn_buffer_ctrl #(
        .RX_NUM_CRDTS (RX_NUM_CRDTS),
        .TX_NUM_CRDTS (TX_NUM_CRDTS)
    ) u_buffer_ctrl (
        .clk            (clk),
        .rst            (!rst_n), // Assuming rst in ctrl is active high

        // RX Side (Receiving flits into the buffer)
        .rxflitv        (rxflitv),
        .rxlcrdv        (rxlcrdv),
        .rx_link_state  (rx_link_state),

        // TX Side (Sending flits out of the buffer)
        .txflitv        (txflitv),
        .txlcrdv        (txlcrdv),
        .tx_link_state  (tx_link_state),

        // FIFO Control Interface
        .fifo_push_o    (fifo_push),
        .fifo_pop_o     (fifo_pop),
        .fifo_full_i    (fifo_full),
        .fifo_empty_i   (fifo_empty)
    );

    // --- 2. Fall-Through FIFO Instance ---
    fifo_v3 #(
        .FALL_THROUGH   (1'b1),
        .DATA_WIDTH     (DATA_WIDTH),
        .DEPTH          (RX_NUM_CRDTS),
        .dtype          (logic [DATA_WIDTH-1:0])
    ) u_req_fifo (
        .clk_i          (clk),
        .rst_ni         (rst_n),
        .flush_i        (1'b0),
        .testmode_i     (1'b0),

        .full_o         (fifo_full),
        .empty_o        (fifo_empty),
        .usage_o        (), // Optional monitoring

        .data_i         (rxflit), // Data directly from the input port
        .push_i         (fifo_push),   // Gated by controller

        .data_o         (txflit), // Data directly to the output port
        .pop_i          (fifo_pop)     // Gated by controller
    );

endmodule