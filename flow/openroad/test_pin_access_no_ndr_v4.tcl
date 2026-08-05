set repo_root /home/sxw/PDE/pdeMujunjie
set work_dir [file join $repo_root flow work openroad]
read_liberty [file join $work_dir tcbn65lpwc_openroad_impl_sta.lib]
read_db [file join $work_dir 20_cts_v4.odb]
set_thread_count 8
set_routing_layers -signal M1-M6 -clock M1-M6
global_connect
set block [ord::get_db_block]
set guarded 0
set ndr_cleared 0
foreach net [$block getNets] {
  set sig [$net getSigType]
  set pins [expr {[llength [$net getITerms]] + [llength [$net getBTerms]]}]
  if {![$net isSpecial] && $pins == 0 && ($sig eq "POWER" || $sig eq "GROUND")} {
    $net setSpecial
    incr guarded
  }
  if {[$net getNonDefaultRule] != "NULL"} {
    $net setNonDefaultRule NULL
    incr ndr_cleared
  }
}
puts "PDE_PIN_TEST_GUARDED=$guarded"
puts "PDE_PIN_TEST_NDR_CLEARED=$ndr_cleared"
if {$guarded != 203} {error "Expected 203 zero-terminal supply nets"}
pin_access -bottom_routing_layer M1 -top_routing_layer M6 -verbose 1
puts "PDE_PIN_ACCESS_NO_NDR_PASS"
exit
