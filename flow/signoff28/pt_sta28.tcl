# Post-route PrimeTime STA for the pnr28-first-clean artifacts.
# One corner per pt_shell session, selected by PDE28_PT_CORNER:
#   WC : ssg0p9vm40c NLDM + rcworst SPEF  -> setup / recovery / DRV
#        (mirrors ICC2 scenario FUNC_WC: setup+max_tran+max_cap active)
#   BC : ffg0p99vm40c NLDM + rcbest SPEF  -> hold / removal
#        (mirrors ICC2 scenario FUNC_BC: hold active)
# Analysis: OCV + CRPR, no derates. AOCV intentionally NOT enabled for this
# baseline so numbers stay comparable to ICC2 (which also ran without derate).
# [28nm AOCV hook] sbocv .aocvm tables live under
#   <pdk>/tcbn28hpcplusbwp40p140_180b/TSMCHOME/digital/Front_End/SBOCV/
# attach in a later pass via read_aocvm + set_timing_derate -aocvm.
# This script reads design data only; it writes nothing but reports.

if {![info exists ::env(PDE28_SIGNOFF_ROOT)] || $::env(PDE28_SIGNOFF_ROOT) eq ""} {
  error "PDE28_SIGNOFF_ROOT must point at the signoff work tree"
}
if {![info exists ::env(PDE28_PT_CORNER)]} {
  error "PDE28_PT_CORNER must be WC or BC"
}
set ROOT   $::env(PDE28_SIGNOFF_ROOT)
set CORNER $::env(PDE28_PT_CORNER)
# Full-chip line (pad-level top, selected by PDE_TOP): link additionally
# against the GPIO NLDM; the default keeps the core-only top byte-identical.
set TOP    pde_chip_top_safe
if {[info exists ::env(PDE_TOP)] && [string trim $::env(PDE_TOP)] ne ""} {
  set TOP $::env(PDE_TOP)
}
set IS_CHIP [expr {$TOP eq "pde_chip_pads"}]
set INPUT  $ROOT/inputs
set LIBDIR $ROOT/lib
set RPT    $ROOT/pt/reports
file mkdir $RPT

set EXTRA_DBS {}
switch -exact -- $CORNER {
  WC { set DB   tcbn28hpcplusbwp40p140ssg0p9vm40c.db
       set SPEF $INPUT/$TOP.WC.spef.RC_WORST_-40.spef
       set AOCVM_FILE tcbn28hpcplusbwp40p140ssg0p9vm40c_setup_P_P_ccs.aocvm
       if {$IS_CHIP} { lappend EXTRA_DBS tphn28hpcpgv18ssg0p81v1p62vm40c.db } }
  BC { set DB   tcbn28hpcplusbwp40p140ffg0p99vm40c.db
       set SPEF $INPUT/$TOP.BC.spef.RC_BEST_-40.spef
       set AOCVM_FILE tcbn28hpcplusbwp40p140ffg0p99vm40c_hold_P_P_ccs.aocvm
       if {$IS_CHIP} { lappend EXTRA_DBS tphn28hpcpgv18ffg0p99v1p98vm40c.db } }
  default { error "PDE28_PT_CORNER must be WC or BC, got: $CORNER" }
}
# R2 (N.3): second pass with SBOCV AOCV tables (TSMC CCS-derived .aocvm,
# lib collateral 170a -- the only sbocv delivery in this PDK; NLDM is 180a).
# PDE28_PT_AOCV=1 selects the AOCV pass; reports get an _aocv prefix so the
# no-derate baseline and the AOCV pass coexist.
set AOCV [expr {[info exists ::env(PDE28_PT_AOCV)] && $::env(PDE28_PT_AOCV) eq "1"}]
set PFX $CORNER
if {$AOCV} { set PFX ${CORNER}_aocv }
set req [list $INPUT/$TOP.postroute.v $INPUT/$TOP.sdc $SPEF $LIBDIR/$DB]
foreach db $EXTRA_DBS { lappend req $LIBDIR/$db }
foreach f $req {
  if {![file isfile $f]} { error "Required input missing: $f" }
}

set_host_options -max_cores 8
set search_path [list . $LIBDIR]
set link_path   [concat [list * $DB] $EXTRA_DBS]

read_verilog $INPUT/$TOP.postroute.v
current_design $TOP
# Bond pads (PAD50GU, physical-only COVER cells: no .lib exists at all) are
# the only legitimate black boxes; anything else unresolved is a real
# library gap and must stop the run.
if {$IS_CHIP} { set link_create_black_boxes true }
redirect -variable link_log { link_design }
puts $link_log
# LNK-005 = unresolved reference, LNK-043 = black box created; the generic
# "Removed N unconnected cells and blackboxes" cleanup line must not trip
# this (first chip run lesson).
set bb_lines {}
foreach line [split $link_log "\n"] {
  if {[regexp {LNK-005|LNK-043} $line]} { lappend bb_lines $line }
}
foreach line $bb_lines {
  if {![string match {*PAD50GU*} $line]} {
    error "Unexpected black box during link: $line"
  }
}
echo "PDE28_PT black_box_link_lines=[llength $bb_lines] (PAD50GU only)"

