# Provisional block-level timing constraints for physical implementation.
# The 10 ns target matches the validated VCS/DC baseline; replace it with the
# product requirement and rerun every stage before signoff.

create_clock -name core_clk -period 10.000 [get_ports clk]
set_clock_uncertainty 0.200 [get_clocks core_clk]
set_clock_transition 0.100 [get_clocks core_clk]

set pde_data_inputs [remove_from_collection [all_inputs] [get_ports {clk rst_n}]]
if {[sizeof_collection $pde_data_inputs] > 0} {
  set_input_delay 1.000 -clock core_clk $pde_data_inputs
  set_input_transition 0.100 $pde_data_inputs
}
if {[sizeof_collection [all_outputs]] > 0} {
  set_output_delay 1.000 -clock core_clk [all_outputs]
  set_load 0.050 [all_outputs]
}

set_false_path -from [get_ports rst_n]
set_max_transition 0.500 [current_design]
set_max_fanout 32 [current_design]
