# Clock-tree synthesis for 23,905 sequential sinks using dedicated tcbn65lp
# clock buffers.  Synthetic Liberty delays are implementation-only.

set repo_root /home/sxw/PDE/pdeMujunjie
set work_dir [file join $repo_root flow work openroad]
set result_dir [file join $repo_root flow results openroad]
set report_dir [file join $repo_root flow reports openroad]
set liberty [file join $work_dir tcbn65lpwc_openroad_impl_sta.lib]
set input_db [file join $work_dir 10_place_v2.odb]
set sdc [file join $repo_root flow openroad pde_chip_top_safe_v2.sdc]

read_liberty $liberty
read_db $input_db
read_sdc $sdc
set_routing_layers -signal M2-M6 -clock M3-M6
foreach layer {M2 M3 M4 M5} {
  set_global_routing_layer_adjustment $layer 0.65
}
set_global_routing_layer_adjustment M6 0.75
set_wire_rc -signal -layer M3
set_wire_rc -clock -layer M5

clock_tree_synthesis -buf_list {CKBD2 CKBD4 CKBD8} -root_buf CKBD8 \
  -wire_unit 20 -obstruction_aware -apply_ndr
detailed_placement -disallow_one_site_gaps
set_propagated_clock [all_clocks]
estimate_parasitics -placement

write_db [file join $work_dir 20_cts.odb]
write_def [file join $result_dir 20_cts.def]
write_verilog -include_pwr_gnd [file join $result_dir 20_cts.v]
write_sdc -no_timestamp [file join $result_dir 20_cts.sdc]
report_cts -out_file [file join $report_dir 20_cts.rpt]
check_placement -verbose -disallow_one_site_gaps
puts "PDE_OPENROAD_CTS_PASS"
exit
