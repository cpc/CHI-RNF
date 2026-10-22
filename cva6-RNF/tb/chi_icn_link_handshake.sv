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


module chi_icn_link_handshake #(
)(

    input  logic clk,
    input  logic rst,

    // Link layer handshake
    input  logic                      txlinkactivereq,
    output logic                      txlinkactiveack,
    output logic                      rxlinkactivereq,
    input  logic                      rxlinkactiveack,

    input  logic                      txactive,
    output logic                      rxactive,

    input  logic                      txflit_avail_i,

    output logic [1:0]                txlink_state,
    output logic [1:0]                rxlink_state
);

    typedef enum logic [2:0] {
        CHI_LNK_STOP       = 2'b00, // Link is inactive/reset
        CHI_LNK_ACTIVATE   = 2'b10, // Activation handshake in progress
        CHI_LNK_RUN        = 2'b11, // Link is active; flits and credits can flow
        CHI_LNK_DEACTIVATE = 2'b01  // Transitioning to low power
    } lnk_state_e;

    lnk_state_e txlink_state_q, rxlink_state_q;
    logic       txlinkactivereq_q, txlinkactiveack_d, txlinkactiveack_q;
    logic       rxlinkactivereq_q, rxlinkactiveack_q;


    always @(posedge clk or posedge rst) begin
        if (rst == 1'b1)
            txlinkactiveack_q <= 1'b0;
        else
            txlinkactiveack_q <= txlinkactiveack_d;
    end


    always_comb begin
        case(rxlink_state_q)
           2'b00:
            txlinkactiveack_d = txflit_avail_i;
           2'b11:
            txlinkactiveack_d = 1'b1;
           default:
            txlinkactiveack_d = txlinkactivereq;
        endcase
    end

    assign txlink_state_q = {txlinkactivereq, txlinkactiveack_q};


    always @(posedge clk or posedge rst)begin
        if (rst == 1'b1)
            rxlinkactivereq_q <= 1'b0;
        else
            rxlinkactivereq_q <= rxlinkactivereq_d;
    end

    always_comb begin
        case(rxlink_state_q)
           2'b00:
            rxlinkactivereq_d = 1'b1;
           2'b10:
            rxlinkactivereq_d = 1'b1;
           2'b01:
            rxlinkactivereq_d = 1'b0;
           2'b11:
            rxlinkactivereq_d = 1'b1;
           default:
            rxlinkactivereq_d = 1'b0;
        endcase
    end

    assign rxlink_state_q = {rxlinkactivereq_q, rxlinkactiveack};

endmodule