# ECO10 stage 3: final report battery and stream-out for the eco10 database.
#
# Mirrors the report/write tail of flow/icc2/pnr.tcl (same report names, same
# writer options) so the eco10 tree can be compared file-for-file with
# flow/local_runs/icc2_20260803_full and consumed by the existing HOWTO
# instructions.  Adds the 4-digit violation reports used by the history audit.
# Read-only with respect to netlist/routing: no optimization commands here.

proc require_env {name} {
  if {![info exists ::env($name)] || [string trim $::env($name)] eq ""} {
    error "Missing required environment variable: $name"
  }
  return [file normalize $::env($name)]
}

proc require_report_line {report_file pattern description} {
  set fh [open $report_file r]
  set text [read $fh]
  close $fh
  if {![regexp $pattern $text]} {
    error "Verification failed: $description not found in $report_file"
  }
}

set design_lib [require_env PDE_ECO10_DESIGN_LIB]
set report_dir [require_env PDE_ECO10_REPORT_DIR]
set result_dir [require_env PDE_ECO10_RESULT_DIR]
set gds_map [require_env PDE_GDS_MAP]
set gds_map_format $::env(PDE_GDS_MAP_FORMAT)
set TOP pde_chip_top_safe

file mkdir $report_dir
file mkdir $result_dir

set_host_options -max_cores 8
open_lib $design_lib
open_block ${TOP}.design
link_block
puts "PDE_ECO10_S3_BEGIN design_lib=$design_lib"

redirect -file [file join $report_dir final_design.rpt] {
  report_design -all
}
redirect -file [file join $report_dir final_qor.rpt] {
  report_qor -nosplit
}
redirect -file [file join $report_dir final_setup_timing.rpt] {
  report_timing -delay_type max -scenarios [get_scenarios FUNC_WC] \
    -max_paths 50 -sort_by slack -physical -nosplit
}
redirect -file [file join $report_dir final_hold_timing.rpt] {
  report_timing -delay_type min -scenarios [get_scenarios FUNC_BC] \
    -max_paths 250 -sort_by slack -physical -nosplit
}
redirect -file [file join $report_dir final_setup_violations_4d.rpt] {
  report_timing -delay_type max -scenarios [get_scenarios FUNC_WC] \
    -max_paths 10000 -slack_lesser_than 0 \
    -significant_digits 4 -physical -nosplit
}
redirect -file [file join $report_dir final_setup_worst_4d.rpt] {
  report_timing -delay_type max -scenarios [get_scenarios FUNC_WC] \
    -max_paths 1 -significant_digits 4 -physical -nosplit
}
redirect -file [file join $report_dir final_hold_violations_4d.rpt] {
  report_timing -delay_type min -scenarios [get_scenarios FUNC_BC] \
    -max_paths 10000 -slack_lesser_than 0 \
    -significant_digits 4 -physical -nosplit
}
redirect -file [file join $report_dir final_hold_worst_4d.rpt] {
  report_timing -delay_type min -scenarios [get_scenarios FUNC_BC] \
    -max_paths 1 -significant_digits 4 -physical -nosplit
}
redirect -file [file join $report_dir final_constraints.rpt] {
  report_constraints -all_violators -nosplit
}
redirect -file [file join $report_dir final_power.rpt] {
  report_power -scenarios [get_scenarios FUNC_WC] -verbose -nosplit
}
redirect -file [file join $report_dir final_utilization.rpt] {
  report_utilization -verbose
}
redirect -file [file join $report_dir final_congestion.rpt] {
  report_congestion -mode summary -nosplit
}
redirect -file [file join $report_dir final_clock_qor.rpt] {
  report_clock_qor -all -nosplit
}
redirect -file [file join $report_dir final_legality.rpt] {
  check_legality -verbose
}
redirect -file [file join $report_dir final_pg_connectivity.rpt] {
  check_pg_connectivity -nets [get_nets {VDD VSS}] \
    -check_std_cell_pins all -check_block_pins none -check_pad_pins none
}
redirect -file [file join $report_dir final_routes.rpt] {
  check_routes -open_net true -drc true -antenna true
}
redirect -file [file join $report_dir final_lvs.rpt] {
  check_lvs -checks all -max_errors 200
}

# The corrected-constraint state must be present in the final reports.
require_report_line [file join $report_dir final_setup_worst_4d.rpt] \
  {clock uncertainty\s+-0\.2000} "setup clock uncertainty -0.2000"
require_report_line [file join $report_dir final_hold_worst_4d.rpt] \
  {clock uncertainty\s+0\.0500} "hold clock uncertainty +0.0500"

set FINAL_GDS [file join $result_dir ${TOP}.gds]
set FINAL_DEF [file join $result_dir ${TOP}.def]
set FINAL_NETLIST [file join $result_dir ${TOP}.postroute.v]
set FINAL_WC_SPEF [file join $result_dir ${TOP}.WC.spef]
set FINAL_BC_SPEF [file join $result_dir ${TOP}.BC.spef]

write_verilog -include all $FINAL_NETLIST
write_def $FINAL_DEF
write_parasitics -format spef -corner WC -output $FINAL_WC_SPEF
write_parasitics -format spef -corner BC -output $FINAL_BC_SPEF
write_gds -hierarchy all -lib_cell_view layout -long_names \
  -output_pin all -fill include -layer_map $gds_map \
  -layer_map_format $gds_map_format $FINAL_GDS

puts "PDE_ECO10_S3_DONE gds=$FINAL_GDS def=$FINAL_DEF netlist=$FINAL_NETLIST"
exit
