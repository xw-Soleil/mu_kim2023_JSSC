# 怎么查看和运行 —— 操作手册

面向：接手这套东西、要看结果或重跑流程的人。
配套阅读：`flow/local/README.md`（讲的是**为什么**这么做、踩过哪些坑）。
本文只讲**怎么操作**。

> **2026-08-03 状态**：Ubuntu 本地已实际完成一次 RTL -> DC -> 新 NDM -> ICC2 ->
> GDS/DEF/netlist/SPEF 全链回归，正式设计插入 136,478 个 filler，新 GDS 无空壳单元。
> 流程能跑通，但新结果仍有 1 个 open、2 条 short DRC 和小量时序/约束违例。
> ICC2 内部 antenna rules 仍为空；新 GDS 已另在 EDAServer 跑 Calibre foundry
> antenna deck，26 checks、0 results。该结论不代表完整 DRC/LVS signoff。

机器：`soleilUbuntu`（跑 Synopsys）+ `EDAServer`（跑 Calibre，因为 Calibre 的
license 只在那边）。两台之间没有网络路由，文件要经你的 Mac 中转。

---

## 0. 三分钟上手

```bash
ssh soleilUbuntu

# 看最新完整回归（不用进容器、不用 license）
cd ~/code/DigitalIC/PDE/pdeMujunjie
RUN=flow/local_runs/icc2_20260803_full
sed -n '1,120p' $RUN/reports/icc2/final_qor.rpt
cat $RUN/reports/icc2/final_lvs.rpt                 # 1 open + 2 short
cat $RUN/reports/icc2/final_utilization.rpt
ls -la $RUN/results/icc2/                           # GDS / DEF / 后仿网表 / SPEF
```

要重跑流程才需要进容器、才需要 license。见第 3 节。

---

## 1. 东西都在哪

### soleilUbuntu

```
~/code/DigitalIC/PDE/
├── SYNOPSYS_SETUP.md              环境说明（开头有一段 2026-08-02 的更正，先看）
└── pdeMujunjie/                   项目本体，从 EDAServer 搬来
    ├── README.md                  设计本身的说明（RTL 架构、仿真怎么跑）
    ├── src/ tb/ sim/ doc/         RTL、testbench、仿真、设计笔记
    ├── flow/
    │   ├── icc2/pnr.tcl           ★ 主流程脚本，支持隔离输出目录
    │   ├── icc2/create_ndm.tcl    建参考库（完整建库已验证，见 README 3.3）
    │   ├── dc/synth.tcl           DC 综合（本地完整综合已验证）
    │   ├── openroad/              旧方案的脚本，保留作参考，本地不用
    │   ├── calibre/               签核脚本，实际在 EDAServer 上跑
    │   ├── local/                 ★ 本地适配层，见下
    │   ├── local_runs/            ★ Ubuntu 隔离回归；最新见 icc2_20260803_full
    │   ├── results/icc2/          ★ 最终产物
    │   ├── results/dc/            综合网表 + SDC（P&R 的输入）
    │   ├── reports/icc2/          ★ 所有签核报告
    │   └── work/icc2/             设计库 .dlib、参考 NDM、打过补丁的脚本
    └── local_artifacts/            根目录工具日志归档（内容不纳入 Git）

~/code/DigitalIC/stdlib/tsmc65/    从服务器搬来的 PDK 子集（tech/LEF/GDS/CCS/TLU+）
```

`flow/local/` 里各文件的职责：

| 文件 | 做什么 |
|------|--------|
| `env_local.sh` | 所有路径。`pnr.tcl` 的每个输入都有 `PDE_*` 环境变量可覆盖，靠它把原脚本指到本地 |
| `run_full_flow.sh` | ★ 一次串联 RTL→DC→ICC2→GDS，每轮创建独立输出树 |
| `run_pnr.sh` | ★ 跑完整 P&R。带重试（原因见第 5 节） |
| `pnr_local.tcl` | 设并行核数 + 给 `pnr.tcl` 打 2018→2024 的 API 补丁，然后 source 它 |
| `run_dc.sh` | 本地完整 DC 综合，默认隔离输出到 `flow/local_runs/dc/` |
| `run_finish.sh` + `finish.tcl` | ★ 从存盘的布线结果**续跑尾部**，不重做 place/CTS/route |
| `run_create_ndm.sh` | 本地隔离重建参考库，正式入口已成功运行 |
| `rescale_gds.py` | GDS 精度缩放（KLayout），带无损校验 |
| `merge_gds.py` | 给旧 NDM 流出的 GDS 补齐厂商单元内部几何 |
| `README.md` | 背景、根因、踩坑记录 |

