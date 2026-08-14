# Stage 02 (full-chip variant): die-driven floorplan + IO pad ring + bond
# pads + boundary/tap cells + PG with ring-to-pad straps. Replaces
# s02_floorplan.tcl when PDE_TOP=pde_chip_pads; the core-only script stays
# untouched. Command syntax proven in local_runs/icc2_28nm_synprobe_20260814
# (probe rounds 1-3): -boundary keeps the die exact where -side_length snaps
# to the site grid; set_cell_location -coordinates is the post-orientation
# bbox lower-left; bond pads overlay their host pad by writing the origin +
# orientation attributes (both LEF frames are ORIGIN 0 0 in GDS coordinates).
source [file join [file dirname [file normalize [info script]]] pnr28_common.tcl]
open_design
if {!$IS_CHIP} {
  error "s02_floorplan_chip.tcl requires PDE_TOP=pde_chip_pads; core tops use s02_floorplan.tcl"
}

# ---- geometry constants (um) ------------------------------------------
# Die 685 square: core offset 135 = 110 pad depth + 25 routing channel,
# reproducing the R2 core (415 square, util ~0.84). Pad slots sit on a
# 0.5 um grid so every ring gap is composable from PFILLER{20,10,5,1,05}.
set DIE       685.0
set PAD_D     110.0
set CORE_OFF  135.0
set EDGE_FAR  [expr {$DIE - $PAD_D}]
set GUIDE_LEN [expr {$DIE - 2.0 * $PAD_D}]

initialize_floorplan -control_type die \
  -boundary [list [list 0 0] [list $DIE 0] [list $DIE $DIE] [list 0 $DIE]] \
  -core_offset $CORE_OFF -site_def core

# ---- edge transforms ---------------------------------------------------
# Pad cells are drawn die-edge at y=0, core-side pins at y=110 (20x110,
# ORIGIN 0 0). Orientation per edge and the local(u,v)->global map:
#   south R0, east R90, north R180, west R270 (LEF/DEF CCW rotations).
proc pad_coords {edge s} {
  global EDGE_FAR
  switch $edge {
    south { return [list $s 0] }
    north { return [list $s $EDGE_FAR] }
    east  { return [list $EDGE_FAR $s] }
    west  { return [list 0 $s] }
  }
}
proc pad_orient {edge} {
  switch $edge { south { return R0 } east { return R90 } north { return R180 } west { return R270 } }
}
proc pad_xform {edge s u v} {
  global DIE
  switch $edge {
    south { return [list [expr {$s + $u}] $v] }
    north { return [list [expr {$s + 20.0 - $u}] [expr {$DIE - $v}]] }
    east  { return [list [expr {$DIE - $v}] [expr {$s + $u}]] }
    west  { return [list $v [expr {$s + 20.0 - $u}]] }
  }
}
proc local_rect_to_global {edge s p1 p2} {
  set g1 [pad_xform $edge $s [lindex $p1 0] [lindex $p1 1]]
  set g2 [pad_xform $edge $s [lindex $p2 0] [lindex $p2 1]]
  set xs [lsort -real [list [lindex $g1 0] [lindex $g2 0]]]
  set ys [lsort -real [list [lindex $g1 1] [lindex $g2 1]]]
  return [list [lindex $xs 0] [lindex $ys 0] [lindex $xs 1] [lindex $ys 1]]
}
proc cell_bbox {inst} {
  set xs {}; set ys {}
  foreach p [get_attribute [get_cells $inst] boundary] {
    lappend xs [lindex $p 0]; lappend ys [lindex $p 1]
  }
  set xs [lsort -real $xs]; set ys [lsort -real $ys]
  return [list [lindex $xs 0] [lindex $ys 0] [lindex $xs end] [lindex $ys end]]
}
proc assert_bbox {inst exp} {
  set got [cell_bbox $inst]
  foreach g $got e $exp {
    if {abs($g - $e) > 0.001} {
      error "Placement assertion failed for $inst: got {$got} expected {$exp}"
    }
  }
}

