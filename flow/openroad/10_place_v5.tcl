# Placement v5: lower density plus DRV repair before CTS.
#
# v4 at density 0.40 produced local clumps, and the unbuffered 16227-sink
# rst_n net forced GRT into allow_congestion (98.4% of guides on M1-M3) and
# left DRT stuck near 284k violations.  v5 lowers density to 0.34, derates
# the lower routing layers so the congestion estimate matches the strict GRT
# that follows, and runs repair_design under an explicit max_fanout so the
# reset (a false path, invisible to timing) is finally buffered into a tree.

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
set_thread_count 16
set_routing_layers -signal M2-M6 -clock M3-M6
set_global_routing_layer_adjustment M2 0.50
set_global_routing_layer_adjustment M3 0.40
set_global_routing_layer_adjustment M4 0.20
set_global_routing_layer_adjustment M5 0.20
set_global_routing_layer_adjustment M6 0.10
set_wire_rc -signal -layer M3
set_wire_rc -clock -layer M5

global_placement -density 0.34 -disable_timing_driven -routability_driven \
  -routability_max_density 0.60

# CKBD8 has two unroutable pin-access patterns in this LEF (see 20_cts v11);
# keep every clock-buffer family out of the datapath repair as well.
set_dont_use {CKBD* CKND* CKMUX* CKXOR* CKAN*}
set_max_fanout 32 [current_design]
estimate_parasitics -placement

set block [ord::get_db_block]
set pre_insts [llength [$block getInsts]]
repair_design
set post_insts [llength [$block getInsts]]
puts "PDE_PLACE_V5_REPAIR_INSERTED=[expr {$post_insts - $pre_insts}]"

set rst_net [$block findNet rst_n]
if {$rst_net ne "NULL" && $rst_net ne ""} {
  puts "PDE_PLACE_V5_RSTN_FANOUT=[llength [$rst_net getITerms]]"
}

detailed_placement -disallow_one_site_gaps
check_placement -verbose -disallow_one_site_gaps \
  -report_file_name [file join $report_dir 10_check_placement_v5.rpt]

foreach net {VDD VSS} {
  psm::clear_solvers
  check_power_grid -net $net \
    -error_file [file join $report_dir 10_pdn_v5_${net}_open.rpt]
}

write_db [file join $work_dir 10_place_v5.odb]
write_def [file join $result_dir 10_place_v5.def]
report_design_area
puts "PDE_OPENROAD_PLACE_V5_PASS"
exit
