# Replace every CKBD8 with the logically equivalent BUFFD2 master.  BUFFD2 is
# present in both the TSMC65 LEF and the implementation Liberty and exposes a
# simple on-grid M1 output pin.  The change is physical-cell remapping only.

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
set replacement NULL
foreach lib [$db getLibs] {
  set candidate [$lib findMaster BUFFD2]
  if {$candidate != "NULL"} {set replacement $candidate}
}
if {$replacement == "NULL"} {error "BUFFD2 master is missing from loaded LEF"}

set swapped 0
foreach inst [$block getInsts] {
  if {[[$inst getMaster] getName] eq "CKBD8"} {
    if {![$inst swapMaster $replacement]} {
      error "Failed equivalent-master swap for [$inst getName]"
    }
    incr swapped
  }
}
puts "PDE_ALL_CKBD8_TO_BUFFD2_SWAPPED=$swapped"
if {$swapped != 3537} {error "Expected 3537 CKBD8 cells, got $swapped"}

set_placement_padding -global -left 1 -right 1
detailed_placement -max_displacement {30 10} -disallow_one_site_gaps \
  -report_file_name [file join $report_dir 21_buffd2_v9_placement.json]
global_connect
assert_all_pg_iterms_connected POST_BUFFD2
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
    -error_file [file join $report_dir 21_buffd2_v9_${net}_open.rpt]
}

estimate_parasitics -placement
report_checks -path_delay max -fields {slew cap input_pins nets fanout} \
  > [file join $report_dir 21_buffd2_v9_timing.rpt]
report_design_area
write_db [file join $work_dir 21_cts_buffd2_pinaccess_v9.odb]
write_def [file join $result_dir 21_cts_buffd2_pinaccess_v9.def]
write_sdc -no_timestamp [file join $result_dir 21_cts_buffd2_pinaccess_v9.sdc]
puts "PDE_CTS_BUFFD2_PINACCESS_V9_PASS"
exit
