# Minimal isolated ICC2 implementation-license probe.
set REPO_ROOT /home/sxw/PDE/pdeMujunjie
set REF_NDM [file join $REPO_ROOT flow work icc2 ref tcbn65lp_6lmT1.ndm]
set NETLIST [file join $REPO_ROOT flow results dc pde_chip_top_safe.v]
set PROBE_LIB [file join $REPO_ROOT flow work icc2 license_probe.dlib]

if {[file exists $PROBE_LIB]} {
  error "Refusing to overwrite prior probe: $PROBE_LIB"
}
create_lib -use_technology_lib $REF_NDM -ref_libs [list $REF_NDM] $PROBE_LIB
read_verilog -top pde_chip_top_safe [list $NETLIST]
current_block pde_chip_top_safe
link_block
initialize_floorplan -control_type core -shape R -side_ratio {1.0 1.0} \
  -core_utilization 0.55 -core_offset 10.0
puts "PDE_ICC2_LICENSE_PROBE_PASS"
