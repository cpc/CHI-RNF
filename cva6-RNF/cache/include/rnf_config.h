 /*
 * Copyright (c) 2026 Tampere University
 * Licensed under the Solderpad Hardware License v 2.1, see LICENSE for details.
 * SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
 */

//==================================================================================================
//  Filename        : rnf_config
//  Author          : Teemu Rinne, Tampere University
//
//  Description     : Size configuration macros for AMBA CHI based RN-F coherent cache
//
//==================================================================================================


`ifndef RNF_CONFIGS
`define RNF_CONFIGS
`endif

`define RNF_CACHE_SIZE 32768    //262144 //131072 //65536 //32768(default)
`define RNF_WAY_COUNT 4
`define RNF_WAY_WIDTH 2 //$clog(`RNF_WAY_COUNT)
`define RNF_MSHR_COUNT 2

// Uncomment RNF_WMT_EXTENDED_ALIAS if: Set-count = (size/64B)/way-count > 128
//`define RNF_WMT_EXTENDED_ALIAS

