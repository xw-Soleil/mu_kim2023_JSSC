# Re-map the CKBD8 CTS cells to the pin-accessible CKBD4 equivalent available
# in both the TSMC65 LEF and the implementation Liberty, then legalize and
# hard-gate pin access before global routing.

set repo_root /home/sxw/PDE/pdeMujunjie
set work_dir [file join $repo_root flow work openroad]
set result_dir [file join $repo_root flow results openroad]
set report_dir [file join $repo_root flow reports openroad]
set liberty [file join $work_dir tcbn65lpwc_openroad_impl_sta.lib]

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
  puts "PDE_${tag}_UNCONNECTED_PG_ITERMS=[llength $null_pg]"
  if {[llength $null_pg] != 0} {error "$tag has unconnected PG terminals"}
}

read_liberty $liberty
read_db [file join $work_dir 20_cts_v4.odb]
read_sdc [file join $repo_root flow openroad pde_chip_top_safe_v2.sdc]
set_thread_count 8
set_propagated_clock [all_clocks]
set_routing_layers -signal M2-M6 -clock M3-M6
set_wire_rc -signal -layer M3
set_wire_rc -clock -layer M5

set db [ord::get_db]
set block [ord::get_db_block]
set ckbd4 NULL
foreach lib [$db getLibs] {
  set candidate [$lib findMaster CKBD4]
  if {$candidate != "NULL"} {set ckbd4 $candidate}
}
if {$ckbd4 == "NULL"} {error "CKBD4 master is missing from loaded LEF"}

set swapped 0
foreach inst [$block getInsts] {
  if {[[$inst getMaster] getName] eq "CKBD8"} {
    if {![$inst swapMaster $ckbd4]} {
      error "Failed equivalent-master swap for [$inst getName]"
    }
    incr swapped
  }
}
puts "PDE_CTS_CKBD8_TO_CKBD4_SWAPPED=$swapped"
if {$swapped != 3169} {error "Expected 3169 CKBD8 CTS cells, got $swapped"}

set_placement_padding -global -left 1 -right 1
detailed_placement -max_displacement {30 10} -disallow_one_site_gaps \
  -report_file_name [file join $report_dir 21_ckbd4_v7_placement.json]
global_connect
assert_all_pg_iterms_connected POST_CKBD4
check_placement -verbose -disallow_one_site_gaps

set guarded 0
foreach net [$block getNets] {
  set sig [$net getSigType]
  set pins [expr {[llength [$net getITerms]] + [llength [$net getBTerms]]}]
  if {![$net isSpecial] && $pins == 0 && ($sig eq "POWER" || $sig eq "GROUND")} {
    $net setSpecial
    incr guarded
  }
}
puts "PDE_PIN_ACCESS_GUARDED_ZERO_SUPPLY=$guarded"
if {$guarded != 203} {error "Expected 203 zero-terminal supply nets"}

pin_access -bottom_routing_layer M1 -top_routing_layer M6 -verbose 1

foreach net {VDD VSS} {
  psm::clear_solvers
  check_power_grid -net $net \
    -error_file [file join $report_dir 21_ckbd4_v7_${net}_open.rpt]
}

estimate_parasitics -placement
report_checks -path_delay max -fields {slew cap input_pins nets fanout} \
  > [file join $report_dir 21_ckbd4_v7_timing.rpt]
report_design_area
write_db [file join $work_dir 21_cts_ckbd4_pinaccess_v7.odb]
write_def [file join $result_dir 21_cts_ckbd4_pinaccess_v7.def]
write_sdc -no_timestamp [file join $result_dir 21_cts_ckbd4_pinaccess_v7.sdc]
puts "PDE_CTS_CKBD4_PINACCESS_V7_PASS"
exit
