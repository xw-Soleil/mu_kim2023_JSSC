# 工作全记录：PDE 后端流程从 EDAServer 迁移到 soleilUbuntu

> 时间：2026-08-01 深夜 → 08-02 上午。
> 起因：EDAServer 上没有 ICC2 实现级 license（`ICCompilerII-4/-8`），
> `initialize_floorplan` 跑不了，之前只能用 OpenROAD 顶替布局布线。
> 目标：把项目搬到 soleilUbuntu（那台机 license 齐全），用 Synopsys
> DC 综合结果 + ICC2 把后端流程重新跑通，并补上天线检查。

> **2026-08-03 复核更正**：本文记录的 8 月 2 日执行过程真实，但原摘要混用了
> `route_auto` 阶段值和最终值。最终是 8 条 route DRC、0 open；`check_lvs` 的
> 3 条 short 记录对应 2 个物理位置；峰值内存 8444.52 MB；`final_*.rpt` 共 13 份。
> 同日已用 `snps_no_udev.sh` 稳定绕开 SCL udev 崩溃，并完成 Ubuntu 本地
> RTL -> DC -> 新 NDM -> ICC2 -> GDS/DEF/netlist/SPEF 全链回归。新 NDM 修复
> layout/site 并成功插入 filler，但新结果仍有 1 open、2 short；ICC2 内部 antenna
> rules 仍为空。新 GDS 随后已在 EDAServer 重跑 foundry antenna deck，26 checks、
> 0 results；该结果仍不等于完整 DRC/LVS signoff。

---

# 第一部分：做了什么（结果视角）

## 1. 数据迁移（EDAServer → soleilUbuntu）

| 内容 | 从哪 | 到哪 | 大小 | 校验 |
|------|------|------|------|------|
| 项目主体（RTL/脚本/DC 结果/报告） | `~/PDE/pdeMujunjie` | `~/code/DigitalIC/PDE/pdeMujunjie` | 62M / 329 个文件 | md5 抽验一致 |
| PDK 子集（tf/LEF/GDS/CCS db/TLU+） | `/ssd0/PDKs/TSMC65nm/.../tcbn65lp_200b` | `~/code/DigitalIC/stdlib/tsmc65/` | 916M / 79 个文件 | md5 抽验一致 |
| 参考 NDM（2018 版建好的） | `flow/work/icc2/ref/` | `flow/work/icc2/ref_from_server/` | 322M | md5 全验一致 |

**没搬**：`sim/` 的 VCS 编译产物、OpenROAD 的 2.3G 中间 DEF/guide、
DC 的 185M SDF（P&R 用不到）。

两台机之间**没有网络路由**（EDAServer ping 不通 Ubuntu 的 Tailscale 地址，
也没装 Tailscale），所有传输经我这台 Mac 中转。

## 2. 修好了本地 Synopsys 环境的三个致命问题

1. **容器里 ICC2 一启动就崩**（申请 55GB 内存后段错误）→ 改容器
   `/etc/nsswitch.conf` 修好，备份 `/etc/nsswitch.conf.bak.before-icc2-fix`。
2. **SCL 签 license 的 udev 路径随机段错误** → `snps_no_udev.sh` 让可选
   `libudev.so.1` 加载失败并走 SCL fallback；ICC2 与 Library Manager 各 12/12。
3. **`icc2_lm_shell` 原先启动即崩** → wrapper 后已完整重建 NDM；旧 NDM 仍保留作历史对照。

另外发现并修了：宿主机跑 ICC2 缺 `libsasl2.so.3`
（做了 `~/synopsys/compat-libs/libsasl2.so.3 → 系统 .so.2` 的软链，
不动系统目录，默认环境不受影响）。

## 3. ICC2 后端流程跑通（服务器上卡死的那步及之后全部）

流程：`initialize_floorplan` → PG 网络 → `place_opt` → `clock_opt` →
`route_auto` → `route_opt` →（跳过 filler）→ 全套签核报告 → 写出。