# ---- ring table --------------------------------------------------------
# {instance master edge slot}; master "" = signal pad already in the
# netlist. Placement rules honored (RN 170A): a PVSS2/PVSS3 between every
# digital IO run and each corner; >=3 um filler between digital IO and
# PVDD1 (smallest such gap here is 46.5 um); bond pitch >= 50 um.
set RING_TABLE {
  {u_pvss2_w    PVSS2DGZ_H_G   west  138.5}
  {u_pad_sclk   {}             west  216.0}
  {u_pad_csn    {}             west  293.5}
  {u_pad_mosi   {}             west  371.0}
  {u_pad_miso   {}             west  448.5}
  {u_pvss3_w    PVSS3DGZ_H_G   west  526.0}
  {u_pvss3_n    PVSS3DGZ_H_G   north 138.5}
  {u_pad_clk    {}             north 216.0}
  {u_pad_rstn   {}             north 293.5}
  {u_pvdd2poc_n PVDD2POC_H_G   north 371.0}
  {u_pvdd2_n    PVDD2DGZ_H_G   north 448.5}
  {u_pvss2_n    PVSS2DGZ_H_G   north 526.0}
  {u_pvss3_es   PVSS3DGZ_H_G   east  133.0}
  {u_pvdd1_e    PVDD1DGZ_H_G   east  199.5}
  {u_pvss1_e    PVSS1DGZ_H_G   east  266.0}
  {u_pad_scanl  {}             east  332.5}
  {u_pad_scanv  {}             east  399.0}
  {u_pad_scano  {}             east  465.5}
  {u_pvss3_en   PVSS3DGZ_H_G   east  532.0}
  {u_pvdd1_s    PVDD1DGZ_H_G   south 295.0}
  {u_pvss1_s    PVSS1DGZ_H_G   south 365.0}
}

# static ring-table sanity: bond pitch >= 50 um per edge
foreach edge {west north east south} {
  set slots {}
  foreach row $RING_TABLE {
    if {[lindex $row 2] eq $edge} { lappend slots [lindex $row 3] }
  }
  set slots [lsort -real $slots]
  for {set i 1} {$i < [llength $slots]} {incr i} {
    set pitch [expr {[lindex $slots $i] - [lindex $slots $i-1]}]
    if {$pitch < 50.0} { error "Bond pitch $pitch < 50 um on $edge edge" }
  }
}

# ---- pad + corner placement -------------------------------------------
foreach row $RING_TABLE {
  lassign $row inst master edge slot
  if {$master ne ""} {
    create_cell $inst tphn28hpcpgv18/$master
  } elseif {[sizeof_collection [get_cells -quiet $inst]] == 0} {
    error "Signal pad instance missing from netlist: $inst"
  }
  set c [pad_coords $edge $slot]
  set_cell_location -coordinates $c -orientation [pad_orient $edge] \
    -fixed [get_cells $inst]
  lassign $c cx cy
  if {$edge eq "south" || $edge eq "north"} {
    assert_bbox $inst [list $cx $cy [expr {$cx + 20.0}] [expr {$cy + 110.0}]]
  } else {
    assert_bbox $inst [list $cx $cy [expr {$cx + 110.0}] [expr {$cy + 20.0}]]
  }
}
foreach {inst orient} {U_CORNER_BL R0 U_CORNER_BR R90 U_CORNER_TR R180 U_CORNER_TL R270} {
  create_cell $inst tphn28hpcpgv18/PCORNER_G
}
set_cell_location -coordinates [list 0 0] -orientation R0 -fixed [get_cells U_CORNER_BL]
set_cell_location -coordinates [list $EDGE_FAR 0] -orientation R90 -fixed [get_cells U_CORNER_BR]
set_cell_location -coordinates [list $EDGE_FAR $EDGE_FAR] -orientation R180 -fixed [get_cells U_CORNER_TR]
set_cell_location -coordinates [list 0 $EDGE_FAR] -orientation R270 -fixed [get_cells U_CORNER_TL]

# ---- bond pads: inserted at s07 AFTER the hard gates -------------------
# PAD50GU's CUP layout legitimately overlaps its host pad and neighbors
# (the overlap IS the bond connection), which check_lvs reads as >100k
# "shorts" if the cells are present during checking. s07_finish creates
# them right before write_gds, copying each host's origin+orientation.

