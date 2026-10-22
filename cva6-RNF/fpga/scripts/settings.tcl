# settings.tcl — synthesis / implementation strategy + Verilog defines.
#
# Strategy values mirror the openpiton VCU118 flow (gen_project.tcl):
#   synth     : retiming on, fsm auto, control_set_opt auto
#   opt       : Default (ExploreWithRemap when PERF_OPT)
#   place     : Default (Explore     when PERF_OPT)
#   phys_opt  : AggressiveExplore (always)
#   route     : Default (AggressiveExplore when PERF_OPT)
#   post-rt   : ExploreWithAggressiveHoldFix (only when POSTROUTEPHYSOPT)
#
# Toggle the heavier flow:
#   PERF_OPT=1 vivado -mode batch -source scripts/build.tcl
#   POSTROUTEPHYSOPT=1 ... (orthogonal — runs an extra phys_opt after route)

# ── Performance knobs ───────────────────────────────────────────────────────
if {![info exists ::env(PERF_OPT)]} {
    set ::env(PERF_OPT) 0
}
if {![info exists ::env(POSTROUTEPHYSOPT)]} {
    set ::env(POSTROUTEPHYSOPT) 0
}
set perf_opt        $::env(PERF_OPT)
set postroute_opt   $::env(POSTROUTEPHYSOPT)

# Directives for each stage (Default vs Perf-optimized)
set synth_directive   [expr {$perf_opt ? "default"            : "Default"}]
set opt_directive     [expr {$perf_opt ? "ExploreWithRemap"   : "Default"}]
set place_directive   [expr {$perf_opt ? "Explore"            : "Default"}]
set route_directive   [expr {$perf_opt ? "AggressiveExplore"  : "Default"}]
set physopt_directive [expr {$perf_opt ? "AggressiveExplore"  : "AggressiveExplore"}]
set postroute_directive  "ExploreWithAggressiveHoldFix"

# Maximum parallelism for placement/routing
set_param general.maxThreads 8

# ── Verilog defines passed to synth_design ──────────────────────────────────
# Match openpiton's VCU118_BOARD macro so any guarded code paths come along.
set vlog_defines [list \
    SYNTHESIS \
    VCU118 \
    VCU118_BOARD \
]

# HNF_USE_BRAM=1 → add `HNF_DELAY_ONE_CYCLE`, which registers the SRAM read
# output inside hnf_sram*.v.  Registered reads are BRAM-eligible (async-read
# forces Vivado to use LUTRAM / distributed memory).  WARNING: this adds 1
# cycle of read latency to the HN-F cache path; the upstream HNF pipeline
# does not have a corresponding `\`ifdef`, so behavioural verification is
# REQUIRED before trusting a bitstream built with this flag.
if {[info exists ::env(HNF_USE_BRAM)] && $::env(HNF_USE_BRAM) eq "1"} {
    lappend vlog_defines HNF_DELAY_ONE_CYCLE
    puts "==> HNF_USE_BRAM=1 -> +define+HNF_DELAY_ONE_CYCLE"
}

set_property verilog_define $vlog_defines [current_fileset]
