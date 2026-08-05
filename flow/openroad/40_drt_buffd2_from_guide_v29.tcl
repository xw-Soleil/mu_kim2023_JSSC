# Physical-only detailed route from stable BUFFD2 CTS plus a matching GRT guide.  Zero DRT
# violations, full connectivity, zero antenna violations and PDN connectivity
# are hard gates.  Fillers are followed by a second DRT gate so their M1
# obstructions cannot invalidate a pre-filler route.

set repo_root /home/sxw/PDE/pdeMujunjie
set work_dir [file join $repo_root flow work openroad]
set result_dir [file join $repo_root flow results openroad]
set report_dir [file join $repo_root flow reports openroad]
set liberty [file join $work_dir tcbn65lpwc_openroad_impl_sta.lib]
if {![info exists ::env(PDE_DRT_INPUT_TAG)] || ![info exists ::env(PDE_DRT_TAG)]} {
  error "PDE_DRT_INPUT_TAG and PDE_DRT_TAG are required"
}
set input_tag $::env(PDE_DRT_INPUT_TAG)
set tag $::env(PDE_DRT_TAG)
if {![regexp {^grt_buffd2_s([1-3])_v26$} $input_tag -> guide_seed]} {
  error "Unsafe or unsupported PDE_DRT_INPUT_TAG: $input_tag"
}
if {![regexp {^drt_buffd2_s([1-3])_v29$} $tag -> route_seed]} {
  error "Unsafe or unsupported PDE_DRT_TAG: $tag"
}
if {$guide_seed ne $route_seed} {
  error "Guide seed $guide_seed does not match route seed $route_seed"
}
set input_db [file join $work_dir 20_cts_buffd2_v11.odb]
set sdc [file join $result_dir 20_cts_buffd2_v11.sdc]
set guide [file join $result_dir 30_${input_tag}.guide]

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

proc run_drt {tag report_dir work_dir result_dir} {
  set route_rc [catch {
    detailed_route \
      -output_maze [file join $report_dir ${tag}.maze.log] \
      -output_drc [file join $report_dir ${tag}_drc.rpt] \
      -output_cmap [file join $report_dir ${tag}.cmap] \
      -output_guide_coverage [file join $report_dir ${tag}_guide_coverage.rpt] \
      -drc_report_iter_step 5 -droute_end_iter 64 \
      -bottom_routing_layer M1 -top_routing_layer M6 \
      -save_guide_updates -verbose 1
  } route_msg]
  # Preserve the original DRT error even if a corrupted failure-state
  # database cannot be serialized for diagnostics.
  catch {write_db [file join $work_dir ${tag}_diagnostic.odb]}
  catch {write_def -version 5.8 [file join $result_dir ${tag}_diagnostic.def]}
  if {$route_rc != 0} {error "$tag detailed_route failed: $route_msg"}
  set drvs [detailed_route_num_drvs]
  puts "PDE_DRT_${tag}_DRVS=$drvs"
  if {$drvs != 0} {error "$tag left $drvs detailed-route violations"}
  if {![design_is_routed -verbose]} {error "$tag is not fully routed"}
}

read_liberty $liberty
read_db $input_db
read_sdc $sdc
set_thread_count 8
set_propagated_clock [all_clocks]
set_routing_layers -signal M2-M6 -clock M3-M6
set_wire_rc -signal -layer M3
set_wire_rc -clock -layer M5
global_connect
assert_all_pg_iterms_connected PRE_DRT
check_placement -verbose -disallow_one_site_gaps

set block [ord::get_db_block]
set guarded 0
set guarded_supply_nets {}
foreach net [$block getNets] {
  set sig [$net getSigType]
  set pins [expr {[llength [$net getITerms]] + [llength [$net getBTerms]]}]
  if {![$net isSpecial] && $pins == 0 && ($sig eq "POWER" || $sig eq "GROUND")} {
    $net setSpecial
    lappend guarded_supply_nets [$net getName]
    incr guarded
  }
}
puts "PDE_${tag}_ROUTING_GUARDED_SPECIAL_COUNT=$guarded"
if {$guarded != 203} {error "Expected to guard 203 zero-terminal supply nets"}
if {![file exists $guide] || [file size $guide] == 0} {
  error "Missing non-empty global-route guide: $guide"
}
read_guides $guide

# Re-run the proven pin-access hard gate against the imported guide database.
pin_access -bottom_routing_layer M1 -top_routing_layer M6 -verbose 1
run_drt ${tag}_initial $report_dir $work_dir $result_dir

write_db [file join $work_dir 40_${tag}_routed_initial.odb]
write_def -version 5.8 [file join $result_dir 40_${tag}_routed_initial.def]
set antenna_violations [check_antennas \
  -report_file [file join $report_dir 40_${tag}_initial_antennas.rpt]]
puts "PDE_${tag}_POSTDR_ANT_INITIAL=$antenna_violations"

