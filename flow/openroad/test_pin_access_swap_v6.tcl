set repo_root /home/sxw/PDE/pdeMujunjie
set work_dir [file join $repo_root flow work openroad]
read_liberty [file join $work_dir tcbn65lpwc_openroad_impl_sta.lib]
read_db [file join $work_dir 20_cts_v4.odb]
set_thread_count 8
set_routing_layers -signal M1-M6 -clock M1-M6
global_connect
set block [ord::get_db_block]

proc swap_same_master_instances {block name_a name_b} {
  set a [$block findInst $name_a]
  set b [$block findInst $name_b]
  set loc_a [$a getLocation]
  set loc_b [$b getLocation]
  set orient_a [$a getOrient]
  set orient_b [$b getOrient]
  puts "PDE_SWAP $name_a $loc_a $orient_a <-> $name_b $loc_b $orient_b"
  $a setLocation {*}$loc_b
  $a setOrient $orient_b
  $b setLocation {*}$loc_a
  $b setOrient $orient_a
}

swap_same_master_instances $block clkbuf_0_clk clkbuf_1_1_0_clk
swap_same_master_instances $block clkbuf_2_0_0_clk clkbuf_2_1_0_clk
check_placement -verbose -disallow_one_site_gaps

set guarded 0
foreach net [$block getNets] {
  set sig [$net getSigType]
  set pins [expr {[llength [$net getITerms]] + [llength [$net getBTerms]]}]
  if {![$net isSpecial] && $pins == 0 && ($sig eq "POWER" || $sig eq "GROUND")} {
    $net setSpecial
    incr guarded
  }
}
puts "PDE_PIN_TEST_GUARDED=$guarded"
if {$guarded != 203} {error "Expected 203 zero-terminal supply nets"}
pin_access -bottom_routing_layer M1 -top_routing_layer M6 -verbose 1
puts "PDE_PIN_ACCESS_SWAP_PASS"
exit