### EDAServer

```
~/PDE/pdeMujunjie/
├── flow/calibre/                       签核脚本（原有）
├── flow/reports/calibre/               ★ 天线检查结果
│   ├── READ_ME_FIRST.md                ★ 先读！哪份有效哪份作废
│   ├── pde_chip_top_safe_rebuilt_20260803_antenna.summary  ★ 最新有效结果
│   ├── pde_chip_top_safe_icc2full_antenna.summary   ✅ 有效结果
│   └── pde_chip_top_safe_icc2_antenna.summary       ❌ 作废（丢通孔）
└── flow/results/icc2_from_ubuntu/      从 Ubuntu 传过来的版图
    ├── pde_chip_top_safe.full.gds      8 月 2 日旧版图：已通过 antenna deck
    ├── pde_chip_top_safe.gds           8 月 2 日旧 NDM 原始输出（缺单元几何）
    ├── pde_chip_top_safe.def
    └── *.merged*.gds                   fdi2gds 那条废弃路线的产物
```

---

## 2. 怎么看结果

### 2.1 看报告（最省事，不需要 license）

```bash
cd ~/code/DigitalIC/PDE/pdeMujunjie
R=flow/local_runs/icc2_20260803_full/reports/icc2
```

| 想知道什么 | 看哪个 |
|-----------|--------|
| 时序、面积、单元数总览 | `final_qor.rpt` |
| 建立时间最差路径明细 | `final_setup_timing.rpt`（298K，用 `less`） |
| 保持时间 | `final_hold_timing.rpt` |
| 所有约束违例 | `final_constraints.rpt` |
| **LVS 短路/开路** | `final_lvs.rpt` ← 新结果 1 open + 2 条 M5 short |
| 布线 DRC、开路、天线 | `final_routes.rpt` |
| 利用率 | `final_utilization.rpt` |
| 功耗 | `final_power.rpt`（**没读 SAIF，动态功耗只能当下限**） |
| 时钟树质量 | `final_clock_qor.rpt` |
| 拥塞 | `final_congestion.rpt` |
| 摆放合法性 | `final_legality.rpt` |
| PG 连接性 | `final_pg_connectivity.rpt` |
| 流程日志全文 | `pnr.local.log` / `finish.local.log` |

快速抓关键数：

```bash
grep -A 8 "Timing Path Group" $R/final_qor.rpt
grep -E "short violations|open nets" $R/final_lvs.rpt
grep "Utilization Ratio" $R/final_utilization.rpt
```

### 2.2 看版图

**KLayout（快，不要 license）**

```bash
klayout ~/code/DigitalIC/PDE/pdeMujunjie/flow/local_runs/icc2_20260803_full/results/icc2/pde_chip_top_safe.gds
```

新 NDM 的原始 GDS 已直接包含完整几何：KLayout 检查为 198 structures、0 empty cells，
181 个实际使用的厂商单元逐层图形数/面积全匹配。只有 8 月 2 日旧 NDM 的历史 GDS
需要 `.full.gds` 合并补几何。

**ICC2 GUI（能查时序、拥塞、定位违例，要 license）**

```bash
syndock                                    # 进容器
source ~/code/DigitalIC/PDE/pdeMujunjie/flow/local/env_local.sh
cd ~/code/DigitalIC/PDE/pdeMujunjie
flow/local/snps_no_udev.sh icc2_shell
```

进去之后：

```tcl
open_lib flow/local_runs/icc2_20260803_full/work/icc2/pde_chip_top_safe.dlib
open_block pde_chip_top_safe.design        # 注意要 .design 后缀
link_block
start_gui
```

> 不要直接绕过 `snps_no_udev.sh`；未包装的 SCL udev 路径仍可能随机段错误。

