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
set TOP    pde_chip_top_safe
set INPUT  $ROOT/inputs
set LIBDIR $ROOT/lib
set RPT    $ROOT/pt/reports
file mkdir $RPT

switch -exact -- $CORNER {
  WC { set DB   tcbn28hpcplusbwp40p140ssg0p9vm40c.db
       set SPEF $INPUT/$TOP.WC.spef.RC_WORST_-40.spef }
  BC { set DB   tcbn28hpcplusbwp40p140ffg0p99vm40c.db
       set SPEF $INPUT/$TOP.BC.spef.RC_BEST_-40.spef }
  default { error "PDE28_PT_CORNER must be WC or BC, got: $CORNER" }
}
foreach f [list $INPUT/$TOP.postroute.v $INPUT/$TOP.sdc $SPEF $LIBDIR/$DB] {
  if {![file isfile $f]} { error "Required input missing: $f" }
}

set_host_options -max_cores 8
set search_path [list . $LIBDIR]
set link_path   [list * $DB]

read_verilog $INPUT/$TOP.postroute.v
current_design $TOP
link_design

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

# The DC-era SDC still declares the clock port ideal. ICC2 timed the design
# with the routed clock tree propagated (post-CTS state); do the same here.
# This adds real clock network delay -- more checking, not a relaxation.
if {[llength [get_ports -quiet clk]] > 0} {
  remove_ideal_network [get_ports clk]
}
set_propagated_clock [all_clocks]

update_timing -full

redirect $RPT/${CORNER}_annotation.rpt { report_annotated_parasitics -check }
redirect $RPT/${CORNER}_analysis_coverage.rpt { report_analysis_coverage -nosplit }
# Account for every untested endpoint in the four functional check classes
# (min_pulse_width excluded here: its untested population is reported in the
# coverage summary and is too large to enumerate usefully).
redirect $RPT/${CORNER}_untested.rpt {
  report_analysis_coverage -status_details untested \
    -check_type {setup hold recovery removal} -nosplit
}
redirect $RPT/${CORNER}_constraint_summary.rpt { report_constraint -nosplit }
redirect $RPT/${CORNER}_constraint_violators.rpt {
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
  pde_slack_summary max "WC_max(setup+recovery)"
  redirect $RPT/WC_setup_paths.rpt {
    report_timing -delay_type max -max_paths 20 -nworst 1 -slack_lesser_than 1000000 \
      -path_type full_clock_expanded -nosplit
  }
  # Recovery: max-delay checks at the async preset/clear pins.
  redirect $RPT/WC_recovery_paths.rpt {
    report_timing -delay_type max -to [all_registers -async_pins] -slack_lesser_than 1000000 \
      -max_paths 20 -nworst 1 -path_type full_clock_expanded -nosplit
  }
} else {
  pde_slack_summary min "BC_min(hold+removal)"
  redirect $RPT/BC_hold_paths.rpt {
    report_timing -delay_type min -max_paths 20 -nworst 1 -slack_lesser_than 1000000 \
      -path_type full_clock_expanded -nosplit
  }
  # Removal: min-delay checks at the async preset/clear pins.
  redirect $RPT/BC_removal_paths.rpt {
    report_timing -delay_type min -to [all_registers -async_pins] -slack_lesser_than 1000000 \
      -max_paths 20 -nworst 1 -path_type full_clock_expanded -nosplit
  }
}

echo "PDE28_PT_DONE corner=$CORNER reports=$RPT"
exit
