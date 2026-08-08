# Stage 01 (E.1): design library, netlist link, MMMC, parasitic tech,
# in-flow antenna rules. Checkpoint: saved block "setup".
source [file join [file dirname [file normalize [info script]]] pnr28_common.tcl]

foreach item [list \
  [list $NETLIST "DC28 gate-level netlist"] \
  [list $SDC "DC28 SDC"] \
  [list $TLU_WORST "rcworst TLU+"] \
  [list $TLU_BEST "rcbest TLU+"] \
  [list $ANTENNA_TCL "PRTF antenna rule tcl"] \
  [list $GDS_MAP "PRTF gdsout layer map"]] {
  require_regular_file [lindex $item 0] [lindex $item 1]
}
if {[file exists $DESIGN_LIB]} {
  error "Refusing to overwrite existing ICC2 design library: $DESIGN_LIB"
}

puts "PDE28: netlist=$NETLIST"
puts "PDE28: ref_ndm=$REF_NDM"
create_lib -use_technology_lib $REF_NDM -ref_libs [list $REF_NDM] $DESIGN_LIB
read_verilog -top $TOP [list $NETLIST]
current_block $TOP
link_block

redirect -file [file join $REPORT_DIR s01_link_check.rpt] {
  check_design -checks {netlist unbound}
}

# In-flow antenna rules: the PRTF tcl carries a native icc2_shell branch
# (current_lib / define_antenna_rule); rules are stored in the design lib.
source $ANTENNA_TCL
redirect -file [file join $REPORT_DIR s01_antenna_rules.rpt] {
  report_antenna_rules
}

# MMMC: FUNC mode, WC=ssg0p9vm40c (0.9 V, -40 C, rcworst),
# BC=ffg0p99vm40c (0.99 V, -40 C, rcbest). Labels were stamped into the NDM
# at read_db time (65nm recipe). Per-scenario read_sdc: the mode-context
# import pitfall was root-caused on W-2024.09 in the 65nm line.
remove_scenarios -all
remove_modes -all
remove_corners -all
create_mode FUNC
create_corner WC
create_corner BC
create_scenario -mode FUNC -corner WC -name FUNC_WC
create_scenario -mode FUNC -corner BC -name FUNC_BC
foreach sdc_scenario {FUNC_WC FUNC_BC} {
  current_scenario $sdc_scenario
  read_sdc $SDC
  set_clock_uncertainty -setup 0.2 [all_clocks]
  set_clock_uncertainty -hold 0.05 [all_clocks]
}
set_process_label WC -corners [get_corners WC]
set_process_label BC -corners [get_corners BC]
set_temperature -40 -corners [get_corners WC]
set_temperature -40 -corners [get_corners BC]
set_voltage 0.9  -min 0.9  -corners [get_corners WC]
set_voltage 0.99 -min 0.99 -corners [get_corners BC]

# ITF conductor names (M1..M9, AP) match the tf layer names, so no layer map
# is passed; the command fails loudly if any layer stays unmapped.
read_parasitic_tech -tlup $TLU_WORST -name RC_WORST
read_parasitic_tech -tlup $TLU_BEST  -name RC_BEST
set_parasitic_parameters -corners [get_corners WC] \
  -early_spec RC_WORST -late_spec RC_WORST
set_parasitic_parameters -corners [get_corners BC] \
  -early_spec RC_BEST -late_spec RC_BEST

set_scenario_status [get_scenarios FUNC_WC] \
  -active true -setup true -hold false \
  -max_transition true -max_capacitance true \
  -leakage_power true -dynamic_power true
set_scenario_status [get_scenarios FUNC_BC] \
  -active true -setup false -hold true \
  -max_transition true -max_capacitance true \
  -leakage_power false -dynamic_power false
current_scenario FUNC_WC

# Analysis mode: CPPR on; OCV here is min/max corner bounding without derate.
# [28nm AOCV hook - intentionally NOT enabled in this baseline]
# sbocv .aocvm tables live under
#   $PDE28_PDK_ROOT/tcbn28hpcplusbwp40p140_180b/TSMCHOME/digital/Front_End/SBOCV/
# attach via read_aocvm + set_timing_derate -aocvm once the baseline is banked.
set_app_options -name time.remove_clock_reconvergence_pessimism -value true

# R2 (K.2, user-confirmed): the round-1 fanout-40 HFS buffers came from this
# option's system default of 40 (measured on W-2024.09), not from DC. Align
# optimization fanout with the SDC's set_max_fanout 32; the SDC is untouched.
set_app_options -name opt.common.max_fanout -value 32

# Signal routing window M1..M6; M8/M9 (thick Mr pair) reserved for the ring.
foreach layer_name {M1 M2 M3 M4 M5 M6 M8 M9} {
  if {[sizeof_collection [get_layers -quiet $layer_name]] == 0} {
    error "Required routing layer missing from 1P9M tech: $layer_name"
  }
}
set_ignored_layers -min_routing_layer M1 -max_routing_layer M6

# Antenna fixing + real diode insertion (diode master verified in the NDM).
set ANTENNA_CELLS [require_one_lib_cell ANTENNABWP40P140]
set_lib_cell_purpose -include optimization $ANTENNA_CELLS
set_app_options -name route.detail.antenna -value true
set_app_options -name route.detail.diode_libcell_names -value {ANTENNABWP40P140}
set_app_options -name route.detail.insert_diodes_during_routing -value true
set_app_options -name route.detail.antenna_fixing_preference -value use_diodes
set_app_options -name route.detail.diode_insertion_mode -value new

stage_done s01_setup
exit
