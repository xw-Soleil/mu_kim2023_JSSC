read_db /home/sxw/PDE/pdeMujunjie/flow/work/openroad/10_place_v4.odb
set block [ord::get_db_block]
set target NULL
foreach net [$block getNets] {
  set sig [$net getSigType]
  set pins [expr {[llength [$net getITerms]] + [llength [$net getBTerms]]}]
  if {![$net isSpecial] && $pins == 0 && ($sig eq "POWER" || $sig eq "GROUND")} {
    set target $net
    break
  }
}
if {$target == "NULL"} {error "No test net"}
puts "PDE_SPECIAL_BEFORE=[$target isSpecial]"
$target setSpecial
puts "PDE_SPECIAL_SET=[$target isSpecial]"
set rc [catch {$target clearSpecial} msg]
puts "PDE_CLEAR_SPECIAL_RC=$rc MSG=$msg AFTER=[$target isSpecial]"
exit