定位新回归的 open/short（坐标来自 `final_lvs.rpt`）：

```tcl
# M5 short: bnd_north_flat[57] <-> n5244_CDR1
gui_zoom -window {619.8 433.6 620.8 434.0}
# open: HFSNET_639
gui_zoom -window {136.0 528.5 168.0 564.0}
```

### 2.3 看天线检查结果（在 EDAServer）

```bash
ssh EDAServer
cd ~/PDE/pdeMujunjie/flow/reports/calibre
cat READ_ME_FIRST.md                                      # 先读这个
cat pde_chip_top_safe_rebuilt_20260803_antenna.summary     # 最新有效结果
```

判断一份天线结果是否可信，**先看通孔数量**：

```bash
sed -n '/ORIGINAL LAYER STATISTICS/,/^---------/p' \
    pde_chip_top_safe_icc2full_antenna.summary | grep VIA
```

新结果应该是**百万级**（VIA1 约 49.9 万、VIA2 约 53.5 万）。
如果只有几万，说明通孔被丢了，那份结果作废。

---

## 3. 怎么重新跑

### 3.0 前置：license 服务器

每次开机做一次（在**宿主机**，不是容器里）：

```bash
/home/soleil/synopsys/scl/2024.06/linux64/bin/lmgrd \
    -c /home/soleil/synopsys/scl/2024.06/admin/license/Synopsys.dat \
    -l /home/soleil/synopsys/lmgrd.log
```

确认：

```bash
/home/soleil/synopsys/scl/2024.06/linux64/bin/lmutil \
    lmstat -c 27000@localhost -f ICCompilerII-4
```

期望看到 `Total of 99 licenses issued`。

> ⚠ `lmstat` 能查到 feature **不等于**工具能签出。真正的验证是启动 `icc2_shell`
> 跑一条需要 license 的命令。这个区别当初误导过人，见 README 第 4 节。

### 3.1 一次跑完整 Synopsys 实现链

```bash
cd ~/code/DigitalIC/PDE/pdeMujunjie
PDE_FULL_RUN_TAG=my_run \
  distrobox enter synopsys-focal -- $PWD/flow/local/run_full_flow.sh
```

输出隔离到 `flow/local_runs/full_my_run/{dc,icc2}/`，已有目录会拒绝覆盖。脚本先检查
DC 网表/SDC，再把它们显式传给 ICC2；默认使用本地重建 NDM 和 `SITE core`。本次实测
DC 398 秒、ICC2 2014 秒，完整链约 40 分钟。

### 3.2 DC 综合（RTL → gate netlist/SDC）

入口默认拒绝覆盖已有结果，所以每轮给一个新目录：

```bash
cd ~/code/DigitalIC/PDE/pdeMujunjie
PDE_DC_OUTPUT_ROOT=$PWD/flow/local_runs/dc_next \
  distrobox enter synopsys-focal -- $PWD/flow/local/run_dc.sh
```

2026-08-03 完整回归耗时 398 秒，生成 DDC、Verilog、SDC、SDF 和 SVF。成功判据
同时检查 shell 退出码、行首 `PDE_DC_DONE` 和实际网表/SDC。

### 3.3 重建参考 NDM

```bash
PDE_NDM_BUILD_OUTPUT=$PWD/flow/work/icc2/ref_rebuilt_next/tcbn65lp_6lmT1.ndm \
  distrobox enter synopsys-focal -- $PWD/flow/local/run_create_ndm.sh
```

默认候选输出为 `flow/work/icc2/ref_candidate/...`，且拒绝覆盖现用库。2026-08-03
正式回归耗时 22 秒；成功判据还会检查 `reflib.ndm` 实际存在。建库成功不代表
antenna rules 已生成，后者当前仍为 0。

### 3.4 完整 P&R（从综合网表开始）

```bash
distrobox enter synopsys-focal -- \
  ~/code/DigitalIC/PDE/pdeMujunjie/flow/local/run_pnr.sh
```

- 本次新 NDM 回归耗时 2014 秒（约 33.6 分钟）
- 会自动清掉上次的 `.dlib` 重建
- 结束打印 `RESULT: OK` 或 `RESULT: FAILED`
- 日志 `flow/reports/icc2/pnr.local.log`