# G.3 evidence: PT's recovery/removal gating differs from DC's
# enable_recovery_removal_arcs. Record the live default before any override,
# then force-enable so the state is explicit in the log either way.
echo "PDE28_PT pre-set timing_disable_recovery_removal_checks = $timing_disable_recovery_removal_checks"
set timing_disable_recovery_removal_checks false
echo "PDE28_PT CRPR default timing_remove_clock_reconvergence_pessimism = $timing_remove_clock_reconvergence_pessimism"
set timing_remove_clock_reconvergence_pessimism true

set_operating_conditions -analysis_type on_chip_variation
read_parasitics $SPEF
read_sdc $INPUT/$TOP.sdc

# The DC-era SDC still declares the clock source port ideal. ICC2 timed the
# design with the routed clock tree propagated (post-CTS state); do the same
# here. Derive the port from the clock definitions instead of a hardcoded
# name -- the core top clocks on `clk`, the pad top on `PAD_CLK`, and a
# silently skipped removal here would leave the clock network ideal.
set ideal_released 0
foreach_in_collection c [all_clocks] {
  foreach_in_collection s [get_attribute $c sources] {
    if {[get_attribute -quiet $s object_class] eq "port"} {
      remove_ideal_network $s
      incr ideal_released
    }
  }
}
if {$ideal_released == 0} { error "No clock source port found to release from ideal network" }
echo "PDE28_PT ideal_network_released_ports=$ideal_released"
set_propagated_clock [all_clocks]

if {$AOCV} {
  if {![file isfile $LIBDIR/$AOCVM_FILE]} {
    error "AOCV table missing: $LIBDIR/$AOCVM_FILE"
  }
  echo "PDE28_PT pre-set timing_aocvm_enable_analysis = $timing_aocvm_enable_analysis"
  set timing_aocvm_enable_analysis true
  read_aocvm $LIBDIR/$AOCVM_FILE
  redirect $RPT/${PFX}_aocvm_tables.rpt { report_aocvm }
}

update_timing -full

redirect $RPT/${PFX}_annotation.rpt { report_annotated_parasitics -check }
redirect $RPT/${PFX}_analysis_coverage.rpt { report_analysis_coverage -nosplit }
# Account for every untested endpoint in the four functional check classes
# (min_pulse_width excluded here: its untested population is reported in the
# coverage summary and is too large to enumerate usefully).
redirect $RPT/${PFX}_untested.rpt {
  report_analysis_coverage -status_details untested \
    -check_type {setup hold recovery removal} -nosplit
}
redirect $RPT/${PFX}_constraint_summary.rpt { report_constraint -nosplit }
redirect $RPT/${PFX}_constraint_violators.rpt {
  report_constraint -all_violators -nosplit
}

# WNS/TNS/NVP per delay type, computed from unique-endpoint worst paths
# (report_global_timing is unavailable in this build -- it errors out).
proc pde_slack_summary {delay_type label} {
  set paths [get_timing_paths -delay_type $delay_type -nworst 1 \
    -max_paths 1000000 -slack_lesser_than 0]
  set tns 0.0; set nvp 0; set wns 0.0
  foreach_in_collection p $paths {
    set s [get_attribute $p slack]
    if {$s < 0} {
      incr nvp
      set tns [expr {$tns + $s}]
      if {$s < $wns} { set wns $s }
    }
  }
  echo [format "PDE28_PT_SUMMARY %s WNS=%.4f TNS=%.4f NVP=%d" $label $wns $tns $nvp]
}

if {$CORNER eq "WC"} {
  pde_slack_summary max "${PFX}_max(setup+recovery)"
  redirect $RPT/${PFX}_setup_paths.rpt {
    report_timing -delay_type max -max_paths 20 -nworst 1 -slack_lesser_than 1000000 \
      -path_type full_clock_expanded -nosplit
  }
  # Recovery: max-delay checks at the async preset/clear pins.
  redirect $RPT/${PFX}_recovery_paths.rpt {
    report_timing -delay_type max -to [all_registers -async_pins] -slack_lesser_than 1000000 \
      -max_paths 20 -nworst 1 -path_type full_clock_expanded -nosplit
  }
} else {
  pde_slack_summary min "${PFX}_min(hold+removal)"
  redirect $RPT/${PFX}_hold_paths.rpt {
    report_timing -delay_type min -max_paths 20 -nworst 1 -slack_lesser_than 1000000 \
      -path_type full_clock_expanded -nosplit
  }
  # Removal: min-delay checks at the async preset/clear pins.
  redirect $RPT/${PFX}_removal_paths.rpt {
    report_timing -delay_type min -to [all_registers -async_pins] -slack_lesser_than 1000000 \
      -max_paths 20 -nworst 1 -path_type full_clock_expanded -nosplit
  }
}

echo "PDE28_PT_DONE corner=$CORNER reports=$RPT"
exit