set antenna_round 0
while {$antenna_violations > 0 && $antenna_round < 3} {
  incr antenna_round
  set added [repair_antennas ANTENNA -iterations 1 -ratio_margin 20]
  puts "PDE_${tag}_ANT_ROUND_${antenna_round}_DIODES=$added"
  # repair_antennas performs its own legalization/incremental route update.
  # A second full-design padded placement here can invalidate existing wires.
  set_placement_padding -global -left 0 -right 0
  global_connect
  assert_all_pg_iterms_connected ${tag}_POSTANT_${antenna_round}
  check_placement -verbose -disallow_one_site_gaps
  run_drt ${tag}_postant_${antenna_round} $report_dir $work_dir $result_dir
  set antenna_violations [check_antennas \
    -report_file [file join $report_dir 40_${tag}_postant_${antenna_round}.rpt]]
  puts "PDE_${tag}_ANT_ROUND_${antenna_round}_VIOLATIONS=$antenna_violations"
}
if {$antenna_violations != 0} {
  error "Post-DR antenna closure failed with $antenna_violations violating nets"
}

foreach net {VDD VSS} {
  psm::clear_solvers
  check_power_grid -net $net \
    -error_file [file join $report_dir 40_${tag}_prefill_${net}_open.rpt]
}
write_db [file join $work_dir 40_${tag}_prefill_antclosed.odb]
write_def -version 5.8 [file join $result_dir 40_${tag}_prefill_antclosed.def]

# Fill only after antenna closure, then rerun DRT so filler obstructions are
# included in the final zero-DRV decision.  Padding must be cleared before
# fillers are inserted because filler_placement uses physical cell gaps.
set_placement_padding -global -left 0 -right 0
set filler_masters {FILL64 FILL32 FILL16 FILL8 FILL4 FILL2 FILL1}
filler_placement -prefix PDE_FILL_ -verbose $filler_masters
global_connect
assert_all_pg_iterms_connected ${tag}_POSTFILL
check_placement -verbose -disallow_one_site_gaps \
  -report_file_name [file join $report_dir 45_${tag}_placement.json]
run_drt ${tag}_postfill $report_dir $work_dir $result_dir
set final_antennas [check_antennas \
  -report_file [file join $report_dir 45_${tag}_antennas.rpt]]
puts "PDE_${tag}_FINAL_ANTENNA_VIOLATIONS=$final_antennas"
if {$final_antennas != 0} {error "Final filled route has antenna violations"}

foreach net {VDD VSS} {
  psm::clear_solvers
  check_power_grid -net $net \
    -error_file [file join $report_dir 45_${tag}_${net}_open.rpt]
}

set unexpected_special 0
foreach net [$block getNets] {
  set sig [$net getSigType]
  set pins [expr {[llength [$net getITerms]] + [llength [$net getBTerms]]}]
  if {[$net isSpecial] && $pins == 0 && ($sig eq "POWER" || $sig eq "GROUND") &&
      [lsearch -exact $guarded_supply_nets [$net getName]] < 0} {
    puts "PDE_${tag}_UNEXPECTED_SPECIAL_ZERO_SUPPLY=[$net getName]"
    incr unexpected_special
  }
}
if {$unexpected_special != 0} {
  error "Found $unexpected_special zero-terminal supply nets outside guarded set"
}
set restored 0
foreach net_name $guarded_supply_nets {
  set net [$block findNet $net_name]
  if {$net == "NULL"} {error "Guarded supply net disappeared: $net_name"}
  set sig [$net getSigType]
  set pins [expr {[llength [$net getITerms]] + [llength [$net getBTerms]]}]
  if {![$net isSpecial] || $pins != 0 || !($sig eq "POWER" || $sig eq "GROUND")} {
    error "Guarded supply net changed identity/state: $net_name"
  }
  $net clearSpecial
  incr restored
}
puts "PDE_${tag}_RESTORED_ZERO_SUPPLY=$restored"
if {$restored != 203 || $restored != [llength $guarded_supply_nets]} {
  error "Expected to restore the exact 203 guarded zero-terminal supply nets"
}

report_design_area

set final_odb [file join $work_dir 45_${tag}_final.odb]
set final_def [file join $result_dir 45_${tag}_final.def]
set final_lvs [file join $result_dir 45_${tag}_final_lvs.v]
set final_nofill [file join $result_dir 45_${tag}_final_nofill.v]
set final_sdc [file join $result_dir 45_${tag}_final.sdc]
write_db $final_odb
write_def -version 5.8 $final_def
write_verilog -sort -include_pwr_gnd $final_lvs
write_verilog -sort -include_pwr_gnd -remove_cells $filler_masters $final_nofill
write_sdc -no_timestamp $final_sdc

# Publish an atomic hard-pass manifest only after every final artifact exists.
set pass_manifest [file join $result_dir 45_${tag}_final.pass]
set pass_tmp ${pass_manifest}.tmp
set def_sha [lindex [exec /usr/bin/sha256sum $final_def] 0]
set odb_sha [lindex [exec /usr/bin/sha256sum $final_odb] 0]
set guide_sha [lindex [exec /usr/bin/sha256sum $guide] 0]
set pass_fh [open $pass_tmp w]
puts $pass_fh "PDE_OPENROAD_PHYSICAL_HARD_PASS"
puts $pass_fh "tag=$tag"
puts $pass_fh "input_tag=$input_tag"
puts $pass_fh "def=$final_def"
puts $pass_fh "def_sha256=$def_sha"
puts $pass_fh "odb=$final_odb"
puts $pass_fh "odb_sha256=$odb_sha"
puts $pass_fh "guide=$guide"
puts $pass_fh "guide_sha256=$guide_sha"
close $pass_fh
file rename -force $pass_tmp $pass_manifest
puts "PDE_OPENROAD_PHYSICAL_HARD_PASS tag=$tag manifest=$pass_manifest"
exit