`env_local.sh` 现已默认使用新 NDM 和 `core` site；单独跑 P&R 时如要接本地 DC 隔离结果，
仍需显式给网表/SDC 和输出根：

```bash
PDE_DC_NETLIST=$PWD/flow/local_runs/dc/results/pde_chip_top_safe.v \
PDE_DC_SDC=$PWD/flow/local_runs/dc/results/pde_chip_top_safe.sdc \
PDE_ICC2_OUTPUT_ROOT=$PWD/flow/local_runs/icc2_next \
  distrobox enter synopsys-focal -- $PWD/flow/local/run_pnr.sh
```

要脱离终端跑（推荐，避免 ssh 断线中断）：

```bash
ssh soleilUbuntu 'setsid nohup distrobox enter synopsys-focal -- \
  /home/soleil/code/DigitalIC/PDE/pdeMujunjie/flow/local/run_pnr.sh \
  > /home/soleil/code/DigitalIC/PDE/pdeMujunjie/flow/reports/icc2/pnr.console.log 2>&1 < /dev/null &'
```

盯进度：

```bash
tail -f flow/reports/icc2/pnr.console.log | grep -E "Starting '|Ending '|^PDE_|^RESULT"
```

顶层阶段标记是**带引号**的，例如 `Information: Starting 'clock_opt' (FLW-8000)`。

### 3.5 只重跑尾部（布线已完成的情况）

`route_opt` 之后会 `save_block` 存盘。如果只是后面的填充单元/报告/写出出了问题，
不必重做前面 30 分钟：

```bash
distrobox enter synopsys-focal -- \
  ~/code/DigitalIC/PDE/pdeMujunjie/flow/local/run_finish.sh

# 8 月 2 日旧 .dlib 使用旧 NDM，续跑它仍需跳过 filler
PDE_SKIP_FILLERS=1 distrobox enter synopsys-focal -- \
  ~/code/DigitalIC/PDE/pdeMujunjie/flow/local/run_finish.sh
```

耗时约 3 分钟。`finish.tcl` 的尾部代码是从 `pnr.tcl` 按注释锚点切出来 eval 的，
不是手抄，所以改 `pnr.tcl` 这边会自动跟着变。

### 3.6 改流程参数

一般参数优先改这两处：

- 路径、顶层名、网表位置 → `flow/local/env_local.sh`
- 并行核数、API 兼容补丁 → `flow/local/pnr_local.tcl`

举例，把并行核数从 8 调到 16：

```tcl
# flow/local/pnr_local.tcl
set_host_options -max_cores 16
```

打补丁的写法（`pnr_local.tcl` 里的替换表）：

```tcl
set patches {
  {-pin_spacing 0\.4}  {-pin_spacing 2}   {说明文字}
}
```

补丁后的脚本会落到本轮 `PDE_ICC2_OUTPUT_ROOT/work/icc2/pnr.patched.tcl`，可以直接
与 `flow/icc2/pnr.tcl` 做 `diff`。

### 3.7 重跑天线检查（跨两台机器）

**第一步：把新 NDM 的完整 GDS 缩放到 deck 要求的 1nm**

```bash
cd ~/code/DigitalIC/PDE/pdeMujunjie/flow/local_runs/icc2_20260803_full/results/icc2
R=$PWD
P=~/code/DigitalIC/stdlib/tsmc65/tcbn65lp_200b

# (1) 精度 0.1nm → 1nm。脚本会校验 offgrid=0、逐层面积一致，打印 RESULT OK 才算数
klayout -b -r ../../../../local/rescale_gds.py \
  -rd inp=$R/pde_chip_top_safe.gds \
  -rd outp=$R/pde_chip_top_safe.rebuilt_20260803.dbu1000.gds
```

新 GDS 已有完整单元，不要再 merge。只有处理 8 月 2 日旧 `flow/results/icc2` GDS 时，
才额外执行：

