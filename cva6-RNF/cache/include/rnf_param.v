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
*    Ziqing Li <liziqing@bosc.ac.cn>
*    Chunyan Lin <linchunyan@bosc.ac.cn>
*/


// Modifications: 
/*
 * Copyright (c) 2026 Tampere University
 * Licensed under the Solderpad Hardware License v 2.1, see LICENSE for details.
 * SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
 */

//==================================================================================================
//  Filename        : rnf_param (original hnf_param)
//  Modified        : Teemu Rinne, Tampere University
//
//  Description     : Module parameters of AMBA CHI based RN-F coherent cache
//                      - cache size parameters are configured in rnf_config.h 
//
//==================================================================================================



//`ifndef RNF_PARAM_H
`define RNF_PARAM_H
`define RNF_PARAM #( \
    parameter CHIE_REQ_ADDR_WIDTH_PARAM     = 44,    \
    parameter CHIE_SNP_ADDR_WIDTH_PARAM     = 41,    \
    parameter CHIE_NID_WIDTH_PARAM          = 7,     \
    parameter CHIE_DATA_WIDTH_PARAM         = 256,   \
    parameter CHIE_BE_WIDTH_PARAM           = CHIE_DATA_WIDTH_PARAM/8,    \
    parameter CHIE_DATACHECK_WIDTH_PARAM    = 0,    \
    parameter CHIE_POISON_WIDTH_PARAM       = 0,     \
    parameter CHIE_REQ_RSVDC_WIDTH_PARAM    = 0,     \
    parameter CHIE_DAT_RSVDC_WIDTH_PARAM    = 0,     \
    parameter HNF_NID_PARAM                 = 2,     \
    parameter XP_LCRD_NUM_PARAM             = 15,    \
    parameter CACHED_REGION_BASE            = 'h80000000,\
    parameter CACHED_REGION_SIZE            = 'h80000, \
    parameter BOOT_REGION_BASE              = 'hFFF1010000,\
    parameter BOOT_REGION_SIZE              = 'h10000, \
    parameter IO_REGION_BASE                = 'hFFF1000000,\
    parameter IO_REGION_SIZE                = 'h1000, \
    parameter RNF_NID                       = 0)

`define RNF_PARAM_INST #( \
    .CHIE_REQ_ADDR_WIDTH_PARAM          (CHIE_REQ_ADDR_WIDTH_PARAM         ), \
    .CHIE_SNP_ADDR_WIDTH_PARAM          (CHIE_SNP_ADDR_WIDTH_PARAM         ), \
    .CHIE_NID_WIDTH_PARAM               (CHIE_NID_WIDTH_PARAM              ), \
    .CHIE_DATA_WIDTH_PARAM              (CHIE_DATA_WIDTH_PARAM             ), \
    .CHIE_BE_WIDTH_PARAM                (CHIE_BE_WIDTH_PARAM               ), \
    .CHIE_DATACHECK_WIDTH_PARAM         (CHIE_DATACHECK_WIDTH_PARAM        ), \
    .CHIE_POISON_WIDTH_PARAM            (CHIE_POISON_WIDTH_PARAM           ), \
    .CHIE_REQ_RSVDC_WIDTH_PARAM         (CHIE_REQ_RSVDC_WIDTH_PARAM        ), \
    .CHIE_DAT_RSVDC_WIDTH_PARAM         (CHIE_DAT_RSVDC_WIDTH_PARAM        ), \
    .HNF_NID_PARAM                      (HNF_NID_PARAM                     ), \
    .XP_LCRD_NUM_PARAM                  (XP_LCRD_NUM_PARAM                 ), \
    .CACHED_REGION_BASE                 (CACHED_REGION_BASE                ), \
    .CACHED_REGION_SIZE                 (CACHED_REGION_SIZE                ), \
    .BOOT_REGION_BASE                   (BOOT_REGION_BASE                  ), \
    .BOOT_REGION_SIZE                   (BOOT_REGION_SIZE                  ), \
    .IO_REGION_BASE                     (IO_REGION_BASE                    ), \
    .IO_REGION_SIZE                     (IO_REGION_SIZE                    ), \
    .RNF_NID                            (RNF_NID                           ))

//`endif /* RNF_PARAM_H */
