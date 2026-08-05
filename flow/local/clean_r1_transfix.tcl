# Clean-flow round 1 targeted mop-up (full_clean_20260804).
#
# The per-scenario-SDC rerun came out of the box with setup WNS +0.74 (0
# violations), hold 0, max_cap 0, route DRC 0, LVS 0/0.  The only residue is
# 50 max_transition nets (1x -0.03, 12x -0.01, 37x -0.00).  With +0.74 ns of
# setup headroom a one-step driver upsize is risk-free; drivers with no larger
# variant fall back to the guarded BUFFD4 repeater (setup slack > 0.15 ns
# required).  Net names frozen from final_constraints.rpt of that run.

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
  u_impl/u_core/g_row_5__g_col_6__u_pe/read_value[3]
  u_impl/u_core/g_row_10__g_col_9__u_pe/u_alu/n20
  u_impl/ropt_net_1857
  u_impl/u_core/g_row_14__g_col_6__u_pe/n32
  u_impl/n5429_CDR1
  u_impl/u_core/g_row_3__g_col_1__u_pe/ZBUF_13_472
  u_impl/u_core/ZCTSNET_1946
  u_impl/ropt_net_1863
  u_impl/u_core/g_row_6__g_col_5__u_pe/u_sol/n72
  u_impl/u_core/g_row_5__g_col_3__u_pe/read_value[11]
  u_impl/u_core/g_row_12__g_col_1__u_pe/u_sol/ropt_net_2012
  u_impl/n2617_CDR1
  u_impl/u_core/u_boundary/n5923_CDR1
  u_impl/n753_CDR1
  u_impl/u_core/g_row_19__g_col_1__u_pe/read_value[3]
  u_impl/u_core/n681_CDR1
  u_impl/ZBUF_2_275
  u_impl/ZBUF_2_286
  u_impl/u_core/HFSNET_992
  u_impl/ZBUF_50_147
  u_impl/u_core/HFSNET_861
  u_impl/ropt_net_1847
  u_impl/u_core/g_row_13__g_col_1__u_pe/read_value[4]
  u_impl/u_core/g_row_9__g_col_6__u_pe/read_value[8]
  u_impl/u_core/g_row_4__g_col_1__u_pe/read_value[8]
  u_impl/load_black_flat[1875]
  u_impl/u_core/g_row_17__g_col_1__u_pe/ZBUF_13_470
  u_impl/u_core/g_row_4__g_col_1__u_pe/read_value[5]
  u_impl/u_core/g_row_16__g_col_9__u_pe/u_sol/n69
  u_impl/u_core/g_row_9__g_col_6__u_pe/read_value[6]
  u_impl/u_core/g_row_2__g_col_0__u_pe/u_sol/n69
  u_impl/u_core/g_row_12__g_col_5__u_pe/n23
  u_impl/u_core/g_row_6__g_col_1__u_pe/read_value[6]
  u_impl/u_core/g_row_17__g_col_2__u_pe/read_value[14]
  u_impl/u_core/g_row_10__g_col_9__u_pe/read_value[6]
  u_impl/u_core/g_row_0__g_col_3__u_pe/u_r_black/HFSNET_3
  u_impl/u_core/g_row_2__g_col_9__u_pe/u_black_we
  u_impl/n1636_CDR1
  u_impl/load_red_flat[288]
  u_impl/load_black_flat[2926]
  u_impl/u_core/g_row_12__g_col_1__u_pe/u_r_red/n9
  u_impl/load_red_flat[832]
  u_impl/u_core/g_row_19__g_col_3__u_pe/u_sol/n49
  u_impl/u_core/g_row_17__g_col_4__u_pe/copt_gre_net_1809
  u_impl/u_core/g_row_11__g_col_2__u_pe/u_r_black/n9
  u_impl/n1327_CDR1
  u_impl/u_core/g_row_11__g_col_0__u_pe/read_value[3]
  u_impl/u_core/g_row_14__g_col_8__u_pe/u_sol/n69
  u_impl/ZBUF_2_452
  u_impl/u_core/g_row_6__g_col_3__u_pe/u_black_we
}
set SHORT_FIX_NETS {}

set design_lib [require_env PDE_ECO10_DESIGN_LIB]
set report_dir [require_env PDE_ECO10_REPORT_DIR]
file mkdir $report_dir

set_host_options -max_cores 8
open_lib $design_lib
open_block pde_chip_top_safe.design
link_block
puts "PDE_CLEAN_R1_BEGIN design_lib=$design_lib"

current_scenario FUNC_WC
write_sdc -output [file join $report_dir s2t_entry_FUNC_WC.sdc]
require_report_line [file join $report_dir s2t_entry_FUNC_WC.sdc] \
  {set_clock_uncertainty -setup 0\.2} "setup uncertainty 0.2 in FUNC_WC"
puts "PDE_CLEAN_R1_CONSTRAINTS_OK"

# --- fillers out
set fillers [get_cells -quiet {xofiller!PDE_FILLER_!*}]
set filler_count [sizeof_collection $fillers]
puts "PDE_CLEAN_R1_FILLERS_BEFORE count=$filler_count"
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
    puts "PDE_CLEAN_R1_SIZED net=$net_name cell=[get_attribute $cell full_name] $ref->$target_ref"
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
  puts "PDE_CLEAN_R1_BUFFERED net=$net_name driver_ref=$ref slack=$gslack"
  incr sized
}
puts "PDE_CLEAN_R1_SIZE_SUMMARY sized=$sized skipped=[llength $skipped]"
foreach entry $skipped {
  puts "PDE_CLEAN_R1_SKIPPED [lindex $entry 0] reason=[lindex $entry 1]"
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
  puts "PDE_CLEAN_R1_ROUTES_REMOVED net=$net_name"
}

route_eco -open_net_driven true \
  -reroute modified_nets_first_then_others \
  -reuse_existing_global_route true \
  -utilize_dangling_wires true \
  -max_detail_route_iterations 100
puts "PDE_CLEAN_R1_ROUTE_ECO_OPEN_END"
route_eco -open_net_driven false \
  -reroute modified_nets_first_then_others \
  -reuse_existing_global_route true \
  -utilize_dangling_wires true \
  -max_detail_route_iterations 100
puts "PDE_CLEAN_R1_ROUTE_ECO_DRC_END"

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
puts "PDE_CLEAN_R1_FILLERS_AFTER count=[sizeof_collection [get_cells -quiet {xofiller!PDE_FILLER_!*}]]"

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
puts "PDE_CLEAN_R1_VERIFIED"

save_block
save_lib
puts "PDE_CLEAN_R1_DONE design_lib=$design_lib"
exit
