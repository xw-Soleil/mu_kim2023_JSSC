# 续跑：布线（route_opt）已经完成并 save_block，dlib 里是完整的布线后数据。
# 流程死在下一步 create_stdcell_fillers（"Filler FILL64 has no site def set"），
# 这里从那一步接着往下跑，不重做 place/CTS/route。
#
# 尾部代码不手抄，直接从 pnr.tcl 里按注释锚点切出来 eval —— 保证和主流程一致，
# pnr.tcl 改了这里自动跟着改。
#
# 环境变量由 flow/local/env_local.sh 提供。
# PDE_SKIP_FILLERS=1 可以跳过填充单元，先把报告和 GDS 出出来。

set TOP $env(PDE_TOP)
set REPO_ROOT $env(PDE_REPO_ROOT)
set RESULT_DIR [file join $REPO_ROOT flow results icc2]
set REPORT_DIR [file join $REPO_ROOT flow reports icc2]
set GDS_MAP $env(PDE_GDS_MAP)
set GDS_MAP_FORMAT $env(PDE_GDS_MAP_FORMAT)
file mkdir $RESULT_DIR $REPORT_DIR

# 与 pnr.tcl 中同名过程保持一致
proc connect_named_pg_pins {} {
  set vdd_pins [get_pins -hierarchical -physical_context -quiet */VDD]
  set vss_pins [get_pins -hierarchical -physical_context -quiet */VSS]
  if {[sizeof_collection $vdd_pins] == 0} {
    error "No physical VDD pins were found; verify the RVT NDM and netlist link"
  }
  if {[sizeof_collection $vss_pins] == 0} {
    error "No physical VSS pins were found; verify the RVT NDM and netlist link"
  }
  connect_pg_net -net VDD $vdd_pins
  connect_pg_net -net VSS $vss_pins
}

open_lib $env(PDE_ICC2_DESIGN_LIB)

# 续跑必须先 open_block：get_blocks 只匹配已经打开的 block，
# 而这里的 block 是上一次 run_pnr.sh 里 save_block 存进 dlib 的（list_blocks 能看到
# pde_chip_top_safe.design），不 open 的话 get_blocks 返回空。
set blk ""
foreach cand [list ${TOP}.design $TOP] {
  if {![catch {set blk [open_block $cand]}] && $blk ne ""} {
    puts "PDE_FINISH: 打开 block '$cand'"
    break
  }
}
if {$blk eq ""} {
  error "打不开 block，dlib 里有的是：[list_blocks]"
}
current_block $blk
link_block
puts "PDE_FINISH: block=[get_object_name [current_block]]"

set FILLER_MASTERS {FILL64 FILL32 FILL16 FILL8 FILL4 FILL2 FILL1}
set filler_patterns {}
foreach filler_master $FILLER_MASTERS {
  lappend filler_patterns "*/$filler_master"
}
set FILLER_CELLS [get_lib_cells -quiet $filler_patterns]
puts "PDE_FINISH: filler_cells=[sizeof_collection $FILLER_CELLS]"

# ---- 切出 pnr.tcl 从填充单元开始的尾部 ----
set src [file join $REPO_ROOT flow icc2 pnr.tcl]
set fh [open $src r]
set body [read $fh]
close $fh

set anchor "# Fill every legal row gap"
set pos [string first $anchor $body]
if {$pos < 0} {
  error "在 pnr.tcl 里找不到锚点 '$anchor'，脚本可能已改动"
}
set tail [string range $body $pos end]

if {[info exists env(PDE_SKIP_FILLERS)] && $env(PDE_SKIP_FILLERS) eq "1"} {
  # 只掐掉 create_stdcell_fillers 那一行，后面的 connect/save/报告/写出全部保留
  set n [regsub -all -- {create_stdcell_fillers[^\n]*\n} $tail \
         "puts \"PDE_FINISH: 按 PDE_SKIP_FILLERS=1 跳过填充单元\"\n" tail]
  puts "PDE_FINISH: 跳过填充单元（改写 $n 处）"
}

set patched [file join $REPO_ROOT flow work icc2 finish.patched.tcl]
set fh [open $patched w]
puts -nonewline $fh $tail
close $fh
puts "PDE_FINISH: 尾部写到 $patched，开始执行"

source $patched