# ---- IO guides + ring fillers -----------------------------------------
# One short guide PER GAP between pads/corners, so fillers can only land in
# gaps. A single full-edge guide makes create_io_filler_cells tile the whole
# edge, stacking fillers on the fixed pads (first run: 32 unfixable routing
# shorts + filler-vs-pad LVS shorts); -pad_cells association is rejected for
# create_cell-created power pads (DES-122 "not a pad cell").
# Guide lines run clockwise: left starts at its bottom end, top at its left
# end, right at its top end, bottom at its right end -- DES-123 otherwise.
foreach edge {west north east south} {
  set slots {}
  foreach row $RING_TABLE {
    if {[lindex $row 2] eq $edge} { lappend slots [lindex $row 3] }
  }
  set slots [lsort -real $slots]
  set gaps {}
  set pos $PAD_D
  foreach s $slots {
    if {$s > $pos + 0.001} { lappend gaps [list $pos $s] }
    set pos [expr {$s + 20.0}]
  }
  if {$pos < $EDGE_FAR - 0.001} { lappend gaps [list $pos $EDGE_FAR] }
  set i 0
  foreach g $gaps {
    lassign $g g0 g1
    set len [expr {$g1 - $g0}]
    switch $edge {
      west  { create_io_guide -name gap_${edge}_$i \
                -line [list [list 0 $g0] $len] -side left }
      north { create_io_guide -name gap_${edge}_$i \
                -line [list [list $g0 $DIE] $len] -side top }
      east  { create_io_guide -name gap_${edge}_$i \
                -line [list [list $DIE $g1] $len] -side right }
      south { create_io_guide -name gap_${edge}_$i \
                -line [list [list $g1 0] $len] -side bottom }
    }
    incr i
  }
  puts "PDE28: $edge gap guides: $i"
}
create_io_filler_cells -prefix PDE_IOFIL_ \
  -reference_cells {PFILLER20_G PFILLER10_G PFILLER5_G PFILLER1_G PFILLER05_G}
puts "PDE28: io fillers inserted: [sizeof_collection [get_cells -quiet PDE_IOFIL_*]]"

# ---- ring continuity audit --------------------------------------------
# The IO power buses (VDDPST/VSSPST/POC) connect purely by abutment, so a
# single gap breaks the ring. Assert gapless coverage of all four edges by
# PAD/SPACER/ENDCAP cells (IO masters: P*_G; bond pad PAD50GU excluded).
proc audit_ring_edge {edge rptfd} {
  global DIE
  set spans {}
  foreach_in_collection c [get_cells -quiet {u_pad_* u_pv* U_CORNER_* PDE_IOFIL_*}] {
    set ref [get_attribute $c ref_name]
    set nm  [get_attribute $c full_name]
    if {![string match {P*_G} $ref]} { continue }
    lassign [cell_bbox $nm] llx lly urx ury
    switch $edge {
      west  { if {$llx > 0.001} continue
              lappend spans [list $lly $ury $nm] }
      east  { if {$urx < $DIE - 0.001} continue
              lappend spans [list $lly $ury $nm] }
      south { if {$lly > 0.001} continue
              lappend spans [list $llx $urx $nm] }
      north { if {$ury < $DIE - 0.001} continue
              lappend spans [list $llx $urx $nm] }
    }
  }
  set spans [lsort -real -index 0 $spans]
  set pos 0.0
  set gaps 0
  foreach sp $spans {
    lassign $sp lo hi nm
    if {$lo > $pos + 0.001} {
      puts $rptfd "RING_GAP $edge: [format %.3f $pos] .. [format %.3f $lo]"
      incr gaps
    }
    if {$lo < $pos - 0.001} {
      puts $rptfd "RING_OVERLAP $edge: [format %.3f $lo] .. [format %.3f $pos] ($nm)"
      incr gaps
    }
    if {$hi > $pos} { set pos $hi }
    puts $rptfd "RING_CELL $edge [format %8.3f $lo] [format %8.3f $hi] $nm"
  }
  if {$pos < $DIE - 0.001} {
    puts $rptfd "RING_GAP $edge: [format %.3f $pos] .. [format %.3f $DIE]"
    incr gaps
  }
  return $gaps
}
set ring_rpt [open [file join $REPORT_DIR s02_ring_audit.rpt] w]
set ring_gaps 0
foreach edge {west north east south} {
  incr ring_gaps [audit_ring_edge $edge $ring_rpt]
}
puts $ring_rpt "RING_AUDIT total_gaps=$ring_gaps"
close $ring_rpt
puts "PDE28: ring audit gaps=$ring_gaps"
if {$ring_gaps != 0} { error "IO ring has $ring_gaps gap(s); see s02_ring_audit.rpt" }

