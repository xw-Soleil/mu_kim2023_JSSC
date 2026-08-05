foreach pattern {odb::*BTerm* odb::*BPin* odb::*Box* odb::*TechLayer*} {
  puts "===== $pattern ====="
  foreach command [lsort [info commands $pattern]] {
    puts $command
  }
}
exit
