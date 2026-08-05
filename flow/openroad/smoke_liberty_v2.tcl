# Parse and link the finalized implementation-only Liberty view.
set repo_root /home/sxw/PDE/pdeMujunjie
set lef /ssd0/PDKs/TSMC65nm/STDCELL/std/STD_Cell/tcbn65lp_200b/Back_End/lef/tcbn65lp_200a/lef/tcbn65lp_6lmT1.lef
set liberty [file join $repo_root flow work openroad tcbn65lpwc_openroad_impl_sta.lib]
set netlist [file join $repo_root flow results dc pde_chip_top_safe.v]

read_liberty $liberty
read_lef $lef
read_verilog $netlist
link_design pde_chip_top_safe
report_design_area
puts "PDE_OPENROAD_LIBERTY_IMPORT_PASS"
exit
