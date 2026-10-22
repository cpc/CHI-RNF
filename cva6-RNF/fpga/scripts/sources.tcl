# sources.tcl — synthesizable RTL list for the VCU118 FPGA prototype.
#
# Only synthesizable code goes in here:
#   - HN-F                    (opennoc/rtl/src/hnf + overrides in src/)
#   - SN-F                    (opennoc/rtl/src/snf — but we wrap it via mem_ss
#                              for AXI to MIG)
#   - CHI mesh ICN            (src/mesh/, opennoc/rtl/misc/chi_xp_channel.v,
#                              xp_sel_bit_from_vec.v)
#   - RN-F CHI flit layer     (cache/rnf_link + cache/)
#   - L1.5                    (singlecore-cva6/tile/ariane/.../l15)
#   - CVA6                    (singlecore-cva6/tile/ariane/.../core/cva6)
#   - riscv-dbg               (debug module + JTAG TAP)
#   - axi2mem, common_cells, axi infra
#   - FPGA glue               (fpga/rtl/*)
#
# Testbench code (chi_icn_beh.sv, chi_monitor.sv, tb_snf*.v, tlm_rnf_hnf_tb.sv,
# testgen/*) is excluded.

set proj_root [file normalize $fpga_dir/..]

# ── Include directories ─────────────────────────────────────────────────────
set incdirs [list \
    $proj_root/src \
    $proj_root/cache/include \
    $proj_root/common_cells/include \
    $proj_root/opennoc/rtl/include \
]
set_property include_dirs $incdirs [current_fileset]

# ── Verilog packages first ──────────────────────────────────────────────────
# dm_pkg is needed before the FPGA debug subsystem reads.  Other CHI/CVA6
# packages (axi_pkg, axi_intf, ariane_pkg, etc.) come in via rnf_flist below.
read_verilog -sv [list \
    $proj_root/singlecore-cva6/tile/ariane/corev_apu/riscv-dbg/src/dm_pkg.sv \
]

# ── CHI defines headers (re-included by all RTL via include_dirs) ───────────
# (chie_defines.v + hnf_defines.v are headers; nothing to read here.)

# ── HN-F (opennoc base + repo overrides) ────────────────────────────────────
# Note: hnf_cache_pipeline.v, hnf_mshr_ctl.v, hnf_mshr_bypass.v,
# hnf_link_rxreq_parse.v, hnf_link_txsnp_wrap.v come from cva6-RNF/src/ NOT
# opennoc/.  See project-cva6-rnf memory: the opennoc versions cause a
# ReadClean deadlock; hnf_link_txsnp_wrap.v places snoop tgtid at the wrong
# bit range vs the chie_defines.v that chi_icn_beh/mesh read.
set hnf_sources [list \
    $proj_root/opennoc/rtl/misc/hnf_biq.v \
    $proj_root/opennoc/rtl/misc/poll_function.v \
    $proj_root/opennoc/rtl/misc/sync_fifo.v \
    $proj_root/opennoc/rtl/misc/poll_with_start_entry.v \
    \
    $proj_root/opennoc/rtl/src/hnf/hnf_link_txdat_wrap.v \
    $proj_root/opennoc/rtl/src/hnf/hnf_tag_sram.v \
    $proj_root/opennoc/rtl/src/hnf/hnf_sram.v \
    $proj_root/opennoc/rtl/src/hnf/hnf_sram_mask.v \
    $proj_root/opennoc/rtl/src/hnf/hnf_link_rxdat_parse.v \
    $proj_root/opennoc/rtl/src/hnf/hnf_lru_sram.v \
    $proj_root/opennoc/rtl/src/hnf/hnf_mshr_qos.v \
    $proj_root/opennoc/rtl/src/hnf/hnf_mshr_global_monitor.v \
    $proj_root/opennoc/rtl/src/hnf/hnf_link_txrsp_wrap.v \
    $proj_root/opennoc/rtl/src/hnf/hnf_link.v \
    $proj_root/opennoc/rtl/src/hnf/hnf_data_sram.v \
    $proj_root/opennoc/rtl/src/hnf/hnf_sf_sram.v \
    $proj_root/src/hnf_mshr.v \
    $proj_root/opennoc/rtl/src/hnf/hnf_mshr_addr_buffer.v \
    $proj_root/src/hnf_link_txsnp_wrap.v \
    $proj_root/opennoc/rtl/src/hnf/hnf_data_buffer.v \
    $proj_root/opennoc/rtl/src/hnf/hnf_link_rxrsp_parse.v \
    $proj_root/opennoc/rtl/src/hnf/hnf_link_txreq_wrap.v \
    $proj_root/src/hnf.v \
    $proj_root/opennoc/rtl/src/hnf/hnf_mem_ctl.v \
    \
    $proj_root/src/hnf_cache_pipeline.v \
    $proj_root/src/hnf_mshr_ctl.v \
    $proj_root/src/hnf_mshr_bypass.v \
    $proj_root/src/hnf_link_rxreq_parse.v \
    $proj_root/src/hnf_atomic_alu.sv \
]
# OpenNoC `.v` files use a couple of SV-2005+ idioms (e.g. integer decls
# inside unnamed always blocks).  Vivado is strict in pure-Verilog mode, so
# read them as SystemVerilog -- SV is a superset of Verilog, no behavioural
# change.
read_verilog -sv $hnf_sources

