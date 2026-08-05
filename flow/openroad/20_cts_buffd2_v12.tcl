# CTS v12: BUFFD2 tree on the repaired v5 placement, without the clock NDR.
#
# The v11 double-width/double-spacing NDR multiplied clock track usage on the
# already congested lower layers; v12 drops -apply_ndr and keeps everything
# else from v11 (BUFFD2-only masters, pin-access guard, PG assertions).

set repo_root /home/sxw/PDE/pdeMujunjie
set work_dir [file join $repo_root flow work openroad]
set result_dir [file join $repo_root flow results openroad]
set report_dir [file join $repo_root flow reports openroad]
set liberty [file join $work_dir tcbn65lpwc_openroad_impl_sta.lib]
set input_db [file join $work_dir 10_place_v5.odb]
set sdc [file join $repo_root flow openroad pde_chip_top_safe_v2.sdc]

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

read_liberty $liberty
read_db $input_db
read_sdc $sdc
set_thread_count 16
set_routing_layers -signal M2-M6 -clock M3-M6
set_global_routing_layer_adjustment M2 0.50
set_global_routing_layer_adjustment M3 0.40
set_global_routing_layer_adjustment M4 0.20
set_global_routing_layer_adjustment M5 0.20
set_global_routing_layer_adjustment M6 0.10
set_wire_rc -signal -layer M3
set_wire_rc -clock -layer M5

set block [ord::get_db_block]
set pre_buffd2 0
foreach inst [$block getInsts] {
  if {[[$inst getMaster] getName] eq "BUFFD2"} {incr pre_buffd2}
}
puts "PDE_PRECTS_BUFFD2_COUNT=$pre_buffd2"

clock_tree_synthesis -buf_list {BUFFD2} -root_buf BUFFD2 \
  -wire_unit 20 -obstruction_aware
set_placement_padding -global -left 1 -right 1
detailed_placement -max_displacement {30 10} -disallow_one_site_gaps \
  -report_file_name [file join $report_dir 20_cts_buffd2_v12_placement.json]
global_connect
assert_all_pg_iterms_connected CTS_BUFFD2
check_placement -verbose -disallow_one_site_gaps

set post_buffd2 0
set post_ckbd8 0
foreach inst [$block getInsts] {
  set master [[$inst getMaster] getName]
  if {$master eq "BUFFD2"} {incr post_buffd2}
  if {$master eq "CKBD8"} {incr post_ckbd8}
}
set inserted_buffd2 [expr {$post_buffd2 - $pre_buffd2}]
puts "PDE_CTS_BUFFD2_INSERTED=$inserted_buffd2"
puts "PDE_POSTCTS_CKBD8_COUNT=$post_ckbd8"
if {$inserted_buffd2 <= 0} {error "CTS inserted no BUFFD2 cells"}
if {$post_ckbd8 != 0} {error "CTS left $post_ckbd8 CKBD8 cells"}

set guarded 0
foreach net [$block getNets] {
  set sig [$net getSigType]
  set pins [expr {[llength [$net getITerms]] + [llength [$net getBTerms]]}]
  if {![$net isSpecial] && $pins == 0 && ($sig eq "POWER" || $sig eq "GROUND")} {
    $net setSpecial
    incr guarded
  }
}
puts "PDE_CTS_PIN_ACCESS_GUARDED=$guarded"
if {$guarded != 203} {error "Expected 203 zero-terminal supply nets"}
pin_access -bottom_routing_layer M1 -top_routing_layer M6 -verbose 1

set restored 0
foreach net [$block getNets] {
  set sig [$net getSigType]
  set pins [expr {[llength [$net getITerms]] + [llength [$net getBTerms]]}]
  if {[$net isSpecial] && $pins == 0 && ($sig eq "POWER" || $sig eq "GROUND")} {
    $net clearSpecial
    incr restored
  }
}
puts "PDE_CTS_PIN_ACCESS_RESTORED=$restored"
if {$restored != 203} {error "Expected to restore 203 zero-terminal supply nets"}

set_propagated_clock [all_clocks]
estimate_parasitics -placement
foreach net {VDD VSS} {
  psm::clear_solvers
  check_power_grid -net $net \
    -error_file [file join $report_dir 20_cts_buffd2_v12_${net}_open.rpt]
}

write_db [file join $work_dir 20_cts_buffd2_v12.odb]
write_def [file join $result_dir 20_cts_buffd2_v12.def]
write_verilog -include_pwr_gnd [file join $result_dir 20_cts_buffd2_v12.v]
write_sdc -no_timestamp [file join $result_dir 20_cts_buffd2_v12.sdc]
report_cts -out_file [file join $report_dir 20_cts_buffd2_v12.rpt]
puts "PDE_OPENROAD_CTS_BUFFD2_V12_PASS"
exit
