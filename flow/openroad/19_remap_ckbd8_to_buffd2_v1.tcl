# OpenDB-only equivalent remap before CTS.  Avoid loading STA during the master
# swap because this OpenROAD build has a known swapMaster callback heap bug.

set repo_root /home/sxw/PDE/pdeMujunjie
set work_dir [file join $repo_root flow work openroad]
set result_dir [file join $repo_root flow results openroad]
set report_dir [file join $repo_root flow reports openroad]

proc assert_all_pg_iterms_connected {tag} {
  set block [ord::get_db_block]
  set open_pg 0
  foreach inst [$block getInsts] {
    foreach iterm [$inst getITerms] {
      set sig [[$iterm getMTerm] getSigType]
      if {($sig eq "POWER" || $sig eq "GROUND") && [$iterm getNet] == "NULL"} {
        incr open_pg
      }
    }
  }
  puts "PDE_${tag}_UNCONNECTED_PG_ITERMS=$open_pg"
  if {$open_pg != 0} {error "$tag has $open_pg unconnected PG terminals"}
}

read_db [file join $work_dir 10_place_v4.odb]
set db [ord::get_db]
set block [ord::get_db_block]
set replacement NULL
foreach lib [$db getLibs] {
  set candidate [$lib findMaster BUFFD2]
  if {$candidate != "NULL"} {set replacement $candidate}
}
if {$replacement == "NULL"} {error "BUFFD2 master is missing from loaded LEF"}

set swapped 0
foreach inst [$block getInsts] {
  if {[[$inst getMaster] getName] eq "CKBD8"} {
    if {![$inst swapMaster $replacement]} {
      error "Failed CKBD8-to-BUFFD2 remap for [$inst getName]"
    }
    incr swapped
  }
}
puts "PDE_PRECTS_CKBD8_TO_BUFFD2_SWAPPED=$swapped"
if {$swapped != 368} {error "Expected 368 pre-CTS CKBD8 cells, got $swapped"}

global_connect
assert_all_pg_iterms_connected PRECTS_REMAP
check_placement -verbose -disallow_one_site_gaps
foreach net {VDD VSS} {
  psm::clear_solvers
  check_power_grid -net $net \
    -error_file [file join $report_dir 19_remap_v1_${net}_open.rpt]
}

write_db [file join $work_dir 19_place_buffd2_v1.odb]
write_def [file join $result_dir 19_place_buffd2_v1.def]
write_verilog -include_pwr_gnd [file join $result_dir 19_place_buffd2_v1.v]
puts "PDE_PRECTS_BUFFD2_REMAP_V1_PASS"
exit
