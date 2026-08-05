# OpenSTA-compatible provisional constraints for physical implementation.
create_clock -name core_clk -period 10.000 [get_ports clk]
set_clock_uncertainty 0.200 [get_clocks core_clk]
set_clock_transition 0.100 [get_clocks core_clk]

set pde_data_inputs [get_ports {cfg_valid cfg_write cfg_addr[*] cfg_wdata[*]}]
set_input_delay 1.000 -clock core_clk $pde_data_inputs
set_input_transition 0.100 $pde_data_inputs
set_output_delay 1.000 -clock core_clk [all_outputs]
set_load 0.050 [all_outputs]

# rst_n is an asynchronous assertion path.  Recovery/removal must be checked
# with the qualified foundry library after CTS; it is excluded from data setup.
set_false_path -from [get_ports rst_n]
