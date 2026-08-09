# Ubuntu ECO10：约束根因定位与正确约束下的重新收敛

> 日期：2026-08-04（Asia/Shanghai）
> 主机：`soleilUbuntu`
> 项目：`/home/soleil/code/DigitalIC/PDE/pdeMujunjie`
> 前置：`CODEX_UBUNTU_WORKLOG_2026-08-03.md`（uncertainty A/B 实验与暂停决定）
> 本文所有编辑均发生在新分支 `eco10`；`eco01~eco09` 目录未被触碰。

## 1. 结论摘要

1. 08-03 发现的 uncertainty 异常已定位到确切根因，且实际缺失范围比
   uncertainty 更大：当年 `pnr.tcl` 在 `current_mode FUNC` 后执行 `read_sdc`，
   但所有 **scenario 级约束只落进了当时的 current scenario（FUNC_BC）**。
   FUNC_WC 的 setup 分析自第一次全链回归起就缺少：clock uncertainty、
   全部 34 个输入端口的 input delay/transition、全部 21 个输出端口的
   output delay/负载、设计级 `max_transition 0.5` / `max_fanout 32`。
   mode 级对象（时钟定义、`set_false_path -from rst_n`）不受影响。
2. 证据：对 eco10 库两个 scenario 分别 `write_sdc`，FUNC_WC 有效约束仅
   44 行，FUNC_BC 有 403 行。文件在
   `flow/local_runs/icc2_signoff_eco10/reports/icc2/uncertainty_fix/before_effective_FUNC_{WC,BC}.sdc`。
3. eco10 从 eco03（物理/PG/PVT 干净、未被错误 hold 目标的大规模 ECO 污染）
   复制建立，先后完成：
   - stage 1：两 scenario 显式 `set_clock_uncertainty -setup 0.2 / -hold 0.05`，
     路径报告验证到 `-0.2000` / `+0.0500` 后才存盘；
   - stage 1b：按 `flow/dc/synth.tcl` 的生成逻辑补回 FUNC_WC 缺失的全部
     I/O 与电气约束（不整份重读 SDC——`create_clock` 会重建时钟对象、
     丢掉 post-CTS 的 propagated/latency 状态）。
4. 完整约束下的真实基线（修复后、优化前）：setup 29 条违例 / WNS -0.21 /
   TNS -2.79；WC max_transition 7,945 条、max_capacitance 14 条；
   hold 0 条（0.05 目标下原 262 条假违例全部消失）。
5. 经过 6 轮收敛（3 轮全局 route_opt + 3 轮定点 ECO），达到：setup/hold/
   max_cap 0 违例、route DRC 0、LVS 0 short 0 open、legality/PG 干净；
   仅剩 10 条 -0.00（<5 ps）max_transition 贴线值，按 waive 记录。
   终版 GDS/DEF/netlist/SPEF 已写出并完成 1nm 缩放，待送 EDAServer 跑
   Calibre antenna。详见第 6 节。
6. 源头已修：`flow/dc/synth.tcl` 显式拆分 uncertainty；`flow/icc2/pnr.tcl`
   最终改为**逐 scenario 执行 read_sdc**（并固化 PVT 角与 PG terminal，
   见第 9 节）。修正脚本下的全链重跑 `full_clean_20260804` 已完成收敛，
   为最终推荐交付：setup WNS +0.74、全库仅 7 颗 DEL、buf/inv 少 43%。

## 2. 根因：read_sdc 的 scenario 捕获

### 2.1 机制

`pnr.tcl` 原序列：

```tcl
create_scenario -mode FUNC -corner WC -name FUNC_WC
create_scenario -mode FUNC -corner BC -name FUNC_BC   ;# <- current 停在这里
current_mode FUNC
read_sdc $SDC
```

W-2024.09 的实测行为：`current_mode` 并未把后续 `read_sdc` 变成纯 mode
级导入。SDC 中 scenario 作用域的命令全部落到当时的 current scenario——
即最后一个 `create_scenario` 的 FUNC_BC。由于 FUNC_BC 只启用 hold 分析、
FUNC_WC 只启用 setup 分析，于是：