| 阶段 | 耗时 | 结果 |
|------|------|------|
| floorplan + PG ring/rails | ~1 min | 过 |
| `place_opt`（4 个子阶段） | ~13 min | 过 |
| `clock_opt`（Trial CTS + CTS + route_clock + opto） | ~9 min | 387 buf + 148 inv，2090 µm² |
| `route_auto` | ~1.4 min | 阶段性 **0 DRC、0 开路**；0.13% 是中间拥塞口径 |
| `route_opt` | ~2.7 min | 最终变为 **8 DRC、0 开路** |
| `create_stdcell_fillers` | — | **失败**（site 对不上，见下），用 `PDE_SKIP_FILLERS=1` 跳过 |
| 报告 + 写出 | ~3 min | 过 |

机器：i9-13900HX，8 线程并行，ICC2 日志峰值内存 8444.52 MB（约 8.45 GB）。

**产物**（`flow/results/icc2/`）：

| 文件 | 大小 |
|------|------|
| `pde_chip_top_safe.gds` | 117M（ICC2 原始输出，缺单元几何） |
| `pde_chip_top_safe.full.gds` | 112M（几何完整、通过 antenna deck 的输入；不是完整 signoff） |
| `pde_chip_top_safe.def` | 114M |
| `pde_chip_top_safe.postroute.v` | 19.7M（后仿网表） |
| `pde_chip_top_safe.WC.spef` / `.BC.spef` | 各 ~260M |

**质量数据**（`flow/reports/icc2/final_*.rpt`，13 份）：

| 项 | 数值 |
|----|------|
| 建立 WC | 最差 slack **−0.02ns**，TNS −0.03，3 条路径违例 |
| 保持 BC | 最差 **−0.01ns**，总 −0.28ns |
| 布线 | 117,285 网络，0 开路，最终 8 DRC |
| `check_lvs` | **3 处 M1 短路**（实为 2 个物理位置，坐标已定位） |
| 利用率 | 63.6% |
| 单元 | 93,358 → 112,970（优化插了 2 万个 buf/inv） |

## 4. 复核后拆分为两类根因

**这套 PDK 的 7 个 Milkyway `.tf` 工艺文件里，antenna 规则和 site 定义都是 0 条**，
LEF 中有 site、layer antenna 声明和 pin antenna 面积。但后续证据表明不能把三个症状
都归到 `.tf`：

1. ICC2 天线检查被静默关闭（`Turn off antenna since no rule is specified`），
   `pnr.tcl` 里配好的自动插二极管全部空转；
2. 旧 NDM 的 filler 没有 site，floorplan 又默认选择 `unit`；新建库保留
   `SITE core`，并显式 `initialize_floorplan -site_def core` 后已实际插入 filler；
3. 缺 layout 的直接原因是原建库先读 LEF、后读 GDS，855 个同名 GDS physical
   blocks 全部触发 `LM-058`，工具保留 LEF frame、丢弃 GDS layout。新建库用
   `read_gds -merge_action update` 和 `lib.workspace.save_layout_views=true` 修复。

LEF reader 仍不会把累计面积、diffusion PWL 等声明自动转成 ICC2 的
`define_antenna_*` router rules。现存 13 个 OpenROAD antenna 脚本只能证明做过多轮
开发，保存的日志没有实际 antenna violation 数，不能写成“已证实报了一堆违例”。

## 5. Calibre 天线检查（含两次作废与最终有效结果）

- **第一次（作废）**：直接拿 ICC2 的 GDS 跑 → Calibre 报 166 个
  `Cell ... referenced but not defined`，版图缺单元几何，结果无意义。
