# 从 EDAServer 迁移到 soleilUbuntu 的本地后端流程

服务器上因为缺 `ICCompilerII-4/-8` 实现级 license，后端曾用 OpenROAD 顶替。
这台机器的 license 里有实现级 feature，所以把数据搬过来用 Synopsys DC/ICC2 重做。

> **2026-08-03 当前边界**：Ubuntu 本地 DC -> 新 NDM -> ICC2 -> GDS/DEF/netlist/SPEF
> 已完成一次正式隔离回归，filler 也已插入。流程能力已跑通，但新结果仍有 1 个 open、
> 2 条 short DRC 和小量时序/约束违例。ICC2 内部 antenna rule 仍为 0；新 GDS
> 已在 EDAServer 重跑 foundry antenna deck 并得到 26 checks、0 results。

---

## 1. 搬了什么

两台机之间没有路由（EDAServer 上没有 Tailscale），所有数据经 Mac 中转，
关键文件都做了 md5 比对。

| 内容 | 服务器路径 | 本地路径 | 大小 |
|------|-----------|---------|------|
| 项目（脚本/RTL/DC 结果/报告） | `~/PDE/pdeMujunjie` | `~/code/DigitalIC/PDE/pdeMujunjie` | 62M |
| PDK 子集（tech/LEF/GDS/CCS db/TLU+） | `/ssd0/PDKs/TSMC65nm/.../tcbn65lp_200b` | `~/code/DigitalIC/stdlib/tsmc65/tcbn65lp_200b` | 916M |
| 参考 NDM | `flow/work/icc2/ref/tcbn65lp_6lmT1.ndm` | `flow/work/icc2/ref_from_server/…` | 322M |

**没搬**：`sim/`（VCS 编译产物 34M）、`flow/work/openroad` 与
`flow/results/openroad`（2.3G 的 DEF/guide，是被替代掉的那条路线的中间结果）、
`results/dc/*.sdf`（185M，P&R 用不到）。需要的话再单独拉。

设计规模（DC 报告）：93,358 个 leaf cell、23,905 个触发器、无 macro，
cell area 412,524 µm²，时钟 10 ns 且综合后有 4.08 ns 余量。

## 2. 怎么跑

```bash
syndock                                   # 进容器
flow/local/run_full_flow.sh               # RTL -> DC -> ICC2 -> GDS，隔离输出
```

`flow/local/` 里的主要入口：

- `env_local.sh` —— 所有路径；预先设置的 `PDE_*` 会被保留，便于隔离回归。
- `run_full_flow.sh` —— 串联 DC 与 ICC2，每次创建独立的时间戳目录。
- `run_dc.sh` —— 本地 DC 完整综合入口，默认写到 `flow/local_runs/dc/`。
- `pnr_local.tcl` —— 设 `-max_cores 8`，按替换表给 `pnr.tcl` 打补丁（见第 4 节），
  写到本轮输出树的 `work/icc2/pnr.patched.tcl` 再 source，改动可 diff。
- `run_pnr.sh` —— 带重试的入口，理由见下面第 3 节。
- `run_finish.sh` + `finish.tcl` —— 从存盘的布线结果续跑尾部（填充单元 → 报告 → 写出），
  不重做 place/CTS/route。尾部代码从 `pnr.tcl` 按注释锚点切出来 eval，不手抄。
  `PDE_SKIP_FILLERS=1` 可跳过填充单元。
- `snps_no_udev.sh` —— 只对被包装的 Synopsys 进程关闭不稳定的 udev 枚举路径。
- `run_create_ndm.sh` —— 本地隔离重建 NDM；已完整成功，见 3.3。
- `merge_gds.py` —— 给旧 NDM 流出的 GDS 补厂商单元几何，见第 6 节。

## 2.1 跑出来的结果（2026-08-02）

| 项目 | 结果 |
|------|------|
| 建立时间 WC | 最差 slack −0.02 ns，TNS −0.03，3 条违例路径 |
| 保持时间 BC | 最差 −0.01 ns，总计 −0.28 ns |
| 布线 | 117,285 网络，0 开路，**最终 8 条 DRC**（5 minimum edge length、1 same-net spacing、2 short） |
| `check_lvs` | **3 条 M1 short 记录，对应 2 个物理位置**，在 `g_row_10__g_col_1__u_pe/u_r_red` 和 `g_row_14__g_col_0__u_pe/u_sol` |
| 利用率 | 63.6%（floorplan 目标 55%，优化后涨的） |
| 单元数 | 93,358 → 112,970；buf/inv 8,482 → 28,545 |
| **Calibre 天线** | **26 checks、0 results**；AP/RV 无几何，DNW 覆盖也需按设计结构解释，见第 6 节 |

