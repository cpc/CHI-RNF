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
//  Filename        : txreq_encoder (original noc1encoder)
//  Original Author : Tri Nguyen, trin@princeton.edu, Princeton University
//  Modified        : Teemu Rinne, Tampere University
//
//  Description     : Request encoder of AMBA CHI based RN-F coherent cache
//
//==================================================================================================


`include "l15.tmp.h"
`include "define.tmp.h"

`include "rnf_param.v"
`include "rnf_defines.v"
`include "chie_defines.v"

`ifdef DEFAULT_NETTYPE_NONE
`default_nettype none
`endif
module txreq_encoder `RNF_PARAM (
   input wire clk,
   input wire rst_n,

   // interface with noc1buffer
   input wire [63:0] noc1buffer_noc1encoder_req_data_0,
   input wire [63:0] noc1buffer_noc1encoder_req_data_1,
   input wire noc1buffer_noc1encoder_req_val,
   input wire [`L15_NOC1_REQTYPE_WIDTH-1:0] noc1buffer_noc1encoder_req_type,
   input wire [`L15_MSHR_ID_WIDTH-1:0] noc1buffer_noc1encoder_req_mshrid,
   input wire [`L15_THREADID_MASK] noc1buffer_noc1encoder_req_threadid,
   input wire [39:0] noc1buffer_noc1encoder_req_address,
   input wire noc1buffer_noc1encoder_req_non_cacheable,
   input wire [`PCX_SIZE_WIDTH-1:0] noc1buffer_noc1encoder_req_size,
   input wire noc1buffer_noc1encoder_req_prefetch,
   input wire [`PACKET_HOME_ID_WIDTH-1:0] noc1buffer_noc1encoder_req_homeid,
   input wire [`MSG_SDID_WIDTH-1:0] noc1buffer_noc1encoder_req_csm_sdid,
   input wire [`MSG_LSID_WIDTH-1:0] noc1buffer_noc1encoder_req_csm_lsid,

   output reg noc1encoder_noc1buffer_req_ack,

   // ready at noc1
   input wire noc1out_ready,
   output reg noc1encoder_noc1out_val,          // Used with CHI TXREQ valid signal

   output wire [127:0] atomic_data,

   // CHI message outputs
   output wire [`CHIE_REQ_FLIT_TXNID_WIDTH-1:0]             encoder_txreq_txnid_sx1_q,     
   output wire [`CHIE_REQ_FLIT_OPCODE_WIDTH-1:0]            encoder_txreq_opcode_sx1,      
   output wire [`CHIE_REQ_FLIT_SIZE_WIDTH-1:0]              encoder_txreq_size_sx1,        
   output wire [`CHIE_REQ_FLIT_ADDR_WIDTH-1:0]              encoder_txreq_addr_sx1,        
   output wire [`CHIE_REQ_FLIT_DODWT_WIDTH-1:0]             encoder_txreq_snpattr,
   output wire [`CHIE_REQ_FLIT_TGTID_RANGE]                 encoder_txreq_tgtid,           
   output wire [`CHIE_REQ_FLIT_SRCID_RANGE]                 encoder_txreq_srcid,           
   output wire [`CHIE_REQ_FLIT_LIKELYSHARED_WIDTH-1:0]      encoder_txreq_likelyshared,
   output wire [`CHIE_REQ_FLIT_QOS_WIDTH-1:0]               encoder_txreq_qos_sx1,
   output wire [`CHIE_REQ_FLIT_RETURNNID_WIDTH-1:0]         encoder_txreq_returnnid_sx1,
   output wire [`CHIE_REQ_FLIT_RETURNTXNID_WIDTH-1:0]       encoder_txreq_returntxnid_sx1,
   output wire [`CHIE_REQ_FLIT_NS_WIDTH-1:0]                encoder_txreq_ns_sx1,
   output wire [`CHIE_REQ_FLIT_ALLOWRETRY_WIDTH-1:0]        encoder_txreq_allowretry_sx1,
   output wire [`CHIE_REQ_FLIT_ORDER_WIDTH-1:0]             encoder_txreq_order_sx1,
   output wire [`CHIE_REQ_FLIT_PCRDTYPE_WIDTH-1:0]          encoder_txreq_pcrdtype_sx1,
   output wire [`CHIE_REQ_FLIT_MEMATTR_WIDTH-1:0]           encoder_txreq_memattr_sx1,
   output wire [`CHIE_REQ_FLIT_TRACETAG_WIDTH-1:0]          encoder_txreq_tracetag_sx1,
   output wire                                              encoder_txreq_reg_icache,
   output wire [`CHIE_REQ_FLIT_EXCL_WIDTH-1:0]              encoder_txreq_exclusive,
   output wire [`CHIE_REQ_FLIT_ENDIAN_WIDTH-1:0]            encoder_txreq_endian,
   output wire [`CHIE_REQ_FLIT_LPID_WIDTH-1:0]              encoder_txreq_lpid,
   output wire [`CHIE_REQ_FLIT_EXPCOMPACK_WIDTH-1:0]        encoder_txreq_expcompack,
   input wire                                               txreq_enc_won_sx1,

   input wire                                               receipt_received,
   input wire                                               requestregister_rdy

);

// CHI logic
reg channel_ready;

reg sending;
reg control_raw_data_flit1;

reg block_ordered_reqs;
reg ordered_req;

// Block later Requests requiring Request/Endpoint ordering, if one has already been sent
always @ (posedge clk)
begin
   if (!rst_n)
   begin
      block_ordered_reqs <= 0;
   end
   else
   begin
      if (receipt_received) begin
         block_ordered_reqs <= 'b0;
      end else if (sending && txreq_enc_won_sx1 && ordered_req) begin
         block_ordered_reqs <= 'b1;
      end
   end
end


reg [`L15_NOC1_REQTYPE_WIDTH-1:0] req_type;

