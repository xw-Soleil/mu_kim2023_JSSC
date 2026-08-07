# Stage 06 (E.8): second optimization pass targeting hold margin. The 65nm
# lesson: a single pass converging to exactly zero leaves no headroom, so a
# +50 ps hold target is applied for this pass (extra pessimism, not a
# relaxation) and removed afterwards.
source [file join [file dirname [file normalize [info script]]] pnr28_common.tcl]
open_design
# Antenna rules are session-local (s05b finding); re-source for any repair.
source $ANTENNA_TCL

# Probe for a dedicated hold-margin option in this build; fall back to a
# temporary +50 ps hold uncertainty adder in the hold scenario (tightening).
set margin_applied none
if {![catch {set_app_options -name opt.timing.hold_margin -value 0.05} msg]} {
  set margin_applied "opt.timing.hold_margin=0.05"
} else {
  current_scenario FUNC_BC
  set_clock_uncertainty -hold 0.10 [all_clocks]
  set margin_applied "FUNC_BC hold uncertainty 0.05->0.10 for this pass only"
}
puts "PDE28_HOLD_MARGIN: $margin_applied"
route_opt
# Restore the signed-off uncertainty if the fallback was used.
if {[string match "FUNC_BC*" $margin_applied]} {
  current_scenario FUNC_BC
  set_clock_uncertainty -hold 0.05 [all_clocks]
  current_scenario FUNC_WC
}
save_block
save_lib
catch { redirect -file [file join $REPORT_DIR s06_qor.rpt] { report_qor -nosplit } }
catch { redirect -file [file join $REPORT_DIR s06_constraints.rpt] {
  report_constraints -all_violators -nosplit
} }
stage_done s06_postroute
exit
