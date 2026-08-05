foreach command {odb::dbBTerm_create odb::dbBPin_create odb::dbBox_create odb::dbTech_findLayer} {
  puts "===== $command ====="
  if {[catch [list $command] result]} {
    puts $result
  } else {
    puts $result
  }
}
exit
