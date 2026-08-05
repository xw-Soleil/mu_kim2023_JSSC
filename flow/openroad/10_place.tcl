# Congestion-driven global placement followed by row legalization.

set repo_root /home/sxw/PDE/pdeMujunjie
set work_dir [file join $repo_root flow work openroad]
set result_dir [file join $repo_root flow results openroad]
set report_dir [file join $repo_root flow reports openroad]
set liberty [file join $work_dir tcbn65lpwc_openroad_impl_sta.lib]
set input_db [file join $work_dir 00_floorplan_pdn_v3.odb]
set sdc [file join $repo_root flow openroad pde_chip_top_safe_v2.sdc]

read_liberty $liberty
read_db $input_db
read_sdc $sdc

set_routing_layers -signal M2-M5 -clock M3-M5
foreach layer {M2 M3 M4 M5} {
  set_global_routing_layer_adjustment $layer 0.65
}
set_wire_rc -signal -layer M3
set_wire_rc -clock -layer M5

# 55% target density leaves whitespace beyond the 45% raw utilization while
# letting the routability engine inflate locally congested bins.
global_placement -density 0.55 -disable_timing_driven -routability_driven \
  -routability_use_grt -routability_max_density 0.75
detailed_placement -disallow_one_site_gaps
check_placement -verbose -disallow_one_site_gaps \
  -report_file_name [file join $report_dir 10_check_placement.rpt]

estimate_parasitics -placement
report_design_area
report_wns -digits 4
report_tns -digits 4
report_checks -path_delay max -group_count 10 -format full_clock_expanded \
  > [file join $report_dir 10_setup_placeholder.rpt]
report_checks -path_delay min -group_count 10 -format full_clock_expanded \
  > [file join $report_dir 10_hold_placeholder.rpt]

write_db [file join $work_dir 10_place.odb]
write_def [file join $result_dir 10_place.def]
puts "PDE_OPENROAD_PLACE_PASS"
exit