- **第二次（作废，最危险）**：改走项目原有的 `fdi2gds`（DEF→GDS）路线 →
  跑出"26 条规则 0 违例"，**但被我判定为假**：层统计里通孔只有 3.7 万，
  而 DEF 里有 1,069,568 个通孔引用。追查发现 ICC2 的 DEF 用技术库通孔名
  （`VIA23` 47.6万、`VIA12_HV` 28.2万…），LEF/DEF 里都没定义，
  `fdi2gds` 把它们连同布线**整段静默丢弃**（日志只留 20 条警告，
  其余被 Calibre 去重过滤）。金属与栅极断开 → 天线比值天然为 0 → 假通过。
- **最终（有效）**：不走 DEF。实测 ICC2 的 GDS 里通孔**全都在**
  （`$$VIA23` 476,503 次放置，与 DEF 逐一对应），只缺单元内部几何 →
  用 KLayout 把 ICC2 GDS 与厂商 `tcbn65lp.gds` **合并**
  （166 个空壳全部填上，脚本校验 GHOST_AFTER=0），再跑天线检查。

**最终结果**：TSMC deck `CN65S_6M.ANT.23a`，26 条规则 **0 违例**。
层统计通孔约 110 万（VIA1 447,928 / VIA2 484,215…），与 DEF 对得上，
无缺单元、无精度告警 —— **这次是真的**。
保留意见：RV/AP 两层无几何，DNW 也需按设计是否使用 deep-Nwell 解释；因此只应写
“26 checks、0 results”，不能精确宣称 24/26 有效覆盖率。

现存项目目录中没有更早的有效 Calibre antenna 结果；是否为项目历史第一次无法独立证明。

## 6. 2026-08-03 新 NDM 完整回归

8 月 2 日结果保持为历史记录；8 月 3 日另用隔离目录做了从本地 RTL 综合结果开始的
完整回归：

```text
DC:   flow/local_runs/dc/
ICC2: flow/local_runs/icc2_20260803_full/
NDM:  flow/work/icc2/ref_rebuilt/tcbn65lp_6lmT1.ndm
```

- DC 完整综合 398 秒，生成 DDC/Verilog/SDC/SDF/SVF；
- ICC2 首次 license checkout 成功，无启动重试，2014 秒，峰值 3890.58 MB；
- floorplan 使用 `SITE core`，正式设计插入 136,478 个 filler，legality 0；
- 7 个 physical-only `FILL*` master 仍报 `CHF-011 not marked filler type`，但显式列表
  全部插入成功；这是 purpose 元数据 warning，不是此次插入失败；
- 最终 WC setup WNS/TNS 约 -0.01/-0.01 ns（2 paths），BC hold WNS/TNS
  -0.02/-0.42 ns（195 paths）；
- 最终 route/LVS 为 1 open、2 条 M5 short，仍未 signoff；
- `rst_n` 超过 1000 pins 被 extraction 跳过，coupling capacitance lump 到 ground，
  SI analysis 未启用；
- GDS 139,399,862 bytes，KLayout 只读检查为 198 structures、0 empty cells；
  其中 181 个已使用的厂商单元逐层图形数和物理面积全匹配，不再需要 `merge_gds.py`；
- `read_tech_lef -merge_action update` 与 `overwrite` 已分别在两个 `.dlib` 副本中测试，
  `get_antenna_rule_names` 前后都为 0，ICC2 自动天线分析仍未激活；
- 新 GDS 无损缩放到 1nm 后传至 EDAServer，MD5 双端均为
  `749e6b2cf5606cc0d085477e728fa248`；Calibre `CN65S_6M.ANT.23a` 执行 26 checks、
  生成 0 results。VIA1-VIA5 展开合计 1,228,347，summary runtime warnings 为空。

## 7. 工作区整理与文档

- **删除**（仅崩溃垃圾，共 101 个 / 2.2M，清单存 `/tmp/cleanup_list.txt`）：
  `crte_*.txt` ×45、`Synopsys_stack_trace_*.txt` ×45、
  `pnr.local.log.startup-crash.*` ×11。删后逐一复查关键产物健在。
  特意**保留** `check_design.ems`（4.4M，是可在 GUI 加载的错误数据库，不是垃圾）。
