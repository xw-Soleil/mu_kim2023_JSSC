set repo_root /home/sxw/PDE/pdeMujunjie
set work_dir [file join $repo_root flow work openroad]
set report_dir [file join $repo_root flow reports openroad]
read_liberty [file join $work_dir tcbn65lpwc_openroad_impl_sta.lib]
read_db [file join $work_dir 20_cts_v4.odb]
set_thread_count 8
set_routing_layers -signal M2-M6 -clock M3-M6
set block [ord::get_db_block]
set moves [list \
  clkbuf_0_clk $::env(PDE_CLKBUF0_X) 1339200 \
  clkbuf_2_0_0_clk $::env(PDE_CLKBUF2_X) 1177200]
foreach {name x y} $moves {
  set inst [$block findInst $name]
  puts "PDE_MOVE_${name}_FROM=[$inst getLocation] TO=$x $y"
  $inst setLocation $x $y
}
check_placement -verbose -disallow_one_site_gaps \
  -report_file_name [file join $report_dir pin_access_move_placement.json]
pin_access -bottom_routing_layer M1 -top_routing_layer M6 -verbose 1
puts "PDE_PIN_ACCESS_MOVE_PASS"
exit