```bash
cd ~/code/DigitalIC/PDE/pdeMujunjie/flow/results/icc2
R=$PWD
P=~/code/DigitalIC/stdlib/tsmc65/tcbn65lp_200b
klayout -b -r ../../local/merge_gds.py \
  -rd design=$R/pde_chip_top_safe.dbu1000.gds \
  -rd cells=$P/Back_End/gds/tcbn65lp_200a/tcbn65lp.gds \
  -rd outp=$R/pde_chip_top_safe.full.gds
```

**第二步：经 Mac 中转到 EDAServer**（两台机之间不通）

```bash
# 在 Mac 上执行
ssh soleilUbuntu "cd \$HOME/code/DigitalIC/PDE/pdeMujunjie/flow/local_runs/icc2_20260803_full/results/icc2 && \
    tar czf - pde_chip_top_safe.rebuilt_20260803.dbu1000.gds" \
  | ssh EDAServer 'cd $HOME/PDE/pdeMujunjie/flow/results/icc2_from_ubuntu && tar xzf -'
```

> tar 退出码可能是 2 —— 是远端 shell 退出时吐的终端控制字符混进流尾，
> gzip 会忽略。**用 md5 校验，别看退出码。**

```bash
ssh soleilUbuntu 'md5sum ~/code/DigitalIC/PDE/pdeMujunjie/flow/local_runs/icc2_20260803_full/results/icc2/pde_chip_top_safe.rebuilt_20260803.dbu1000.gds'
ssh EDAServer   'md5sum ~/PDE/pdeMujunjie/flow/results/icc2_from_ubuntu/pde_chip_top_safe.rebuilt_20260803.dbu1000.gds'
```

**第三步：在 EDAServer 上跑**

```bash
ssh EDAServer
cd ~/PDE/pdeMujunjie
export PDE_GDS=$PWD/flow/results/icc2_from_ubuntu/pde_chip_top_safe.rebuilt_20260803.dbu1000.gds
export PDE_ANT_RDB=$PWD/flow/results/calibre/pde_chip_top_safe_rebuilt_20260803_antenna.db
export PDE_ANT_SUMMARY=$PWD/flow/reports/calibre/pde_chip_top_safe_rebuilt_20260803_antenna.summary
export PDE_ANT_LOG=$PWD/flow/reports/calibre/pde_chip_top_safe_rebuilt_20260803_antenna.log
./flow/calibre/run_block_signoff_final.sh antenna
```

约 45 秒。**跑完先看通孔数量**（第 2.3 节），再看违例数。

2026-08-03 的上述新 GDS 已实跑：54 秒，26 checks、0 results，VIA1-VIA5
展开合计 1,228,347，summary runtime warnings 为空。

> `run_block_signoff_final.sh` 还支持 `drc` 和 `all`。DRC deck 是
> `CLN65S_6M_4X1Z.23a`，注意它是 4X1Z 金属方案，而流出用的是 `gdsout_3X1Z.map`，
> 这个不一致**没有验证过**，跑 DRC 前先确认。天线 deck `CN65S_6M.ANT.23a`
> 是通用 6M 的，不受影响。

---

## 4. 当前结果与已知问题

> **2026-08-04 更新**：本节下面的 8 月 3 日状态已被超越（两次）。约束根因
> （read_sdc 把全部 scenario 级约束只灌进当时 current 的 FUNC_BC）已定位；
> eco10 在修复约束后收敛通过；随后用修正过的 synth.tcl/pnr.tcl（逐
> scenario read_sdc、PVT 角、PG terminal）完成了**全链干净重跑
> `full_clean_20260804`，这是当前最终推荐交付**：setup WNS +0.74、
> hold/cap/DRC/LVS 全零、全库仅 7 颗 DEL 单元（旧网表 9,029）、buf/inv
> 少 43%，仅 2 条 -0.00 trans 记录 waive。产物在
> `flow/local_runs/full_clean_20260804/icc2/{results,reports}/icc2/`，
> 1nm GDS 已备好待送 EDAServer 跑 antenna。eco10 树保留作审计对照。
> 全部细节见 `doc/worklogs/CLAUDE_UBUNTU_WORKLOG_2026-08-04.md`。

### 最新完整回归（2026-08-03）

