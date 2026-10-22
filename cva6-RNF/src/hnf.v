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

`include "chie_defines.v"
`include "hnf_defines.v"
`include "hnf_param.v"

module hnf `HNF_PARAM
    (
        //inputs
        CLK,
        RST,
        RXREQFLITV,
        RXREQFLIT,
        RXREQFLITPEND,
        RXRSPFLITV,
        RXRSPFLIT,
        RXRSPFLITPEND,
        RXDATFLITV,
        RXDATFLIT,
        RXDATFLITPEND,
        TXREQLCRDV,
        TXRSPLCRDV,
        TXSNPLCRDV,
        TXDATLCRDV,

        //outputs
        RXREQLCRDV,
        RXRSPLCRDV,
        RXDATLCRDV,
        TXREQFLITV,
        TXREQFLIT,
        TXREQFLITPEND,
        TXRSPFLITV,
        TXRSPFLIT,
        TXRSPFLITPEND,
        TXSNPFLITV,
        TXSNPFLIT,
        TXSNPFLITPEND,
        TXDATFLITV,
        TXDATFLIT,
        TXDATFLITPEND,

        notify_reg

`ifdef tb_hnf

        //debug signals
        ,
        dbg_l3_valid_q,
        dbg_l3_index_q,
        dbg_l3_rd_ways_q,
        dbg_l3_wr_data_q,
        dbg_l3_wr_ways_q,
        dbg_loc_valid_q,
        dbg_loc_index_q,
        dbg_loc_rd_en_q,
        dbg_loc_wr_ways_q,
        dbg_loc_wr_cline_q,
        dbg_sf_valid_q,
        dbg_sf_index_q,
        dbg_sf_rd_en_q,
        dbg_sf_wr_ways_q,
        dbg_sf_wr_cline_q,
        dbg_lru_valid_q,
        dbg_lru_index_q,
        dbg_lru_rd_en_q,
        dbg_lru_wr_en_q,
        dbg_lru_wr_data_q,
        dbg_l3_rd_data_q,
        dbg_lru_rd_data_q,
        dbg_loc_rd_clines_q,
        dbg_sf_rd_clines_q
`endif

    );
    //inputs
    input wire                                  CLK;
    input wire                                  RST;
    input wire                                  RXREQFLITV;
    input wire [`CHIE_REQ_FLIT_RANGE]           RXREQFLIT;
    input wire                                  RXREQFLITPEND;
    input wire                                  RXRSPFLITV;
    input wire [`CHIE_RSP_FLIT_RANGE]           RXRSPFLIT;
    input wire                                  RXRSPFLITPEND;
    input wire                                  RXDATFLITV;
    input wire [`CHIE_DAT_FLIT_RANGE]           RXDATFLIT;
    input wire                                  RXDATFLITPEND;
    input wire                                  TXREQLCRDV;
    input wire                                  TXRSPLCRDV;
    input wire                                  TXSNPLCRDV;
    input wire                                  TXDATLCRDV;

    //outputs
    output wire                                 RXREQLCRDV;
    output wire                                 RXRSPLCRDV;
    output wire                                 RXDATLCRDV;
    output wire                                 TXREQFLITV;
    output wire [`CHIE_REQ_FLIT_RANGE]          TXREQFLIT;
    output wire                                 TXREQFLITPEND;
    output wire                                 TXRSPFLITV;
    output wire [`CHIE_RSP_FLIT_RANGE]          TXRSPFLIT;
    output wire                                 TXRSPFLITPEND;
    output wire                                 TXSNPFLITV;
    output wire [`HNF_SNP_FLIT_RANGE]           TXSNPFLIT;
    output wire                                 TXSNPFLITPEND;
    output wire                                 TXDATFLITV;
    output wire [`CHIE_DAT_FLIT_RANGE]          TXDATFLIT;
    output wire                                 TXDATFLITPEND;
    output wire [2:0]                           notify_reg;

`ifdef tb_hnf
    //debug ports
    //inputs
    input wire                                      dbg_l3_valid_q;
    input wire [`LOC_INDEX_WIDTH-1:0]               dbg_l3_index_q;
    input wire [`LOC_WAY_NUM-1:0]                   dbg_l3_rd_ways_q;
    input wire [`CACHE_LINE_WIDTH-1:0]              dbg_l3_wr_data_q;
    input wire [`LOC_WAY_NUM-1:0]                   dbg_l3_wr_ways_q;
    input wire                                      dbg_loc_valid_q;
    input wire [`LOC_INDEX_WIDTH-1:0]               dbg_loc_index_q;
    input wire                                      dbg_loc_rd_en_q;
    input wire [`LOC_WAY_NUM-1:0]                   dbg_loc_wr_ways_q;
    input wire [`LOC_CLINE_WIDTH-1:0]               dbg_loc_wr_cline_q;
    input wire                                      dbg_sf_valid_q;
    input wire [`SF_INDEX_WIDTH-1:0]                dbg_sf_index_q;
    input wire                                      dbg_sf_rd_en_q;
    input wire [`SF_WAY_NUM-1:0]                    dbg_sf_wr_ways_q;
    input wire [`SF_CLINE_WIDTH-1:0]                dbg_sf_wr_cline_q;
    input wire                                      dbg_lru_valid_q;
    input wire [`LOC_INDEX_WIDTH-1:0]               dbg_lru_index_q;
    input wire                                      dbg_lru_rd_en_q;
    input wire                                      dbg_lru_wr_en_q;
    input wire [`LRU_CLINE_WIDTH-1:0]               dbg_lru_wr_data_q;

    //outputs
    output wire [`CACHE_LINE_WIDTH-1:0]             dbg_l3_rd_data_q;
    output wire [`LRU_CLINE_WIDTH-1:0]              dbg_lru_rd_data_q;
    output wire [`LOC_CLINE_WIDTH*`LOC_WAY_NUM-1:0] dbg_loc_rd_clines_q;
    output wire [`SF_CLINE_WIDTH*`SF_WAY_NUM-1:0]   dbg_sf_rd_clines_q;
`endif

    //wires
    wire                                        biq_req_valid_s0_q;
    wire [`CHIE_REQ_FLIT_ADDR_WIDTH-1:0]        biq_req_addr_s0_q;
    wire                                        qos_seq_pool_full_s0_q;
    wire                                        rxreq_retry_enable_s0;
    wire                                        mshr_txreq_bypass_valid_s1;
    wire [`CHIE_REQ_FLIT_QOS_WIDTH-1:0]         mshr_txreq_bypass_qos_s1;
    wire [`CHIE_REQ_FLIT_TXNID_WIDTH-1:0]       mshr_txreq_bypass_txnid_s1;
    wire [`CHIE_REQ_FLIT_RETURNNID_WIDTH-1:0]   mshr_txreq_bypass_returnnid_s1;
    wire [`CHIE_REQ_FLIT_RETURNTXNID_WIDTH-1:0] mshr_txreq_bypass_returntxnid_s1;
    wire [`CHIE_REQ_FLIT_OPCODE_WIDTH-1:0]      mshr_txreq_bypass_opcode_s1;
    wire [`CHIE_REQ_FLIT_SIZE_WIDTH-1:0]        mshr_txreq_bypass_size_s1;
    wire [`CHIE_REQ_FLIT_ADDR_WIDTH-1:0]        mshr_txreq_bypass_addr_s1;
    wire [`CHIE_REQ_FLIT_NS_WIDTH-1:0]          mshr_txreq_bypass_ns_s1;
    wire [`CHIE_REQ_FLIT_ALLOWRETRY_WIDTH-1:0]  mshr_txreq_bypass_allowretry_s1;
    wire [`CHIE_REQ_FLIT_ORDER_WIDTH-1:0]       mshr_txreq_bypass_order_s1;
    wire [`CHIE_REQ_FLIT_PCRDTYPE_WIDTH-1:0]    mshr_txreq_bypass_pcrdtype_s1;
    wire [`CHIE_REQ_FLIT_MEMATTR_WIDTH-1:0]     mshr_txreq_bypass_memattr_s1;
    wire [`CHIE_REQ_FLIT_DODWT_WIDTH-1:0]       mshr_txreq_bypass_dodwt_s1;
    wire [`CHIE_REQ_FLIT_TRACETAG_WIDTH-1:0]    mshr_txreq_bypass_tracetag_s1;
    wire                                        mshr_txreq_valid_sx1_q;
    wire [`CHIE_REQ_FLIT_QOS_WIDTH-1:0]         mshr_txreq_qos_sx1;
    wire [`CHIE_REQ_FLIT_TXNID_WIDTH-1:0]       mshr_txreq_txnid_sx1_q;
    wire [`CHIE_REQ_FLIT_RETURNNID_WIDTH-1:0]   mshr_txreq_returnnid_sx1;
    wire [`CHIE_REQ_FLIT_RETURNTXNID_WIDTH-1:0] mshr_txreq_returntxnid_sx1;
    wire [`CHIE_REQ_FLIT_OPCODE_WIDTH-1:0]      mshr_txreq_opcode_sx1;
    wire [`CHIE_REQ_FLIT_SIZE_WIDTH-1:0]        mshr_txreq_size_sx1;
    wire [`CHIE_REQ_FLIT_ADDR_WIDTH-1:0]        mshr_txreq_addr_sx1;
    wire [`CHIE_REQ_FLIT_NS_WIDTH-1:0]          mshr_txreq_ns_sx1;
    wire [`CHIE_REQ_FLIT_ALLOWRETRY_WIDTH-1:0]  mshr_txreq_allowretry_sx1;
    wire [`CHIE_REQ_FLIT_ORDER_WIDTH-1:0]       mshr_txreq_order_sx1;
    wire [`CHIE_REQ_FLIT_PCRDTYPE_WIDTH-1:0]    mshr_txreq_pcrdtype_sx1;
    wire [`CHIE_REQ_FLIT_MEMATTR_WIDTH-1:0]     mshr_txreq_memattr_sx1;
    wire [`CHIE_REQ_FLIT_DODWT_WIDTH-1:0]       mshr_txreq_dodwt_sx1;
    wire [`CHIE_REQ_FLIT_TRACETAG_WIDTH-1:0]    mshr_txreq_tracetag_sx1;
    wire                                        mshr_txrsp_bypass_valid_s1;
    wire [`CHIE_RSP_FLIT_QOS_WIDTH-1:0]         mshr_txrsp_bypass_qos_s1;
    wire [`CHIE_RSP_FLIT_TGTID_WIDTH-1:0]       mshr_txrsp_bypass_tgtid_s1;
    wire [`CHIE_RSP_FLIT_TXNID_WIDTH-1:0]       mshr_txrsp_bypass_txnid_s1;
    wire [`CHIE_RSP_FLIT_OPCODE_WIDTH-1:0]      mshr_txrsp_bypass_opcode_s1;
    wire [`CHIE_RSP_FLIT_RESPERR_WIDTH-1:0]     mshr_txrsp_bypass_resperr_s1;
    wire [`CHIE_RSP_FLIT_DBID_WIDTH-1:0]        mshr_txrsp_bypass_dbid_s1;
    wire [`CHIE_RSP_FLIT_TRACETAG_WIDTH-1:0]    mshr_txrsp_bypass_tracetag_s1;
    wire                                        qos_txrsp_retryack_valid_s1;
    wire [`CHIE_RSP_FLIT_QOS_WIDTH-1:0]         qos_txrsp_retryack_qos_s1;
    wire [`CHIE_RSP_FLIT_TGTID_WIDTH-1:0]       qos_txrsp_retryack_tgtid_s1;
    wire [`CHIE_RSP_FLIT_TXNID_WIDTH-1:0]       qos_txrsp_retryack_txnid_s1;
    wire [`CHIE_RSP_FLIT_PCRDTYPE_WIDTH-1:0]    qos_txrsp_retryack_pcrdtype_s1;
    wire [`CHIE_RSP_FLIT_TRACETAG_WIDTH-1:0]    qos_txrsp_retryack_tracetag_s1;
    wire                                        qos_txrsp_pcrdgnt_valid_s2;
    wire [`CHIE_RSP_FLIT_QOS_WIDTH-1:0]         qos_txrsp_pcrdgnt_qos_s2;
    wire [`CHIE_RSP_FLIT_TGTID_WIDTH-1:0]       qos_txrsp_pcrdgnt_tgtid_s2;
    wire [`CHIE_RSP_FLIT_PCRDTYPE_WIDTH-1:0]    qos_txrsp_pcrdgnt_pcrdtype_s2;
    wire                                        mshr_txrsp_valid_sx1_q;
    wire [`CHIE_RSP_FLIT_QOS_WIDTH-1:0]         mshr_txrsp_qos_sx1;
    wire [`CHIE_RSP_FLIT_TGTID_WIDTH-1:0]       mshr_txrsp_tgtid_sx1;
    wire [`CHIE_RSP_FLIT_TXNID_WIDTH-1:0]       mshr_txrsp_txnid_sx1_q;
    wire [`CHIE_RSP_FLIT_OPCODE_WIDTH-1:0]      mshr_txrsp_opcode_sx1;
    wire [`CHIE_RSP_FLIT_RESPERR_WIDTH-1:0]     mshr_txrsp_resperr_sx1;
    wire [`CHIE_RSP_FLIT_RESP_WIDTH-1:0]        mshr_txrsp_resp_sx1;
    wire [`CHIE_RSP_FLIT_DBID_WIDTH-1:0]        mshr_txrsp_dbid_sx1;
    wire [`CHIE_RSP_FLIT_TRACETAG_WIDTH-1:0]    mshr_txrsp_tracetag_sx1;
    wire                                        mshr_txsnp_valid_sx1_q;
    wire [`CHIE_SNP_FLIT_QOS_WIDTH-1:0]         mshr_txsnp_qos_sx1;
    wire [`CHIE_SNP_FLIT_TXNID_WIDTH-1:0]       mshr_txsnp_txnid_sx1_q;
    wire [`CHIE_SNP_FLIT_FWDNID_WIDTH-1:0]      mshr_txsnp_fwdnid_sx1;
    wire [`CHIE_SNP_FLIT_FWDTXNID_WIDTH-1:0]    mshr_txsnp_fwdtxnid_sx1;
    wire [`CHIE_SNP_FLIT_OPCODE_WIDTH-1:0]      mshr_txsnp_opcode_sx1;
    wire [`CHIE_SNP_FLIT_ADDR_WIDTH-1:0]        mshr_txsnp_addr_sx1;
    wire [`CHIE_SNP_FLIT_NS_WIDTH-1:0]          mshr_txsnp_ns_sx1;
    wire [`CHIE_SNP_FLIT_RETTOSRC_WIDTH-1:0]    mshr_txsnp_rettosrc_sx1;
    wire [`CHIE_SNP_FLIT_TRACETAG_WIDTH-1:0]    mshr_txsnp_tracetag_sx1;
    wire [HNF_MSHR_RNF_NUM_PARAM-1:0]           mshr_txsnp_rn_vec_sx1;
    wire [`CHIE_DAT_FLIT_TGTID_WIDTH-1:0]       mshr_txdat_tgtid_sx2;
    wire [`CHIE_DAT_FLIT_TXNID_WIDTH-1:0]       mshr_txdat_txnid_sx2;
    wire [`CHIE_DAT_FLIT_OPCODE_WIDTH-1:0]      mshr_txdat_opcode_sx2;
    wire [`CHIE_DAT_FLIT_RESP_WIDTH-1:0]        mshr_txdat_resp_sx2;
    wire [`CHIE_DAT_FLIT_RESPERR_WIDTH-1:0]     mshr_txdat_resperr_sx2;
    wire [`CHIE_DAT_FLIT_DBID_WIDTH-1:0]        mshr_txdat_dbid_sx2;
    wire [`CHIE_DAT_FLIT_DATA_WIDTH*2-1:0]      dbf_txdat_data_sx1;
    // P5/P6b -- AtomicLoad CompData data path (see comment block near
    // hnf_atomic_alu instance for rationale)
    wire [`CHIE_DAT_FLIT_DATA_WIDTH*2-1:0]      dbf_txdat_data_sx1_muxed;
    wire [`MSHR_ENTRIES_WIDTH-1:0]              dbf_txdat_idx_sx1;
    wire [`CHIE_DAT_FLIT_BE_WIDTH*2-1:0]        dbf_txdat_be_sx1;
    wire [1:0]                                  dbf_txdat_pe_sx1;
    wire                                        dbf_txdat_valid_sx1;
    wire                                        li_mshr_rxreq_valid_s0;
    wire [`CHIE_REQ_FLIT_QOS_WIDTH-1:0]         li_mshr_rxreq_qos_s0;
    wire [`CHIE_REQ_FLIT_SRCID_WIDTH-1:0]       li_mshr_rxreq_srcid_s0;
    wire [`CHIE_REQ_FLIT_TXNID_WIDTH-1:0]       li_mshr_rxreq_txnid_s0;
    wire [`CHIE_REQ_FLIT_OPCODE_WIDTH-1:0]      li_mshr_rxreq_opcode_s0;
    wire [`CHIE_REQ_FLIT_SIZE_WIDTH-1:0]        li_mshr_rxreq_size_s0;
    wire [`CHIE_REQ_FLIT_ADDR_WIDTH-1:0]        li_mshr_rxreq_addr_s0;
    wire                                        li_mshr_rxreq_ns_s0;
    wire                                        li_mshr_rxreq_allowretry_s0;
    wire [`CHIE_REQ_FLIT_ORDER_WIDTH-1:0]       li_mshr_rxreq_order_s0;
    wire [`CHIE_REQ_FLIT_PCRDTYPE_WIDTH-1:0]    li_mshr_rxreq_pcrdtype_s0;
    wire [`CHIE_REQ_FLIT_MEMATTR_WIDTH-1:0]     li_mshr_rxreq_memattr_s0;
    wire [`CHIE_REQ_FLIT_LPID_WIDTH-1:0]        li_mshr_rxreq_lpid_s0;
    wire                                        li_mshr_rxreq_excl_s0;
    wire                                        li_mshr_rxreq_expcompack_s0;
    wire                                        li_mshr_rxreq_tracetag_s0;
    wire                                        li_mshr_rxrsp_valid_s0;
    wire [`CHIE_RSP_FLIT_SRCID_WIDTH-1:0]       li_mshr_rxrsp_srcid_s0;
    wire [`CHIE_RSP_FLIT_TXNID_WIDTH-1:0]       li_mshr_rxrsp_txnid_s0;
    wire [`CHIE_RSP_FLIT_OPCODE_WIDTH-1:0]      li_mshr_rxrsp_opcode_s0;
    wire [`CHIE_RSP_FLIT_RESP_WIDTH-1:0]        li_mshr_rxrsp_resp_s0;
    wire [`CHIE_RSP_FLIT_FWDSTATE_WIDTH-1:0]    li_mshr_rxrsp_fwdstate_s0;
    wire [`CHIE_RSP_FLIT_DBID_WIDTH-1:0]        li_mshr_rxrsp_dbid_s0;
    wire [`CHIE_RSP_FLIT_PCRDTYPE_WIDTH-1:0]    li_mshr_rxrsp_pcrdtype_s0;
    wire                                        li_mshr_rxdat_valid_s0;
    wire [`CHIE_DAT_FLIT_TXNID_WIDTH-1:0]       li_mshr_rxdat_txnid_s0;
    wire [`CHIE_DAT_FLIT_OPCODE_WIDTH-1:0]      li_mshr_rxdat_opcode_s0;
    wire [`CHIE_DAT_FLIT_RESP_WIDTH-1:0]        li_mshr_rxdat_resp_s0;
    wire [`CHIE_DAT_FLIT_FWDSTATE_WIDTH-1:0]    li_mshr_rxdat_fwdstate_s0;
    wire [`CHIE_DAT_FLIT_DATAID_WIDTH-1:0]      li_mshr_rxdat_dataid_s0;
    wire                                        li_dbf_rxdat_valid_s0;
    wire [`MSHR_ENTRIES_WIDTH-1:0]              li_dbf_rxdat_txnid_s0;
    wire [`CHIE_DAT_FLIT_OPCODE_WIDTH-1:0]      li_dbf_rxdat_opcode_s0;
    wire [`CHIE_DAT_FLIT_DATAID_WIDTH-1:0]      li_dbf_rxdat_dataid_s0;
    wire [`CHIE_DAT_FLIT_BE_WIDTH-1:0]          li_dbf_rxdat_be_s0;
    wire [`CHIE_DAT_FLIT_DATA_WIDTH-1:0]        li_dbf_rxdat_data_s0;
    wire                                        txrsp_mshr_retryack_won_s1;
    wire                                        txrsp_mshr_pcrdgnt_won_s2;
    wire                                        txrsp_mshr_won_sx1;
    wire                                        txreq_mshr_won_sx1;
    wire                                        txreq_mshr_bypass_won_s1;
    wire                                        txrsp_mshr_bypass_won_s1;
    wire                                        txsnp_mshr_busy_sx1;
    wire                                        txdat_mshr_clr_dbf_busy_valid_sx3;
    wire [`MSHR_ENTRIES_WIDTH-1:0]              txdat_mshr_clr_dbf_busy_idx_sx3;
    wire [`MSHR_ENTRIES_WIDTH-1:0]              txdat_mshr_rd_idx_sx2;
    wire                                        txdat_mshr_busy_sx;
    wire [`CHIE_REQ_FLIT_ADDR_WIDTH-1:0]        pipe_mshr_addr_sx2_q;
    wire                                        pipe_mshr_addr_valid_sx2_q;
    wire [`MSHR_ENTRIES_WIDTH-1:0]              pipe_mshr_addr_idx_sx2_q;
    wire [`MSHR_ENTRIES_WIDTH-1:0]              l3_mshr_entry_sx7_q;
    wire                                        l3_evict_sx7_q;
    wire [`CHIE_REQ_FLIT_ADDR_WIDTH-1:0]        l3_evict_addr_sx7_q;
    wire                                        l3_pipeval_sx7_q;
    wire [`CHIE_REQ_FLIT_OPCODE_WIDTH-1:0]      l3_opcode_sx7_q;
    wire                                        l3_memrd_sx7_q;
    wire                                        l3_hit_sx7_q;
    wire                                        l3_hit_d_sx7_q;
    wire                                        l3_sfhit_sx7_q;
    wire                                        l3_snpdirect_sx7_q;
    wire                                        l3_snpbrd_sx7_q;
    wire [HNF_MSHR_RNF_NUM_PARAM-1:0]           l3_snp_bit_sx7_q;
    wire                                        l3_replay_sx7_q;
    wire                                        l3_mshr_wr_op_sx7_q;
    wire                                        mshr_l3_hazard_valid_sx3_q;
    wire [`CHIE_REQ_FLIT_ADDR_WIDTH-1:0]        mshr_l3_addr_sx1;
    wire [`MSHR_ENTRIES_WIDTH-1:0]              mshr_dbf_rd_idx_sx1_q;
    wire                                        mshr_dbf_rd_valid_sx1_q;
    wire [`MSHR_ENTRIES_WIDTH-1:0]              mshr_dbf_retired_idx_sx1_q;
    wire                                        mshr_dbf_retired_valid_sx1_q;
    wire                                        mshr_l3_req_en_sx1_q;
    wire [`MSHR_ENTRIES_WIDTH-1:0]              mshr_l3_entry_idx_sx1_q;
    wire                                        mshr_l3_fill_sx1_q;
    wire [`CHIE_REQ_FLIT_OPCODE_WIDTH-1:0]      mshr_l3_opcode_sx1_q;
    wire [CHIE_NID_WIDTH_PARAM-1:0]             mshr_l3_rnf_sx1_q;
    wire                                        mshr_l3_fill_dirty_sx1_q;

    // P5 -- per-entry atomic-active vector + ALU plumbing
    wire [HNF_MSHR_ENTRIES_NUM_PARAM-1:0]        mshr_atomic_active_vec_sx1_q;
    wire [HNF_MSHR_ENTRIES_NUM_PARAM-1:0]        mshr_atomic_memwr_pending_vec_sx1_q;
    wire [HNF_MSHR_ENTRIES_NUM_PARAM-1:0]        mshr_rn_data_busy_vec_sx_q;
    wire [HNF_MSHR_ENTRIES_NUM_PARAM-1:0]        mshr_sn_data_busy_vec_sx_q;
    wire [HNF_MSHR_ENTRIES_NUM_PARAM*4-1:0]      mshr_atomic_op_vec_sx1_q;
    wire                                        mshr_l3_seq_retire_sx1_q;
    wire [`LOC_CLINE_WIDTH*`LOC_WAY_NUM-1:0]    loc_rd_clines_q;
    wire [`SF_CLINE_WIDTH*`SF_WAY_NUM-1:0]      sf_rd_clines_q;
    wire [`LRU_CLINE_WIDTH-1:0]                 lru_rd_data_q;
    wire [`LOC_INDEX_WIDTH-1:0]                 loc_index_q;
    wire                                        loc_rd_en_q;
    wire [`LOC_WAY_NUM-1:0]                     loc_wr_ways_q;
    wire [`LOC_CLINE_WIDTH-1:0]                 loc_wr_cline_q;
    wire [`SF_INDEX_WIDTH-1:0]                  sf_index_q;
    wire                                        sf_rd_en_q;
    wire [`SF_WAY_NUM-1:0]                      sf_wr_ways_q;
    wire [`SF_CLINE_WIDTH-1:0]                  sf_wr_cline_q;
    wire [`LOC_INDEX_WIDTH-1:0]                 l3_index_q;
    wire [`LOC_WAY_NUM-1:0]                     l3_rd_ways_q;
    wire [`LOC_WAY_NUM-1:0]                     l3_wr_ways_q;
    wire [`LOC_INDEX_WIDTH-1:0]                 lru_index_q;
    wire                                        lru_rd_en_q;
    wire                                        lru_wr_en_q;
    wire [`LRU_CLINE_WIDTH-1:0]                 lru_wr_data_q;
    wire [`CACHE_LINE_WIDTH-1:0]                l3_rd_data_q;
    wire [`CACHE_LINE_WIDTH-1:0]                l3_wr_data_q;
    wire [`LOC_INDEX_WIDTH-1:0]                 cpl_l3_index_q;
    wire [`LOC_WAY_NUM-1:0]                     cpl_l3_rd_ways_q;
    wire [`CACHE_LINE_WIDTH-1:0]                dbf_l3_wr_data_q;
    wire [`LOC_WAY_NUM-1:0]                     cpl_l3_wr_ways_q;
    wire [`LOC_INDEX_WIDTH-1:0]                 cpl_loc_index_q;
    wire                                        cpl_loc_rd_en_q;
    wire [`LOC_WAY_NUM-1:0]                     cpl_loc_wr_ways_q;
    wire [`LOC_CLINE_WIDTH-1:0]                 cpl_loc_wr_cline_q;
    wire [`SF_INDEX_WIDTH-1:0]                  cpl_sf_index_q;
    wire                                        cpl_sf_rd_en_q;
    wire [`SF_WAY_NUM-1:0]                      cpl_sf_wr_ways_q;
    wire [`SF_CLINE_WIDTH-1:0]                  cpl_sf_wr_cline_q;
    wire [`LOC_INDEX_WIDTH-1:0]                 cpl_lru_index_q;
    wire                                        cpl_lru_rd_en_q;
    wire                                        cpl_lru_wr_en_q;
    wire [`LRU_CLINE_WIDTH-1:0]                 cpl_lru_wr_data_q;
    wire                                        pipe_dbf_wr_valid_sx9_q;
    wire [`MSHR_ENTRIES_WIDTH-1:0]              pipe_dbf_wr_idx_sx9_q;
    wire                                        pipe_dbf_rd_idx_sx2_valid_q;
    wire [`MSHR_ENTRIES_WIDTH-1:0]              pipe_dbf_rd_idx_sx2_q;

    hnf_link `HNF_PARAM_INST
             u_hnf_link(
                 //inputs
                 .clk                                          (CLK                               ),
                 .rst                                          (RST                               ),
                 .rxreqflitv                                   (RXREQFLITV                        ),
                 .rxreqflit                                    (RXREQFLIT                         ),
                 .rxreqflitpend                                (RXREQFLITPEND                     ),
                 .biq_req_valid_s0_q                           (biq_req_valid_s0_q                ),
                 .biq_req_addr_s0_q                            (biq_req_addr_s0_q                 ),
                 .qos_seq_pool_full_s0_q                       (qos_seq_pool_full_s0_q            ),
                 .rxreq_retry_enable_s0                        (rxreq_retry_enable_s0             ),
                 .rxrspflitv                                   (RXRSPFLITV                        ),
                 .rxrspflit                                    (RXRSPFLIT                         ),
                 .rxrspflitpend                                (RXRSPFLITPEND                     ),
                 .rxdatflitv                                   (RXDATFLITV                        ),
                 .rxdatflit                                    (RXDATFLIT                         ),
                 .rxdatflitpend                                (RXDATFLITPEND                     ),
                 .txreq_lcrdv                                  (TXREQLCRDV                        ),
                 .mshr_txreq_bypass_valid_s1                       (mshr_txreq_bypass_valid_s1            ),
                 .mshr_txreq_bypass_qos_s1                         (mshr_txreq_bypass_qos_s1              ),
                 .mshr_txreq_bypass_txnid_s1                       (mshr_txreq_bypass_txnid_s1            ),
                 .mshr_txreq_bypass_returnnid_s1                   (mshr_txreq_bypass_returnnid_s1        ),
                 .mshr_txreq_bypass_returntxnid_s1                 (mshr_txreq_bypass_returntxnid_s1      ),
                 .mshr_txreq_bypass_opcode_s1                      (mshr_txreq_bypass_opcode_s1           ),
                 .mshr_txreq_bypass_size_s1                        (mshr_txreq_bypass_size_s1             ),
                 .mshr_txreq_bypass_addr_s1                        (mshr_txreq_bypass_addr_s1             ),
                 .mshr_txreq_bypass_ns_s1                          (mshr_txreq_bypass_ns_s1               ),
                 .mshr_txreq_bypass_allowretry_s1                  (mshr_txreq_bypass_allowretry_s1       ),
                 .mshr_txreq_bypass_order_s1                       (mshr_txreq_bypass_order_s1            ),
                 .mshr_txreq_bypass_pcrdtype_s1                    (mshr_txreq_bypass_pcrdtype_s1         ),
                 .mshr_txreq_bypass_memattr_s1                     (mshr_txreq_bypass_memattr_s1          ),
                 .mshr_txreq_bypass_dodwt_s1                       (mshr_txreq_bypass_dodwt_s1            ),
                 .mshr_txreq_bypass_tracetag_s1                    (mshr_txreq_bypass_tracetag_s1         ),
                 .mshr_txreq_valid_sx1_q                       (mshr_txreq_valid_sx1_q            ),
                 .mshr_txreq_qos_sx1                           (mshr_txreq_qos_sx1                ),
                 .mshr_txreq_txnid_sx1_q                       (mshr_txreq_txnid_sx1_q            ),
                 .mshr_txreq_returnnid_sx1                     (mshr_txreq_returnnid_sx1          ),
                 .mshr_txreq_returntxnid_sx1                   (mshr_txreq_returntxnid_sx1        ),
                 .mshr_txreq_opcode_sx1                        (mshr_txreq_opcode_sx1             ),
                 .mshr_txreq_size_sx1                          (mshr_txreq_size_sx1               ),
                 .mshr_txreq_addr_sx1                          (mshr_txreq_addr_sx1               ),
                 .mshr_txreq_ns_sx1                            (mshr_txreq_ns_sx1                 ),
                 .mshr_txreq_allowretry_sx1                    (mshr_txreq_allowretry_sx1         ),
                 .mshr_txreq_order_sx1                         (mshr_txreq_order_sx1              ),
                 .mshr_txreq_pcrdtype_sx1                      (mshr_txreq_pcrdtype_sx1           ),
                 .mshr_txreq_memattr_sx1                       (mshr_txreq_memattr_sx1            ),
                 .mshr_txreq_dodwt_sx1                         (mshr_txreq_dodwt_sx1              ),
                 .mshr_txreq_tracetag_sx1                      (mshr_txreq_tracetag_sx1           ),
                 .txrsp_lcrdv                                  (TXRSPLCRDV                        ),
                 .mshr_txrsp_bypass_valid_s1                       (mshr_txrsp_bypass_valid_s1            ),
                 .mshr_txrsp_bypass_qos_s1                         (mshr_txrsp_bypass_qos_s1              ),
                 .mshr_txrsp_bypass_tgtid_s1                       (mshr_txrsp_bypass_tgtid_s1            ),
                 .mshr_txrsp_bypass_txnid_s1                       (mshr_txrsp_bypass_txnid_s1            ),
                 .mshr_txrsp_bypass_opcode_s1                      (mshr_txrsp_bypass_opcode_s1           ),
                 .mshr_txrsp_bypass_resperr_s1                     (mshr_txrsp_bypass_resperr_s1          ),
                 .mshr_txrsp_bypass_dbid_s1                        (mshr_txrsp_bypass_dbid_s1             ),
                 .mshr_txrsp_bypass_tracetag_s1                    (mshr_txrsp_bypass_tracetag_s1         ),
                 .qos_txrsp_retryack_valid_s1                  (qos_txrsp_retryack_valid_s1       ),
                 .qos_txrsp_retryack_qos_s1                    (qos_txrsp_retryack_qos_s1         ),
                 .qos_txrsp_retryack_tgtid_s1                  (qos_txrsp_retryack_tgtid_s1       ),
                 .qos_txrsp_retryack_txnid_s1                  (qos_txrsp_retryack_txnid_s1       ),
                 .qos_txrsp_retryack_pcrdtype_s1               (qos_txrsp_retryack_pcrdtype_s1    ),
                 .qos_txrsp_retryack_tracetag_s1               (qos_txrsp_retryack_tracetag_s1    ),
                 .qos_txrsp_pcrdgnt_valid_s2                   (qos_txrsp_pcrdgnt_valid_s2        ),
                 .qos_txrsp_pcrdgnt_qos_s2                     (qos_txrsp_pcrdgnt_qos_s2          ),
                 .qos_txrsp_pcrdgnt_tgtid_s2                   (qos_txrsp_pcrdgnt_tgtid_s2        ),
                 .qos_txrsp_pcrdgnt_pcrdtype_s2                (qos_txrsp_pcrdgnt_pcrdtype_s2     ),
                 .mshr_txrsp_valid_sx1_q                       (mshr_txrsp_valid_sx1_q            ),
                 .mshr_txrsp_qos_sx1                           (mshr_txrsp_qos_sx1                ),
                 .mshr_txrsp_tgtid_sx1                         (mshr_txrsp_tgtid_sx1              ),
                 .mshr_txrsp_txnid_sx1_q                       (mshr_txrsp_txnid_sx1_q            ),
                 .mshr_txrsp_opcode_sx1                        (mshr_txrsp_opcode_sx1             ),
                 .mshr_txrsp_resperr_sx1                       (mshr_txrsp_resperr_sx1            ),
                 .mshr_txrsp_resp_sx1                          (mshr_txrsp_resp_sx1               ),
                 .mshr_txrsp_dbid_sx1                          (mshr_txrsp_dbid_sx1               ),
                 .mshr_txrsp_tracetag_sx1                      (mshr_txrsp_tracetag_sx1           ),
                 .txsnp_lcrdv                                  (TXSNPLCRDV                        ),
                 .mshr_txsnp_valid_sx1_q                       (mshr_txsnp_valid_sx1_q            ),
                 .mshr_txsnp_qos_sx1                           (mshr_txsnp_qos_sx1                ),
                 .mshr_txsnp_txnid_sx1_q                       (mshr_txsnp_txnid_sx1_q            ),
                 .mshr_txsnp_fwdnid_sx1                        (mshr_txsnp_fwdnid_sx1             ),
                 .mshr_txsnp_fwdtxnid_sx1                      (mshr_txsnp_fwdtxnid_sx1           ),
                 .mshr_txsnp_opcode_sx1                        (mshr_txsnp_opcode_sx1             ),
                 .mshr_txsnp_addr_sx1                          (mshr_txsnp_addr_sx1               ),
                 .mshr_txsnp_ns_sx1                            (mshr_txsnp_ns_sx1                 ),
                 .mshr_txsnp_rettosrc_sx1                      (mshr_txsnp_rettosrc_sx1           ),
                 .mshr_txsnp_tracetag_sx1                      (mshr_txsnp_tracetag_sx1           ),
                 .mshr_txsnp_rn_vec_sx1                        (mshr_txsnp_rn_vec_sx1             ),
                 .txdat_lcrdv                                  (TXDATLCRDV                        ),
                 .mshr_txdat_tgtid_sx2                         (mshr_txdat_tgtid_sx2              ),
                 .mshr_txdat_txnid_sx2                         (mshr_txdat_txnid_sx2              ),
                 .mshr_txdat_opcode_sx2                        (mshr_txdat_opcode_sx2             ),
                 .mshr_txdat_resp_sx2                          (mshr_txdat_resp_sx2               ),
                 .mshr_txdat_resperr_sx2                       (mshr_txdat_resperr_sx2            ),
                 .mshr_txdat_dbid_sx2                          (mshr_txdat_dbid_sx2               ),
                 .dbf_txdat_data_sx1                           (dbf_txdat_data_sx1_muxed          ),
                 .dbf_txdat_idx_sx1                            (dbf_txdat_idx_sx1                 ),
                 .dbf_txdat_be_sx1                             (dbf_txdat_be_sx1                  ),
                 .dbf_txdat_pe_sx1                             (dbf_txdat_pe_sx1                  ),
                 .dbf_txdat_valid_sx1                          (dbf_txdat_valid_sx1               ),

                 //outputs
                 .rxreq_lcrdv                                  (RXREQLCRDV                        ),
                 .li_mshr_rxreq_valid_s0                       (li_mshr_rxreq_valid_s0            ),
                 .li_mshr_rxreq_qos_s0                         (li_mshr_rxreq_qos_s0              ),
                 .li_mshr_rxreq_srcid_s0                       (li_mshr_rxreq_srcid_s0            ),
                 .li_mshr_rxreq_txnid_s0                       (li_mshr_rxreq_txnid_s0            ),
                 .li_mshr_rxreq_opcode_s0                      (li_mshr_rxreq_opcode_s0           ),
                 .li_mshr_rxreq_size_s0                        (li_mshr_rxreq_size_s0             ),
                 .li_mshr_rxreq_addr_s0                        (li_mshr_rxreq_addr_s0             ),
                 .li_mshr_rxreq_ns_s0                          (li_mshr_rxreq_ns_s0               ),
                 .li_mshr_rxreq_allowretry_s0                  (li_mshr_rxreq_allowretry_s0       ),
                 .li_mshr_rxreq_order_s0                       (li_mshr_rxreq_order_s0            ),
                 .li_mshr_rxreq_pcrdtype_s0                    (li_mshr_rxreq_pcrdtype_s0         ),
                 .li_mshr_rxreq_memattr_s0                     (li_mshr_rxreq_memattr_s0          ),
                 .li_mshr_rxreq_lpid_s0                        (li_mshr_rxreq_lpid_s0             ),
                 .li_mshr_rxreq_excl_s0                        (li_mshr_rxreq_excl_s0             ),
                 .li_mshr_rxreq_expcompack_s0                  (li_mshr_rxreq_expcompack_s0       ),
                 .li_mshr_rxreq_tracetag_s0                    (li_mshr_rxreq_tracetag_s0         ),
                 .rxrsp_lcrdv                                  (RXRSPLCRDV                        ),
                 .li_mshr_rxrsp_valid_s0                       (li_mshr_rxrsp_valid_s0            ),
                 .li_mshr_rxrsp_srcid_s0                       (li_mshr_rxrsp_srcid_s0            ),
                 .li_mshr_rxrsp_txnid_s0                       (li_mshr_rxrsp_txnid_s0            ),
                 .li_mshr_rxrsp_opcode_s0                      (li_mshr_rxrsp_opcode_s0           ),
                 .li_mshr_rxrsp_resp_s0                        (li_mshr_rxrsp_resp_s0             ),
                 .li_mshr_rxrsp_fwdstate_s0                    (li_mshr_rxrsp_fwdstate_s0         ),
                 .li_mshr_rxrsp_dbid_s0                        (li_mshr_rxrsp_dbid_s0             ),
                 .li_mshr_rxrsp_pcrdtype_s0                    (li_mshr_rxrsp_pcrdtype_s0         ),
                 .rxdat_lcrdv                                  (RXDATLCRDV                        ),
                 .li_mshr_rxdat_valid_s0                       (li_mshr_rxdat_valid_s0            ),
                 .li_mshr_rxdat_txnid_s0                       (li_mshr_rxdat_txnid_s0            ),
                 .li_mshr_rxdat_opcode_s0                      (li_mshr_rxdat_opcode_s0           ),
                 .li_mshr_rxdat_resp_s0                        (li_mshr_rxdat_resp_s0             ),
                 .li_mshr_rxdat_fwdstate_s0                    (li_mshr_rxdat_fwdstate_s0         ),
                 .li_mshr_rxdat_dataid_s0                      (li_mshr_rxdat_dataid_s0           ),
                 .li_dbf_rxdat_valid_s0                        (li_dbf_rxdat_valid_s0             ),
                 .li_dbf_rxdat_txnid_s0                        (li_dbf_rxdat_txnid_s0             ),
                 .li_dbf_rxdat_opcode_s0                       (li_dbf_rxdat_opcode_s0            ),
                 .li_dbf_rxdat_dataid_s0                       (li_dbf_rxdat_dataid_s0            ),
                 .li_dbf_rxdat_be_s0                           (li_dbf_rxdat_be_s0                ),
                 .li_dbf_rxdat_data_s0                         (li_dbf_rxdat_data_s0              ),
                 .txreqflitv                                   (TXREQFLITV                        ),
                 .txreqflit                                    (TXREQFLIT                         ),
                 .txreqflitpend                                (TXREQFLITPEND                     ),
                 .txrspflitv                                   (TXRSPFLITV                        ),
                 .txrspflit                                    (TXRSPFLIT                         ),
                 .txrspflitpend                                (TXRSPFLITPEND                     ),
                 .txrsp_mshr_retryack_won_s1                   (txrsp_mshr_retryack_won_s1        ),
                 .txrsp_mshr_pcrdgnt_won_s2                    (txrsp_mshr_pcrdgnt_won_s2         ),
                 .txrsp_mshr_won_sx1                           (txrsp_mshr_won_sx1                ),
                 .txreq_mshr_won_sx1                           (txreq_mshr_won_sx1                ),
                 .txreq_mshr_bypass_won_s1                         (txreq_mshr_bypass_won_s1              ),
                 .txrsp_mshr_bypass_won_s1                         (txrsp_mshr_bypass_won_s1              ),
                 .txsnpflitv                                   (TXSNPFLITV                        ),
                 .txsnpflit                                    (TXSNPFLIT                         ),
                 .txsnpflitpend                                (TXSNPFLITPEND                     ),
                 .txsnp_mshr_busy_sx1                          (txsnp_mshr_busy_sx1               ),
                 .txdatflitv                                   (TXDATFLITV                        ),
                 .txdatflit                                    (TXDATFLIT                         ),
                 .txdatflitpend                                (TXDATFLITPEND                     ),
                 .txdat_mshr_clr_dbf_busy_valid_sx3            (txdat_mshr_clr_dbf_busy_valid_sx3 ),
                 .txdat_mshr_clr_dbf_busy_idx_sx3              (txdat_mshr_clr_dbf_busy_idx_sx3   ),
                 .txdat_mshr_rd_idx_sx2                        (txdat_mshr_rd_idx_sx2             ),
                 .txdat_mshr_busy_sx                           (txdat_mshr_busy_sx                )
             );

    hnf_mshr `HNF_PARAM_INST
             u_hnf_mshr(
                 //inputs
                 .clk                                          (CLK                               ),
                 .rst                                          (RST                               ),
                 .li_mshr_rxreq_valid_s0                       (li_mshr_rxreq_valid_s0            ),
                 .li_mshr_rxreq_qos_s0                         (li_mshr_rxreq_qos_s0              ),
                 .li_mshr_rxreq_srcid_s0                       (li_mshr_rxreq_srcid_s0            ),
                 .li_mshr_rxreq_txnid_s0                       (li_mshr_rxreq_txnid_s0            ),
                 .li_mshr_rxreq_opcode_s0                      (li_mshr_rxreq_opcode_s0           ),
                 .li_mshr_rxreq_size_s0                        (li_mshr_rxreq_size_s0             ),
                 .li_mshr_rxreq_addr_s0                        (li_mshr_rxreq_addr_s0             ),
                 .li_mshr_rxreq_ns_s0                          (li_mshr_rxreq_ns_s0               ),
                 .li_mshr_rxreq_allowretry_s0                  (li_mshr_rxreq_allowretry_s0       ),
                 .li_mshr_rxreq_order_s0                       (li_mshr_rxreq_order_s0            ),
                 .li_mshr_rxreq_pcrdtype_s0                    (li_mshr_rxreq_pcrdtype_s0         ),
                 .li_mshr_rxreq_memattr_s0                     (li_mshr_rxreq_memattr_s0          ),
                 .li_mshr_rxreq_lpid_s0                        (li_mshr_rxreq_lpid_s0             ),
                 .li_mshr_rxreq_excl_s0                        (li_mshr_rxreq_excl_s0             ),
                 .li_mshr_rxreq_expcompack_s0                  (li_mshr_rxreq_expcompack_s0       ),
                 .li_mshr_rxreq_tracetag_s0                    (li_mshr_rxreq_tracetag_s0         ),
                 .txrsp_mshr_retryack_won_s1                   (txrsp_mshr_retryack_won_s1        ),
                 .txrsp_mshr_pcrdgnt_won_s2                    (txrsp_mshr_pcrdgnt_won_s2         ),
                 .txreq_mshr_bypass_won_s1                         (txreq_mshr_bypass_won_s1              ),
                 .txrsp_mshr_bypass_won_s1                         (txrsp_mshr_bypass_won_s1              ),
                 .pipe_mshr_addr_sx2_q                         (pipe_mshr_addr_sx2_q              ),
                 .pipe_mshr_addr_valid_sx2_q                   (pipe_mshr_addr_valid_sx2_q        ),
                 .pipe_mshr_addr_idx_sx2_q                     (pipe_mshr_addr_idx_sx2_q          ),
                 .l3_mshr_entry_sx7_q                          (l3_mshr_entry_sx7_q               ),
                 .l3_evict_sx7_q                               (l3_evict_sx7_q                    ),
                 .l3_evict_addr_sx7_q                          (l3_evict_addr_sx7_q               ),
                 .li_mshr_rxdat_valid_s0                       (li_mshr_rxdat_valid_s0            ),
                 .li_mshr_rxdat_txnid_s0                       (li_mshr_rxdat_txnid_s0            ),
                 .li_mshr_rxdat_opcode_s0                      (li_mshr_rxdat_opcode_s0           ),
                 .li_mshr_rxdat_resp_s0                        (li_mshr_rxdat_resp_s0             ),
                 .li_mshr_rxdat_fwdstate_s0                    (li_mshr_rxdat_fwdstate_s0         ),
                 .li_mshr_rxdat_dataid_s0                      (li_mshr_rxdat_dataid_s0           ),
                 .li_mshr_rxrsp_valid_s0                       (li_mshr_rxrsp_valid_s0            ),
                 .li_mshr_rxrsp_srcid_s0                       (li_mshr_rxrsp_srcid_s0            ),
                 .li_mshr_rxrsp_txnid_s0                       (li_mshr_rxrsp_txnid_s0            ),
                 .li_mshr_rxrsp_opcode_s0                      (li_mshr_rxrsp_opcode_s0           ),
                 .li_mshr_rxrsp_resp_s0                        (li_mshr_rxrsp_resp_s0             ),
                 .li_mshr_rxrsp_fwdstate_s0                    (li_mshr_rxrsp_fwdstate_s0         ),
                 .li_mshr_rxrsp_dbid_s0                        (li_mshr_rxrsp_dbid_s0             ),
                 .li_mshr_rxrsp_pcrdtype_s0                    (li_mshr_rxrsp_pcrdtype_s0         ),
                 .txreq_mshr_won_sx1                           (txreq_mshr_won_sx1                ),
                 .txrsp_mshr_won_sx1                           (txrsp_mshr_won_sx1                ),
                 .txsnp_mshr_busy_sx1                          (txsnp_mshr_busy_sx1               ),
                 .txdat_mshr_busy_sx                           (txdat_mshr_busy_sx                ),
                 .txdat_mshr_rd_idx_sx2                        (txdat_mshr_rd_idx_sx2             ),
                 .txdat_mshr_clr_dbf_busy_valid_sx3            (txdat_mshr_clr_dbf_busy_valid_sx3 ),
                 .txdat_mshr_clr_dbf_busy_idx_sx3              (txdat_mshr_clr_dbf_busy_idx_sx3   ),
                 .l3_opcode_sx7_q                              (l3_opcode_sx7_q                   ),
                 .l3_memrd_sx7_q                               (l3_memrd_sx7_q                    ),
                 .l3_hit_sx7_q                                 (l3_hit_sx7_q                      ),
                 .l3_sfhit_sx7_q                               (l3_sfhit_sx7_q                    ),
                 .l3_pipeval_sx7_q                             (l3_pipeval_sx7_q                  ),
                 .l3_mshr_wr_op_sx7_q                          (l3_mshr_wr_op_sx7_q | ~(&notify_reg)),
                 .l3_snpdirect_sx7_q                           (l3_snpdirect_sx7_q                ),
                 .l3_snpbrd_sx7_q                              (l3_snpbrd_sx7_q                   ),
                 .l3_snp_bit_sx7_q                             (l3_snp_bit_sx7_q                  ),
                 .l3_replay_sx7_q                              (l3_replay_sx7_q                   ),
                 .l3_hit_d_sx7_q                               (l3_hit_d_sx7_q                    ),

                 //outputs
                 .mshr_txrsp_bypass_valid_s1                       (mshr_txrsp_bypass_valid_s1            ),
                 .mshr_txrsp_bypass_qos_s1                         (mshr_txrsp_bypass_qos_s1              ),
                 .mshr_txrsp_bypass_tgtid_s1                       (mshr_txrsp_bypass_tgtid_s1            ),
                 .mshr_txrsp_bypass_txnid_s1                       (mshr_txrsp_bypass_txnid_s1            ),
                 .mshr_txrsp_bypass_opcode_s1                      (mshr_txrsp_bypass_opcode_s1           ),
                 .mshr_txrsp_bypass_resperr_s1                     (mshr_txrsp_bypass_resperr_s1          ),
                 .mshr_txrsp_bypass_dbid_s1                        (mshr_txrsp_bypass_dbid_s1             ),
                 .mshr_txrsp_bypass_tracetag_s1                    (mshr_txrsp_bypass_tracetag_s1         ),
                 .mshr_txreq_bypass_valid_s1                       (mshr_txreq_bypass_valid_s1            ),
                 .mshr_txreq_bypass_qos_s1                         (mshr_txreq_bypass_qos_s1              ),
                 .mshr_txreq_bypass_txnid_s1                       (mshr_txreq_bypass_txnid_s1            ),
                 .mshr_txreq_bypass_returnnid_s1                   (mshr_txreq_bypass_returnnid_s1        ),
                 .mshr_txreq_bypass_returntxnid_s1                 (mshr_txreq_bypass_returntxnid_s1      ),
                 .mshr_txreq_bypass_opcode_s1                      (mshr_txreq_bypass_opcode_s1           ),
                 .mshr_txreq_bypass_size_s1                        (mshr_txreq_bypass_size_s1             ),
                 .mshr_txreq_bypass_addr_s1                        (mshr_txreq_bypass_addr_s1             ),
                 .mshr_txreq_bypass_ns_s1                          (mshr_txreq_bypass_ns_s1               ),
                 .mshr_txreq_bypass_allowretry_s1                  (mshr_txreq_bypass_allowretry_s1       ),
                 .mshr_txreq_bypass_order_s1                       (mshr_txreq_bypass_order_s1            ),
                 .mshr_txreq_bypass_pcrdtype_s1                    (mshr_txreq_bypass_pcrdtype_s1         ),
                 .mshr_txreq_bypass_memattr_s1                     (mshr_txreq_bypass_memattr_s1          ),
                 .mshr_txreq_bypass_dodwt_s1                       (mshr_txreq_bypass_dodwt_s1            ),
                 .mshr_txreq_bypass_tracetag_s1                    (mshr_txreq_bypass_tracetag_s1         ),
                 .qos_txrsp_retryack_valid_s1                  (qos_txrsp_retryack_valid_s1       ),
                 .qos_txrsp_retryack_qos_s1                    (qos_txrsp_retryack_qos_s1         ),
                 .qos_txrsp_retryack_tgtid_s1                  (qos_txrsp_retryack_tgtid_s1       ),
                 .qos_txrsp_retryack_txnid_s1                  (qos_txrsp_retryack_txnid_s1       ),
                 .qos_txrsp_retryack_pcrdtype_s1               (qos_txrsp_retryack_pcrdtype_s1    ),
                 .qos_txrsp_retryack_tracetag_s1               (qos_txrsp_retryack_tracetag_s1    ),
                 .qos_txrsp_pcrdgnt_valid_s2                   (qos_txrsp_pcrdgnt_valid_s2        ),
                 .qos_txrsp_pcrdgnt_qos_s2                     (qos_txrsp_pcrdgnt_qos_s2          ),
                 .qos_txrsp_pcrdgnt_tgtid_s2                   (qos_txrsp_pcrdgnt_tgtid_s2        ),
                 .qos_txrsp_pcrdgnt_pcrdtype_s2                (qos_txrsp_pcrdgnt_pcrdtype_s2     ),
                 .rxreq_retry_enable_s0                        (rxreq_retry_enable_s0             ),
                 .qos_seq_pool_full_s0_q                       (qos_seq_pool_full_s0_q            ),
                 .mshr_txsnp_addr_sx1                          (mshr_txsnp_addr_sx1               ),
                 .mshr_txreq_addr_sx1                          (mshr_txreq_addr_sx1               ),
                 .mshr_l3_hazard_valid_sx3_q                   (mshr_l3_hazard_valid_sx3_q        ),
                 .mshr_l3_addr_sx1                             (mshr_l3_addr_sx1                  ),
                 .mshr_dbf_rd_idx_sx1_q                        (mshr_dbf_rd_idx_sx1_q             ),
                 .mshr_dbf_rd_valid_sx1_q                      (mshr_dbf_rd_valid_sx1_q           ),
                 .mshr_dbf_retired_idx_sx1_q                   (mshr_dbf_retired_idx_sx1_q        ),
                 .mshr_dbf_retired_valid_sx1_q                 (mshr_dbf_retired_valid_sx1_q      ),
                 .mshr_txreq_valid_sx1_q                       (mshr_txreq_valid_sx1_q            ),
                 .mshr_txreq_qos_sx1                           (mshr_txreq_qos_sx1                ),
                 .mshr_txreq_txnid_sx1_q                       (mshr_txreq_txnid_sx1_q            ),
                 .mshr_txreq_returnnid_sx1                     (mshr_txreq_returnnid_sx1          ),
                 .mshr_txreq_returntxnid_sx1                   (mshr_txreq_returntxnid_sx1        ),
                 .mshr_txreq_opcode_sx1                        (mshr_txreq_opcode_sx1             ),
                 .mshr_txreq_size_sx1                          (mshr_txreq_size_sx1               ),
                 .mshr_txreq_ns_sx1                            (mshr_txreq_ns_sx1                 ),
                 .mshr_txreq_allowretry_sx1                    (mshr_txreq_allowretry_sx1         ),
                 .mshr_txreq_order_sx1                         (mshr_txreq_order_sx1              ),
                 .mshr_txreq_pcrdtype_sx1                      (mshr_txreq_pcrdtype_sx1           ),
                 .mshr_txreq_memattr_sx1                       (mshr_txreq_memattr_sx1            ),
                 .mshr_txreq_dodwt_sx1                         (mshr_txreq_dodwt_sx1              ),
                 .mshr_txreq_tracetag_sx1                      (mshr_txreq_tracetag_sx1           ),
                 .mshr_txrsp_valid_sx1_q                       (mshr_txrsp_valid_sx1_q            ),
                 .mshr_txrsp_qos_sx1                           (mshr_txrsp_qos_sx1                ),
                 .mshr_txrsp_tgtid_sx1                         (mshr_txrsp_tgtid_sx1              ),
                 .mshr_txrsp_txnid_sx1_q                       (mshr_txrsp_txnid_sx1_q            ),
                 .mshr_txrsp_opcode_sx1                        (mshr_txrsp_opcode_sx1             ),
                 .mshr_txrsp_resperr_sx1                       (mshr_txrsp_resperr_sx1            ),
                 .mshr_txrsp_resp_sx1                          (mshr_txrsp_resp_sx1               ),
                 .mshr_txrsp_dbid_sx1                          (mshr_txrsp_dbid_sx1               ),
                 .mshr_txrsp_tracetag_sx1                      (mshr_txrsp_tracetag_sx1           ),
                 .mshr_txsnp_valid_sx1_q                       (mshr_txsnp_valid_sx1_q            ),
                 .mshr_txsnp_qos_sx1                           (mshr_txsnp_qos_sx1                ),
                 .mshr_txsnp_txnid_sx1_q                       (mshr_txsnp_txnid_sx1_q            ),
                 .mshr_txsnp_fwdnid_sx1                        (mshr_txsnp_fwdnid_sx1             ),
                 .mshr_txsnp_fwdtxnid_sx1                      (mshr_txsnp_fwdtxnid_sx1           ),
                 .mshr_txsnp_opcode_sx1                        (mshr_txsnp_opcode_sx1             ),
                 .mshr_txsnp_ns_sx1                            (mshr_txsnp_ns_sx1                 ),
                 .mshr_txsnp_rettosrc_sx1                      (mshr_txsnp_rettosrc_sx1           ),
                 .mshr_txsnp_tracetag_sx1                      (mshr_txsnp_tracetag_sx1           ),
                 .mshr_txsnp_rn_vec_sx1                        (mshr_txsnp_rn_vec_sx1             ),
                 .mshr_txdat_tgtid_sx2                         (mshr_txdat_tgtid_sx2              ),
                 .mshr_txdat_txnid_sx2                         (mshr_txdat_txnid_sx2              ),
                 .mshr_txdat_opcode_sx2                        (mshr_txdat_opcode_sx2             ),
                 .mshr_txdat_resp_sx2                          (mshr_txdat_resp_sx2               ),
                 .mshr_txdat_resperr_sx2                       (mshr_txdat_resperr_sx2            ),
                 .mshr_txdat_dbid_sx2                          (mshr_txdat_dbid_sx2               ),
                 .mshr_l3_fill_sx1_q                           (mshr_l3_fill_sx1_q                ),
                 .mshr_l3_rnf_sx1_q                            (mshr_l3_rnf_sx1_q                 ),
                 .mshr_l3_seq_retire_sx1_q                     (mshr_l3_seq_retire_sx1_q          ),
                 .mshr_l3_opcode_sx1_q                         (mshr_l3_opcode_sx1_q              ),
                 .mshr_l3_req_en_sx1_q                         (mshr_l3_req_en_sx1_q              ),
                 .mshr_l3_entry_idx_sx1_q                      (mshr_l3_entry_idx_sx1_q           ),
                 .mshr_l3_fill_dirty_sx1_q                     (mshr_l3_fill_dirty_sx1_q          ),
                 .mshr_atomic_active_vec_sx1_q                 (mshr_atomic_active_vec_sx1_q      ),
                 .mshr_atomic_memwr_pending_vec_sx1_q          (mshr_atomic_memwr_pending_vec_sx1_q),
                 .mshr_rn_data_busy_vec_sx_q                   (mshr_rn_data_busy_vec_sx_q       ),
                 .mshr_sn_data_busy_vec_sx_q                   (mshr_sn_data_busy_vec_sx_q       ),
                 .mshr_atomic_op_vec_sx1_q                     (mshr_atomic_op_vec_sx1_q         )
             );

    hnf_cache_pipeline `HNF_PARAM_INST
                       u_hnf_cache_pipeline(
                           //inputs
                           .clk                                          (CLK                               ),
                           .rst                                          (RST                               ),
                           .mshr_l3_req_en_sx1_q                         (mshr_l3_req_en_sx1_q & (&notify_reg)),
                           .mshr_l3_addr_sx1                             (mshr_l3_addr_sx1                  ),
                           .mshr_l3_entry_idx_sx1_q                      (mshr_l3_entry_idx_sx1_q           ),
                           .mshr_l3_fill_sx1_q                           (mshr_l3_fill_sx1_q                ),
                           .mshr_l3_opcode_sx1_q                         (mshr_l3_opcode_sx1_q              ),
                           .mshr_l3_rnf_sx1_q                            (mshr_l3_rnf_sx1_q                 ),
                           .mshr_l3_fill_dirty_sx1_q                     (mshr_l3_fill_dirty_sx1_q          ),
                           .mshr_l3_seq_retire_sx1_q                     (mshr_l3_seq_retire_sx1_q          ),
                           .loc_rd_clines_q                              (loc_rd_clines_q                   ),
                           .sf_rd_clines_q                               (sf_rd_clines_q                    ),
                           .lru_rd_data_q                                (lru_rd_data_q                     ),
                           .mshr_l3_hazard_valid_sx3_q                   (mshr_l3_hazard_valid_sx3_q        ),

                           //outputs
                           .loc_index_q                                  (cpl_loc_index_q                   ),
                           .loc_rd_en_q                                  (cpl_loc_rd_en_q                   ),
                           .loc_wr_ways_q                                (cpl_loc_wr_ways_q                 ),
                           .loc_wr_cline_q                               (cpl_loc_wr_cline_q                ),
                           .sf_index_q                                   (cpl_sf_index_q                    ),
                           .sf_rd_en_q                                   (cpl_sf_rd_en_q                    ),
                           .sf_wr_ways_q                                 (cpl_sf_wr_ways_q                  ),
                           .sf_wr_cline_q                                (cpl_sf_wr_cline_q                 ),
                           .l3_index_q                                   (cpl_l3_index_q                    ),
                           .l3_rd_ways_q                                 (cpl_l3_rd_ways_q                  ),
                           .l3_wr_ways_q                                 (cpl_l3_wr_ways_q                  ),
                           .lru_index_q                                  (cpl_lru_index_q                   ),
                           .lru_rd_en_q                                  (cpl_lru_rd_en_q                   ),
                           .lru_wr_en_q                                  (cpl_lru_wr_en_q                   ),
                           .lru_wr_data_q                                (cpl_lru_wr_data_q                 ),
                           .pipe_mshr_addr_sx5_q                         (pipe_mshr_addr_sx2_q              ),
                           .pipe_mshr_addr_valid_sx5_q                   (pipe_mshr_addr_valid_sx2_q        ),
                           .pipe_mshr_addr_idx_sx5_q                     (pipe_mshr_addr_idx_sx2_q          ),
                           .l3_evict_addr_sx7_q                          (l3_evict_addr_sx7_q               ),
                           .l3_evict_sx7_q                               (l3_evict_sx7_q                    ),
                           .l3_mshr_entry_sx7_q                          (l3_mshr_entry_sx7_q               ),
                           .biq_req_valid_s0_q                           (biq_req_valid_s0_q                ),
                           .biq_req_addr_s0_q                            (biq_req_addr_s0_q                 ),
                           .l3_pipeval_sx7_q                             (l3_pipeval_sx7_q                  ),
                           .l3_opcode_sx7_q                              (l3_opcode_sx7_q                   ),
                           .l3_memrd_sx7_q                               (l3_memrd_sx7_q                    ),
                           .l3_hit_sx7_q                                 (l3_hit_sx7_q                      ),
                           .l3_hit_dirty_sx7_q                           (l3_hit_d_sx7_q                    ),
                           .l3_sfhit_sx7_q                               (l3_sfhit_sx7_q                    ),
                           .l3_snpdirect_sx7_q                           (l3_snpdirect_sx7_q                ),
                           .l3_snpbrd_sx7_q                              (l3_snpbrd_sx7_q                   ),
                           .l3_snp_bit_sx7_q                             (l3_snp_bit_sx7_q                  ),
                           .l3_replay_sx7_q                              (l3_replay_sx7_q                   ),
                           .l3_mshr_wr_op_sx7_q                          (l3_mshr_wr_op_sx7_q               ),
                           .pipe_dbf_wr_valid_sx9_q                      (pipe_dbf_wr_valid_sx9_q           ),
                           .pipe_dbf_wr_idx_sx9_q                        (pipe_dbf_wr_idx_sx9_q             ),
                           .pipe_dbf_rd_idx_valid_sx6_q                  (pipe_dbf_rd_idx_sx2_valid_q       ),
                           .pipe_dbf_rd_idx_sx6_q                        (pipe_dbf_rd_idx_sx2_q             )
                       );

    hnf_data_buffer `HNF_PARAM_INST
                    u_hnf_data_buffer(
                        //inputs
                        .clk                                          (CLK                               ),
                        .rst                                          (RST                               ),
                        .li_dbf_rxdat_valid_s0                        (li_dbf_rxdat_valid_s0             ),
                        .li_dbf_rxdat_txnid_s0                        (li_dbf_rxdat_txnid_s0             ),
                        .li_dbf_rxdat_opcode_s0                       (li_dbf_rxdat_opcode_s0            ),
                        .li_dbf_rxdat_dataid_s0                       (li_dbf_rxdat_dataid_s0            ),
                        .li_dbf_rxdat_be_s0                           (li_dbf_rxdat_be_s0                ),
                        .li_dbf_rxdat_data_s0                         (li_dbf_rxdat_data_s0              ),
                        .mshr_dbf_rd_idx_sx1_q                        (mshr_dbf_rd_idx_sx1_q             ),
                        .mshr_dbf_rd_valid_sx1_q                      (mshr_dbf_rd_valid_sx1_q           ),
                        .mshr_dbf_retired_idx_sx1_q                   (mshr_dbf_retired_idx_sx1_q        ),
                        .mshr_dbf_retired_valid_sx1_q                 (mshr_dbf_retired_valid_sx1_q      ),
                        .pipe_dbf_wr_valid_sx9_q                      (pipe_dbf_wr_valid_sx9_q           ),
                        .pipe_dbf_wr_idx_sx9_q                        (pipe_dbf_wr_idx_sx9_q             ),
                        .pipe_dbf_wr_data_sx9_q                       (l3_rd_data_q                      ),
                        .pipe_dbf_rd_idx_sx2_q                        (pipe_dbf_rd_idx_sx2_q             ),
                        .pipe_dbf_rd_idx_sx2_valid_q                  (pipe_dbf_rd_idx_sx2_valid_q       ),

                        //outputs
                        .dbf_pipe_rd_data_sx7_q                       (dbf_l3_wr_data_q                  ),
                        .dbf_txdat_valid_sx1                          (dbf_txdat_valid_sx1               ),
                        .dbf_txdat_idx_sx1                            (dbf_txdat_idx_sx1                 ),
                        .dbf_txdat_be_sx1                             (dbf_txdat_be_sx1                  ),
                        .dbf_txdat_pe_sx1                             (dbf_txdat_pe_sx1                  ),
                        .dbf_txdat_data_sx1                           (dbf_txdat_data_sx1                )
                    );

    hnf_sf_sram `HNF_PARAM_INST
                u_hnf_sf_sram(
                    //inputs
                    .clk                                          (CLK                               ),
                    .rst                                          (RST                               ),
                    .sf_index_q                                   (sf_index_q                        ),
                    .sf_rd_en_q                                   (sf_rd_en_q                        ),
                    .sf_wr_ways_q                                 (sf_wr_ways_q                      ),
                    .sf_wr_cline_q                                (sf_wr_cline_q                     ),
                    //outputs
                    .sf_rd_clines_q                               (sf_rd_clines_q                    )
                );

    hnf_tag_sram `HNF_PARAM_INST
                 u_hnf_tag_sram(
                     //inputs
                     .clk                                          (CLK                               ),
                     .rst                                          (RST                               ),
                     .loc_index_q                                  (loc_index_q                       ),
                     .loc_rd_en_q                                  (loc_rd_en_q                       ),
                     .loc_wr_ways_q                                (loc_wr_ways_q                     ),
                     .loc_wr_cline_q                               (loc_wr_cline_q                    ),
                     //outputs
                     .loc_rd_clines_q                              (loc_rd_clines_q                   )
                 );

    hnf_lru_sram `HNF_PARAM_INST
                 u_hnf_lru_sram(
                     //inputs
                     .clk                                          (CLK                               ),
                     .rst                                          (RST                               ),
                     .lru_index_q                                  (lru_index_q                       ),
                     .lru_rd_en_q                                  (lru_rd_en_q                       ),
                     .lru_wr_en_q                                  (lru_wr_en_q                       ),
                     .lru_wr_data_q                                (lru_wr_data_q                     ),
                     //outputs
                     .lru_rd_data_q                                (lru_rd_data_q                     )
                 );

    hnf_data_sram `HNF_PARAM_INST
                  u_hnf_data_sram(
                      //inputs
                      .clk                                          (CLK                               ),
                      .rst                                          (RST                               ),
                      .l3_index_q                                   (l3_index_q                        ),
                      .l3_rd_ways_q                                 (l3_rd_ways_q                      ),
                      .l3_wr_data_q                                 (l3_wr_data_q                      ),
                      .l3_wr_ways_q                                 (l3_wr_ways_q                      ),
                      //outputs
                      .l3_rd_data_q                                 (l3_rd_data_q                      )
                  );

    // ════════════════════════════════════════════════════════════════════════
    // P5 -- atomic ALU insertion (structural; full per-entry timing alignment
    // is a follow-on refinement, see TODO below).
    //
    // For atomic transactions:
    //   cur_value  := l3_rd_data_q       (current line read from L3)
    //   operand    := dbf_l3_wr_data_q   (RN-F TX DAT value sitting in data
    //                                     buffer, normally about to be written
    //                                     back to L3 verbatim)
    //   new_value  := ALU(cur, operand)  (replaces dbf_l3_wr_data_q on its
    //                                     way to hnf_mem_ctl)
    //
    // Gating: any MSHR entry being processed as atomic toggles the mux on
    // for *every* L3 write that cycle.  This is correct only when
    // simulations avoid interleaving atomics with other writes -- safe for
    // single-atomic testing, NOT safe in general traffic.
    //
    // TODO P5b -- propagate pipe_dbf_rd_idx_sx2_q through 5 stages to
    // produce dbf_rd_idx_at_l3wr_sx7_q, then gate the mux with
    // mshr_atomic_active_vec_sx1_q[dbf_rd_idx_at_l3wr_sx7_q] so only the
    // atomic transaction's write goes through the ALU.
    //
    // TODO P5c -- thread `atomic_op` and `addr_lo` from the MSHR.  Today
    // both are hardcoded (ADD on 8B at offset 0), so any AtomicLoad/Store
    // collapses to "L3[entry] += operand[63:0]".
    // ════════════════════════════════════════════════════════════════════════

    wire [`CACHE_LINE_WIDTH-1:0] alu_new_value;
    wire [`CACHE_LINE_WIDTH-1:0] alu_returned;     // unused today; P6
    wire                         any_atomic_active = |mshr_atomic_active_vec_sx1_q;
    // Forward-declared so the ALU instance below can reference it; the
    // FFs that drive them are at the "P6b" comment block further down.
    reg [`CHIE_DAT_FLIT_DATA_WIDTH-1:0] atomic_old_data_q;       // beat 0 (bytes 0-31)
    reg [`CHIE_DAT_FLIT_DATA_WIDTH-1:0] atomic_old_data_beat1_q; // beat 1 (bytes 32-63)
    reg [`CHIE_DAT_FLIT_DATA_WIDTH-1:0] atomic_operand_data_q;
    wire [`CACHE_LINE_WIDTH-1:0] dbf_l3_wr_data_q_muxed =
                                 any_atomic_active ? alu_new_value : dbf_l3_wr_data_q;

    // P6 -- ALU cur_value sourced from the SN-F-CompData latch
    // atomic_old_data_q (the OLD value).  Previously we tied this to
    // l3_rd_data_q, but atomics don't engage the L3 read pipeline in
    // this minimum-viable wiring, so l3_rd_data_q is stale.  Splice the
    // 256-bit beat-0 latch into the LSB lane; upper bytes pass through
    // from the data buffer (the SN-F memwr below uses alu_new_value
    // directly, so upper-byte freshness only matters for byte lanes
    // we are not touching -- which atomic_old_data_q carries verbatim
    // for beat 0).
    // P6 -- select atomic_op from the currently-active atomic entry.
    // For a single in-flight atomic, this OR-reduce-by-mask picks out the
    // 4-bit op of whichever entry is active.  Multi-atomic interleaving
    // would need per-flit-index gating (TODO).
    wire [3:0] alu_atomic_op_sel;
    genvar alu_op_gi;
    wire [3:0] alu_op_per_entry [HNF_MSHR_ENTRIES_NUM_PARAM-1:0];
    generate
        for(alu_op_gi=0; alu_op_gi<HNF_MSHR_ENTRIES_NUM_PARAM;
            alu_op_gi=alu_op_gi+1) begin : alu_op_unpack
            assign alu_op_per_entry[alu_op_gi] =
                mshr_atomic_active_vec_sx1_q[alu_op_gi] ?
                    mshr_atomic_op_vec_sx1_q[alu_op_gi*4 +: 4] : 4'h0;
        end
    endgenerate
    // Per-entry OR-reduce: legal because at most one bit of
    // mshr_atomic_active_vec_sx1_q is set in single-atomic mode.
    reg [3:0] alu_op_or;
    integer alu_op_idx;
    always @* begin
        alu_op_or = 4'h0;
        for(alu_op_idx=0; alu_op_idx<HNF_MSHR_ENTRIES_NUM_PARAM;
            alu_op_idx=alu_op_idx+1)
            alu_op_or = alu_op_or | alu_op_per_entry[alu_op_idx];
    end
    assign alu_atomic_op_sel = alu_op_or;

    hnf_atomic_alu #(
        .DATA_WIDTH (`CACHE_LINE_WIDTH),
        .LANE_WIDTH (64)
    ) u_hnf_atomic_alu (
        // Full cache line from both SN-F CompData beats so non-target
        // lanes pass through with the original memory contents (not zero).
        .cur_value   ({atomic_old_data_beat1_q, atomic_old_data_q}),
        .operand     ({{(`CACHE_LINE_WIDTH-`CHIE_DAT_FLIT_DATA_WIDTH){1'b0}},
                      atomic_operand_data_q}),
        .compare_val ({`CACHE_LINE_WIDTH{1'b0}}),    // reserved
        .addr_lo     (5'b0),                         // TODO P5c: thread from MSHR
        .atomic_op   (alu_atomic_op_sel),            // ATOMIC_OP_ADD or SWAP
        .new_value   (alu_new_value),
        .returned    (alu_returned)
    );

    // ════════════════════════════════════════════════════════════════════════
    // P5/P6b -- AtomicLoad CompData data-path fix
    //
    // The RN-F's operand TX DAT lands in the same data_buffer slot that
    // (later) gets the L3 read fill via pipe_dbf_wr_data_sx9_q.  When TX
    // DAT fires for AtomicLoad's CompData, dbf_txdat_data_sx1 carries
    // whatever the buffer holds -- which may be the operand (overwritten
    // the L3 data) or vice versa, depending on order.  In the smoke test
    // we observed only the operand's low byte (0x11) coming back.
    //
    // Fix: latch l3_rd_data_q the cycle the L3 read result is written
    // into the buffer (pipe_dbf_wr_valid_sx9_q), and mux that latched
    // value over dbf_txdat_data_sx1 while any atomic is active.
    //
    // Limitations (P5b/c follow-on):
    //   - Single in-flight atomic only (one latch, not per-MSHR-entry).
    //   - For AtomicStore the response is Comp (TX_RSP) so this mux is
    //     a no-op for it.
    //   - Doesn't yet route alu_returned with proper byte-lane placement.
    // ════════════════════════════════════════════════════════════════════════

    // Latch l3_rd_data_q on every cycle the L3 SRAM produced a non-zero
    // read (any read is captured; for a single in-flight atomic this is
    // the atomic's L3 line).  The pipe_dbf_wr_valid_sx9_q gate proved too
    // restrictive for atomics (cache_pipeline doesn't fire it for atomic
    // ops), so use a coarser capture: latch whenever l3_rd_data_q is
    // non-zero while any atomic is active.
    reg [`CACHE_LINE_WIDTH-1:0] atomic_l3_data_q;
    always @(posedge CLK or posedge RST) begin
        if (RST)
            atomic_l3_data_q <= {`CACHE_LINE_WIDTH{1'b0}};
        else if (any_atomic_active & (|l3_rd_data_q))
            atomic_l3_data_q <= l3_rd_data_q;
    end

    // ════════════════════════════════════════════════════════════════════════
    // P6b -- AtomicLoad CompData data-path correction (Gap 1)
    //
    // Capture the SN-F CompData payload BEFORE the operand RX DAT arrives
    // and overwrites the data-buffer slot.  Triggered by:
    //   li_mshr_rxdat_valid_s0
    //   & li_mshr_rxdat_opcode_s0 == CHIE_COMPDATA
    //   & the addressed MSHR entry is atomic
    //
    // Stored as a per-MSHR-entry array so multiple in-flight atomics work.
    // (For now we still drive a single 256-bit slice to TX DAT via
    // any_atomic_active; per-entry indexing into TX DAT can come later.)
    // ════════════════════════════════════════════════════════════════════════

    // Single-slot capture (sufficient while only one atomic is in flight).
    // Triggered on ANY incoming CompData while an atomic is active --
    // assumes the only CompData in flight during atomic activity is for
    // that atomic.  Safe for the smoke test.
    //
    // P6 -- Only latch beat 0 (DataID=0).  For full-line CompData (size=6)
    // the SN-F sends two beats; beat 0 holds bytes [0:31] (offset-0 lane
    // for our 8B atomics), beat 1 holds bytes [32:63] (wrong lane).
    // Latching beat 1 last produced the prior "old=0x3837363534333231"
    // miscompare against the seed at bytes 0-7.
    // (atomic_old_data_q declared above so the ALU can reference it.)
    always @(posedge CLK or posedge RST) begin
        if (RST)
            atomic_old_data_q <= {`CHIE_DAT_FLIT_DATA_WIDTH{1'b0}};
        else if (li_mshr_rxdat_valid_s0
                 & (li_mshr_rxdat_opcode_s0 == `CHIE_COMPDATA)
                 & any_atomic_active
                 & (li_mshr_rxdat_dataid_s0 == 2'b00))
            atomic_old_data_q <= li_dbf_rxdat_data_s0;
    end

    // P6 -- Mirror latch for beat 1 (DataID=2) so the ALU sees the full
    // 64B cache line.  Without this, bytes 32-63 of atomic memwr came
    // out as zero (ALU's "pass-through" preserves cur_value lanes,
    // which were padded with zeros).
    always @(posedge CLK or posedge RST) begin
        if (RST)
            atomic_old_data_beat1_q <= {`CHIE_DAT_FLIT_DATA_WIDTH{1'b0}};
        else if (li_mshr_rxdat_valid_s0
                 & (li_mshr_rxdat_opcode_s0 == `CHIE_COMPDATA)
                 & any_atomic_active
                 & (li_mshr_rxdat_dataid_s0 == 2'b10))
            atomic_old_data_beat1_q <= li_dbf_rxdat_data_s0;
    end

    // P6 -- Latch the RN-F-supplied operand (NonCopyBkWrData beat 0) into a
    // dedicated register.  The data-buffer slot for the entry is shared
    // between the SN-F memrd response and the RN-F operand, so each
    // overwrites the other; the ALU needs both inputs simultaneously, so
    // we capture into a separate latch (mirroring atomic_old_data_q).
    always @(posedge CLK or posedge RST) begin
        if (RST)
            atomic_operand_data_q <= {`CHIE_DAT_FLIT_DATA_WIDTH{1'b0}};
        else if (li_mshr_rxdat_valid_s0
                 & ((li_mshr_rxdat_opcode_s0 == `CHIE_NONCOPYBACKWRDATA) |
                    (li_mshr_rxdat_opcode_s0 == `CHIE_NCBWRDATACOMPACK))
                 & any_atomic_active
                 & (li_mshr_rxdat_dataid_s0 == 2'b00))
            atomic_operand_data_q <= li_dbf_rxdat_data_s0;
    end

    // P6 -- TX DAT data path mux for atomic transactions.  Three cases:
    //
    //   (a) atomic active && memwr-pending (TX REQ for SN-F memwr won):
    //         send the ALU's NEW value (alu_new_value) so memory commits
    //         OLD + operand.
    //   (b) atomic active && not memwr-pending (RN-F-facing CompData):
    //         send the latched OLD value (atomic_old_data_q) so the
    //         requester sees the pre-RMW state.
    //   (c) non-atomic: pass through dbf_txdat_data_sx1 unchanged.
    //
    // memwr-pending is exposed from hnf_mshr_ctl as a per-entry vector
    // (mshr_atomic_memwr_pending_vec_sx1_q).  We OR it across all entries
    // because dbf_txdat_data_sx1_muxed is sampled into the TX DAT wrap's
    // slot register at slot-alloc time; that sampling cycle is when this
    // mux's value matters.  For a single in-flight atomic this is exact;
    // multi-atomic interleaving needs per-flit index awareness (TODO).
    //
    // alu_new_value is a full 512-bit cache-line; for our 8B-at-offset-0
    // atomic the modified lane is in bits [63:0], the rest of the line
    // is OLD (preserved by the ALU's "non-target lanes pass through"
    // behavior -- see hnf_atomic_alu.sv).
    // P6 -- distinguish RN-F-bound CompData slot capture from SN-F-bound
    // memwr slot capture.  An atomic entry whose sn_data_busy=1 is being
    // read out for SN-F memwr -> use ALU's NEW value.  An atomic entry
    // whose rn_data_busy=1 (but sn_data_busy=0) is being read out for
    // RN-F CompData -> use latched OLD value.  Priority: SN-F first
    // (because rn_data_busy may still be set at slot2 capture time
    // -- rn_data_busy clears at SX3 of TX DAT wrap, after slot1 emit,
    // which may be AFTER slot2 already captured its data).
    wire any_atomic_sn_active = |(mshr_atomic_active_vec_sx1_q &
                                  mshr_sn_data_busy_vec_sx_q);
    wire any_atomic_rn_active = |(mshr_atomic_active_vec_sx1_q &
                                  mshr_rn_data_busy_vec_sx_q);
    assign dbf_txdat_data_sx1_muxed =
        any_atomic_active
            ? (any_atomic_sn_active
                ? alu_new_value
                : (any_atomic_rn_active
                    ? {dbf_txdat_data_sx1[`CHIE_DAT_FLIT_DATA_WIDTH*2-1 :
                                          `CHIE_DAT_FLIT_DATA_WIDTH],
                       atomic_old_data_q}
                    : dbf_txdat_data_sx1))
            : dbf_txdat_data_sx1;


    hnf_mem_ctl `HNF_PARAM_INST
                u_hnf_mem_ctl(
                    //inputs
                    .clk                                          (CLK                               ),
                    .rst                                          (RST                               ),
                    //ouputs
                    .sf_index_q                                   (sf_index_q                        ),
                    .sf_rd_en_q                                   (sf_rd_en_q                        ),
                    .sf_wr_ways_q                                 (sf_wr_ways_q                      ),
                    .sf_wr_cline_q                                (sf_wr_cline_q                     ),
                    .loc_index_q                                  (loc_index_q                       ),
                    .loc_rd_en_q                                  (loc_rd_en_q                       ),
                    .loc_wr_ways_q                                (loc_wr_ways_q                     ),
                    .loc_wr_cline_q                               (loc_wr_cline_q                    ),
                    .lru_index_q                                  (lru_index_q                       ),
                    .lru_rd_en_q                                  (lru_rd_en_q                       ),
                    .lru_wr_en_q                                  (lru_wr_en_q                       ),
                    .lru_wr_data_q                                (lru_wr_data_q                     ),
                    .l3_index_q                                   (l3_index_q                        ),
                    .l3_rd_ways_q                                 (l3_rd_ways_q                      ),
                    .l3_wr_data_q                                 (l3_wr_data_q                      ),
                    .l3_wr_ways_q                                 (l3_wr_ways_q                      ),
                    .notify_reg                                   (notify_reg                        ),
`ifdef tb_hnf
                    .dbg_l3_valid_q                               (dbg_l3_valid_q                    ),
                    .dbg_l3_index_q                               (dbg_l3_index_q                    ),
                    .dbg_l3_rd_ways_q                             (dbg_l3_rd_ways_q                  ),
                    .dbg_l3_wr_data_q                             (dbg_l3_wr_data_q                  ),
                    .dbg_l3_wr_ways_q                             (dbg_l3_wr_ways_q                  ),
                    .dbg_loc_valid_q                              (dbg_loc_valid_q                   ),
                    .dbg_loc_index_q                              (dbg_loc_index_q                   ),
                    .dbg_loc_rd_en_q                              (dbg_loc_rd_en_q                   ),
                    .dbg_loc_wr_ways_q                            (dbg_loc_wr_ways_q                 ),
                    .dbg_loc_wr_cline_q                           (dbg_loc_wr_cline_q                ),
                    .dbg_sf_valid_q                               (dbg_sf_valid_q                    ),
                    .dbg_sf_index_q                               (dbg_sf_index_q                    ),
                    .dbg_sf_rd_en_q                               (dbg_sf_rd_en_q                    ),
                    .dbg_sf_wr_ways_q                             (dbg_sf_wr_ways_q                  ),
                    .dbg_sf_wr_cline_q                            (dbg_sf_wr_cline_q                 ),
                    .dbg_lru_valid_q                              (dbg_lru_valid_q                   ),
                    .dbg_lru_index_q                              (dbg_lru_index_q                   ),
                    .dbg_lru_rd_en_q                              (dbg_lru_rd_en_q                   ),
                    .dbg_lru_wr_en_q                              (dbg_lru_wr_en_q                   ),
                    .dbg_lru_wr_data_q                            (dbg_lru_wr_data_q                 ),
                    .dbg_l3_rd_data_q                             (dbg_l3_rd_data_q                  ),
                    .dbg_lru_rd_data_q                            (dbg_lru_rd_data_q                 ),
                    .dbg_loc_rd_clines_q                          (dbg_loc_rd_clines_q               ),
                    .dbg_sf_rd_clines_q                           (dbg_sf_rd_clines_q                ),
                    .loc_rd_clines_q                              (loc_rd_clines_q                   ),
                    .sf_rd_clines_q                               (sf_rd_clines_q                    ),
                    .l3_rd_data_q                                 (l3_rd_data_q                      ),
                    .lru_rd_data_q                                (lru_rd_data_q                     ),
`endif
                    .cpl_l3_index_q                               (cpl_l3_index_q                    ),
                    .cpl_l3_rd_ways_q                             (cpl_l3_rd_ways_q                  ),
                    .dbf_l3_wr_data_q                             (dbf_l3_wr_data_q_muxed            ),
                    .cpl_l3_wr_ways_q                             (cpl_l3_wr_ways_q                  ),
                    .cpl_loc_index_q                              (cpl_loc_index_q                   ),
                    .cpl_loc_rd_en_q                              (cpl_loc_rd_en_q                   ),
                    .cpl_loc_wr_ways_q                            (cpl_loc_wr_ways_q                 ),
                    .cpl_loc_wr_cline_q                           (cpl_loc_wr_cline_q                ),
                    .cpl_sf_index_q                               (cpl_sf_index_q                    ),
                    .cpl_sf_rd_en_q                               (cpl_sf_rd_en_q                    ),
                    .cpl_sf_wr_ways_q                             (cpl_sf_wr_ways_q                  ),
                    .cpl_sf_wr_cline_q                            (cpl_sf_wr_cline_q                 ),
                    .cpl_lru_index_q                              (cpl_lru_index_q                   ),
                    .cpl_lru_rd_en_q                              (cpl_lru_rd_en_q                   ),
                    .cpl_lru_wr_en_q                              (cpl_lru_wr_en_q                   ),
                    .cpl_lru_wr_data_q                            (cpl_lru_wr_data_q                 )
                );

endmodule