- 不带限定符的 `set_clock_uncertainty 0.2` 表现为"只压 hold"；
- FUNC_WC 的 setup 同时丢掉 I/O delay、端口负载、input transition、
  `max_transition 0.5`、`max_fanout 32`，且多年报告中毫无痕迹
  （I/O 路径根本不进违例报告，电气检查只按库限值执行）。

08-03 的 A/B 实验只看到了 uncertainty 一角；本次 `write_sdc` 对照才暴露
全部缺失面。**教训：MCMM 下导入约束必须逐 scenario 进行或导入后逐
scenario 审计 `write_sdc`。**

### 2.2 修复原则

不能整份重读 SDC 修复既有数据库：`create_clock` 会重建时钟对象，丢掉
post-CTS 的 `set_propagated_clock` 与工具写入的 IO latency
（`set_clock_latency -min 0.701466 / -max 0.707016`）。因此 stage 1b 按
`synth.tcl` 生成约束的原始逻辑（`remove_from_collection [all_inputs]
{clk rst_n}` 等）重建缺失命令，端口集合动态推导，不硬编码端口名。

## 3. eco10 各阶段脚本与验证

全部脚本在 `flow/local/`，launcher 沿用 `snps_no_udev.sh` 包装与启动
崩溃重试判据；每阶段先验证后 `save_block`，验证失败即 error、不存盘：

| 阶段 | 脚本 | 内容 | 验证点 |
|---|---|---|---|
| stage 1 | `eco10_stage1_constraints.tcl` | 两 scenario 拆分 uncertainty | 路径报告出现 `-0.2000`/`+0.0500` |
| stage 1b | `eco10_stage1b_restore_wc.tcl` | 补回 WC 缺失约束（34 入/21 出） | `write_sdc` 含 I/O delay、负载、trans、0.5 限值 |
| stage 2 | `eco10_stage2_closure.tcl` | fillers out → route_opt → route_eco → fillers in → 全套检查 | 报告电池 + uncertainty 回归守卫 |
| stage 2t | `eco10_stage2t_targeted.tcl` | 67 网驱动升档 + 2 短路网重布（eco08 手法） | 同上 |
| stage 3 | `eco10_stage3_writeout.tcl` | 终版报告 + GDS/DEF/netlist/SPEF 写出 | 同上（只读，无优化命令） |

运行方式（示例）：

```bash
distrobox enter synopsys-focal -- flow/local/run_eco10_stage2.sh
# 换报告目录跑第 N 轮：
PDE_ECO10_REPORT_DIR=$PWD/flow/local_runs/icc2_signoff_eco10/reports/icc2/closureN \
  distrobox enter synopsys-focal -- flow/local/run_eco10_stage2.sh
```

stage 1 / 1b / 2 / 2t 均一次启动成功（license wrapper 12/12 的稳定性
延续）。stage 2t 首次运行在 `remove_routes` 因缺 shape 参数报
ZRT-555 中止（未到 save，无损），补 `-detail_route -global_route` 后通过。

## 4. 源头补丁（对未来全链回归生效）

1. `flow/dc/synth.tcl`：

```tcl
set_clock_uncertainty -setup 0.200 [get_clocks $CLOCK_NAME]
set_clock_uncertainty -hold  0.050 [get_clocks $CLOCK_NAME]
```

2. `flow/icc2/pnr.tcl`：`read_sdc` 后逐 scenario 显式：

```tcl
foreach unc_scenario {FUNC_WC FUNC_BC} {
  current_scenario $unc_scenario
  set_clock_uncertainty -setup 0.2 [all_clocks]
  set_clock_uncertainty -hold 0.05 [all_clocks]
}
```

