# Connectivity-qualified floorplan and M1-M5 power grid.
# The upper mesh explicitly reaches the core ring; otherwise the ring and
# internal grid are geometrically present but electrically disconnected.

set repo_root /home/sxw/PDE/pdeMujunjie
set work_dir [file join $repo_root flow work openroad]
set result_dir [file join $repo_root flow results openroad]
set report_dir [file join $repo_root flow reports openroad]
file mkdir $work_dir
file mkdir $result_dir
file mkdir $report_dir

set lef /ssd0/PDKs/TSMC65nm/STDCELL/std/STD_Cell/tcbn65lp_200b/Back_End/lef/tcbn65lp_200a/lef/tcbn65lp_6lmT1.lef
set liberty [file join $work_dir tcbn65lpwc_openroad_impl_sta.lib]
set netlist [file join $repo_root flow results dc pde_chip_top_safe.v]
set sdc [file join $repo_root flow openroad pde_chip_top_safe_v2.sdc]

read_liberty $liberty
read_lef $lef
read_verilog $netlist
link_design pde_chip_top_safe
read_sdc $sdc

initialize_floorplan -utilization 30 -aspect_ratio 1.0 \
  -core_space {10.0 10.0 10.0 10.0} -site core
make_tracks
place_pins -hor_layers {M3} -ver_layers {M4} -random_seed 65 \
  -corner_avoidance 10.0 -min_distance 0.8

set_routing_layers -signal M2-M6 -clock M3-M6
foreach layer {M2 M3 M4 M5} {
  set_global_routing_layer_adjustment $layer 0.20
}
set_global_routing_layer_adjustment M6 0.10

add_global_connection -net VDD -inst_pattern {.*} -pin_pattern {^VDD$} -power
add_global_connection -net VSS -inst_pattern {.*} -pin_pattern {^VSS$} -ground
global_connect
set_voltage_domain -name CORE -power VDD -ground VSS
define_pdn_grid -name core_grid -voltage_domains {CORE} -starts_with POWER
add_pdn_ring -grid core_grid -layers {M4 M5} -widths {1.0 1.0} \
  -spacings {0.8 0.8} -core_offsets {3.0 3.0}
add_pdn_stripe -grid core_grid -layer M1 -followpins -width 0.10
add_pdn_stripe -grid core_grid -layer M2 -width 0.40 -spacing 0.40 \
  -pitch 20.0 -offset 5.0 -starts_with POWER -snap_to_grid
add_pdn_stripe -grid core_grid -layer M3 -width 0.40 -spacing 0.40 \
  -pitch 20.0 -offset 5.0 -starts_with POWER -snap_to_grid
add_pdn_stripe -grid core_grid -layer M4 -width 0.60 -spacing 0.60 \
  -pitch 40.0 -offset 10.0 -starts_with POWER -snap_to_grid \
  -extend_to_core_ring
add_pdn_stripe -grid core_grid -layer M5 -width 0.80 -spacing 0.80 \
  -pitch 40.0 -offset 10.0 -starts_with POWER -snap_to_grid \
  -extend_to_core_ring
add_pdn_connect -grid core_grid -layers {M1 M2}
add_pdn_connect -grid core_grid -layers {M2 M3}
add_pdn_connect -grid core_grid -layers {M3 M4}
add_pdn_connect -grid core_grid -layers {M4 M5}
pdngen -failed_via_report [file join $report_dir 00_pdn_v6_failed_vias.rpt]

foreach net {VDD VSS} {
  psm::clear_solvers
  check_power_grid -net $net -floorplanning \
    -error_file [file join $report_dir 00_pdn_v6_${net}_open.rpt]
}

report_design_area
write_db [file join $work_dir 00_floorplan_pdn_v6.odb]
write_def [file join $result_dir 00_floorplan_pdn_v6.def]
puts "PDE_OPENROAD_FLOORPLAN_PDN_V6_PASS"
exit

