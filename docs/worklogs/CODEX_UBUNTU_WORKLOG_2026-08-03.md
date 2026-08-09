# Ubuntu Synopsys 全流程修复与 ECO 工作记录

> 日期：2026-08-03（Asia/Shanghai）  
> 主机：`soleilUbuntu`  
> 项目：`/home/soleil/code/DigitalIC/PDE/pdeMujunjie`  
> 当前状态：按用户要求暂停；没有启动 `eco10`，没有继续修改设计数据库。

## 1. 结论摘要

已经完成并有报告/产物支持的部分：

1. SCL 的 license checkout 随机段错误已通过进程级 wrapper 稳定绕开：
   `icc2_shell` 12/12、`icc2_lm_shell` 12/12 成功。
2. `icc2/create_ndm.tcl` 已能在 Ubuntu 本地成功运行；新 NDM 保留 855 个
   GDS layout view 和 `SITE core`，不再出现旧流程的 855 条 `LM-058`。
3. Ubuntu 本地 RTL -> DC -> ICC2 -> filler -> GDS/DEF/netlist/SPEF 全链已跑通。
4. 新 GDS 已在 EDAServer 使用 foundry antenna deck 复查：26 checks、0 results。
5. `eco01` 已把新回归版图的 1 open、2 short 修成 0 open、0 route DRC、
   0 LVS short/open；后续各个已提交 ECO 均保持物理检查为 0。
6. `eco02` 补了 VDD/VSS 顶层 M5 terminal；`eco03` 修正 WC/BC PVT。

当前不能称为 signoff 完成，主要原因不是那几条亚皮秒 hold，而是新的 uncertainty
对照实验发现了约束语义问题：

- `eco09` 原数据库的 setup 路径中没有 `clock uncertainty` 项；
- 同一数据库的 hold 路径实际使用 `0.2000 ns`；
- 显式设为 setup `0.2 ns`、hold `0.05 ns` 后，hold 3 条全部消失，最差路径变为
  `+0.1495 ns`；但 setup 变成 27 条违例，WNS `-0.2148 ns`。

因此，`eco04~eco09` 不能继续当作正确约束下的时序收敛历史。正确做法是先在
post-route 明确拆分 uncertainty，再从物理/PVT 已清洁的数据库重新做 timing closure。

## 2. License 随机崩溃：做了什么

### 2.1 原始故障

修复容器 NSS 后，未包装的 Synopsys 进程仍会在 license checkout 前后随机崩溃，
典型栈为：

```text
udev_get_userdata
udev_enumerate_scan_devices
scl_lc_checkout
SIGSEGV
```

未屏蔽对照：`icc2_shell` 8 次仅 2 次成功，6 次在 udev/SCL 路径崩溃。
Ubuntu 24.04/systemd 255 容器也出现过 `sd-netlink` assertion，因此不能再把完整
根因简单写成“systemd 245 读取 255 数据库”。能直接确认的是：SCL 的可选 udev
硬件枚举路径不稳定。

### 2.2 实际绕法

新增并接入：

```text
flow/local/snps_no_udev.sh
```

wrapper 只对被包装的子进程修改 `LD_LIBRARY_PATH`，把一个指向 `/dev/null` 的
`libudev.so.1` 放在搜索路径首位，使 SCL 的可选 `dlopen()` 失败并走非 udev fallback。
它不修改系统 libudev，也不修改 `/run/udev`。

回归结果：

```text
未屏蔽：icc2_shell      2/8 成功，6/8 udev crash
已屏蔽：icc2_shell     12/12 成功
已屏蔽：icc2_lm_shell  12/12 成功
```

`run_full_flow.sh`、`run_dc.sh`、`run_pnr.sh`、`run_finish.sh`、
`run_create_ndm.sh` 均已接入该 wrapper。原来的启动重试仍保留为第二层保护。

这属于稳定 workaround，不是 Synopsys 官方 hotfix。诊断时可设置
`PDE_SNPS_USE_SYSTEM_UDEV=1` 恢复系统 udev，但会重新引入随机崩溃。

## 3. NDM 重建：做了什么

本地建库入口现已成功执行，active 参考库为：

```text
flow/work/icc2/ref_rebuilt/tcbn65lp_6lmT1.ndm
```

结果：

- 建库约 22 秒，输出约 309 MiB；
- `check_workspace` 成功；
- 855 个同名 GDS physical blocks 不再触发 `LM-058`；
- 使用 `read_gds -merge_action update` 并保留 layout views；
- `BUFFD2.layout` 与厂商 GDS 的 DBU、逐层图形数和面积一致；
- 普通单元和 `FILL*` 的 `site_name` 均为 `core`；
- floorplan 显式使用 `-site_def core` 后，filler insertion 可运行。

这修复了旧 NDM 的两个问题：标准单元内部 GDS geometry 丢失，以及 filler/site
不兼容。它没有补出 ICC2 router 的 antenna rule；该问题是独立问题。

## 4. Ubuntu 全链回归结果

主要隔离目录：

