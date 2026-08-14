# Stage 06b (R2): close open nets left after the s06 DRC repair pass.
# Round-2 finding: the s06 gate counts detail DRC totals; check_lvs opens are
# only counted at s07 -- two signal nets arrived open. Repair with eco
# routing (open-net driven), judged by check_lvs's own totals.
source [file join [file dirname [file normalize [info script]]] pnr28_common.tcl]
open_design
source $ANTENNA_TCL

# Chip run finding: cells inserted after s02 (CTS buffers, route_opt hold
# cells -- 44k physical PG pins) are not on the PG nets yet; check_lvs then
# flags every pin-over-rail overlap as a short (200-cap hit). Reconnect
# before judging. Core-only flow is left byte-identical (s07 reconnects
# there after filler insertion, same idiom).
if {$IS_CHIP} { connect_named_pg_pins }

for {set i 1} {$i <= 3} {incr i} {
  route_eco -open_net_driven true
  save_block
  if {$IS_CHIP} {
    lassign [chip_lvs_counts] short_total open_total bad_open_names
    puts "PDE28_S06B_WAIVED bad_opens=$bad_open_names"
  } else {
    redirect -variable lvs { check_lvs -checks all -max_errors 200 }
    set open_total -1; set short_total -1
    regexp {Total number of open nets is\s+(\d+)} $lvs -> open_total
    regexp {Total number of short violations is\s+(\d+)} $lvs -> short_total
  }
  redirect -variable chk { check_routes -open_net true -drc true -antenna true }
  set drc_total -1
  regexp {TOTAL VIOLATIONS =\s+(\d+)} $chk -> drc_total
  puts "PDE28_S06B iter=$i opens=$open_total shorts=$short_total drc=$drc_total"
  if {$open_total == 0 && $short_total == 0 && $drc_total == 0} break
}
save_block
save_lib
redirect -file [file join $REPORT_DIR s06b_lvs.rpt] {
  check_lvs -checks all -max_errors 200
}
redirect -file [file join $REPORT_DIR s06b_routes.rpt] {
  check_routes -open_net true -drc true -antenna true
}
if {$open_total != 0 || $short_total != 0 || $drc_total != 0} {
  error "s06b open repair unconverged: opens=$open_total shorts=$short_total drc=$drc_total"
}
stage_done s06b_open_fix
exit
