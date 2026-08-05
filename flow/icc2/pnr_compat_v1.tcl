# Compatibility launcher for ICC2 O-2018.06-SP1.
# The release does not accept the newer grouped "netlist unbound" check name;
# map only that early link check to the release's default check_design command
# and pass every stage-specific check through unchanged.

set SCRIPT_DIR [file dirname [file normalize [info script]]]
set REPO_ROOT [file normalize [file join $SCRIPT_DIR ../..]]
set ::env(PDE_ICC2_DESIGN_LIB) \
  [file join $REPO_ROOT flow work icc2 pde_chip_top_safe_run2.dlib]

rename check_design pde_native_check_design
proc check_design {args} {
  if {[llength $args] == 2 && [lindex $args 0] eq "-checks" &&
      [lindex $args 1] eq "netlist unbound"} {
    return [uplevel 1 [list pde_native_check_design]]
  }
  return [uplevel 1 [linsert $args 0 pde_native_check_design]]
}

source [file join $SCRIPT_DIR pnr.tcl]
