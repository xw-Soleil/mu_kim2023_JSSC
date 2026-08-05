# Detailed route from a matching strict BUFFD2 GRT checkpoint.  Zero DRT
# violations, full connectivity, zero antenna violations and PDN connectivity
# are hard gates.  Fillers are followed by a second DRT gate so their M1
# obstructions cannot invalidate a pre-filler route.

set repo_root /home/sxw/PDE/pdeMujunjie
set work_dir [file join $repo_root flow work openroad]
set result_dir [file join $repo_root flow results openroad]
set report_dir [file join $repo_root flow reports openroad]
set liberty [file join $work_dir tcbn65lpwc_openroad_impl_sta.lib]
if {![info exists ::env(PDE_DRT_INPUT_TAG)] || ![info exists ::env(PDE_DRT_TAG)]} {
  error "PDE_DRT_INPUT_TAG and PDE_DRT_TAG are required"
}
set input_tag $::env(PDE_DRT_INPUT_TAG)
set tag $::env(PDE_DRT_TAG)
set input_db [file join $work_dir 30_${input_tag}.odb]
set sdc [file join $result_dir 30_${input_tag}.sdc]

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
  if {$open_pg != 0} {error "$tag has $open_pg unconnected PG terminals"}
}

proc run_drt {tag report_dir work_dir result_dir} {
  set route_rc [catch {
    detailed_route \
      -output_maze [file join $report_dir ${tag}.maze.log] \
      -output_drc [file join $report_dir ${tag}_drc.rpt] \
      -output_cmap [file join $report_dir ${tag}.cmap] \
      -output_guide_coverage [file join $report_dir ${tag}_guide_coverage.rpt] \
      -drc_report_iter_step 5 -droute_end_iter 64 \
      -bottom_routing_layer M1 -top_routing_layer M6 \
      -save_guide_updates -verbose 1
  } route_msg]
  write_db [file join $work_dir ${tag}_diagnostic.odb]
  write_def -version 5.8 [file join $result_dir ${tag}_diagnostic.def]
  if {$route_rc != 0} {error "$tag detailed_route failed: $route_msg"}
  set drvs [detailed_route_num_drvs]
  puts "PDE_DRT_${tag}_DRVS=$drvs"
  if {$drvs != 0} {error "$tag left $drvs detailed-route violations"}
  if {![design_is_routed -verbose]} {error "$tag is not fully routed"}
}

read_liberty $liberty
read_db $input_db
read_sdc $sdc
set_thread_count 8
set_propagated_clock [all_clocks]
set_routing_layers -signal M2-M6 -clock M3-M6
set_wire_rc -signal -layer M3
set_wire_rc -clock -layer M5
global_connect
assert_all_pg_iterms_connected PRE_DRT
check_placement -verbose -disallow_one_site_gaps

set block [ord::get_db_block]
set guarded 0
foreach net [$block getNets] {
  set sig [$net getSigType]
  set pins [expr {[llength [$net getITerms]] + [llength [$net getBTerms]]}]
  if {[$net isSpecial] && $pins == 0 && ($sig eq "POWER" || $sig eq "GROUND")} {
    incr guarded
  }
}
puts "PDE_${tag}_ROUTING_GUARDED_SPECIAL_COUNT=$guarded"
if {$guarded != 203} {error "Expected 203 guarded zero-terminal supply nets"}

# Re-run the proven pin-access hard gate at the exact routed checkpoint.
pin_access -bottom_routing_layer M1 -top_routing_layer M6 -verbose 1
run_drt ${tag}_initial $report_dir $work_dir $result_dir

write_db [file join $work_dir 40_${tag}_routed_initial.odb]
write_def -version 5.8 [file join $result_dir 40_${tag}_routed_initial.def]
set antenna_violations [check_antennas \
  -report_file [file join $report_dir 40_${tag}_initial_antennas.rpt]]
puts "PDE_${tag}_POSTDR_ANT_INITIAL=$antenna_violations"

