# Placement rebuilt from the connectivity-qualified v5 power grid.

set repo_root /home/sxw/PDE/pdeMujunjie
set work_dir [file join $repo_root flow work openroad]
set result_dir [file join $repo_root flow results openroad]
set report_dir [file join $repo_root flow reports openroad]
set liberty [file join $work_dir tcbn65lpwc_openroad_impl_sta.lib]
set input_db [file join $work_dir 00_floorplan_pdn_v6.odb]
set sdc [file join $repo_root flow openroad pde_chip_top_safe_v2.sdc]

read_liberty $liberty
read_db $input_db
read_sdc $sdc
set_routing_layers -signal M2-M6 -clock M3-M6
foreach layer {M2 M3 M4 M5} {
  set_global_routing_layer_adjustment $layer 0.10
}
set_global_routing_layer_adjustment M6 0.05
set_wire_rc -signal -layer M3
set_wire_rc -clock -layer M5

global_placement -density 0.40 -disable_timing_driven -routability_driven \
  -routability_max_density 0.60
detailed_placement -disallow_one_site_gaps
check_placement -verbose -disallow_one_site_gaps \
  -report_file_name [file join $report_dir 10_check_placement_v4.rpt]

foreach net {VDD VSS} {
  psm::clear_solvers
  check_power_grid -net $net \
    -error_file [file join $report_dir 10_pdn_v4_${net}_open.rpt]
}

write_db [file join $work_dir 10_place_v4.odb]
write_def [file join $result_dir 10_place_v4.def]
report_design_area
puts "PDE_OPENROAD_PLACE_V4_PASS"
exit

