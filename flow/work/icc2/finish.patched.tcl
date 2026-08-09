# Fill every legal row gap using only the explicitly verified RVT FILL family.
puts "PDE_FINISH: 按 PDE_SKIP_FILLERS=1 跳过填充单元"
connect_named_pg_pins
save_block

redirect -file [file join $REPORT_DIR final_design.rpt] {
  report_design -all
}
redirect -file [file join $REPORT_DIR final_qor.rpt] {
  report_qor -nosplit
}
redirect -file [file join $REPORT_DIR final_setup_timing.rpt] {
  report_timing -delay_type max -scenarios [get_scenarios FUNC_WC] \
    -max_paths 50 -sort_by slack -physical -nosplit
}
redirect -file [file join $REPORT_DIR final_hold_timing.rpt] {
  report_timing -delay_type min -scenarios [get_scenarios FUNC_BC] \
    -max_paths 50 -sort_by slack -physical -nosplit
}
redirect -file [file join $REPORT_DIR final_constraints.rpt] {
  report_constraints -all_violators -nosplit
}
redirect -file [file join $REPORT_DIR final_power.rpt] {
  report_power -scenarios [get_scenarios FUNC_WC] -verbose -nosplit
}
redirect -file [file join $REPORT_DIR final_utilization.rpt] {
  report_utilization -verbose
}
redirect -file [file join $REPORT_DIR final_congestion.rpt] {
  report_congestion -mode summary -nosplit
}
redirect -file [file join $REPORT_DIR final_clock_qor.rpt] {
  report_clock_qor -all -nosplit
}
redirect -file [file join $REPORT_DIR final_legality.rpt] {
  check_legality -verbose
}
redirect -file [file join $REPORT_DIR final_pg_connectivity.rpt] {
  check_pg_connectivity -nets [get_nets {VDD VSS}] \
    -check_std_cell_pins all -check_block_pins none -check_pad_pins none
}
redirect -file [file join $REPORT_DIR final_routes.rpt] {
  check_routes -open_net true -drc true -antenna true
}
redirect -file [file join $REPORT_DIR final_lvs.rpt] {
  check_lvs -checks all -max_errors 200
}

set FINAL_GDS [file join $RESULT_DIR ${TOP}.gds]
set FINAL_DEF [file join $RESULT_DIR ${TOP}.def]
set FINAL_NETLIST [file join $RESULT_DIR ${TOP}.postroute.v]
set FINAL_WC_SPEF [file join $RESULT_DIR ${TOP}.WC.spef]
set FINAL_BC_SPEF [file join $RESULT_DIR ${TOP}.BC.spef]

write_verilog -include all $FINAL_NETLIST
write_def $FINAL_DEF
write_parasitics -format spef -corner WC -output $FINAL_WC_SPEF
write_parasitics -format spef -corner BC -output $FINAL_BC_SPEF
write_gds -hierarchy all -lib_cell_view layout -long_names \
  -output_pin all -fill include -layer_map $GDS_MAP \
  -layer_map_format $GDS_MAP_FORMAT $FINAL_GDS

save_block
save_lib
puts "PDE_ICC2_DONE gds=$FINAL_GDS def=$FINAL_DEF netlist=$FINAL_NETLIST"
