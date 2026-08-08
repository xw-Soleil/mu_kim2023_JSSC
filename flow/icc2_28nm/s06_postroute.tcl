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

# R2 (M.5) gate: round-1's route_opt left 113 DRC + 73 shorts that surfaced
# only at s07. Check here; repair incrementally (s07b recipe); hard-stop if
# unconverged so the failure is diagnosed at its source.
set drc_total -1
for {set i 0} {$i <= 3} {incr i} {
  if {$i > 0} {
    route_detail -incremental true
    save_block
  }
  redirect -variable chk { check_routes -open_net true -drc true -antenna true }
  regexp {TOTAL VIOLATIONS =\s+(\d+)} $chk -> drc_total
  puts "PDE28_S06_GATE iter=$i drc_total=$drc_total"
  if {$drc_total == 0} break
}
redirect -file [file join $REPORT_DIR s06_routes.rpt] {
  check_routes -open_net true -drc true -antenna true
}
if {$drc_total != 0} {
  save_block
  save_lib
  error "s06 route gate failed after incremental repair: DRC=$drc_total"
}
catch { redirect -file [file join $REPORT_DIR s06_qor.rpt] { report_qor -nosplit } }
catch { redirect -file [file join $REPORT_DIR s06_constraints.rpt] {
  report_constraints -all_violators -nosplit
} }
stage_done s06_postroute
exit
