# Stage 04 (E.6): CTS + postCTS optimization; clock and reset tree census;
# recovery/removal must be reported here.
source [file join [file dirname [file normalize [info script]]] pnr28_common.tcl]
open_design

redirect -file [file join $REPORT_DIR s04_pre_cts_check.rpt] {
  check_design -checks pre_clock_tree_stage
}
clock_opt
# Checkpoint immediately: a failing report must never cost the CTS result
# (lesson from the first s04 attempt, where an unsupported report command
# aborted the stage before save_block).
save_block
save_lib
catch { redirect -file [file join $REPORT_DIR s04_qor.rpt] { report_qor -nosplit } }
catch { redirect -file [file join $REPORT_DIR s04_clock_qor.rpt] { report_clock_qor -all -nosplit } }
catch { report_reset_tree s04_reset_tree.rpt }
# Recovery = max check (setup scenario), removal = min check (hold scenario).
catch { redirect -file [file join $REPORT_DIR s04_recovery.rpt] {
  report_timing -delay_type max -scenarios [get_scenarios FUNC_WC] \
    -to [get_pins -hierarchical */CDN] -max_paths 20 -nworst 1 -nosplit
} }
catch { redirect -file [file join $REPORT_DIR s04_removal.rpt] {
  report_timing -delay_type min -scenarios [get_scenarios FUNC_BC] \
    -to [get_pins -hierarchical */CDN] -max_paths 20 -nworst 1 -nosplit
} }
catch { redirect -file [file join $REPORT_DIR s04_constraints.rpt] {
  report_constraints -all_violators -nosplit
} }
stage_done s04_cts
exit
