# 本地 P&R 入口。
#
# 从 EDAServer 带过来的 flow/icc2/pnr.tcl 是 ICC2 O-2018.06-SP1 时代写的，
# 本地是 W-2024.09，中间隔了六年，有少量 API 语义变化。这里在加载时按下面的
# 替换表生成隔离输出目录下的 work/icc2/pnr.patched.tcl 再 source ——
# 补丁后的脚本是落盘的，改了哪几处可以直接 diff 出来。
#
# （试过用 rename + proc 做运行时垫片，ICC2 不允许 rename 内建命令：
#   "Error: command cannot be renamed"。）

# 这台机器 32 线程 / 31G 内存。93k 个 leaf cell 的块，8 核是稳妥值；
# 调高要先确认 license 里的多核 feature，否则 place_opt 会退回单核并告警。
set_host_options -max_cores 8

set src [file join $env(PDE_REPO_ROOT) flow icc2 pnr.tcl]
set dst [file join $env(PDE_ICC2_OUTPUT_ROOT) work icc2 pnr.patched.tcl]
file mkdir [file dirname $dst]

set fh [open $src r]
set body [read $fh]
close $fh

# ---- 替换表：{正则  替换  说明} ----
# -pin_spacing 在 O-2018.06 里是微米（浮点），W-2024.09 改成了轨道数（整数）。
# M3 pitch 是 0.2 um，所以原来的 0.4 um 等价于 2 条轨道，物理意图不变。
set patches {
  {-pin_spacing 0\.4}  {-pin_spacing 2}
  {W-2024.09 的 -pin_spacing 单位是轨道数(整数)，0.4um / 0.2um pitch = 2 tracks}
}

# The rebuilt NDM preserves the LEF SITE core on every standard/filler cell.
# Select that site explicitly; otherwise initialize_floorplan picks the smaller
# default site named unit and later filler insertion cannot use the core cells.
if {[info exists ::env(PDE_SITE_DEF)] && [string trim $::env(PDE_SITE_DEF)] ne ""} {
  set site_def [string trim $::env(PDE_SITE_DEF)]
  if {![regexp {^[A-Za-z0-9_./:-]+$} $site_def]} {
    error "PDE_SITE_DEF contains unsupported characters: $site_def"
  }
  lappend patches \
    {-core_utilization 0\.55 -core_offset 10\.0} \
    "-core_utilization 0.55 -core_offset 10.0 -site_def $site_def" \
    "select the rebuilt NDM standard-cell site '$site_def'"
}

set total 0
foreach {pat rep desc} $patches {
  # 必须有 --：模式以 '-' 开头，否则 regsub 会把它当成自己的选项
  set n [regsub -all -- $pat $body $rep body]
  puts "PDE_COMPAT: $n 处 -- $desc"
  incr total $n
  if {$n == 0} {
    puts "PDE_COMPAT_WARNING: 上面这条补丁没匹配到任何内容，pnr.tcl 可能已经变了"
  }
}
puts "PDE_COMPAT: 共替换 $total 处，补丁后脚本写到 $dst"

set fh [open $dst w]
puts -nonewline $fh $body
close $fh

source $dst
