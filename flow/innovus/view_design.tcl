# Innovus 版图查看脚本（仅查看，不做实现；无需时序库）。
#
# 用法：把本文件与下面三个文件放同一目录，在有 Innovus 的机器上执行
#   innovus -init view_design.tcl
# 所需文件（见 HOWTO / worklog 的打包命令）：
#   pde_chip_top_safe.postroute.v   布线后网表
#   pde_chip_top_safe.def           布线后 DEF（含 PG/填充/全部绕线）
#   tcbn65lp_6lmT1.lef              TSMC65LP 6LM-T1 LEF（含 tech 段）
#
# 说明：没有加载 .lib 时序库，Timing 菜单不可用——纯版图查看。
# 在 Innovus 18.1 的 legacy init 流程下验证目标；更老/更新版本如报
# init 变量弃用警告，可改用 File -> Import Design 图形界面等价操作。

set init_verilog  pde_chip_top_safe.postroute.v
set init_lef_file tcbn65lp_6lmT1.lef
set init_top_cell pde_chip_top_safe
set init_pwr_net  VDD
set init_gnd_net  VSS

init_design

# 读入布线后 DEF：覆盖摆放与全部绕线（含 SPECIALNETS 的 PG 和 filler）
defIn pde_chip_top_safe.def

fit
puts "PDE_INNOVUS_VIEW_READY top=pde_chip_top_safe"
