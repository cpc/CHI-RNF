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
//  Filename        : rf_rnf_wmt (original rf_l15_wmt)
//  Original Author : Tri Nguyen, trin@princeton.edu, Princeton University
//  Modified        : Teemu Rinne, Tampere University
//
//  Description     : Way-map table (WMT) register file of AMBA CHI based RN-F coherent cache
//                      - tracks index and way of cacheline in L1D (wt_dcache)
//                      - structure as in L1D-wt_dcache (associativity, line count)
//                      - Entry: rnf_cache-way_count*(| valid | rnf_cache-way |)
//                         - if alias bits are required due to unmatching line-counts between wt-dcache and rnf_cache:
//                            rnf_cache-way_count*(| valid | rnf_cache-way | addr[L1D_addr_hi+1 +: alias_w] |)
//
//==================================================================================================



// trin timing fix 12/16: move read s3 to s2
// timing 12/17: move write to s2 to s3


`include "l15.tmp.h"


module rf_rnf_wmt(
   input wire clk,
   input wire rst_n,

   input wire read_valid,
   input wire [`L1D_SET_IDX_MASK] read_index,

   input wire write_valid,
   input wire [`L1D_SET_IDX_MASK] write_index,
   input wire [`L15_WMT_MASK] write_mask,
   input wire [`L15_WMT_MASK] write_data,

   output wire [`L15_WMT_MASK] read_data
   );


// reg [`L15_WMT_MASK] data_out_f;

// reg [`L15_WMT_MASK] regfile [0:127];

// always @ (posedge clk)
// begin
//    if (read_valid)
//       data_out_f <= regfile[read_index];
// end


// assign read_data = data_out_f;


reg [`L15_WMT_MASK] data_out_f;
reg [`L1D_SET_IDX_MASK] write_index_f;
reg [`L15_WMT_MASK] write_data_f;
reg [`L15_WMT_MASK] write_mask_f;
reg write_valid_f;

reg [`L15_WMT_MASK] regfile [0:`L15_WMT_ENTRY_COUNT-1];

// reset loop index
integer wmt_rst_i;

always @ (posedge clk)
begin
   if (read_valid)
      data_out_f <= regfile[read_index];
end


assign read_data = data_out_f;

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
      for (wmt_rst_i = 0; wmt_rst_i < `L15_WMT_ENTRY_COUNT; wmt_rst_i = wmt_rst_i + 1)
         regfile[wmt_rst_i] <= {`L15_WMT_WIDTH{1'b0}};
   end
   else
   if (write_valid_f)
   begin
      regfile[write_index_f] <= (write_data_f & write_mask_f) | (regfile[write_index_f] & ~write_mask_f);
   end
end
endmodule
