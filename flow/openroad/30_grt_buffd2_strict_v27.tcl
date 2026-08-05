# Strict global route for the v12 CTS DB: no -allow_congestion.
#
# Passing here is the gate for starting detailed routing at all.  The lower
# layers are derated (same numbers as placement/CTS v5/v12) so the router is
# pushed onto M4-M6 instead of packing 98% of the guides into M1-M3.
# Required environment: PDE_GRT_TAG (grt_buffd2_strict_s<N>_v27) and
# PDE_GRT_SEED.

set repo_root /home/sxw/PDE/pdeMujunjie
set work_dir [file join $repo_root flow work openroad]
set result_dir [file join $repo_root flow results openroad]
set report_dir [file join $repo_root flow reports openroad]
set liberty [file join $work_dir tcbn65lpwc_openroad_impl_sta.lib]
set input_db [file join $work_dir 20_cts_buffd2_v12.odb]
set sdc [file join $repo_root flow results openroad 20_cts_buffd2_v12.sdc]

if {![info exists ::env(PDE_GRT_TAG)] || ![info exists ::env(PDE_GRT_SEED)]} {
  error "PDE_GRT_TAG and PDE_GRT_SEED are required"
}
set tag $::env(PDE_GRT_TAG)
set seed $::env(PDE_GRT_SEED)

proc assert_all_pg_iterms_connected {tag} {
  set block [ord::get_db_block]
  set open_pg 0
  foreach inst [$block getInsts] {
    foreach iterm [$inst getITerms] {
      set sig [[$iterm getMTerm] getSigType]
      if {($sig eq "POWER" || $sig eq "GROUND") && [$iterm getNet] == "NULL"} {
        incr open_pg
      }
    }
  }
  puts "PDE_${tag}_UNCONNECTED_PG_ITERMS=$open_pg"
  if {$open_pg != 0} {error "$tag has $open_pg unconnected PG terminals"}
}

read_liberty $liberty
read_db $input_db
read_sdc $sdc
set_thread_count 8
set_propagated_clock [all_clocks]
set_routing_layers -signal M2-M6 -clock M3-M6
set_global_routing_layer_adjustment M2 0.50
set_global_routing_layer_adjustment M3 0.40
set_global_routing_layer_adjustment M4 0.20
set_global_routing_layer_adjustment M5 0.20
set_global_routing_layer_adjustment M6 0.10
set_wire_rc -signal -layer M3
set_wire_rc -clock -layer M5
global_connect
assert_all_pg_iterms_connected PRE_GRT
check_placement -verbose -disallow_one_site_gaps

foreach net {VDD VSS} {
  psm::clear_solvers
  check_power_grid -net $net \
    -error_file [file join $report_dir 30_${tag}_pre_${net}_open.rpt]
}

set block [ord::get_db_block]
set guarded 0
foreach net [$block getNets] {
  set sig [$net getSigType]
  set pins [expr {[llength [$net getITerms]] + [llength [$net getBTerms]]}]
  if {![$net isSpecial] && $pins == 0 && ($sig eq "POWER" || $sig eq "GROUND")} {
    $net setSpecial
    incr guarded
  }
}
puts "PDE_${tag}_GUARDED_ZERO_SUPPLY=$guarded"
if {$guarded != 203} {error "Expected 203 zero-terminal supply nets"}

set_global_routing_random -seed $seed
global_route -guide_file [file join $result_dir 30_${tag}.guide] \
  -congestion_iterations 100 -congestion_report_iter_step 10 \
  -critical_nets_percentage 0 \
  -congestion_report_file [file join $report_dir 30_${tag}_congestion.rpt]

estimate_parasitics -global_routing
report_checks -path_delay max -fields {slew cap input_pins nets fanout} \
  > [file join $report_dir 30_${tag}_timing.rpt]
global_connect
assert_all_pg_iterms_connected POST_GRT
foreach net {VDD VSS} {
  psm::clear_solvers
  check_power_grid -net $net \
    -error_file [file join $report_dir 30_${tag}_${net}_open.rpt]
}

write_db [file join $work_dir 30_${tag}.odb]
write_def [file join $result_dir 30_${tag}.def]
write_sdc -no_timestamp [file join $result_dir 30_${tag}.sdc]
write_guides [file join $result_dir 30_${tag}_checkpoint.guide]
puts "PDE_GRT_STRICT_PASS tag=$tag seed=$seed"
exit
