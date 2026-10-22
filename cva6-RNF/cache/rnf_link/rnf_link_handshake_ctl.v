 /*
 * Copyright (c) 2026 Tampere University
 * Licensed under the Solderpad Hardware License v 2.1, see LICENSE for details.
 * SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
 */

//==================================================================================================
//  Filename        : rnf_link_handshake_ctl
//  Author          : Teemu Rinne, Tampere University
//
//  Description     : AMBA CHI based link layer interface activation and deactivation
//
//==================================================================================================



`include "chie_defines.v"
`include "rnf_defines.v"
`include "rnf_param.v"

module rnf_link_handshake_ctl  `RNF_PARAM
    (
        // global inputs
        clk,
        rst,

        // link handshake
        TXLINKACTIVEREQ,
        TXLINKACTIVEACK,
        RXLINKACTIVEREQ,
        RXLINKACTIVEACK,

        TXACTIVE,
        RXACTIVE,

        tx_active_ready,
        tx_ready,
        tx_lcredits_used,
        rx_ready,
        rx_lcredits_returned

    );

    input wire clk;
    input wire rst;

    output wire TXLINKACTIVEREQ;
    input wire TXLINKACTIVEACK;
    input wire RXLINKACTIVEREQ;
    output wire RXLINKACTIVEACK;

    output wire TXACTIVE;
    input wire RXACTIVE;
    
    input wire tx_active_ready;                 // Signal to show that TXLINKACTIVEREQ can be asserted
    output wire tx_ready;                       // Indicate that TX flits can be sent   
    input wire [2:0] tx_lcredits_used;          // if all L-credits are returned to receivers

    output wire rx_ready;                       // signal for IFs that L-credits can be given
    input wire [2:0] rx_lcredits_returned;      // if all L-credits are returned when transmitter entering lowpower


    reg rx_active_ack;

    reg [1:0] tx_state;
    reg [1:0] tx_state_next;
    reg [1:0] rx_state;
    reg [1:0] rx_state_next;

    reg tx_active;

    reg tx_ready_s;
    reg rx_ready_s;

    assign TXLINKACTIVEREQ = (tx_state == `CHIE_TXLA_ACTIVATE || tx_state == `CHIE_TXLA_RUN);
    assign RXLINKACTIVEACK = rx_active_ack;
    assign TXACTIVE = tx_active;

    assign tx_ready = tx_ready_s;
    assign rx_ready = rx_ready_s;


    always @ (posedge clk or posedge rst) begin
        if (rst) begin
            tx_state <= 'b0;
            rx_state <= 'b0;
        end
        else begin
            tx_state <= tx_state_next;
            rx_state <= rx_state_next;
        end
    end


    always @ (*) begin : tx_active_control
    
        tx_state_next = `CHIE_TXLA_STOP;
        tx_active = 'b0;
        tx_ready_s = 'b0;

        if (tx_state == `CHIE_TXLA_STOP) begin
            if(tx_active_ready) begin
                tx_state_next = `CHIE_TXLA_ACTIVATE;
            end
        end

        else if (tx_state == `CHIE_TXLA_ACTIVATE) begin
            if (TXLINKACTIVEACK) begin
                tx_state_next = `CHIE_TXLA_RUN;
            end
            else if (!tx_active_ready) begin
                tx_state_next = `CHIE_TXLA_DEACTIVATE;
            end
            else begin
                tx_state_next = `CHIE_TXLA_ACTIVATE;
            end
        end

        else if (tx_state == `CHIE_TXLA_RUN) begin
            tx_active = 'b1;
            tx_ready_s = 'b1;
            if(!tx_active_ready) begin
                tx_state_next = `CHIE_TXLA_DEACTIVATE;
            end
            else begin
                tx_state_next = `CHIE_TXLA_RUN;
            end
        end

        else if (tx_state == `CHIE_TXLA_DEACTIVATE) begin
            if((tx_lcredits_used == 3'b111) && !TXLINKACTIVEACK) begin
                tx_state_next = `CHIE_TXLA_STOP;
                tx_ready_s = 'b0;
            end
            else begin
                tx_state_next = `CHIE_TXLA_DEACTIVATE;
                tx_active = 'b1;
                tx_ready_s = 'b1;
            end
        end
    end


    always @ (*) begin : rx_active_control
    
        rx_state_next = `CHIE_RXLA_STOP;
        rx_active_ack = 1'b0;
        rx_ready_s = 1'b0;

        if (rx_state == `CHIE_RXLA_STOP) begin
            if(RXLINKACTIVEREQ) begin
                rx_state_next = `CHIE_RXLA_ACTIVATE;
            end
        end

        else if (rx_state == `CHIE_RXLA_ACTIVATE) begin

            rx_ready_s = 1'b1;

            if (RXLINKACTIVEREQ) begin
                rx_state_next = `CHIE_RXLA_RUN;
                rx_active_ack = 1'b1;
            end
            else begin
                rx_state_next = `CHIE_RXLA_DEACTIVATE;
            end
        end

        else if (rx_state == `CHIE_RXLA_RUN) begin
            rx_active_ack = 1'b1;
            if(!RXLINKACTIVEREQ) begin
                rx_state_next = `CHIE_RXLA_DEACTIVATE;
            end
            else begin
                rx_state_next = `CHIE_RXLA_RUN;
                rx_ready_s = 1'b1;
            end
        end

        else if (rx_state == `CHIE_RXLA_DEACTIVATE) begin
            if(!(rx_lcredits_returned == 3'b111)) begin
                rx_state_next = `CHIE_RXLA_DEACTIVATE;
                rx_active_ack = 1'b1;
            end
            else begin
                rx_state_next = `CHIE_RXLA_STOP;
            end
        end

    end


endmodule 