foreach command {
  set_voltage_domain check_placement report_floating_nets
  report_tns report_wns report_checks set_propagated_clock write_sdc
  set_global_routing_layer_adjustment pin_access
} {
  puts "PDE_HELP_BEGIN $command"
  help $command
  puts "PDE_HELP_END $command"
}
exit
