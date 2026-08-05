# Detailed routing and physical closure from the congestion-hard v9 guide.

set repo_root /home/sxw/PDE/pdeMujunjie
set work_dir [file join $repo_root flow work openroad]
set result_dir [file join $repo_root flow results openroad]
set report_dir [file join $repo_root flow reports openroad]
set liberty [file join $work_dir tcbn65lpwc_openroad_impl_sta.lib]
set input_db [file join $work_dir 35_antenna_v9.odb]
set sdc [file join $repo_root flow results openroad 35_antenna_v9.sdc]

proc assert_all_pg_iterms_connected {tag} {
  set block [ord::get_db_block]
  set open_pg 0
  foreach inst [$block getInsts] {
    foreach iterm [$inst getITerms] {
      set sig [[$iterm getMTerm] getSigType]
      if {($sig eq "POWER" || $sig eq "GROUND") && [$iterm getNet] == "NULL"} {
        incr open_pg
      }
    }
  }
  puts "PDE_${tag}_UNCONNECTED_PG_ITERMS=$open_pg"
  if {$open_pg != 0} {error "$tag has $open_pg unconnected PG instance terminals"}
}

read_liberty $liberty
read_db $input_db
read_sdc $sdc
set_thread_count 4
set_propagated_clock [all_clocks]
set_routing_layers -signal M2-M6 -clock M3-M6
set_wire_rc -signal -layer M3
set_wire_rc -clock -layer M5

set block [ord::get_db_block]
set guarded_special 0
foreach net [$block getNets] {
  set sig [$net getSigType]
  set pin_count [expr {[llength [$net getITerms]] + [llength [$net getBTerms]]}]
  if {[$net isSpecial] && $pin_count == 0 && ($sig eq "POWER" || $sig eq "GROUND")} {
    incr guarded_special
  }
}
puts "PDE_ROUTING_GUARDED_SPECIAL_COUNT=$guarded_special"
if {$guarded_special != 203} {
  error "Expected 203 guarded zero-terminal supply nets, got $guarded_special"
}

detailed_route \
  -output_maze [file join $report_dir 40_route_v9_maze.log] \
  -output_drc [file join $report_dir 40_route_v9_drc.rpt] \
  -output_cmap [file join $report_dir 40_route_v9_cmap.csv] \
  -output_guide_coverage [file join $report_dir 40_route_v9_guide_coverage.rpt] \
  -drc_report_iter_step 5 -droute_end_iter 64 \
  -bottom_routing_layer M1 -top_routing_layer M6 \
  -save_guide_updates -verbose 1

set route_drvs [detailed_route_num_drvs]
puts "PDE_DETAILED_ROUTE_DRVS=$route_drvs"
if {$route_drvs != 0} {error "Detailed routing has $route_drvs violations"}
if {![design_is_routed -verbose]} {error "Detailed routing left unrouted nets"}

write_db [file join $work_dir 40_route_v9_prefill.odb]
write_def [file join $result_dir 40_route_v9_prefill.def]

set antenna_violations [check_antennas \
  -report_file [file join $report_dir 40_route_v9_antennas.rpt]]
puts "PDE_POST_DRT_ANTENNA_VIOLATIONS=$antenna_violations"
if {$antenna_violations != 0} {
  error "Post-DRT antenna closure failed with $antenna_violations violating nets"
}

foreach net {VDD VSS} {
  psm::clear_solvers
  check_power_grid -net $net \
    -error_file [file join $report_dir 40_pdn_v9_prefill_${net}_open.rpt]
}

set filler_masters {FILL64 FILL32 FILL16 FILL8 FILL4 FILL2 FILL1}
filler_placement -prefix PDE_FILL_ -verbose $filler_masters
global_connect
assert_all_pg_iterms_connected FINAL
check_placement -verbose -disallow_one_site_gaps \
  -report_file_name [file join $report_dir 40_route_v9_placement.json]

foreach net {VDD VSS} {
  psm::clear_solvers
  check_power_grid -net $net \
    -error_file [file join $report_dir 40_pdn_v9_final_${net}_open.rpt]
}

set zero_supply_restored 0
foreach net [$block getNets] {
  set sig [$net getSigType]
  set pin_count [expr {[llength [$net getITerms]] + [llength [$net getBTerms]]}]
  if {[$net isSpecial] && $pin_count == 0 && ($sig eq "POWER" || $sig eq "GROUND")} {
    $net setSpecial 0
    incr zero_supply_restored
  }
}
puts "PDE_RESTORED_ZERO_TERM_SUPPLY_NORMAL=$zero_supply_restored"
if {$zero_supply_restored != 203} {
  error "Expected to restore 203 zero-terminal supply nets, got $zero_supply_restored"
}

estimate_parasitics -global_routing
redirect [file join $report_dir 40_route_v9_checks.rpt] {
  report_checks -path_delay max -fields {slew cap input_pins nets fanout}
}
write_db [file join $work_dir 40_route.odb]
write_def [file join $result_dir 40_route.def]
write_verilog -include_pwr_gnd -remove_cells $filler_masters \
  [file join $result_dir 40_route.v]
write_sdc -no_timestamp [file join $result_dir 40_route.sdc]
puts "PDE_OPENROAD_DETAILED_ROUTE_V9_PASS"
exit