# ── SN-F (opennoc base RTL; AXI exposed at top by the FPGA wrapper) ─────────
read_verilog -sv [glob -nocomplain $proj_root/opennoc/rtl/src/snf/*.v]

# ── CHI 2×2 mesh interconnect ───────────────────────────────────────────────
read_verilog -sv [list \
    $proj_root/opennoc/rtl/misc/xp_sel_bit_from_vec.v \
    $proj_root/opennoc/rtl/misc/chi_xp_channel.v \
    $proj_root/opennoc/rtl/misc/assert_checker.sv \
]
read_verilog -sv [list \
    $proj_root/src/mesh/chi_xp_node.sv \
    $proj_root/src/mesh/mesh_wrapper_2x2.sv \
]

# ── chi_icn_mesh adapter + RN-F multi-core wrapper ──────────────────────────
# Both tb/chi_icn_mesh.sv and tb/rnf_wrapper.sv are synth-clean.
read_verilog -sv $proj_root/tb/chi_icn_mesh.sv
read_verilog -sv $proj_root/tb/rnf_wrapper.sv

# Note: mem_ss + axi2mem are NOT pulled in for FPGA — they are a sim-only
# memory-backing helper.  The FPGA top instantiates `snf` directly and routes
# its AXI master to MIG (or to an AXI BRAM controller during bring-up).

# ── RN-F (CHI flit layer + L1.5 + CVA6) via OpenPiton-style -f flist ────────
# singlecore-cva6/rnf_flist is an OpenPiton `-f` style file list.  We parse it
# inline and dispatch read_verilog/include-dir add per entry.  Anything we
# don't want in synthesis is filtered via the SKIP_PATTERNS list below.
proc parse_openpiton_flist {flist_path proj_root_path} {
    global skip_patterns
    set fh [open $flist_path r]
    set src_files     [list]
    set inc_dirs      [list]

    while {[gets $fh line] >= 0} {
        set line [string trim $line]
        if {$line eq "" || [string match "#*" $line] || [string match "//*" $line]} { continue }

        # Strip Synopsys/VCS-only switches that Vivado doesn't grok.
        regsub -all {^\-mixedsvvh\s+} $line "" line
        regsub -all {^\-sv\s+}        $line "" line
        regsub -all {^\-v\s+}         $line "" line

        # Expand $PROJ_ROOT.
        regsub -all {\$PROJ_ROOT}     $line $proj_root_path line
        regsub -all {\$\{PROJ_ROOT\}} $line $proj_root_path line

        # `+incdir+<path>` (canonical) or `+incdir<path>` (typo we tolerate).
        if {[string match "+incdir+*" $line]} {
            set dir [string range $line 8 end]
            if {[file isdirectory $dir]} { lappend inc_dirs $dir }
            continue
        }
        if {[string match "+incdir*" $line]} {
            set dir [string range $line 7 end]
            if {[file isdirectory $dir]} { lappend inc_dirs $dir }
            continue
        }

        # Skip files matching the SKIP_PATTERNS list (OpenPiton chip-level
        # noise we don't pull into the CHI FPGA build).
        set skip 0
        foreach pat $skip_patterns {
            if {[string match $pat $line]} { set skip 1; break }
        }
        if {$skip} { continue }

        if {[file isfile $line]} {
            lappend src_files $line
        } else {
            puts "  \[flist\] WARN: missing file $line"
        }
    }
    close $fh
    return [list $src_files $inc_dirs]
}

# Skip OpenPiton chip-level + simulation-only noise (we replace these with
# our own CHI mesh + FPGA glue).  Pattern matched with `string match`.
set skip_patterns [list \
    "*/dynamic_node/*"                          \
    "*/dmbr/*"                                  \
    "*/network_common/*"                        \
    "*/ucb_bus_*"                               \
    "*/swrvr_clib*"                             \
    "*/noc_axilite_bridge*"                     \
    "*/bootrom_linux.sv"                        \
    "*_para.tmp.v"                              \
    "*instr_tracer*"                            \
    "*/common/local/util/tc_sram_wrapper.sv"    \
    "*/tech_cells_generic/src/rtl/tc_sram.sv"   \
]

set rnf_flist  $proj_root/singlecore-cva6/rnf_flist
# The flist uses `$PROJ_ROOT/cva6-RNF/...` paths, so PROJ_ROOT in that
# convention is the parent of `cva6-RNF/`.
set openpiton_proj_root [file normalize $proj_root/..]
puts "==> Parsing OpenPiton-style flist: $rnf_flist"
puts "    PROJ_ROOT = $openpiton_proj_root"
set parsed     [parse_openpiton_flist $rnf_flist $openpiton_proj_root]
set rnf_files  [lindex $parsed 0]
set rnf_incs   [lindex $parsed 1]

# Add discovered include dirs (in addition to the ones already set).
set incdirs [concat [get_property include_dirs [current_fileset]] $rnf_incs]
set_property include_dirs $incdirs [current_fileset]

# Hand the discovered files to Vivado.  We read everything as -sv (the
# OpenPiton flist marks several .v files with `-sv` because they use SV
# idioms — e.g. cache/rnf_link/*.v has `input reg` which Vivado rejects in
# pure-Verilog mode but accepts under -sv).  SV is a strict superset of
# Verilog so this is safe.
foreach f $rnf_files {
    read_verilog -sv $f
}
puts "==> rnf_flist contributed [llength $rnf_files] files, [llength $rnf_incs] +incdirs"

# ── CVA6/L1.5 SRAM: swap the simulation tc_sram_wrapper + tc_sram for the
# ── Xilinx-targeted variants so place_design can infer BRAM rather than
# ── leaving them as unresolved black boxes.  Both files define a module
# ── named `tc_sram_wrapper` / `tc_sram` respectively, so we skip the
# ── RTL versions in skip_patterns above and read the FPGA versions here.
set sram_fpga_dir $proj_root/singlecore-cva6/tile/ariane/common/local/util
set sram_fpga_tc  $proj_root/singlecore-cva6/tile/ariane/corev_apu/src/tech_cells_generic/src/fpga
read_verilog -sv $sram_fpga_dir/tc_sram_xilinx_wrapper.sv
read_verilog -sv $sram_fpga_tc/tc_sram_xilinx.sv
puts "==> using FPGA-targeted tc_sram_xilinx_wrapper + tc_sram_xilinx"

# ── RISC-V Debug Module ─────────────────────────────────────────────────────
read_verilog -sv [list \
    $proj_root/singlecore-cva6/tile/ariane/corev_apu/riscv-dbg/src/dmi_cdc.sv \
    $proj_root/singlecore-cva6/tile/ariane/corev_apu/riscv-dbg/src/dmi_jtag_tap.sv \
    $proj_root/singlecore-cva6/tile/ariane/corev_apu/riscv-dbg/src/dmi_jtag.sv \
    $proj_root/singlecore-cva6/tile/ariane/corev_apu/riscv-dbg/src/dm_csrs.sv \
    $proj_root/singlecore-cva6/tile/ariane/corev_apu/riscv-dbg/src/dm_mem.sv \
    $proj_root/singlecore-cva6/tile/ariane/corev_apu/riscv-dbg/src/dm_sba.sv \
    $proj_root/singlecore-cva6/tile/ariane/corev_apu/riscv-dbg/src/dm_top.sv \
]

# ── FPGA glue (this directory) ──────────────────────────────────────────────
read_verilog -sv [list \
    $fpga_dir/rtl/cva6_debug_subsystem.sv \
    $fpga_dir/rtl/cva6_chi_fpga_top.sv \
]

# ── Constraints ─────────────────────────────────────────────────────────────
read_xdc $fpga_dir/constraints/vcu118.xdc

# ── IP (clock wizard + MIG DDR4) ────────────────────────────────────────────
# Generated one-time via `vivado -mode batch -source ip/clk_wiz.tcl` (and
# similarly for ip/mig_ddr4.tcl).  We pick up the .xci files if they exist
# and abort with a clear message otherwise.
set clk_wiz_xci $fpga_dir/ip/clk_wiz_0/clk_wiz_0.xci
set mig_xci     $fpga_dir/ip/mig_ddr4_0/mig_ddr4_0.xci

if {[file exists $clk_wiz_xci]} {
    read_ip $clk_wiz_xci
    puts "==> read_ip $clk_wiz_xci"
} else {
    error "Missing IP: $clk_wiz_xci\n       Run:  vivado -mode batch -source ip/clk_wiz.tcl"
}

# MIG isn't wired into the design yet; only load if generated, otherwise
# skip silently — synth still works because nothing instantiates mig_ddr4_0.
if {[file exists $mig_xci]} {
    read_ip $mig_xci
    puts "==> read_ip $mig_xci"
}
