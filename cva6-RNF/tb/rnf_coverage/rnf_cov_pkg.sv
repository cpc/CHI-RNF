/*
 * Copyright (c) 2026 Customized Parallel Computing (CPC) Group, Tampere University
 * Author: Abdesattar Kalache <abdesattar.kalache@tuni.fi>
 *
 * SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
 *
 * Licensed under the Solderpad Hardware License v2.1 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at:
 *
 *     https://solderpad.org/licenses/SHL-2.1/
 *
 * Unless required by applicable law or agreed to in writing, any work
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
 * implied.  See the License for the specific language governing
 * permissions and limitations under the License.
 */
/*
 * rnf_cov_pkg.sv
 *
 * Shared typedefs for rnf_phase_tracker + rnf_coverage.  Lives in a
 * package so coverpoints can reference enum bins via the `::` qualifier
 * (module-scope typedefs can't be reached that way).
 */

package rnf_cov_pkg;

    typedef enum logic [2:0] {
        TX_IDLE                = 3'd0,
        TX_AWAIT_RSP           = 3'd1,
        TX_AWAIT_DATA_SEND     = 3'd2,
        TX_AWAIT_COMP          = 3'd3,
        TX_AWAIT_COMPACK_CLEAN = 3'd4,
        TX_AWAIT_COMPACK_DIRTY = 3'd5
    } tx_phase_e;

    typedef enum logic [3:0] {
        TX_NONE          = 4'd0,
        TX_READCLEAN     = 4'd1,
        TX_READUNIQUE    = 4'd2,
        TX_MAKEUNIQUE    = 4'd3,
        TX_CLEANUNIQUE   = 4'd4,
        TX_CLEANINVALID  = 4'd5,
        TX_CLEANSHARED   = 4'd6,
        TX_EVICT         = 4'd7,
        TX_WRITEBACKFULL = 4'd8,
        TX_WRITECLEANFUL = 4'd9,
        TX_ATOMICLOAD    = 4'd10,
        TX_ATOMICSTORE   = 4'd11,
        TX_OTHER         = 4'd15
    } tx_op_e;

    typedef enum logic [2:0] {
        RX_NONE            = 3'd0,
        RX_SNPCLEAN        = 3'd1,
        RX_SNPUNIQUE       = 3'd2,
        RX_SNPMAKEINVALID  = 3'd3,
        RX_SNPCLEANINVALID = 3'd4,
        RX_SNPSHARED       = 3'd5,
        RX_SNPOTHER        = 3'd7
    } rx_snp_op_e;

    typedef enum logic [2:0] {
        L1_I  = 3'd0,
        L1_SC = 3'd1,
        L1_UC = 3'd2,
        L1_SD = 3'd3,
        L1_UD = 3'd4
    } l1_state_e;

    typedef enum logic [2:0] {
        SR_UNK, SR_I, SR_SC, SR_I_D, SR_SC_D, SR_I_PD, SR_SC_PD
    } snp_resp_kind_e;

endpackage