- **防陷阱**：EDAServer 的 `flow/reports/calibre/` 里两份天线摘要
  文件名只差 `_icc2_`/`_icc2full_`，且作废那份也写着 0 违例 →
  写了 `READ_ME_FIRST.md` 说明哪份有效、怎么一眼分辨（看通孔数量级）。
- **文档三层**：
  - `pdeMujunjie/HOWTO.md`（17K，新写）—— 怎么看、怎么跑、怎么排障，命令全部实测；
  - `flow/local/README.md`（12K，新写）—— 为什么、根因分析、全部踩坑记录；
  - `PDE/SYNOPSYS_SETUP.md` —— 原有文档，顶部插入了更正
    （原文"全部实测可启动""可正常 checkout license"两条与实测不符，
    原验证方法只测了 `-version` 和 `lmstat`，都不触发真实签出）。

---

# 第二部分：怎么实现的（技术视角，按问题展开）

## A. 传输：没有直连路由怎么搬 1.3G 数据

```
EDAServer --(ssh)--> Mac --(ssh)--> soleilUbuntu
```

用 tar 管道，Mac 只做中转不落盘：

```bash
ssh EDAServer "cd ... && tar czf - 目录" | ssh soleilUbuntu "cd ... && tar xzf -"
```

三个实现细节：

1. **末尾脏字节**：远端 shell 退出时会往流里吐终端控制字符
   （`[?1000l...` 一串），tar/gzip 会报 `trailing garbage ignored`、退出码 2。
   用 `xxd` 验证过垃圾只追加在**流末尾**、不会插进中间，因此判定传输可用，
   但**一律用 md5 双端比对代替退出码**作为成败判据。
2. **第一次翻车**：脚本里写 `DST=~/code/...`，`~` 在 Mac 本地就展开成
   `/Users/soleil`，远端 `mkdir /Users` 权限拒绝。改为传 `$HOME/相对路径`
   并转义 `\$HOME` 让它在远端展开。
3. 大传输全部 `run_in_background` 后台跑 + 完成后 md5 校验。

## B. 容器里 ICC2 启动即崩：strace 定位到 NSS

现象：`icc2_shell` 报 `MEM Fatal: Out of memory, Request size = 55834574848`
（55GB！）然后段错误，栈里有 `getgrouplist / _nss_systemd_initgroups_dyn`。

推理链：

1. 崩溃点在**用户组枚举**，不是工具逻辑;
2. 容器（Ubuntu 20.04）自带 libnss_systemd 是 systemd **245**，
   宿主机是 systemd **255**；容器共享宿主机 `/run`，245 的 NSS 模块
   和 255 的 userdb 协议不匹配，返回垃圾组数 → 工具照单 malloc 55GB → 崩;
3. 验证：容器内 `id`、`getent group` 走 `files` 完全正常。

修法（一行 sed，先备份）：

```
/etc/nsswitch.conf:  passwd/group 从 "files systemd" 改为 "files"
```

改完 trivial 脚本立即通过。**教训**：SETUP.md 说"全部实测可启动"，
但 `-version` 这条路径既不查用户组也不签 license，验证是假的。

## C. SCL 签 license 随机段错误：定位、试错、绕过

修完 B 之后，跑真正签 license 的命令仍崩，但**变成间歇性**（8 次测 2 次成功）。

定位过程：

1. 容器里没 strace → `apt install strace`；
2. strace 抓到崩溃前最后一次系统调用：读完宿主机 systemd 255 写的
   `/run/udev/data/+dmi:id`（1892 字节）后立即 SIGSEGV —— 还是 245 vs 255，
   这次是 **libudev** 解析 udev 数据库；
3. 顺带发现宿主机直跑也崩（栈到 libnss_systemd —— 宿主机 nsswitch 也带 systemd），
   排除了"容器专属问题"的假设。

试过但**无效**的方案（都记录在案）：

- 空 tmpfs 盖住 `/run/udev`（挂载传播是 slave，安全）→ 反而引入**新**崩溃
  （libudev 打不开 `+dmi:id` 也崩），已撤销恢复原状；
