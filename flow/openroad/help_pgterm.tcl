foreach command {place_pin create_voltage_domain add_global_connection global_connect check_power_grid analyze_power_grid create_port make_io_bump_array assign_io_bump} {
  puts "===== HELP $command ====="
  if {[catch {help $command} result]} {
    puts "UNAVAILABLE: $result"
  }
}
exit
