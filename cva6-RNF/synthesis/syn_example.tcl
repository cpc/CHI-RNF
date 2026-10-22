
## Add your lib path here, this one uses ASAP7
#set lib_dir /opt/soc/work/hepola/norcas2024/rt-ss/pcs_synth/asap7sc7p5t_28/LIB/NLDM
set lib_dir /opt/soc/tech/tcbn22ull/libraries/TSMCHOME/digital/Back_End/ndm

set lib_files [glob -nocomplain $lib_dir/*.lib]

# Read all the library files
read_libs $lib_files

get_db init_hdl_search_path

set_db init_hdl_search_path {/opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/include /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/vendor/pulp-platform/common_cells/include /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/vendor/pulp-platform/common_cells/src /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/vendor/pulp-platform/common_cells/src /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/vendor/pulp-platform/axi/include /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/common/local/util /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cache_subsystem/hpdcache/rtl/include}

get_db init_hdl_search_path

# Add file paths here! TODO: use a file list instead of listing each src file
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/vendor/pulp-platform/fpga-support/rtl/SyncDpRam.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/vendor/pulp-platform/fpga-support/rtl/AsyncDpRam.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/vendor/pulp-platform/fpga-support/rtl/AsyncThreePortRam.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/vendor/pulp-platform/fpga-support/rtl/SyncThreePortRam.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/vendor/pulp-platform/fpga-support/rtl/SyncDpRam_ind_r_w.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cvfpu/src/fpnew_pkg.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cvfpu/src/fpnew_cast_multi.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cvfpu/src/fpnew_classifier.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cvfpu/src/fpnew_divsqrt_multi.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cvfpu/src/fpnew_fma_multi.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cvfpu/src/fpnew_fma.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cvfpu/src/fpnew_noncomp.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cvfpu/src/fpnew_opgroup_block.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cvfpu/src/fpnew_opgroup_fmt_slice.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cvfpu/src/fpnew_opgroup_multifmt_slice.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cvfpu/src/fpnew_rounding.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cvfpu/src/fpnew_top.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cvfpu/src/fpu_div_sqrt_mvp/hdl/defs_div_sqrt_mvp.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cvfpu/src/fpu_div_sqrt_mvp/hdl/control_mvp.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cvfpu/src/fpu_div_sqrt_mvp/hdl/div_sqrt_top_mvp.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cvfpu/src/fpu_div_sqrt_mvp/hdl/iteration_div_sqrt_mvp.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cvfpu/src/fpu_div_sqrt_mvp/hdl/norm_div_sqrt_mvp.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cvfpu/src/fpu_div_sqrt_mvp/hdl/nrbd_nrsc_mvp.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cvfpu/src/fpu_div_sqrt_mvp/hdl/preprocess_mvp.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/include/config_pkg.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/include/cv32a65x_config_pkg.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/include/riscv_pkg.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/include/ariane_pkg.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/vendor/pulp-platform/axi/src/axi_pkg.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/include/wt_cache_pkg.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/include/std_cache_pkg.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/include/instr_tracer_pkg.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/include/build_config_pkg.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cvxif_compressed_if_driver.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cvxif_issue_register_commit_if_driver.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cvxif_fu.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/cvx-src/systemverilog/cvxif_sup_pkg.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/cvx-src/systemverilog/custom_fu_coprocessor.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/cvx-src/systemverilog/cvxifcompressed_decoder.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/cvx-src/systemverilog/fu_custom_fu.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/cvx-src/systemverilog/instr_tracker_custom_fu.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/vendor/pulp-platform/common_cells/src/cf_math_pkg.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/vendor/pulp-platform/common_cells/src/fifo_v3.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/vendor/pulp-platform/common_cells/src/lfsr.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/vendor/pulp-platform/common_cells/src/lfsr_8bit.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/vendor/pulp-platform/common_cells/src/stream_arbiter.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/vendor/pulp-platform/common_cells/src/stream_arbiter_flushable.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/vendor/pulp-platform/common_cells/src/stream_mux.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/vendor/pulp-platform/common_cells/src/stream_demux.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/vendor/pulp-platform/common_cells/src/lzc.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/vendor/pulp-platform/common_cells/src/rr_arb_tree.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/vendor/pulp-platform/common_cells/src/shift_reg.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/vendor/pulp-platform/common_cells/src/unread.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/vendor/pulp-platform/common_cells/src/popcount.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/vendor/pulp-platform/common_cells/src/exp_backoff.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/vendor/pulp-platform/common_cells/src/counter.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/vendor/pulp-platform/common_cells/src/delta_counter.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cva6.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cva6_rvfi_probes.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/alu.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/fpu_wrap.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/branch_unit.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/compressed_decoder.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/macro_decoder.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/controller.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/zcmt_decoder.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/csr_buffer.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/csr_regfile.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/decoder.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/ex_stage.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/instr_realign.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/id_stage.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/issue_read_operands.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/issue_stage.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/load_unit.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/load_store_unit.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/lsu_bypass.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/mult.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/multiplier.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/serdiv.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/perf_counters.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/ariane_regfile_ff.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/ariane_regfile_fpga.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/scoreboard.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/store_buffer.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/amo_buffer.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/store_unit.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/commit_stage.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/axi_shim.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cva6_accel_first_pass_decoder_stub.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/acc_dispatcher.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cva6_fifo_v3.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/frontend/btb.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/frontend/bht.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/frontend/ras.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/frontend/instr_scan.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/frontend/instr_queue.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/frontend/frontend.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cache_subsystem/wt_dcache_ctrl.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cache_subsystem/wt_dcache_mem.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cache_subsystem/wt_dcache_missunit.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cache_subsystem/wt_dcache_wbuffer.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cache_subsystem/wt_dcache.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cache_subsystem/cva6_icache.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cache_subsystem/wt_cache_subsystem.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cache_subsystem/wt_axi_adapter.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cache_subsystem/tag_cmp.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cache_subsystem/axi_adapter.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cache_subsystem/miss_handler.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cache_subsystem/cache_ctrl.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cache_subsystem/cva6_icache_axi_wrapper.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cache_subsystem/std_cache_subsystem.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cache_subsystem/std_nbdcache.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cache_subsystem/hpdcache/rtl/src/hpdcache_pkg.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cache_subsystem/hpdcache/rtl/src/common/hpdcache_demux.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cache_subsystem/hpdcache/rtl/src/common/hpdcache_lfsr.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cache_subsystem/hpdcache/rtl/src/common/hpdcache_sync_buffer.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cache_subsystem/hpdcache/rtl/src/common/hpdcache_fifo_reg.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cache_subsystem/hpdcache/rtl/src/common/hpdcache_fifo_reg_initialized.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cache_subsystem/hpdcache/rtl/src/common/hpdcache_fxarb.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cache_subsystem/hpdcache/rtl/src/common/hpdcache_rrarb.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cache_subsystem/hpdcache/rtl/src/common/hpdcache_mux.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cache_subsystem/hpdcache/rtl/src/common/hpdcache_1hot_to_binary.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cache_subsystem/hpdcache/rtl/src/common/hpdcache_prio_1hot_encoder.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cache_subsystem/hpdcache/rtl/src/common/hpdcache_sram.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cache_subsystem/hpdcache/rtl/src/common/hpdcache_sram_wbyteenable.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cache_subsystem/hpdcache/rtl/src/common/hpdcache_sram_wmask.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cache_subsystem/hpdcache/rtl/src/common/hpdcache_regbank_wbyteenable_1rw.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cache_subsystem/hpdcache/rtl/src/common/hpdcache_regbank_wmask_1rw.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cache_subsystem/hpdcache/rtl/src/common/hpdcache_data_downsize.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cache_subsystem/hpdcache/rtl/src/common/hpdcache_data_upsize.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cache_subsystem/hpdcache/rtl/src/hwpf_stride/hwpf_stride_pkg.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cache_subsystem/hpdcache/rtl/src/hwpf_stride/hwpf_stride.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cache_subsystem/hpdcache/rtl/src/hwpf_stride/hwpf_stride_arb.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cache_subsystem/hpdcache/rtl/src/hwpf_stride/hwpf_stride_wrapper.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cache_subsystem/hpdcache/rtl/src/hpdcache.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cache_subsystem/hpdcache/rtl/src/hpdcache_amo.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cache_subsystem/hpdcache/rtl/src/hpdcache_cmo.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cache_subsystem/hpdcache/rtl/src/hpdcache_core_arbiter.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cache_subsystem/hpdcache/rtl/src/hpdcache_ctrl.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cache_subsystem/hpdcache/rtl/src/hpdcache_ctrl_pe.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cache_subsystem/hpdcache/rtl/src/hpdcache_memctrl.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cache_subsystem/hpdcache/rtl/src/hpdcache_miss_handler.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cache_subsystem/hpdcache/rtl/src/hpdcache_mshr.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cache_subsystem/hpdcache/rtl/src/hpdcache_plru.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cache_subsystem/hpdcache/rtl/src/hpdcache_rtab.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cache_subsystem/hpdcache/rtl/src/hpdcache_uncached.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cache_subsystem/hpdcache/rtl/src/hpdcache_victim_sel.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cache_subsystem/hpdcache/rtl/src/hpdcache_wbuf.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cache_subsystem/hpdcache/rtl/src/utils/hpdcache_mem_resp_demux.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cache_subsystem/hpdcache/rtl/src/utils/hpdcache_mem_to_axi_read.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cache_subsystem/hpdcache/rtl/src/utils/hpdcache_mem_to_axi_write.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cache_subsystem/cva6_hpdcache_subsystem.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cache_subsystem/cva6_hpdcache_subsystem_axi_arbiter.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cache_subsystem/cva6_hpdcache_if_adapter.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cache_subsystem/cva6_hpdcache_wrapper.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cache_subsystem/hpdcache/rtl/src/common/macros/blackbox/hpdcache_sram_1rw.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cache_subsystem/hpdcache/rtl/src/common/macros/blackbox/hpdcache_sram_wbyteenable_1rw.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cache_subsystem/hpdcache/rtl/src/common/macros/blackbox/hpdcache_sram_wmask_1rw.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/pmp/src/pmp.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/pmp/src/pmp_entry.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/pmp/src/pmp_data_if.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/common/local/util/instr_tracer.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/common/local/util/tc_sram_wrapper.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/common/local/util/tc_sram_wrapper_cache_techno.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/vendor/pulp-platform/tech_cells_generic/src/rtl/tc_sram.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/common/local/util/sram.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/common/local/util/sram_cache.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cva6_mmu/cva6_mmu.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cva6_mmu/cva6_ptw.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cva6_mmu/cva6_tlb.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cva6_mmu/cva6_shared_tlb.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/cvx-src/systemverilog/custom_fu_coprocessor.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/cvx-src/systemverilog/cvxifcompressed_decoder.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/cvx-src/systemverilog/cvxif_sup_pkg.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/cvx-src/systemverilog/fu_custom_fu.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/cvx-src/systemverilog/instr_tracker_custom_fu.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/corev_apu/tb/ariane_soc_pkg.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/corev_apu/tb/ariane_axi_pkg.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/corev_apu/tb/ariane_axi_soc_pkg.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cache_subsystem/hpdcache/rtl/src/utils/hpdcache_mem_req_write_arbiter.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cache_subsystem/hpdcache/rtl/src/utils/hpdcache_mem_req_read_arbiter.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cache_subsystem/hpdcache/rtl/src/hpdcache_flush.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cache_subsystem/hpdcache/rtl/src/hpdcache_victim_plru.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cache_subsystem/hpdcache/rtl/src/hpdcache_victim_random.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cache_subsystem/hpdcache/rtl/src/common/hpdcache_data_resize.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cache_subsystem/hpdcache/rtl/src/common/hpdcache_data_upsize.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cache_subsystem/hpdcache/rtl/src/common/hpdcache_decoder.sv
read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/corev_apu/src/ariane.sv



#####################################################################################
# eof filelists
# top elaborate config & command
#####################################################################################
set_db hdl_parameterize_module_name false
set_db hdl_max_loop_limit 32768
  

# The top-level module
elaborate ariane

#### Some commands for playing around with synth optimizations ###
#preserve [get_pins] true

#set_attribute preserve true [find -hierarchical -port *]
#set_attribute preserve true [find -hierarchical -pin *]

#set_db [get_pins -hierarchical op_i*] .preserve true

#set_db design:ariane .retime true
#set_db design:i_cvxif_coprocessor .retime true
#####################################################################


### Set clock period for 650 ps
set clock [define_clock -period 650 -name {clk_i} [clock_ports]]


# Constrain the input I/O path
set_input_delay -clock clk_i -max 1 [all_inputs]
set_input_delay -clock clk_i -min 0 [all_inputs]

# Constrain the output I/O path
set_output_delay -clock clk_i -max 1 [all_inputs]


# enable global worst-TNS optimization
set_db tns_opto true

# disable ungrouping to preserve design hierarchy 
set_db auto_ungroup none


check_design -unresolved 

set_db syn_generic_effort low
syn_generic 

set_db syn_map_effort low
syn_map 

syn_opt 


report_timing -lint 


report_timing > reports/genus/synth_report_timing.txt 
report_gates  > reports/genus/synth_report_gates.txt 
report_area -detail -show_leaf_cells > reports/genus/synth_report_area.txt 
report_power  > reports/genus/synth_report_power.txt 

#####################################################################################
#
#####################################################################################
# Report elaboration
report_messages -warning > logs/genus_messages_warnings.txt
report_messages -error > logs/genus_messages_errors.txt
check_design -multiple_driver -unresolved -undriven > logs/genus_check_design_fatal.txt
check_design -unloaded -unloaded_comb > logs/genus_check_design_unloaded.txt
check_design -combo_loops > logs/genus_check_design_combo_loops.txt

write_netlist > output.v

exit 0