- `setarch -R` 关 ASLR → 成功率不变（2/8）；
- 宿主机原生跑（补了 libsasl2 软链）→ 撞回 NSS 崩溃。

8 月 2 日的临时绕法是**启动阶段安全重试**，关键是判据设计：

```
崩溃永远发生在脚本产生任何输出之前
→ 日志里没有 "^PDE_ICC2: top=" ⇒ 启动崩溃，重跑安全（最多 25 次）
→ 有了它再失败 ⇒ 真失败，立即停
→ 没有它、也没有 "Internal system error" ⇒ 确定性 Tcl 错误，重试无意义，立即停
```

第三条是后补的：第一版重试把 API 不兼容这种确定性错误也重试了 25 次。

8 月 3 日进一步部署 `flow/local/snps_no_udev.sh`：只在被包装的 Synopsys 子进程
`LD_LIBRARY_PATH` 前放一个不可加载的 `libudev.so.1`，使 SCL 走非 udev fallback；
不改系统 libudev 或 `/run/udev`。回归为 `icc2_shell` 12/12、`icc2_lm_shell`
12/12，DC 完整综合也成功。重试仍保留为第二层保护。

## D. 让旧版 P&R 流程适配新版 ICC2

8 月 2 日最初保持 `pnr.tcl` 不动；8 月 3 日为支持隔离回归，主脚本增加了
`PDE_ICC2_OUTPUT_ROOT` 非破坏性输出根参数。版本差异和本地 site 仍由适配层处理：

1. **环境变量注入**（`flow/local/env_local.sh`）：原脚本每个输入都有
   `env_or_default PDE_XXX` 兜底，把 20 来个 `PDE_*` 全部 export 指到本地路径即可。
2. **加载时文本补丁**（`flow/local/pnr_local.tcl`）：
   - 先试过 `rename set_block_pin_constraints` + proc 包装做运行时垫片 →
     ICC2 拒绝：`Error: command cannot be renamed`；
   - 改为：读入 `pnr.tcl` 源码 → `regsub` 按替换表改写 → 落盘到本轮
     `PDE_ICC2_OUTPUT_ROOT/work/icc2/pnr.patched.tcl`（可 diff 审计）→ source 它。
   - 固定补丁：`-pin_spacing 0.4` → `-pin_spacing 2`。
     语义漂移：O-2018.06 该参数单位是 µm（浮点），W-2024.09 改成轨道数（整数）；
     M3 pitch = 0.2µm，0.4µm ≡ 2 tracks，物理意图不变。
   - 新 NDM 默认设置 `PDE_SITE_DEF=core`，另补
     `initialize_floorplan ... -site_def core`；正式设计已插入 136,478 个 filler。
   - 踩坑：`regsub -all $pat` 的模式以 `-` 开头会被当成选项，必须 `regsub -all --`。
3. **断点续跑**（`flow/local/finish.tcl`）：filler 失败时布线已 `save_block`，
   为不重跑 30 分钟，写续跑脚本从 filler 一步接下去。
   - 尾部代码**不手抄**：从 `pnr.tcl` 里按注释锚点 `"# Fill every legal row gap"`
     `string first` 切出尾巴、落盘、source —— 主脚本改了自动跟随；
   - `PDE_SKIP_FILLERS=1` 时只 regsub 掉 `create_stdcell_fillers` 那一行，
     后面的 connect/save/报告/写出全保留；
   - 踩坑：`get_blocks` 只见已打开的 block，存盘的必须先
     `open_block pde_chip_top_safe.design`（注意 `.design` 后缀）。

## E. 监控与判真：怎么不被假成功骗

