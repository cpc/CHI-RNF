# vcu118.xdc — VCU118 constraints for the cva6-RNF prototype.
#
# Derived from openpiton/piton/design/xilinx/vcu118/constraints.xdc,
# trimmed to: clocks, reset, PMOD1 JTAG (RISC-V Debug Module), LEDs.
# UART/SD/Ethernet/DDR4 sections are commented out — re-enable when the
# corresponding subsystem is brought up.

# ── Bitstream configuration ─────────────────────────────────────────────────
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 8 [current_design]
set_property BITSTREAM.CONFIG.EXTMASTERCCLK_EN div-1 [current_design]
set_property BITSTREAM.CONFIG.SPI_FALL_EDGE YES [current_design]
set_property BITSTREAM.CONFIG.SPI_OPCODE 8'h6B [current_design]
set_property CONFIG_MODE SPIx8 [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.UNUSEDPIN Pulldown [current_design]
set_property CONFIG_VOLTAGE 1.8 [current_design]

# ── System clock (≈100 MHz reference, board "SYSCLK0" / chipset_clk_osc) ────
# F31/G31 is the 156.25 MHz LVDS pair used by OpenPiton.  We will divide it
# down to the CHI/CVA6 clock inside clk_wiz_0.
set_property -dict {PACKAGE_PIN F31 IOSTANDARD DIFF_SSTL12} [get_ports "sys_clk_n"]
set_property -dict {PACKAGE_PIN G31 IOSTANDARD DIFF_SSTL12} [get_ports "sys_clk_p"]
# The clk_wiz IP's auto-XDC declares an (anonymous) create_clock on
# sys_clk_p with period 6.400 -- we let that win to avoid the
# 'completely overrides clock' critical warning.  Downstream constraints
# reference it via `[get_clocks -of_objects [get_ports sys_clk_p]]`.
set_property CLOCK_DEDICATED_ROUTE BACKBONE [get_nets -of_objects [get_pins u_clk_wiz/inst/clkin1_ibufds/I]] \
    -quiet

# ── Push-button reset (active-high on this board) ──────────────────────────
set_property -dict {PACKAGE_PIN L19 IOSTANDARD LVCMOS12} [get_ports "sys_rst_n"]
set_false_path -from [get_ports sys_rst_n]

# ── JTAG TAP for RISC-V Debug Module (PMOD1, Male header J53) ──────────────
# Pin assignments lifted from openpiton.  Connect an FTDI FT2232-class JTAG
# adapter (Olimex ARM-USB-TINY-H, SiPEED RV-Debugger, etc.) here.
set_property -dict {PACKAGE_PIN N28 IOSTANDARD LVCMOS12} [get_ports tck_i]
set_property -dict {PACKAGE_PIN M30 IOSTANDARD LVCMOS12} [get_ports td_i]
set_property -dict {PACKAGE_PIN N30 IOSTANDARD LVCMOS12} [get_ports td_o]
set_property -dict {PACKAGE_PIN P30 IOSTANDARD LVCMOS12} [get_ports tms_i]
set_property -dict {PACKAGE_PIN P29 IOSTANDARD LVCMOS12} [get_ports trst_ni]

# JTAG TCK is 10 MHz max — declare an external clock and false-path CDC.
create_clock -period 100.000 -name tck_i -waveform {0.000 50.000} [get_ports tck_i]
set_input_delay  -clock tck_i -clock_fall 5 [get_ports td_i]
set_input_delay  -clock tck_i -clock_fall 5 [get_ports tms_i]
set_output_delay -clock tck_i             5 [get_ports td_o]
set_false_path -from [get_ports trst_ni]

# Bound CDC delay between TCK and clk_sys domains; dmi_jtag has explicit
# crossing logic, this just keeps the place-and-route honest.
# Reference the IP's auto-derived input clock by its port object so we
# don't depend on its anonymous name.
set sysclk_in [get_clocks -of_objects [get_ports sys_clk_p]]
set_max_delay -datapath_only -from [get_clocks -include_generated_clocks $sysclk_in] -to [get_clocks tck_i] 8.0
set_max_delay -datapath_only -from [get_clocks tck_i] -to [get_clocks -include_generated_clocks $sysclk_in] 8.0

# TCK landed on a non-clock-capable pin — let the router accept sub-optimal
# placement (the JTAG path is async + low-frequency).
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets tck_i_IBUF_inst/O]

# ── LEDs ────────────────────────────────────────────────────────────────────
set_property -dict {PACKAGE_PIN AT32 IOSTANDARD LVCMOS12} [get_ports {leds[0]}]
set_property -dict {PACKAGE_PIN AV34 IOSTANDARD LVCMOS12} [get_ports {leds[1]}]
set_property -dict {PACKAGE_PIN AY30 IOSTANDARD LVCMOS12} [get_ports {leds[2]}]
set_property -dict {PACKAGE_PIN BB32 IOSTANDARD LVCMOS12} [get_ports {leds[3]}]
set_property -dict {PACKAGE_PIN BF32 IOSTANDARD LVCMOS12} [get_ports {leds[4]}]
set_property -dict {PACKAGE_PIN AU37 IOSTANDARD LVCMOS12} [get_ports {leds[5]}]
set_property -dict {PACKAGE_PIN AV36 IOSTANDARD LVCMOS12} [get_ports {leds[6]}]
set_property -dict {PACKAGE_PIN BA37 IOSTANDARD LVCMOS12} [get_ports {leds[7]}]

# ── UART (commented until UART subsystem is in scope) ───────────────────────
# set_property -dict {PACKAGE_PIN AW25 IOSTANDARD LVCMOS18} [get_ports "uart_rx"]
# set_property -dict {PACKAGE_PIN BB21 IOSTANDARD LVCMOS18} [get_ports "uart_tx"]

# ── DDR4 pins (commented; MIG IP supplies its own pin XDC once integrated) ─
# See openpiton/piton/design/xilinx/vcu118/constraints.xdc for the full map.
