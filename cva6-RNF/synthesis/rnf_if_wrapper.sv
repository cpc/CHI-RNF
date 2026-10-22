/* RNF interface wrapper */


//`timescale 1 ns / 10 ps
//`include "../../include/l15.tmp.h"
`include "l15.tmp.h"
//`include "../../include/lsu.tmp.h"
`include "lsu.tmp.h"
`include "rnf_param.v"
`include "rnf_defines.v"
`include "chie_defines.v"


module rnf_if_wrapper `RNF_PARAM (
    input                                   clk,
    input                                   rst_n,
    


    // Signals still in the modules

    // from txreq
    output                                  l15_dmbr_l1missIn,
    output [`DMBR_TAG_WIDTH-1:0]            l15_dmbr_l1missTag,
    input                                   dmbr_l15_stall,
    
    input [`NOC_CHIPID_WIDTH-1:0]           chipid,
    input [`NOC_X_WIDTH-1:0]                coreid_x,
    input [`NOC_Y_WIDTH-1:0]                coreid_y,

    // CHI interface

    // INPUTS
    // from response channel
    input RXRSPFLITV,
    input [`CHIE_RSP_FLIT_RANGE] RXRSPFLIT,
    input RXRSPFLITPEND,
    // from data channel
    input RXDATFLITV,
    input [`CHIE_DAT_FLIT_RANGE] RXDATFLIT,     // w:406
    input RXDATFLITPEND,
    // to snoop channel
    input RXSNPFLITV,
    input [`CHIE_SNP_FLIT_RANGE] RXSNPFLIT,
    input RXSNPFLITPEND,

    // Credits back from responder?
    input TXREQLCRDV,
    input TXRSPLCRDV,
    input TXDATLCRDV,

    // OUTPUTS
    // Credits to requestor
    output RXRSPLCRDV,
    output RXDATLCRDV,
    output RXSNPLCRDV,
    // to request channel
    output TXREQFLITV,
    output [`CHIE_REQ_FLIT_RANGE] TXREQFLIT,    // w:131
    output TXREQFLITPEND,
    // response channel
    output TXRSPFLITV,
    output [`CHIE_RSP_FLIT_RANGE] TXRSPFLIT,
    output TXRSPFLITPEND,
    // to data channel
    output TXDATFLITV,
    output [`CHIE_DAT_FLIT_RANGE] TXDATFLIT,
    output TXDATFLITPEND,

    output  TXLINKACTIVEREQ,
    input   TXLINKACTIVEACK,
    input   RXLINKACTIVEREQ,
    output  RXLINKACTIVEACK,
    output  TXACTIVE,
    input   RXACTIVE,

    // OP L1.5 to IF
    input [`MSG_SDID_WIDTH-1:0] noc1buffer_noc1encoder_req_csm_sdid,
    input [`MSG_LSID_WIDTH-1:0] noc1buffer_noc1encoder_req_csm_lsid,
    input [`L15_NOC1_REQTYPE_WIDTH-1:0] noc1buffer_noc1encoder_req_type,
    input [`L15_THREADID_MASK] noc1buffer_noc1encoder_req_threadid,
    input [`L15_MSHR_ID_WIDTH-1:0] noc1buffer_noc1encoder_req_mshrid,
    input [`L15_PADDR_HI:0] noc1buffer_noc1encoder_req_address,
    input noc1buffer_noc1encoder_req_non_cacheable,
    input [2:0] noc1buffer_noc1encoder_req_size,
    input noc1buffer_noc1encoder_req_prefetch,
    input [63:0] noc1buffer_noc1encoder_req_data_0,
    input [63:0] noc1buffer_noc1encoder_req_data_1,
    input [`PACKET_HOME_ID_WIDTH-1:0] noc1buffer_noc1encoder_req_homeid,
    output noc1encoder_noc1buffer_req_ack,
    input noc1buffer_noc1encoder_req_val,
    output noc1encoder_csm_req_ack,
    input csm_noc1encoder_req_val,
    input [`L15_NOC1_REQTYPE_WIDTH-1:0] csm_noc1encoder_req_type,
    input [`L15_CSM_NUM_TICKETS_LOG2-1:0] csm_noc1encoder_req_mshrid,
    input [`PHY_ADDR_WIDTH-1:0] csm_noc1encoder_req_address,
    input csm_noc1encoder_req_non_cacheable,
    input  [`PCX_SIZE_WIDTH-1:0] csm_noc1encoder_req_size,


    output noc3encoder_noc3buffer_req_ack,
    input noc3buffer_noc3encoder_req_val,
    input [`L15_NOC3_REQTYPE_WIDTH-1:0] noc3buffer_noc3encoder_req_type,
    input [63:0] noc3buffer_noc3encoder_req_data_0,
    input [63:0] noc3buffer_noc3encoder_req_data_1,
    input [`L15_MSHR_ID_WIDTH-1:0] noc3buffer_noc3encoder_req_mshrid,
    input [1:0] noc3buffer_noc3encoder_req_sequenceid,
    input [`L15_THREADID_MASK] noc3buffer_noc3encoder_req_threadid,
    input [`L15_PADDR_HI:0] noc3buffer_noc3encoder_req_address,
    input noc3buffer_noc3encoder_req_with_data,
    input noc3buffer_noc3encoder_req_was_inval,
    input [3:0] noc3buffer_noc3encoder_req_fwdack_vector,
    input [`PACKET_HOME_ID_WIDTH-1:0] noc3buffer_noc3encoder_req_homeid,

    output [511:0] noc2_data,
    output noc2_data_val,
    input noc2_data_ack

);







wire [`CHIE_DAT_FLIT_HOMENID_WIDTH-1:0]    li_decoder_rxdat_homenid;
wire [`CHIE_DAT_FLIT_CCID_WIDTH-1:0]       li_decoder_rxdat_ccid;
wire [`CHIE_DAT_FLIT_DBID_WIDTH-1:0]       li_decoder_rxdat_dbid;
wire                                       rxdat_buf_ready;

wire                                       li_mshr_rxdat_valid_s0;
wire [`CHIE_DAT_FLIT_TXNID_WIDTH-1:0]      li_mshr_rxdat_txnid_s0;
wire [`CHIE_DAT_FLIT_OPCODE_WIDTH-1:0]     li_mshr_rxdat_opcode_s0;
wire [`CHIE_DAT_FLIT_RESP_WIDTH-1:0]       li_mshr_rxdat_resp_s0;
wire [`CHIE_DAT_FLIT_FWDSTATE_WIDTH-1:0]   li_mshr_rxdat_fwdstate_s0;
wire [`CHIE_DAT_FLIT_DATAID_WIDTH-1:0]     li_mshr_rxdat_dataid_s0;
wire                                       li_dbf_rxdat_valid_s0;
wire [`MSHR_ENTRIES_WIDTH-1:0]             li_dbf_rxdat_txnid_s0;
wire [`CHIE_DAT_FLIT_OPCODE_WIDTH-1:0]     li_dbf_rxdat_opcode_s0;
wire [`CHIE_DAT_FLIT_DATAID_WIDTH-1:0]     li_dbf_rxdat_dataid_s0;
wire [`CHIE_DAT_FLIT_BE_WIDTH-1:0]         li_dbf_rxdat_be_s0;
wire [`CHIE_DAT_FLIT_DATA_WIDTH-1:0]       li_dbf_rxdat_data_s0;

wire                                        noc2buffer_txrsp_valid_sx1_q;
wire [`CHIE_RSP_FLIT_QOS_WIDTH-1:0]         noc2buffer_txrsp_qos_sx1;
wire [`CHIE_RSP_FLIT_TGTID_WIDTH-1:0]       noc2buffer_txrsp_tgtid_sx1;
wire [`CHIE_RSP_FLIT_TXNID_WIDTH-1:0]       noc2buffer_txrsp_txnid_sx1_q;
wire [`CHIE_RSP_FLIT_OPCODE_WIDTH-1:0]      noc2buffer_txrsp_opcode_sx1;
wire [`CHIE_RSP_FLIT_RESPERR_WIDTH-1:0]     noc2buffer_txrsp_resperr_sx1;
wire [`CHIE_RSP_FLIT_RESP_WIDTH-1:0]        noc2buffer_txrsp_resp_sx1;
wire [`CHIE_RSP_FLIT_DBID_WIDTH-1:0]        noc2buffer_txrsp_dbid_sx1;
wire [`CHIE_RSP_FLIT_TRACETAG_WIDTH-1:0]    noc2buffer_txrsp_tracetag_sx1;