已确认与 `pnr_local.tcl` 的 2018→2024 补丁表无冲突。
**后续更正（同日）**：上述"只钉 uncertainty"的形式在第一次全链重跑中被
证实不充分（FUNC_WC 仍缺 I/O delay 与 0.5ns trans 限制）；pnr.tcl 最终
改为逐 scenario 执行 read_sdc + 拆分 uncertainty，见 9.1 节第 3 条。

## 5. 修复后的真实基线（eco10 stage 1b 之后、优化之前）

| 项目 | 数值 |
|---|---:|
| setup（reg2reg core_clk） | WNS -0.21 / TNS -2.79 / 29 条 |
| setup（in2reg，首次可见） | 最差 +0.02，0 条违例 |
| setup（reg2out，首次可见） | 最差 +6.55，0 条违例 |
| hold（0.05 目标） | 0 条（原 0.2 目标下 262 条全消失） |
| WC max_transition（0.5 限值首次生效） | 7,945 条（最差 -0.29） |
| WC max_capacitance | 14 条 |
| 物理 | 0 open / 0 short / legality PG 干净（继承 eco03） |

最差 setup 路径尾部有一颗 route_opt 时代为假 hold 目标插入的 DEL1
（单颗 1.716 ns）。eco03 网表含 9,029 颗 DEL 单元 / 18,895 个
`copt_h_inst` hold 修复实例；收敛后 DEL 数基本未减（route_opt 选择
绕开而非拆除，时序已满足，代价是无谓的面积/功耗，见第 7 节）。

## 6. 收敛轮次

| 轮次 | 操作 | setup WNS(条) | hold 条 | WC trans(条) | WC cap(条) | route DRC | LVS short/open | legality |
|---|---|---:|---:|---:|---:|---:|---:|---|
| 基线 | stage 1b 后 | -0.21 (29) | 0 | 7945 | 14 | 0 | 0/0 | 过 |
| closure1 | route_opt+route_eco | -0.07 (4) | 0 | 446 | 0 | 6 | 5/0 | 过 |
| closure2 | route_opt+route_eco | **+0.01 (0)** | 0 | 66 | 0 | 3 | 4/0 | 过 |
| closure3 | 定点：59 驱动升档 + 2 短路网重布 | -0.01 (1) | 0 | 52 | 6 | 16 | **0/0** | 过 |
| closure4 | route_opt+route_eco（收扰动） | **+0.01 (0)** | 0 | 13 | 0 | **0** | 1/0 | 过 |
| closure5 | 定点：3 升档 + 3 守卫式插 buffer + 短路重布 | +0.01 (0) | 0 | 12 | 0 | 0 | **0/0** | 过 |
| closure6 | 定点：TRANSFIX buffer 升 BUFFD6 等 3 处 | **+0.01 (0)** | **0** | **10×-0.00** | **0** | **0** | **0/0** | 过 |

closure3 说明：升档扰动使 1 条 setup 回落 -0.01、BC 侧新增 6 trans/8 cap、
几何类 DRC 反弹到 16（2 diff-net spacing / 6 min-edge / 4 fat-contact /
4 same-net spacing，无短路）；同时两处 route_eco 反复复现的短路
（M5 `ropt_net_26846`、M1 `copt_net_15295`）被拆线重布后归零。
升档跳过 7 处：1 处 DFQD4 无更大档、6 处驱动为 DEL005/DEL015
（延迟单元无驱动档位序列，需插 buffer 而非升档）。

closure4 说明：全局 route_opt 收掉 closure3 的扰动——setup 回到 0 违例
（WNS +0.01）、BC 电气清零、check_routes DRC 0。残留 13 行 trans
= 6 个唯一网络（最差 -0.03，其中 4 个为 -0.00 贴线值）、1 条新 M1
LVS 短路（`ZBUF_2_200` 压过 `ZBUF_2_inst_25027` 内部 obstruction，
check_routes 的 wire-vs-wire DRC 不计此类，故两报告口径差 1）。

### 6.1 closure5 / closure6 定点微 ECO 结果