这只是 8 月 2 日的历史结果：时序、route DRC 和 LVS 都未收敛，filler 也被跳过。

## 2.2 新 NDM 完整回归（2026-08-03）

输入和输出均在 Ubuntu：

```text
DC:   flow/local_runs/dc/
ICC2: flow/local_runs/icc2_20260803_full/
NDM:  flow/work/icc2/ref_rebuilt/tcbn65lp_6lmT1.ndm
```

| 项目 | 结果 |
|------|------|
| 完整链 | 本地 RTL -> DC netlist/SDC -> ICC2 floorplan/place/CTS/route/filler -> GDS/DEF/netlist/SPEF |
| ICC2 运行 | 首次启动成功，2014 秒，8 线程，峰值 3890.58 MB |
| filler | 136,478 个；最终 264,600 components；legality 0；7 个 master 仍有 `CHF-011` purpose 元数据 warning |
| 时序 | WC setup WNS/TNS 约 -0.01/-0.01 ns、2 paths；BC hold WNS/TNS -0.02/-0.42 ns、195 paths |
| route/LVS | 131,161 nets；**1 open、2 short DRC**，同样由 `check_lvs` 报出 |
| 约束 | 1 max-transition、13 max-capacitance（`final_constraints.rpt` 口径） |
| GDS | 139,399,862 bytes；198 structures、0 empty/undefined cells；181 个已用厂商单元逐层图形数和面积全匹配 |
| Calibre antenna | 新 GDS 26 checks、0 results；VIA1-VIA5 约 122.8 万；runtime warnings 为空 |

这证明 Synopsys 实现链能在 Ubuntu 连续运行到 GDS，但不代表 signoff。新 GDS 只跑了
Calibre antenna，尚未跑完整 Calibre DRC/LVS；ICC2 自身报告的 open/short 也必须先修。
此外 `rst_n` 因超过 1000 pins 被 extraction 跳过，coupling capacitance lump 到 ground，
SI analysis 未启用，当前 SPEF/时序口径不能当作 SI signoff。

## 3. 这台机器上踩到的环境问题

### 3.1 容器里任何 Synopsys 工具都起不来（已修）

`icc2_shell` 一启动就 `MEM Fatal: Out of memory`（申请 55 GB）然后段错误。

原因：容器 `/etc/nsswitch.conf` 里 `passwd`/`group` 带 `systemd`，容器自带的
libnss_systemd 是 systemd **245**（Ubuntu 20.04），宿主机是 **255**，
工具调 `getgrouplist()` 时拿到垃圾组数，据此 malloc 后崩掉。

修法：去掉 `systemd`，只留 `files`（容器内 `id`、`getent group` 走 files 完全正常）。
备份在容器里的 `/etc/nsswitch.conf.bak.before-icc2-fix`。

> 注意这个改动在容器文件系统里。如果哪天重建了 `synopsys-focal` 容器，要重新改。

### 3.2 SCL 签 license 时随机段错误（已稳定绕开）

修好 3.1 之后，未处理的 `icc2_shell` 仍有约 75% 概率在 Tcl 执行前崩溃。
2026-08-03 的独立对照为 8 次成功 2 次、`udev_get_userdata`/`scl_lc_checkout`
段错误 6 次。异常内存申请可达 180 GB，但这不是设计内存不足。

进一步实验修正了原先“只要把容器升级到 systemd 255 就能根治”的判断：

- Focal 的 `udevadm` 连续解析宿主 udev 数据库全部成功，说明 libudev 245 不是普遍不能读；
- 去掉 `+dmi:id` 的全部 `MEMORY_*` 字段仍有 3/8 次崩溃；
- 新建 Ubuntu 24.04/systemd 255 容器后，版本虽然与宿主完全一致，SCL 仍在
  `sd-netlink` 中触发 assertion。

因此能够直接确认的是：**崩溃发生在 SCL 的可选 udev 硬件枚举路径中**；容器/宿主
版本差异会影响表现，但不是完整根因。`icc2_exec` 本身不直接依赖 libudev，SCL 是运行时
`dlopen()`。让这次 `dlopen()` 失败后，SCL 会走非 udev fallback，license 仍能正常签出。

`snps_no_udev.sh` 只对被包装的进程把一个指向 `/dev/null` 的 `libudev.so.1` 放到
`LD_LIBRARY_PATH` 首位，不改系统库、不改 `/run/udev`。回归结果：

```text
未屏蔽：icc2_shell       2/8 成功，6/8 udev crash
已屏蔽：icc2_shell      12/12 成功
已屏蔽：icc2_lm_shell   12/12 成功
```

`run_full_flow.sh`、`run_dc.sh`、`run_pnr.sh`、`run_finish.sh`、`run_create_ndm.sh`
已自动使用这个 wrapper。交互式启动：

