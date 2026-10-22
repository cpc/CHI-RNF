// Original work:
/*
Copyright (c) 2015 Princeton University
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:
    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of Princeton University nor the
      names of its contributors may be used to endorse or promote products
      derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY PRINCETON UNIVERSITY "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL PRINCETON UNIVERSITY BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/


// Modifications: 
/*
 * Copyright (c) 2026 Tampere University
 * Licensed under the Solderpad Hardware License v 2.1, see LICENSE for details.
 * SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
 */

//==================================================================================================
//  Filename        : rf_rnf_lrsc_flag (original rf_l15_lrsc_flag)
//  Original Author : Fei Gao, feig@princeton.edu, Princeton University
//  Modified        : Teemu Rinne, Tampere University
//
//  Description     : LRSC-flag register file of AMBA CHI based RN-F coherent cache
//
//==================================================================================================



//`timescale 1 ns / 10 ps
//`default_nettype none


`include "l15.tmp.h"

// Each entry stores 3 bits per L15 way: {sub_blk_id[1:0], lrsc_flag}
// sub_blk_id = address[5:4], identifying which 16B sub-block within the 64B line holds the reservation
// Total 4 ways * 3 bits = 12 bits per set
module rf_rnf_lrsc_flag(
   input wire clk,
   input wire rst_n,

   input wire read_valid,
   input wire [`L15_CACHE_INDEX_WIDTH-1:0] read_index,

   input wire write_valid,
   input wire [`L15_CACHE_INDEX_WIDTH-1:0] write_index,
   input wire [`L15_LRSC_MASK] write_mask,
   input wire [`L15_LRSC_MASK] write_data,

   output wire [`L15_LRSC_MASK] read_data
   );



// reg read_valid_f;
reg [`L15_CACHE_INDEX_WIDTH-1:0] read_index_f;
reg [`L15_CACHE_INDEX_WIDTH-1:0] write_index_f;
reg [`L15_LRSC_MASK] write_data_f;
reg [`L15_LRSC_MASK] write_mask_f;
reg write_valid_f;

reg [`L15_LRSC_MASK] regfile [0:`L15_CACHE_INDEX_VECTOR_WIDTH-1];

integer i;

always @ (posedge clk)
begin
   if (!rst_n)
   begin
      read_index_f <= 0;
   end
   else
   if (read_valid)
      read_index_f <= read_index;
   else
      read_index_f <= read_index_f;
end

// read port
assign read_data = regfile[read_index_f];

// Write port
always @ (posedge clk)
begin
   write_valid_f <= write_valid;
   if (write_valid)
   begin
      write_data_f <= write_data;
      write_index_f <= write_index;
      write_mask_f <= write_mask;
   end
end

always @ (posedge clk)
begin
   if (!rst_n)
   begin
      for (i=0; i<`L15_CACHE_INDEX_VECTOR_WIDTH; i=i+1) begin
         regfile[i] <= `L15_LRSC_WIDTH'b0;
      end 

      // regfile <= 1024'b0;
   end
   else
   if (write_valid_f)
   begin
      regfile[write_index_f] <= (write_data_f & write_mask_f) | (regfile[write_index_f] & ~write_mask_f);
   end
end
endmodule
