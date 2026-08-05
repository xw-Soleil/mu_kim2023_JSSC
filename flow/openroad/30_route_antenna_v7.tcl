# Global routing and pre-detailed-route antenna closure on the corrected PDN.

set repo_root /home/sxw/PDE/pdeMujunjie
set work_dir [file join $repo_root flow work openroad]
set result_dir [file join $repo_root flow results openroad]
set report_dir [file join $repo_root flow reports openroad]
set liberty [file join $work_dir tcbn65lpwc_openroad_impl_sta.lib]
set input_db [file join $work_dir 20_cts_v2.odb]
set sdc [file join $repo_root flow openroad pde_chip_top_safe_v2.sdc]

read_liberty $liberty
read_db $input_db
read_sdc $sdc
set_thread_count 4
set_propagated_clock [all_clocks]

# This exact synthesized hierarchy has 203 terminal-free local supply nets.
# GRT ignores them, but this OpenROAD revision's antenna checker otherwise
# dereferences them.  Mark only this guarded set special through routing.
set block [ord::get_db_block]
set zero_supply_fixed 0
foreach net [$block getNets] {
  set sig [$net getSigType]
  set pin_count [expr {[llength [$net getITerms]] + [llength [$net getBTerms]]}]
  if {![$net isSpecial] && $pin_count == 0 && ($sig eq "POWER" || $sig eq "GROUND")} {
    $net setSpecial
    incr zero_supply_fixed
  }
}
puts "PDE_MARKED_ZERO_TERM_SUPPLY_SPECIAL=$zero_supply_fixed"
if {$zero_supply_fixed != 203} {
  error "Expected exactly 203 zero-terminal POWER/GROUND nets, got $zero_supply_fixed"
}

set_routing_layers -signal M2-M6 -clock M3-M6
foreach layer {M2 M3 M4 M5} {
  set_global_routing_layer_adjustment $layer 0.20
}
set_global_routing_layer_adjustment M6 0.10
set_wire_rc -signal -layer M3
set_wire_rc -clock -layer M5

global_route -guide_file [file join $result_dir 30_route_antenna_v7.guide] \
  -congestion_iterations 100 -congestion_report_iter_step 10 \
  -critical_nets_percentage 0 -allow_congestion \
  -congestion_report_file [file join $report_dir 30_congestion_v7.rpt]

repair_antennas ANTENNA -iterations 3 -ratio_margin 20
check_placement -verbose
estimate_parasitics -global_routing

# Preserve the repaired state even if the hard closure gate reports a failure.
write_db [file join $work_dir 35_antenna_v7.odb]
write_def [file join $result_dir 35_antenna_v7.def]
write_sdc -no_timestamp [file join $result_dir 35_antenna_v7.sdc]

set antenna_violations [check_antennas \
  -report_file [file join $report_dir 35_antenna_v7.rpt]]
puts "PDE_PRE_DRT_ANTENNA_VIOLATIONS=$antenna_violations"
if {$antenna_violations != 0} {
  error "Pre-DRT antenna closure failed with $antenna_violations violating nets"
}

foreach net {VDD VSS} {
  psm::clear_solvers
  check_power_grid -net $net \
    -error_file [file join $report_dir 35_pdn_v7_${net}_open.rpt]
}

puts "PDE_OPENROAD_ROUTE_ANTENNA_V7_PASS"
exit
