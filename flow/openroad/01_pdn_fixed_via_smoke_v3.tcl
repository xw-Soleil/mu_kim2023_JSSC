# Fixed-via PDN connectivity smoke on the existing floorplan checkpoint.

set repo_root /home/sxw/PDE/pdeMujunjie
set work_dir [file join $repo_root flow work openroad]
set result_dir [file join $repo_root flow results openroad]
set report_dir [file join $repo_root flow reports openroad]

read_liberty [file join $work_dir tcbn65lpwc_openroad_impl_sta.lib]
read_db [file join $work_dir 00_floorplan_pdn_v4.odb]

set block [ord::get_db_block]
foreach net_name {VDD VSS} {
  set pg_net [$block findNet $net_name]
  if {$pg_net == "NULL"} {error "Missing top-level PG net $net_name"}
  foreach swire [$pg_net getSWires] {odb::dbSWire_destroy $swire}
}

add_global_connection -net VDD -inst_pattern {.*} -pin_pattern {^VDD$} -power
add_global_connection -net VSS -inst_pattern {.*} -pin_pattern {^VSS$} -ground
global_connect
set_voltage_domain -name Core -power VDD -ground VSS
define_pdn_grid -name core_grid_fixed -voltage_domains {Core} -starts_with POWER
add_pdn_ring -grid core_grid_fixed -layers {M4 M5} -widths {1.0 1.0} \
  -spacings {0.8 0.8} -core_offsets {3.0 3.0}
add_pdn_stripe -grid core_grid_fixed -layer M1 -followpins -width 0.10
add_pdn_stripe -grid core_grid_fixed -layer M2 -width 0.40 -spacing 0.40 \
  -pitch 20.0 -offset 5.0 -starts_with POWER -snap_to_grid
add_pdn_stripe -grid core_grid_fixed -layer M3 -width 0.40 -spacing 0.40 \
  -pitch 20.0 -offset 5.0 -starts_with POWER -snap_to_grid
add_pdn_stripe -grid core_grid_fixed -layer M4 -width 0.60 -spacing 0.60 \
  -pitch 40.0 -offset 10.0 -starts_with POWER -snap_to_grid
add_pdn_stripe -grid core_grid_fixed -layer M5 -width 0.80 -spacing 0.80 \
  -pitch 40.0 -offset 10.0 -starts_with POWER -snap_to_grid
add_pdn_connect -grid core_grid_fixed -layers {M1 M2} \
  -fixed_vias {VIA12_2cut_E}
add_pdn_connect -grid core_grid_fixed -layers {M2 M3}
add_pdn_connect -grid core_grid_fixed -layers {M3 M4}
add_pdn_connect -grid core_grid_fixed -layers {M4 M5}
pdngen -failed_via_report [file join $report_dir 01_pdn_fixed_v3_failed.rpt]

set failures 0
foreach net {VDD VSS} {
  psm::clear_solvers
  set rc [catch {check_power_grid -net $net -floorplanning \
    -error_file [file join $report_dir 01_pdn_fixed_v3_${net}_open.rpt]} msg]
  puts "PDE_PDN_FIXED_V3_SMOKE net=$net rc=$rc message={$msg}"
  if {$rc != 0} {incr failures}
}

write_db [file join $work_dir 01_pdn_fixed_via_smoke_v3.odb]
write_def [file join $result_dir 01_pdn_fixed_via_smoke_v3.def]
if {$failures != 0} {error "Fixed-via PDN connectivity failed for $failures nets"}
puts "PDE_PDN_FIXED_VIA_V3_SMOKE_PASS"
exit
