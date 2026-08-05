# Corrected-capacity routability pass.  Timing-critical net reweighting is
# disabled here because it rebuilds parasitics for all 117k nets every third
# overflow iteration in this release; enable it only after zero overflow.

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
set_propagated_clock [all_clocks]
set_routing_layers -signal M2-M6 -clock M3-M6
foreach layer {M2 M3 M4 M5} {
  set_global_routing_layer_adjustment $layer 0.25
}
set_global_routing_layer_adjustment M6 0.15
set_wire_rc -signal -layer M3
set_wire_rc -clock -layer M5

global_route -guide_file [file join $result_dir 30_global_route_v3.guide] \
  -congestion_iterations 50 -congestion_report_iter_step 10 \
  -critical_nets_percentage 0 -allow_congestion \
  -congestion_report_file [file join $report_dir 30_congestion_v3.rpt]
estimate_parasitics -global_routing
write_db [file join $work_dir 30_global_route_v3.odb]
write_def [file join $result_dir 30_global_route_v3.def]
write_spef [file join $result_dir 30_global_route_v3_estimated.spef]
puts "PDE_OPENROAD_GLOBAL_ROUTE_PASS"
exit
