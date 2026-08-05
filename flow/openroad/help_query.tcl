# Version-specific command signatures used while bringing up this flow.
foreach command {
  initialize_floorplan make_tracks place_pins global_placement
  detailed_placement set_routing_layers set_wire_rc
  clock_tree_synthesis repair_clock_nets estimate_parasitics report_cts
  global_route detailed_route check_antennas repair_antennas
  add_global_connection global_connect define_pdn_grid add_pdn_ring
  add_pdn_stripe add_pdn_connect pdngen filler_placement
  write_def write_verilog write_spef write_db report_design_area
} {
  puts "PDE_HELP_BEGIN $command"
  help $command
  puts "PDE_HELP_END $command"
}
exit