# ---- boundary + tap cells (core rows, unchanged from s02) -------------
require_command create_boundary_cells
create_boundary_cells \
  -left_boundary_cell  [get_lib_cells */BOUNDARY_LEFTBWP40P140] \
  -right_boundary_cell [get_lib_cells */BOUNDARY_RIGHTBWP40P140] \
  -prefix PDE_BND_
require_command create_tap_cells
create_tap_cells -lib_cell [get_lib_cells */TAPCELLBWP40P140] \
  -distance 60 -pattern every_row -prefix PDE_TAP_
redirect -file [file join $REPORT_DIR s02_tap_boundary.rpt] {
  puts "TAP  instances: [sizeof_collection [get_cells -quiet PDE_TAP_*]]"
  puts "BND  instances: [sizeof_collection [get_cells -quiet PDE_BND_*]]"
}

# ---- PG ----------------------------------------------------------------
# Core VDD/VSS ring + M1 follow-pin rails: same proven commands as the
# core-only s02. New chip-level nets: VDDPST/VSSPST (IO 1.8 V rails) and
# POC (power-on-control feedthrough) exist only through the pad ring bus.
if {[sizeof_collection [get_nets -quiet VDD]] == 0} {
  create_net -power VDD
} else { set_attribute [get_nets VDD] net_type power }
if {[sizeof_collection [get_nets -quiet VSS]] == 0} {
  create_net -ground VSS
} else { set_attribute [get_nets VSS] net_type ground }
create_net -power  VDDPST
create_net -ground VSSPST
create_net -power  POC
connect_named_pg_pins

foreach pg_command {create_pg_ring_pattern create_pg_std_cell_conn_pattern set_pg_strategy compile_pg create_pg_strap} {
  require_command $pg_command
}
create_pg_ring_pattern PDE_CORE_RING \
  -horizontal_layer M9 -vertical_layer M8 \
  -horizontal_width 1.6 -vertical_width 1.6 \
  -horizontal_spacing 0.8 -vertical_spacing 0.8
set_pg_strategy PDE_CORE_RING_STRATEGY -core \
  -pattern {{name: PDE_CORE_RING} {nets: {VDD VSS}} {offset: {2.0 2.0}}}
compile_pg -strategies {PDE_CORE_RING_STRATEGY}
create_pg_std_cell_conn_pattern PDE_STDCELL_RAILS \
  -layers {M1} -mark_as_follow_pin true
set_pg_strategy PDE_STDCELL_RAIL_STRATEGY -core \
  -pattern {{name: PDE_STDCELL_RAILS} {nets: {VDD VSS}}} \
  -extension {{stop: innermost_ring}}
compile_pg -strategies {PDE_STDCELL_RAIL_STRATEGY}
connect_named_pg_pins