```bash
source flow/local/env_local.sh
flow/local/snps_no_udev.sh icc2_shell
```

原来的启动重试仍保留，用来防御尚未分类的启动错误。诊断时可临时设置
`PDE_SNPS_USE_SYSTEM_UDEV=1` 恢复系统 libudev，但在这台机上会重新引入随机崩溃。
这个 workaround 没有得到 Synopsys 官方确认；将来若有 SCL hotfix，应优先换官方修复。

### 3.3 `icc2_lm_shell` 与完整 NDM 重建均已验证

旧环境中 `icc2_lm_shell` 每次都在 license/udev 路径崩溃。使用
`snps_no_udev.sh` 后，最小 license checkout 已连续 12/12 通过。

`run_create_ndm.sh` 现在默认写到 `ref_candidate`，不移动现用 NDM。正式入口已在
22 秒内完成，当前 active 输出：

```text
flow/work/icc2/ref_rebuilt/tcbn65lp_6lmT1.ndm   约 309 MiB
```

`check_workspace` 成功；855 个同名 GDS physical blocks 不再触发 `LM-058`；
`BUFFD2.layout` 与厂商 GDS 的 DBU、逐层图形数和面积一致。新 NDM 中普通单元与
`FILL*` 的 `site_name` 均为 `core`。

### 3.4 两类独立的 PDK/NDM 问题

把 PDK 里 7 个 Milkyway 工艺文件全 grep 一遍：

```
tsmcn65_6lmT1.tf   antenna=0   site=0      （其余 6 个同样）
```

**这套 PDK 的 `.tf` 只带层/通孔/布线规则，天线声明和 site 定义在 LEF 里。**
现有证据要求把问题拆开：

1. **天线检查被静默关闭** —— 日志里 `Turn off antenna since no rule is specified`。
   `pnr.tcl` 里设的 `route.detail.antenna true` / `use_diodes` / `diode_libcell_names ANTENNA`
   说的是"发现违例怎么修"，不是"什么算违例"，没有规则就全部空转。
   LEF 中虽有 `ANTENNACUMAREARATIO`、diffusion PWL 和 pin 面积，但不会自动生成
   ICC2 router 需要的 `define_antenna_*` 规则。2026-08-03 已在两个 `.dlib` 副本中
   分别实测 `read_tech_lef -merge_action update/overwrite`，规则数前后均为 0。
2. **site/filler 已修** —— 建库时保留 LEF cell site，并在 floorplan 显式选择
   `-site_def core`。隔离小块已实际完成 filler insertion，不再报 `CHF-013`。
3. **旧 NDM 缺 layout 的直接原因是导入冲突** —— 原建库先 `read_lef`、后
   `read_gds`，855 个同名 physical blocks 全部 `LM-058`，工具保留 LEF frame、丢掉
   GDS layout。新脚本用同一 physical library、`read_gds -merge_action update` 和
   `lib.workspace.save_layout_views=true` 修复了它。

不能把这三项继续归并成一个 `.tf` 根因，也不能自行把 LEF 的少量 ratio 数字硬编码成
ICC2 规则；完整 foundry 语义还包括累计面积、diffusion PWL 和 diode mode。

## 4. 对 SYNOPSYS_SETUP.md 的更正

那份文档里有两处与实测不符：

1. **"已安装的工具（全部实测可启动）"** —— 当时应该只验证了 `-version`，
   那条路径不查用户组也不签 license。真正跑脚本时 ICC2 是崩的（3.1）。
2. **"容器内可以正常 checkout 实现级 license"** —— `lmutil lmstat -f ICCompilerII-4`
   查的是**许可证服务器**有没有这个 feature（确实有，99 seats），
   跟**工具进程能不能签出**是两回事。后者当时是不成立的。

其余部分（拓扑、lmgrd 的 IPv6 bind 修复、路径、别名）都核对无误。
`Synopsys.dat` 的 SERVER 行和 `env_synopsys_2024.sh` 按要求没有动。

## 5. 顺带装的东西

- 容器里 `apt install strace`（诊断用）
- 宿主机 `~/synopsys/compat-libs/libsasl2.so.3` → 系统 `.so.2` 的软链。
  这个只有在 `LD_LIBRARY_PATH` 里显式带上才生效，默认环境不受影响，留着无害。

## 6. 拿 ICC2 的版图做 Calibre 签核 —— 三个坑

Calibre 的 license 只有 EDAServer 有（本机 `/home/soleil/cadence/calibre2015` 装了
但没有任何 MGLS 授权配置），所以签核在服务器上跑。走通之前废掉了两次结果，
**两次都会给出漂亮的"0 违例"，而且不看层统计根本发现不了**。

### 坑一：ICC2 的 GDS 缺 166 个标准单元的内部几何

