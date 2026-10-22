# cva6-RNF FPGA prototype — VCU118

Target: **Xilinx VCU118 (XCVU9P-FLGA2104-2L-e)**.
Scope: **NUM_RNFS** × (CVA6 + L1.5/RN-F) → CHI 2×2 mesh → HN-F (L3+SF) → SN-F.

`NUM_RNFS` is a top-level parameter (default `1`, max `2` with the current
2×2 mesh). All cores share a single JTAG TAP — the DM's `hartsel` selects
which hart OpenOCD addresses.

## Prerequisites

- **Vivado 2022.x or later, Enterprise/Design Edition** (UltraScale+ VU9P is
  *not* covered by free Vivado ML Standard — use an XUP academic license or
  the VCU118 board voucher).
- `vivado` on `PATH`.

## Build

```bash
cd cva6-RNF/fpga

# One-time: generate the IPs (clk_wiz + MIG DDR4).
vivado -mode batch -source ip/clk_wiz.tcl
vivado -mode batch -source ip/mig_ddr4.tcl

# Build (synth + impl + bitstream).
vivado -mode batch -source scripts/build.tcl
#                            -tclargs synth   # just synth
#                            -tclargs impl    # synth + impl
#                            -tclargs bit     # full pipeline (default)
```

To change the core count, override the top-level `NUM_RNFS` parameter
(default 1, max 2):

```bash
NUM_RNFS=2 vivado -mode batch -source scripts/build.tcl -tclargs synth
```

Artifacts land in `build/{synth,impl}/`. Final bitstream: `build/cva6_chi_fpga.bit`.

### Performance knobs

| Env var              | Effect                                                              |
|----------------------|---------------------------------------------------------------------|
| `NUM_RNFS=N`         | Number of CVA6 cores (default 1, max 2 for the 2×2 mesh).            |
| `PERF_OPT=1`         | opt/place/route → ExploreWithRemap/Explore/AggressiveExplore (~2× impl time). |
| `POSTROUTEPHYSOPT=1` | Extra `phys_opt_design -directive ExploreWithAggressiveHoldFix` after route. |
| `HNF_USE_BRAM=1`     | `+define+HNF_DELAY_ONE_CYCLE` → HNF SRAMs gain a registered read, becoming BRAM-eligible. **Adds 1 cycle of HNF read latency; verify behaviour first.** |

`synth_design` always runs with `-retiming`. See `scripts/settings.tcl`.

## Functional simulation (Questa) with all Xilinx IPs

Exports a Vivado-prepared Questa run from the same source tree.  Use this
when you want to simulate the synthesizable FPGA design (RTL + behavioural
models of `clk_wiz_0`, MIG, etc.) in the wave tooling already used by the
`tb/` flow.

**One-time** — compile Xilinx simulation libraries for Questa:

```bash
vivado -mode batch -source - <<'EOF'
compile_simlib -simulator questa \
               -directory $env(HOME)/.vivado-simlib \
               -family ultrascale_plus
EOF
```

**Per run** — generate the Questa runner from inside Vivado after the
in-memory project is loaded:

```bash
vivado -mode batch -source - <<'EOF'
create_project -in_memory -part xcvu9p-flga2104-2L-e
source scripts/sources.tcl
read_verilog -sv fpga/sim/tb_cva6_chi_fpga.sv   ;# board-level TB
export_simulation -simulator questa \
                  -directory fpga/sim/questa_run \
                  -ip_user_files_dir fpga/sim/ip_user \
                  -lib_map_path $env(HOME)/.vivado-simlib
EOF
```

The export drops a self-contained `fpga/sim/questa_run/tb_cva6_chi_fpga.sh`
together with `compile.do` and `simulate.do`.  Run with `vsim` exactly as
the `tb/` flow does — IP behavioural models, `glbl.v`, and the unisim /
secureip libraries are wired in automatically.

> The board-level TB at `fpga/sim/tb_cva6_chi_fpga.sv` is not committed
> yet; add it when you want to drive the design with clock + reset +
> JTAG idle stimulus and observe the SN-F AXI master / LED outputs.

## System