# ---- ring-to-pad straps for the four core power pads ------------------
# The power pads' core-supply pin (VDD/VSS) is the M5-M7 strip at local
# (1.975,70.05)-(18.025,73.05) -- the same rect the bond pad lands on, and
# the bond pad's internal VIA7/VIA8 arrays tie that strip to its M8/M9
# plates. So the strap recipe is: narrow M8 (south) / M9 (east) fingers
# from over the plate region out to the core ring. create_pg_strap
# auto-vias each finger to its net's ring segment at the crossing (probe
# rounds 8-17: this is the ONLY via path this W-2024.09 build accepts --
# standalone create_pg_vias never commits onto PAD-class lib cell pins,
# and the IO pads' full-cell M1-M7 OBS kills every via attempt at the pin
# itself). Finger-to-pin continuity therefore runs through the bond pad
# plate (mask-level metal union, verified in GDS; Calibre LVS is the
# arbiter). check_pg_connectivity cannot see through the pinless COVER
# bond pad, so ring cells stay "floating" in that report -- known tool
# model limitation, documented, not gated.
proc strap_vias_in {net x1 y1 x2 y2} {
  set n 0
  foreach_in_collection v [get_vias -quiet -of_objects [get_nets $net]] {
    set bb [get_attribute $v bbox]
    set vx [lindex $bb 0 0]; set vy [lindex $bb 0 1]
    if {$vx >= $x1 && $vx <= $x2 && $vy >= $y1 && $vy <= $y2} { incr n }
  }
  return $n
}
foreach {inst net edge slot} {
  u_pvdd1_s VDD south 295.0
  u_pvss1_s VSS south 365.0
  u_pvdd1_e VDD east  199.5
  u_pvss1_e VSS east  266.0
} {
  set f_lo [expr {$slot + 4.0}]
  set f_hi [expr {$slot + 16.0}]
  if {$edge eq "south"} {
    create_pg_strap -layer M8 -direction vertical -width 1.6 -net $net \
      -start $f_lo -stop $f_hi -pitch 4 -low_end 70.5 -high_end 136
    set ring_vias [strap_vias_in $net [expr {$slot + 2}] 125 [expr {$slot + 18}] 140]
  } else {
    create_pg_strap -layer M9 -direction horizontal -width 1.6 -net $net \
      -start $f_lo -stop $f_hi -pitch 4 -low_end 548 -high_end 618
    set ring_vias [strap_vias_in $net 545 [expr {$slot + 2}] 560 [expr {$slot + 18}]]
  }
  if {$ring_vias == 0} { error "Strap for $inst ($net, $edge) has no ring vias" }
  puts "PDE28: strap $net <- $inst ($edge) ring_vias=$ring_vias"
}

# ---- PAD_* port terminals ---------------------------------------------
# Terminal geometry = the pad's PAD pin rect on M7 (same rect as the bond
# pad landing strip). Pin and terminal coincide, so PAD_* nets need no
# routing, and write_gds -output_pin all drops the port text on the metal
# under the bond pad (round-1 s07b pin-count lesson, applied forward).
foreach {inst port} {
  u_pad_clk  PAD_CLK   u_pad_rstn PAD_RSTN u_pad_sclk PAD_SCLK
  u_pad_csn  PAD_CSN   u_pad_mosi PAD_MOSI u_pad_miso PAD_MISO
  u_pad_scano PAD_SCAN_OUT u_pad_scanv PAD_SCAN_VALID u_pad_scanl PAD_SCAN_LAST
} {
  set edge ""; set slot ""
  foreach row $RING_TABLE {
    if {[lindex $row 0] eq $inst} { set edge [lindex $row 2]; set slot [lindex $row 3] }
  }
  if {$edge eq ""} { error "Pad $inst missing from RING_TABLE" }
  lassign [local_rect_to_global $edge $slot {1.975 70.05} {18.025 73.05}] tx1 ty1 tx2 ty2
  create_terminal -port $port -layer M7 \
    -boundary [list [list $tx1 $ty1] [list $tx2 $ty2]]
  puts "PDE28: terminal $port on M7 ([format %.3f $tx1],[format %.3f $ty1])-([format %.3f $tx2],[format %.3f $ty2])"
}

# ---- checks ------------------------------------------------------------
redirect -file [file join $REPORT_DIR s02_chip_legality.rpt] { check_legality -verbose }
redirect -file [file join $REPORT_DIR s02_chip_io_placement.rpt] {
  catch { check_io_placement }
}
redirect -file [file join $REPORT_DIR s02_pg.rpt] {
  puts "PG shapes: [sizeof_collection [get_shapes -quiet -of_objects [get_nets {VDD VSS}]]]"
  check_pg_connectivity -nets [get_nets {VDD VSS VDDPST VSSPST POC}] \
    -check_std_cell_pins none -check_block_pins none -check_pad_pins all
}
write_def [file join $REPORT_DIR s02_chip.def]

stage_done s02_floorplan_chip
exit
