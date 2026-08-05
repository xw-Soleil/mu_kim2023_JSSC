# Generate a deliberately limited Liberty view for OpenROAD physical
# implementation.  Cell area, pins, capacitance, max capacitance and Boolean
# functions come from the installed Synopsys CCS .db.  The scalar delay and
# constraint tables below are placeholders so OpenSTA/CTS can build a timing
# graph; they are NOT a replacement for the qualified CCS timing database.

set SCRIPT_DIR [file dirname [file normalize [info script]]]
set REPO_ROOT  [file normalize [file join $SCRIPT_DIR ../..]]
set WORK_DIR   [file join $REPO_ROOT flow work openroad]
set REPORT_DIR [file join $REPO_ROOT flow reports openroad]
file mkdir $WORK_DIR
file mkdir $REPORT_DIR

set DB_FILE /ssd0/PDKs/TSMC65nm/STDCELL/std/STD_Cell/tcbn65lp_200b/Front_End/timing_power_noise/CCS/tcbn65lpwc_ccs.db
set LIB_NAME tcbn65lpwc_ccs
set OUT_LIB [file join $WORK_DIR tcbn65lpwc_openroad_impl.lib]

if {![file exists $DB_FILE]} {
  error "Missing source CCS database: $DB_FILE"
}

# Exact DC-mapped masters plus legal clock-tree buffers.  Filler, antenna and
# tap cells are physical-only and intentionally do not need Liberty entries.
set CELL_NAMES {
  AN4D0 AO211D0 AO21D0 AO21D1 AO222D0 AO22D0 AO31D0 AO31D2
  AOI211D0 AOI21D0 AOI221D0 AOI22D0 AOI31D0
  BUFFD0 BUFFD1 BUFFD2
  CKAN2D0 CKBD0 CKBD1 CKBD2 CKBD4 CKBD8 CKND1 CKND2
  CKND2D0 CKND2D1 CKND2D2 CKXOR2D0
  DFCNQD1 DFCNQD2 DFQD1 DFSNQD1 EDFCNQD1 EDFCNQD2
  FA1D0 HA1D0 IAO21D0 IND2D0 IND4D0 INR2D0 INR2XD0 INR2XD1
  INR3D0 INR4D0 INVD0 INVD1 IOA21D0 MAOI22D0 MOAI22D0
  MUX2D0 MUX2ND0 MUX4D0 ND2D0 ND2D2 ND3D0 ND3D1 ND4D0
  NR2D0 NR2D1 NR2XD0 NR2XD1 NR3D0 NR3D1 NR4D0
  OA211D0 OA21D0 OA22D0 OA32D0 OAI211D0 OAI21D0 OAI221D0
  OAI222D0 OAI22D0 OAI31D0 OAI32D0 OR2D0 OR3D1 OR4D0
  TIEL XNR4D0 XOR3D0
}

set SEQ_CELLS {DFCNQD1 DFCNQD2 DFQD1 DFSNQD1 EDFCNQD1 EDFCNQD2}

proc attr_or {object attribute fallback} {
  if {[catch {set value [get_attribute $object $attribute]}]} {
    return $fallback
  }
  if {$value eq ""} {
    return $fallback
  }
  return $value
}

proc pin_basename {pin_object} {
  return [lindex [split [get_object_name $pin_object] /] end]
}

proc write_delay_table {fh group value} {
  puts $fh "        $group (pde_delay_template) {"
  puts $fh "          values (\"$value\");"
  puts $fh "        }"
}

proc write_delay_arc {fh related sense timing_type} {
  puts $fh "      timing () {"
  puts $fh "        related_pin : \"$related\";"
  if {$sense ne ""} {
    puts $fh "        timing_sense : $sense;"
  }
  if {$timing_type ne ""} {
    puts $fh "        timing_type : $timing_type;"
  }
  write_delay_table $fh cell_rise 0.050
  write_delay_table $fh cell_fall 0.050
  write_delay_table $fh rise_transition 0.030
  write_delay_table $fh fall_transition 0.030
  puts $fh "      }"
}

proc write_constraint_table {fh group value} {
  puts $fh "        $group (pde_constraint_template) {"
  puts $fh "          values (\"$value\");"
  puts $fh "        }"
}

proc write_constraint_arc {fh clock_pin timing_type value} {
  puts $fh "      timing () {"
  puts $fh "        related_pin : \"$clock_pin\";"
  puts $fh "        timing_type : $timing_type;"
  write_constraint_table $fh rise_constraint $value
  write_constraint_table $fh fall_constraint $value
  puts $fh "      }"
}

read_db $DB_FILE