wire                                        txrsp_cache_crd_avail;
wire                                        txrsp_rxdat_buf_won_sx1;

wire                                        rxsnp_buf_ready;                  

wire                                         rxsnp_decoder_valid_sx;
wire [`CHIE_SNP_FLIT_QOS_WIDTH-1:0]          rxsnp_decoder_qos;
wire [`CHIE_SNP_FLIT_SRCID_WIDTH-1:0]        rxsnp_decoder_srcid;
wire [`CHIE_SNP_FLIT_TXNID_WIDTH-1:0]        rxsnp_decoder_txnid;
wire [`CHIE_SNP_FLIT_FWDNID_WIDTH-1:0]       rxsnp_decoder_fwdnid;
wire [`CHIE_SNP_FLIT_FWDTXNID_WIDTH-1:0]     rxsnp_decoder_fwdtxnid;
wire [`CHIE_SNP_FLIT_OPCODE_WIDTH-1:0]       rxsnp_decoder_opcode;
wire [`CHIE_SNP_FLIT_ADDR_WIDTH-1:0]         rxsnp_decoder_addr;
wire [`CHIE_SNP_FLIT_NS_WIDTH-1:0]           rxsnp_decoder_ns;
wire [`CHIE_SNP_FLIT_DONOTGOTOSD_WIDTH-1:0]  rxsnp_decoder_donotgotosd;
wire [`CHIE_SNP_FLIT_RETTOSRC_WIDTH-1:0]     rxsnp_decoder_rettosrc;
wire [`CHIE_SNP_FLIT_TRACETAG_WIDTH-1:0]     rxsnp_decoder_tracetag;

wire                                         rxbuf_txreq_bypass_valid_s1;
wire [`CHIE_REQ_FLIT_QOS_WIDTH-1:0]          rxbuf_txreq_bypass_qos_s1;
wire [`CHIE_REQ_FLIT_TXNID_WIDTH-1:0]        rxbuf_txreq_bypass_txnid_s1;
wire [`CHIE_REQ_FLIT_RETURNNID_WIDTH-1:0]    rxbuf_txreq_bypass_returnnid_s1;
wire [`CHIE_REQ_FLIT_RETURNTXNID_WIDTH-1:0]  rxbuf_txreq_bypass_returntxnid_s1;
wire [`CHIE_REQ_FLIT_OPCODE_WIDTH-1:0]       rxbuf_txreq_bypass_opcode_s1;
wire [`CHIE_REQ_FLIT_SIZE_WIDTH-1:0]         rxbuf_txreq_bypass_size_s1;
wire [`CHIE_REQ_FLIT_ADDR_WIDTH-1:0]         rxbuf_txreq_bypass_addr_s1;
wire [`CHIE_REQ_FLIT_NS_WIDTH-1:0]           rxbuf_txreq_bypass_ns_s1;
wire [`CHIE_REQ_FLIT_ALLOWRETRY_WIDTH-1:0]   rxbuf_txreq_bypass_allowretry_s1;
wire [`CHIE_REQ_FLIT_ORDER_WIDTH-1:0]        rxbuf_txreq_bypass_order_s1;
wire [`CHIE_REQ_FLIT_PCRDTYPE_WIDTH-1:0]     rxbuf_txreq_bypass_pcrdtype_s1;
wire [`CHIE_REQ_FLIT_MEMATTR_WIDTH-1:0]      rxbuf_txreq_bypass_memattr_s1;
wire [`CHIE_REQ_FLIT_DODWT_WIDTH-1:0]        rxbuf_txreq_bypass_dodwt_s1;
wire [`CHIE_REQ_FLIT_TRACETAG_WIDTH-1:0]     rxbuf_txreq_bypass_tracetag_s1;
wire [`CHIE_REQ_FLIT_TGTID_WIDTH-1:0]        rxbuf_txreq_bypass_tgtid;
wire [`CHIE_REQ_FLIT_SRCID_WIDTH-1:0]        rxbuf_txreq_bypass_srcid;
wire [`CHIE_REQ_FLIT_LIKELYSHARED_WIDTH-1:0] rxbuf_txreq_bypass_likelyshared;
wire [`CHIE_REQ_FLIT_EXCL_WIDTH-1:0]         rxbuf_txreq_bypass_exclusive;
wire [`CHIE_REQ_FLIT_ENDIAN_WIDTH-1:0]       txreq_bypass_endian;
wire [`CHIE_REQ_FLIT_LPID_WIDTH-1:0]         txreq_bypass_lpid;
wire [`CHIE_REQ_FLIT_EXPCOMPACK_WIDTH-1:0]   txreq_bypass_expcompack;
wire                                         txreq_rxbuf_bypass_won_s1;

wire                                         li_rxbuf_rxrsp_valid_s0;
wire [`CHIE_RSP_FLIT_SRCID_WIDTH-1:0]        li_rxbuf_rxrsp_srcid_s0;
wire [`CHIE_RSP_FLIT_TXNID_WIDTH-1:0]        li_rxbuf_rxrsp_txnid_s0;
wire [`CHIE_RSP_FLIT_OPCODE_WIDTH-1:0]       li_rxbuf_rxrsp_opcode_s0;
wire [`CHIE_RSP_FLIT_RESP_WIDTH-1:0]         li_rxbuf_rxrsp_resp_s0;
wire [`CHIE_RSP_FLIT_FWDSTATE_WIDTH-1:0]     li_rxbuf_rxrsp_fwdstate_s0;
wire [`CHIE_RSP_FLIT_DBID_WIDTH-1:0]         li_rxbuf_rxrsp_dbid_s0;
wire [`CHIE_RSP_FLIT_PCRDTYPE_WIDTH-1:0]     li_rxbuf_rxrsp_pcrdtype_s0;
wire                                         rxrsp_buf_ready;

wire                                         rxbuf_rspenc_txdat_valid;
wire [`CHIE_DAT_FLIT_QOS_WIDTH-1:0]          rxbuf_rspenc_txdat_qos;
wire [`CHIE_DAT_FLIT_SRCID_WIDTH-1:0]        rxbuf_rspenc_txdat_srcid;
wire [`CHIE_DAT_FLIT_TXNID_WIDTH-1:0]        rxbuf_rspenc_txdat_txnid;
wire [`CHIE_DAT_FLIT_OPCODE_WIDTH-1:0]       rxbuf_rspenc_txdat_opcode;
wire [`CHIE_DAT_FLIT_RESP_WIDTH-1:0]         rxbuf_rspenc_txdat_resp;
wire [`CHIE_DAT_FLIT_RESPERR_WIDTH-1:0]      rxbuf_rspenc_txdat_resperr;
wire [`CHIE_DAT_FLIT_FWDSTATE_WIDTH-1:0]     rxbuf_rspenc_txdat_fwdstate;
wire [`CHIE_DAT_FLIT_DATAID_WIDTH-1:0]       rxbuf_rspenc_txdat_dataid;
wire [`CHIE_DAT_FLIT_HOMENID_WIDTH-1:0]      rxbuf_rspenc_txdat_homenid;
wire [`CHIE_DAT_FLIT_CCID_WIDTH-1:0]         rxbuf_rspenc_txdat_ccid;
wire [`CHIE_DAT_FLIT_TGTID_WIDTH-1:0]        rxbuf_rspenc_txdat_tgtid;
wire [`CHIE_DAT_FLIT_DBID_WIDTH-1:0]         rxbuf_rspenc_txdat_dbid;
wire [`CHIE_DAT_FLIT_BE_WIDTH*2-1:0]           rxbuf_rspenc_txdat_be;
wire [`CHIE_DAT_FLIT_DATA_WIDTH*2-1:0]         rxbuf_rspenc_txdat_data;
wire                                         rspenc_rxbuf_ack;



wire [127:0]                                        txreq_enc_rxctrl_atomic_data;
wire                                                mshr_txreq_valid_sx1_q;     //connected
wire                                                txreq_encoder_crd_avail_s1;
// Flit fields from encoder to txreq_wrap
wire [`CHIE_REQ_FLIT_QOS_WIDTH-1:0]                 mshr_txreq_qos_sx1;          
wire [`CHIE_REQ_FLIT_TXNID_WIDTH-1:0]               mshr_txreq_txnid_sx1_q;     //connected
wire [`CHIE_REQ_FLIT_RETURNNID_WIDTH-1:0]           mshr_txreq_returnnid_sx1;       // not needed when sending req
wire [`CHIE_REQ_FLIT_RETURNTXNID_WIDTH-1:0]         mshr_txreq_returntxnid_sx1;     // not needed when sending req
wire [`CHIE_REQ_FLIT_OPCODE_WIDTH-1:0]              mshr_txreq_opcode_sx1;      //connected
wire [`CHIE_REQ_FLIT_SIZE_WIDTH-1:0]                mshr_txreq_size_sx1;        //connected
wire [`CHIE_REQ_FLIT_ADDR_WIDTH-1:0]                mshr_txreq_addr_sx1;        //connected
wire [`CHIE_REQ_FLIT_NS_WIDTH-1:0]                  mshr_txreq_ns_sx1;          // need logic, zero
wire [`CHIE_REQ_FLIT_ALLOWRETRY_WIDTH-1:0]          mshr_txreq_allowretry_sx1;  // need logic, zero
wire [`CHIE_REQ_FLIT_ORDER_WIDTH-1:0]               mshr_txreq_order_sx1;       // need logic, zero, for specific chi txs set no non-zero(eg atomics)
wire [`CHIE_REQ_FLIT_PCRDTYPE_WIDTH-1:0]            mshr_txreq_pcrdtype_sx1;        // just zero should be enough
wire [`CHIE_REQ_FLIT_MEMATTR_WIDTH-1:0]             mshr_txreq_memattr_sx1;     // 
wire [`CHIE_REQ_FLIT_DODWT_WIDTH-1:0]               mshr_txreq_dodwt_sx1;           // this is also SnpAttr
wire [`CHIE_REQ_FLIT_TRACETAG_WIDTH-1:0]            mshr_txreq_tracetag_sx1;        // zero should be okay 
wire [`CHIE_REQ_FLIT_TGTID_WIDTH-1:0]               mshr_txreq_tgtid;           // connected
wire [`CHIE_REQ_FLIT_SRCID_WIDTH-1:0]               mshr_txreq_srcid;           // connected
wire [`CHIE_REQ_FLIT_LIKELYSHARED_WIDTH-1:0]        encoder_txreq_likelyshared;
wire [`CHIE_REQ_FLIT_EXCL_WIDTH-1:0]                encoder_txreq_exclusive;
wire [`CHIE_REQ_FLIT_ENDIAN_WIDTH-1:0]              encoder_txreq_endian;
wire [`CHIE_REQ_FLIT_LPID_WIDTH-1:0]                encoder_txreq_lpid;
wire [`CHIE_REQ_FLIT_EXPCOMPACK_WIDTH-1:0]          encoder_txreq_expcompack;
wire                                                encoder_txreq_reg_icache;
wire                                                txreq_enc_won_sx1;

