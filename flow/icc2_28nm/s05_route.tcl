# Stage 05 (E.7): routing with antenna fixing + diode insertion, then the
# first post-route optimization pass.
source [file join [file dirname [file normalize [info script]]] pnr28_common.tcl]
open_design

redirect -file [file join $REPORT_DIR s05_pre_route_check.rpt] {
  check_design -checks pre_route_stage
}
route_auto
save_block
route_opt
save_block
save_lib
catch { redirect -file [file join $REPORT_DIR s05_routes.rpt] {
  check_routes -open_net true -drc true -antenna true
} }
catch { redirect -file [file join $REPORT_DIR s05_diodes.rpt] {
  puts "ANTENNA diode instances: [sizeof_collection [get_cells -quiet -hierarchical -filter {ref_name==ANTENNABWP40P140}]]"
} }
catch { redirect -file [file join $REPORT_DIR s05_qor.rpt] { report_qor -nosplit } }
stage_done s05_route
exit
