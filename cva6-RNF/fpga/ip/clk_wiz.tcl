# clk_wiz.tcl — generate the system clock-wizard IP.
#
# Run once via:
#   vivado -mode batch -source ip/clk_wiz.tcl
# from the fpga/ directory. The output .xci is then picked up by
# scripts/sources.tcl on subsequent builds.
#
# Inputs:  250 MHz LVDS (SYSCLK1 on VCU118)
# Outputs: clk_out_sys  = 50 MHz  (CHI / CVA6 system clock — start low!)
#          clk_out_ddr  = 200 MHz (DDR4 IO reference for MIG)

set fpga_dir  [file normalize [file dirname [info script]]/..]
set ip_dir    $fpga_dir/ip
set part      "xcvu9p-flga2104-2L-e"

create_project -in_memory -part $part

create_ip -name clk_wiz -vendor xilinx.com -library ip \
    -module_name clk_wiz_0 -dir $ip_dir

# Input clock is the 156.25 MHz LVDS pair on F31/G31 (chipset_clk_osc).
# Period = 1/156.25 MHz = 6.4 ns.
set_property -dict [list \
    CONFIG.PRIM_IN_FREQ                {156.25} \
    CONFIG.PRIM_SOURCE                 {Differential_clock_capable_pin} \
    CONFIG.CLKIN1_JITTER_PS            {64.0} \
    CONFIG.CLKOUT1_USED                {true} \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ  {50.000} \
    CONFIG.CLKOUT2_USED                {true} \
    CONFIG.CLKOUT2_REQUESTED_OUT_FREQ  {200.000} \
    CONFIG.RESET_TYPE                  {ACTIVE_HIGH} \
    CONFIG.USE_LOCKED                  {true} \
] [get_ips clk_wiz_0]

# Generate the synthesizable wrapper + out-of-context DCP so build.tcl can
# pick up `clk_wiz_0` by name.
generate_target all  [get_ips clk_wiz_0]
synth_ip             [get_ips clk_wiz_0]

puts "==> clk_wiz_0 generated under $ip_dir/clk_wiz_0/"
