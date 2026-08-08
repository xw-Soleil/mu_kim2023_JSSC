# DC synthesis for pde_chip_top_safe on TSMC 28nm HPC+ (tcbn28hpcplusbwp40p140).
#
# Origin: copied from flow/dc/synth.tcl @ commit 57572a9 (65nm, reset-unmask
# verified). Do not edit the 65nm original. Diff points vs the origin:
#   * target/link/min libraries -> 28nm NLDM (setup ssg0p9vm40c, hold/min
#     ffg0p99vm40c via set_min_library); PDK root ~/pdk/tsmc28hpcplus
#   * output tree via PDE28_DC_OUTPUT_ROOT (never the 65nm flow/work areas)
#   * max_transition 0.5 kept (library default_max_transition measured
#     0.5187 ns at ssg0p9vm40c; 0.5 is tighter, hence not a relaxation)
#   * everything process-independent carried unchanged: recovery/removal
#     arc enable, reset three-layer structure, report set, 10 ns clock and
#     uncertainty/io budgets (kept identical for 65nm comparability)

proc env_or_default {name fallback} {
  if {[info exists ::env($name)] && [string trim $::env($name)] ne ""} {
    return $::env($name)
  }
  return $fallback
}

set SCRIPT_DIR [file dirname [file normalize [info script]]]
set REPO_ROOT [file normalize [env_or_default PDE_REPO_ROOT \
  [file join $SCRIPT_DIR ../..]]]
set OUTPUT_ROOT [string trim [env_or_default PDE28_DC_OUTPUT_ROOT ""]]
if {$OUTPUT_ROOT eq ""} {
  error "PDE28_DC_OUTPUT_ROOT must point to a fresh run directory"
}
set WORK_DIR   [file join $OUTPUT_ROOT work]
set REPORT_DIR [file join $OUTPUT_ROOT reports]
set RESULT_DIR [file join $OUTPUT_ROOT results]

file mkdir $WORK_DIR
file mkdir $REPORT_DIR
file mkdir $RESULT_DIR

set TOP [env_or_default PDE_TOP pde_chip_top_safe]
set CLOCK_PORT clk
set CLOCK_NAME core_clk
# R2 (Stage L): period is env-overridable; default stays the 10 ns baseline.
# R2 runs set PDE28_CLOCK_PERIOD=6.0 (rationale: round-1 post-route setup
# slack +5.25 on 10 ns puts circuit capability near 4.7 ns; 6 ns keeps ~20%).
set CLOCK_PERIOD [env_or_default PDE28_CLOCK_PERIOD 10.000]

# 28nm NLDM delivery (original-structure extraction; see the PDK-root README).
# PDK root comes from the environment; no machine paths in tracked scripts.
set PDK28_ROOT [env_or_default PDE28_PDK_ROOT \
  [file join $::env(HOME) pdk tsmc28hpcplus]]
set NLDM_DIR [env_or_default PDE28_NLDM_DIR \
  [file join $PDK28_ROOT tcbn28hpcplusbwp40p140_180b TSMCHOME digital Front_End timing_power_noise NLDM tcbn28hpcplusbwp40p140_180a]]
# Setup (max) corner: ssg global slow, nominal 0.9 V, -40 C. 28nm shows
# temperature inversion, so the slow library at cold is the setup-critical
# choice among the delivered ssg0p9v{m40,125}c pair.
set TARGET_DB [env_or_default PDE28_TARGET_DB \
  [file join $NLDM_DIR tcbn28hpcplusbwp40p140ssg0p9vm40c.db]]
# Hold (min) corner: ffg global fast at nominal+10% (0.99 V), -40 C: the
# fastest delivered min-delay library for removal/hold pessimism.
set MIN_DB [env_or_default PDE28_MIN_DB \
  [file join $NLDM_DIR tcbn28hpcplusbwp40p140ffg0p99vm40c.db]]

foreach f [list $TARGET_DB $MIN_DB] {
  if {![file exists $f]} { error "Missing library: $f" }
}

