# Strict global route using nominal routing capacity and deterministic net-order seed 2.  The 90% trial still had
# 14 bins with exactly one-track overflow and exposed a FastRoute heap bug.

set repo_root /home/sxw/PDE/pdeMujunjie
set work_dir [file join $repo_root flow work openroad]
set result_dir [file join $repo_root flow results openroad]
set report_dir [file join $repo_root flow reports openroad]
set liberty [file join $work_dir tcbn65lpwc_openroad_impl_sta.lib]
set input_db [file join $work_dir 20_cts_v3.odb]
set sdc [file join $repo_root flow openroad pde_chip_top_safe_v2.sdc]

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

read_liberty $liberty
read_db $input_db
read_sdc $sdc
set_thread_count 4
set_propagated_clock [all_clocks]
set_routing_layers -signal M2-M6 -clock M3-M6
foreach layer {M2 M3 M4 M5 M6} {
  set_global_routing_layer_adjustment $layer 0.0
}
set_wire_rc -signal -layer M3
set_wire_rc -clock -layer M5

global_connect
assert_all_pg_iterms_connected PRE_GRT
check_placement -verbose -disallow_one_site_gaps
foreach net {VDD VSS} {
  psm::clear_solvers
  check_power_grid -net $net \
    -error_file [file join $report_dir 30_pdn_v15_pregrt_${net}_open.rpt]
}

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

set_global_routing_random -seed 2

global_route -guide_file [file join $result_dir 30_route_antenna_v15.guide] \
  -congestion_iterations 100 -congestion_report_iter_step 10 \
  -critical_nets_percentage 0 \
  -congestion_report_file [file join $report_dir 30_congestion_v15.rpt]

set antenna_diodes [repair_antennas ANTENNA -iterations 3 -ratio_margin 20]
puts "PDE_GRT_ANTENNA_DIODES_INSERTED=$antenna_diodes"
global_connect
assert_all_pg_iterms_connected POST_ANTENNA
check_placement -verbose
estimate_parasitics -global_routing

write_db [file join $work_dir 35_antenna_v15.odb]
write_def [file join $result_dir 35_antenna_v15.def]
write_sdc -no_timestamp [file join $result_dir 35_antenna_v15.sdc]
write_guides [file join $result_dir 35_antenna_v15_postrepair.guide]

set antenna_violations [check_antennas \
  -report_file [file join $report_dir 35_antenna_v15.rpt]]
puts "PDE_PRE_DRT_ANTENNA_VIOLATIONS=$antenna_violations"
if {$antenna_violations != 0} {
  error "Pre-DRT antenna closure failed with $antenna_violations violating nets"
}

foreach net {VDD VSS} {
  psm::clear_solvers
  check_power_grid -net $net \
    -error_file [file join $report_dir 35_pdn_v15_${net}_open.rpt]
}

puts "PDE_OPENROAD_ROUTE_ANTENNA_V15_PASS"
exit