```text
DC:   flow/local_runs/dc/
ICC2: flow/local_runs/icc2_20260803_full/
NDM:  flow/work/icc2/ref_rebuilt/tcbn65lp_6lmT1.ndm
```

完整链已实际执行：

```text
RTL -> DC netlist/SDC -> floorplan -> PG -> placement -> CTS
    -> route -> filler -> GDS/DEF/post-route netlist/SPEF
```

全链初始回归的关键结果：

| 项目 | 结果 |
|---|---|
| ICC2 | 首次启动成功；2014 秒；8 线程；峰值 3890.58 MB |
| filler | 136,478 个；最终 264,600 components；legality 0 |
| 初始时序 | setup 约 -0.01 ns / 2 paths；hold 约 -0.02 ns / 195 paths |
| 初始物理 | 1 open、2 short DRC，`check_lvs` 同样报出 |
| GDS | 139,399,862 bytes；198 structures；0 empty/undefined cells |
| GDS 单元 | 181 个已用厂商单元逐层图形数和面积匹配 |

ICC2 内部天线检查仍显示 `no antenna rules defined`。原因是 `.tf` 没有 antenna
规则，而 LEF 中的 antenna 属性不会自动变成 router 所需的 `define_antenna_*` 规则。
这不影响外部 Calibre antenna deck 的检查。

## 5. Calibre antenna

新回归 GDS 已传到 EDAServer，并使用 foundry antenna deck 检查：

```text
26 checks executed
0 results generated
runtime warnings: none
VIA1~VIA5: 约 122.8 万
```

该结果可信地说明 antenna deck 没有报违例，但不等于完整 Calibre DRC/LVS signoff。
当前仍未确认一套与实际 `3X1Z` stream-out 完全匹配的完整 DRC/LVS deck，也没有运行
PrimeTime/Formality。

## 6. ECO01~ECO09 做法与趋势

### 6.1 每轮改动

| 轮次 | 基线与实际改动 | 是否提交 |
|---|---|---|
| eco01 | 对全链结果执行 `route_eco`，修 1 open 和 2 short | 是 |
| eco02 | 在既有 M5 PG ring 上为 VDD/VSS 各建 1 个顶层 terminal | 是 |
| eco03 | WC 改为 1.08 V / 125 C；BC 改为 1.32 V / 0 C | 是 |
| eco04 | 删除 filler，执行第 1 轮 timing-driven `route_opt`，再布线/回填 | 是 |
| eco05 | 从 eco04 做第 2 轮 `route_opt` | 是 |
| eco06 | 从 eco05 做第 3 轮 `route_opt`；出现量化抖动，未作为最佳版本 | 是，保留诊断 |
| eco07 | 首次定点 sizing 脚本把 `size_cell` 状态值误当 collection，提前停止 | 否；无 `save_*` |
| eco08 | 从干净 eco05 重做定点 ECO：关键 setup 门 D0->D1；8 个驱动升档；4 个 endpoint 插 `DEL005` | 是 |
| eco09 | 从 eco08：关键门 D1->D2；6 个残余驱动升档；5 个 endpoint 插 `DEL005` | 是，结果退化 |

### 6.2 统一四位精度重报

为了避免原报告中的 `-0.00`，2026-08-03 对每个 `.dlib` 重新执行只读报告：

```tcl
report_timing ... -slack_lesser_than 0 -max_paths 10000 \
  -significant_digits 4 -physical -nosplit
```

每轮均只 `open_lib/open_block/link_block/report/exit`，没有 `save_block`、`save_lib`
或任何设计编辑。统一报告位于：

```text
flow/reports/icc2/history_audit_20260803/eco01/
...
flow/reports/icc2/history_audit_20260803/eco09/
```

下表的 trans/cap 也是本次 fresh `report_qor` 数值，避免混用旧报告。括号为违例路径数。
对小于 0.0001 ns 的值，额外保留已有 6 位精度，避免再次写成零。

| 轮次 | setup WNS ns（条数） | hold WNS ns（条数） | max trans | max cap | 物理状态 |
|---|---:|---:|---:|---:|---|
| eco01 | -0.0075 (2) | -0.0175 (194) | 12 | 114 | 0 open / 0 route DRC / 0 LVS short |
| eco02 | -0.0076 (2) | -0.0175 (194) | 12 | 115 | 同 eco01；PG terminal 已补 |
| eco03 | -0.0076 (2) | -0.0214 (262) | 10 | 115 | 物理 0；PVT mismatch 0 |
| eco04 | -0.0010 (1) | -0.0138 (27) | 2 | 8 | 物理 0 |
| eco05 | -0.000976 (1) | -0.000029 (4) | 0 | 8 | 物理 0 |
| eco06 | -0.0008 (1) | -0.0001 (8) | 0 | 5 | 物理 0；比 eco05 有抖动 |
| eco07 | -0.0010 (1) | -0.000029 (4) | 0 | 8 | 脚本失败且未保存，等价于父数据库 eco05 |
| eco08 | +0.001842 (0) | -0.000593 (5) | 1 | 6 | 物理 0 |
| eco09 | -0.014752 (1) | -0.000523 (3) | 3 | 6 | 物理 0；legality/PG/PVT 均为 0 |

