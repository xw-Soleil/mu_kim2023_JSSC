foreach command {repair_antennas check_antennas pin_access detailed_route filler_placement check_placement report_floating_nets report_design_area write_abstract_lef} {
  puts "===== HELP $command ====="
  help $command
}
exit
