# Stage 03 (E.5): placement + preCTS optimization.
source [file join [file dirname [file normalize [info script]]] pnr28_common.tcl]
open_design

redirect -file [file join $REPORT_DIR s03_pre_place_check.rpt] {
  check_design -checks pre_placement_stage
}
place_opt
redirect -file [file join $REPORT_DIR s03_qor.rpt] { report_qor -nosplit }
redirect -file [file join $REPORT_DIR s03_qor_summary.rpt] { report_qor -summary }
redirect -file [file join $REPORT_DIR s03_utilization.rpt] { report_utilization }
stage_done s03_place
exit
