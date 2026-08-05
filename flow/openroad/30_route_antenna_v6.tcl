# Global route and antenna repair in one process, with a narrowly-scoped
# workaround for an OpenROAD v2.0-17598 antenna-checker null dereference.

set repo_root /home/sxw/PDE/pdeMujunjie
set work_dir [file join $repo_root flow work openroad]
set result_dir [file join $repo_root flow results openroad]
set report_dir [file join $repo_root flow reports openroad]
set liberty [file join $work_dir tcbn65lpwc_openroad_impl_sta.lib]
set input_db [file join $work_dir 20_cts.odb]
set sdc [file join $repo_root flow openroad pde_chip_top_safe_v2.sdc]

read_liberty $liberty
read_db $input_db
read_sdc $sdc
set_thread_count 4
set_propagated_clock [all_clocks]

# The hierarchical DC netlist contains exactly 203 local constant supply nets
# with no physical terminals.  GRT excludes them, but this OpenROAD revision's
# antenna checker dereferences them unless they are marked special.  The exact
# count is a guard against accidentally changing a real signal or PG net.
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

global_route -guide_file [file join $result_dir 30_route_antenna_v6.guide] \
  -congestion_iterations 100 -critical_nets_percentage 0 \
  -allow_congestion

# Filler cells must not be present while antenna diodes are inserted.
repair_antennas ANTENNA -iterations 3 -ratio_margin 20
check_placement -verbose -disallow_one_site_gaps
estimate_parasitics -global_routing

# Save before optional reports so this checkpoint survives report failures.
write_db [file join $work_dir 35_antenna_v6.odb]
write_def [file join $result_dir 35_antenna_v6.def]
write_sdc -no_timestamp [file join $result_dir 35_antenna_v6.sdc]
check_antennas -report_violating_nets \
  -report_file [file join $report_dir 35_antenna_v6.rpt]
puts "PDE_OPENROAD_ROUTE_ANTENNA_V6_PASS"
exit