set antenna_round 0
while {$antenna_violations > 0 && $antenna_round < 3} {
  incr antenna_round
  set added [repair_antennas ANTENNA -iterations 1 -ratio_margin 20]
  puts "PDE_${tag}_ANT_ROUND_${antenna_round}_DIODES=$added"
  set_placement_padding -global -left 1 -right 1
  detailed_placement -max_displacement {10 5} -disallow_one_site_gaps
  global_connect
  assert_all_pg_iterms_connected ${tag}_POSTANT_${antenna_round}
  check_placement -verbose -disallow_one_site_gaps
  run_drt ${tag}_postant_${antenna_round} $report_dir $work_dir $result_dir
  set antenna_violations [check_antennas \
    -report_file [file join $report_dir 40_${tag}_postant_${antenna_round}.rpt]]
  puts "PDE_${tag}_ANT_ROUND_${antenna_round}_VIOLATIONS=$antenna_violations"
}
if {$antenna_violations != 0} {
  error "Post-DR antenna closure failed with $antenna_violations violating nets"
}

foreach net {VDD VSS} {
  psm::clear_solvers
  check_power_grid -net $net \
    -error_file [file join $report_dir 40_${tag}_prefill_${net}_open.rpt]
}
write_db [file join $work_dir 40_${tag}_prefill_antclosed.odb]
write_def -version 5.8 [file join $result_dir 40_${tag}_prefill_antclosed.def]

# Fill only after antenna closure, then rerun DRT so filler obstructions are
# included in the final zero-DRV decision.
set filler_masters {FILL64 FILL32 FILL16 FILL8 FILL4 FILL2 FILL1}
filler_placement -prefix PDE_FILL_ -verbose $filler_masters
global_connect
assert_all_pg_iterms_connected ${tag}_POSTFILL
check_placement -verbose -disallow_one_site_gaps \
  -report_file_name [file join $report_dir 45_${tag}_placement.json]
run_drt ${tag}_postfill $report_dir $work_dir $result_dir
set final_antennas [check_antennas \
  -report_file [file join $report_dir 45_${tag}_antennas.rpt]]
puts "PDE_${tag}_FINAL_ANTENNA_VIOLATIONS=$final_antennas"
if {$final_antennas != 0} {error "Final filled route has antenna violations"}

foreach net {VDD VSS} {
  psm::clear_solvers
  check_power_grid -net $net \
    -error_file [file join $report_dir 45_${tag}_${net}_open.rpt]
}

set restored 0
foreach net [$block getNets] {
  set sig [$net getSigType]
  set pins [expr {[llength [$net getITerms]] + [llength [$net getBTerms]]}]
  if {[$net isSpecial] && $pins == 0 && ($sig eq "POWER" || $sig eq "GROUND")} {
    $net clearSpecial
    incr restored
  }
}
puts "PDE_${tag}_RESTORED_ZERO_SUPPLY=$restored"
if {$restored != 203} {error "Expected to restore 203 zero-terminal supply nets"}

estimate_parasitics -global_routing
report_check_types -violators -max_slew -max_capacitance -max_fanout \
  > [file join $report_dir 45_${tag}_limit_violators.rpt]
report_check_types -violators -max_delay -min_delay -recovery -removal -max_skew \
  > [file join $report_dir 45_${tag}_timing_violators.rpt]
report_clock_skew -setup > [file join $report_dir 45_${tag}_clock_skew.rpt]
report_checks -path_delay max -fields {slew cap input_pins nets fanout} \
  > [file join $report_dir 45_${tag}_timing_checks.rpt]
report_design_area

write_db [file join $work_dir 45_${tag}_final.odb]
write_def -version 5.8 [file join $result_dir 45_${tag}_final.def]
write_verilog -sort -include_pwr_gnd \
  [file join $result_dir 45_${tag}_final_lvs.v]
write_verilog -sort -include_pwr_gnd -remove_cells $filler_masters \
  [file join $result_dir 45_${tag}_final_nofill.v]
write_sdc -no_timestamp [file join $result_dir 45_${tag}_final.sdc]
puts "PDE_OPENROAD_PHYSICAL_HARD_PASS tag=$tag"
exit
