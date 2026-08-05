set repo_root /home/sxw/PDE/pdeMujunjie
set lef /ssd0/PDKs/TSMC65nm/STDCELL/std/STD_Cell/tcbn65lp_200b/Back_End/lef/tcbn65lp_200a/lef/tcbn65lp_6lmT1.lef
set liberty [file join $repo_root flow work openroad tcbn65lpwc_openroad_impl_sta.lib]
set netlist [file join $repo_root flow results dc pde_chip_top_safe.v]
set sdc [file join $repo_root flow openroad pde_chip_top_safe_v2.sdc]

read_liberty $liberty
read_lef $lef
read_verilog $netlist
link_design pde_chip_top_safe
read_sdc $sdc
report_clocks
report_checks -path_delay max -group_count 3
puts "PDE_OPENROAD_SDC_PASS"
exit
