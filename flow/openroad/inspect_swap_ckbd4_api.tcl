set work_dir /home/sxw/PDE/pdeMujunjie/flow/work/openroad
read_liberty [file join $work_dir tcbn65lpwc_openroad_impl_sta.lib]
read_db [file join $work_dir 20_cts_v4.odb]
set db [ord::get_db]
set block [ord::get_db_block]
set target NULL
foreach lib [$db getLibs] {
  set candidate [$lib findMaster CKBD4]
  if {$candidate != "NULL"} {set target $candidate}
}
if {$target == "NULL"} {error "CKBD4 master not found"}
set inst [$block findInst clkbuf_0_clk]
puts "PDE_SWAP_MASTER_BEFORE=[[$inst getMaster] getName]"
set rc [catch {$inst swapMaster $target} msg]
puts "PDE_SWAP_MASTER_RC=$rc MSG=$msg AFTER=[[$inst getMaster] getName]"
exit
