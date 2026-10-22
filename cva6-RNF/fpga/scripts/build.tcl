# build.tcl — non-project mode entry point for the cva6-RNF VCU118 prototype.
#
# Stages (selectable via -tclargs):
#   <none> | all  → synth + impl + bitstream
#   synth         → synth_design only
#   impl          → synth + opt/place/route (no bitstream)
#   bit           → synth + impl + write_bitstream
#
# Outputs under ./build/{synth,impl}/. The final bitstream is
# build/cva6_chi_fpga.bit.

# ── Paths ────────────────────────────────────────────────────────────────────
set fpga_dir   [file normalize [file dirname [info script]]/..]
set build_dir  [file normalize $fpga_dir/build]
set synth_dir  $build_dir/synth
set impl_dir   $build_dir/impl

file mkdir $build_dir $synth_dir $impl_dir

# ── Stage selection ─────────────────────────────────────────────────────────
set stage "all"
if {$argc > 0} {
    set stage [lindex $argv 0]
}

# ── Board / part ────────────────────────────────────────────────────────────
set part   "xcvu9p-flga2104-2L-e"
set board  "xilinx.com:vcu118:part0:2.4"

# ── In-memory project ───────────────────────────────────────────────────────
create_project -in_memory -part $part
set_property board_part $board [current_project]

set top "cva6_chi_fpga_top"
set_property top $top [current_fileset]

# ── Source files (RTL + IP + constraints) ───────────────────────────────────
source $fpga_dir/scripts/sources.tcl

# ── Synth/impl strategy ─────────────────────────────────────────────────────
source $fpga_dir/scripts/settings.tcl

# ── Synthesis ───────────────────────────────────────────────────────────────
# NUM_RNFS overrides the top-level parameter via `synth_design -generic`.
# Defaults to 1; cap is the mesh's CORE_COUNT (= 2).
set num_rnfs [expr {[info exists ::env(NUM_RNFS)] ? $::env(NUM_RNFS) : 1}]

proc do_synth {synth_dir} {
    global synth_directive num_rnfs
    puts "==> synth_design (directive=$synth_directive, NUM_RNFS=$num_rnfs)"
    synth_design -top [get_property top [current_fileset]] \
                 -flatten_hierarchy rebuilt \
                 -directive $synth_directive \
                 -retiming \
                 -generic NUM_RNFS=$num_rnfs
    write_checkpoint -force $synth_dir/post_synth.dcp
    report_utilization -file  $synth_dir/post_synth_util.rpt
    report_timing_summary -file $synth_dir/post_synth_timing.rpt
}

# ── Implementation (opt + place + phys_opt + route + opt-postroute) ─────────
proc do_impl {impl_dir} {
    global opt_directive place_directive route_directive
    global physopt_directive postroute_opt postroute_directive

    puts "==> opt_design (directive=$opt_directive)"
    opt_design -directive $opt_directive

    puts "==> place_design (directive=$place_directive)"
    place_design -directive $place_directive

    puts "==> phys_opt_design (directive=$physopt_directive)"
    phys_opt_design -directive $physopt_directive

    puts "==> route_design (directive=$route_directive)"
    route_design -directive $route_directive

    if {$postroute_opt} {
        puts "==> post-route phys_opt_design (directive=$postroute_directive)"
        phys_opt_design -directive $postroute_directive
    }

    write_checkpoint -force $impl_dir/post_route.dcp
    report_utilization      -file $impl_dir/post_route_util.rpt
    report_timing_summary   -file $impl_dir/post_route_timing.rpt
    report_drc              -file $impl_dir/post_route_drc.rpt
    report_clock_utilization -file $impl_dir/post_route_clock_util.rpt
}

# ── Bitstream + .ltx (probes file) ──────────────────────────────────────────
proc do_bitstream {build_dir} {
    puts "==> write_bitstream"
    write_bitstream -force $build_dir/cva6_chi_fpga.bit
    # write_debug_probes -force $build_dir/cva6_chi_fpga.ltx
}

# ── Dispatch ────────────────────────────────────────────────────────────────
switch -- $stage {
    "synth" {
        do_synth $synth_dir
    }
    "impl" {
        do_synth $synth_dir
        do_impl  $impl_dir
    }
    "bit" -
    "all" -
    default {
        do_synth     $synth_dir
        do_impl      $impl_dir
        do_bitstream $build_dir
    }
}

puts "==> done. Build artifacts in: $build_dir"
