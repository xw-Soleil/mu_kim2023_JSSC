set work_dir /home/sxw/PDE/pdeMujunjie/flow/work/openroad
read_liberty [file join $work_dir tcbn65lpwc_openroad_impl_sta.lib]
read_db [file join $work_dir 20_cts_v4.odb]
set block [ord::get_db_block]
foreach name {clk clknet_0_clk clknet_1_0_1_clk clknet_2_0_0_clk clknet_11_0__leaf_clk} {
  set net [$block findNet $name]
  if {$net == "NULL"} {
    puts "PDE_NDR_$name=MISSING"
    continue
  }
  set rule [$net getNonDefaultRule]
  puts "PDE_NDR_$name=$rule"
}
set net [$block findNet clknet_0_clk]
foreach null_value {NULL null {}} {
  set rc [catch {$net setNonDefaultRule $null_value} msg]
  puts "PDE_SET_NDR_NULL_VALUE=<$null_value> RC=$rc MSG=$msg AFTER=[$net getNonDefaultRule]"
}
exit