set RTL_FILES [list \
  [file join $REPO_ROOT src common counter_ce.sv] \
  [file join $REPO_ROOT src common pipeline_delay_bit.sv] \
  [file join $REPO_ROOT src pe pde_q8p7_pkg.sv] \
  [file join $REPO_ROOT src pe r_alu.sv] \
  [file join $REPO_ROOT src pe r_reg.sv] \
  [file join $REPO_ROOT src pe r_dsm.sv] \
  [file join $REPO_ROOT src pe r_status.sv] \
  [file join $REPO_ROOT src pe sol_acc.sv] \
  [file join $REPO_ROOT src pe r_state_ctrl.sv] \
  [file join $REPO_ROOT src pe pe_top.sv] \
  [file join $REPO_ROOT src pe_array pde_memcontrol.sv] \
  [file join $REPO_ROOT src pe_array pde_tcu.sv] \
  [file join $REPO_ROOT src pe_array pde_core.sv] \
  [file join $REPO_ROOT src pe_array pde_chip_top.sv] \
  [file join $REPO_ROOT src pe_array pde_chip_top_safe.sv]]

foreach RTL_FILE $RTL_FILES {
  if {![file exists $RTL_FILE]} {
    error "Missing RTL source: $RTL_FILE"
  }
}

set_app_var search_path [concat [list $REPO_ROOT $NLDM_DIR] $search_path]
set_app_var target_library [list $TARGET_DB]
set_app_var link_library [concat "*" $target_library]

# DC ignores library recovery/removal arcs by default (var default: false).
# Without this, no reset-release check is ever performed regardless of SDC.
# [carried from 65nm, process independent; keep enabled]
set_app_var enable_recovery_removal_arcs true

# [28nm AOCV hook - NOT enabled in this baseline run]
# sbocv tables exist under
#   $PDE28_PDK_ROOT/tcbn28hpcplusbwp40p140_180b/TSMCHOME/digital/Front_End/SBOCV/
# (216 .aocvm, ssg/ffg x voltage x temp). Enable in PT (read_aocvm +
# variation-aware analysis) or DC topographical derate flow once the
# no-derate baseline below is banked for 65nm comparison.

set_svf [file join $RESULT_DIR ${TOP}.svf]
define_design_lib WORK -path [file join $WORK_DIR WORK]

catch {set_host_options -max_cores 4}

analyze -format sverilog -library WORK $RTL_FILES
elaborate $TOP -library WORK
current_design $TOP
link
uniquify

# Min-delay (hold/removal) analysis library pairing.
set_min_library [file tail $TARGET_DB] -min_version [file tail $MIN_DB]

redirect -file [file join $REPORT_DIR check_design_precompile.rpt] {
  check_design
}

create_clock -name $CLOCK_NAME -period $CLOCK_PERIOD [get_ports $CLOCK_PORT]
# Uncertainty kept split and identical to the 65nm baseline (setup 0.2 /
# hold 0.05) for cross-node comparability of this bring-up run.
set_clock_uncertainty -setup 0.200 [get_clocks $CLOCK_NAME]
set_clock_uncertainty -hold 0.050 [get_clocks $CLOCK_NAME]
set_clock_transition 0.100 [get_clocks $CLOCK_NAME]

set DATA_INPUTS [remove_from_collection [all_inputs] [get_ports {clk rst_n}]]
if {[sizeof_collection $DATA_INPUTS] > 0} {
  set_input_delay 1.000 -clock $CLOCK_NAME $DATA_INPUTS
  set_input_transition 0.100 $DATA_INPUTS
}
if {[sizeof_collection [all_outputs]] > 0} {
  set_output_delay 1.000 -clock $CLOCK_NAME [all_outputs]
  set_load 0.050 [all_outputs]
}

