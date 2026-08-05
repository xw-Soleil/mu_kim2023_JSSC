set repo_root /home/sxw/PDE/pdeMujunjie
set report_dir [file join $repo_root flow reports openroad]
read_liberty [file join $repo_root flow work openroad tcbn65lpwc_openroad_impl_sta.lib]
read_db [file join $repo_root flow work openroad 20_cts.odb]

proc pde_check_pg {net mode report_path} {
  psm::clear_solvers
  if {$mode eq "floorplan"} {
    set rc [catch {check_power_grid -net $net -floorplanning -error_file $report_path} msg]
  } else {
    set rc [catch {check_power_grid -net $net -error_file $report_path} msg]
  }
  puts "PDE_PDN_CHECK net=$net mode=$mode rc=$rc message={$msg}"
}

pde_check_pg VDD floorplan [file join $report_dir pdn_VDD_floorplan_open.rpt]
pde_check_pg VSS floorplan [file join $report_dir pdn_VSS_floorplan_open.rpt]
pde_check_pg VDD full [file join $report_dir pdn_VDD_full_open.rpt]
pde_check_pg VSS full [file join $report_dir pdn_VSS_full_open.rpt]
puts "PDE_PDN_CURRENT_CHECK_COMPLETE"
exit