8 月 2 日旧结果使用的参考 NDM 没有可用 layout view。
症状是 Calibre 报 `Cell XXX is referenced but not defined`（166 条）。
天线检查靠栅极面积算比值，没有单元几何 = 结果无意义。

### 坑二：走 `fdi2gds` 从 DEF 生成，会丢掉上百万个通孔

这是**最危险**的一个，因为它不报错、只在日志里留下少量警告。

ICC2 写的 DEF 用技术库里的通孔名引用通孔：

```
VIA23     476,504 次      VIA12_HV  281,977 次
VIA12     155,444 次      VIA34     119,058 次      VIA45  27,381 次
```

这些名字 **LEF 和 DEF 的 VIAS 段都没有定义**（LEF 里叫 `VIA12_1cut`/`VIA12_2cut_E`，
DEF 的 VIAS 段只定义了 10 个）。`fdi2gds` 对每一个都执行
`The via ... was not found. The routing for this net was ignored.` ——
**连同布线整段丢弃**。现存日志只保留 20 条同类告警，不能据此估计总丢失次数。

后果：金属与栅极断开 → 天线比值天然为 0 → 26 条规则全部"通过"。

> 判据：跑完先看 summary 里的 `ORIGINAL LAYER STATISTICS`。
> 这个设计的通孔应该是**百万级**（VIA1 44.8 万、VIA2 48.4 万…）。
> 丢通孔那次只有 3.7 万，差 30 倍。**通孔数量是这类假阳性的唯一可靠探针。**

### 坑三：精度不匹配

TSMC 的 deck 写死 `PRECISION 1000`（1nm）。ICC2 的 `write_gds` 输出 10000（0.1nm），
`fdi2gds` 跟随 LEF 头里的 `DATABASE MICRONS 2000` 输出 2000 —— 都会报
`Rule file precision ... is not consistent with database precision ...`。

不要去改 deck 的 `PRECISION`（那还得连 `RESOLUTION` 一起等比例改，而且会破坏
`prepare_block_signoff_decks*.sh` 对 foundry deck 的 SHA-256 校验）。
改数据这边：DEF 本身是 `UNITS DISTANCE MICRONS 1000`、厂商单元 GDS 也是 1000 dbu/µm，
所以 1nm 才是这批数据的原生精度。

### 走通的做法

新 `ref_rebuilt` NDM 流出的 GDS 已直接包含完整单元几何，只需缩放精度；旧 NDM 的
历史 GDS 才需要第二步 merge：

```bash
# 1) 本机：ICC2 的 GDS 缩到 1nm（无损，脚本会校验 offgrid 和逐层面积）
klayout -b -r rescale_gds.py -rd inp=...gds -rd outp=...dbu1000.gds
# 2) 仅旧 NDM：与厂商 GDS 合并，补齐 166 个空壳
klayout -b -r flow/local/merge_gds.py \
  -rd design=...dbu1000.gds \
  -rd cells=~/code/DigitalIC/stdlib/tsmc65/.../tcbn65lp.gds \
  -rd outp=...full.gds
# 3) 传到 EDAServer，用项目原有脚本跑；新 GDS 用缩放结果，旧 GDS 用 full.gds
PDE_GDS=...dbu1000.gds ./flow/calibre/run_block_signoff_final.sh antenna
```

旧 ICC2 GDS 的布线和通孔完整，缺的只是单元内部几何，所以合并就够了，不需要绕道
DEF。新 ICC2 GDS 已验证 0 个空壳，不能再无条件 merge。

**旧版图结果（2026-08-02）**：26 条规则 0 违例，
`TOTAL Original Layer Geometries: 1,327,853 (12,137,847)`，通孔约 110 万，
无 `referenced but not defined`、无精度警告。
报告在服务器 `flow/reports/calibre/pde_chip_top_safe_icc2full_antenna.summary`。
8 月 3 日新 GDS 已另跑同一 deck：26 checks、0 results，VIA1-VIA5 展开合计
1,228,347，summary runtime warnings 为空。报告为
`pde_chip_top_safe_rebuilt_20260803_antenna.summary`。

保留意见：`RV` / `AP` 无几何，`DNW` 也需按设计是否使用 deep-Nwell 解释，因此不能
把覆盖率精确写成“24/26”。现存 13 个 OpenROAD antenna 脚本只能证明做过多轮开发，
没有保存下来的 antenna violation 数量；如需比较，应拿 OpenROAD GDS 跑同一 deck。

运行 deck 不是字节级不变：准备脚本先校验 foundry 源 deck 的 SHA-256，再只 patch
`LAYOUT PATH/PRIMARY` 和输出报告路径；`PRECISION`、`RESOLUTION` 与规则正文不改。
