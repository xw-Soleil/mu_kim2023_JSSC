# Add the one-site detailed-routing padding used by the reference OpenROAD
# flow, legalize the post-CTS design, and hard-gate pin access before rerouting.

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
  if {[llength $null_pg] != 0} {
    error "$tag has unconnected PG instance terminals"
  }
}

read_liberty $liberty
read_db [file join $work_dir 20_cts_v4.odb]
read_sdc [file join $repo_root flow openroad pde_chip_top_safe_v2.sdc]
set_thread_count 8
set_propagated_clock [all_clocks]
set_routing_layers -signal M2-M6 -clock M3-M6

set_placement_padding -global -left 1 -right 1
detailed_placement -max_displacement {30 10} -disallow_one_site_gaps \
  -report_file_name [file join $report_dir 21_padding_v5_placement.json]
global_connect
assert_all_pg_iterms_connected POST_PADDING
check_placement -verbose -disallow_one_site_gaps

set block [ord::get_db_block]
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
    -error_file [file join $report_dir 21_padding_v5_${net}_open.rpt]
}

write_db [file join $work_dir 21_pin_access_padding_v5.odb]
write_def [file join $result_dir 21_pin_access_padding_v5.def]
write_sdc -no_timestamp [file join $result_dir 21_pin_access_padding_v5.sdc]
puts "PDE_PIN_ACCESS_PADDING_V5_PASS"
exit
