# Physical-only OpenROAD import smoke test for the DC mapped netlist.
set repo_root /home/sxw/PDE/pdeMujunjie
set lef /ssd0/PDKs/TSMC65nm/STDCELL/std/STD_Cell/tcbn65lp_200b/Back_End/lef/tcbn65lp_200a/lef/tcbn65lp_6lmT1.lef
set netlist [file join $repo_root flow results dc pde_chip_top_safe.v]

read_lef $lef
read_verilog $netlist
link_design pde_chip_top_safe
report_design_area
puts "PDE_OPENROAD_IMPORT_PASS"
exit
