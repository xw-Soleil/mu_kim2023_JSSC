# Stage 07 (E.9): fillers, hard gates (geometry DRC=0, connectivity clean,
# setup AND hold violating paths = 0), then deliverables. The timing gate is
# the explicit 65nm lesson: never stream GDS past open timing violations.
source [file join [file dirname [file normalize [info script]]] pnr28_common.tcl]
open_design
# Antenna rules are session-local (s05b finding); re-source for any repair.
source $ANTENNA_TCL

set FILLER_MASTERS {FILL64BWP40P140 FILL32BWP40P140 FILL16BWP40P140 \
  FILL8BWP40P140 FILL4BWP40P140 FILL3BWP40P140 FILL2BWP40P140}
set filler_patterns {}
foreach m $FILLER_MASTERS { require_one_lib_cell $m; lappend filler_patterns "*/$m" }
set FILLER_CELLS [get_lib_cells $filler_patterns]
set_lib_cell_purpose -include none $FILLER_CELLS
if {[sizeof_collection [get_cells -quiet PDE_FILLER_*]] == 0} {
  create_stdcell_fillers -lib_cells $FILLER_CELLS -prefix PDE_FILLER_
  connect_named_pg_pins
} else {
  puts "PDE28: fillers already present, skipping insertion"
}

redirect -file [file join $REPORT_DIR s07_legality.rpt] { check_legality -verbose }
redirect -file [file join $REPORT_DIR s07_routes.rpt] {
  check_routes -open_net true -drc true -antenna true
}
redirect -file [file join $REPORT_DIR s07_pg_connectivity.rpt] {
  check_pg_connectivity -nets [get_nets {VDD VSS}] \
    -check_std_cell_pins all -check_block_pins none -check_pad_pins none
}
redirect -file [file join $REPORT_DIR s07_lvs.rpt] {
  check_lvs -checks all -max_errors 200
}
redirect -file [file join $REPORT_DIR s07_qor.rpt] { report_qor -nosplit }
redirect -file [file join $REPORT_DIR s07_constraints.rpt] {
  report_constraints -all_violators -nosplit
}
redirect -file [file join $REPORT_DIR s07_recovery.rpt] {
  report_timing -delay_type max -scenarios [get_scenarios FUNC_WC] \
    -to [get_pins -hierarchical */CDN] -max_paths 20 -nworst 1 -nosplit
}
redirect -file [file join $REPORT_DIR s07_removal.rpt] {
  report_timing -delay_type min -scenarios [get_scenarios FUNC_BC] \
    -to [get_pins -hierarchical */CDN] -max_paths 20 -nworst 1 -nosplit
}
report_reset_tree s07_reset_tree.rpt
redirect -file [file join $REPORT_DIR s07_design.rpt] { report_design -all }
redirect -file [file join $REPORT_DIR s07_utilization.rpt] { report_utilization -verbose }

# ---- hard gates ----
set gate_fail {}
redirect -variable qor_sum { report_qor -summary }
puts $qor_sum
# Timing gate: parse violating path counts from the scenario summary table.
set setup_viol -1
set hold_viol -1
foreach line [split $qor_sum "\n"] {
  if {[regexp {FUNC_WC.*\(Setup\)} $line]} {
    set setup_viol [lindex [regexp -all -inline {\S+} $line] end]
  }
  if {[regexp {FUNC_BC.*\(Hold\)} $line]} {
    set hold_viol [lindex [regexp -all -inline {\S+} $line] end]
  }
}
puts "PDE28_GATE setup_violations=$setup_viol hold_violations=$hold_viol"
if {$setup_viol != 0} { lappend gate_fail "setup violating paths=$setup_viol" }
if {$hold_viol != 0} { lappend gate_fail "hold violating paths=$hold_viol" }
# Geometry/connectivity gates parsed from the checkers' own totals
# (first finish attempt showed the setup/hold-only gate let 113 DRC and
# 73 shorts through; every count below must be exactly zero).
redirect -variable chk { check_routes -open_net true -drc true -antenna true }
set drc_total -1; set ant_total -1; set open_total -1
regexp {TOTAL VIOLATIONS =\s+(\d+)} $chk -> drc_total
regexp {Total number of antenna violations =\s+(\d+)} $chk -> ant_total
regexp {Total number of open nets =\s+(\d+)} $chk -> open_total
redirect -variable lvs { check_lvs -checks all -max_errors 200 }
set short_total -1
regexp {Total number of short violations is\s+(\d+)} $lvs -> short_total
puts "PDE28_GATE drc=$drc_total antenna=$ant_total opens=$open_total shorts=$short_total"
if {$drc_total != 0}   { lappend gate_fail "geometry DRC=$drc_total" }
if {$ant_total != 0}   { lappend gate_fail "antenna=$ant_total" }
if {$open_total != 0}  { lappend gate_fail "open nets=$open_total" }
if {$short_total != 0} { lappend gate_fail "shorts=$short_total" }
if {[llength $gate_fail] > 0} {
  puts "PDE28_GATE_FAIL: [join $gate_fail {; }]"
  save_block
  save_lib
  error "Hard gate failed; GDS not written: [join $gate_fail {; }]"
}

set FINAL_GDS     [file join $RESULT_DIR ${TOP}.gds]
set FINAL_DEF     [file join $RESULT_DIR ${TOP}.def]
set FINAL_NETLIST [file join $RESULT_DIR ${TOP}.postroute.v]
set FINAL_WC_SPEF [file join $RESULT_DIR ${TOP}.WC.spef]
set FINAL_BC_SPEF [file join $RESULT_DIR ${TOP}.BC.spef]
set FINAL_SDF     [file join $RESULT_DIR ${TOP}.sdf]
write_verilog -include all $FINAL_NETLIST
write_def $FINAL_DEF
write_parasitics -format spef -corner WC -output $FINAL_WC_SPEF
write_parasitics -format spef -corner BC -output $FINAL_BC_SPEF
if {[llength [info commands write_sdf]] > 0} {
  write_sdf $FINAL_SDF
} else {
  puts "PDE28_NOTE: write_sdf unavailable in this build; SDF deferred to PT"
}
write_gds -hierarchy all -lib_cell_view layout -long_names \
  -output_pin all -fill include -layer_map $GDS_MAP \
  -layer_map_format icc_default $FINAL_GDS

stage_done s07_finish
puts "PDE28_PNR_DONE gds=$FINAL_GDS"
exit