| 项目 | 结果 |
|------|------|
| 完整链 | Ubuntu 本地 RTL -> DC -> ICC2 -> GDS/DEF/netlist/SPEF，成功完成 |
| 建立时间 WC | WNS/TNS 约 −0.01/−0.01 ns，2 条违例路径 |
| 保持时间 BC | WNS/TNS −0.02/−0.42 ns，195 条违例路径 |
| 布线 | 131,161 网络，**1 open、2 条 short DRC** |
| LVS | 同一个 M5 net pair 的 2 条 short 记录；1 个 open net |
| 约束 | 1 max-transition、13 max-capacitance（constraints report 口径） |
| filler/合法性 | 136,478 个 filler；264,600 DEF components；0 legality violation |
| 利用率 | 65.53% |
| GDS | 198 structures、0 empty cells；181 个已用厂商单元几何全匹配 |
| Calibre 天线 | 新 GDS：26 checks、0 results；VIA1-VIA5 约 122.8 万，runtime warnings 为空 |

隔离目录：`flow/local_runs/icc2_20260803_full/`。`PDE_ICC2_DONE` 和全部产物存在；
ICC2 耗时 2014 秒、峰值 3890.58 MB，license 首次启动成功。

### 已知问题

**① 先修 open 与 M5 short**

```
open: u_impl/u_core/HFSNET_639
      bbox (136.2500,528.7100)-(167.6900,563.6900)
short pair: u_impl/bnd_north_flat[57] <-> u_impl/u_core/u_boundary/n5244_CDR1
      M5 bbox (620.1400,433.8000)-(620.6600,433.8500)
      M5 bbox (619.9500,433.8100)-(620.5900,433.8500)
```

两条 short 记录是同一对 net 的相邻重叠区域。先在最新 `.dlib` 中做 ECO reroute，
然后重新生成全部 final reports，不能沿用 8 月 2 日的坐标和修复判断。

**② 时序和 max-cap 没收干净**。setup 很小，但 hold 有 195 paths；不要只看两位小数。

**③ filler/site 已解决**。正式回归已插入 136,478 个 filler，legality 为 0；
8 月 2 日旧 `.dlib` 仍是跳过 filler 的历史结果。7 个 physical-only `FILL*` master
仍报 `CHF-011 not marked filler type`；显式列表插入成功，但 NDM purpose 元数据可继续完善。

**④ 天线规则没进 ICC2** —— 布线时的自动插二极管仍空转。`read_tech_lef`
用 `update`/`overwrite` 两种策略实测后规则数仍为 0。新 GDS 的外部 Calibre antenna
已通过，但每次 ECO/重布后都必须重跑，不能由 ICC2 流程内保证。

site/filler 与 antenna 不能再写成同一个根因。LEF site 已成功保留；LEF antenna
声明不会自动变成 ICC2 `define_antenna_*` router rules，见 README 3.4。

**⑤ 顶层 VDD/VSS 没有有效 pin shape**。PG connectivity 对标准单元为 0 floating，
但 route/LVS 报告仍提示顶层 VDD/VSS unplaced/no valid pin shapes，完整 LVS 前需补齐。

**⑥ 当前 extraction 不是 SI signoff 配置**。`rst_n` 因超过 1000 pins 被跳过，coupling
capacitance 被 lump 到 ground，且 post-route optimization 明确提示 SI analysis 未启用。

### 历史结果（2026-08-02）

旧 NDM 那轮是 0 open、最终 8 route DRC、3 条 M1 short 记录（2 个位置）、未插 filler；
对应外部 Calibre antenna 为 26 checks、0 results。不要与上面的 8 月 3 日新回归混用。

---

## 5. 故障处理

### 5.1 ICC2 启动就崩（旧路径约 75% 概率，已加稳定 workaround）

```
MEM Fatal: Out of memory (MEM-1)
Fatal: Internal system error, cannot recover.  Error code=11
```

**这是 SCL 的 udev 硬件枚举路径崩溃，不是设计内存不足或 Tcl 错误。** 未屏蔽时的
对照测试为 2/8 成功、6/8 在 `udev_get_userdata`/`scl_lc_checkout` 段错误。
Ubuntu 24.04/systemd 255 容器也会在 `sd-netlink` assertion 中退出，所以不能再简单归因于
“245 读取 255 数据库”。