wire                                                rspenc_rxctrl_txreq_valid;
wire [`CHIE_REQ_FLIT_TXNID_WIDTH-1:0]               rspenc_rxctrl_txreq_txnid;
wire [`CHIE_REQ_FLIT_OPCODE_WIDTH-1:0]              rspenc_rxctrl_txreq_opcode;
wire [`CHIE_REQ_FLIT_SIZE_WIDTH-1:0]                rspenc_rxctrl_txreq_size;
wire [`CHIE_REQ_FLIT_ADDR_WIDTH-1:0]                rspenc_rxctrl_txreq_addr;
wire [`CHIE_REQ_FLIT_TGTID_WIDTH-1:0]               rspenc_rxctrl_txreq_tgtid;
wire [`CHIE_REQ_FLIT_SRCID_WIDTH-1:0]               rspenc_rxctrl_txreq_srcid;
wire [`CHIE_REQ_FLIT_DODWT_WIDTH-1:0]               rspenc_rxctrl_txreq_snpattr;
wire [`CHIE_REQ_FLIT_LIKELYSHARED_WIDTH-1:0]        rspenc_rxctrl_txreq_likelyshared;
wire [`CHIE_REQ_FLIT_QOS_WIDTH-1:0]                 rspenc_rxctrl_txreq_qos;
wire [`CHIE_REQ_FLIT_RETURNNID_WIDTH-1:0]           rspenc_rxctrl_txreq_returnnid;
wire [`CHIE_REQ_FLIT_RETURNTXNID_WIDTH-1:0]         rspenc_rxctrl_txreq_returntxnid;
wire [`CHIE_REQ_FLIT_NS_WIDTH-1:0]                  rspenc_rxctrl_txreq_ns;
wire [`CHIE_REQ_FLIT_ALLOWRETRY_WIDTH-1:0]          rspenc_rxctrl_txreq_allowretry;
wire [`CHIE_REQ_FLIT_ORDER_WIDTH-1:0]               rspenc_rxctrl_txreq_order;
wire [`CHIE_REQ_FLIT_PCRDTYPE_WIDTH-1:0]            rspenc_rxctrl_txreq_pcrdtype;
wire [`CHIE_REQ_FLIT_MEMATTR_WIDTH-1:0]             rspenc_rxctrl_txreq_memattr;
wire [`CHIE_REQ_FLIT_TRACETAG_WIDTH-1:0]            rspenc_rxctrl_txreq_tracetag;     
wire [`CHIE_REQ_FLIT_EXCL_WIDTH-1:0]                rspenc_rxctrl_txreq_exclusive;  
wire [`CHIE_REQ_FLIT_ENDIAN_WIDTH-1:0]              rspenc_rxctrl_txreq_endian;
wire [`CHIE_REQ_FLIT_LPID_WIDTH-1:0]                rspenc_rxctrl_txreq_lpid;
wire [`CHIE_REQ_FLIT_EXPCOMPACK_WIDTH-1:0]          rspenc_rxctrl_txreq_expcompack;
wire [`CHIE_DAT_FLIT_BE_WIDTH*2-1:0]                rspenc_rxctrl_txreq_be;     // 512bit BE
wire [`CHIE_DAT_FLIT_DATA_WIDTH*2-1:0]              rspenc_rxctrl_txreq_data;   // 512bit data
wire                                                rspenc_txreq_won;

/////////////////////////////////////////////////////////////////////////////////////////////////////////
// RXDAT to noc2encoder
// translates CHI message to noc2 message
rx_control `RNF_PARAM_INST rx_control(
    .clk(clk),
    .rst_n(rst_n),
    // noc2decoder 
    .msg_ack(noc2_data_ack),
    .msg(noc2_data),
    .msg_val(noc2_data_val),
    // rxdat_parse
    .li_mshr_rxdat_valid_s0                       (li_mshr_rxdat_valid_s0            ),
    .li_mshr_rxdat_txnid_s0                       (li_mshr_rxdat_txnid_s0            ),
    .li_mshr_rxdat_opcode_s0                      (li_mshr_rxdat_opcode_s0           ),
    .li_mshr_rxdat_resp_s0                        (li_mshr_rxdat_resp_s0             ),
    .li_mshr_rxdat_fwdstate_s0                    (li_mshr_rxdat_fwdstate_s0         ),
    .li_mshr_rxdat_dataid_s0                      (li_mshr_rxdat_dataid_s0           ),
    .li_decoder_rxdat_homenid                     (li_decoder_rxdat_homenid),        // added for RNF
    .li_decoder_rxdat_ccid                        (li_decoder_rxdat_ccid),           // added for RNF
    .li_decoder_rxdat_dbid                        (li_decoder_rxdat_dbid),           // added for RNF
    .li_dbf_rxdat_valid_s0                        (li_dbf_rxdat_valid_s0             ),
    .li_dbf_rxdat_txnid_s0                        (li_dbf_rxdat_txnid_s0             ),
    .li_dbf_rxdat_opcode_s0                       (li_dbf_rxdat_opcode_s0            ),
    .li_dbf_rxdat_dataid_s0                       (li_dbf_rxdat_dataid_s0            ),
    .li_dbf_rxdat_be_s0                           (li_dbf_rxdat_be_s0                ),
    .li_dbf_rxdat_data_s0                         (li_dbf_rxdat_data_s0              ),
    .rxdat_buf_ready                               (rxdat_buf_ready),
    // txrsp
    .noc2buffer_txrsp_valid_sx1_q                 (noc2buffer_txrsp_valid_sx1_q            ),
    .noc2buffer_txrsp_qos_sx1                     (noc2buffer_txrsp_qos_sx1                ),
    .noc2buffer_txrsp_tgtid_sx1                   (noc2buffer_txrsp_tgtid_sx1              ),
    .noc2buffer_txrsp_txnid_sx1_q                 (noc2buffer_txrsp_txnid_sx1_q            ),
    .noc2buffer_txrsp_opcode_sx1                  (noc2buffer_txrsp_opcode_sx1             ),
    .noc2buffer_txrsp_resperr_sx1                 (noc2buffer_txrsp_resperr_sx1            ),
    .noc2buffer_txrsp_resp_sx1                    (noc2buffer_txrsp_resp_sx1               ),
    .noc2buffer_txrsp_dbid_sx1                    (noc2buffer_txrsp_dbid_sx1               ),
    .noc2buffer_txrsp_tracetag_sx1                (noc2buffer_txrsp_tracetag_sx1           ),
    .txrsp_cache_crd_avail                        (txrsp_cache_crd_avail                   ),
    .txrsp_rxdat_buf_won_sx1                      (txrsp_rxdat_buf_won_sx1                 ),
    // RXSNP
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
    // TXREQ bypass
    .rxbuf_txreq_bypass_valid                          (rxbuf_txreq_bypass_valid_s1            ),
    .rxbuf_txreq_bypass_qos                            (rxbuf_txreq_bypass_qos_s1              ),
    .rxbuf_txreq_bypass_txnid                          (rxbuf_txreq_bypass_txnid_s1            ),
    .rxbuf_txreq_bypass_returnnid                      (rxbuf_txreq_bypass_returnnid_s1        ),
    .rxbuf_txreq_bypass_returntxnid                    (rxbuf_txreq_bypass_returntxnid_s1      ),
    .rxbuf_txreq_bypass_opcode                         (rxbuf_txreq_bypass_opcode_s1           ),
    .rxbuf_txreq_bypass_size                           (rxbuf_txreq_bypass_size_s1             ),
    .rxbuf_txreq_bypass_addr                           (rxbuf_txreq_bypass_addr_s1             ),
    .rxbuf_txreq_bypass_ns                             (rxbuf_txreq_bypass_ns_s1               ),
    .rxbuf_txreq_bypass_allowretry                     (rxbuf_txreq_bypass_allowretry_s1       ),
    .rxbuf_txreq_bypass_order                          (rxbuf_txreq_bypass_order_s1            ),
    .rxbuf_txreq_bypass_pcrdtype                       (rxbuf_txreq_bypass_pcrdtype_s1         ),
    .rxbuf_txreq_bypass_memattr                        (rxbuf_txreq_bypass_memattr_s1          ),
    .rxbuf_txreq_bypass_dodwt                          (rxbuf_txreq_bypass_dodwt_s1            ),
    .rxbuf_txreq_bypass_tracetag                       (rxbuf_txreq_bypass_tracetag_s1         ),
    .rxbuf_txreq_bypass_tgtid                          (rxbuf_txreq_bypass_tgtid            ),
    .rxbuf_txreq_bypass_srcid                          (rxbuf_txreq_bypass_srcid            ),
    .rxbuf_txreq_bypass_likelyshared                   (rxbuf_txreq_bypass_likelyshared          ),
    .rxbuf_txreq_bypass_exclusive                      (rxbuf_txreq_bypass_exclusive             ),
    .rxbuf_txreq_bypass_endian                           (txreq_bypass_endian           ),
    .rxbuf_txreq_bypass_lpid                             (txreq_bypass_lpid             ),
    .rxbuf_txreq_bypass_expcompack                       (txreq_bypass_expcompack       ),
    .txreq_rxbuf_bypass_won                            (txreq_rxbuf_bypass_won_s1              ),
    // RXRSP
    .li_rxbuf_rxrsp_valid_s0                            (li_rxbuf_rxrsp_valid_s0                 ),
    .li_rxbuf_rxrsp_srcid_s0                            (li_rxbuf_rxrsp_srcid_s0                 ),
    .li_rxbuf_rxrsp_txnid_s0                            (li_rxbuf_rxrsp_txnid_s0                 ),
    .li_rxbuf_rxrsp_opcode_s0                           (li_rxbuf_rxrsp_opcode_s0                ),
    .li_rxbuf_rxrsp_resp_s0                             (li_rxbuf_rxrsp_resp_s0                  ),
    .li_rxbuf_rxrsp_fwdstate_s0                         (li_rxbuf_rxrsp_fwdstate_s0              ),
    .li_rxbuf_rxrsp_dbid_s0                             (li_rxbuf_rxrsp_dbid_s0                  ),
    .li_rxbuf_rxrsp_pcrdtype_s0                         (li_rxbuf_rxrsp_pcrdtype_s0              ),
    .rxrsp_buf_ready                                     (rxrsp_buf_ready                          ),
    // TXDAT to response_encoder
    .rxbuf_rspenc_txdat_valid                           (rxbuf_rspenc_txdat_valid                      ),
    .rxbuf_rspenc_txdat_qos                             (rxbuf_rspenc_txdat_qos                         ),
    .rxbuf_rspenc_txdat_srcid                           (rxbuf_rspenc_txdat_srcid                           ),
    .rxbuf_rspenc_txdat_txnid                           (rxbuf_rspenc_txdat_txnid                      ),
    .rxbuf_rspenc_txdat_opcode                          (rxbuf_rspenc_txdat_opcode                     ),    
    .rxbuf_rspenc_txdat_resp                            (rxbuf_rspenc_txdat_resp                       ),
    .rxbuf_rspenc_txdat_resperr                         (rxbuf_rspenc_txdat_resperr                          ),
    .rxbuf_rspenc_txdat_fwdstate                        (rxbuf_rspenc_txdat_fwdstate                   ),    
    .rxbuf_rspenc_txdat_dataid                          (rxbuf_rspenc_txdat_dataid                     ),    
    .rxbuf_rspenc_txdat_homenid                         (rxbuf_rspenc_txdat_homenid                    ),    
    .rxbuf_rspenc_txdat_ccid                            (rxbuf_rspenc_txdat_ccid                       ),
    .rxbuf_rspenc_txdat_tgtid                           (rxbuf_rspenc_txdat_tgtid                            ),
    .rxbuf_rspenc_txdat_dbid                            (rxbuf_rspenc_txdat_dbid                       ),
    .rxbuf_rspenc_txdat_be                              (rxbuf_rspenc_txdat_be                         ),
    .rxbuf_rspenc_txdat_data                            (rxbuf_rspenc_txdat_data                       ),
    .rspenc_rxbuf_ack                                   (rspenc_rxbuf_ack                              ),
    // from txreq_encoder
    .atomic_data                                        (txreq_enc_rxctrl_atomic_data),
    .reqenc_txreq_valid                                 (mshr_txreq_valid_sx1_q),
    .reqenc_txreq_txnid                                 (mshr_txreq_txnid_sx1_q),
    .reqenc_txreq_opcode                                (mshr_txreq_opcode_sx1),
    .reqenc_txreq_size                                  (mshr_txreq_size_sx1),
    .reqenc_txreq_addr                                  (mshr_txreq_addr_sx1),
    .reqenc_txreq_tgtid                                 (mshr_txreq_tgtid),
    .reqenc_txreq_srcid                                 (mshr_txreq_srcid),
    .reqenc_txreq_snpattr                               (mshr_txreq_dodwt_sx1),                         // used as SnpAttr here
    .reqenc_txreq_likelyshared                          (encoder_txreq_likelyshared),                    // 
    .reqenc_txreq_exclusive                             (encoder_txreq_exclusive),
    .reqenc_txreq_qos                                   (mshr_txreq_qos_sx1),
    .reqenc_txreq_returnnid                             (mshr_txreq_returnnid_sx1),
    .reqenc_txreq_returntxnid                           (mshr_txreq_returntxnid_sx1),
    .reqenc_txreq_ns                                    (mshr_txreq_ns_sx1),         
    .reqenc_txreq_allowretry                            (mshr_txreq_allowretry_sx1),
    .reqenc_txreq_order                                 (mshr_txreq_order_sx1),
    .reqenc_txreq_pcrdtype                              (mshr_txreq_pcrdtype_sx1),
    .reqenc_txreq_memattr                               (mshr_txreq_memattr_sx1),
    .reqenc_txreq_tracetag                              (mshr_txreq_tracetag_sx1),
    .reqenc_txreq_endian                                (encoder_txreq_endian           ),
    .reqenc_txreq_lpid                                  (encoder_txreq_lpid             ),
    .reqenc_txreq_expcompack                            (encoder_txreq_expcompack       ),
    .reqenc_txreq_reg_icache                            (encoder_txreq_reg_icache),
    .txreq_enc_won                                      (txreq_enc_won_sx1),
    .rspenc_rxctrl_txreq_valid                          (rspenc_rxctrl_txreq_valid),                            
    .rspenc_rxctrl_txreq_txnid                          (rspenc_rxctrl_txreq_txnid),                  
    .rspenc_rxctrl_txreq_opcode                         (rspenc_rxctrl_txreq_opcode),                  
    .rspenc_rxctrl_txreq_size                           (rspenc_rxctrl_txreq_size),                  
    .rspenc_rxctrl_txreq_addr                           (rspenc_rxctrl_txreq_addr),                  
    .rspenc_rxctrl_txreq_tgtid                          (rspenc_rxctrl_txreq_tgtid),                  
    .rspenc_rxctrl_txreq_srcid                          (rspenc_rxctrl_txreq_srcid),                  
    .rspenc_rxctrl_txreq_snpattr                        (rspenc_rxctrl_txreq_snpattr),                      
    .rspenc_rxctrl_txreq_likelyshared                   (rspenc_rxctrl_txreq_likelyshared),                          
    .rspenc_rxctrl_txreq_qos                            (rspenc_rxctrl_txreq_qos),                  
    .rspenc_rxctrl_txreq_returnnid                      (rspenc_rxctrl_txreq_returnnid),                      
    .rspenc_rxctrl_txreq_returntxnid                    (rspenc_rxctrl_txreq_returntxnid),                          
    .rspenc_rxctrl_txreq_ns                             (rspenc_rxctrl_txreq_ns),              
    .rspenc_rxctrl_txreq_allowretry                     (rspenc_rxctrl_txreq_allowretry),                      
    .rspenc_rxctrl_txreq_order                          (rspenc_rxctrl_txreq_order),                  
    .rspenc_rxctrl_txreq_pcrdtype                       (rspenc_rxctrl_txreq_pcrdtype),                      
    .rspenc_rxctrl_txreq_memattr                        (rspenc_rxctrl_txreq_memattr),                      
    .rspenc_rxctrl_txreq_tracetag                       (rspenc_rxctrl_txreq_tracetag),       
    .rspenc_rxctrl_txreq_exclusive                      (rspenc_rxctrl_txreq_exclusive),     
    .rspenc_rxctrl_txreq_endian                         (rspenc_rxctrl_txreq_endian),
    .rspenc_rxctrl_txreq_lpid                           (rspenc_rxctrl_txreq_lpid),
    .rspenc_rxctrl_txreq_expcompack                     (rspenc_rxctrl_txreq_expcompack),       
    .rspenc_rxctrl_txreq_be                             (rspenc_rxctrl_txreq_be), 
    .rspenc_rxctrl_txreq_data                           (rspenc_rxctrl_txreq_data),    
    .rspenc_txreq_won                                   (rspenc_txreq_won)
);



// TXDAT wires
    wire [`CHIE_DAT_FLIT_QOS_WIDTH-1:0]         encoder_txdat_qos;
    wire [`CHIE_DAT_FLIT_SRCID_WIDTH-1:0]       encoder_txdat_srcid;
    wire [`CHIE_DAT_FLIT_HOMENID_WIDTH-1:0]     encoder_txdat_homenid;
    wire [`CHIE_DAT_FLIT_FWDSTATE_WIDTH-1:0]    encoder_txdat_fwdstate;
    wire [`CHIE_DAT_FLIT_CCID_WIDTH-1:0]        encoder_txdat_ccid;
    wire [`CHIE_DAT_FLIT_TGTID_WIDTH-1:0]       mshr_txdat_tgtid_sx2;
    wire [`CHIE_DAT_FLIT_TXNID_WIDTH-1:0]       mshr_txdat_txnid_sx2;
    wire [`CHIE_DAT_FLIT_OPCODE_WIDTH-1:0]      mshr_txdat_opcode_sx2;
    wire [`CHIE_DAT_FLIT_RESP_WIDTH-1:0]        mshr_txdat_resp_sx2;
    wire [`CHIE_DAT_FLIT_RESPERR_WIDTH-1:0]     mshr_txdat_resperr_sx2;
    wire [`CHIE_DAT_FLIT_DBID_WIDTH-1:0]        mshr_txdat_dbid_sx2;
    wire [`CHIE_DAT_FLIT_DATA_WIDTH*2-1:0]      dbf_txdat_data_sx1;
    wire [`MSHR_ENTRIES_WIDTH-1:0]              dbf_txdat_idx_sx1;
    wire [1:0]                                  dbf_txdat_pe_sx1;
    wire [`CHIE_DAT_FLIT_BE_WIDTH*2-1:0]        dbf_txdat_be_sx1;
    wire                                        dbf_txdat_valid_sx1;
    wire                                        txdat_mshr_clr_dbf_busy_valid_sx3;
    wire [`MSHR_ENTRIES_WIDTH-1:0]              txdat_mshr_clr_dbf_busy_idx_sx3;
    wire [`MSHR_ENTRIES_WIDTH-1:0]              txdat_mshr_rd_idx_sx2;
    wire                                        txdat_mshr_busy_sx;

    wire                                        encoder_txrsp_bypass_valid_s1;
    wire [`CHIE_RSP_FLIT_QOS_WIDTH-1:0]         encoder_txrsp_bypass_qos_s1;
    wire [`CHIE_RSP_FLIT_TGTID_WIDTH-1:0]       encoder_txrsp_bypass_tgtid_s1;
    wire [`CHIE_RSP_FLIT_TXNID_WIDTH-1:0]       encoder_txrsp_bypass_txnid_s1;
    wire [`CHIE_RSP_FLIT_OPCODE_WIDTH-1:0]      encoder_txrsp_bypass_opcode_s1;
    wire [`CHIE_RSP_FLIT_RESP_WIDTH-1:0]        encoder_txrsp_bypass_resp;
    wire [`CHIE_RSP_FLIT_RESPERR_WIDTH-1:0]     encoder_txrsp_bypass_resperr_s1;
    wire [`CHIE_RSP_FLIT_DBID_WIDTH-1:0]        encoder_txrsp_bypass_dbid_s1;
    wire [`CHIE_RSP_FLIT_TRACETAG_WIDTH-1:0]    encoder_txrsp_bypass_tracetag_s1;
    wire                                        txrsp_encoder_bypass_won_s1;


response_encoder `RNF_PARAM_INST response_encoder(
    .clk(clk),
    .rst_n(rst_n),
    .l15_noc3encoder_req_val_i(noc3buffer_noc3encoder_req_val),
    .l15_noc3encoder_req_type_i(noc3buffer_noc3encoder_req_type),
    .l15_noc3encoder_req_data_0_i(noc3buffer_noc3encoder_req_data_0),
    .l15_noc3encoder_req_data_1_i(noc3buffer_noc3encoder_req_data_1),
    .l15_noc3encoder_req_mshrid_i(noc3buffer_noc3encoder_req_mshrid),
    .l15_noc3encoder_req_sequenceid_i(noc3buffer_noc3encoder_req_sequenceid),
    .l15_noc3encoder_req_threadid_i(noc3buffer_noc3encoder_req_threadid),
    .l15_noc3encoder_req_address_i(noc3buffer_noc3encoder_req_address),
    .l15_noc3encoder_req_with_data_i(noc3buffer_noc3encoder_req_with_data),
    .l15_noc3encoder_req_was_inval_i(noc3buffer_noc3encoder_req_was_inval),
    .l15_noc3encoder_req_fwdack_vector_i(noc3buffer_noc3encoder_req_fwdack_vector),
    .l15_noc3encoder_req_homeid_i(noc3buffer_noc3encoder_req_homeid),
    .noc3encoder_l15_req_ack(noc3encoder_noc3buffer_req_ack),
    .chipid_i(chipid),
    .coreid_x_i(coreid_x),
    .coreid_y_i(coreid_y),


    .encoder_txdat_qos                            (encoder_txdat_qos                 ),
    .encoder_txdat_srcid                          (encoder_txdat_srcid               ),
    .encoder_txdat_homenid                        (encoder_txdat_homenid             ),
    .encoder_txdat_fwdstate                       (encoder_txdat_fwdstate            ),
    .encoder_txdat_ccid                           (encoder_txdat_ccid                ),
    .mshr_txdat_tgtid_sx2                         (mshr_txdat_tgtid_sx2              ),
    .mshr_txdat_txnid_sx2                         (mshr_txdat_txnid_sx2              ),
    .mshr_txdat_opcode_sx2                        (mshr_txdat_opcode_sx2             ),
    .mshr_txdat_resp_sx2                          (mshr_txdat_resp_sx2               ),
    .mshr_txdat_resperr_sx2                       (mshr_txdat_resperr_sx2            ),
    .mshr_txdat_dbid_sx2                          (mshr_txdat_dbid_sx2               ),
    .dbf_txdat_data_sx1                           (dbf_txdat_data_sx1                ),
    .dbf_txdat_idx_sx1                            (dbf_txdat_idx_sx1                 ),
    .dbf_txdat_be_sx1                             (dbf_txdat_be_sx1                  ),
    .dbf_txdat_pe_sx1                             (dbf_txdat_pe_sx1                  ),
    .dbf_txdat_valid_sx1                          (dbf_txdat_valid_sx1               ),
    .txdat_mshr_clr_dbf_busy_valid_sx3            (txdat_mshr_clr_dbf_busy_valid_sx3 ),
    .txdat_mshr_clr_dbf_busy_idx_sx3              (txdat_mshr_clr_dbf_busy_idx_sx3   ),
    .txdat_mshr_rd_idx_sx2                        (txdat_mshr_rd_idx_sx2             ),
    .txdat_mshr_busy_sx                           (txdat_mshr_busy_sx                ),
    .encoder_txrsp_bypass_valid_s1                (encoder_txrsp_bypass_valid_s1            ),
    .encoder_txrsp_bypass_qos_s1                  (encoder_txrsp_bypass_qos_s1              ),
    .encoder_txrsp_bypass_tgtid_s1                (encoder_txrsp_bypass_tgtid_s1            ),
    .encoder_txrsp_bypass_txnid_s1                (encoder_txrsp_bypass_txnid_s1            ),
    .encoder_txrsp_bypass_opcode_s1               (encoder_txrsp_bypass_opcode_s1           ),
    .encoder_txrsp_bypass_resp                    (encoder_txrsp_bypass_resp                ),
    .encoder_txrsp_bypass_resperr_s1              (encoder_txrsp_bypass_resperr_s1          ),
    .encoder_txrsp_bypass_dbid_s1                 (encoder_txrsp_bypass_dbid_s1             ),
    .encoder_txrsp_bypass_tracetag_s1             (encoder_txrsp_bypass_tracetag_s1         ),
    .txrsp_encoder_bypass_won_s1                  (txrsp_encoder_bypass_won_s1              ),
    .rxbuf_rspenc_txdat_valid                     (rxbuf_rspenc_txdat_valid                      ),
    .rxbuf_rspenc_txdat_qos                       (rxbuf_rspenc_txdat_qos                         ),
    .rxbuf_rspenc_txdat_srcid                     (rxbuf_rspenc_txdat_srcid                           ),
    .rxbuf_rspenc_txdat_txnid                     (rxbuf_rspenc_txdat_txnid                      ),
    .rxbuf_rspenc_txdat_opcode                    (rxbuf_rspenc_txdat_opcode                     ),    
    .rxbuf_rspenc_txdat_resp                      (rxbuf_rspenc_txdat_resp                       ),
    .rxbuf_rspenc_txdat_resperr                   (rxbuf_rspenc_txdat_resperr                          ),
    .rxbuf_rspenc_txdat_fwdstate                  (rxbuf_rspenc_txdat_fwdstate                   ),    
    .rxbuf_rspenc_txdat_dataid                    (rxbuf_rspenc_txdat_dataid                     ),    
    .rxbuf_rspenc_txdat_homenid                   (rxbuf_rspenc_txdat_homenid                    ),    
    .rxbuf_rspenc_txdat_ccid                      (rxbuf_rspenc_txdat_ccid                       ),
    .rxbuf_rspenc_txdat_tgtid                     (rxbuf_rspenc_txdat_tgtid                            ),
    .rxbuf_rspenc_txdat_dbid                      (rxbuf_rspenc_txdat_dbid                       ),
    .rxbuf_rspenc_txdat_be                        (rxbuf_rspenc_txdat_be                         ),
    .rxbuf_rspenc_txdat_data                      (rxbuf_rspenc_txdat_data                       ),
    .rspenc_rxbuf_ack                             (rspenc_rxbuf_ack                             ),
    .rspenc_rxctrl_txreq_valid                    (rspenc_rxctrl_txreq_valid),                            
    .rspenc_rxctrl_txreq_txnid                    (rspenc_rxctrl_txreq_txnid),                  
    .rspenc_rxctrl_txreq_opcode                   (rspenc_rxctrl_txreq_opcode),                  
    .rspenc_rxctrl_txreq_size                     (rspenc_rxctrl_txreq_size),                  
    .rspenc_rxctrl_txreq_addr                     (rspenc_rxctrl_txreq_addr),                  
    .rspenc_rxctrl_txreq_tgtid                    (rspenc_rxctrl_txreq_tgtid),                  
    .rspenc_rxctrl_txreq_srcid                    (rspenc_rxctrl_txreq_srcid),                  
    .rspenc_rxctrl_txreq_snpattr                  (rspenc_rxctrl_txreq_snpattr),                      
    .rspenc_rxctrl_txreq_likelyshared             (rspenc_rxctrl_txreq_likelyshared),                          
    .rspenc_rxctrl_txreq_qos                      (rspenc_rxctrl_txreq_qos),                  
    .rspenc_rxctrl_txreq_returnnid                (rspenc_rxctrl_txreq_returnnid),                      
    .rspenc_rxctrl_txreq_returntxnid              (rspenc_rxctrl_txreq_returntxnid),                          
    .rspenc_rxctrl_txreq_ns                       (rspenc_rxctrl_txreq_ns),              
    .rspenc_rxctrl_txreq_allowretry               (rspenc_rxctrl_txreq_allowretry),                      
    .rspenc_rxctrl_txreq_order                    (rspenc_rxctrl_txreq_order),                  
    .rspenc_rxctrl_txreq_pcrdtype                 (rspenc_rxctrl_txreq_pcrdtype),                      
    .rspenc_rxctrl_txreq_memattr                  (rspenc_rxctrl_txreq_memattr),                      
    .rspenc_rxctrl_txreq_tracetag                 (rspenc_rxctrl_txreq_tracetag),      
    .rspenc_rxctrl_txreq_exclusive                (rspenc_rxctrl_txreq_exclusive), 
    .rspenc_rxctrl_txreq_endian                   (rspenc_rxctrl_txreq_endian),
    .rspenc_rxctrl_txreq_lpid                     (rspenc_rxctrl_txreq_lpid),
    .rspenc_rxctrl_txreq_expcompack               (rspenc_rxctrl_txreq_expcompack),   
    .rspenc_rxctrl_txreq_be                       (rspenc_rxctrl_txreq_be), 
    .rspenc_rxctrl_txreq_data                     (rspenc_rxctrl_txreq_data),               
    .rspenc_txreq_won                             (rspenc_txreq_won)  
);




// Translates L1.5 cache requests to CHI-requests
txreq_encoder `RNF_PARAM_INST txreq_encoder(
    .clk(clk),
    .rst_n(rst_n),
    .noc1buffer_noc1encoder_req_data_0(noc1buffer_noc1encoder_req_data_0),
    .noc1buffer_noc1encoder_req_data_1(noc1buffer_noc1encoder_req_data_1),
    .noc1buffer_noc1encoder_req_val(noc1buffer_noc1encoder_req_val),
    .noc1buffer_noc1encoder_req_type(noc1buffer_noc1encoder_req_type),
    .noc1buffer_noc1encoder_req_mshrid(noc1buffer_noc1encoder_req_mshrid),
    .noc1buffer_noc1encoder_req_threadid(noc1buffer_noc1encoder_req_threadid),
    .noc1buffer_noc1encoder_req_address(noc1buffer_noc1encoder_req_address),
    .noc1buffer_noc1encoder_req_non_cacheable(noc1buffer_noc1encoder_req_non_cacheable),
    .noc1buffer_noc1encoder_req_size(noc1buffer_noc1encoder_req_size),
    .noc1buffer_noc1encoder_req_prefetch(noc1buffer_noc1encoder_req_prefetch),
    .noc1buffer_noc1encoder_req_csm_sdid(noc1buffer_noc1encoder_req_csm_sdid),
    .noc1buffer_noc1encoder_req_csm_lsid(noc1buffer_noc1encoder_req_csm_lsid),
    .noc1buffer_noc1encoder_req_homeid(noc1buffer_noc1encoder_req_homeid),

    .noc1encoder_noc1buffer_req_ack(noc1encoder_noc1buffer_req_ack),
    
    // csm interface
    .noc1encoder_csm_req_ack(noc1encoder_csm_req_ack),
    .csm_noc1encoder_req_val(csm_noc1encoder_req_val),
    .csm_noc1encoder_req_type(csm_noc1encoder_req_type),
    .csm_noc1encoder_req_mshrid(csm_noc1encoder_req_mshrid),
    .csm_noc1encoder_req_address(csm_noc1encoder_req_address),
    .csm_noc1encoder_req_non_cacheable(csm_noc1encoder_req_non_cacheable),
    .csm_noc1encoder_req_size(csm_noc1encoder_req_size),    
    
    .dmbr_l15_stall(dmbr_l15_stall),
    .chipid(chipid),
    .coreid_x(coreid_x),
    .coreid_y(coreid_y),
    .l15_dmbr_l1missIn(l15_dmbr_l1missIn),
    .l15_dmbr_l1missTag(l15_dmbr_l1missTag),
    

    // CHI
        // link protocol ports
    .noc1out_ready(txreq_encoder_crd_avail_s1),  
    .noc1encoder_noc1out_val(mshr_txreq_valid_sx1_q), // noc packet valid to chi ports
    .atomic_data(txreq_enc_rxctrl_atomic_data),
        // flit fields
    .encoder_txreq_txnid_sx1_q       (mshr_txreq_txnid_sx1_q),
    .encoder_txreq_opcode_sx1        (mshr_txreq_opcode_sx1),
    .encoder_txreq_size_sx1          (mshr_txreq_size_sx1),
    .encoder_txreq_addr_sx1          (mshr_txreq_addr_sx1),
    .encoder_txreq_tgtid             (mshr_txreq_tgtid),
    .encoder_txreq_srcid             (mshr_txreq_srcid),
    .encoder_txreq_snpattr           (mshr_txreq_dodwt_sx1),                         // used as SnpAttr here
    .encoder_txreq_likelyshared      (encoder_txreq_likelyshared),                    // 
    .encoder_txreq_qos_sx1           (mshr_txreq_qos_sx1),
    .encoder_txreq_returnnid_sx1     (mshr_txreq_returnnid_sx1),
    .encoder_txreq_returntxnid_sx1   (mshr_txreq_returntxnid_sx1),
    .encoder_txreq_ns_sx1            (mshr_txreq_ns_sx1),         
    .encoder_txreq_allowretry_sx1    (mshr_txreq_allowretry_sx1),
    .encoder_txreq_order_sx1         (mshr_txreq_order_sx1),
    .encoder_txreq_pcrdtype_sx1      (mshr_txreq_pcrdtype_sx1),
    .encoder_txreq_memattr_sx1       (mshr_txreq_memattr_sx1),
    .encoder_txreq_tracetag_sx1      (mshr_txreq_tracetag_sx1),
    .encoder_txreq_reg_icache        (encoder_txreq_reg_icache),
    .encoder_txreq_exclusive         (encoder_txreq_exclusive),
    .encoder_txreq_endian            (encoder_txreq_endian           ),
    .encoder_txreq_lpid              (encoder_txreq_lpid             ),
    .encoder_txreq_expcompack        (encoder_txreq_expcompack       ),
    .txreq_enc_won_sx1               (txreq_enc_won_sx1)


);

wire tx_active_ready; 
reg tx_active_ready_r;

assign tx_active_ready = tx_active_ready_r;
// Assert the tx ready right after rst_n is lifted
always @ (posedge clk) begin
    if (~rst_n) 
        tx_active_ready_r <= 'b0;
    else 
        tx_active_ready_r <= 'b1;
        
end

/////////////////////////////////////////////////////////////////////////////////////////////////////////
// RNF link
/////////////////////////////////////////////////////////////////////////////////////////////////////////
    rnf_link `RNF_PARAM_INST rnf_link(
                 //inputs
                 .clk                                          (clk                               ),
                 .rst                                          (~rst_n                               ),
                 .rxrspflitv                                   (RXRSPFLITV                        ),
                 .rxrspflit                                    (RXRSPFLIT                         ),
                 .rxrspflitpend                                (RXRSPFLITPEND                     ),
                 .rxdatflitv                                   (RXDATFLITV                        ),
                 .rxdatflit                                    (RXDATFLIT                         ),
                 .rxdatflitpend                                (RXDATFLITPEND                     ),
                 // TXREQ
                        // bypass ports
                 .txreq_lcrdv                                  (TXREQLCRDV                        ),
                 .mshr_txreq_bypass_valid_s1                       (rxbuf_txreq_bypass_valid_s1            ),
                 .mshr_txreq_bypass_qos_s1                         (rxbuf_txreq_bypass_qos_s1              ),
                 .mshr_txreq_bypass_txnid_s1                       (rxbuf_txreq_bypass_txnid_s1            ),
                 .mshr_txreq_bypass_returnnid_s1                   (rxbuf_txreq_bypass_returnnid_s1        ),
                 .mshr_txreq_bypass_returntxnid_s1                 (rxbuf_txreq_bypass_returntxnid_s1      ),
                 .mshr_txreq_bypass_opcode_s1                      (rxbuf_txreq_bypass_opcode_s1           ),
                 .mshr_txreq_bypass_size_s1                        (rxbuf_txreq_bypass_size_s1             ),
                 .mshr_txreq_bypass_addr_s1                        (rxbuf_txreq_bypass_addr_s1             ),
                 .mshr_txreq_bypass_ns_s1                          (rxbuf_txreq_bypass_ns_s1               ),
                 .mshr_txreq_bypass_allowretry_s1                  (rxbuf_txreq_bypass_allowretry_s1       ),
                 .mshr_txreq_bypass_order_s1                       (rxbuf_txreq_bypass_order_s1            ),
                 .mshr_txreq_bypass_pcrdtype_s1                    (rxbuf_txreq_bypass_pcrdtype_s1         ),
                 .mshr_txreq_bypass_memattr_s1                     (rxbuf_txreq_bypass_memattr_s1          ),
                 .mshr_txreq_bypass_dodwt_s1                       (rxbuf_txreq_bypass_dodwt_s1            ),
                 .mshr_txreq_bypass_tracetag_s1                    (rxbuf_txreq_bypass_tracetag_s1         ),
                 .mshr_txreq_bypass_tgtid                          (rxbuf_txreq_bypass_tgtid            ),
                 .mshr_txreq_bypass_srcid                          (rxbuf_txreq_bypass_srcid            ),
                 .txreq_bypass_likelyshared                        (rxbuf_txreq_bypass_likelyshared          ),
                 .txreq_bypass_exclusive                             (rxbuf_txreq_bypass_exclusive             ),
                 .txreq_bypass_endian                             (txreq_bypass_endian           ),
                 .txreq_bypass_lpid                               (txreq_bypass_lpid             ),
                 .txreq_bypass_expcompack                         (txreq_bypass_expcompack       ),
                        // general ports
                 .mshr_txreq_valid_sx1_q                       (mshr_txreq_valid_sx1_q            ),
                 .mshr_txreq_qos_sx1                           (mshr_txreq_qos_sx1),
                 .mshr_txreq_txnid_sx1_q                       (mshr_txreq_txnid_sx1_q),
                 .mshr_txreq_returnnid_sx1                     (mshr_txreq_returnnid_sx1),
                 .mshr_txreq_returntxnid_sx1                   (mshr_txreq_returntxnid_sx1),
                 .mshr_txreq_opcode_sx1                        (mshr_txreq_opcode_sx1             ),
                 .mshr_txreq_size_sx1                          (mshr_txreq_size_sx1               ),
                 .mshr_txreq_addr_sx1                          ( mshr_txreq_addr_sx1 ),
                 .mshr_txreq_ns_sx1                            (mshr_txreq_ns_sx1),               //atm there should not be nonsecure accesses             
                 .mshr_txreq_allowretry_sx1                    (mshr_txreq_allowretry_sx1),       //atm not supported
                 .mshr_txreq_order_sx1                         (mshr_txreq_order_sx1),            //this is required in specific CHI txs 
                 .mshr_txreq_pcrdtype_sx1                      (mshr_txreq_pcrdtype_sx1),                     
                 .mshr_txreq_memattr_sx1                       (mshr_txreq_memattr_sx1),
                 .mshr_txreq_dodwt_sx1                         (mshr_txreq_dodwt_sx1              ),    // This is also SnpAttr!!! No direct write transactions in CHI-B
                 .mshr_txreq_tracetag_sx1                      (mshr_txreq_tracetag_sx1),               
                 .mshr_txreq_tgtid                             (mshr_txreq_tgtid),                      // for RNF
                 .mshr_txreq_srcid                             (mshr_txreq_srcid),                      // for RNF
                 .encoder_txreq_likelyshared                   (encoder_txreq_likelyshared),            // for RNF
                 .encoder_txreq_exclusive                        (encoder_txreq_exclusive        ),
                 .encoder_txreq_endian                           (encoder_txreq_endian           ),
                 .encoder_txreq_lpid                             (encoder_txreq_lpid             ),
                 .encoder_txreq_expcompack                       (encoder_txreq_expcompack       ),
                 // TXRSP
                 .txrsp_lcrdv                                  (TXRSPLCRDV                        ),
                 .mshr_txrsp_bypass_valid_s1                       (encoder_txrsp_bypass_valid_s1            ),
                 .mshr_txrsp_bypass_qos_s1                         (encoder_txrsp_bypass_qos_s1              ),
                 .mshr_txrsp_bypass_tgtid_s1                       (encoder_txrsp_bypass_tgtid_s1            ),
                 .mshr_txrsp_bypass_txnid_s1                       (encoder_txrsp_bypass_txnid_s1            ),
                 .mshr_txrsp_bypass_opcode_s1                      (encoder_txrsp_bypass_opcode_s1           ),
                 .encoder_txrsp_bypass_resp                        (encoder_txrsp_bypass_resp                ),
                 .mshr_txrsp_bypass_resperr_s1                     (encoder_txrsp_bypass_resperr_s1          ),
                 .mshr_txrsp_bypass_dbid_s1                        (encoder_txrsp_bypass_dbid_s1             ),
                 .mshr_txrsp_bypass_tracetag_s1                    (encoder_txrsp_bypass_tracetag_s1         ),
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
                 .mshr_txrsp_valid_sx1_q                       (noc2buffer_txrsp_valid_sx1_q            ),
                 .mshr_txrsp_qos_sx1                           (noc2buffer_txrsp_qos_sx1                ),
                 .mshr_txrsp_tgtid_sx1                         (noc2buffer_txrsp_tgtid_sx1              ),
                 .mshr_txrsp_txnid_sx1_q                       (noc2buffer_txrsp_txnid_sx1_q            ),
                 .mshr_txrsp_opcode_sx1                        (noc2buffer_txrsp_opcode_sx1             ),
                 .mshr_txrsp_resperr_sx1                       (noc2buffer_txrsp_resperr_sx1            ),
                 .mshr_txrsp_resp_sx1                          (noc2buffer_txrsp_resp_sx1               ),
                 .mshr_txrsp_dbid_sx1                          (noc2buffer_txrsp_dbid_sx1               ),
                 .mshr_txrsp_tracetag_sx1                      (noc2buffer_txrsp_tracetag_sx1           ),
                 // TXDAT
                 .txdat_lcrdv                                  (TXDATLCRDV                        ),
                 .encoder_txdat_qos                            (encoder_txdat_qos                 ),
                 .encoder_txdat_srcid                          (encoder_txdat_srcid               ),
                 .encoder_txdat_homenid                        (encoder_txdat_homenid             ),
                 .encoder_txdat_fwdstate                       (encoder_txdat_fwdstate            ),
                 .encoder_txdat_ccid                           (encoder_txdat_ccid                ),
                 .mshr_txdat_tgtid_sx2                         (mshr_txdat_tgtid_sx2              ),
                 .mshr_txdat_txnid_sx2                         (mshr_txdat_txnid_sx2              ),
                 .mshr_txdat_opcode_sx2                        (mshr_txdat_opcode_sx2             ),
                 .mshr_txdat_resp_sx2                          (mshr_txdat_resp_sx2               ),
                 .mshr_txdat_resperr_sx2                       (mshr_txdat_resperr_sx2            ),
                 .mshr_txdat_dbid_sx2                          (mshr_txdat_dbid_sx2               ),
                 .dbf_txdat_data_sx1                           (dbf_txdat_data_sx1                ),
                 .dbf_txdat_idx_sx1                            (dbf_txdat_idx_sx1                 ),
                 .dbf_txdat_be_sx1                             (dbf_txdat_be_sx1                  ),
                 .dbf_txdat_pe_sx1                             (dbf_txdat_pe_sx1                  ),
                 .dbf_txdat_valid_sx1                          (dbf_txdat_valid_sx1               ),

                 //outputs
                 // RXRSP
                 .rxrsp_lcrdv                                  (RXRSPLCRDV                        ),
                 .li_mshr_rxrsp_valid_s0                       (li_rxbuf_rxrsp_valid_s0            ),
                 .li_mshr_rxrsp_srcid_s0                       (li_rxbuf_rxrsp_srcid_s0            ),
                 .li_mshr_rxrsp_txnid_s0                       (li_rxbuf_rxrsp_txnid_s0            ),
                 .li_mshr_rxrsp_opcode_s0                      (li_rxbuf_rxrsp_opcode_s0           ),
                 .li_mshr_rxrsp_resp_s0                        (li_rxbuf_rxrsp_resp_s0             ),
                 .li_mshr_rxrsp_fwdstate_s0                    (li_rxbuf_rxrsp_fwdstate_s0         ),
                 .li_mshr_rxrsp_dbid_s0                        (li_rxbuf_rxrsp_dbid_s0             ),
                 .li_mshr_rxrsp_pcrdtype_s0                    (li_rxbuf_rxrsp_pcrdtype_s0         ),
                 .rxrsp_buf_ready                               (rxrsp_buf_ready                     ),
                 // RXDAT
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
                 .li_decoder_rxdat_homenid                     (li_decoder_rxdat_homenid),        // added for RNF
                 .li_decoder_rxdat_ccid                        (li_decoder_rxdat_ccid),           // added for RNF
                 .li_decoder_rxdat_dbid                        (li_decoder_rxdat_dbid),           // added for RNF
                 .rxdat_buf_ready                               (rxdat_buf_ready),    // added for RNF
                 // transmit channel signals
                 .txreqflitv                                   (TXREQFLITV                        ),
                 .txreqflit                                    (TXREQFLIT                         ),
                 .txreqflitpend                                (TXREQFLITPEND                     ),
                 .txrspflitv                                   (TXRSPFLITV                        ),
                 .txrspflit                                    (TXRSPFLIT                         ),
                 .txrspflitpend                                (TXRSPFLITPEND                     ),
                 .txrsp_mshr_retryack_won_s1                   (txrsp_mshr_retryack_won_s1        ),
                 .txrsp_mshr_pcrdgnt_won_s2                    (txrsp_mshr_pcrdgnt_won_s2         ),
                 .txrsp_cache_crd_avail                        (txrsp_cache_crd_avail),     // added for RNF 
                 .txrsp_mshr_won_sx1                           (txrsp_rxdat_buf_won_sx1           ),
                 .txreq_mshr_won_sx1                           (txreq_enc_won_sx1                ),
                 .txreq_encoder_crd_avail_s1                   (txreq_encoder_crd_avail_s1        ),
                 .txreq_mshr_bypass_won_s1                         (txreq_rxbuf_bypass_won_s1              ),
                 .txrsp_mshr_bypass_won_s1                         (txrsp_encoder_bypass_won_s1              ),
                 .txdatflitv                                   (TXDATFLITV                        ),
                 .txdatflit                                    (TXDATFLIT                         ),
                 .txdatflitpend                                (TXDATFLITPEND                     ),
                 .txdat_mshr_clr_dbf_busy_valid_sx3            (txdat_mshr_clr_dbf_busy_valid_sx3 ),
                 .txdat_mshr_clr_dbf_busy_idx_sx3              (txdat_mshr_clr_dbf_busy_idx_sx3   ),
                 .txdat_mshr_rd_idx_sx2                        (txdat_mshr_rd_idx_sx2             ),
                 .txdat_mshr_busy_sx                           (txdat_mshr_busy_sx                ),
                 // RXSNP I/O
                 .rxsnpflitv                                     (RXSNPFLITV                         ),
                 .rxsnpflit                                      (RXSNPFLIT                          ),
                 .rxsnpflitpend                                  (RXSNPFLITPEND                      ),
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
                 .rxsnp_lcrdv                                    (RXSNPLCRDV                         ),
                // Link Layer handshake
                 .TXLINKACTIVEREQ                                (TXLINKACTIVEREQ),
                 .TXLINKACTIVEACK                                (TXLINKACTIVEACK),
                 .RXLINKACTIVEREQ                                (RXLINKACTIVEREQ),
                 .RXLINKACTIVEACK                                (RXLINKACTIVEACK),
                 .TXACTIVE                                       (TXACTIVE),
                 .RXACTIVE                                       (RXACTIVE),
                 .tx_active_ready                                (tx_active_ready)
             );


endmodule