always @ *
begin

   // Do not send OP-WRBackGuards with CHI, and block ordered requests if waiting for permission to send them from a completer/PoS after last ordered req
   sending = ((noc1buffer_noc1encoder_req_val && req_type != `L15_NOC1_REQTYPE_WRITEBACK_GUARD)) && !(ordered_req && block_ordered_reqs) && requestregister_rdy;
   noc1encoder_noc1out_val = sending;

   // Wait until the request is sent (signaled with txreq_enc_won_sx1)
   channel_ready = noc1out_ready && (txreq_enc_won_sx1 || req_type == `L15_NOC1_REQTYPE_WRITEBACK_GUARD);

end


reg [`L15_NOC1ENCODER_SOURCE_WIDTH-1:0] req_source;
reg req_prefetch;
reg req_nc;
// reg req_blkstore;
// reg req_blkinitstore;
reg [63:0] req_data0;
reg [63:0] req_data1;
reg [`CHIE_REQ_FLIT_ADDR_WIDTH:0] req_address;
reg [`CHIE_REQ_FLIT_TXNID_WIDTH-1:0] req_mshrid;
reg [`PCX_SIZE_WIDTH-1:0] req_size;
reg [`NOC_X_WIDTH-1:0] req_dest_l2_xpos;
reg [`NOC_Y_WIDTH-1:0] req_dest_l2_ypos;
reg [`NOC_CHIPID_WIDTH-1:0] req_dest_chipid;

always @ *
begin
   req_source = 0;
   req_type = 0;
   req_prefetch = 0;
   req_nc = 0;
   // req_blkstore = 0;
   // req_blkinitstore = 0;
   req_data0 = 0;
   req_data1 = 0;
   req_address = 0;
   req_mshrid = 0;
   req_size = 0;
   req_dest_l2_xpos = 0;
   req_dest_l2_ypos = 0;
   req_dest_chipid = 0;

   req_source = `L15_NOC1ENCODER_SOURCE_L15;

   if (req_source == `L15_NOC1ENCODER_SOURCE_L15)
   begin
      req_type = noc1buffer_noc1encoder_req_type;
      req_prefetch = noc1buffer_noc1encoder_req_prefetch;
      req_nc = noc1buffer_noc1encoder_req_non_cacheable;
      // req_blkstore = 1'b0; // All block stores are translated to normal stores
      // req_blkinitstore = 1'b0;
      req_data0 = noc1buffer_noc1encoder_req_data_0;
      req_data1 = noc1buffer_noc1encoder_req_data_1;
      req_address = noc1buffer_noc1encoder_req_address;
      req_mshrid = {noc1buffer_noc1encoder_req_threadid,noc1buffer_noc1encoder_req_mshrid};
      req_mshrid[`CHIE_REQ_FLIT_TXNID_WIDTH-1 -: (`CHIE_REQ_FLIT_TXNID_WIDTH-`L15_MSHR_ID_WIDTH-`L15_THREADID_WIDTH)] = RNF_NID; 
      req_size = noc1buffer_noc1encoder_req_size;
      req_dest_l2_xpos = noc1buffer_noc1encoder_req_homeid[`PACKET_HOME_ID_X_MASK];
      req_dest_l2_ypos = noc1buffer_noc1encoder_req_homeid[`PACKET_HOME_ID_Y_MASK];
      req_dest_chipid = noc1buffer_noc1encoder_req_homeid[`PACKET_HOME_ID_CHIP_MASK];

   end


end

// translate req_ -> msg_
reg [`CHIE_REQ_FLIT_ADDR_WIDTH-1:0]    msg_address;
reg [`NOC_X_WIDTH-1:0]                 msg_dest_l2_xpos;
reg [`NOC_Y_WIDTH-1:0]                 msg_dest_l2_ypos;
reg [`NOC_X_WIDTH-1:0]                 msg_dest_l2_xpos_new;
reg [`NOC_Y_WIDTH-1:0]                 msg_dest_l2_ypos_new;
wire [`NOC_X_WIDTH-1:0]                msg_dest_l2_xpos_compat;
wire [`NOC_Y_WIDTH-1:0]                msg_dest_l2_ypos_compat;
reg [`NOC_CHIPID_WIDTH-1:0]            msg_dest_chipid;
reg [`NOC_FBITS_WIDTH-1:0]             msg_dest_fbits;
reg [`NOC_FBITS_WIDTH-1:0]             msg_src_fbits;
reg [`MSG_TYPE_WIDTH-1:0]              msg_type;
reg [`CHIE_REQ_FLIT_OPCODE_WIDTH-1:0]  msg_type_chi;
reg [`CHIE_REQ_FLIT_TXNID_WIDTH-1:0]   msg_mshrid;
reg [`MSG_MESI_BITS-1:0]               msg_mesi;
reg [`MSG_LAST_SUBLINE_WIDTH-1:0]      msg_last_subline;
reg [`MSG_OPTIONS_1]                   msg_options_1;
reg [`MSG_OPTIONS_2_]                  msg_options_2;
reg [`MSG_OPTIONS_3_]                  msg_options_3;
reg [`MSG_CACHE_TYPE_WIDTH-1:0]        msg_cache_type;
reg [`MSG_SUBLINE_VECTOR_WIDTH-1:0]    msg_subline_vector;
reg [`MSG_DATA_SIZE_WIDTH-1:0]         msg_data_size;
reg [`CHIE_REQ_FLIT_SIZE_WIDTH-1:0]    msg_data_size_chi;
reg [5:0] t1_interrupt_cpuid;

reg [`CHIE_REQ_FLIT_DODWT_WIDTH-1:0]   msg_noncacheable; // for CHI SnpAttr
reg [`CHIE_REQ_FLIT_LIKELYSHARED_WIDTH-1:0] msg_likelyshared;

reg [`CHIE_REQ_FLIT_QOS_WIDTH-1:0]           msg_qos;
reg [`CHIE_REQ_FLIT_RETURNNID_WIDTH-1:0]     msg_returnid;
reg [`CHIE_REQ_FLIT_RETURNTXNID_WIDTH-1:0]   msg_returntxid;
reg [`CHIE_REQ_FLIT_NS_WIDTH-1:0]            msg_ns;
reg [`CHIE_REQ_FLIT_ALLOWRETRY_WIDTH-1:0]    msg_allowretry;
reg [`CHIE_REQ_FLIT_ORDER_WIDTH-1:0]         msg_order;
reg [`CHIE_REQ_FLIT_PCRDTYPE_WIDTH-1:0]      msg_pcrdtype;
reg [`CHIE_REQ_FLIT_MEMATTR_WIDTH-1:0]       msg_memattr;
reg [`CHIE_REQ_FLIT_TRACETAG_WIDTH-1:0]      msg_tracetag;
reg [`CHIE_REQ_FLIT_EXCL_WIDTH-1:0]          msg_exclusive;
reg [`CHIE_REQ_FLIT_ENDIAN_WIDTH-1:0]        msg_endian;
reg [`CHIE_REQ_FLIT_LPID_WIDTH-1:0]          msg_lpid;
reg [`CHIE_REQ_FLIT_EXPCOMPACK_WIDTH-1:0]    msg_expcompack;
reg                                          msg_icache_req;
reg amo_req;



always @ *
begin
   msg_type = 0;
   msg_mesi = 0;
   msg_last_subline = 0;
   msg_cache_type = 0;
   msg_subline_vector = 0; // always 0 for requests
   control_raw_data_flit1 = 0;
   t1_interrupt_cpuid = 0;
   msg_address = req_address;
   msg_mshrid = req_mshrid;
   msg_data_size = req_size;

   // source are static
   msg_src_fbits = `NOC_FBITS_L1;
   // Set fbits for on-chip device access according to the fbits field in addr
   // For interrupt controller access, hard code the fbits. This is DECADES_CHIP specific. 
   // otherwise set fbits to 0 (target L2)
   msg_dest_fbits = (noc1buffer_noc1encoder_req_address[39:33] == 7'b1110000) ?
                   noc1buffer_noc1encoder_req_address[`ON_CHIP_DEV_FBITS] : `NOC_FBITS_L2;

   // default value for a message, will be overwritten by interrupt reqs
   msg_dest_l2_xpos = req_dest_l2_xpos;
   msg_dest_l2_ypos = req_dest_l2_ypos;
   msg_dest_chipid = req_dest_chipid;

   // trin: removing latches
   msg_dest_l2_xpos_new = 0;
   msg_dest_l2_ypos_new = 0;

   msg_noncacheable = 0;
   msg_likelyshared = 0;
   msg_qos = 0;
   msg_returnid = 0;
   msg_returntxid = 0;
   msg_ns = 0;
   msg_allowretry = 0;
   msg_order = 0;
   msg_pcrdtype = 0;
   msg_memattr = 0;
   msg_tracetag = 0;
   msg_exclusive = 0;
   msg_endian = 0;
   msg_lpid = 0;
   msg_expcompack = 0;

   msg_icache_req = 0;
   msg_type_chi = 'b0;
   amo_req = 'b0;

   case (req_type)
      `L15_NOC1_REQTYPE_WRITEBACK_GUARD:
      begin
         msg_type = `MSG_TYPE_WBGUARD_REQ;
      end
      `L15_NOC1_REQTYPE_LD_REQUEST:
      begin
         // this needs to be splitted into
         //  normal ld, ld nc, and prefetch ld
         if (req_prefetch) begin
         end
         else if (req_nc) begin
            // CHI ReadNoSnp
         end
         else begin
            msg_type_chi = `CHIE_READCLEAN; //`CHIE_READSHARED;    // ReadShared
            msg_noncacheable = req_nc;    // to SnpAttr ('non Snoopable')
            msg_likelyshared = 1'b1;
            msg_qos = `RNF_QOS_CLASS_MED;      // 
            msg_allowretry = 1;
            msg_memattr[3] = 1; // Allocate
            msg_memattr[2] = 1; //~req_nc; // Cacheable 
            msg_memattr[1] = 0;  // Device: 0=normal(normal mem access), 1=Device
            msg_memattr[0] = 1;  // Early Write Acknowledge (EWA)
            msg_endian = 0;
            msg_lpid = 0;
            msg_expcompack = 1;

         end

      end
      `L15_NOC1_REQTYPE_IFILL_REQUEST:
      begin
         // can be either normal or nc
         if (req_nc) begin
            msg_type_chi = `CHIE_READNOSNP;    // ReadNoSnp
            msg_noncacheable = req_nc;    // to SnpAttr ('non Snoopable')
            msg_likelyshared = 1'b0;
            msg_qos = `RNF_QOS_CLASS_MED;      // 
            msg_allowretry = 1;
            msg_memattr[3] = 0; // Allocate
            msg_memattr[2] = ~req_nc; // Cacheable 
            // according to OP address spaces, dram_base:'h80000000, bootrom and debug base:'hFFF1000000   1111111111110000111111111111111111111111
            //msg_memattr[1] = ((BOOT_REGION_BASE+BOOT_REGION_SIZE > msg_address &&  BOOT_REGION_BASE <= msg_address) || 
            //                  (IO_REGION_BASE+IO_REGION_SIZE > msg_address &&  IO_REGION_BASE <= msg_address)) ? 'b1 : 'b0;  // Device: 0=normal(normal mem access), 1=Device
            //// SET TO ZERO FOR NOW as slicc-HNF doesn't support ordered requests/read_receipts (which is specified to be supported with in CHI)
            msg_memattr[1] = 'b0;
            
            msg_memattr[0] = 0;  // Early Write Acknowledge (EWA)
            msg_order = (msg_memattr[1]) ? 2'b11 : 2'b00; // Request Order
         end
         else begin
            msg_type_chi = `CHIE_READCLEAN; //`CHIE_READSHARED;    // ReadShared
            msg_noncacheable = req_nc;    // to SnpAttr ('non Snoopable')
            msg_likelyshared = 1'b1;
            msg_qos = `RNF_QOS_CLASS_MED;      // 
            msg_allowretry = 1;
            msg_memattr[3] = 0; // Allocate
            msg_memattr[2] = ~req_nc; // Cacheable 
            msg_memattr[1] = 0;  // Device: 0=normal(normal mem access), 1=Device
            msg_memattr[0] = 1;  // Early Write Acknowledge (EWA)
            msg_order = 2'b00; // Request Order


         end

         // Mark the request made by instruction cache to the request-register 
         msg_icache_req = 'b1;
         msg_endian = 0;
         msg_lpid = 0;
         msg_expcompack = 1;

      end
      `L15_NOC1_REQTYPE_WRITETHROUGH_REQUEST:
      begin
         msg_type_chi = `CHIE_WRITENOSNPPTL;
         msg_noncacheable = 1;    // = ~SnpAttr: must be always zero
         msg_likelyshared = 1'b0;
         msg_qos = `RNF_QOS_CLASS_LOW;
         msg_allowretry = 1;
         // MemAttr always 0011
         msg_memattr[3] = 0;        // Allocate?
         msg_memattr[2] = ~req_nc;  // Cacheable? NOTE: later with address mapping, might be to IO or memory(cacheable/noncach)
         //msg_memattr[1] = !(CACHED_REGION_BASE+CACHED_REGION_SIZE > msg_address && CACHED_REGION_BASE <= msg_address);        // Device?: 0=normal(normal mem access), 1=Device   NOTE: later with address mapping, might be to IO
         //// SET TO ZERO FOR NOW as slicc-HNF doesn't support ordered requests/read_receipts (which is specified to be supported with in CHI)
         msg_memattr[1] = 'b0;
         
         
         msg_memattr[0] = 1;        // Early Write Acknowledge (EWA), ACK from HNF or endpoint?
         msg_exclusive = 0;         // with atomics this is SnoopMe-field, 
                                    // indicates if the HNF must send a Snoop to the Requester in case the requested address is in the cache of the RNF
                                    // Asserted to be sure, l15 doesnt propagate info about that
         msg_order = (msg_memattr[1]) ? 2'b11 : 2'b00; // No ordering required for reqs coming from this RNF     //2'b11; // Order=Endpoint Order (transaction order is preserved to the same endpoint address range)
         msg_endian = 0;
         msg_lpid = 0;              // Logical Processor Identifier (if RNF would have more than one processor initiating requests)
         msg_expcompack = 0;        // RN-F will not send CompAck with WriteNoSnp

      end
      `L15_NOC1_REQTYPE_ST_UPGRADE_REQUEST, `L15_NOC1_REQTYPE_ST_FILL_REQUEST:
      begin

         // if (req_type == `L15_NOC1_REQTYPE_ST_UPGRADE_REQUEST) begin
         //    msg_type_chi = `CHIE_CLEANUNIQUE;
         // end else begin
            msg_type_chi = `CHIE_READUNIQUE;    // ReadUnique
         // end

         msg_noncacheable = req_nc;    // to SnpAttr
         msg_likelyshared = 1'b0;
         msg_qos = `RNF_QOS_CLASS_HIGH;//1;      // 
         msg_allowretry = 1;
         msg_memattr[3] = 1; // Allocate
         msg_memattr[2] = 1; //~req_nc; // Cacheable 
         msg_memattr[1] = 0;  // Device: 0=normal(normal mem access), 1=Device
         msg_memattr[0] = 1;  // Early Write Acknowledge (EWA)
         msg_endian = 0;
         msg_lpid = 0;
         msg_expcompack = 1;



      end
      // Unenabled in RNF
      // `L15_NOC1_REQTYPE_CAS_REQUEST:
      // begin
      //    msg_type = `MSG_TYPE_CAS_REQ;
      //    msg_cache_type = `MSG_CACHE_TYPE_DATA;
      //    msg_length = 4; // 2 extra headers + 1 compare data + 1 swap data
      // end
      `L15_NOC1_REQTYPE_SWAP_REQUEST:
      begin
         msg_type_chi = `CHIE_ATOMICSWAP;
         msg_noncacheable = 0;    // to SnpAttr
         msg_likelyshared = 1'b0;
         msg_qos = `RNF_QOS_CLASS_HIGH;
         msg_allowretry = 1;
         msg_memattr[3] = 1; // Allocate
         msg_memattr[2] = 1; //~req_nc; // Cacheable 
         msg_memattr[1] = 0;  // Device: 0=normal(normal mem access), 1=Device
         msg_memattr[0] = 1;  // Early Write Acknowledge (EWA)
         msg_exclusive = 1;   // with atomics this is SnoopMe-field, 
                              // indicates if the HNF must send a Snoop to the Requester in case the requested address is in the cache of the RNF
                              // Asserted to be sure, l15 doesnt propagate info about that
         msg_order = 2'b10; // Request Order
         msg_endian = 0;
         msg_lpid = 0;
         msg_expcompack = 0;  // No CompAcks with atomics
         amo_req = 'b1;

      end
      // Unenabled in RNF
      // `L15_NOC1_REQTYPE_INTERRUPT_FWD:
      // begin
      //    msg_type = `MSG_TYPE_INTERRUPT_FWD;
      //    msg_length = 1; // just 1 data
      //    control_raw_data_flit1 = 1'b1;
      //    t1_interrupt_cpuid = req_data0[14:9];
      //    msg_dest_l2_xpos_new = req_data0[`NOC_X_WIDTH+17:18];
      //    msg_dest_l2_ypos_new = req_data0[`NOC_Y_WIDTH+`NOC_X_WIDTH+17:`NOC_X_WIDTH+18];
      //    msg_dest_l2_xpos = req_data0[63] ? msg_dest_l2_xpos_new : msg_dest_l2_xpos_compat; 
      //    msg_dest_l2_ypos = req_data0[63] ? msg_dest_l2_ypos_new : msg_dest_l2_ypos_compat; 
      //    msg_dest_chipid  = req_data0[63] ? req_data0[`NOC_CHIPID_WIDTH+`NOC_Y_WIDTH+`NOC_X_WIDTH+17:`NOC_Y_WIDTH+`NOC_X_WIDTH+18] : `NOC_CHIPID_WIDTH'b0;
      // end
      `L15_NOC1_REQTYPE_LR_REQUEST:
      begin

         msg_type_chi = `CHIE_READUNIQUE;    // ReadUnique
         msg_noncacheable = 0;    // to SnpAttr (=~noncacheable)
         msg_likelyshared = 1'b0;
         msg_qos = `RNF_QOS_CLASS_HIGH;//1;      // 
         msg_allowretry = 1;
         msg_memattr[3] = 1; // Allocate
         msg_memattr[2] = 1; //~req_nc; // Cacheable 
         msg_memattr[1] = 0;  // Device: 0=normal(normal mem access), 1=Device
         msg_memattr[0] = 1;  // Early Write Acknowledge (EWA)
         msg_endian = 0;
         msg_lpid = 0;
         msg_expcompack = 1;
         amo_req = 'b1;

      end
      `L15_NOC1_REQTYPE_AMO_ADD_REQUEST:
      begin
         msg_type_chi = `CHIE_ATOMICLOAD_ADD;
         msg_noncacheable = 0;    // to SnpAttr
         msg_likelyshared = 1'b0;
         msg_qos = `RNF_QOS_CLASS_HIGH;
         msg_allowretry = 1;
         msg_memattr[3] = 1; // Allocate
         msg_memattr[2] = 1; //~req_nc; // Cacheable 
         msg_memattr[1] = 0;  // Device: 0=normal(normal mem access), 1=Device
         msg_memattr[0] = 1;  // Early Write Acknowledge (EWA)
         msg_exclusive = 1;   // with atomics this is SnoopMe-field, 
                              // indicates if the HNF must send a Snoop to the Requester in case the requested address is in the cache of the RNF
                              // Asserted to be sure, l15 doesnt propagate info about that
         msg_order = 2'b10; // Request Order
         msg_endian = 0;
         msg_lpid = 0;
         msg_expcompack = 0;  // No CompAcks with atomics
         amo_req = 'b1;


      end
      `L15_NOC1_REQTYPE_AMO_AND_REQUEST:
      begin
         msg_type_chi = `CHIE_ATOMICLOAD_CLR;
         msg_noncacheable = 0;    // to SnpAttr
         msg_likelyshared = 1'b0;
         msg_qos = `RNF_QOS_CLASS_HIGH;
         msg_allowretry = 1;
         msg_memattr[3] = 1; // Allocate
         msg_memattr[2] = 1; //~req_nc; // Cacheable 
         msg_memattr[1] = 0;  // Device: 0=normal(normal mem access), 1=Device
         msg_memattr[0] = 1;  // Early Write Acknowledge (EWA)
         msg_exclusive = 1;   // with atomics this is SnoopMe-field, 
                              // indicates if the HNF must send a Snoop to the Requester in case the requested address is in the cache of the RNF
                              // Asserted to be sure, l15 doesnt propagate info about that
         msg_order = 2'b10; // Request Order
         msg_endian = 0;
         msg_lpid = 0;
         msg_expcompack = 0;  // No CompAcks with atomics
         amo_req = 'b1;

      end
      `L15_NOC1_REQTYPE_AMO_OR_REQUEST:
      begin
         msg_type_chi = `CHIE_ATOMICLOAD_SET;
         msg_noncacheable = 0;    // to SnpAttr
         msg_likelyshared = 1'b0;
         msg_qos = `RNF_QOS_CLASS_HIGH;
         msg_allowretry = 1;
         msg_memattr[3] = 1; // Allocate
         msg_memattr[2] = 1; //~req_nc; // Cacheable 
         msg_memattr[1] = 0;  // Device: 0=normal(normal mem access), 1=Device
         msg_memattr[0] = 1;  // Early Write Acknowledge (EWA)
         msg_exclusive = 1;   // with atomics this is SnoopMe-field, 
                              // indicates if the HNF must send a Snoop to the Requester in case the requested address is in the cache of the RNF
                              // Asserted to be sure, l15 doesnt propagate info about that
         msg_order = 2'b10; // Request Order
         msg_endian = 0;
         msg_lpid = 0;
         msg_expcompack = 0;  // No CompAcks with atomics
         amo_req = 'b1;

      end
      `L15_NOC1_REQTYPE_AMO_XOR_REQUEST:
      begin
         msg_type_chi = `CHIE_ATOMICLOAD_EOR;
         msg_noncacheable = 0;    // to SnpAttr
         msg_likelyshared = 1'b0;
         msg_qos = `RNF_QOS_CLASS_HIGH;
         msg_allowretry = 1;
         msg_memattr[3] = 1; // Allocate
         msg_memattr[2] = 1; //~req_nc; // Cacheable 
         msg_memattr[1] = 0;  // Device: 0=normal(normal mem access), 1=Device
         msg_memattr[0] = 1;  // Early Write Acknowledge (EWA)
         msg_exclusive = 1;   // with atomics this is SnoopMe-field, 
                              // indicates if the HNF must send a Snoop to the Requester in case the requested address is in the cache of the RNF
                              // Asserted to be sure, l15 doesnt propagate info about that
         msg_order = 2'b10; // Request Order
         msg_endian = 0;
         msg_lpid = 0;
         msg_expcompack = 0;  // No CompAcks with atomics
         amo_req = 'b1;

      end
      `L15_NOC1_REQTYPE_AMO_MAX_REQUEST:
      begin
         msg_type_chi = `CHIE_ATOMICLOAD_SMAX;
         msg_noncacheable = 0;    // to SnpAttr
         msg_likelyshared = 1'b0;
         msg_qos = `RNF_QOS_CLASS_HIGH;
         msg_allowretry = 1;
         msg_memattr[3] = 1; // Allocate
         msg_memattr[2] = 1; //~req_nc; // Cacheable 
         msg_memattr[1] = 0;  // Device: 0=normal(normal mem access), 1=Device
         msg_memattr[0] = 1;  // Early Write Acknowledge (EWA)
         msg_exclusive = 1;   // with atomics this is SnoopMe-field, 
                              // indicates if the HNF must send a Snoop to the Requester in case the requested address is in the cache of the RNF
                              // Asserted to be sure, l15 doesnt propagate info about that
         msg_order = 2'b10; // Request Order
         msg_endian = 0;
         msg_lpid = 0;
         msg_expcompack = 0;  // No CompAcks with atomics
         amo_req = 'b1;

      end
      `L15_NOC1_REQTYPE_AMO_MAXU_REQUEST:
      begin
         msg_type_chi = `CHIE_ATOMICLOAD_UMAX;
         msg_noncacheable = 0;    // to SnpAttr
         msg_likelyshared = 1'b0;
         msg_qos = `RNF_QOS_CLASS_HIGH;
         msg_allowretry = 1;
         msg_memattr[3] = 1; // Allocate
         msg_memattr[2] = 1; //~req_nc; // Cacheable 
         msg_memattr[1] = 0;  // Device: 0=normal(normal mem access), 1=Device
         msg_memattr[0] = 1;  // Early Write Acknowledge (EWA)
         msg_exclusive = 1;   // with atomics this is SnoopMe-field, 
                              // indicates if the HNF must send a Snoop to the Requester in case the requested address is in the cache of the RNF
                              // Asserted to be sure, l15 doesnt propagate info about that
         msg_order = 2'b10; // Request Order
         msg_endian = 0;
         msg_lpid = 0;
         msg_expcompack = 0;
         amo_req = 'b1;

      end
      `L15_NOC1_REQTYPE_AMO_MIN_REQUEST:
      begin
         msg_type_chi = `CHIE_ATOMICLOAD_SMIN;
         msg_noncacheable = 0;    // to SnpAttr
         msg_likelyshared = 1'b0;
         msg_qos = `RNF_QOS_CLASS_HIGH;
         msg_allowretry = 1;
         msg_memattr[3] = 1; // Allocate
         msg_memattr[2] = 1; //~req_nc; // Cacheable 
         msg_memattr[1] = 0;  // Device: 0=normal(normal mem access), 1=Device
         msg_memattr[0] = 1;  // Early Write Acknowledge (EWA)
         msg_exclusive = 1;   // with atomics this is SnoopMe-field, 
                              // indicates if the HNF must send a Snoop to the Requester in case the requested address is in the cache of the RNF
                              // Asserted to be sure, l15 doesnt propagate info about that
         msg_order = 2'b10; // Request Order
         msg_endian = 0;
         msg_lpid = 0;
         msg_expcompack = 0;  // No CompAcks with atomics
         amo_req = 'b1;

      end
      `L15_NOC1_REQTYPE_AMO_MINU_REQUEST:
      begin
         msg_type_chi = `CHIE_ATOMICLOAD_UMIN;
         msg_noncacheable = 0;    // to SnpAttr
         msg_likelyshared = 1'b0;
         msg_qos = `RNF_QOS_CLASS_HIGH;
         msg_allowretry = 1;
         msg_memattr[3] = 1; // Allocate
         msg_memattr[2] = 1; //~req_nc; // Cacheable 
         msg_memattr[1] = 0;  // Device: 0=normal(normal mem access), 1=Device
         msg_memattr[0] = 1;  // Early Write Acknowledge (EWA)
         msg_exclusive = 1;   // with atomics this is SnoopMe-field, 
                              // indicates if the HNF must send a Snoop to the Requester in case the requested address is in the cache of the RNF
                              // Asserted to be sure, l15 doesnt propagate info about that
         msg_order = 2'b10; // Request Order
         msg_endian = 0;
         msg_lpid = 0;
         msg_expcompack = 0;  // No CompAcks with atomics
         amo_req = 'b1;

      end
   endcase

   ordered_req = (msg_order != 2'b00);

end

reg [127:0] bitmask;

// OP data size translation to CHI data size
always @ *
begin

   msg_data_size_chi = 'b0;
   bitmask = 'b0;
   
   case (msg_type_chi) 
      `CHIE_ATOMICLOAD_ADD, `CHIE_ATOMICLOAD_CLR, `CHIE_ATOMICLOAD_EOR, `CHIE_ATOMICLOAD_SET, 
      `CHIE_ATOMICLOAD_SMAX, `CHIE_ATOMICLOAD_SMIN, `CHIE_ATOMICLOAD_UMAX, `CHIE_ATOMICLOAD_UMIN, 
      `CHIE_ATOMICSWAP, `CHIE_WRITENOSNPPTL:
      begin 
         case (msg_data_size)
            `MSG_DATA_SIZE_0B:
            begin
               msg_data_size_chi = 3'h7; // reserved
            end
            `MSG_DATA_SIZE_1B:
            begin
               msg_data_size_chi = `CHIE_SIZE1B;
               bitmask = {{64{1'b0}}, {8{1'b1}}, {56{1'b0}}};
            end
            `MSG_DATA_SIZE_2B:
            begin
               msg_data_size_chi = `CHIE_SIZE2B;
               bitmask = {{64{1'b0}}, {16{1'b1}}, {48{1'b0}}};
            end
            `MSG_DATA_SIZE_4B:
            begin
               msg_data_size_chi = `CHIE_SIZE4B;
               bitmask = {{64{1'b0}}, {32{1'b1}}, {32{1'b0}}};
            end
            `MSG_DATA_SIZE_8B:
            begin
               msg_data_size_chi = `CHIE_SIZE8B;
               bitmask = {{64{1'b0}}, {64{1'b1}}};
            end
            `MSG_DATA_SIZE_16B:
            begin
               msg_data_size_chi = `CHIE_SIZE16B;
               bitmask = {128{1'b1}};
            end
               `MSG_DATA_SIZE_32B:
            begin
               msg_data_size_chi = `CHIE_SIZE32B;
               bitmask = {128{1'b1}};
            end
               `MSG_DATA_SIZE_64B:
            begin
               msg_data_size_chi = `CHIE_SIZE64B;
               bitmask = {128{1'b1}};
            end
         endcase
      end
      // Cacheable line reads always request a full 64B cacheline; the
      // responder uses address[5:4] from this TXREQ as the CriticalChunkID.
      `CHIE_READSHARED, `CHIE_READUNIQUE, `CHIE_READCLEAN:
      begin
         msg_data_size_chi = `CHIE_SIZE64B;
      end
      `CHIE_READNOSNP:
      begin
         msg_data_size_chi = `CHIE_SIZE8B;
      end
   endcase
end   


   // CHI TXREQ 
   assign encoder_txreq_addr_sx1           = msg_address;
   assign encoder_txreq_tgtid              = HNF_NID_PARAM;
   assign encoder_txreq_srcid              = RNF_NID;
   assign encoder_txreq_opcode_sx1         = msg_type_chi;
   assign encoder_txreq_txnid_sx1_q        = msg_mshrid;
   assign encoder_txreq_size_sx1           = msg_data_size_chi;
   assign encoder_txreq_snpattr            = ~msg_noncacheable;
   assign encoder_txreq_likelyshared       = msg_likelyshared;
   assign encoder_txreq_qos_sx1            = msg_qos;
   assign encoder_txreq_returnnid_sx1      = msg_returnid;
   assign encoder_txreq_returntxnid_sx1    = msg_returntxid;
   assign encoder_txreq_ns_sx1             = msg_ns;
   assign encoder_txreq_allowretry_sx1     = msg_allowretry;
   assign encoder_txreq_order_sx1          = msg_order;
   assign encoder_txreq_pcrdtype_sx1       = msg_pcrdtype;
   assign encoder_txreq_memattr_sx1        = msg_memattr;
   assign encoder_txreq_tracetag_sx1       = msg_tracetag;
   assign encoder_txreq_exclusive          = msg_exclusive; // Exclusvie/SnoopMe(amo)
   assign encoder_txreq_reg_icache         = msg_icache_req; // For the request register
   assign encoder_txreq_endian             = msg_endian;
   assign encoder_txreq_lpid               = msg_lpid;
   assign encoder_txreq_expcompack         = msg_expcompack;
   assign atomic_data                      = (amo_req) ? ({req_data1, req_data0} & bitmask) : {req_data1, req_data0};


always @ *
begin
   // ack logic to L1.5
   noc1encoder_noc1buffer_req_ack = 0;
   if (noc1buffer_noc1encoder_req_val && channel_ready && (req_source == `L15_NOC1ENCODER_SOURCE_L15))
      noc1encoder_noc1buffer_req_ack = 1'b1;
   else
      noc1encoder_noc1buffer_req_ack = 1'b0;

end

endmodule