所有本地批处理入口都会通过 `flow/local/snps_no_udev.sh` 启动工具，让 SCL 改走
非 udev fallback；回归为 ICC2 12/12、Library Manager 12/12 成功。交互式使用：

```bash
source flow/local/env_local.sh
flow/local/snps_no_udev.sh icc2_shell
```

wrapper 只修改子进程的 `LD_LIBRARY_PATH`，不改系统 libudev 或 `/run/udev`。
原来的最多 25 次重试仍保留作为第二层保护，不再是主要绕法。

判据很干净：崩溃发生在脚本产生**任何输出之前**，所以日志里没有
`^PDE_ICC2: top=` 就是启动崩溃，可以安全重跑；有了就说明已进入流程，
这时失败是真失败，不该重试。

> ⚠ 判断是否成功，grep 一定要**锚定行首**（`^PDE_ICC2_DONE`）。
> icc2_shell 会回显脚本源码，不加 `^` 会匹配到源码里的 `puts "PDE_ICC2_DONE ..."`
> 从而误判成功。这个坑踩过。

诊断时设置 `PDE_SNPS_USE_SYSTEM_UDEV=1` 可以恢复旧行为，但会重新引入随机崩溃。
如果 Synopsys 提供对应 SCL hotfix，应优先使用官方修复。

### 5.2 `icc2_lm_shell` 与建库已验证

通过 `snps_no_udev.sh` 的最小 checkout 已连续 12/12 成功。`run_create_ndm.sh`
默认写到 `ref_candidate`、不移动现用 NDM；正式建库已在 22 秒内成功，当前 active
输出约 309 MiB：

```text
flow/work/icc2/ref_rebuilt/tcbn65lp_6lmT1.ndm
```

855 个 LEF/GDS 同名 block 已用 `read_gds -merge_action update` 合并，layout view 和
LEF cell site 均已验证。ICC2 antenna rules 仍为空，这是独立的技术规则问题。

### 5.3 Calibre 报 `Rule file precision ... not consistent`

版图精度和 deck 的 `PRECISION 1000` 不一致。**不要改 deck**
（还得连 `RESOLUTION` 一起等比例改，而且会破坏 `prepare_block_signoff_decks*.sh`
对 foundry deck 的 SHA-256 校验）。用 `rescale_gds.py` 把版图转到 1nm。

### 5.4 Calibre 报 `Cell XXX is referenced but not defined`

先确认是不是 8 月 2 日旧 NDM 的 GDS。旧版图用 `merge_gds.py` 与厂商 GDS 合并；
新 `ref_rebuilt` 流出的 GDS 若仍出现此错误，应视为建库/stream-out 回归，不要再次盲目 merge。

### 5.5 天线结果"全 0"但可疑

先查通孔数量（第 2.3 节）。只有几万说明通孔被丢了。
**千万别用 `fdi2gds` 从 ICC2 的 DEF 生成签核版图** —— ICC2 用技术库通孔名
（`VIA23` 等），LEF 里没定义，上百万通孔会被静默丢弃。应直接使用 ICC2 GDS；
只有旧 NDM 缺 leaf geometry 时才额外 merge。

### 5.6 写脚本时的两个坑（都踩过）

- `pkill -f xxx` 会匹配到**自己的命令行**（命令行文本里含 `xxx`）从而自杀。
  按 PID 杀：`ps -eo pid,args | awk '/pat/ && !/awk/ {print $1}' | xargs -r kill`
- 同理，用 `pgrep -f xxx` 写等待循环会永远等不到结束。能顺序执行就别用等待循环。

---

## 6. 清理过什么

2026-08-02 删除了 101 个纯崩溃产物（2.2M），清单存在 `/tmp/cleanup_list.txt`：

- `crte_*.txt` 45 个（Synopsys 崩溃运行时快照）
- `Synopsys_stack_trace_*.txt` 45 个
- `flow/reports/icc2/*.startup-crash.*` 11 个（重试机制的日志副本）

其余全部保留。`check_design.ems`（4.4M）看着像垃圾，其实是 `check_design`
的错误数据库，能在 ICC2 GUI 里加载定位，已归档到
`local_artifacts/icc2/check_design/2026-08-04/check_design.ems`，**别删**。
