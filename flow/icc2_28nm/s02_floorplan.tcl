# Stage 02 (E.2-E.4): floorplan + placed pins + boundary/tap cells + PG.
source [file join [file dirname [file normalize [info script]]] pnr28_common.tcl]
open_design

# E.2: square core, 55% utilization (65nm-comparable), explicit core site.
# -site_def is mandatory here: the NDM carries both "unit" (tf tile) and
# "core" (LEF site); the 65nm line documented initialize_floorplan defaulting
# to the wrong site when left implicit.
initialize_floorplan -control_type core -shape R -side_ratio {1.0 1.0} \
  -core_utilization 0.55 -core_offset 10.0 -site_def core
# W-2024.09 takes -pin_spacing in routing tracks (integer), not um.
set_block_pin_constraints -self -allowed_layers [get_layers {M3 M4}] \
  -corner_keepout_num_tracks 2 -pin_spacing 2 -allow_feedthroughs false
place_pins -self

# E.2 gate: every port must be placed. DEF PINS section is the arbiter.
set pin_def [file join $REPORT_DIR s02_pins.def]
write_def $pin_def
redirect -file [file join $REPORT_DIR s02_pin_placement.rpt] {
  report_pin_placement -self
}

# E.3: boundary cells first, then tap cells.
# Spacing basis: appnote quotes DRM LUP.6 R=30 um single-pickup radius;
# S = sqrt(R^2 - H^2) with this library's H=0.9 um row height gives
# S=29.986, 2S=59.97 -- the appnote's own recommendation "every 60 um"
# stands for bwp40p140 (their H=2.52 example gives 59.79 -> 60 as well).
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
  set xs {}
  foreach_in_collection t [get_cells -quiet PDE_TAP_*] {
    set bb [get_attribute $t boundary_bounding_box]
    lappend xs [format %.2f [lindex $bb 0 0]]
  }
  puts "TAP distinct column x (sorted): [lsort -real -unique $xs]"
}

# E.4: named PG nets, follow-pin rails on M1, ring on the thick Mr pair
# (M9 horizontal / M8 vertical per HVH directions). Widths are the same
# implementation baseline the 65nm flow used; not an IR/EM-signed grid.
if {[sizeof_collection [get_nets -quiet VDD]] == 0} {
  create_net -power VDD
} else { set_attribute [get_nets VDD] net_type power }
if {[sizeof_collection [get_nets -quiet VSS]] == 0} {
  create_net -ground VSS
} else { set_attribute [get_nets VSS] net_type ground }
connect_named_pg_pins

foreach pg_command {create_pg_ring_pattern create_pg_std_cell_conn_pattern set_pg_strategy compile_pg} {
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

redirect -file [file join $REPORT_DIR s02_pg.rpt] {
  puts "PG shapes: [sizeof_collection [get_shapes -quiet -of_objects [get_nets {VDD VSS}]]]"
  check_pg_connectivity -nets [get_nets {VDD VSS}] \
    -check_std_cell_pins none -check_block_pins none -check_pad_pins none
}

stage_done s02_floorplan
exit
