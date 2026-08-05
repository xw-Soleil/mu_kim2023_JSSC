# CTS with explicit PG reconnection for all newly inserted clock buffers.

set repo_root /home/sxw/PDE/pdeMujunjie
set work_dir [file join $repo_root flow work openroad]
set result_dir [file join $repo_root flow results openroad]
set report_dir [file join $repo_root flow reports openroad]
set liberty [file join $work_dir tcbn65lpwc_openroad_impl_sta.lib]
set input_db [file join $work_dir 10_place_v3.odb]
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
  if {$open_pg != 0} {error "$tag has $open_pg unconnected PG instance terminals"}
}

read_liberty $liberty
read_db $input_db
read_sdc $sdc
set_routing_layers -signal M2-M6 -clock M3-M6
foreach layer {M2 M3 M4 M5} {
  set_global_routing_layer_adjustment $layer 0.20
}
set_global_routing_layer_adjustment M6 0.10
set_wire_rc -signal -layer M3
set_wire_rc -clock -layer M5

clock_tree_synthesis -buf_list {CKBD2 CKBD4 CKBD8} -root_buf CKBD8 \
  -wire_unit 20 -obstruction_aware -apply_ndr
detailed_placement -disallow_one_site_gaps
global_connect
assert_all_pg_iterms_connected CTS
check_placement -verbose -disallow_one_site_gaps
set_propagated_clock [all_clocks]
estimate_parasitics -placement

foreach net {VDD VSS} {
  psm::clear_solvers
  check_power_grid -net $net \
    -error_file [file join $report_dir 20_pdn_v3_${net}_open.rpt]
}

write_db [file join $work_dir 20_cts_v3.odb]
write_def [file join $result_dir 20_cts_v3.def]
write_verilog -include_pwr_gnd [file join $result_dir 20_cts_v3.v]
write_sdc -no_timestamp [file join $result_dir 20_cts_v3.sdc]
report_cts -out_file [file join $report_dir 20_cts_v3.rpt]
puts "PDE_OPENROAD_CTS_V3_PASS"
exit
