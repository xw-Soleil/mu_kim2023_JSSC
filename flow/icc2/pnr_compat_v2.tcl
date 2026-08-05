# ICC2 O-2018.06-SP1 compatibility launcher.
#
# Keep the reviewed implementation flow immutable and substitute only the one
# grouped check name that this release predates.  Use an isolated design
# library so failed attempts remain inspectable and are never overwritten.

set SCRIPT_DIR [file dirname [file normalize [info script]]]
set REPO_ROOT [file normalize [file join $SCRIPT_DIR ../..]]
set ::env(PDE_ICC2_DESIGN_LIB) \
  [file join $REPO_ROOT flow work icc2 pde_chip_top_safe_run3.dlib]

set flow_file [file join $SCRIPT_DIR pnr.tcl]
set flow_fp [open $flow_file r]
set flow_text [read $flow_fp]
close $flow_fp

set unsupported {check_design -checks {netlist unbound}}
if {[string first $unsupported $flow_text] < 0} {
  error "Expected compatibility target is absent from $flow_file"
}
set flow_text [string map [list $unsupported {check_design}] $flow_text]

uplevel #0 $flow_text
