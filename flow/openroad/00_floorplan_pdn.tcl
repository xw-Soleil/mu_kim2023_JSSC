# OpenROAD floorplan, I/O placement and provisional core power grid for the
# 20x20 pde_chip_top_safe implementation.

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

foreach required [list $lef $liberty $netlist $sdc] {
  if {![file exists $required]} {
    error "Missing required input: $required"
  }
}

read_liberty $liberty
read_lef $lef
read_verilog $netlist
link_design pde_chip_top_safe
read_sdc $sdc

# 45% initial utilization leaves room for a large clock tree, legalization,
# diode insertion and the dense PE-array routing.  OpenROAD aligns the core to
# the 0.2 um x 1.8 um foundry site.
initialize_floorplan -utilization 45 -aspect_ratio 1.0 \
  -core_space {10.0 10.0 10.0 10.0} -site core
make_tracks

# The chip top has only 55 logical signal pins.  Keep signal I/O on M3/M4 so
# M5/M6 can carry the provisional core grid.
place_pins -hor_layers {M3} -ver_layers {M4} -random_seed 65 \
  -corner_avoidance 10.0 -min_distance 0.8

set_routing_layers -signal M2-M5 -clock M3-M5
set_global_routing_layer_adjustment M2 0.70
set_global_routing_layer_adjustment M3 0.70
set_global_routing_layer_adjustment M4 0.70
set_global_routing_layer_adjustment M5 0.70

# Connect every standard-cell PG pin to explicit special nets even though this
# block-level top intentionally has no pad-ring ports yet.
add_global_connection -net VDD -inst_pattern {.*} -pin_pattern {^VDD$} -power
add_global_connection -net VSS -inst_pattern {.*} -pin_pattern {^VSS$} -ground
global_connect

set_voltage_domain -name CORE -power VDD -ground VSS
define_pdn_grid -name core_grid -voltage_domains {CORE} -starts_with POWER
add_pdn_ring -grid core_grid -layers {M5 M6} -widths {2.0 2.0} \
  -spacings {1.0 1.0} -core_offsets {3.0 3.0}
add_pdn_stripe -grid core_grid -layer M1 -followpins -width 0.10 \
  -starts_with POWER
add_pdn_stripe -grid core_grid -layer M5 -width 0.80 -spacing 0.80 \
  -pitch 40.0 -offset 10.0 -starts_with POWER -snap_to_grid
add_pdn_stripe -grid core_grid -layer M6 -width 1.60 -spacing 1.60 \
  -pitch 40.0 -offset 10.0 -starts_with POWER -snap_to_grid
add_pdn_connect -grid core_grid -layers {M1 M6}
add_pdn_connect -grid core_grid -layers {M5 M6}
pdngen -failed_via_report [file join $report_dir 00_pdn_failed_vias.rpt]

report_design_area
report_floating_nets > [file join $report_dir 00_floating_nets.rpt]
write_db [file join $work_dir 00_floorplan_pdn.odb]
write_def [file join $result_dir 00_floorplan_pdn.def]

puts "PDE_OPENROAD_FLOORPLAN_PDN_PASS"
exit
