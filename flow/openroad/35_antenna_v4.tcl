# Global-route antenna repair.  Filler cells must not be present at this stage.

set repo_root /home/sxw/PDE/pdeMujunjie
set work_dir [file join $repo_root flow work openroad]
set result_dir [file join $repo_root flow results openroad]
set report_dir [file join $repo_root flow reports openroad]
set liberty [file join $work_dir tcbn65lpwc_openroad_impl_sta.lib]
set input_db [file join $work_dir 30_global_route_v4.odb]
set sdc [file join $repo_root flow openroad pde_chip_top_safe_v2.sdc]

read_liberty $liberty
read_db $input_db
read_sdc $sdc
set_thread_count 4
set_propagated_clock [all_clocks]
set_routing_layers -signal M2-M6 -clock M3-M6
set_wire_rc -signal -layer M3
set_wire_rc -clock -layer M5

repair_antennas ANTENNA -iterations 3 -ratio_margin 20
check_placement -verbose -disallow_one_site_gaps

# Save the recoverable design before optional reports.
write_db [file join $work_dir 35_antenna_v4.odb]
write_def [file join $result_dir 35_antenna_v4.def]
write_sdc -no_timestamp [file join $result_dir 35_antenna_v4.sdc]
check_antennas -report_violating_nets \
  -report_file [file join $report_dir 35_antenna_v4.rpt]
puts "PDE_OPENROAD_ANTENNA_V4_PASS"
exit
