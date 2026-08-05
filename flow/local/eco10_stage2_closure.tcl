# ECO10 stage 2: timing/electrical closure under the corrected constraints.
#
# Prerequisites: stage 1 (split uncertainty) and stage 1b (FUNC_WC scenario
# constraints restored) have been saved into the eco10 design library.  This
# stage re-runs timing-driven post-route optimization so route_opt can
#   - fix the ~29 real setup violations (WNS ~-0.21 ns), largely by removing
#     or downsizing the DEL* delay cells inserted for the phantom 0.2 ns hold
#     target (7,688 DEL1 alone in the eco03 netlist),
#   - clean the 7,945 max_transition / 14 max_capacitance violations exposed
#     by restoring the 0.5 ns design limit to FUNC_WC,
#   - keep hold clean against the real 0.05 ns target.
# Sequence mirrors the proven eco04 session: fillers out -> route_opt ->
# route_eco -> fillers in -> full check battery -> save.

proc require_env {name} {
  if {![info exists ::env($name)] || [string trim $::env($name)] eq ""} {
    error "Missing required environment variable: $name"
  }
  return [file normalize $::env($name)]
}

proc connect_named_pg_pins {} {
  set vdd_pins [get_pins -hierarchical -physical_context -quiet */VDD]
  set vss_pins [get_pins -hierarchical -physical_context -quiet */VSS]
  if {[sizeof_collection $vdd_pins] == 0 || [sizeof_collection $vss_pins] == 0} {
    error "Missing physical VDD/VSS pins"
  }
  connect_pg_net -net VDD $vdd_pins
  connect_pg_net -net VSS $vss_pins
}

