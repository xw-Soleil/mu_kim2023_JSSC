# ECO10 stage 1b: restore the scenario-level constraints that never reached
# FUNC_WC.
#
# Evidence (uncertainty_fix/before_effective_FUNC_WC.sdc vs _FUNC_BC.sdc): the
# original mode-context read_sdc delivered every scenario-scoped constraint —
# I/O delays, port loads, input transitions, design max_transition/max_fanout,
# clock uncertainty — only to FUNC_BC, the current scenario at import time.
# FUNC_WC setup analysis therefore never checked I/O paths or the intended
# electrical limits.
#
# Deliberately NOT done by re-running read_sdc: create_clock would rebuild the
# clock object and drop its post-CTS propagated/latency state.  The missing
# constraints are rebuilt exactly the way flow/dc/synth.tcl generated them,
# then the setup/hold uncertainty split is re-asserted.  Values must stay in
# lockstep with flow/dc/synth.tcl.

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

proc require_sdc_line {sdc_file pattern description} {
  set fh [open $sdc_file r]
  set text [read $fh]
  close $fh
  if {![regexp $pattern $text]} {
    error "Verification failed: $description not found in $sdc_file"
  }
}

set design_lib [require_env PDE_ECO10_DESIGN_LIB]
set report_dir [require_env PDE_ECO10_REPORT_DIR]
file mkdir $report_dir

set_host_options -max_cores 8
open_lib $design_lib
open_block pde_chip_top_safe.design
link_block
puts "PDE_ECO10_S1B_BEGIN design_lib=$design_lib"

foreach scen {FUNC_WC FUNC_BC} {
  current_scenario $scen
  set data_inputs [remove_from_collection [all_inputs] [get_ports {clk rst_n}]]
  set data_outputs [all_outputs]
  if {[sizeof_collection $data_inputs] == 0 || [sizeof_collection $data_outputs] == 0} {
    error "Unexpected empty data port collection in scenario $scen"
  }
  set_max_fanout 32 [current_design]
  set_max_transition 0.5 [current_design]
  set_clock_transition 0.1 [get_clocks core_clk]
  set_input_delay -clock core_clk 1 $data_inputs
  set_input_transition 0.1 $data_inputs
  set_output_delay -clock core_clk 1 $data_outputs
  set_load -pin_load 0.05 $data_outputs
  set_clock_uncertainty -setup 0.2 [get_clocks core_clk]
  set_clock_uncertainty -hold 0.05 [get_clocks core_clk]
  puts "PDE_ECO10_S1B_APPLIED scenario=$scen inputs=[sizeof_collection $data_inputs] outputs=[sizeof_collection $data_outputs]"
}

current_scenario FUNC_WC
write_sdc -output [file join $report_dir s1b_effective_FUNC_WC.sdc]
current_scenario FUNC_BC
write_sdc -output [file join $report_dir s1b_effective_FUNC_BC.sdc]

write_timing_reports $report_dir s1b

# FUNC_WC must now carry the full scenario constraint set and the split
# uncertainty; refuse to save otherwise.
set wc_sdc [file join $report_dir s1b_effective_FUNC_WC.sdc]
require_sdc_line $wc_sdc {set_input_delay}  "input delays in FUNC_WC"
require_sdc_line $wc_sdc {set_output_delay} "output delays in FUNC_WC"
require_sdc_line $wc_sdc {set_load}         "output port loads in FUNC_WC"
require_sdc_line $wc_sdc {set_max_transition 0\.5} "design max_transition in FUNC_WC"
require_sdc_line $wc_sdc {set_clock_uncertainty -setup 0\.2} "setup uncertainty in FUNC_WC"
require_sdc_line $wc_sdc {set_clock_uncertainty -hold 0\.05} "hold uncertainty in FUNC_WC"
puts "PDE_ECO10_S1B_VERIFIED"

save_block
save_lib
puts "PDE_ECO10_S1B_DONE design_lib=$design_lib"
exit
