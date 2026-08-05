# DC synthesis flow for the narrow-interface PDE accelerator chip top.
# The 10 ns clock and simple block-level I/O budgets are provisional.

proc env_or_default {name fallback} {
  if {[info exists ::env($name)] && [string trim $::env($name)] ne ""} {
    return $::env($name)
  }
  return $fallback
}

set SCRIPT_DIR [file dirname [file normalize [info script]]]
set REPO_ROOT [file normalize [env_or_default PDE_REPO_ROOT \
  [file join $SCRIPT_DIR ../..]]]
set OUTPUT_ROOT [string trim [env_or_default PDE_DC_OUTPUT_ROOT ""]]
if {$OUTPUT_ROOT eq ""} {
  set WORK_DIR   [file join $REPO_ROOT flow work dc]
  set REPORT_DIR [file join $REPO_ROOT flow reports dc]
  set RESULT_DIR [file join $REPO_ROOT flow results dc]
} else {
  set WORK_DIR   [file join $OUTPUT_ROOT work]
  set REPORT_DIR [file join $OUTPUT_ROOT reports]
  set RESULT_DIR [file join $OUTPUT_ROOT results]
}

file mkdir $WORK_DIR
file mkdir $REPORT_DIR
file mkdir $RESULT_DIR

set TOP [env_or_default PDE_TOP pde_chip_top_safe]
set CLOCK_PORT clk
set CLOCK_NAME core_clk
set CLOCK_PERIOD 10.000

set PDK_ROOT [env_or_default PDE_PDK_ROOT \
  /ssd0/PDKs/TSMC65nm/STDCELL/std/STD_Cell/tcbn65lp_200b]
set LIB_DIR  [file join $PDK_ROOT Front_End timing_power_noise CCS]
set TARGET_DB [env_or_default PDE_TARGET_DB \
  [file join $LIB_DIR tcbn65lpwc_ccs.db]]

if {![file exists $TARGET_DB]} {
  error "Missing target library: $TARGET_DB"
}

set RTL_FILES [list \
  [file join $REPO_ROOT src common counter_ce.sv] \
  [file join $REPO_ROOT src common pipeline_delay_bit.sv] \
  [file join $REPO_ROOT src pe pde_q8p7_pkg.sv] \
  [file join $REPO_ROOT src pe r_alu.sv] \
  [file join $REPO_ROOT src pe r_reg.sv] \
  [file join $REPO_ROOT src pe r_dsm.sv] \
  [file join $REPO_ROOT src pe r_status.sv] \
  [file join $REPO_ROOT src pe sol_acc.sv] \
  [file join $REPO_ROOT src pe r_state_ctrl.sv] \
  [file join $REPO_ROOT src pe pe_top.sv] \
  [file join $REPO_ROOT src pe_array pde_memcontrol.sv] \
  [file join $REPO_ROOT src pe_array pde_tcu.sv] \
  [file join $REPO_ROOT src pe_array pde_core.sv] \
  [file join $REPO_ROOT src pe_array pde_chip_top.sv] \
  [file join $REPO_ROOT src pe_array pde_chip_top_safe.sv]]

foreach RTL_FILE $RTL_FILES {
  if {![file exists $RTL_FILE]} {
    error "Missing RTL source: $RTL_FILE"
  }
}

set_app_var search_path [concat [list $REPO_ROOT $LIB_DIR] $search_path]
set_app_var target_library [list $TARGET_DB]
set_app_var link_library [concat "*" $target_library]

set_svf [file join $RESULT_DIR ${TOP}.svf]
define_design_lib WORK -path [file join $WORK_DIR WORK]

catch {set_host_options -max_cores 4}

analyze -format sverilog -library WORK $RTL_FILES
elaborate $TOP -library WORK
current_design $TOP
link
uniquify

redirect -file [file join $REPORT_DIR check_design_precompile.rpt] {
  check_design
}

create_clock -name $CLOCK_NAME -period $CLOCK_PERIOD [get_ports $CLOCK_PORT]
# Keep setup/hold uncertainty explicitly split.  The old unqualified 0.2 was
# imported by ICC2 (W-2024.09) as hold-only in the split-scenario setup, which
# hid a real ~-0.21 ns setup problem behind a phantom 0.2 ns hold target; see
# CODEX_UBUNTU_WORKLOG_2026-08-03.md section 7.
set_clock_uncertainty -setup 0.200 [get_clocks $CLOCK_NAME]
set_clock_uncertainty -hold 0.050 [get_clocks $CLOCK_NAME]
set_clock_transition 0.100 [get_clocks $CLOCK_NAME]

set DATA_INPUTS [remove_from_collection [all_inputs] [get_ports {clk rst_n}]]
if {[sizeof_collection $DATA_INPUTS] > 0} {
  set_input_delay 1.000 -clock $CLOCK_NAME $DATA_INPUTS
  set_input_transition 0.100 $DATA_INPUTS
}
if {[sizeof_collection [all_outputs]] > 0} {
  set_output_delay 1.000 -clock $CLOCK_NAME [all_outputs]
  set_load 0.050 [all_outputs]
}

# rst_n is an asynchronous functional reset. Ignore its assertion path during
# synthesis optimization; recovery/removal remains a required post-CTS check.
set_false_path -from [get_ports rst_n]
set_ideal_network [get_ports {clk rst_n}]

set_max_fanout 32 [current_design]
set_max_transition 0.500 [current_design]
set_fix_multiple_port_nets -all -buffer_constants

compile_ultra -no_autoungroup

change_names -rules verilog -hierarchy

redirect -file [file join $REPORT_DIR check_design.rpt] {
  check_design
}
redirect -file [file join $REPORT_DIR check_timing.rpt] {
  check_timing
}
redirect -file [file join $REPORT_DIR qor.rpt] {
  report_qor
}
redirect -file [file join $REPORT_DIR area_hier.rpt] {
  report_area -hierarchy
}
redirect -file [file join $REPORT_DIR timing_max.rpt] {
  report_timing -delay_type max -max_paths 50 -nworst 2 -input_pins -nets
}
redirect -file [file join $REPORT_DIR timing_min.rpt] {
  report_timing -delay_type min -max_paths 20 -nworst 1 -input_pins -nets
}
redirect -file [file join $REPORT_DIR constraints.rpt] {
  report_constraint -all_violators
}
redirect -file [file join $REPORT_DIR power.rpt] {
  report_power -hierarchy
}
redirect -file [file join $REPORT_DIR clocks.rpt] {
  report_clock
}
redirect -file [file join $REPORT_DIR high_fanout.rpt] {
  report_net_fanout -threshold 32
}
redirect -file [file join $REPORT_DIR resources.rpt] {
  report_resources -hierarchy
}

write -format ddc -hierarchy -output [file join $RESULT_DIR ${TOP}.ddc]
write_file -format verilog -hierarchy -output [file join $RESULT_DIR ${TOP}.v]
write_sdc [file join $RESULT_DIR ${TOP}.sdc]
write_sdf -version 2.1 [file join $RESULT_DIR ${TOP}.sdf]

puts "PDE_DC_DONE top=$TOP clock_period=$CLOCK_PERIOD result_dir=$RESULT_DIR"
quit
