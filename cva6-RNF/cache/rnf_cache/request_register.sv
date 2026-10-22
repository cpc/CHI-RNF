/*
 * Copyright (c) 2026 Tampere University
 * Licensed under the Solderpad Hardware License v 2.1, see LICENSE for details.
 * SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
 */

//==================================================================================================
//  Filename   : request_register
//  Author     : Teemu Rinne, Tampere University
//
//  Description     : Request register for outbound CHI-requests of AMBA CHI based RN-F coherent cache. 
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

module request_register `RNF_PARAM (
    input wire clk,
    input wire rst_n,

    input wire get_request,
    input wire update_entry,
    input wire evict_entry,
    input wire check_snp_match,
    input wire invalidate_wb_data,
    input wire [`CHIE_SNP_FLIT_ADDR_WIDTH-1:0]             snp_addr,
    input wire [`CHIE_REQ_FLIT_TXNID_WIDTH-1:0]            search_txnid,

    // TXREQ flit in
    input wire                                              txreq_valid,
    input wire [`CHIE_REQ_FLIT_TXNID_WIDTH-1:0]             txreq_txnid,     
    input wire [`CHIE_REQ_FLIT_OPCODE_WIDTH-1:0]            txreq_opcode,      
    input wire [`CHIE_REQ_FLIT_SIZE_WIDTH-1:0]              txreq_size,        
    input wire [`CHIE_REQ_FLIT_ADDR_WIDTH-1:0]              txreq_addr,        
    input wire [`CHIE_REQ_FLIT_DODWT_WIDTH-1:0]             txreq_snpattr,
    input wire [`CHIE_REQ_FLIT_TGTID_WIDTH-1:0]             txreq_tgtid,           
    input wire [`CHIE_REQ_FLIT_SRCID_WIDTH-1:0]             txreq_srcid,           
    input wire [`CHIE_REQ_FLIT_LIKELYSHARED_WIDTH-1:0]      txreq_likelyshared,
    input wire [`CHIE_REQ_FLIT_QOS_WIDTH-1:0]               txreq_qos,
    input wire [`CHIE_REQ_FLIT_RETURNNID_WIDTH-1:0]         txreq_returnnid,
    input wire [`CHIE_REQ_FLIT_RETURNTXNID_WIDTH-1:0]       txreq_returntxnid,
    input wire [`CHIE_REQ_FLIT_NS_WIDTH-1:0]                txreq_ns,
    input wire [`CHIE_REQ_FLIT_ALLOWRETRY_WIDTH-1:0]        txreq_allowretry,
    input wire [`CHIE_REQ_FLIT_ORDER_WIDTH-1:0]             txreq_order,
    input wire [`CHIE_REQ_FLIT_PCRDTYPE_WIDTH-1:0]          txreq_pcrdtype,
    input wire [`CHIE_REQ_FLIT_MEMATTR_WIDTH-1:0]           txreq_memattr,
    input wire [`CHIE_REQ_FLIT_TRACETAG_WIDTH-1:0]          txreq_tracetag,
    input wire [`CHIE_REQ_FLIT_EXCL_WIDTH-1:0]              txreq_exclusive,
    input wire [`CHIE_REQ_FLIT_ENDIAN_WIDTH-1:0]            txreq_endian,
    input wire [`CHIE_REQ_FLIT_LPID_WIDTH-1:0]              txreq_lpid,
    input wire [`CHIE_REQ_FLIT_EXPCOMPACK_WIDTH-1:0]        txreq_expcompack,
    input wire [`CHI_CACHE_LINE_WIDTH-1:0]                  txreq_amo_data,
    input wire [`CHI_CACHE_BE_WIDTH-1:0]                    txreq_amo_be,
    input wire                                              txreq_icache,
    input wire                                              txreq_respsepdata,
    input wire                                              txreq_datasepresp,

    // TXREQ flit out
    output reg                                              req_valid,
    output reg [`CHIE_REQ_FLIT_TXNID_WIDTH-1:0]             req_txnid,     
    output reg [`CHIE_REQ_FLIT_OPCODE_WIDTH-1:0]            req_opcode,      
    output reg [`CHIE_REQ_FLIT_SIZE_WIDTH-1:0]              req_size,        
    output reg [`CHIE_REQ_FLIT_ADDR_WIDTH-1:0]              req_addr,        
    output reg [`CHIE_REQ_FLIT_DODWT_WIDTH-1:0]             req_snpattr,
    output reg [`CHIE_REQ_FLIT_TGTID_WIDTH-1:0]             req_tgtid,           
    output reg [`CHIE_REQ_FLIT_SRCID_WIDTH-1:0]             req_srcid,           
    output reg [`CHIE_REQ_FLIT_LIKELYSHARED_WIDTH-1:0]      req_likelyshared,
    output reg [`CHIE_REQ_FLIT_QOS_WIDTH-1:0]               req_qos,
    output reg [`CHIE_REQ_FLIT_RETURNNID_WIDTH-1:0]         req_returnnid,
    output reg [`CHIE_REQ_FLIT_RETURNTXNID_WIDTH-1:0]       req_returntxnid,
    output reg [`CHIE_REQ_FLIT_NS_WIDTH-1:0]                req_ns,
    output reg [`CHIE_REQ_FLIT_ALLOWRETRY_WIDTH-1:0]        req_allowretry,
    output reg [`CHIE_REQ_FLIT_ORDER_WIDTH-1:0]             req_order,
    output reg [`CHIE_REQ_FLIT_PCRDTYPE_WIDTH-1:0]          req_pcrdtype,
    output reg [`CHIE_REQ_FLIT_MEMATTR_WIDTH-1:0]           req_memattr,
    output reg [`CHIE_REQ_FLIT_TRACETAG_WIDTH-1:0]          req_tracetag,
    output reg [`CHIE_REQ_FLIT_EXCL_WIDTH-1:0]              req_exclusive,
    output reg [`CHIE_REQ_FLIT_ENDIAN_WIDTH-1:0]            req_endian,
    output reg [`CHIE_REQ_FLIT_LPID_WIDTH-1:0]              req_lpid,
    output reg [`CHIE_REQ_FLIT_EXPCOMPACK_WIDTH-1:0]        req_expcompack,
    output reg [`CHI_CACHE_LINE_WIDTH-1:0]                  req_data,
    output reg [`CHI_CACHE_BE_WIDTH-1:0]                    req_be,
    output reg                                              req_icache,
    output reg                                              req_respsepdata_received,
    output reg                                              req_datasepresp_received,
    
    output reg                                              snp_match_found,

    input wire                                               txreq_enc_won

);
// cache mshr: st+ld+ifill. st and ld can trigger writeback-request =>  registersize= 2xST_mshr_w + 1+1(LD_mshr) + 1(IFILL_mshr)
localparam registersize = `L15_NUM_THREADS*2+2+1;
localparam idxWidth = $clog2(registersize);
// txreq 
reg                                         txreq_valid_r[registersize-1:0];
reg [`CHIE_REQ_FLIT_QOS_WIDTH-1:0]          txreq_qos_r[registersize-1:0];
reg [`CHIE_REQ_FLIT_TXNID_WIDTH-1:0]        txreq_txnid_r[registersize-1:0];
reg [`CHIE_REQ_FLIT_RETURNNID_WIDTH-1:0]    txreq_returnnid_r[registersize-1:0];
reg [`CHIE_REQ_FLIT_RETURNTXNID_WIDTH-1:0]  txreq_returntxnid_r[registersize-1:0];
reg [`CHIE_REQ_FLIT_OPCODE_WIDTH-1:0]       txreq_opcode_r[registersize-1:0];
reg [`CHIE_REQ_FLIT_SIZE_WIDTH-1:0]         txreq_size_r[registersize-1:0];
reg [`CHIE_REQ_FLIT_ADDR_WIDTH-1:0]         txreq_addr_r[registersize-1:0];
reg [`CHIE_REQ_FLIT_DODWT_WIDTH-1:0]        txreq_snpattr_r[registersize-1:0];   // DoDWT
reg [`CHIE_REQ_FLIT_TGTID_WIDTH-1:0]        txreq_tgtid_r[registersize-1:0];
reg [`CHIE_REQ_FLIT_SRCID_WIDTH-1:0]        txreq_srcid_r[registersize-1:0];
reg [`CHIE_REQ_FLIT_LIKELYSHARED_WIDTH-1:0] txreq_likelyshared_r[registersize-1:0];
reg [`CHIE_REQ_FLIT_NS_WIDTH-1:0]           txreq_ns_r[registersize-1:0];
reg [`CHIE_REQ_FLIT_ALLOWRETRY_WIDTH-1:0]   txreq_allowretry_r[registersize-1:0];
reg [`CHIE_REQ_FLIT_ORDER_WIDTH-1:0]        txreq_order_r[registersize-1:0];
reg [`CHIE_REQ_FLIT_PCRDTYPE_WIDTH-1:0]     txreq_pcrdtype_r[registersize-1:0];
reg [`CHIE_REQ_FLIT_MEMATTR_WIDTH-1:0]      txreq_memattr_r[registersize-1:0];
reg [`CHIE_REQ_FLIT_TRACETAG_WIDTH-1:0]     txreq_tracetag_r[registersize-1:0];
reg [`CHIE_REQ_FLIT_EXCL_WIDTH-1:0]         txreq_exclusive_r[registersize-1:0];
reg [`CHIE_REQ_FLIT_ENDIAN_WIDTH-1:0]       txreq_endian_r[registersize-1:0];
reg [`CHIE_REQ_FLIT_LPID_WIDTH-1:0]         txreq_lpid_r[registersize-1:0];
reg [`CHIE_REQ_FLIT_EXPCOMPACK_WIDTH-1:0]   txreq_expcompack_r[registersize-1:0];
reg [`CHI_CACHE_LINE_WIDTH-1:0]             txreq_amo_data_r[registersize-1:0];
reg [`CHI_CACHE_BE_WIDTH-1:0]               txreq_amo_be_r[registersize-1:0];
reg                                         txreq_icache_r[registersize-1:0];
reg                                         txreq_respsepdata_received_r[registersize-1:0];
reg                                         txreq_datasepresp_received_r[registersize-1:0];

reg                                         allocated;
reg                                         evicted;
reg                                         req_found;
reg                                         match_found;
reg [idxWidth-1:0]                          evict_idx;
reg [idxWidth-1:0]                          req_idx;
reg [idxWidth-1:0]                          alloc_idx;
reg [idxWidth-1:0]                          old_entry_idx;
reg [idxWidth-1:0]                          match_idx;

// 
always @ (posedge clk)
begin
   if (~rst_n)
   begin
        for (int i=0; i<registersize; i=i+1) begin
            txreq_valid_r[i] <= 'b0;
            txreq_qos_r[i] <= 'b0;
            txreq_txnid_r[i] <= 'b0;
            txreq_returnnid_r[i] <= 'b0;
            txreq_returntxnid_r[i] <= 'b0;
            txreq_opcode_r[i] <= 'b0;
            txreq_size_r[i] <= 'b0;
            txreq_addr_r[i] <= 'b0;
            txreq_snpattr_r[i] <= 'b0;
            txreq_tgtid_r[i] <= 'b0;
            txreq_srcid_r[i] <= 'b0;
            txreq_likelyshared_r[i] <= 'b0;
            txreq_ns_r[i] <= 'b0;
            txreq_allowretry_r[i] <= 'b0;
            txreq_order_r[i] <= 'b0;
            txreq_pcrdtype_r[i] <= 'b0;
            txreq_memattr_r[i] <= 'b0;
            txreq_tracetag_r[i] <= 'b0;
            txreq_exclusive_r[i] <= 'b0;
            txreq_endian_r[i] <= 'b0;
            txreq_lpid_r[i] <= 'b0;
            txreq_expcompack_r[i] <= 'b0;
            txreq_amo_data_r[i] <= 'b0;
            txreq_amo_be_r[i] <= 'b0;
            txreq_icache_r[i] <= 'b0;
            txreq_respsepdata_received_r[i] <= 'b0;
            txreq_datasepresp_received_r[i] <= 'b0;
        end
        req_valid <= 'b0;
        req_qos <= 'b0;
        req_txnid <= 'b0;
        req_returnnid <= 'b0;
        req_returntxnid <= 'b0;
        req_opcode <= 'b0;
        req_size <= 'b0;
        req_addr <= 'b0;
        req_snpattr <= 'b0;
        req_tgtid <= 'b0;
        req_srcid <= 'b0;
        req_likelyshared <= 'b0;
        req_ns <= 'b0;
        req_allowretry <= 'b0;
        req_order <= 'b0;
        req_pcrdtype <= 'b0;
        req_memattr <= 'b0;
        req_tracetag <= 'b0;
        req_exclusive <= 'b0;
        req_endian <= 'b0;
        req_lpid <= 'b0;
        req_expcompack <= 'b0;    
        req_data <= 'b0;
        req_be <= 'b0;
        req_icache <= 'b0;
        req_respsepdata_received <= 'b0;
        req_datasepresp_received <= 'b0;
            

   end
   else
   begin


        if (evicted) begin
            txreq_valid_r[evict_idx] <= 'b0;
            txreq_qos_r[evict_idx] <= 'b0;
            txreq_txnid_r[evict_idx] <= 'b0;
            txreq_returnnid_r[evict_idx] <= 'b0;
            txreq_returntxnid_r[evict_idx] <= 'b0;
            txreq_opcode_r[evict_idx] <= 'b0;
            txreq_size_r[evict_idx] <= 'b0;
            txreq_addr_r[evict_idx] <= 'b0;
            txreq_snpattr_r[evict_idx] <= 'b0;
            txreq_tgtid_r[evict_idx] <= 'b0;
            txreq_srcid_r[evict_idx] <= 'b0;
            txreq_likelyshared_r[evict_idx] <= 'b0;
            txreq_ns_r[evict_idx] <= 'b0;
            txreq_allowretry_r[evict_idx] <= 'b0;
            txreq_order_r[evict_idx] <= 'b0;
            txreq_pcrdtype_r[evict_idx] <= 'b0;
            txreq_memattr_r[evict_idx] <= 'b0;
            txreq_tracetag_r[evict_idx] <= 'b0;
            txreq_exclusive_r[evict_idx] <= 'b0;
            txreq_endian_r[evict_idx] <= 'b0;
            txreq_lpid_r[evict_idx] <= 'b0;
            txreq_expcompack_r[evict_idx] <= 'b0;
            txreq_amo_data_r[evict_idx] <= 'b0;
            txreq_amo_be_r[evict_idx] <= 'b0;
            txreq_icache_r[evict_idx] <= 'b0;
            txreq_respsepdata_received_r[evict_idx] <= 'b0;
            txreq_datasepresp_received_r[evict_idx] <= 'b0;
        end 

        if (get_request && req_found) begin
            req_valid <= txreq_valid_r[req_idx];
            req_qos <= txreq_qos_r[req_idx];
            req_txnid <= txreq_txnid_r[req_idx];
            req_returnnid <= txreq_returnnid_r[req_idx];
            req_returntxnid <= txreq_returntxnid_r[req_idx];
            req_opcode <= txreq_opcode_r[req_idx];
            req_size <= txreq_size_r[req_idx];
            req_addr <= txreq_addr_r[req_idx];
            req_snpattr <= txreq_snpattr_r[req_idx];
            req_tgtid <= txreq_tgtid_r[req_idx];
            req_srcid <= txreq_srcid_r[req_idx];
            req_likelyshared <= txreq_likelyshared_r[req_idx];
            req_ns <= txreq_ns_r[req_idx];
            req_allowretry <= txreq_allowretry_r[req_idx];
            req_order <= txreq_order_r[req_idx];
            req_pcrdtype <= txreq_pcrdtype_r[req_idx];
            req_memattr <= txreq_memattr_r[req_idx];
            req_tracetag <= txreq_tracetag_r[req_idx];
            req_exclusive <= txreq_exclusive_r[req_idx];
            req_endian <= txreq_endian_r[req_idx];
            req_lpid <= txreq_lpid_r[req_idx];
            req_expcompack <= txreq_expcompack_r[req_idx];
            req_data <= txreq_amo_data_r[req_idx];
            req_be <= txreq_amo_be_r[req_idx];
            req_icache <= txreq_icache_r[req_idx];
            req_respsepdata_received <= txreq_respsepdata_received_r[req_idx];
            req_datasepresp_received <= txreq_datasepresp_received_r[req_idx];
        end else if (match_found) begin
            req_valid <= txreq_valid_r[match_idx];
            req_qos <= txreq_qos_r[match_idx];
            req_txnid <= txreq_txnid_r[match_idx];
            req_returnnid <= txreq_returnnid_r[match_idx];
            req_returntxnid <= txreq_returntxnid_r[match_idx];
            req_opcode <= txreq_opcode_r[match_idx];
            req_size <= txreq_size_r[match_idx];
            req_addr <= txreq_addr_r[match_idx];
            req_snpattr <= txreq_snpattr_r[match_idx];
            req_tgtid <= txreq_tgtid_r[match_idx];
            req_srcid <= txreq_srcid_r[match_idx];
            req_likelyshared <= txreq_likelyshared_r[match_idx];
            req_ns <= txreq_ns_r[match_idx];
            req_allowretry <= txreq_allowretry_r[match_idx];
            req_order <= txreq_order_r[match_idx];
            req_pcrdtype <= txreq_pcrdtype_r[match_idx];
            req_memattr <= txreq_memattr_r[match_idx];
            req_tracetag <= txreq_tracetag_r[match_idx];
            req_exclusive <= txreq_exclusive_r[match_idx];
            req_endian <= txreq_endian_r[match_idx];
            req_lpid <= txreq_lpid_r[match_idx];
            req_expcompack <= txreq_expcompack_r[match_idx];
            req_data <= txreq_amo_data_r[match_idx];
            req_be <= txreq_amo_be_r[match_idx];
            req_icache <= txreq_icache_r[match_idx];
            req_respsepdata_received <= txreq_respsepdata_received_r[match_idx];
            req_datasepresp_received <= txreq_datasepresp_received_r[match_idx];
        end else begin
            req_valid <= 'b0;
            req_qos <= 'b0;
            req_txnid <= 'b0;
            req_returnnid <= 'b0;
            req_returntxnid <= 'b0;
            req_opcode <= 'b0;
            req_size <= 'b0;
            req_addr <= 'b0;
            req_snpattr <= 'b0;
            req_tgtid <= 'b0;
            req_srcid <= 'b0;
            req_likelyshared <= 'b0;
            req_ns <= 'b0;
            req_allowretry <= 'b0;
            req_order <= 'b0;
            req_pcrdtype <= 'b0;
            req_memattr <= 'b0;
            req_tracetag <= 'b0;
            req_exclusive <= 'b0;
            req_endian <= 'b0;
            req_lpid <= 'b0;
            req_expcompack <= 'b0;
            req_data <= 'b0;
            req_be <= 'b0;
            req_icache <= 'b0;
            req_respsepdata_received <= 'b0;
            req_datasepresp_received <= 'b0;
        end
        
        if (allocated) begin
            txreq_valid_r[alloc_idx] <= txreq_valid;
            txreq_qos_r[alloc_idx] <= txreq_qos;
            txreq_txnid_r[alloc_idx] <= txreq_txnid;
            txreq_returnnid_r[alloc_idx] <= txreq_returnnid;
            txreq_returntxnid_r[alloc_idx] <= txreq_returntxnid;
            txreq_opcode_r[alloc_idx] <= txreq_opcode;
            txreq_size_r[alloc_idx] <= txreq_size;
            txreq_addr_r[alloc_idx] <= txreq_addr;
            txreq_snpattr_r[alloc_idx] <= txreq_snpattr;
            txreq_tgtid_r[alloc_idx] <= txreq_tgtid;
            txreq_srcid_r[alloc_idx] <= txreq_srcid;
            txreq_likelyshared_r[alloc_idx] <= txreq_likelyshared;
            txreq_ns_r[alloc_idx] <= txreq_ns;
            txreq_allowretry_r[alloc_idx] <= txreq_allowretry;
            txreq_order_r[alloc_idx] <= txreq_order;
            txreq_pcrdtype_r[alloc_idx] <= txreq_pcrdtype;
            txreq_memattr_r[alloc_idx] <= txreq_memattr;
            txreq_tracetag_r[alloc_idx] <= txreq_tracetag;
            txreq_exclusive_r[alloc_idx] <= txreq_exclusive;
            txreq_endian_r[alloc_idx] <= txreq_endian;
            txreq_lpid_r[alloc_idx] <= txreq_lpid;
            txreq_expcompack_r[alloc_idx] <= txreq_expcompack;
            txreq_amo_data_r[alloc_idx] <= txreq_amo_data;
            txreq_amo_be_r[alloc_idx] <= txreq_amo_be;
            txreq_icache_r[alloc_idx] <= txreq_icache;
            txreq_respsepdata_received_r[alloc_idx] <= 'b0;
            txreq_datasepresp_received_r[alloc_idx] <= 'b0;
        end else if (update_entry && req_found) begin
            txreq_qos_r[req_idx] <= txreq_qos;
            txreq_txnid_r[req_idx] <= txreq_txnid;
            txreq_returnnid_r[req_idx] <= txreq_returnnid;
            txreq_returntxnid_r[req_idx] <= txreq_returntxnid;
            txreq_opcode_r[req_idx] <= txreq_opcode;
            txreq_size_r[req_idx] <= txreq_size;
            txreq_addr_r[req_idx] <= txreq_addr;
            txreq_snpattr_r[req_idx] <= txreq_snpattr;
            txreq_tgtid_r[req_idx] <= txreq_tgtid;
            txreq_srcid_r[req_idx] <= txreq_srcid;
            txreq_likelyshared_r[req_idx] <= txreq_likelyshared;
            txreq_ns_r[req_idx] <= txreq_ns;
            txreq_allowretry_r[req_idx] <= txreq_allowretry;
            txreq_order_r[req_idx] <= txreq_order;
            txreq_pcrdtype_r[req_idx] <= txreq_pcrdtype;
            txreq_memattr_r[req_idx] <= txreq_memattr;
            txreq_tracetag_r[req_idx] <= txreq_tracetag;
            txreq_exclusive_r[req_idx] <= txreq_exclusive;
            txreq_endian_r[req_idx] <= txreq_endian;
            txreq_lpid_r[req_idx] <= txreq_lpid;
            txreq_expcompack_r[req_idx] <= txreq_expcompack;
            txreq_amo_data_r[req_idx] <= txreq_amo_data;
            txreq_amo_be_r[req_idx] <= txreq_amo_be;
            txreq_icache_r[req_idx] <= txreq_icache;
            txreq_respsepdata_received_r[req_idx] <= txreq_respsepdata;
            txreq_datasepresp_received_r[req_idx] <= txreq_datasepresp;
        end

        if (match_found && invalidate_wb_data) begin
            txreq_amo_be_r[match_idx] <= 'b0;
        end

   end
end



always @ (*)
begin

    allocated = 1'b0;
    alloc_idx = 'b0;

    // Allocate the coming request
    for ( int i = 0; i<registersize; i=i+1 ) begin
        if (txreq_valid) begin
            if (txreq_valid_r[i] == 1'b0 && allocated == 1'b0) begin
                alloc_idx = i[$clog2(registersize)-1:0];
                allocated = 1'b1; 
            end 
        end
    end
end

always @ (*) begin : find_evictentry
    
    evicted = 1'b0;
    evict_idx = 'b0;
    
    // Evict entry
    for ( int i = 0; i<registersize; i=i+1 ) begin
        if (evict_entry) begin
            if (txreq_valid_r[i] == 1'b1 && txreq_txnid_r[i] == search_txnid && evicted == 1'b0) begin
                evict_idx = i[$clog2(registersize)-1:0];
                evicted = 1'b1; 
            end 
        end  
    end
end

always @ (*) begin : find_req_entry
    
    req_found = 1'b0;
    req_idx = 'b0;
    
    // Evict entry
    for ( int i = 0; i<registersize; i=i+1 ) begin
        if (get_request || update_entry) begin
            if (txreq_valid_r[i] == 1'b1 && txreq_txnid_r[i] == search_txnid && req_found == 1'b0) begin
                req_idx = i[$clog2(registersize)-1:0];
                req_found = 1'b1; 
            end
        end
    end
end



always @ (*) begin : check_addr_match
    
    match_found = 1'b0;
    match_idx = 'b0;
    
    // Evict entry
    for ( int i = 0; i<registersize; i=i+1 ) begin
        if (check_snp_match) begin
            if (txreq_valid_r[i] == 1'b1 && txreq_opcode_r[i] == `CHIE_WRITEBACKFULL && 
                txreq_addr_r[i][`CHIE_REQ_FLIT_ADDR_WIDTH-1:6] == snp_addr[`CHIE_SNP_FLIT_ADDR_WIDTH-1:3] && match_found == 1'b0) begin
                match_idx = i[$clog2(registersize)-1:0];
                match_found = 1'b1; 
            end
        end
    end
end

assign snp_match_found = match_found;

endmodule