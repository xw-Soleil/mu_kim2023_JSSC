# ICC2 Library Manager flow for the TSMC65LP RVT 6LM-T1 standard-cell NDM.
# Run with: icc2_lm_shell -f flow/icc2/create_ndm.tcl

proc env_or_default {name fallback} {
  if {[info exists ::env($name)] && [string trim $::env($name)] ne ""} {
    return $::env($name)
  }
  return $fallback
}

proc require_regular_file {path description} {
  if {![file exists $path] || ![file isfile $path] || ![file readable $path]} {
    error "$description is missing or unreadable: $path"
  }
}

set SCRIPT_DIR [file dirname [file normalize [info script]]]
set REPO_ROOT [file normalize [env_or_default PDE_REPO_ROOT \
  [file join $SCRIPT_DIR .. ..]]]

set RVT_ROOT "/ssd0/PDKs/TSMC65nm/STDCELL/std/STD_Cell/tcbn65lp_200b"
set RVT_BE   [file join $RVT_ROOT Back_End]
set RVT_MW   [file join $RVT_BE milkyway tcbn65lp_200a]
set RVT_CCS  [file join $RVT_ROOT Front_End timing_power_noise CCS]

set TECH_FILE [env_or_default PDE_TECH_FILE \
  [file join $RVT_MW techfiles tsmcn65_6lmT1.tf]]
set CELL_LEF [env_or_default PDE_CELL_LEF \
  [file join $RVT_BE lef tcbn65lp_200a lef tcbn65lp_6lmT1.lef]]
set CELL_GDS [env_or_default PDE_CELL_GDS \
  [file join $RVT_BE gds tcbn65lp_200a tcbn65lp.gds]]
set GDS_MAP [env_or_default PDE_GDS_MAP \
  [file join $RVT_MW gdsout_3X1Z.map]]
set WC_DB [env_or_default PDE_TARGET_DB \
  [file join $RVT_CCS tcbn65lpwc_ccs.db]]
set BC_DB [env_or_default PDE_BC_DB \
  [file join $RVT_CCS tcbn65lpbc_ccs.db]]

set WORKSPACE_NAME [env_or_default PDE_REF_WORKSPACE tcbn65lp_6lmT1]
set PHYSICAL_LIB_NAME [env_or_default PDE_REF_PHYSICAL_LIB tcbn65lp_6lmT1_physical]
set REF_NDM [file normalize [env_or_default PDE_REF_NDM \
  [file join $REPO_ROOT flow work icc2 ref tcbn65lp_6lmT1.ndm]]]
set REPORT_DIR [file join $REPO_ROOT flow reports icc2]

foreach item [list \
  [list $TECH_FILE "6LM-T1 technology file"] \
  [list $CELL_LEF "RVT 6LM-T1 LEF"] \
  [list $CELL_GDS "RVT standard-cell GDS"] \
  [list $GDS_MAP "RVT GDS layer map"] \
  [list $WC_DB "RVT WC CCS database"] \
  [list $BC_DB "RVT BC CCS database"]] {
  require_regular_file [lindex $item 0] [lindex $item 1]
}

file mkdir [file dirname $REF_NDM]
file mkdir $REPORT_DIR
if {[file exists $REF_NDM]} {
  error "Refusing to overwrite existing reference NDM: $REF_NDM"
}

puts "PDE_NDM: technology=$TECH_FILE"
puts "PDE_NDM: LEF=$CELL_LEF"
puts "PDE_NDM: GDS=$CELL_GDS"
puts "PDE_NDM: WC=$WC_DB"
puts "PDE_NDM: BC=$BC_DB"

create_workspace -technology $TECH_FILE -flow normal $WORKSPACE_NAME

# FILL1/2/4/8/16/32/64 are physical-only in this delivery.  Without this
# documented Library Manager option they are discarded by the normal flow.
set_app_options -name lib.workspace.keep_all_physical_cells -value true
# Layout views are not retained in the committed NDM unless this is enabled.
set_app_options -name lib.workspace.save_layout_views -value true

# These labels are consumed explicitly by pnr.tcl via set_process_label.
read_db -process_label WC [list $WC_DB]
read_db -process_label BC [list $BC_DB]
read_lef -library $PHYSICAL_LIB_NAME -preserve_lef_cell_site [list $CELL_LEF]

# Merge GDS geometry into the same physical library as the LEF frames. Without
# an explicit library and update action, all 855 same-name blocks conflict and
# the workspace keeps only the LEF versions (LM-058).
read_gds -library $PHYSICAL_LIB_NAME -merge_action update \
  -layer_map $GDS_MAP -layer_map_format icc_default [list $CELL_GDS]

redirect -file [file join $REPORT_DIR create_ndm.check_workspace.rpt] {
  check_workspace
}
commit_workspace -output $REF_NDM

puts "PDE_NDM_DONE ref_ndm=$REF_NDM"
