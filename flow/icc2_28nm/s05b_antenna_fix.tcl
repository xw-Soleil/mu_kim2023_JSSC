# Stage 05b (E.7 completion): antenna rules do NOT persist across
# save_lib/open_lib in this build (verified: report_antenna_rules is empty in
# a fresh session after the s01 definition). Re-source the PRTF rules in this
# session, then run incremental detail route so antenna checking + diode
# insertion actually execute on the finished routing.
source [file join [file dirname [file normalize [info script]]] pnr28_common.tcl]
open_design

source $ANTENNA_TCL
redirect -variable r { report_antenna_rules }
if {[string length $r] < 100} {
  error "Antenna rules still empty after re-source; aborting antenna fix"
}
puts "PDE28: antenna rules re-sourced ([string length $r] chars)"

route_detail -incremental true
save_block
save_lib
catch { redirect -file [file join $REPORT_DIR s05b_routes.rpt] {
  check_routes -open_net true -drc true -antenna true
} }
catch { redirect -file [file join $REPORT_DIR s05b_diodes.rpt] {
  puts "ANTENNA diode instances: [sizeof_collection [get_cells -quiet -hierarchical -filter {ref_name==ANTENNABWP40P140}]]"
} }
stage_done s05b_antenna_fix
exit
