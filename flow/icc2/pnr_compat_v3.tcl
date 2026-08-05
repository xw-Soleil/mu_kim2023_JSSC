# ICC2 O-2018.06-SP1 launcher for the installed base-license feature set.
# The server lacks the ICCompilerII-4/8 feature required only by check_design;
# preserve stage reports with an explicit skip marker and run the implementation
# engines plus the dedicated final legality/connectivity/route/LVS checks.

set SCRIPT_DIR [file dirname [file normalize [info script]]]
set REPO_ROOT [file normalize [file join $SCRIPT_DIR ../..]]
set ::env(PDE_ICC2_DESIGN_LIB) \
  [file join $REPO_ROOT flow work icc2 pde_chip_top_safe_run4.dlib]

set flow_file [file join $SCRIPT_DIR pnr.tcl]
set flow_fp [open $flow_file r]
set flow_text [read $flow_fp]
close $flow_fp

set substitutions [list \
  {check_design -checks {netlist unbound}} \
  {puts "PDE_ICC2_CHECK_SKIPPED: check_design netlist/unbound requires unavailable ICCompilerII-4/8 license"} \
  {check_design -checks pre_placement_stage} \
  {puts "PDE_ICC2_CHECK_SKIPPED: check_design pre_placement_stage requires unavailable ICCompilerII-4/8 license"} \
  {check_design -checks pre_clock_tree_stage} \
  {puts "PDE_ICC2_CHECK_SKIPPED: check_design pre_clock_tree_stage requires unavailable ICCompilerII-4/8 license"} \
  {check_design -checks pre_route_stage} \
  {puts "PDE_ICC2_CHECK_SKIPPED: check_design pre_route_stage requires unavailable ICCompilerII-4/8 license"}]

foreach {unsupported replacement} $substitutions {
  if {[string first $unsupported $flow_text] < 0} {
    error "Expected compatibility target is absent from $flow_file: $unsupported"
  }
}
set flow_text [string map $substitutions $flow_text]
uplevel #0 $flow_text
