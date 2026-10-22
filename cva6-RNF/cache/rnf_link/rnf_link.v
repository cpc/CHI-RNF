// Original work:
/*
* Copyright (c) 2024 Beijing Institute of Open Source Chip
* OpenNoC is licensed under Mulan PSL v2.
* You can use this software according to the terms and conditions of the Mulan PSL v2.
* You may obtain a copy of Mulan PSL v2 at:
*          http://license.coscl.org.cn/MulanPSL2
* THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
* EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
* MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
* See the Mulan PSL v2 for more details.
*
* Author:
*    Jianxing Wang <wangjianxing@bosc.ac.cn>
*    Jianhong Zhang <zhangjianhong@bosc.ac.cn>
*/


// Modifications: 
/*
 * Copyright (c) 2026 Tampere University
 * Licensed under the Solderpad Hardware License v 2.1, see LICENSE for details.
 * SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
 */

//==================================================================================================
//  Filename        : rnf_link (original hnf_link)
//  Modified        : Teemu Rinne, Tampere University
//
//  Description     : Top-level of AMBA CHI based RN-F link layer interface 
//
//==================================================================================================


`include "chie_defines.v"
`include "rnf_defines.v"
`include "rnf_param.v"

module rnf_link `RNF_PARAM
    (
        // 95 inputs + clk + rst
        clk,
        rst,
        //
        rxrspflitv,
        rxrspflit,
        rxrspflitpend,
        rxdatflitv,
        rxdatflit,
        rxdatflitpend,
        rxdat_buf_ready,
        txreq_lcrdv,
        // from mshr
            // TXREQ
        mshr_txreq_bypass_valid_s1,
        mshr_txreq_bypass_qos_s1,
        mshr_txreq_bypass_txnid_s1,
        mshr_txreq_bypass_returnnid_s1,
        mshr_txreq_bypass_returntxnid_s1,
        mshr_txreq_bypass_opcode_s1,
        mshr_txreq_bypass_size_s1,
        mshr_txreq_bypass_addr_s1,
        mshr_txreq_bypass_ns_s1,
        mshr_txreq_bypass_allowretry_s1,
        mshr_txreq_bypass_order_s1,
        mshr_txreq_bypass_pcrdtype_s1,
        mshr_txreq_bypass_memattr_s1,
        mshr_txreq_bypass_dodwt_s1,
        mshr_txreq_bypass_tracetag_s1,
        mshr_txreq_bypass_tgtid,
        mshr_txreq_bypass_srcid,
        txreq_bypass_likelyshared,
        txreq_bypass_exclusive,
        txreq_bypass_endian,
        txreq_bypass_lpid,
        txreq_bypass_expcompack,
        mshr_txreq_valid_sx1_q,
        mshr_txreq_qos_sx1,
        mshr_txreq_txnid_sx1_q,
        mshr_txreq_returnnid_sx1,
        mshr_txreq_returntxnid_sx1,
        mshr_txreq_opcode_sx1,
        mshr_txreq_size_sx1,
        mshr_txreq_addr_sx1,
        mshr_txreq_ns_sx1,
        mshr_txreq_allowretry_sx1,
        mshr_txreq_order_sx1,
        mshr_txreq_pcrdtype_sx1,
        mshr_txreq_memattr_sx1,
        mshr_txreq_dodwt_sx1,
        mshr_txreq_tracetag_sx1,
        mshr_txreq_tgtid,
        mshr_txreq_srcid,
        encoder_txreq_likelyshared,
        encoder_txreq_exclusive,
        encoder_txreq_endian,
        encoder_txreq_lpid,
        encoder_txreq_expcompack,
            // TXRSP
        txrsp_lcrdv,
        mshr_txrsp_bypass_valid_s1,
        mshr_txrsp_bypass_qos_s1,
        mshr_txrsp_bypass_tgtid_s1,
        mshr_txrsp_bypass_txnid_s1,
        mshr_txrsp_bypass_opcode_s1,
        encoder_txrsp_bypass_resp,
        mshr_txrsp_bypass_resperr_s1,
        mshr_txrsp_bypass_dbid_s1,
        mshr_txrsp_bypass_tracetag_s1,
        // from mshr qos
        qos_txrsp_retryack_valid_s1,
        qos_txrsp_retryack_qos_s1,
        qos_txrsp_retryack_tgtid_s1,
        qos_txrsp_retryack_txnid_s1,
        qos_txrsp_retryack_pcrdtype_s1,
        qos_txrsp_retryack_tracetag_s1,
        qos_txrsp_pcrdgnt_valid_s2,
        qos_txrsp_pcrdgnt_qos_s2,
        qos_txrsp_pcrdgnt_tgtid_s2,
        qos_txrsp_pcrdgnt_pcrdtype_s2,
        // from mshr
        mshr_txrsp_valid_sx1_q,
        mshr_txrsp_qos_sx1,
        mshr_txrsp_tgtid_sx1,
        mshr_txrsp_txnid_sx1_q,
        mshr_txrsp_opcode_sx1,
        mshr_txrsp_resperr_sx1,
        mshr_txrsp_resp_sx1,
        mshr_txrsp_dbid_sx1,
        mshr_txrsp_tracetag_sx1,
            // TXDAT
        txdat_lcrdv,
        mshr_txdat_tgtid_sx2,
        mshr_txdat_txnid_sx2,
        mshr_txdat_opcode_sx2,
        mshr_txdat_resp_sx2,
        mshr_txdat_resperr_sx2,
        mshr_txdat_dbid_sx2,
        encoder_txdat_qos,
        encoder_txdat_srcid,
        encoder_txdat_homenid,
        encoder_txdat_fwdstate,
        encoder_txdat_ccid,

            // RXRSP
        rxrsp_lcrdv,
        li_mshr_rxrsp_valid_s0,
        li_mshr_rxrsp_srcid_s0,
        li_mshr_rxrsp_txnid_s0,
        li_mshr_rxrsp_opcode_s0,
        li_mshr_rxrsp_resp_s0,
        li_mshr_rxrsp_fwdstate_s0,
        li_mshr_rxrsp_dbid_s0,
        li_mshr_rxrsp_pcrdtype_s0,
        rxrsp_buf_ready,
            // RXDAT
        rxdat_lcrdv,
        li_mshr_rxdat_valid_s0,
        li_mshr_rxdat_txnid_s0,
        li_mshr_rxdat_opcode_s0,
        li_mshr_rxdat_resp_s0,
        li_mshr_rxdat_fwdstate_s0,
        li_mshr_rxdat_dataid_s0,
        li_decoder_rxdat_homenid,        
        li_decoder_rxdat_ccid,           
        li_decoder_rxdat_dbid, 
        // flits to noc
        txreqflitv,
        txreqflit,
        txreqflitpend,
        txrspflitv,
        txrspflit,
        txrspflitpend,
        // to mshr
        txrsp_mshr_retryack_won_s1,
        txrsp_mshr_pcrdgnt_won_s2,
        txrsp_mshr_won_sx1,
        txrsp_cache_crd_avail,
        txreq_mshr_won_sx1,
        txreq_mshr_bypass_won_s1,
        txrsp_mshr_bypass_won_s1,
        // to OP-encoder
        txreq_encoder_crd_avail_s1,
        //
        txdatflitv,
        txdatflit,
        txdatflitpend,
        // to mshr
        txdat_mshr_clr_dbf_busy_valid_sx3,
        txdat_mshr_clr_dbf_busy_idx_sx3,
        txdat_mshr_rd_idx_sx2,
        txdat_mshr_busy_sx,


        // DATA BUFFER signals
        // to data buffer
        li_dbf_rxdat_valid_s0,
        li_dbf_rxdat_txnid_s0,
        li_dbf_rxdat_opcode_s0,
        li_dbf_rxdat_dataid_s0,
        li_dbf_rxdat_be_s0,
        li_dbf_rxdat_data_s0,
        // from data buffer
        dbf_txdat_data_sx1,
        dbf_txdat_idx_sx1,
        dbf_txdat_be_sx1,
        dbf_txdat_pe_sx1,
        dbf_txdat_valid_sx1,

        // RXSNP
        rxsnpflitv,
        rxsnpflit,
        rxsnpflitpend,
        //outputs to decoder
        rxsnp_decoder_valid_sx,
        rxsnp_decoder_qos,
        rxsnp_decoder_srcid,
        rxsnp_decoder_txnid,
        rxsnp_decoder_fwdnid,
        rxsnp_decoder_fwdtxnid,
        rxsnp_decoder_opcode,
        rxsnp_decoder_addr,
        rxsnp_decoder_ns,
        rxsnp_decoder_donotgotosd,
        rxsnp_decoder_rettosrc,
        rxsnp_decoder_tracetag,
        rxsnp_buf_ready,

        rxsnp_lcrdv,

        // link active handshake
        TXLINKACTIVEREQ,
        TXLINKACTIVEACK,
        RXLINKACTIVEREQ,
        RXLINKACTIVEACK,
        TXACTIVE,
        RXACTIVE,
        tx_active_ready

    );
    //inputs
    input wire                                        clk;
    input wire                                        rst;

    input wire                                        rxrspflitv;
    input wire [`CHIE_RSP_FLIT_RANGE]                 rxrspflit;
    input wire                                        rxrspflitpend;
    input wire                                        rxdatflitv;
    input wire [`CHIE_DAT_FLIT_RANGE]                 rxdatflit;
    input wire                                        rxdatflitpend;
    // rxdat OP buffer to rxdat_parse, added for RNF
    input wire                                        rxdat_buf_ready;
    // TXREQ 
    input wire                                        txreq_lcrdv;
    input wire                                        mshr_txreq_bypass_valid_s1;
    input wire [`CHIE_REQ_FLIT_QOS_WIDTH-1:0]         mshr_txreq_bypass_qos_s1;
    input wire [`CHIE_REQ_FLIT_TXNID_WIDTH-1:0]       mshr_txreq_bypass_txnid_s1;
    input wire [`CHIE_REQ_FLIT_RETURNNID_WIDTH-1:0]   mshr_txreq_bypass_returnnid_s1;
    input wire [`CHIE_REQ_FLIT_RETURNTXNID_WIDTH-1:0] mshr_txreq_bypass_returntxnid_s1;
    input wire [`CHIE_REQ_FLIT_OPCODE_WIDTH-1:0]      mshr_txreq_bypass_opcode_s1;
    input wire [`CHIE_REQ_FLIT_SIZE_WIDTH-1:0]        mshr_txreq_bypass_size_s1;
    input wire [`CHIE_REQ_FLIT_ADDR_WIDTH-1:0]        mshr_txreq_bypass_addr_s1;
    input wire [`CHIE_REQ_FLIT_NS_WIDTH-1:0]          mshr_txreq_bypass_ns_s1;
    input wire [`CHIE_REQ_FLIT_ALLOWRETRY_WIDTH-1:0]  mshr_txreq_bypass_allowretry_s1;
    input wire [`CHIE_REQ_FLIT_ORDER_WIDTH-1:0]       mshr_txreq_bypass_order_s1;
    input wire [`CHIE_REQ_FLIT_PCRDTYPE_WIDTH-1:0]    mshr_txreq_bypass_pcrdtype_s1;
    input wire [`CHIE_REQ_FLIT_MEMATTR_WIDTH-1:0]     mshr_txreq_bypass_memattr_s1;
    input wire [`CHIE_REQ_FLIT_DODWT_WIDTH-1:0]       mshr_txreq_bypass_dodwt_s1;
    input wire [`CHIE_REQ_FLIT_TRACETAG_WIDTH-1:0]    mshr_txreq_bypass_tracetag_s1;
    input wire [`CHIE_REQ_FLIT_TGTID_RANGE]           mshr_txreq_bypass_tgtid; // added for RNF
    input wire [`CHIE_REQ_FLIT_SRCID_RANGE]           mshr_txreq_bypass_srcid; // added for RNF
    input wire [`CHIE_REQ_FLIT_LIKELYSHARED_WIDTH-1:0]  txreq_bypass_likelyshared; // for RNF
    input wire [`CHIE_REQ_FLIT_EXCL_WIDTH-1:0]          txreq_bypass_exclusive;
    input wire [`CHIE_REQ_FLIT_ENDIAN_WIDTH-1:0]      txreq_bypass_endian;
    input wire [`CHIE_REQ_FLIT_LPID_WIDTH-1:0]        txreq_bypass_lpid;
    input wire [`CHIE_REQ_FLIT_EXPCOMPACK_WIDTH-1:0]  txreq_bypass_expcompack;
    input wire                                        mshr_txreq_valid_sx1_q;
    input wire [`CHIE_REQ_FLIT_QOS_WIDTH-1:0]         mshr_txreq_qos_sx1;
    input wire [`CHIE_REQ_FLIT_TXNID_WIDTH-1:0]       mshr_txreq_txnid_sx1_q;
    input wire [`CHIE_REQ_FLIT_RETURNNID_WIDTH-1:0]   mshr_txreq_returnnid_sx1;
    input wire [`CHIE_REQ_FLIT_RETURNTXNID_WIDTH-1:0] mshr_txreq_returntxnid_sx1;
    input wire [`CHIE_REQ_FLIT_OPCODE_WIDTH-1:0]      mshr_txreq_opcode_sx1;
    input wire [`CHIE_REQ_FLIT_SIZE_WIDTH-1:0]        mshr_txreq_size_sx1;
    input wire [`CHIE_REQ_FLIT_ADDR_WIDTH-1:0]        mshr_txreq_addr_sx1;
    input wire [`CHIE_REQ_FLIT_NS_WIDTH-1:0]          mshr_txreq_ns_sx1;
    input wire [`CHIE_REQ_FLIT_ALLOWRETRY_WIDTH-1:0]  mshr_txreq_allowretry_sx1;
    input wire [`CHIE_REQ_FLIT_ORDER_WIDTH-1:0]       mshr_txreq_order_sx1;
    input wire [`CHIE_REQ_FLIT_PCRDTYPE_WIDTH-1:0]    mshr_txreq_pcrdtype_sx1;
    input wire [`CHIE_REQ_FLIT_MEMATTR_WIDTH-1:0]     mshr_txreq_memattr_sx1;
    input wire [`CHIE_REQ_FLIT_DODWT_WIDTH-1:0]       mshr_txreq_dodwt_sx1;
    input wire [`CHIE_REQ_FLIT_TRACETAG_WIDTH-1:0]    mshr_txreq_tracetag_sx1;
    input wire [`CHIE_REQ_FLIT_TGTID_RANGE]           mshr_txreq_tgtid; // added for RNF
    input wire [`CHIE_REQ_FLIT_SRCID_RANGE]           mshr_txreq_srcid; // added for RNF
    input wire [`CHIE_REQ_FLIT_LIKELYSHARED_WIDTH-1:0]  encoder_txreq_likelyshared; // added for RNF
    input wire [`CHIE_REQ_FLIT_EXCL_WIDTH-1:0]          encoder_txreq_exclusive;
    input wire [`CHIE_REQ_FLIT_ENDIAN_WIDTH-1:0]      encoder_txreq_endian;
    input wire [`CHIE_REQ_FLIT_LPID_WIDTH-1:0]        encoder_txreq_lpid;
    input wire [`CHIE_REQ_FLIT_EXPCOMPACK_WIDTH-1:0]  encoder_txreq_expcompack;
    // TXRSP
    input wire                                        txrsp_lcrdv;
    input wire                                        mshr_txrsp_bypass_valid_s1;
    input wire [`CHIE_RSP_FLIT_QOS_WIDTH-1:0]         mshr_txrsp_bypass_qos_s1;
    input wire [`CHIE_RSP_FLIT_TGTID_WIDTH-1:0]       mshr_txrsp_bypass_tgtid_s1;
    input wire [`CHIE_RSP_FLIT_TXNID_WIDTH-1:0]       mshr_txrsp_bypass_txnid_s1;
    input wire [`CHIE_RSP_FLIT_OPCODE_WIDTH-1:0]      mshr_txrsp_bypass_opcode_s1;
    input wire [`CHIE_RSP_FLIT_RESP_WIDTH-1:0]        encoder_txrsp_bypass_resp;
    input wire [`CHIE_RSP_FLIT_RESPERR_WIDTH-1:0]     mshr_txrsp_bypass_resperr_s1;
    input wire [`CHIE_RSP_FLIT_DBID_WIDTH-1:0]        mshr_txrsp_bypass_dbid_s1;
    input wire [`CHIE_RSP_FLIT_TRACETAG_WIDTH-1:0]    mshr_txrsp_bypass_tracetag_s1;
    input wire                                        qos_txrsp_retryack_valid_s1;
    input wire [`CHIE_RSP_FLIT_QOS_WIDTH-1:0]         qos_txrsp_retryack_qos_s1;
    input wire [`CHIE_RSP_FLIT_TGTID_WIDTH-1:0]       qos_txrsp_retryack_tgtid_s1;
    input wire [`CHIE_RSP_FLIT_TXNID_WIDTH-1:0]       qos_txrsp_retryack_txnid_s1;
    input wire [`CHIE_RSP_FLIT_PCRDTYPE_WIDTH-1:0]    qos_txrsp_retryack_pcrdtype_s1;
    input wire [`CHIE_RSP_FLIT_TRACETAG_WIDTH-1:0]    qos_txrsp_retryack_tracetag_s1;
    input wire                                        qos_txrsp_pcrdgnt_valid_s2;
    input wire [`CHIE_RSP_FLIT_QOS_WIDTH-1:0]         qos_txrsp_pcrdgnt_qos_s2;
    input wire [`CHIE_RSP_FLIT_TGTID_WIDTH-1:0]       qos_txrsp_pcrdgnt_tgtid_s2;
    input wire [`CHIE_RSP_FLIT_PCRDTYPE_WIDTH-1:0]    qos_txrsp_pcrdgnt_pcrdtype_s2;
    input wire                                        mshr_txrsp_valid_sx1_q;
    input wire [`CHIE_RSP_FLIT_QOS_WIDTH-1:0]         mshr_txrsp_qos_sx1;
    input wire [`CHIE_RSP_FLIT_TGTID_WIDTH-1:0]       mshr_txrsp_tgtid_sx1;
    input wire [`CHIE_RSP_FLIT_TXNID_WIDTH-1:0]       mshr_txrsp_txnid_sx1_q;
    input wire [`CHIE_RSP_FLIT_OPCODE_WIDTH-1:0]      mshr_txrsp_opcode_sx1;
    input wire [`CHIE_RSP_FLIT_RESPERR_WIDTH-1:0]     mshr_txrsp_resperr_sx1;
    input wire [`CHIE_RSP_FLIT_RESP_WIDTH-1:0]        mshr_txrsp_resp_sx1;
    input wire [`CHIE_RSP_FLIT_DBID_WIDTH-1:0]        mshr_txrsp_dbid_sx1;
    input wire [`CHIE_RSP_FLIT_TRACETAG_WIDTH-1:0]    mshr_txrsp_tracetag_sx1;
    // TXDAT
    input wire                                        txdat_lcrdv;
    input wire [`CHIE_DAT_FLIT_QOS_WIDTH-1:0]         encoder_txdat_qos;
    input wire [`CHIE_DAT_FLIT_SRCID_WIDTH-1:0]       encoder_txdat_srcid;
    input wire [`CHIE_DAT_FLIT_HOMENID_WIDTH-1:0]     encoder_txdat_homenid;
    input wire [`CHIE_DAT_FLIT_FWDSTATE_WIDTH-1:0]    encoder_txdat_fwdstate;
    input wire [`CHIE_DAT_FLIT_CCID_WIDTH-1:0]        encoder_txdat_ccid;
    input wire [`CHIE_DAT_FLIT_TGTID_WIDTH-1:0]       mshr_txdat_tgtid_sx2;
    input wire [`CHIE_DAT_FLIT_TXNID_WIDTH-1:0]       mshr_txdat_txnid_sx2;
    input wire [`CHIE_DAT_FLIT_OPCODE_WIDTH-1:0]      mshr_txdat_opcode_sx2;
    input wire [`CHIE_DAT_FLIT_RESP_WIDTH-1:0]        mshr_txdat_resp_sx2;
    input wire [`CHIE_DAT_FLIT_RESPERR_WIDTH-1:0]     mshr_txdat_resperr_sx2;
    input wire [`CHIE_DAT_FLIT_DBID_WIDTH-1:0]        mshr_txdat_dbid_sx2;
    input wire [`CHI_CACHE_LINE_WIDTH-1:0]            dbf_txdat_data_sx1;
    input wire [2-1:0]                                dbf_txdat_idx_sx1;
    input wire [1:0]                                  dbf_txdat_pe_sx1;
    input wire [`CHI_CACHE_BE_WIDTH-1:0]              dbf_txdat_be_sx1;
    input wire                                        dbf_txdat_valid_sx1;

    //outputs
    // RXRSP
    output wire                                       rxrsp_lcrdv;
    output wire                                       li_mshr_rxrsp_valid_s0;
    output wire [`CHIE_RSP_FLIT_SRCID_WIDTH-1:0]      li_mshr_rxrsp_srcid_s0;
    output wire [`CHIE_RSP_FLIT_TXNID_WIDTH-1:0]      li_mshr_rxrsp_txnid_s0;
    output wire [`CHIE_RSP_FLIT_OPCODE_WIDTH-1:0]     li_mshr_rxrsp_opcode_s0;
    output wire [`CHIE_RSP_FLIT_RESP_WIDTH-1:0]       li_mshr_rxrsp_resp_s0;
    output wire [`CHIE_RSP_FLIT_FWDSTATE_WIDTH-1:0]   li_mshr_rxrsp_fwdstate_s0;
    output wire [`CHIE_RSP_FLIT_DBID_WIDTH-1:0]       li_mshr_rxrsp_dbid_s0;
    output wire [`CHIE_RSP_FLIT_PCRDTYPE_WIDTH-1:0]   li_mshr_rxrsp_pcrdtype_s0;
    input wire                                        rxrsp_buf_ready;
    // RXDAT
    output wire                                       rxdat_lcrdv;
    output wire                                       li_mshr_rxdat_valid_s0;
    output wire [`CHIE_DAT_FLIT_TXNID_WIDTH-1:0]      li_mshr_rxdat_txnid_s0;
    output wire [`CHIE_DAT_FLIT_OPCODE_WIDTH-1:0]     li_mshr_rxdat_opcode_s0;
    output wire [`CHIE_DAT_FLIT_RESP_WIDTH-1:0]       li_mshr_rxdat_resp_s0;
    output wire [`CHIE_DAT_FLIT_FWDSTATE_WIDTH-1:0]   li_mshr_rxdat_fwdstate_s0;
    output wire [`CHIE_DAT_FLIT_DATAID_WIDTH-1:0]     li_mshr_rxdat_dataid_s0;
    output wire [`CHIE_DAT_FLIT_HOMENID_WIDTH-1:0]    li_decoder_rxdat_homenid; // added for RNF
    output wire [`CHIE_DAT_FLIT_CCID_WIDTH-1:0]       li_decoder_rxdat_ccid;    // added for RNF
    output wire [`CHIE_DAT_FLIT_DBID_WIDTH-1:0]       li_decoder_rxdat_dbid;    // added for RNF
    output wire                                       li_dbf_rxdat_valid_s0;
    output wire [`CHIE_DAT_FLIT_TXNID_WIDTH-1:0]      li_dbf_rxdat_txnid_s0;
    output wire [`CHIE_DAT_FLIT_OPCODE_WIDTH-1:0]     li_dbf_rxdat_opcode_s0;
    output wire [`CHIE_DAT_FLIT_DATAID_WIDTH-1:0]     li_dbf_rxdat_dataid_s0;
    output wire [`CHIE_DAT_FLIT_BE_WIDTH-1:0]         li_dbf_rxdat_be_s0;
    output wire [`CHIE_DAT_FLIT_DATA_WIDTH-1:0]       li_dbf_rxdat_data_s0;
    // OUT singals for transmit channels
    output wire                                       txreqflitv;
    output wire [`CHIE_REQ_FLIT_RANGE]                txreqflit;
    output wire                                       txreqflitpend;
    output wire                                       txrspflitv;
    output wire [`CHIE_RSP_FLIT_RANGE]                txrspflit;
    output wire                                       txrspflitpend;
    output wire                                       txrsp_mshr_retryack_won_s1;
    output wire                                       txrsp_mshr_pcrdgnt_won_s2;
    output wire                                       txrsp_mshr_won_sx1;
    output wire                                       txrsp_cache_crd_avail;    // added for RNF
    output wire                                       txreq_mshr_won_sx1;
    output wire                                       txreq_mshr_bypass_won_s1;
    output wire                                       txreq_encoder_crd_avail_s1;
    output wire                                       txrsp_mshr_bypass_won_s1;
    output wire                                       txdatflitv;
    output wire [`CHIE_DAT_FLIT_RANGE]                txdatflit;
    output wire                                       txdatflitpend;
    output wire                                       txdat_mshr_clr_dbf_busy_valid_sx3;
    output wire [2-1:0]                               txdat_mshr_clr_dbf_busy_idx_sx3;
    output wire [2-1:0]                               txdat_mshr_rd_idx_sx2;
    output wire                                       txdat_mshr_busy_sx;


    // RXSNP IN/OUT
    output wire                                         rxsnp_lcrdv;
    output wire                                         rxsnp_decoder_valid_sx;
    output wire [`CHIE_SNP_FLIT_QOS_WIDTH-1:0]          rxsnp_decoder_qos;
    output wire [`CHIE_SNP_FLIT_SRCID_WIDTH-1:0]        rxsnp_decoder_srcid;
    output wire [`CHIE_SNP_FLIT_TXNID_WIDTH-1:0]        rxsnp_decoder_txnid;
    output wire [`CHIE_SNP_FLIT_FWDNID_WIDTH-1:0]       rxsnp_decoder_fwdnid;
    output wire [`CHIE_SNP_FLIT_FWDTXNID_WIDTH-1:0]     rxsnp_decoder_fwdtxnid;
    output wire [`CHIE_SNP_FLIT_OPCODE_WIDTH-1:0]       rxsnp_decoder_opcode;
    output wire [`CHIE_SNP_FLIT_ADDR_WIDTH-1:0]         rxsnp_decoder_addr;
    output wire [`CHIE_SNP_FLIT_NS_WIDTH-1:0]           rxsnp_decoder_ns;
    output wire [`CHIE_SNP_FLIT_DONOTGOTOSD_WIDTH-1:0]  rxsnp_decoder_donotgotosd;
    output wire [`CHIE_SNP_FLIT_RETTOSRC_WIDTH-1:0]     rxsnp_decoder_rettosrc;
    output wire [`CHIE_SNP_FLIT_TRACETAG_WIDTH-1:0]     rxsnp_decoder_tracetag;
    input wire                                          rxsnpflitv;
    input wire  [`RNF_SNP_FLIT_RANGE]                   rxsnpflit;
    input wire                                          rxsnpflitpend;
    input wire                                          rxsnp_buf_ready;

    output wire                                         TXLINKACTIVEREQ;
    input wire                                          TXLINKACTIVEACK;
    input wire                                          RXLINKACTIVEREQ;
    output wire                                         RXLINKACTIVEACK;
    output wire                                         TXACTIVE;
    input wire                                          RXACTIVE;   
    input wire                                          tx_active_ready;  // TXLINKACTIVEREQ can be asserted
    
    wire tx_ready;  
    wire [2:0]  tx_lcredits_used;        // if all L-credits are returned to receiver
    wire rx_ready;               // signal for IFs that L-credits can be given
    wire [2:0]  rx_lcredits_returned;    // if all L-credits are returned when transmitter entering lowpower


    rnf_link_handshake_ctl `RNF_PARAM_INST
                        u_rnf_link_handshake_ctl(
                            .clk                                            (clk),
                            .rst                                            (rst),
                            .TXLINKACTIVEREQ                                (TXLINKACTIVEREQ),
                            .TXLINKACTIVEACK                                (TXLINKACTIVEACK),
                            .RXLINKACTIVEREQ                                (RXLINKACTIVEREQ),
                            .RXLINKACTIVEACK                                (RXLINKACTIVEACK),
                            .TXACTIVE                                       (TXACTIVE),
                            .RXACTIVE                                       (RXACTIVE),
                            .tx_active_ready                                (tx_active_ready),
                            .tx_ready                                       (tx_ready),
                            .tx_lcredits_used                               (tx_lcredits_used),
                            .rx_ready                                       (rx_ready),
                            .rx_lcredits_returned                           (rx_lcredits_returned)
                        );


    rnf_link_rxrsp_parse `RNF_PARAM_INST
                         u_rnf_link_rxrsp_parse(
                             .clk                                            (clk                            ),
                             .rst                                            (rst                            ),
                             .rxrspflitv                                     (rxrspflitv                     ),
                             .rxrspflit                                      (rxrspflit                      ),
                             .rxrspflitpend                                  (rxrspflitpend                  ),
                             .rxrsp_lcrdv                                    (rxrsp_lcrdv                    ),
                             .li_mshr_rxrsp_valid_s0                         (li_mshr_rxrsp_valid_s0         ),
                             .li_mshr_rxrsp_srcid_s0                         (li_mshr_rxrsp_srcid_s0         ),
                             .li_mshr_rxrsp_txnid_s0                         (li_mshr_rxrsp_txnid_s0         ),
                             .li_mshr_rxrsp_opcode_s0                        (li_mshr_rxrsp_opcode_s0        ),
                             .li_mshr_rxrsp_resp_s0                          (li_mshr_rxrsp_resp_s0          ),
                             .li_mshr_rxrsp_fwdstate_s0                      (li_mshr_rxrsp_fwdstate_s0      ),
                             .li_mshr_rxrsp_dbid_s0                          (li_mshr_rxrsp_dbid_s0          ),
                             .li_mshr_rxrsp_pcrdtype_s0                      (li_mshr_rxrsp_pcrdtype_s0      ),
                             .rxrsp_buf_ready                                 (rxrsp_buf_ready                 ),
                            .rx_ready                                       (rx_ready),
                            .rx_lcredits_returned                           (rx_lcredits_returned[0])
                         );

    rnf_link_rxdat_parse `RNF_PARAM_INST
                         u_rnf_link_rxdat_parse(
                             .clk                                            (clk                            ),
                             .rst                                            (rst                            ),
                             .rxdatflitv                                     (rxdatflitv                     ),
                             .rxdatflit                                      (rxdatflit                      ),
                             .rxdatflitpend                                  (rxdatflitpend                  ),
                             .rxdat_lcrdv                                    (rxdat_lcrdv                    ),
                             .li_mshr_rxdat_valid_s0                         (li_mshr_rxdat_valid_s0         ),
                             .li_mshr_rxdat_txnid_s0                         (li_mshr_rxdat_txnid_s0         ),
                             .li_mshr_rxdat_opcode_s0                        (li_mshr_rxdat_opcode_s0        ),
                             .li_mshr_rxdat_resp_s0                          (li_mshr_rxdat_resp_s0          ),
                             .li_mshr_rxdat_fwdstate_s0                      (li_mshr_rxdat_fwdstate_s0      ),
                             .li_mshr_rxdat_dataid_s0                        (li_mshr_rxdat_dataid_s0        ),
                             .li_decoder_rxdat_homenid                       (li_decoder_rxdat_homenid),        // added for RNF
                             .li_decoder_rxdat_ccid                          (li_decoder_rxdat_ccid),           // added for RNF
                             .li_decoder_rxdat_dbid                          (li_decoder_rxdat_dbid),           // added for RNF
                             .li_dbf_rxdat_valid_s0                          (li_dbf_rxdat_valid_s0          ),
                             .li_dbf_rxdat_txnid_s0                          (li_dbf_rxdat_txnid_s0          ),
                             .li_dbf_rxdat_opcode_s0                         (li_dbf_rxdat_opcode_s0         ),
                             .li_dbf_rxdat_dataid_s0                         (li_dbf_rxdat_dataid_s0         ),
                             .li_dbf_rxdat_be_s0                             (li_dbf_rxdat_be_s0             ),
                             .li_dbf_rxdat_data_s0                           (li_dbf_rxdat_data_s0           ),
                             .rxdat_buf_ready                                 (rxdat_buf_ready),
                            .rx_ready                                       (rx_ready),
                            .rx_lcredits_returned                           (rx_lcredits_returned[1])
                         );

    rnf_link_txreq_wrap `RNF_PARAM_INST
                        u_rnf_link_txreq_wrap(
                            .clk                                            (clk                            ),
                            .rst                                            (rst                            ),
                            .txreq_lcrdv                                    (txreq_lcrdv                    ),
                            .mshr_txreq_bypass_valid_s1                         (mshr_txreq_bypass_valid_s1         ),
                            .mshr_txreq_bypass_qos_s1                           (mshr_txreq_bypass_qos_s1           ),
                            .mshr_txreq_bypass_txnid_s1                         (mshr_txreq_bypass_txnid_s1         ),
                            .mshr_txreq_bypass_returnnid_s1                     (mshr_txreq_bypass_returnnid_s1     ),
                            .mshr_txreq_bypass_returntxnid_s1                   (mshr_txreq_bypass_returntxnid_s1   ),
                            .mshr_txreq_bypass_opcode_s1                        (mshr_txreq_bypass_opcode_s1        ),
                            .mshr_txreq_bypass_size_s1                          (mshr_txreq_bypass_size_s1          ),
                            .mshr_txreq_bypass_addr_s1                          (mshr_txreq_bypass_addr_s1          ),
                            .mshr_txreq_bypass_ns_s1                            (mshr_txreq_bypass_ns_s1            ),
                            .mshr_txreq_bypass_allowretry_s1                    (mshr_txreq_bypass_allowretry_s1    ),
                            .mshr_txreq_bypass_order_s1                         (mshr_txreq_bypass_order_s1         ),
                            .mshr_txreq_bypass_pcrdtype_s1                      (mshr_txreq_bypass_pcrdtype_s1      ),
                            .mshr_txreq_bypass_memattr_s1                       (mshr_txreq_bypass_memattr_s1       ),
                            .mshr_txreq_bypass_dodwt_s1                         (mshr_txreq_bypass_dodwt_s1         ),
                            .mshr_txreq_bypass_tracetag_s1                      (mshr_txreq_bypass_tracetag_s1      ),
                            .mshr_txreq_bypass_tgtid                            (mshr_txreq_bypass_tgtid            ),
                            .mshr_txreq_bypass_srcid                            (mshr_txreq_bypass_srcid            ),
                            .txreq_bypass_likelyshared                          (txreq_bypass_likelyshared          ),
                            .txreq_bypass_exclusive                             (txreq_bypass_exclusive             ),
                            .txreq_bypass_endian                               (txreq_bypass_endian                ),
                            .txreq_bypass_lpid                                 (txreq_bypass_lpid                  ),
                            .txreq_bypass_expcompack                           (txreq_bypass_expcompack            ),
                            .mshr_txreq_valid_sx1_q                         (mshr_txreq_valid_sx1_q         ),
                            .mshr_txreq_qos_sx1                             (mshr_txreq_qos_sx1             ),
                            .mshr_txreq_txnid_sx1_q                         (mshr_txreq_txnid_sx1_q         ),
                            .mshr_txreq_returnnid_sx1                       (mshr_txreq_returnnid_sx1       ),
                            .mshr_txreq_returntxnid_sx1                     (mshr_txreq_returntxnid_sx1     ),
                            .mshr_txreq_opcode_sx1                          (mshr_txreq_opcode_sx1          ),
                            .mshr_txreq_size_sx1                            (mshr_txreq_size_sx1            ),
                            .mshr_txreq_addr_sx1                            (mshr_txreq_addr_sx1            ),
                            .mshr_txreq_ns_sx1                              (mshr_txreq_ns_sx1              ),
                            .mshr_txreq_allowretry_sx1                      (mshr_txreq_allowretry_sx1      ),
                            .mshr_txreq_order_sx1                           (mshr_txreq_order_sx1           ),
                            .mshr_txreq_pcrdtype_sx1                        (mshr_txreq_pcrdtype_sx1        ),
                            .mshr_txreq_memattr_sx1                         (mshr_txreq_memattr_sx1         ),
                            .mshr_txreq_dodwt_sx1                           (mshr_txreq_dodwt_sx1           ),
                            .mshr_txreq_tracetag_sx1                        (mshr_txreq_tracetag_sx1        ),
                            .mshr_txreq_tgtid                               (mshr_txreq_tgtid               ),  // for RNF
                            .mshr_txreq_srcid                               (mshr_txreq_srcid               ),  // for RNF
                            .encoder_txreq_likelyshared                     (encoder_txreq_likelyshared     ), // for RNF
                            .encoder_txreq_exclusive                        (encoder_txreq_exclusive        ),
                            .encoder_txreq_endian                           (encoder_txreq_endian           ),
                            .encoder_txreq_lpid                             (encoder_txreq_lpid             ),
                            .encoder_txreq_expcompack                       (encoder_txreq_expcompack       ),
                            .txreqflitv                                     (txreqflitv                     ),
                            .txreqflit                                      (txreqflit                      ),
                            .txreqflitpend                                  (txreqflitpend                  ),
                            .txreq_mshr_won_sx1                             (txreq_mshr_won_sx1             ),
                            .txreq_mshr_bypass_won_s1                           (txreq_mshr_bypass_won_s1           ),
                            .txreq_encoder_crd_avail_s1                     (txreq_encoder_crd_avail_s1),
                            .tx_ready                                       (tx_ready),
                            .tx_lcredits_used                               (tx_lcredits_used[0])
                        );

    rnf_link_txrsp_wrap `RNF_PARAM_INST
                        u_rnf_link_txrsp_wrap(
                            .clk                                            (clk                            ),
                            .rst                                            (rst                            ),
                            .txrsp_lcrdv                                    (txrsp_lcrdv                    ),
                            .mshr_txrsp_bypass_valid_s1                         (mshr_txrsp_bypass_valid_s1         ),
                            .mshr_txrsp_bypass_qos_s1                           (mshr_txrsp_bypass_qos_s1           ),
                            .mshr_txrsp_bypass_tgtid_s1                         (mshr_txrsp_bypass_tgtid_s1         ),
                            .mshr_txrsp_bypass_txnid_s1                         (mshr_txrsp_bypass_txnid_s1         ),
                            .mshr_txrsp_bypass_opcode_s1                        (mshr_txrsp_bypass_opcode_s1        ),
                            .encoder_txrsp_bypass_resp                          (encoder_txrsp_bypass_resp          ),
                            .mshr_txrsp_bypass_resperr_s1                       (mshr_txrsp_bypass_resperr_s1       ),
                            .mshr_txrsp_bypass_dbid_s1                          (mshr_txrsp_bypass_dbid_s1          ),
                            .mshr_txrsp_bypass_tracetag_s1                      (mshr_txrsp_bypass_tracetag_s1      ),
                            .qos_txrsp_retryack_valid_s1                    (1'b0),//(qos_txrsp_retryack_valid_s1    ),
                            .qos_txrsp_retryack_qos_s1                      (qos_txrsp_retryack_qos_s1      ),
                            .qos_txrsp_retryack_tgtid_s1                    (qos_txrsp_retryack_tgtid_s1    ),
                            .qos_txrsp_retryack_txnid_s1                    (qos_txrsp_retryack_txnid_s1    ),
                            .qos_txrsp_retryack_pcrdtype_s1                 (qos_txrsp_retryack_pcrdtype_s1 ),
                            .qos_txrsp_retryack_tracetag_s1                 (qos_txrsp_retryack_tracetag_s1 ),
                            .qos_txrsp_pcrdgnt_valid_s2                     (1'b0),//(qos_txrsp_pcrdgnt_valid_s2     ),
                            .qos_txrsp_pcrdgnt_qos_s2                       (qos_txrsp_pcrdgnt_qos_s2       ),
                            .qos_txrsp_pcrdgnt_tgtid_s2                     (qos_txrsp_pcrdgnt_tgtid_s2     ),
                            .qos_txrsp_pcrdgnt_pcrdtype_s2                  (qos_txrsp_pcrdgnt_pcrdtype_s2  ),
                            .mshr_txrsp_valid_sx1_q                         (mshr_txrsp_valid_sx1_q         ),
                            .mshr_txrsp_qos_sx1                             (mshr_txrsp_qos_sx1             ),
                            .mshr_txrsp_tgtid_sx1                           (mshr_txrsp_tgtid_sx1           ),
                            .mshr_txrsp_txnid_sx1_q                         (mshr_txrsp_txnid_sx1_q         ),
                            .mshr_txrsp_opcode_sx1                          (mshr_txrsp_opcode_sx1          ),
                            .mshr_txrsp_resperr_sx1                         (mshr_txrsp_resperr_sx1         ),
                            .mshr_txrsp_resp_sx1                            (mshr_txrsp_resp_sx1            ),
                            .mshr_txrsp_dbid_sx1                            (mshr_txrsp_dbid_sx1            ),
                            .mshr_txrsp_tracetag_sx1                        (mshr_txrsp_tracetag_sx1        ),
                            .txrspflitv                                     (txrspflitv                     ),
                            .txrspflit                                      (txrspflit                      ),
                            .txrspflitpend                                  (txrspflitpend                  ),
                            .txrsp_mshr_retryack_won_s1                     (txrsp_mshr_retryack_won_s1     ),
                            .txrsp_mshr_pcrdgnt_won_s2                      (txrsp_mshr_pcrdgnt_won_s2      ),
                            .txrsp_mshr_won_sx1                             (txrsp_mshr_won_sx1             ),
                            .txrsp_mshr_bypass_won_s1                       (txrsp_mshr_bypass_won_s1       ),
                            .txrsp_cache_crd_avail                          (txrsp_cache_crd_avail          ),
                            .tx_ready                                       (tx_ready),
                            .tx_lcredits_used                               (tx_lcredits_used[1])
                        );

    rnf_link_txdat_wrap `RNF_PARAM_INST
                        u_rnf_link_txdat_wrap(
                            .clk                                            (clk                               ),
                            .rst                                            (rst                               ),
                            .txdat_lcrdv                                    (txdat_lcrdv                       ),
                            .encoder_txdat_qos                              (encoder_txdat_qos                 ),
                            .encoder_txdat_srcid                            (encoder_txdat_srcid               ),
                            .encoder_txdat_homenid                          (encoder_txdat_homenid             ),
                            .encoder_txdat_fwdstate                         (encoder_txdat_fwdstate            ),
                            .encoder_txdat_ccid                             (encoder_txdat_ccid                ),
                            .mshr_txdat_tgtid_sx2                           (mshr_txdat_tgtid_sx2              ),
                            .mshr_txdat_txnid_sx2                           (mshr_txdat_txnid_sx2              ),
                            .mshr_txdat_opcode_sx2                          (mshr_txdat_opcode_sx2             ),
                            .mshr_txdat_resp_sx2                            (mshr_txdat_resp_sx2               ),
                            .mshr_txdat_resperr_sx2                         (mshr_txdat_resperr_sx2            ),
                            .mshr_txdat_dbid_sx2                            (mshr_txdat_dbid_sx2               ),
                            .dbf_txdat_data_sx1                             (dbf_txdat_data_sx1                ),
                            .dbf_txdat_idx_sx1                              (dbf_txdat_idx_sx1                 ),
                            .dbf_txdat_be_sx1                               (dbf_txdat_be_sx1                  ),
                            .dbf_txdat_pe_sx1                               (dbf_txdat_pe_sx1                  ),
                            .dbf_txdat_valid_sx1                            (dbf_txdat_valid_sx1               ),
                            .txdatflitv                                     (txdatflitv                        ),
                            .txdatflit                                      (txdatflit                         ),
                            .txdatflitpend                                  (txdatflitpend                     ),
                            .txdat_mshr_clr_dbf_busy_valid_sx3              (txdat_mshr_clr_dbf_busy_valid_sx3 ),
                            .txdat_mshr_clr_dbf_busy_idx_sx3                (txdat_mshr_clr_dbf_busy_idx_sx3   ),
                            .txdat_mshr_rd_idx_sx2                          (txdat_mshr_rd_idx_sx2             ),
                            .txdat_mshr_busy_sx                             (txdat_mshr_busy_sx                ),
                            .tx_ready                                       (tx_ready),
                            .tx_lcredits_used                               (tx_lcredits_used[2])
                        );

    rnf_link_rxsnp_parse `RNF_PARAM_INST
                        u_rnf_link_rxsnp_parse(
                            .clk                                            (clk                                ),
                            .rst                                            (rst                                ),
                            .rxsnpflitv                                     (rxsnpflitv                         ),
                            .rxsnpflit                                      (rxsnpflit                          ),
                            .rxsnpflitpend                                  (rxsnpflitpend                      ),
                            .rxsnp_decoder_valid_sx                         (rxsnp_decoder_valid_sx             ),
                            .rxsnp_decoder_qos                              (rxsnp_decoder_qos                  ),
                            .rxsnp_decoder_srcid                            (rxsnp_decoder_srcid                ),
                            .rxsnp_decoder_txnid                            (rxsnp_decoder_txnid                ),
                            .rxsnp_decoder_fwdnid                           (rxsnp_decoder_fwdnid               ),
                            .rxsnp_decoder_fwdtxnid                         (rxsnp_decoder_fwdtxnid             ),
                            .rxsnp_decoder_opcode                           (rxsnp_decoder_opcode               ),
                            .rxsnp_decoder_addr                             (rxsnp_decoder_addr                 ),
                            .rxsnp_decoder_ns                               (rxsnp_decoder_ns                   ),
                            .rxsnp_decoder_donotgotosd                      (rxsnp_decoder_donotgotosd          ),
                            .rxsnp_decoder_rettosrc                         (rxsnp_decoder_rettosrc             ),
                            .rxsnp_decoder_tracetag                         (rxsnp_decoder_tracetag             ),
                            .rxsnp_buf_ready                                 (rxsnp_buf_ready                     ),
                            .rxsnp_lcrdv                                    (rxsnp_lcrdv                        ),
                            .rx_ready                                       (rx_ready),
                            .rx_lcredits_returned                           (rx_lcredits_returned[2])
                        );                     


endmodule