策略：能升档的驱动直接升档（零延迟代价）；DFQD4/DEL005 这类无更大档位
的，先查该网最差 setup 路径 slack，>0.15 ns 才允许插 BUFFD4 中继，
否则记录 waive——几个 ps 的 trans 超标不值得换一条新 setup 违例。

closure5（`eco10_stage2u_lastmile.tcl`）：6/6 修复、0 waive
（3 升档：BUFFD1→2 / CKBD1→2 / BUFFD2→3；3 处守卫式插 buffer，被插
路径 setup 余量分别为 6.66 / 5.10 / 7.73 ns）；`ZBUF_2_200` 拆线重布后
LVS 短路归零。副作用：两颗新插 BUFFD4 的输出网自身 trans -0.07/-0.08
（对该负载驱动仍不足），另有一批 -0.00 贴线值随重布洗牌。
首次运行因 `get_timing_paths` 不支持 `-quiet` 中止（未改动网表即失败，
无损），去掉该选项后通过。

closure6（`eco10_stage2v_transfix.tcl`）：把两颗 PDE_TRANSFIX_BUF 升到
BUFFD6、HFSNET_5036 驱动 CKBD3→4，3/3 修复。

### 6.2 收敛终态（closure6 后，已存盘）

| 项目 | 数值 |
|---|---:|
| setup | **0 违例**（reg2reg WNS +0.01 / in2reg +0.14 / reg2out +6.34） |
| hold（0.05 目标） | **0 违例**（最差 +0.078） |
| max_capacitance | WC/BC 均 0 |
| max_transition | BC 0；WC 剩 **10 条 -0.00**（见下） |
| check_routes DRC | **0** |
| check_lvs | **0 short / 0 open** |
| legality / PG connectivity | 通过 / 0 floating |
| 利用率 | 67.09%（收敛新增约 6.3k 单元） |

**已 waive 项**：10 条 max_transition 违例在两位小数报告下显示 -0.00，
即真实超标 < 5 ps（对 0.5 ns 内部指导限值 < 1%；工艺库自身限值远松于
此）。经 closure3→6 实证，任何一次重布都会在 0.50 边界重新洗牌出同量级
贴线值，继续追打只会永久震荡。工艺库限值下无任何违例。

## 6.3 最终产物（stage 3 写出）

```text
flow/local_runs/icc2_signoff_eco10/results/icc2/
├── pde_chip_top_safe.gds                          144,811,288 B
├── pde_chip_top_safe.eco10_20260804.dbu1000.gds   1nm 缩放版（KLayout 校验
│                                                   offgrid=0、23 层全匹配），
│                                                   供 EDAServer Calibre 用
├── pde_chip_top_safe.def
├── pde_chip_top_safe.postroute.v
├── pde_chip_top_safe.WC.spef.RC_WORST_125.spef
└── pde_chip_top_safe.BC.spef.RC_BEST_0.spef
```

终版全套报告在 `flow/local_runs/icc2_signoff_eco10/reports/icc2/final/`，
命名与历史 `final_*.rpt` 一致，另含 4 位精度违例报告；报告内嵌
uncertainty 守卫（setup `-0.2000` / hold `+0.0500` 不在即报错）。

## 7. 已知残留与代价

1. ~9,000 颗 DEL 单元仍在网表中（假 hold 目标的遗产）。时序/电气已在
   正确约束下收敛，它们只浪费面积与动态功耗。彻底清除需要
   `remove_buffer`/重综合级别的 ECO 或从修好的 pnr.tcl 全链重跑，
   属于可选优化，不阻塞交付。
2. DEL005/DEL015 驱动的少量 trans 违例无法用升档修（见 closure3 说明）。
3. ICC2 内部 antenna rules 仍为空（`.tf` 无规则），布线期自动插二极管
   依旧空转；外部 Calibre antenna 必须在每次重布后重跑。
4. SI 未启用（rst_n >1000 pins 被 extraction 跳过、耦合电容 lump 到地），
   与 08-03 状态相同，不是本轮引入。