说明：这张表忠实反映各数据库在原有约束状态下的结果，但原有约束状态本身随后被
uncertainty A/B 证明存在问题，不能再用它判断 signoff 收敛。

## 7. Uncertainty 关键 A/B 实验

### 7.1 实验约束

数据库：

```text
flow/local_runs/icc2_signoff_eco09/work/icc2/pde_chip_top_safe.dlib
```

同一个 ICC2 会话内：

1. 不改约束，先输出 before 报告；
2. 显式执行：

```tcl
current_scenario FUNC_WC
set_clock_uncertainty -setup 0.2 [get_clocks core_clk]
current_scenario FUNC_BC
set_clock_uncertainty -hold 0.05 [get_clocks core_clk]
```

3. 输出 after 报告；
4. 直接 `exit`，没有调用 `save_block` 或 `save_lib`。

报告目录：

```text
flow/reports/icc2/uncertainty_ab_20260803/
```

日志结束标记：

```text
PDE_UNCERTAINTY_AB_DONE no_save=1
```

### 7.2 A/B 结果

| 项目 | before：数据库原状态 | after：setup 0.2 / hold 0.05 |
|---|---:|---:|
| setup uncertainty（路径报告） | 没有该行 | -0.2000 ns |
| setup WNS | -0.0148 ns | -0.2148 ns |
| setup violations | 1 | 27 |
| setup TNS | -0.01 ns（QoR 两位口径） | -2.45 ns |
| hold uncertainty（路径报告） | +0.2000 ns | +0.0500 ns |
| hold WNS / 最差路径 | -0.0005 ns | +0.1495 ns |
| hold violations | 3 | 0 |
| max transition | 3 | 3 |
| max capacitance | 6 | 6 |

这不是预期中的“setup 保持不变、只放松 hold”。原始 SDC 文本虽然只有：

```tcl
set_clock_uncertainty 0.2 [get_clocks core_clk]
```

但当前 post-route 数据库的实际路径报告显示：0.2 只体现在 hold 检查，setup 路径没有
uncertainty。显式拆分后，setup 才真正承担 0.2 ns uncertainty。

目前只能确认上述行为，尚未定位 unqualified uncertainty 为什么在 ICC2 post-route
表现成这样。不能在没有进一步约束审计的情况下把它写成工具 bug或 SDC import bug。

### 7.3 对九轮 ECO 的重新定性

1. `eco01` 的 open/short 修复仍然必要，与时序 uncertainty 无关。
2. `eco02` 的 PG terminal 修复仍然必要。
3. `eco03` 的 PVT 修复仍然必要。
4. `eco04~eco09` 的 hold 收敛目标使用了 0.2 ns hold uncertainty。改成 0.05 后 hold
   立即 0 violation，因此这些轮次中为 hold 插入/保留的大量 delay cell 不应继续作为
   正确最终方案。
5. `eco04~eco06` 同时显著降低了 max-transition/max-cap，不能简单说所有优化工作都
   没价值；但需要在正确 split uncertainty 下重新评估和执行。
6. `eco08/eco09` 的定点 hold buffer 和围绕亚皮秒 slack 的修改，不应继续追加。
7. 正确 setup `0.2` 被显式应用后出现 27 条、WNS -0.2148 ns。这是下一阶段真正需要
   处理的时序问题，不是原先 `-0.01 ns` 的显示噪声。

## 8. 当前暂停点

已明确停止：

- 没有创建或运行 `eco10`；
- 没有继续查询 app option；
- uncertainty A/B 和九轮精确重报均未保存任何设计数据库；
- `eco01~eco09` 保留为独立回退/审计目录。

恢复工作时建议按以下顺序，而不是从 eco09 继续打补丁：

1. 在 post-route 约束加载后显式设置 setup `0.2`、hold `0.05`；
2. 验证 setup/hold 路径报告中分别出现 `-0.2000` / `+0.0500`；
3. 从 `eco03`（物理、PG、PVT 已修，尚未进行错误 hold 目标下的大量 timing ECO）
   建新分支；
4. 在正确约束下重新做 setup/electrical closure；
5. 每轮同时核对 setup、hold、max-transition、max-cap、route DRC、LVS、legality、PG；
6. 最终重新 stream-out，并重跑 Calibre antenna；完整交付还需匹配的 Calibre DRC/LVS、
   PrimeTime 和 Formality。

## 9. 证据速查

```text
# License workaround
flow/local/snps_no_udev.sh

# 新参考库
flow/work/icc2/ref_rebuilt/tcbn65lp_6lmT1.ndm

# 完整回归
flow/local_runs/icc2_20260803_full/

# ECO 数据库
flow/local_runs/icc2_signoff_eco01/
...
flow/local_runs/icc2_signoff_eco09/

# 统一四位时序报告
flow/reports/icc2/history_audit_20260803/eco01/
...
flow/reports/icc2/history_audit_20260803/eco09/

# uncertainty A/B
flow/reports/icc2/uncertainty_ab_20260803/
```

