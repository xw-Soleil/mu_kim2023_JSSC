# Clean-flow round 3: single-net fix for u_impl/n12297 (-0.09 max_transition
# in FUNC_WC after the global route_opt round).  The two remaining -0.00 rows
# (n944_CDR1, g_row_2__g_col_7 u_red_we) are at-the-limit flicker and are
# waived per the documented policy.  Upsize-or-guarded-buffer, then the full
# check battery.

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

proc require_report_line {report_file pattern description} {
  set fh [open $report_file r]
  set text [read $fh]
  close $fh
  if {![regexp $pattern $text]} {
    error "Verification failed: $description not found in $report_file"
  }
}

# One drive step up within the same cell family, e.g. CKBD4 -> CKBD6 if that
# exists in the NDM, else CKBD8, ...  Returns empty string when no larger
# variant exists or the name does not follow the <base>D<drive> convention.
proc next_drive_ref {ref_name} {
  if {[regexp {^DEL} $ref_name]} {
    return ""
  }
  if {![regexp {^(.*D)(\d+)$} $ref_name -> base drive]} {
    return ""
  }
  set drive [scan $drive %d]
  foreach cand {1 2 3 4 6 8 12 16 20 24 32} {
    if {$cand <= $drive} continue
    if {[sizeof_collection [get_lib_cells -quiet */${base}${cand}]] == 1} {
      return ${base}${cand}
    }
  }
  return ""
}

set TRANS_FIX_NETS {
  u_impl/n12297
}
set SHORT_FIX_NETS {}

set design_lib [require_env PDE_ECO10_DESIGN_LIB]
set report_dir [require_env PDE_ECO10_REPORT_DIR]
file mkdir $report_dir

set_host_options -max_cores 8
open_lib $design_lib
open_block pde_chip_top_safe.design
link_block
puts "PDE_CLEAN_R3_BEGIN design_lib=$design_lib"

current_scenario FUNC_WC
write_sdc -output [file join $report_dir s2t_entry_FUNC_WC.sdc]
require_report_line [file join $report_dir s2t_entry_FUNC_WC.sdc] \
  {set_clock_uncertainty -setup 0\.2} "setup uncertainty 0.2 in FUNC_WC"
puts "PDE_CLEAN_R3_CONSTRAINTS_OK"

# --- fillers out
set fillers [get_cells -quiet {xofiller!PDE_FILLER_!*}]
set filler_count [sizeof_collection $fillers]
puts "PDE_CLEAN_R3_FILLERS_BEFORE count=$filler_count"
if {$filler_count < 100000} {
  error "Implausible baseline filler count: $filler_count"
}
set removed_count [remove_cells $fillers]
if {$removed_count != $filler_count} {
  error "Removed $removed_count of $filler_count fillers"
}

# --- driver upsizing for the frozen max_transition net list
set sized 0
set skipped {}
foreach net_name $TRANS_FIX_NETS {
  set net [get_nets -quiet $net_name]
  if {[sizeof_collection $net] != 1} {
    lappend skipped [list $net_name missing_net]
    continue
  }
  set driver [get_pins -leaf -quiet -of_objects $net -filter "direction==out"]
  if {[sizeof_collection $driver] != 1} {
    lappend skipped [list $net_name driver_count_[sizeof_collection $driver]]
    continue
  }
  set cell [get_cells -quiet -of_objects $driver]
  set ref [get_attribute $cell ref_name]
  set target_ref [next_drive_ref $ref]
  if {$target_ref ne ""} {
    set target [get_lib_cells -quiet */$target_ref]
    set_dont_touch $cell false
    size_cell $cell -lib_cell $target
    puts "PDE_CLEAN_R3_SIZED net=$net_name cell=[get_attribute $cell full_name] $ref->$target_ref"
    incr sized
    continue
  }
  current_scenario FUNC_WC
  set gpaths [get_timing_paths -through $net -delay_type max -max_paths 1]
  set gslack 999
  if {[sizeof_collection $gpaths] > 0} { set gslack [get_attribute $gpaths slack] }
  if {$gslack < 0.15} {
    lappend skipped [list $net_name setup_guard_$gslack]
    continue
  }
  set added [insert_buffer $driver -lib_cell [get_lib_cells */BUFFD4] -snap \
    -new_cell_names PDE_TRANSFIX_BUF -new_net_names PDE_TRANSFIX_NET]
  if {[sizeof_collection $added] != 1} {
    error "Buffer insertion failed on $net_name"
  }
  puts "PDE_CLEAN_R3_BUFFERED net=$net_name driver_ref=$ref slack=$gslack"
  incr sized
}
puts "PDE_CLEAN_R3_SIZE_SUMMARY sized=$sized skipped=[llength $skipped]"
foreach entry $skipped {
  puts "PDE_CLEAN_R3_SKIPPED [lindex $entry 0] reason=[lindex $entry 1]"
}
if {$sized == 0} {
  error "No driver was resized; net list is stale"
}

# --- legalize the resized cells
place_eco_cells -eco_changed_cells -legalize_mode allow_move_other_cells

# --- strip the two stuck short offenders and reroute
foreach net_name $SHORT_FIX_NETS {
  set net [get_nets -quiet $net_name]
  if {[sizeof_collection $net] != 1} {
    error "Short-fix net not found: $net_name"
  }
  remove_routes -nets $net -detail_route -global_route
  puts "PDE_CLEAN_R3_ROUTES_REMOVED net=$net_name"
}

route_eco -open_net_driven true \
  -reroute modified_nets_first_then_others \
  -reuse_existing_global_route true \
  -utilize_dangling_wires true \
  -max_detail_route_iterations 100
puts "PDE_CLEAN_R3_ROUTE_ECO_OPEN_END"
route_eco -open_net_driven false \
  -reroute modified_nets_first_then_others \
  -reuse_existing_global_route true \
  -utilize_dangling_wires true \
  -max_detail_route_iterations 100
puts "PDE_CLEAN_R3_ROUTE_ECO_DRC_END"

# --- fillers back
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
puts "PDE_CLEAN_R3_FILLERS_AFTER count=[sizeof_collection [get_cells -quiet {xofiller!PDE_FILLER_!*}]]"

# --- report battery
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

require_report_line [file join $report_dir s2_setup_worst_4d.rpt] \
  {clock uncertainty\s+-0\.2000} "setup clock uncertainty -0.2000"
require_report_line [file join $report_dir s2_hold_worst_4d.rpt] \
  {clock uncertainty\s+0\.0500} "hold clock uncertainty +0.0500"
puts "PDE_CLEAN_R3_VERIFIED"

save_block
save_lib
puts "PDE_CLEAN_R3_DONE design_lib=$design_lib"
exit