set fh [open $OUT_LIB w]
puts $fh "/*"
puts $fh " * OpenROAD implementation-only view generated from $DB_FILE."
puts $fh " * Scalar timing values are conservative placeholders and MUST NOT be used"
puts $fh " * for signoff.  DC/ICC2 timing authority remains tcbn65lpwc_ccs.db."
puts $fh " */"
puts $fh "library (tcbn65lpwc_openroad_impl) {"
puts $fh "  delay_model : table_lookup;"
puts $fh "  time_unit : \"1ns\";"
puts $fh "  voltage_unit : \"1V\";"
puts $fh "  current_unit : \"1mA\";"
puts $fh "  pulling_resistance_unit : \"1kohm\";"
puts $fh "  leakage_power_unit : \"1nW\";"
puts $fh "  capacitive_load_unit (1, pf);"
puts $fh "  nom_process : 1.0;"
puts $fh "  nom_voltage : 1.08;"
puts $fh "  nom_temperature : 125.0;"
puts $fh "  default_max_transition : 0.500;"
puts $fh "  default_max_fanout : 32.0;"
puts $fh "  default_fanout_load : 1.0;"
puts $fh "  operating_conditions (PDE_WC_PLACEHOLDER) {"
puts $fh "    process : 1.0;"
puts $fh "    voltage : 1.08;"
puts $fh "    temperature : 125.0;"
puts $fh "  }"
puts $fh "  default_operating_conditions : PDE_WC_PLACEHOLDER;"
puts $fh "  lu_table_template (pde_delay_template) {"
puts $fh "    variable_1 : input_net_transition;"
puts $fh "    variable_2 : total_output_net_capacitance;"
puts $fh "    index_1 (\"0.050\");"
puts $fh "    index_2 (\"0.050\");"
puts $fh "  }"
puts $fh "  lu_table_template (pde_constraint_template) {"
puts $fh "    variable_1 : constrained_pin_transition;"
puts $fh "    variable_2 : related_pin_transition;"
puts $fh "    index_1 (\"0.050\");"
puts $fh "    index_2 (\"0.050\");"
puts $fh "  }"

set generated 0
foreach cell_name $CELL_NAMES {
  set cell [get_lib_cells -quiet ${LIB_NAME}/${cell_name}]
  if {[sizeof_collection $cell] != 1} {
    close $fh
    error "Expected exactly one library cell for $cell_name"
  }

  set area [attr_or $cell area 0.0]
  set is_seq [expr {[lsearch -exact $SEQ_CELLS $cell_name] >= 0}]
  set input_pins {}
  foreach_in_collection pin [get_lib_pins -of_objects $cell] {
    if {[attr_or $pin direction ""] eq "in"} {
      lappend input_pins [pin_basename $pin]
    }
  }

  puts $fh "  cell ($cell_name) {"
  puts $fh "    area : $area;"

  if {$is_seq} {
    puts $fh "    ff (IQ, IQN) {"
    puts $fh "      clocked_on : \"CP\";"
    if {[string match "EDFCNQD*" $cell_name]} {
      puts $fh "      next_state : \"((E & D) | (!E & IQ))\";"
      puts $fh "      clear : \"!CDN\";"
    } elseif {[string match "DFCNQD*" $cell_name]} {
      puts $fh "      next_state : \"D\";"
      puts $fh "      clear : \"!CDN\";"
    } elseif {[string match "DFSNQD*" $cell_name]} {
      puts $fh "      next_state : \"D\";"
      puts $fh "      preset : \"!SDN\";"
    } else {
      puts $fh "      next_state : \"D\";"
    }
    puts $fh "    }"
  }

  foreach_in_collection pin [get_lib_pins -of_objects $cell] {
    set pin_name [pin_basename $pin]
    set direction [attr_or $pin direction "in"]
    if {$direction eq "in"} {
      set liberty_direction input
    } elseif {$direction eq "out"} {
      set liberty_direction output
    } else {
      set liberty_direction inout
    }

    puts $fh "    pin ($pin_name) {"
    puts $fh "      direction : $liberty_direction;"

    if {$liberty_direction eq "input"} {
      set capacitance [attr_or $pin capacitance 0.001]
      puts $fh "      capacitance : $capacitance;"
      if {[string equal -nocase [attr_or $pin clock false] true]} {
        puts $fh "      clock : true;"
      }
      if {$is_seq && ($pin_name eq "D" || $pin_name eq "E")} {
        write_constraint_arc $fh CP setup_rising 0.100
        write_constraint_arc $fh CP hold_rising 0.050
      }
    } elseif {$liberty_direction eq "output"} {
      set max_capacitance [attr_or $pin max_capacitance 0.100]
      puts $fh "      max_capacitance : $max_capacitance;"
      set function [attr_or $pin function ""]
      if {$function ne ""} {
        puts $fh "      function : \"$function\";"
      }

      if {$is_seq} {
        if {$pin_name eq "Q"} {
          write_delay_arc $fh CP positive_unate rising_edge
        }
      } else {
        foreach related $input_pins {
          set sense non_unate
          if {[llength $input_pins] == 1 && $function eq $related} {
            set sense positive_unate
          } elseif {[llength $input_pins] == 1 && ($function eq "!$related" || $function eq "(!$related)")} {
            set sense negative_unate
          }
          write_delay_arc $fh $related $sense ""
        }
      }
    }
    puts $fh "    }"
  }
  puts $fh "  }"
  incr generated
}

puts $fh "}"
close $fh

puts "PDE_OPENROAD_LIB_DONE cells=$generated output=$OUT_LIB"
exit