```
   JTAG (PMOD1)            On-board USB-JTAG (unused)
        │
        ▼
   dmi_jtag + dm_top ─── debug_req ──▶  CVA6
                                          │  L1.5 + rnf_link (RN-F)
                                          ▼
                                   chi_icn_mesh (2×2 OpenNoC)
                                    │            │
                                    ▼            ▼
                                  HN-F          SN-F  ── AXI master ──▶ MIG ──▶ DDR4
                                  (L3+SF)               (pin-exposed; MIG wiring pending)
```

## JTAG (PMOD1, J53 header)

| Signal    | Pin |
|-----------|-----|
| `tck_i`   | N28 |
| `td_i`    | M30 |
| `td_o`    | N30 |
| `tms_i`   | P30 |
| `trst_ni` | P29 |

Max TCK = 10 MHz. Connect an FTDI FT2232-class adapter (Olimex
ARM-USB-TINY-H, SiPEED RV-Debugger, etc.). Use stock OpenOCD with a
`cva6.cfg` matching the dmi_jtag IDCODE.

## Directory layout

```
fpga/
├── README.md
├── scripts/
│   ├── build.tcl       # synth + impl + bitstream stages
│   ├── settings.tcl    # synth/impl directives + Verilog defines
│   └── sources.tcl     # synthesizable RTL list + flist parser
├── rtl/
│   ├── cva6_chi_fpga_top.sv     # board top (pins ↔ logic)
│   └── cva6_debug_subsystem.sv  # dmi_jtag + dm_top
├── constraints/
│   └── vcu118.xdc      # clocks, reset, PMOD1 JTAG, LEDs
├── ip/
│   ├── clk_wiz.tcl     # 156.25 MHz LVDS → 50 MHz sys + 200 MHz DDR ref
│   └── mig_ddr4.tcl    # DDR4 controller (256-bit AXI slave)
├── bootrom/            # placeholder; bootrom hookup pending
└── build/              # (gitignored)
```

Source discovery: `scripts/sources.tcl` reads each HN-F / SN-F / mesh / debug
file explicitly, then walks `singlecore-cva6/rnf_flist` (OpenPiton `-f` flist)
to pull in CVA6 + L1.5 + rnf_link + common_cells. Patterns in `skip_patterns`
filter OpenPiton chip-level (`dynamic_node`, `dmbr`, `ucb_bus*`,
`noc_axilite_bridge`, `*.tmp.v`, `instr_tracer*`).

## Status / known TODOs

- `rnf_top.sv` ties `debug_req_i` to 0 internally — needs a one-line patch
  (expose `debug_req_i` as a port, forward to `ariane_verilog_wrap`) before
  OpenOCD halt works against CVA6. JTAG TAP itself responds in the meantime.
- `snf`'s AXI master is exposed at the top level but not yet routed to MIG
  (DDR4). Driving the bitstream will require either a MIG bridge or a
  temporary Xilinx AXI BRAM controller. The sim-only `mem_ss` wrapper
  (snf + axi2mem + inline BRAM) is intentionally not pulled into the FPGA
  flow.
- HN-F caches are FPGA-sized in the top wrapper (L3 = 64 KB / 4-way,
  SF = 1024 entries / 4-way) instead of the simulation defaults (4 MB,
  131072 × 16). The OpenNoC SRAM cells use async read which forces
  Vivado to LUTRAM — restoring sim sizes would consume >100% of the
  device's SLICEM LUTs. Enable `HNF_USE_BRAM=1` to opt into the
  registered-read path and BRAM mapping, with the latency caveat above.
- UART is stubbed; pins commented in the XDC.
- Bootrom path is not yet wired. JTAG-loaded code (OpenOCD `load_image`)
  is the bring-up path.
- Single-core only. The mesh slot for RNF[1] is tied off.

## Simulation parity

Mesh + mem_ss is fully verified in simulation:

- 166/166 Murphi vectors pass
- 102/106 BFS vectors pass (4 pre-existing testgen-driver gaps, not RTL)
- Cross-product `(ICN, SNF) ∈ {behavioral, mesh} × {tbsnf, memss}` all
  functionally equivalent.
