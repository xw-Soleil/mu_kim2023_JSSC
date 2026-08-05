set repo_root /home/sxw/PDE/pdeMujunjie
set report_dir [file join $repo_root flow reports openroad]
read_liberty [file join $repo_root flow work openroad tcbn65lpwc_openroad_impl_sta.lib]
read_db [file join $repo_root flow work openroad 20_cts.odb]

psm::clear_solvers
check_power_grid -net VDD -floorplanning \
  -error_file [file join $report_dir pdn_VDD_floorplan_open.rpt]
psm::clear_solvers
check_power_grid -net VSS -floorplanning \
  -error_file [file join $report_dir pdn_VSS_floorplan_open.rpt]
psm::clear_solvers
check_power_grid -net VDD \
  -error_file [file join $report_dir pdn_VDD_full_open.rpt]
psm::clear_solvers
check_power_grid -net VSS \
  -error_file [file join $report_dir pdn_VSS_full_open.rpt]
puts "PDE_PDN_CURRENT_CHECK_COMPLETE"
exit