- 长任务全部 `setsid nohup ... &` 脱终端 + Monitor 盯日志关键行。
- **grep 判据必须锚定行首**：icc2_shell 会回显脚本源码，
  `grep PDE_ICC2_DONE` 会匹配到源码里的 `puts "PDE_ICC2_DONE..."` 产生假 OK。
  真踩过一次：报了 RESULT: OK 但 `results/icc2/` 是空的。改 `grep -E "^PDE_ICC2_DONE"`
  并加产物文件存在性检查。
- ICC2 顶层阶段标记带引号：`Starting 'clock_opt' (FLW-8000)`，
  第一版监视器正则没带引号导致永不命中，靠直接翻日志发现。
- **shell 自匹配自杀**（踩过两次）：`pkill -f xxx` / `pgrep -f xxx` 会匹配到
  自己所在命令行 —— 一次把后续命令杀了，一次让看门循环永远等不到结束。
  修正：按 PID 杀（`ps -eo pid,args | awk '/pat/ && !/awk/'`），
  等待循环改为顺序脚本。

## F. 天线检查：三堵墙分别怎么破

**墙 1：本地没 Calibre license** → 检查发现只有 EDAServer 配了 MGLS
（`/ssd0/mentor/license/license.dat`）→ 签核在服务器跑，版图传回去（经 Mac）。

**墙 2：精度不一致**。TSMC deck 写死 `PRECISION 1000`（1nm）：

- ICC2 `write_gds` 输出 10000（0.1nm，继承自 2018 NDM，`file.gds.*` 无精度选项）；
- `fdi2gds` 默认输出 2000（跟随 LEF 头 `DATABASE MICRONS 2000`）。

决策：foundry **源 deck** 先做 SHA-256 校验，运行副本只 patch `LAYOUT PATH`、
`LAYOUT PRIMARY` 和输出报告路径；`PRECISION`、`RESOLUTION` 与规则正文不改。
数据侧处理如下：

- 证据：DEF 头 `UNITS DISTANCE MICRONS 1000`；厂商单元 GDS 用自写的
  GDS 二进制解析脚本（读 0x0305 UNITS 记录、excess-64 浮点解码）确认
  也是 1000 dbu/µm → **1nm 才是数据的原生精度**；
- `rescale_gds.py`（KLayout Python）：坐标 ÷10、dbu ×10，物理尺寸不变；
  转换前校验全部 1,318,129 个图形 bbox 坐标都是 10 的倍数（offgrid=0），
  转换后逐层比对图形数与面积（12 层 mismatch=0）→ `RESULT OK` 才放行。
- 后来 `fdi2gds` 路线发现它有 `-precision 1000` 选项（翻 `-help` 找到），
  也用过；最终有效路线用的是 rescale 那份。

**墙 3（最险）：`fdi2gds` 静默丢通孔**。识别过程完整记录：

1. 第二次天线结果全 0，但整个跑完只 45 秒 → 起疑；
2. 看 summary 的 `ORIGINAL LAYER STATISTICS`：几何**确实读进去了**
   （POLY 72.5万、CO 491万 扁平数）→ 排除"空跑"；
3. 但 VIA1..VIA5 合计仅 ~3.7 万，ICC2 报的是 1,046,299 → 差 30 倍，矛盾；
4. `grep` fdi2gds 日志：现存 20 条 `The via VIAxx was not found.
   The routing for this net was ignored.`；20 条只是日志保留量，不能当总数；
5. 直接数 DEF：`VIA23` 476,504 次、`VIA12_HV` 281,977 次…合计 1,069,568，
   全是**裸 VIARULE 名**；LEF 里只有 `VIA12_1cut` 等别名，DEF 的 VIAS 段只定义 10 个
   → 上百万通孔无解析 → 整段布线被丢 → 金属与栅断开 → 假 0。

**破法**：查 ICC2 自己的 GDS —— 用 KLayout 数**单元放置次数**（不是图形数）：
`$$VIA23` 476,503 次、`$$VIA12_HV` 281,977 次，与 DEF 逐一吻合 →
**ICC2 的 GDS 布线+通孔完整，只缺单元内部几何** → 写 `merge_gds.py`：

