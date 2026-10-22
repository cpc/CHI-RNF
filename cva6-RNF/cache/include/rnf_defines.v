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
* Original author:
*    Wenhao Li <liwenhao@bosc.ac.cn>
*    Nana Cai <cainana@bosc.ac.cn>
*/


// Modifications: 
/*
 * Copyright (c) 2026 Tampere University
 * Licensed under the Solderpad Hardware License v 2.1, see LICENSE for details.
 * SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
 */

//==================================================================================================
//  Filename        : rnf_defines (original hnf_defines)
//  Modified        : Teemu Rinne, Tampere University
//
//  Description     : Macro definitions of AMBA CHI based RN-F coherent cache 
//
//==================================================================================================




`ifndef RNF_DEFINES
`define RNF_DEFINES

`include "chie_defines.v"


`define CHI_CACHE_LINE_WIDTH                   512
`define CHI_CACHE_BE_WIDTH                     64

// rnf_link_req_channel_lcredit
`define RNF_LCRD_REQ_CNT_WIDTH             4
`define RNF_LCRD_REQ_CNT_RANGE             3:0
`define RNF_LCRD_REQ_CNT_MSB               3
`define RNF_LCRD_REQ_CNT_LSB               0
`define RNF_LCRD_REQ_MAX_VALUE             XP_LCRD_NUM_PARAM
`define RNF_LCRD_INCDEC_ONE                    1
`define RNF_LCRD_INCDEC_TWO                    2
`define RNF_LCRD_INCDEC_THREE                  3

//rnf_link_rsp_channel_lcredit
// TXRSP
`define RNF_LCRD_RSP_CNT_WIDTH             4
`define RNF_LCRD_RSP_CNT_RANGE             3:0
`define RNF_LCRD_RSP_CNT_MSB               3
`define RNF_LCRD_RSP_CNT_LSB               0
`define RNF_LCRD_RSP_MAX_VALUE             XP_LCRD_NUM_PARAM
// RXRSP
`define RNF_LCRD_RXRSP_CNT_WIDTH             4
`define RNF_LCRD_RXRSP_CNT_RANGE             3:0
`define RNF_LCRD_RXRSP_CNT_MSB               3
`define RNF_LCRD_RXRSP_CNT_LSB               0
`define RNF_LCRD_RXRSP_MAX_VALUE             1
`define RNF_LCRD_RXRSP_CNT_LIMIT             2**`RNF_LCRD_RXRSP_CNT_WIDTH-1-`RNF_LCRD_RXRSP_MAX_VALUE


//rnf_link_snp_channel_lcredit
`define RNF_SNP_FLIT_RANGE                 `CHIE_SNP_FLIT_WIDTH-1:0
`define RNF_SNP_FLIT_WIDTH                 `CHIE_SNP_FLIT_WIDTH
// RXSNP
`define RNF_LCRD_RXSNP_CNT_WIDTH             4
`define RNF_LCRD_RXSNP_CNT_RANGE             3:0
`define RNF_LCRD_RXSNP_CNT_MSB               3
`define RNF_LCRD_RXSNP_CNT_LSB               0
`define RNF_LCRD_RXSNP_MAX_VALUE             1
`define RNF_LCRD_RXSNP_CNT_LIMIT             2**`RNF_LCRD_RXSNP_CNT_WIDTH-1-`RNF_LCRD_RXSNP_MAX_VALUE


//rnf_link_dat_channel_lcredit
// TXDAT
`define RNF_LCRD_DAT_CNT_WIDTH             4
`define RNF_LCRD_DAT_CNT_RANGE             3:0
`define RNF_LCRD_DAT_CNT_MSB               3
`define RNF_LCRD_DAT_CNT_LSB               0
`define RNF_LCRD_DAT_MAX_VALUE             XP_LCRD_NUM_PARAM
// RXDAT
`define RNF_LCRD_RXDAT_CNT_WIDTH             4
`define RNF_LCRD_RXDAT_CNT_RANGE             3:0
`define RNF_LCRD_RXDAT_CNT_MSB               3
`define RNF_LCRD_RXDAT_CNT_LSB               0
`define RNF_LCRD_RXDAT_MAX_VALUE             8  // 2 x 2 (2 DAT flits per msg, 2 store-req-entries in l15)
`define RNF_LCRD_RXDAT_CNT_LIMIT             2**`RNF_LCRD_RXDAT_CNT_WIDTH-1-`RNF_LCRD_RXDAT_MAX_VALUE

`define RNF_QOS_CLASS_WIDTH                    3
`define RNF_QOS_CLASS_SEQ                      4
`define RNF_QOS_CLASS_HHIGH                    3
`define RNF_QOS_CLASS_HIGH                     2
`define RNF_QOS_CLASS_MED                      1
`define RNF_QOS_CLASS_LOW                      0

`define RX_STATE_WIDTH 4
`define RX_STATE_IDLE 4'd0
`define RX_STATE_REQ_CHECK 4'd1
`define RX_STATE_RECEIVING_DATA 4'd2
`define RX_STATE_WAITING_ACK 4'd3
`define RX_STATE_WAITING_SNP_ACK 4'd4
`define RX_STATE_WAIT_CHI_TXRSP 4'd5
`define RX_STATE_SEND_DATA 4'd6
`define RX_STATE_SEND_NC_DATA 4'd7

`define RESP_FLIT_STATE_WIDTH 4
`define RESP_STATE_IDLE 4'd0
`define RESP_STATE_WAIT_DAT 4'd1
`define RESP_SEND_SNPDAT 4'd2
`define RESP_SEND_RSP 4'd3
`define RESP_SEND_CBDAT 4'd4
`define RESP_SEND_WRBCK 4'd5
`define RESP_WAIT_DBID 4'd6
`define RESP_SEND_WRBCK_DAT 4'd7

`endif
