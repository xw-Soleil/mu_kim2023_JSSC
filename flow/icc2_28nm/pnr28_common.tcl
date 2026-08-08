# Shared setup for the staged 28nm ICC2 flow. Origin: structure and command
# forms proven by flow/icc2/pnr.tcl + flow/local/pnr_local.tcl on this exact
# ICC2 build (W-2024.09); 65nm line untouched. Every stage script sources
# this, then operates on the design library under $PDE28_ICC2_OUTPUT_ROOT.

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

proc require_command {name} {
  if {[llength [info commands $name]] == 0} {
    error "Required ICC2 command is unavailable in this release: $name"
  }
}

proc require_one_lib_cell {master} {
  set matches [get_lib_cells -quiet "*/$master"]
  if {[sizeof_collection $matches] == 0} {
    error "Required library master is absent from the NDM: $master"
  }
  return $matches
}

proc connect_named_pg_pins {} {
  set vdd_pins [get_pins -hierarchical -physical_context -quiet */VDD]
  set vss_pins [get_pins -hierarchical -physical_context -quiet */VSS]
  if {[sizeof_collection $vdd_pins] == 0} { error "No physical VDD pins found" }
  if {[sizeof_collection $vss_pins] == 0} { error "No physical VSS pins found" }
  connect_pg_net -net VDD $vdd_pins
  connect_pg_net -net VSS $vss_pins
}

set_host_options -max_cores 8

set REPO_ROOT [file normalize [env_or_default PDE_REPO_ROOT \
  [file join [file dirname [file normalize [info script]]] .. ..]]]
set TOP [env_or_default PDE_TOP pde_chip_top_safe]
set PDK28_ROOT [env_or_default PDE28_PDK_ROOT [file join $::env(HOME) pdk tsmc28hpcplus]]
set BRINGUP [env_or_default PDE28_BRINGUP \
  [file join $::env(HOME) code DigitalIC PDE pdk28_bringup]]

set REF_NDM  [env_or_default PDE28_REF_NDM \
  [file join $BRINGUP ndm tcbn28hpcplusbwp40p140_HVH_t.ndm]]
set DC_ROOT  [env_or_default PDE28_DC_RESULTS \
  [file join $REPO_ROOT flow local_runs dc28_bringup_20260807 dc results]]
set NETLIST  [file join $DC_ROOT ${TOP}.v]
set SDC      [file join $DC_ROOT ${TOP}.sdc]

set TLU_DIR [env_or_default PDE28_TLU_DIR \
  [file join $PDK28_ROOT {RC_TLUplus_cln28hpc+_1p9m_4x2y2r_ut-alrdl_9corners_1.3a}]]
set TLU_WORST [file join $TLU_DIR {cln28hpc+_1p09m+ut-alrdl_4x2y2r_rcworst.tluplus}]
set TLU_BEST  [file join $TLU_DIR {cln28hpc+_1p09m+ut-alrdl_4x2y2r_rcbest.tluplus}]

set PRTF_SYN [file join $PDK28_ROOT tn28clpr002s1_1_5a N28_PRTF_Syn_v1d5a PR_tech Synopsys]
set ANTENNA_TCL [file join $PRTF_SYN SCM antennaRule_n28_9lm.tcl]
# R2 (K.1): env override selects the patched map that routes port TEXT to the
# TSMC MxTXT layers (133/134/139); default stays the as-delivered PRTF map.
set GDS_MAP [env_or_default PDE28_GDS_MAP \
  [file join $PRTF_SYN GdsOutMap gdsout_4X2Y2R.map]]

set OUTPUT_ROOT [env_or_default PDE28_ICC2_OUTPUT_ROOT \
  [file join $REPO_ROOT flow local_runs icc2_28nm_20260807]]
set WORK_DIR   [file join $OUTPUT_ROOT work]
set RESULT_DIR [file join $OUTPUT_ROOT results]
set REPORT_DIR [file join $OUTPUT_ROOT reports]
set DESIGN_LIB [file join $WORK_DIR ${TOP}.dlib]
file mkdir $WORK_DIR
file mkdir $RESULT_DIR
file mkdir $REPORT_DIR

proc open_design {} {
  global DESIGN_LIB TOP
  open_lib $DESIGN_LIB
  open_block ${TOP}
  link_block
}

proc stage_done {name} {
  save_block
  save_lib
  puts "PDE28_STAGE_DONE $name"
}

# Reset-distribution census: combinational cells inside the fanout cone of the
# second synchronizer stage output (excludes the launching flop itself).
proc report_reset_tree {fname} {
  global REPORT_DIR
  set src [get_pins -quiet rst_sync_q_reg_1_/Q]
  if {[sizeof_collection $src] == 0} {
    set src [get_pins -quiet rst_sync_q_reg_1/Q]
  }
  redirect -file [file join $REPORT_DIR $fname] {
    if {[sizeof_collection $src] == 0} {
      puts "RESET_TREE: synchronizer output pin not found"
    } else {
      set cone [all_fanout -from $src -only_cells]
      set bufs [filter_collection $cone "is_combinational==true"]
      puts "RESET_TREE: cone_cells=[sizeof_collection $cone] combinational(buffers/inverters)=[sizeof_collection $bufs]"
      set lc {}
      foreach_in_collection c $bufs {
        lappend lc [get_attribute [get_lib_cells -of_objects $c] base_name]
      }
      foreach {k} [lsort -unique $lc] {
        puts "RESET_TREE_CELL $k x[llength [lsearch -all $lc $k]]"
      }
    }
  }
}
