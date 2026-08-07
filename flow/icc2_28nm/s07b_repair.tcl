# Stage 07b: repair pass. Root causes found by the first finish attempt:
# (1) s06 route_opt left M2 signal shorts + detail DRC (checked only at s07 --
#     the s06 stage had no check_routes; closed here with incremental detail
#     route iterations);
# (2) VDD/VSS ports had no physical terminal (the 65nm eco02 lesson block was
#     not carried into s02; applied here on the M9 ring bottom segments).
source [file join [file dirname [file normalize [info script]]] pnr28_common.tcl]
open_design
source $ANTENNA_TCL

# (2) supply terminals: 1.6 um window at the x-center of the bottommost
# horizontal M9 ring segment of each PG net (65nm-proven geometry, layer
# retargeted from M5 to this stack's horizontal ring layer M9).
foreach pg_port {VDD VSS} {
  if {[sizeof_collection [get_ports -quiet $pg_port]] == 0} {
    create_port -direction inout $pg_port
  }
  set existing [get_terminals -quiet -of_objects [get_ports $pg_port]]
  if {[sizeof_collection $existing] > 0} {
    puts "PDE28: $pg_port terminal already present, skipping"
    continue
  }
  set ring_shapes [get_shapes -quiet -of_objects [get_nets $pg_port] \
    -filter "layer_name==M9 && shape_use==ring"]
  if {[sizeof_collection $ring_shapes] == 0} {
    error "No M9 ring shape found for $pg_port terminal creation"
  }
  set term_lly ""
  foreach_in_collection ring_shape $ring_shapes {
    set bb [get_attribute $ring_shape bbox]
    set llx [lindex $bb 0 0]; set lly [lindex $bb 0 1]
    set urx [lindex $bb 1 0]; set ury [lindex $bb 1 1]
    if {[expr {$urx - $llx}] <= [expr {$ury - $lly}]} continue
    if {$term_lly eq "" || $lly < $term_lly} {
      set term_lly $lly; set term_ury $ury
      set term_cx [expr {($llx + $urx) / 2.0}]
    }
  }
  if {$term_lly eq ""} { error "No horizontal M9 ring segment for $pg_port" }
  create_terminal -port $pg_port -layer M9 -boundary \
    [list [list [expr {$term_cx - 0.8}] $term_lly] \
          [list [expr {$term_cx + 0.8}] $term_ury]]
  puts "PDE28: $pg_port terminal on M9 at x=$term_cx"
}

# (1) incremental repair until DRC converges (max 3 iterations, judged by the
# checker's own total).
for {set i 1} {$i <= 3} {incr i} {
  route_detail -incremental true
  save_block
  redirect -variable chk { check_routes -open_net true -drc true -antenna true }
  set drc_total -1
  regexp {TOTAL VIOLATIONS =\s+(\d+)} $chk -> drc_total
  puts "PDE28_REPAIR iter=$i drc_total=$drc_total"
  if {$drc_total == 0} break
}
save_block
save_lib
redirect -file [file join $REPORT_DIR s07b_routes.rpt] {
  check_routes -open_net true -drc true -antenna true
}
redirect -file [file join $REPORT_DIR s07b_lvs.rpt] {
  check_lvs -checks all -max_errors 200
}
stage_done s07b_repair
exit
