# mig_ddr4.tcl — generate the DDR4 controller IP for VCU118 onboard SDRAM.
#
# Run once via:
#   vivado -mode batch -source ip/mig_ddr4.tcl
# from the fpga/ directory. The output .xci + generated DDR4 pin XDC are then
# picked up by scripts/sources.tcl on subsequent builds.
#
# Board preset: xilinx.com:vcu118:part0:2.4 (set in board_part of project).
# The preset auto-fills 2 GB DDR4 SODIMM on bank C0 with the correct pin map.
#
# AXI slave port: presented to the SN-F via fpga_snf_axi_bridge.sv.
# Width:  256-bit data (matches our axi2mem / SN-F internal beat width).
# Clock:  ddr4_axi_clk (≈300 MHz from MIG) — the SN-F side runs in clk_sys
#         domain, so there is an async CDC FIFO between the two.

set fpga_dir  [file normalize [file dirname [info script]]/..]
set ip_dir    $fpga_dir/ip
set part      "xcvu9p-flga2104-2L-e"
set board     "xilinx.com:vcu118:part0:2.4"

create_project -in_memory -part $part
set_property board_part $board [current_project]

create_ip -name ddr4 -vendor xilinx.com -library ip \
    -module_name mig_ddr4_0 -dir $ip_dir

# Board-aware preset fills DDR4 pin map automatically.
set_property -dict [list \
    CONFIG.C0.DDR4_TimePeriod      {1250} \
    CONFIG.C0.DDR4_InputClockPeriod {4000} \
    CONFIG.C0.DDR4_AxiSelection    {true} \
    CONFIG.C0.DDR4_AxiDataWidth    {256} \
    CONFIG.C0.DDR4_AxiAddressWidth {31} \
    CONFIG.C0.DDR4_AxiIDWidth      {4} \
    CONFIG.C0.DDR4_AxiArbitrationScheme {RD_PRI_REG} \
    CONFIG.C0.DDR4_DataWidth       {72} \
    CONFIG.C0.DDR4_Ecc             {false} \
    CONFIG.RECONFIG_XML_PATH       {} \
] [get_ips mig_ddr4_0]

generate_target all  [get_ips mig_ddr4_0]
synth_ip             [get_ips mig_ddr4_0]

puts "==> mig_ddr4_0 generated under $ip_dir/mig_ddr4_0/"
