# Detailed route with bounded post-route antenna repair/reroute closure.

set repo_root /home/sxw/PDE/pdeMujunjie
set work_dir [file join $repo_root flow work openroad]
set result_dir [file join $repo_root flow results openroad]
set report_dir [file join $repo_root flow reports openroad]
set liberty [file join $work_dir tcbn65lpwc_openroad_impl_sta.lib]
set input_db [file join $work_dir 35_antenna_v9.odb]
set sdc [file join $repo_root flow results openroad 35_antenna_v9.sdc]

proc assert_all_pg_iterms_connected {tag} {
  set block [ord::get_db_block]
  set null_pg {}
  foreach inst [$block getInsts] {
    foreach iterm [$inst getITerms] {
      set sig [[$iterm getMTerm] getSigType]
      if {($sig eq "POWER" || $sig eq "GROUND") && [$iterm getNet] == "NULL"} {
        lappend null_pg [$iterm getName]
      }
    }
  }
  set open_pg [llength $null_pg]
  puts "PDE_${tag}_UNCONNECTED_PG_ITERMS=$open_pg"
  if {$open_pg != 0} {
    error "$tag has $open_pg unconnected PG instance terminals; first=[lindex $null_pg 0]"
  }
}

proc run_drt {tag report_dir} {
  detailed_route \
    -output_maze [file join $report_dir ${tag}.maze.log] \
    -output_drc [file join $report_dir ${tag}_drc.rpt] \
    -output_cmap [file join $report_dir ${tag}.cmap] \
    -output_guide_coverage [file join $report_dir ${tag}_guide_coverage.rpt] \
    -drc_report_iter_step 5 -droute_end_iter 64 \
    -bottom_routing_layer M1 -top_routing_layer M6 \
    -save_guide_updates -verbose 1
  set drvs [detailed_route_num_drvs]
  puts "PDE_DRT_${tag}_DRVS=$drvs"
  if {$drvs != 0} {error "$tag left $drvs detailed-route violations"}
  if {![design_is_routed -verbose]} {error "$tag is not fully routed"}
}

read_liberty $liberty
read_db $input_db
read_sdc $sdc
set_thread_count 4
set_propagated_clock [all_clocks]
set_routing_layers -signal M2-M6 -clock M3-M6
set_wire_rc -signal -layer M3
set_wire_rc -clock -layer M5
global_connect
assert_all_pg_iterms_connected PRE_DRT

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

run_drt initial $report_dir
set antenna_violations [check_antennas \
  -report_file [file join $report_dir 40_initial_antennas.rpt]]
puts "PDE_POSTDR_ANT_INITIAL_VIOLATING_NETS=$antenna_violations"

set antenna_round 0
while {$antenna_violations > 0 && $antenna_round < 3} {
  incr antenna_round
  set added [repair_antennas ANTENNA -ratio_margin 20]
  puts "PDE_POSTDR_ANT_ROUND_${antenna_round}_DIODES=$added"
  global_connect
  assert_all_pg_iterms_connected POSTDR_ANT_${antenna_round}
  check_placement -verbose
  run_drt postant_${antenna_round} $report_dir
  set antenna_violations [check_antennas \
    -report_file [file join $report_dir 40_postant_${antenna_round}.rpt]]
  puts "PDE_POSTDR_ANT_ROUND_${antenna_round}_VIOLATING_NETS=$antenna_violations"
}
if {$antenna_violations != 0} {
  error "Post-DR antenna closure failed with $antenna_violations violating nets"
}
set final_drvs [detailed_route_num_drvs]
if {$final_drvs != 0} {error "Final detailed routing has $final_drvs violations"}
if {![design_is_routed -verbose]} {error "Final design is not fully routed"}

foreach net {VDD VSS} {
  psm::clear_solvers
  check_power_grid -net $net \
    -error_file [file join $report_dir 40_pdn_v10_prefill_${net}_open.rpt]
}

# Keep a no-filler ECO checkpoint with the antenna workaround still active.
write_db [file join $work_dir 40_route_prefill_antclosed.odb]
write_def -version 5.8 [file join $result_dir 40_route_prefill_antclosed.def]

# No further signal routing or antenna analysis occurs after this restoration.
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

set filler_masters {FILL64 FILL32 FILL16 FILL8 FILL4 FILL2 FILL1}
filler_placement -prefix PDE_FILL_ -verbose $filler_masters
global_connect
assert_all_pg_iterms_connected FINAL
check_placement -verbose -disallow_one_site_gaps \
  -report_file_name [file join $report_dir 45_final_placement.json]

foreach net {VDD VSS} {
  psm::clear_solvers
  check_power_grid -net $net \
    -error_file [file join $report_dir 45_pdn_final_${net}_open.rpt]
}

estimate_parasitics -global_routing
check_setup -verbose > [file join $report_dir 45_check_setup.rpt]
report_floating_nets -verbose > [file join $report_dir 45_floating_nets.rpt]
report_checks -path_delay max -fields {slew cap input_pins nets fanout} \
  > [file join $report_dir 45_timing_checks.rpt]
report_design_area

write_db [file join $work_dir 45_final.odb]
write_def -version 5.8 [file join $result_dir 45_final.def]
write_def -version 5.8 [file join $result_dir 40_route.def]
write_verilog -sort -include_pwr_gnd \
  [file join $result_dir 45_final_lvs.v]
write_verilog -sort -include_pwr_gnd -remove_cells $filler_masters \
  [file join $result_dir 45_final_nofill.v]
write_verilog -sort -include_pwr_gnd -remove_cells $filler_masters \
  [file join $result_dir 40_route.v]
write_sdc -no_timestamp [file join $result_dir 45_final.sdc]
write_sdc -no_timestamp [file join $result_dir 40_route.sdc]
puts "PDE_OPENROAD_PHYSICAL_FINAL_HARD_PASS"
exit