# Reset constraints [carried from 65nm Stage 4, process independent]:
# the RTL has a two-stage synchronizer in pde_chip_top_safe
# (rst_sync_q_reg[0]/[1], async assert / sync release).
#  1. rst_n is NOT an ideal network; only clk stays ideal pre-CTS.
#  2. rst_n gets a real arrival window (max 1.0 / min 0.2 ns, same budget
#     convention as the data inputs; re-derive on a real 28nm IO plan).
#  3. The false path covers only the truly asynchronous segment: after the
#     synchronizer, port paths end at the synchronizer CDN pins; downstream
#     CDNs launch from rst_sync_q_reg[1]/CP and stay fully checked.
set_input_delay -max 1.000 -clock $CLOCK_NAME [get_ports rst_n]
set_input_delay -min 0.200 -clock $CLOCK_NAME [get_ports rst_n]
set_input_transition 0.100 [get_ports rst_n]
set_false_path -from [get_ports rst_n]
set_ideal_network [get_ports clk]

set_max_fanout 32 [current_design]
# Library default_max_transition at ssg0p9vm40c measured 0.5187 ns; the
# design-level 0.5 below is tighter than the library default.
set_max_transition 0.500 [current_design]
set_fix_multiple_port_nets -all -buffer_constants

compile_ultra -no_autoungroup

change_names -rules verilog -hierarchy

redirect -file [file join $REPORT_DIR check_design.rpt] {
  check_design
}
redirect -file [file join $REPORT_DIR check_timing.rpt] {
  check_timing
}
redirect -file [file join $REPORT_DIR qor.rpt] {
  report_qor
}
redirect -file [file join $REPORT_DIR area_hier.rpt] {
  report_area -hierarchy
}
redirect -file [file join $REPORT_DIR timing_max.rpt] {
  report_timing -delay_type max -max_paths 50 -nworst 2 -input_pins -nets
}
redirect -file [file join $REPORT_DIR timing_min.rpt] {
  report_timing -delay_type min -max_paths 20 -nworst 1 -input_pins -nets
}
# Reset-release checks (65nm Stage 4 structure). If this DC build lacks
# report_timing -check_type, fall back to addressing the async clear pins
# directly (same path set, CDN endpoints).
redirect -file [file join $REPORT_DIR timing_removal.rpt] {
  if {[catch {report_timing -delay_type min -check_type removal \
                -max_paths 20 -nworst 1 -input_pins} msg]} {
    puts "FALLBACK (-check_type unsupported): $msg"
    report_timing -delay_type min -max_paths 20 -nworst 1 -input_pins \
      -to [get_pins -hierarchical */CDN]
  }
}
redirect -file [file join $REPORT_DIR timing_recovery.rpt] {
  if {[catch {report_timing -delay_type max -check_type recovery \
                -max_paths 20 -nworst 1 -input_pins} msg]} {
    puts "FALLBACK (-check_type unsupported): $msg"
    report_timing -delay_type max -max_paths 20 -nworst 1 -input_pins \
      -to [get_pins -hierarchical */CDN]
  }
}
redirect -file [file join $REPORT_DIR constraints.rpt] {
  report_constraint -all_violators
}
redirect -file [file join $REPORT_DIR power.rpt] {
  report_power -hierarchy
}
redirect -file [file join $REPORT_DIR clocks.rpt] {
  report_clock
}
redirect -file [file join $REPORT_DIR high_fanout.rpt] {
  report_net_fanout -threshold 32
}
redirect -file [file join $REPORT_DIR resources.rpt] {
  report_resources -hierarchy
}

write -format ddc -hierarchy -output [file join $RESULT_DIR ${TOP}.ddc]
write_file -format verilog -hierarchy -output [file join $RESULT_DIR ${TOP}.v]
write_sdc [file join $RESULT_DIR ${TOP}.sdc]
write_sdf -version 2.1 [file join $RESULT_DIR ${TOP}.sdf]

puts "PDE_DC28_DONE top=$TOP clock_period=$CLOCK_PERIOD result_dir=$RESULT_DIR"
quit
