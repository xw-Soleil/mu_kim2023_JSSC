set repo_root /home/sxw/PDE/pdeMujunjie
set work_dir [file join $repo_root flow work openroad]
read_liberty [file join $work_dir tcbn65lpwc_openroad_impl_sta.lib]
read_db [file join $work_dir 20_cts_v4.odb]
set block [ord::get_db_block]
set inst [$block findInst clkbuf_0_clk]
puts "PDE_INST_HANDLE=$inst"
foreach call {{getName} {getOrigin} {getLocation} {getBBox} {getOrient} {getPlacementStatus} {setLocation 1188400 1339200}} {
  set rc [catch {$inst {*}$call} value]
  puts "PDE_API_[lindex $call 0]_RC=$rc VALUE=$value"
}
set bbox [$inst getBBox]
puts "PDE_BBOX=[$bbox xMin],[$bbox yMin],[$bbox xMax],[$bbox yMax]"
exit