proc del_cell_census {} {
  set dels [get_cells -hierarchical -quiet -filter {ref_name =~ DEL*}]
  return [sizeof_collection $dels]
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
file mkdir $report_dir

set_host_options -max_cores 8
open_lib $design_lib
open_block pde_chip_top_safe.design
link_block
puts "PDE_ECO10_S2_BEGIN design_lib=$design_lib"

# Constraint-state guard: refuse to optimize against anything but the split
# uncertainty (stage 1/1b must have been saved into this library).
current_scenario FUNC_WC
write_sdc -output [file join $report_dir s2_entry_FUNC_WC.sdc]
require_report_line [file join $report_dir s2_entry_FUNC_WC.sdc] \
  {set_clock_uncertainty -setup 0\.2} "setup uncertainty 0.2 in FUNC_WC"
require_report_line [file join $report_dir s2_entry_FUNC_WC.sdc] \
  {set_input_delay} "restored input delays in FUNC_WC"
current_scenario FUNC_BC
write_sdc -output [file join $report_dir s2_entry_FUNC_BC.sdc]
require_report_line [file join $report_dir s2_entry_FUNC_BC.sdc] \
  {set_clock_uncertainty -hold 0\.05} "hold uncertainty 0.05 in FUNC_BC"
puts "PDE_ECO10_S2_CONSTRAINTS_OK"

puts "PDE_ECO10_S2_DEL_BEFORE count=[del_cell_census]"

# --- fillers out (they are placement-only; route_opt must see the free sites)
set fillers [get_cells -quiet {xofiller!PDE_FILLER_!*}]
set filler_count [sizeof_collection $fillers]
puts "PDE_ECO10_S2_FILLERS_BEFORE count=$filler_count"
if {$filler_count < 100000} {
  error "Implausible baseline filler count: $filler_count"
}
set removed_count [remove_cells $fillers]
if {$removed_count != $filler_count} {
  error "Removed $removed_count of $filler_count fillers"
}
puts "PDE_ECO10_S2_FILLERS_REMOVED count=$removed_count"

# --- timing/electrical optimization under the corrected targets
puts "PDE_ECO10_S2_ROUTE_OPT_BEGIN"
route_opt
puts "PDE_ECO10_S2_ROUTE_OPT_END"

puts "PDE_ECO10_S2_DEL_AFTER count=[del_cell_census]"

# --- clean any open/DRC introduced by cell and route changes
route_eco -open_net_driven false \
  -reroute modified_nets_first_then_others \
  -reuse_existing_global_route true \
  -utilize_dangling_wires true \
  -max_detail_route_iterations 100
puts "PDE_ECO10_S2_ROUTE_ECO_END"

# --- fillers back with the verified FILL family only
set filler_patterns {}
foreach filler_master {FILL64 FILL32 FILL16 FILL8 FILL4 FILL2 FILL1} {
  set cells [get_lib_cells -quiet */$filler_master]
  if {[sizeof_collection $cells] != 1} {
    error "Expected one library cell for $filler_master"
  }
  lappend filler_patterns "*/$filler_master"
}
set filler_cells [get_lib_cells $filler_patterns]
create_stdcell_fillers -lib_cells $filler_cells -prefix PDE_FILLER_
connect_named_pg_pins
set final_fillers [get_cells -quiet {xofiller!PDE_FILLER_!*}]
puts "PDE_ECO10_S2_FILLERS_AFTER count=[sizeof_collection $final_fillers]"

# --- full report battery
redirect -file [file join $report_dir s2_pvt.rpt] {
  report_pvt
}
redirect -file [file join $report_dir s2_qor.rpt] {
  report_qor -nosplit
}
current_scenario FUNC_WC
redirect -file [file join $report_dir s2_constraints_FUNC_WC.rpt] {
  report_constraints -all_violators -nosplit
}
redirect -file [file join $report_dir s2_setup_violations_4d.rpt] {
  report_timing -delay_type max -scenarios [get_scenarios FUNC_WC] \
    -max_paths 10000 -slack_lesser_than 0 \
    -significant_digits 4 -physical -nosplit
}
redirect -file [file join $report_dir s2_setup_worst_4d.rpt] {
  report_timing -delay_type max -scenarios [get_scenarios FUNC_WC] \
    -max_paths 1 -significant_digits 4 -physical -nosplit
}
current_scenario FUNC_BC
redirect -file [file join $report_dir s2_constraints_FUNC_BC.rpt] {
  report_constraints -all_violators -nosplit
}
redirect -file [file join $report_dir s2_hold_violations_4d.rpt] {
  report_timing -delay_type min -scenarios [get_scenarios FUNC_BC] \
    -max_paths 10000 -slack_lesser_than 0 \
    -significant_digits 4 -physical -nosplit
}
redirect -file [file join $report_dir s2_hold_worst_4d.rpt] {
  report_timing -delay_type min -scenarios [get_scenarios FUNC_BC] \
    -max_paths 1 -significant_digits 4 -physical -nosplit
}
redirect -file [file join $report_dir s2_routes.rpt] {
  check_routes -open_net true -drc true -antenna true
}
redirect -file [file join $report_dir s2_lvs.rpt] {
  check_lvs -checks all -max_errors 200
}
redirect -file [file join $report_dir s2_legality.rpt] {
  check_legality -verbose
}
redirect -file [file join $report_dir s2_pg_connectivity.rpt] {
  check_pg_connectivity -nets [get_nets {VDD VSS}] \
    -check_std_cell_pins all -check_block_pins none -check_pad_pins none
}

# Uncertainty regression guard: optimization must not have disturbed the split.
require_report_line [file join $report_dir s2_setup_worst_4d.rpt] \
  {clock uncertainty\s+-0\.2000} "setup clock uncertainty -0.2000"
require_report_line [file join $report_dir s2_hold_worst_4d.rpt] \
  {clock uncertainty\s+0\.0500} "hold clock uncertainty +0.0500"
puts "PDE_ECO10_S2_VERIFIED"

save_block
save_lib
puts "PDE_ECO10_S2_DONE design_lib=$design_lib"
exit