- 读设计 GDS + 厂商 `tcbn65lp.gds`，先断言两边 dbu 相同（防隐式缩放）；
- 找出"空壳"单元（`is_empty()`）166 个 —— 数字与 Calibre 报的缺失单元数
  精确相等；
- 逐个 `copy_tree` 从厂商库填入；复查 GHOST_AFTER 必须为 0；
- 输出 `pde_chip_top_safe.full.gds`（112M），md5 双端校验后跑天线。

最终运行：45 秒 CPU 144 秒，26 规则 0 结果，层统计通孔 ~110 万 —— 判真。

## G. LVS 短路的预分析（已备好，未动手修）

`final_lvs.rpt` 的 3 条记录中两条 bbox 互相包含 → 实为 **2 个物理位置**：

```
(573.51,123.71)~(573.63,123.81) M1  u_r_red/U12 引脚 ↔ n30 布线   0.12×0.10µm
(68.65,478.95)~(68.69,479.05)  M1  u_sol/copt_h_inst_21598 ↔ n60  0.04×0.10µm
```

性质：引脚接入冲突，与全局布线 M1 溢出 412（0.27%）互相印证。
修复思路（待批）：对这两个 cell 加 pin-access padding 或局部 ECO 重布。

---

# 第三部分：交付物与位置速查

## soleilUbuntu

| 路径 | 是什么 |
|------|--------|
| `~/code/DigitalIC/PDE/pdeMujunjie/HOWTO.md` | ★ 操作手册（看/跑/排障，命令实测过） |
| `.../flow/local/README.md` | ★ 原理与踩坑全记录 |
| `.../flow/local/{env_local.sh, run_full_flow.sh, run_dc.sh, run_pnr.sh, pnr_local.tcl, run_finish.sh, finish.tcl, run_create_ndm.sh, snps_no_udev.sh, rescale_gds.py, merge_gds.py}` | 全部本地适配脚本 |
| `.../flow/local_runs/icc2_20260803_full/` | 新 NDM + 本地 DC 输入的完整回归与最终报告 |
| `.../flow/results/icc2/` | GDS/full.GDS/DEF/后仿网表/SPEF |
| `.../flow/reports/icc2/final_*.rpt` | 13 份最终报告 + 流程日志 |
| `.../flow/work/icc2/pde_chip_top_safe.dlib` | 布线后设计库（可 open_block 继续做 ECO） |
| `~/code/DigitalIC/stdlib/tsmc65/` | PDK 子集 |
| `~/code/DigitalIC/PDE/SYNOPSYS_SETUP.md` | 原环境文档 + 我的更正段 |

## EDAServer

| 路径 | 是什么 |
|------|--------|
| `~/PDE/pdeMujunjie/flow/reports/calibre/READ_ME_FIRST.md` | ★ 哪份天线结果有效、怎么分辨 |
| `.../pde_chip_top_safe_icc2full_antenna.{summary,log}` | ✅ 有效天线结果 |
| `.../pde_chip_top_safe_icc2_antenna.*` | ❌ 作废（丢通孔），留档 |
| `~/PDE/pdeMujunjie/flow/results/icc2_from_ubuntu/` | 传回的各版 GDS/DEF（548M，可裁剪） |

## 遗留事项（按建议优先级）

1. **修新回归的 HFSNET_639 open 和同一 net pair 的 2 条 M5 short**；
2. 收敛 WC setup、195 条 BC hold、max-transition/max-capacitance；
3. 从 foundry/Synopsys 认可的来源建立 ICC2 `define_antenna_*` 规则；不要自行简化 LEF PWL；
4. 补顶层 VDD/VSS pin shapes，并做完整 Calibre DRC/LVS 与时序 signoff；
5. 每次 ECO/重布后重跑已验证的 Calibre antenna 流程；
6. SCL workaround 最终应由 Synopsys 官方 hotfix 替换；
7. EDAServer 磁盘 93% 满，`icc2_from_ubuntu/` 可按留档策略裁剪。
