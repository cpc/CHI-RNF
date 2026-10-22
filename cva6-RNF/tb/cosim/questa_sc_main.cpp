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
// questa_sc_main.cpp — sc_main for Questa SV+SC co-simulation.
//
// sc_main must exist in the .so but must NOT create any SC instances.
// In Questa's SV+SC co-sim mode sc_main's argc/argv do NOT carry vsim
// plusargs.  Plusarg handling is done via DPI-C:
//
//   +rnf_verbose  — SV reads it via $test$plusargs and calls chi_set_rnf_verbose()
//                   (defined in chi_tlm_rnf.cpp), which sets g_rnf_verbose.
#include <systemc>

int sc_main(int argc, char** argv) {
    (void)argc; (void)argv;
    return 0;
}