## 8. 尚未完成的 signoff 项与下一步

- **Calibre antenna（下一个动作）**：1nm GDS 已备好
  （`pde_chip_top_safe.eco10_20260804.dbu1000.gds`），按 HOWTO 3.7 经
  Mac 中转 EDAServer 后执行 `./flow/calibre/run_block_signoff_final.sh
  antenna`；先核对 md5 与 VIA1-VIA5 通孔量级（应为百万级）再看违例数。
  本机与 EDAServer 无网络路由，此步需要人工/Mac 侧执行。
- 本机未安装 PrimeTime / Formality（`/home/soleil/synopsys/` 仅
  VCS/Verdi/SCL/DC/ICC2），两项 signoff 需在其他主机执行；
- 完整 Calibre DRC/LVS deck 与 3X1Z stream-out 的匹配性仍未确认
  （HOWTO 3.7 末尾的警告仍有效）。

## 9. 干净全链重跑（full_clean_20260804）——最终推荐交付

eco10 收敛后按用户要求执行了修正脚本下的全链重跑，目的：让优化器从
placement 起就面对正确约束，甩掉旧网表里为假 hold 目标插入的 ~9,000 颗
DEL 单元。**此树现为最终推荐交付，eco10 保留为审计/对照。**

### 9.1 重跑前补齐的流程缺口

1. `pnr.tcl` 固化 eco03 的 PVT 修复：`set_temperature 125/-corners WC、
   0/-corners BC；set_voltage 1.08/1.32`。探针会话证实原 mismatch 仅在
   BC 角（电压+温度各 1 处），设置后两角 "no PVT mismatches"。
2. `pnr.tcl` 固化 eco02 的 PG terminal 修复：PG 编译后自动
   `create_port`（该时点端口尚不存在——首次重跑在此断言失败后修正）+
   `create_terminal -boundary`（探针验证 `-bounding_box` 选项不存在），
   几何从各自最南水平 M5 环段中心动态切 1.6 µm 窗口。新跑坐标与 eco02
   手工版逐位一致。终版报告中 HOWTO ⑤ 的 VDD/VSS
   "unplaced/no valid pin shapes" 警告消失。
3. **read_sdc 改为逐 scenario 执行**（第 4 节补丁的遗留风险被第一次重跑
   证实：只钉 uncertainty 时，FUNC_WC 仍缺 I/O delay 与 0.5ns trans 限制，
   QoR 中无 in2reg/reg2out 组）。每 scenario `read_sdc` 后再显式拆分
   uncertainty；pre-CTS 重复 create_clock 无害。

### 9.2 运行与收敛轮次

DC 398 秒；ICC2（逐 scenario 版）1654 秒，出炉即：setup WNS **+0.74**
（0 违例，三个 path group 齐全）、hold 0、cap 0、**DRC 0、LVS 0/0**、
PVT 干净——唯一残留 50 条 max_transition（1×-0.03、12×-0.01、37×-0.00）。

| 轮次 | 操作 | 结果 |
|---|---|---|
| clean_r1 | 50 网定点升档/守卫式插 buffer（50/50 修复） | 引发上游连锁：新冒 49 trans（最差 -0.20）+ 21 cap/BC 项 |
| closure2 | 全局 route_opt+route_eco（128 秒） | 连锁全消化：仅剩 3 trans（-0.09 + 2×-0.00） |
| closure3 | 单网定点（n12297 驱动 IAO22D0→D1） | **终态：仅剩 2×-0.00** |

教训（与 eco10 一致但更清晰）：离散的后期定点修改会在限值边界激发上游
连锁与贴线洗牌，**幅度 ≥0.05 的残留应交给全局 route_opt 消化，定点手段
只用于 route_opt 明确啃不动的个别网**。

### 9.3 终态与产物

