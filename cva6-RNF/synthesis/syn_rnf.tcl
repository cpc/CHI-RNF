
## Add your lib path here, this one uses ASAP7
set lib_dir /opt/soc/work/hepola/norcas2024/rt-ss/pcs_synth/asap7sc7p5t_28/LIB/NLDM
#set lib_dir /opt/soc/tech/tcbn22ull/libraries/TSMCHOME/digital/Back_End/ndm

set lib_files [glob -nocomplain $lib_dir/*.lib]

# Read all the library files
read_libs $lib_files

get_db init_hdl_search_path

# set_db init_hdl_search_path {/opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/include 
# /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/vendor/pulp-platform/common_cells/include 
# /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/vendor/pulp-platform/common_cells/src 
# /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/vendor/pulp-platform/common_cells/src 
# /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/vendor/pulp-platform/axi/include 
# /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/common/local/util 
# /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/core/cache_subsystem/hpdcache/rtl/include}

set_db init_hdl_search_path {/opt/soc/work/fcteri/rnf/chi-rnf/cva6-RNF/cache/rnf_link/include /opt/soc/work/fcteri/rnf/chi-rnf/cva6-RNF/cache/include}


get_db init_hdl_search_path

# Add file paths here! TODO: use a file list instead of listing each src file
#read_hdl -language sv -library subsystem /opt/soc/work/hepola/norcas2024/rt-ss/cva6_no_acc_src/corev_apu/src/ariane.sv
# read_hdl -language sv -library subsystem 

read_hdl -language mixvlog -library subsystem /opt/soc/work/fcteri/rnf/chi-rnf/cva6-RNF/cache/include/dm_pkg.sv
read_hdl -language mixvlog -library subsystem /opt/soc/work/fcteri/rnf/chi-rnf/cva6-RNF/cache/include/cv64a6_imafdc_sv39_openpiton_config_pkg.sv
read_hdl -language mixvlog -library subsystem /opt/soc/work/fcteri/rnf/chi-rnf/cva6-RNF/cache/include/riscv_pkg.sv
read_hdl -language mixvlog -library subsystem /opt/soc/work/fcteri/rnf/chi-rnf/cva6-RNF/cache/include/ariane_pkg.sv
read_hdl -language mixvlog -library subsystem /opt/soc/work/fcteri/rnf/chi-rnf/cva6-RNF/cache/include/wt_cache_pkg.sv
read_hdl -language mixvlog -library subsystem /opt/soc/work/fcteri/rnf/chi-rnf/cva6-RNF/cache/include/rnf_param.v
read_hdl -language mixvlog -library subsystem /opt/soc/work/fcteri/rnf/chi-rnf/cva6-RNF/cache/include/rnf_defines.v
read_hdl -language mixvlog -library subsystem /opt/soc/work/fcteri/rnf/chi-rnf/cva6-RNF/cache/include/chie_defines.v
read_hdl -language mixvlog -library subsystem /opt/soc/work/fcteri/rnf/chi-rnf/cva6-RNF/cache/rnf_link/rnf_link_txdat_wrap.v
read_hdl -language mixvlog -library subsystem /opt/soc/work/fcteri/rnf/chi-rnf/cva6-RNF/cache/rnf_link/rnf_link_rxdat_parse.v
read_hdl -language mixvlog -library subsystem /opt/soc/work/fcteri/rnf/chi-rnf/cva6-RNF/cache/rnf_link/rnf_link_txrsp_wrap.v
read_hdl -language mixvlog -library subsystem /opt/soc/work/fcteri/rnf/chi-rnf/cva6-RNF/cache/rnf_link/rnf_link_rxrsp_parse.v
read_hdl -language mixvlog -library subsystem /opt/soc/work/fcteri/rnf/chi-rnf/cva6-RNF/cache/rnf_link/rnf_link_txreq_wrap.v
read_hdl -language mixvlog -library subsystem /opt/soc/work/fcteri/rnf/chi-rnf/cva6-RNF/cache/rnf_link/rnf_link_rxsnp_parse.v
read_hdl -language mixvlog -library subsystem /opt/soc/work/fcteri/rnf/chi-rnf/cva6-RNF/cache/rnf_link/rnf_link_handshake_ctl.v
read_hdl -language mixvlog -library subsystem /opt/soc/work/fcteri/rnf/chi-rnf/cva6-RNF/cache/rnf_link/rnf_link.v
read_hdl -language mixvlog -library subsystem /opt/soc/work/fcteri/rnf/chi-rnf/cva6-RNF/cache/l15/rtl/txreq_encoder.v
read_hdl -language mixvlog -library subsystem /opt/soc/work/fcteri/rnf/chi-rnf/cva6-RNF/cache/l15/rtl/response_encoder.sv 
read_hdl -language mixvlog -library subsystem /opt/soc/work/fcteri/rnf/chi-rnf/cva6-RNF/cache/l15/rtl/request_register.sv 
read_hdl -language mixvlog -library subsystem /opt/soc/work/fcteri/rnf/chi-rnf/cva6-RNF/cache/l15/rtl/rx_control.sv 
read_hdl -language mixvlog -library subsystem /opt/soc/work/fcteri/rnf/chi-rnf/cva6-RNF/synthesis/rnf_if_wrapper.sv



#####################################################################################
# eof filelists
# top elaborate config & command
#####################################################################################
set_db hdl_parameterize_module_name false
set_db hdl_max_loop_limit 32768
  

## Make an error when a latch is inferred
set_db hdl_error_on_latch true

# The top-level module
elaborate rnf_if_wrapper

#### Some commands for playing around with synth optimizations ###
#preserve [get_pins] true

#set_attribute preserve true [find -hierarchical -port *]
#set_attribute preserve true [find -hierarchical -pin *]

#set_db [get_pins -hierarchical op_i*] .preserve true

#set_db design:ariane .retime true
#set_db design:i_cvxif_coprocessor .retime true
#####################################################################



### Set clock period for 650 ps (1,5GHz)
#set clock [define_clock -period 650 -name {clk_i} [clock_ports]]


### Set clock period for 1000 ps (1GHz)
set clock [define_clock -period 1000 -name {clk} [clock_ports]]


# Constrain the input I/O path
set_input_delay -clock clk -max 1 [all_inputs]
set_input_delay -clock clk -min 0 [all_inputs]

# Constrain the output I/O path
set_output_delay -clock clk -max 1 [all_inputs]


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
