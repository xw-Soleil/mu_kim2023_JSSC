# Pin access, detailed routing, and physical-only filler insertion.

set repo_root /home/sxw/PDE/pdeMujunjie
set work_dir [file join $repo_root flow work openroad]
set result_dir [file join $repo_root flow results openroad]
set report_dir [file join $repo_root flow reports openroad]
set liberty [file join $work_dir tcbn65lpwc_openroad_impl_sta.lib]
set input_db [file join $work_dir 35_antenna_v4.odb]
set sdc [file join $repo_root flow results openroad 35_antenna_v4.sdc]

read_liberty $liberty
read_db $input_db
read_sdc $sdc
set_thread_count 4
set_propagated_clock [all_clocks]
set_routing_layers -signal M2-M6 -clock M3-M6
set_wire_rc -signal -layer M3
set_wire_rc -clock -layer M5

pin_access -bottom_routing_layer M1 -top_routing_layer M6 \
  -min_access_points 1
detailed_route \
  -output_drc [file join $report_dir 40_route_v4_drc.rpt] \
  -output_guide_coverage [file join $report_dir 40_route_v4_guide_coverage.rpt] \
  -drc_report_iter_step 5 -droute_end_iter 64 \
  -bottom_routing_layer M1 -top_routing_layer M6 \
  -no_pin_access -save_guide_updates -verbose 1

# Preserve a routed checkpoint before inserting physical-only filler cells.
write_db [file join $work_dir 40_route_v4_prefill.odb]
write_def [file join $result_dir 40_route_v4_prefill.def]
check_antennas -report_violating_nets \
  -report_file [file join $report_dir 40_route_v4_antennas.rpt]

filler_placement -prefix PDE_FILL \
  {FILL64 FILL32 FILL16 FILL8 FILL4 FILL2 FILL1}
check_placement -verbose -disallow_one_site_gaps

write_db [file join $work_dir 40_route.odb]
write_def [file join $result_dir 40_route.def]
write_verilog -include_pwr_gnd [file join $result_dir 40_route.v]
write_sdc -no_timestamp [file join $result_dir 40_route.sdc]
puts "PDE_OPENROAD_DETAILED_ROUTE_V4_PASS"
exit
