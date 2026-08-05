# Global route and antenna repair intentionally run in the same OpenROAD
# process.  In v2.0-17598, reloading a routed ODB before repair_antennas loses
# transient GRT state and can crash in grt::Net::isLocal().

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
set_routing_layers -signal M2-M6 -clock M3-M6
foreach layer {M2 M3 M4 M5} {
  set_global_routing_layer_adjustment $layer 0.20
}
set_global_routing_layer_adjustment M6 0.10
set_wire_rc -signal -layer M3
set_wire_rc -clock -layer M5

global_route -guide_file [file join $result_dir 30_route_antenna_v5.guide] \
  -congestion_iterations 100 -critical_nets_percentage 0 \
  -allow_congestion

# Filler cells must not be present while antenna diodes are inserted.
repair_antennas ANTENNA -iterations 3 -ratio_margin 20
check_placement -verbose -disallow_one_site_gaps
estimate_parasitics -global_routing

# Save before optional reports so this checkpoint survives report failures.
write_db [file join $work_dir 35_antenna_v5.odb]
write_def [file join $result_dir 35_antenna_v5.def]
write_sdc -no_timestamp [file join $result_dir 35_antenna_v5.sdc]
check_antennas -report_violating_nets \
  -report_file [file join $report_dir 35_antenna_v5.rpt]
puts "PDE_OPENROAD_ROUTE_ANTENNA_V5_PASS"
exit
