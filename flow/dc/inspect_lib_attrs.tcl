# Inspect the small set of library attributes needed to build an OpenROAD-only
# physical implementation view from the installed Synopsys CCS .db.
set db /ssd0/PDKs/TSMC65nm/STDCELL/std/STD_Cell/tcbn65lp_200b/Front_End/timing_power_noise/CCS/tcbn65lpwc_ccs.db
read_db $db
set lib tcbn65lpwc_ccs

foreach cell_name {CKBD0 CKBD1 CKBD2 CKBD4 CKBD8 DFCNQD1 DFCNQD2 DFQD1 DFSNQD1 EDFCNQD1 EDFCNQD2 INVD0 BUFFD1 TIEL} {
  set cell [get_lib_cells -quiet ${lib}/${cell_name}]
  puts "PDE_CELL_BEGIN $cell_name"
  foreach attr {area is_sequential cell_footprint dont_use} {
    if {[catch {get_attribute $cell $attr} value]} {
      set value <absent>
    }
    puts "PDE_CELL_ATTR $attr {$value}"
  }
  foreach_in_collection pin [get_lib_pins -of_objects $cell] {
    set pin_name [get_object_name $pin]
    puts "PDE_PIN_BEGIN $pin_name"
    foreach attr {direction capacitance max_capacitance function clock clock_gate_clock_pin clock_gate_enable_pin} {
      if {[catch {get_attribute $pin $attr} value]} {
        set value <absent>
      }
      puts "PDE_PIN_ATTR $attr {$value}"
    }
  }
  puts "PDE_CELL_END $cell_name"
}
exit