| 指标 | full_clean（终） | eco10（终） | 旧网表（eco03 基线） |
|---|---:|---:|---:|
| setup WNS | **+0.74** | +0.01 | -0.21（29 条） |
| in2reg / reg2out | +2.06 / +6.44 | +0.14 / +6.34 | +0.02 / +6.55 |
| hold | 0 | 0 | 0（修正目标后） |
| trans 残留 | **2×-0.00** | 10×-0.00 | 7,945 |
| DRC / LVS | 0 / 0-0 | 0 / 0-0 | 0 / 0-0 |
| DEL 单元 | **7** | ~9,021 | 9,029 |
| buf/inv | **21,961** | ~38,700 | 38,715 |
| 利用率 | 57.28% | 67.09% | 65.53% |
| GDS | 129 MB | 145 MB | 139 MB |

```text
flow/local_runs/full_clean_20260804/
├── dc/results/                          综合网表/SDC/SDF/SVF
├── icc2/work/icc2/pde_chip_top_safe.dlib   已收敛设计库（closure3 后存盘）
├── icc2/reports/icc2/{final,closure1..3}/  全套报告
└── icc2/results/icc2/
    ├── pde_chip_top_safe.gds                       129,272,622 B
    ├── pde_chip_top_safe.clean_20260804.dbu1000.gds  1nm 缩放版（校验 OK）
    ├── pde_chip_top_safe.def / .postroute.v
    └── pde_chip_top_safe.{WC,BC}.spef.*
```

waive 记录：2 条 max_transition 显示 -0.00（<5 ps）：`u_impl/n944_CDR1`、
`g_row_2__g_col_7__u_pe/u_red_we`。工艺库限值下无违例。

signoff 缺口与 eco10 相同：Calibre antenna 待送 EDAServer（1nm GDS 已
备好）；PrimeTime/Formality 本机无安装；完整 DRC/LVS deck 匹配性未确认。

## 10. 证据速查

```text
# eco10 分支（从 eco03 复制）
flow/local_runs/icc2_signoff_eco10/work/icc2/pde_chip_top_safe.dlib

# 根因证据：两 scenario 的 write_sdc 对照（44 行 vs 403 行）
flow/local_runs/icc2_signoff_eco10/reports/icc2/uncertainty_fix/before_effective_FUNC_WC.sdc
flow/local_runs/icc2_signoff_eco10/reports/icc2/uncertainty_fix/before_effective_FUNC_BC.sdc

# stage 1 / 1b / 各收敛轮报告
flow/local_runs/icc2_signoff_eco10/reports/icc2/uncertainty_fix/   (before_*/after_*/s1b_*)
flow/local_runs/icc2_signoff_eco10/reports/icc2/closure1/ ... closure4/

# 各阶段脚本与 launcher
flow/local/eco10_stage1_constraints.tcl   flow/local/run_eco10_stage1.sh
flow/local/eco10_stage1b_restore_wc.tcl   flow/local/run_eco10_stage1b.sh
flow/local/eco10_stage2_closure.tcl       flow/local/run_eco10_stage2.sh
flow/local/eco10_stage2t_targeted.tcl     flow/local/run_eco10_stage2t.sh
flow/local/eco10_stage3_writeout.tcl      flow/local/run_eco10_stage3.sh

# 源头补丁
flow/dc/synth.tcl   （uncertainty 拆分）
flow/icc2/pnr.tcl   （逐 scenario read_sdc + uncertainty 拆分 + PVT 角 + PG terminal）

# 干净全链重跑（最终推荐交付，见第 9 节）
flow/local_runs/full_clean_20260804/dc/results/
flow/local_runs/full_clean_20260804/icc2/work/icc2/pde_chip_top_safe.dlib
flow/local_runs/full_clean_20260804/icc2/reports/icc2/{final,closure1,closure2,closure3}/
flow/local_runs/full_clean_20260804/icc2/results/icc2/
flow/local/clean_r1_transfix.tcl      flow/local/run_clean_r1.sh
flow/local/clean_r3_lastnet.tcl       flow/local/run_clean_r3.sh
flow/local/run_clean_writeout.sh
```
