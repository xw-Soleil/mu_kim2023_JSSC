# ECO10 stage 1: make the post-route uncertainty split explicit and persistent.
#
# Background (CODEX_UBUNTU_WORKLOG_2026-08-03.md section 7): the DC SDC carries
# an unqualified `set_clock_uncertainty 0.2`, but in this post-route database
# the 0.2 ns shows up only on hold checks; setup paths carry no uncertainty at
# all.  eco04~eco09 therefore chased a phantom 0.2 ns hold target while a real
# ~-0.21 ns setup problem stayed hidden.  This stage, on a fresh copy of the
# eco03 database:
#   a) captures the per-scenario effective SDC before any edit (root-cause
#      evidence for where read_sdc actually put each constraint),
#   b) applies the intended split — setup 0.2 ns, hold 0.05 ns — in both
#      scenarios,
#   c) refuses to save unless the worst-path reports actually show -0.2000
#      (setup) and +0.0500 (hold) uncertainty lines.
# No netlist or route edits happen here; closure runs in stage 2.

proc require_env {name} {
  if {![info exists ::env($name)] || [string trim $::env($name)] eq ""} {
    error "Missing required environment variable: $name"
  }
  return [file normalize $::env($name)]
}

proc write_timing_reports {report_dir stem} {
  redirect -file [file join $report_dir ${stem}_qor.rpt] {
    report_qor -nosplit
  }
  current_scenario FUNC_WC
  redirect -file [file join $report_dir ${stem}_constraints_FUNC_WC.rpt] {
    report_constraints -all_violators -nosplit
  }
  redirect -file [file join $report_dir ${stem}_setup_violations_4d.rpt] {
    report_timing -delay_type max -scenarios [get_scenarios FUNC_WC] \
      -max_paths 10000 -slack_lesser_than 0 \
      -significant_digits 4 -physical -nosplit
  }
  redirect -file [file join $report_dir ${stem}_setup_worst_4d.rpt] {
    report_timing -delay_type max -scenarios [get_scenarios FUNC_WC] \
      -max_paths 1 -significant_digits 4 -physical -nosplit
  }
  current_scenario FUNC_BC
  redirect -file [file join $report_dir ${stem}_constraints_FUNC_BC.rpt] {
    report_constraints -all_violators -nosplit
  }
  redirect -file [file join $report_dir ${stem}_hold_violations_4d.rpt] {
    report_timing -delay_type min -scenarios [get_scenarios FUNC_BC] \
      -max_paths 10000 -slack_lesser_than 0 \
      -significant_digits 4 -physical -nosplit
  }
  redirect -file [file join $report_dir ${stem}_hold_worst_4d.rpt] {
    report_timing -delay_type min -scenarios [get_scenarios FUNC_BC] \
      -max_paths 1 -significant_digits 4 -physical -nosplit
  }
}

proc require_uncertainty_line {report_file pattern description} {
  set fh [open $report_file r]
  set text [read $fh]
  close $fh
  if {![regexp $pattern $text]} {
    error "Verification failed: $description not found in $report_file"
  }
}

set design_lib [require_env PDE_ECO10_DESIGN_LIB]
set report_dir [require_env PDE_ECO10_REPORT_DIR]
file mkdir $report_dir

set_host_options -max_cores 8
open_lib $design_lib
open_block pde_chip_top_safe.design
link_block
puts "PDE_ECO10_S1_BEGIN design_lib=$design_lib"

# --- (a) root-cause evidence: what does each scenario actually see today?
current_scenario FUNC_WC
write_sdc -output [file join $report_dir before_effective_FUNC_WC.sdc]
current_scenario FUNC_BC
write_sdc -output [file join $report_dir before_effective_FUNC_BC.sdc]

write_timing_reports $report_dir before

# --- (b) apply the intended split in both scenarios.
foreach scen {FUNC_WC FUNC_BC} {
  current_scenario $scen
  set_clock_uncertainty -setup 0.2 [get_clocks core_clk]
  set_clock_uncertainty -hold 0.05 [get_clocks core_clk]
}
puts "PDE_ECO10_S1_APPLIED setup=0.2 hold=0.05 scenarios={FUNC_WC FUNC_BC}"

current_scenario FUNC_WC
write_sdc -output [file join $report_dir after_effective_FUNC_WC.sdc]
current_scenario FUNC_BC
write_sdc -output [file join $report_dir after_effective_FUNC_BC.sdc]

write_timing_reports $report_dir after

# --- (c) verify before saving anything.
require_uncertainty_line \
  [file join $report_dir after_setup_worst_4d.rpt] \
  {clock uncertainty\s+-0\.2000} \
  "setup clock uncertainty -0.2000"
require_uncertainty_line \
  [file join $report_dir after_hold_worst_4d.rpt] \
  {clock uncertainty\s+0\.0500} \
  "hold clock uncertainty +0.0500"
puts "PDE_ECO10_S1_VERIFIED setup=-0.2000 hold=+0.0500"

save_block
save_lib
puts "PDE_ECO10_S1_DONE design_lib=$design_lib"
exit
