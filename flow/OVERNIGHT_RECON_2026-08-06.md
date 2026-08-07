# OVERNIGHT RECON 2026-08-06 — ICC2/RVT 线侦查报告

- 执行机:soleilUbuntu(主)+ EDAServer(PDK/签核资源侦查,本次可达)
- 基线:`flow/local_runs/full_clean_20260804`(未做任何改动)
- 写入的文件仅三个:`flow/BASELINE_MANIFEST.md`、本报告、
  `flow/calibre/block_signoff_config.sh`(第 11 行,原件备份为 `.bak`)
- 未提交任何 git commit。`git status`:`M flow/calibre/block_signoff_config.sh`
  + 两个未跟踪的新 md + `.bak`。
- ⚠ 本报告与 manifest 含机器绝对路径。若日后要提交,pre-commit hook 会按
  AGENTS.md 规则拦截,需按流程人工审查。

---

## 第一部分:基线冻结结果

已写入 `flow/BASELINE_MANIFEST.md`,要点:

1. **11 个交付物 sha256 全部记录**(两个 GDS、DEF、postroute.v、SPEF×2 +
   scenario 文件×2、DC 网表/SDC、design.ndm)。关键值:
   - 原始 GDS `fbd491f3…b710720`(129,272,622 B,**10000 dbu/µm**,GDS UNITS 二进制实测)
   - dbu1000 GDS `752ca81f…fa52bf0`(121,962,194 B,**1000 dbu/µm**)
2. **report_dir 解析结论**:最终写出会话的 `PDE_ECO10_REPORT_DIR` 由
   `flow/local/run_clean_writeout.sh` 默认为 `…/reports/icc2/final`(嵌套目录)。
   因此 **嵌套 `final/`(16:52)是权威报告集;扁平 `final_*.rpt`(16:39)是
   clean_r1/r3 修复之前的过期集**。时间线证据链见 manifest §2。
3. **`clean_20260804.dbu1000.gds` 来源:来源不明**。搜索了 run 目录、
   local_artifacts、doc、bash/zsh history,只找到 worklog/audit 的叙述性记载,
   没有执行日志。UNITS 10:1 关系与 mtime(晚于 ICC2 写出 41 s)与
   `rescale_gds.py` 流程一致——这是旁证不是证明,已如实标注。

---

## 第二部分:天线规则 —— **找到了**

### 2.1 命中清单(EDAServer,完整 PDK 树)

| 文件 | 格式 | 用途判定 |
|---|---|---|
| `/ssd0/PDKs/TSMC65nm/STDCELL/std/STD_Cell/tcbn65lp_200b/Back_End/milkyway/tcbn65lp_200a/clf/antennaRule_n65_6lm.tcl`(3,845 B,sha256 `409ad799…5ba8ffe`) | **Astro/ICC Milkyway Tcl** | ★ 主候选。头注明"TSMC N65 Antenna Rule for Astro/ICC Router",DR 文档 T-N65-CL-DR-001。6lm 对应本设计 6LM。同目录还有 5/7/8/9lm 版本 |
| 同目录 `antenna_tcbn65lp.clf` | CLF(单元天线数据) | 单元级天线属性(LEF 里已有等价信息) |
| `…/Back_End/volcano/tcbn65lp_200a/techfiles/tsmcn65_6lm_antenna.rules` | Magma BlastFusion | 内容与 tcl 同一套比值,工具不适用,仅作交叉验证 |
| Calibre ANT deck:`/ssd0/PDKs/TSMC65nm/STDCELL/DRC_Calibre_65nm_v2.3a.tar.gz` 成员 `ANTENNA_DRC/CN65S_6M.ANT.23a` | Calibre | **已在用**且已验证(08-03 antenna run);生成的 block 版在 EDAServer `flow/work/calibre/block_signoff/generated/CN65S_6M.block.ANT.23a` |

### 2.2 规则内容(摘自 tcl 原文)

三种模式齐全:单层侧壁(mode 4)、单层面积+过孔(mode 1,VIA ratio=20,
M6 ratio=5000,RV=200)、累积(mode 2,M1–M5 ratio=5000,VIA 累积=900),
均带 diode_ratio 斜率表 `{0.06 0 <slope> <offset>}`;末尾还设了
`doAntennaConx=4` 的布线器参数。全文 121 行,结构是重复的
`define_antenna_rule $lib -mode …` / `define_antenna_layer_rule $lib -mode … -layer … -ratio … -diode_ratio {…}`。

### 2.3 ICC2 加载它需要什么

该文件是 **Milkyway 语法**(第 41 行 `set lib [current_mw_lib]`),不能直接
source 进 ICC2。ICC2 侧存在同名命令 `define_antenna_rule` /
`define_antenna_layer_rule`(参数形式不同,无 `$lib` 位置参数,作用于当前打开
的库)——**本次没有启动 icc2_shell 验证参数兼容性**(启动即签 license,超出
"只查不跑"边界),因此改写后能否一次通过**无法确定**。验证命令:
`icc2_shell` 中 `man define_antenna_rule`。改写工作量:8 个规则块的机械翻译。

先决事实(本次原始证据):
- ICC2 当前规则数为 0:probe 运行 `PDE_ANT_PROBE_BEFORE_COUNT=0`,
  `read_tech_lef -merge_action update` 之后 `AFTER_COUNT=0`
  (`flow/local_runs/antenna_tech_lef_probe_20260803/probe.log`)。
  LEF 里根本没有 tech 层天线规则可读——见下。
- 本地 LEF `tcbn65lp_6lmT1.lef`:`ANTENNAGATEAREA`×2865、`ANTENNADIFFAREA`×1030
  等**单元 pin 级**属性齐全,但 `ANTENNAMODEL`=0,且 MACRO 之前的 tech 段无任何
  层级 ANTENNA 语句(逐行检查)。即 LEF 只提供"受害者/二极管面积",不提供比值规则。
- `.tf`(7 个)与 `.alf`、tluplus 二进制:grep 均无 antenna 内容。
- 本地 PDK 子集(`~/code/DigitalIC/stdlib/tsmc65`,79 个文件)内**无**任何
  `*anten*` 文件——**主候选文件目前只在 EDAServer 上**,要用需先拷贝。
- 修天线用的二极管单元 `ANTENNA` 在库里存在(CLASS CORE,0.4×1.8 µm,
  pin I ANTENNADIFFAREA 0.1066),LEF 定义完整。

---

## 第三部分:tap/endcap 候选表

**硬事实:LEF 中 861 条 CLASS 语句全部是 `CLASS CORE`。**
(`awk` 全量提取,`tcbn65lp_6lmT1.lef`,855 个 MACRO)
没有任何 `CORE WELLTAP`、`ENDCAP*` class 的 master。**穷尽模式搜索
(FILL_NW/NWELL/NW/SUB/DCAP/TIEH/TIEL/BOUNDARY/FILLTIE/WELLTAP/PTAP/NTAP/CAP/END,
大小写不敏感)命中的全部候选如下**:

| MACRO | CLASS | SIZE (µm) | SITE | 判定 |
|---|---|---|---|---|
| FILL_NW_HH | CORE | 1.6×3.6(双排高) | bcoreExt | **不是 tap**。databook §5:多电压域 level-shifter 与 high-VDD 标准单元邻接用的特殊 filler(原文见下) |
| FILL_NW_LL | CORE | 1.6×3.6 | bcoreExt | 同上,low-VDD 邻接 |
| FILL_NW_FA_LL | CORE | 1.6×3.6 | bcoreExt | 同族 |
| TIEH / TIEL | CORE | 0.6×1.8 | core | tie-high/low 单元(输出 Z/ZN),不是 tap |
| GTIEH / GTIEL | CORE | 0.8×1.8 | core | 同上(gated 版) |
| DCAP/DCAP4/8/16/32/64,GDCAP~GDCAP10,OD25DCAP16/32/64 | CORE | 0.6~12.8×1.8 | core | 去耦电容 |
| FILL1/2/4/8/16/32/64,FILL1_LL | CORE | 0.2~12.8×1.8 | core | 普通 filler |
| ANTENNA | CORE | 0.4×1.8 | core | 天线二极管 |

databook 原文(`DB_TCBN65LP_WC.pdf` 文本抽取,行 2202-2213):
"Fill_nw_hh — The fill cell is used when abutting level shifter cell with
high-VDD standard cell." / "Fill_nw_ll — … with low-VDD standard cell."

**全书检索**(pdftotext 全文 193,997 行,非空 120,111 行,抽取有效):
`tap\b|well tap|endcap|end-cap|boundary cell` **命中 0 条**。
→ tcbn65lp databook 完全没有 welltap/endcap 概念。

**well-tap 间距规则检索**(TN65CLDR001_2_1.pdf,pdftotext 成功):
- latch-up 规则章节存在:LUP.1 ~ LUP.5.5(+ 对应 g 后缀 guideline,
  文本行 16827-16830、67043-67045、67090 起"DRC methodology for LUP.1")。
- 具体最大间距**数值未能可靠提取**——规则表格被 pdftotext 打乱。需要人工
  打开 PDF 查第 10.1 节(latch-up DRC methodology)。文中另有
  "maximum latch-up rule" 的表述(行 61046/61231 图 7.5.10),证实存在
  "最大间距版 latch-up 规则"这一概念,数值本次无法确定。

**不做选型**。给你的判断材料:库里没有独立 tap/endcap master + databook 无此
概念,与"每个标准单元自带 well/substrate 接触(self-tapped 库)"的解释相容,
但本次没有找到正面写着 self-tapped 的句子,也没有做 GDS 层面验证 → 见第七部分
决策项 1。

---

## 第四部分:Calibre 配置修复 + 坏路径清单

### 4.1 已改(唯一的文件修改)

`flow/calibre/block_signoff_config.sh` 第 11 行,原件已备份
`block_signoff_config.sh.bak`(cp -p,属性保留)。diff:

```diff
-: "${PDE_GDS:=${PDE_REPO_ROOT}/flow/results/openroad/pde_chip_top_safe.gds}"
+# 2026-08-06: default retargeted from the removed OpenROAD path to the
+# full_clean_20260804 ICC2 deliverable (1 nm/dbu rescaled copy; the raw
+# 0.1 nm ICC2 stream-out is pde_chip_top_safe.gds in the same directory).
+: "${PDE_GDS:=/home/soleil/code/DigitalIC/PDE/pdeMujunjie/flow/local_runs/full_clean_20260804/icc2/results/icc2/pde_chip_top_safe.clean_20260804.dbu1000.gds}"
```

选了 **dbu1000 版**而不是原始 GDS,理由(可推翻,见第七部分决策项 4):
① HOWTO 5.3 记载 deck 对 0.1 nm 精度直接报
"Rule file precision … not consistent";② 08-03 已验证通过的 antenna run
用的就是 1 nm 重缩放版;③ dbu1000 恰是为送 Calibre 而生成的。

### 4.2 其他坏/机器错位默认值(只报告,未改)

**block_signoff_config.sh 其余默认全是 EDAServer 路径,在 soleilUbuntu 上全部
不存在**(逐一 test -e 验证):
```
PDE_REPO_ROOT     /home/sxw/PDE/pdeMujunjie
PDE_CALIBRE_HOME  /ssd0/mentor/Calibre2023/aoj_cal_2023.2_16.9
PDE_LICENSE_FILE  /ssd0/mentor/license/license.dat
PDE_DRC_ARCHIVE   /ssd0/PDKs/TSMC65nm/STDCELL/DRC_Calibre_65nm_v2.3a.tar.gz
```
含义:这套脚本是**在 EDAServer 上执行**的设计(本次确认这 4 个路径在
EDAServer 上全部存在,archive sha256
`647c1ac78d86c280de180543a08234aecc618b5cf8b085b82c40801f1e19f1b2` 与配置里
记录的 DRC/ANT 成员 sha 所属包一致)。在 Ubuntu 上跑则每个都要 override。

**flow/openroad/*.tcl**(归档脚本):十余处硬编码
`set repo_root /home/sxw/PDE/pdeMujunjie` 及 `flow/{work,results,reports}/openroad`
引用(grep 清单已存证)。属历史归档,不建议修,列出备查。

### 4.3 Calibre 安装与 license(只查)

- EDAServer:`/ssd0/mentor/Calibre2023/aoj_cal_2023.2_16.9` 存在。
  裸调 `calibre -version` **失败**——wrapper 第 780 行引用了不存在的
  `Calibre2015 …/calibre_host_info`(Calibre2015 与 2023 并存造成的分发脚本
  问题)。但 runner(`run_block_signoff_final.sh`)会显式
  `export CALIBRE_HOME/MGC_HOME/MGLS_LICENSE_FILE` 后调用
  `$PDE_CALIBRE_HOME/bin/calibre`,08-03 的 antenna log 头两行就是
  **"Calibre v2023.2_16.9"** 并成功跑完 —— 这是可用性的最强证据。
- license:`/ssd0/mentor/license/license.dat` 存在,含 26 行 calibre 相关
  feature;机器上无 mgcld 守护进程(文件式授权,与成功运行记录相容)。
  本次未做真实 checkout 测试(会启动完整会话)。
- soleilUbuntu:**无 calibre 二进制**(container 内外都查过)。

### 4.4 LVS rule deck

**PDK 中未找到 CLN65S(标准逻辑)的 Calibre LVS deck。**
- `DRC_Calibre_65nm_v2.3a.tar.gz` 全成员清单只有 5 类目录:
  `MAIN_DRC_TopMr/TopMu/TopMy/TopMz`、`ANTENNA_DRC`、`ANTENNA_MIM_DRC`
  (+4 个说明 txt);成员名 grep -ci lvs = **0**。
- `/ssd0/PDKs/TSMC65nm` 全树 `-iname *lvs*`:只有 ① CRN65GP/CRN65LP
  混合信号 PDK 的 **Assura** lvsfile(非 CLN65S 逻辑工艺、非 Calibre),
  ② 两份用法文档 PDF(`N65_N55_Calibre_LVS_Deck_Usage.pdf` 等——说明书,
  不是 deck),③ 教学视频。
→ Calibre LVS 签核在当前资源下**无法执行**,deck 需要外部获取(决策项 3)。

---

## 第五部分:签核工具可用性

| 工具 | soleilUbuntu(容器 synopsys-focal) | EDAServer | license 证据 |
|---|---|---|---|
| **PrimeTime** | ✗ 无 pt_shell 二进制 | ✓ `/ssd0/synopsys/install_place/pts/O-2018.06-SP1/bin/pt_shell` | Ubuntu 本地 SCL(27000@localhost,server UP v11.19.6)有 PrimeTime/PrimeTime-ADV/PX 等,99 席 0 用。EDAServer:lmgrd+snpslmd 进程在跑,但**未找到 lmutil/lmstat 二进制,feature 无法枚举**;历史成功运行证据:`flow/reports/pt/sta_prelayout.log` 等 8 个报告存在 |
| **Formality** | ✗ 无 fm_shell | ✓ `…/install_place/fm/O-2018.06-SP1/bin/fm_shell` | Ubuntu SCL 有 Formality 全家族 feature;EDAServer 无法枚举。**两台机都从未实际运行过 FM,checkout 能力无法确定** |
| **Calibre** | ✗ | ✓ v2023.2_16.9(见 4.3) | 08-03 成功运行 = 实证 |
| **StarRC / Quantus** | ✗ 未找到 | ✗ `/ssd0/synopsys` 无 StarRC;`/ssd0/cadence` 仅 IC617/INCISIVE152/MMSIM151,无 Quantus/EXT | **两台机都不可用**。寄生签核目前只有 ICC2 自身 write_parasitics 的 SPEF |
| **VCS** | ✓ W-2024.09-SP1(`~/synopsys/vcs/…`,container 内 PATH 可见) | ✓ `…/install_place/vcs/O-2018.09-SP2/bin/vcs` | Ubuntu SCL 含 VCS 系 feature(VCS-Express-Compile/Runtime、VCSAMS… 已见;99 席 0 用)。未做真实 checkout |
| **Xcelium** | ✗ | ✗(有 INCISIVE152,旧代 Incisive,未验证) | — |
| 辅助 | verilator 5.008(host)、klayout(host)、iverilog ✗ | pdftotext ✓ | — |

注意 HOWTO 3.0 自己的警告(经验教训):**lmstat 查得到 feature ≠ 工具能签出**。
上表 license 列一律只陈述 lmstat/历史运行证据,未做新 checkout。

---

## 第六部分:RTL 修改前置信息(只读)

1. **顶层文件**:`src/pe_array/pde_chip_top_safe.sv`
   (module `pde_chip_top_safe`;`src/` 在仓库根,不是 rtl/src)。
2. **rst_n 声明与用法**:第 22 行 `input logic rst_n,`;第 80 行原样下传
   `.rst_n(rst_n)` 给内层 `pde_chip_top`;顶层内另有 3 个
   `always_ff @(posedge clk or negedge rst_n)`(95/105/117 行)与一处同步使用
   (140 行 `if (rst_n && reject_accept)`)。**全仓库无任何两级同步器结构**;
   `posedge clk or negedge rst_n` 共 **13 处**,分布:
   pde_chip_top_safe(3)、pde_chip_top(3)、pde_tcu(1)、r_dsm(2)、r_reg/r_alu/
   sol_acc/r_status/counter_ce/pipeline_delay_bit(各 1)。
3. **扇出**:
   - DC 网表 `.CDN(rst_n)` = **16,219**
   - postroute 网表 `.CDN ( rst_n )` = **16,219**(总 `.CDN` 16,224,其余 5 个
     由别名网驱动;`rst_ni` 出现 8 次;层次端口穿越 `.rst_n (` 1,403 处)
   - 即 DC 到布线后 reset 结构原样未动,一根网直驱 1.6 万个异步清零脚。
   - 对照:08-05 审查的诊断口径是 23,905 个 reset endpoint / 16,226 条
     removal 违例(nworst=1)。两个口径(网表 CDN 引脚数 vs 时序 endpoint 数)
     本次未强行归一,均给出出处。
4. **验证基建现状(重要缺口)**:
   - testbench 存在:`tb/` 5 个 SV + wave dump;
   - **`sim/` 目录不存在;全仓库没有任何 Makefile;`check_golden.py` 不存在**
     ——README"cd sim; make pe"的整套仿真入口在当前树中缺失(重组遗留)。
   - golden model 在:`matlab/golden_model.py`、`dsm_sweep.py`。
   - 可用仿真器:VCS(容器,license 见第五部分)、Verilator 5.008(host)。
   → 改 RTL 之前必须先恢复仿真跑法,否则改动无法回归验证。

---

## 第七部分:【需要你决策的事项】(按重要性排序)

**1. tap/endcap(P0 #3)怎么定性。**
   事实:855 个 macro 全 CLASS CORE,无 WELLTAP/ENDCAP master;databook 全文
   无 tap/endcap 概念;FILL_NW_* 被 databook 明确定义为多电压 filler。
   选项 A:按"库自带 tap"处理,但先做一次验证——从 `tcbn65lp.gds` 抽一个常用
   单元(如 INVD1)检查 NP/PP/NW 层是否含 pick-up(我可以用 klayout 脚本做,
   只读);验证通过则 P0#3 关闭,latch-up 依据改为"库级自带+LUP 规则由 Calibre
   MAIN_DRC 覆盖"。
   选项 B:直接询问库/工艺负责人(拿 databook 之外的 application note)。
   选项 C:维持 P0 状态不动。
   建议 A(证据一晚可得,且 MAIN_DRC deck 本身含 LUP 检查,行 16827)。

**2. antenna 检查走哪条腿(P0 #2)。**
   选项 A:把 `antennaRule_n65_6lm.tcl` 从 EDAServer 拷来,翻译成 ICC2 命令,
   进 ICC2 后 `check_routes -antenna`+布线器自动修(可插 ANTENNA 二极管);
   需要一次 icc2_shell 验证语法,是"流程内保证"。
   选项 B:维持流程外 Calibre ANT(已验证可行),每次 ECO 后手动重跑,
   ICC2 内继续零规则。
   建议 A+B 并行:A 补流程内,B 仍作签核金标准。
   前置:该 tcl 文件目前只在 EDAServer;拷贝需要你点头(NDA 材料移动)。

**3. LVS deck 缺失(P0 #4 的一半)。**
   CLN65S Calibre LVS deck 两台机都没有,现有资源里也生成不出来。
   需要你从库/工艺渠道获取(或指定接受"无 Calibre LVS,只有 ICC2 check_lvs"
   的降级签核)。这是纯外部依赖,我无法代办。

**4. `PDE_GDS` 默认值我选了 dbu1000 重缩放版**(理由见 4.1)。
   如果你要严格字面的"ICC2 原始 GDS",改回一行即可;但注意 HOWTO 5.3 记载的
   deck 精度不一致报错,以及 dbu1000 版**来源无日志**(建议顺手用
   `rescale_gds.py` 正式重新生成一次并留 log,替换现文件,这样 provenance
   缺口也补上)。

**5. 仿真基建缺失(阻塞一切 RTL 改动)。**
   README 指向的 sim/Makefile + check_golden.py 整体不在。选项:
   A. 从旧机器/历史备份找回 sim 目录;B. 我按 README 描述重建 Makefile
   (VCS 或 Verilator 双后端);C. 先不动 RTL。
   复位同步器(P0 #1)的 RTL 改动方案已明确(异步置位/同步释放,13 处
   always_ff 不用动,只在顶层插两级同步器),但必须先有回归能力。

**6. 签核链补齐顺序。**
   现实约束:PT 只有 EDAServer 有(O-2018.06,能读本地 SPEF 需传输 280 MB×2);
   Ubuntu 有 PT license feature 却没有 PT 安装。
   选项 A:SPEF+netlist+SDC 传 EDAServer,用 pt_shell 做 SPEF 级 STA(工具旧
   但存在,历史运行过);选项 B:在 Ubuntu 装 PT(要安装介质,现无);
   选项 C:接受 ICC2 内建时序作为当前上限。
   StarRC/Quantus 两台都没有——寄生精度上限就是 ICC2 write_parasitics。

**7. git 处理。**
   本次改动(config 一处 + 两个新 md + .bak)是否提交、`.bak` 是否入库
   (建议不入,加进 .gitignore 或删除)、提交时 flow/ 改动需按 hook 流程
   `PDE_FLOW_DISCLOSURE_REVIEWED=1`。等你指示,我不动。

---

## 第八部分:未完成 / 失败项及原因

1. **EDAServer license feature 枚举失败**:lmgrd/snpslmd 进程在跑,但
   `/ssd0/synopsys` 全树找不到 lmutil/lmstat 二进制。影响:EDAServer 侧
   PT/FM/VCS/ICC2 的 feature 清单"无法确定"(工具二进制存在性与历史运行
   证据已另行给出)。
2. **真实 license checkout 一律未测**(PT/FM/VCS/Calibre):按"最轻方式"
   约束,启动会话即 checkout,故只做了 lmstat/进程/历史日志三类证据。
3. **ICC2 `define_antenna_rule` 语法兼容性未验证**:需要启动 icc2_shell。
   已明确验证命令,留给下一步。
4. **latch-up 最大间距数值未提取到**:TN65CLDR001_2_1.pdf 的规则表格被
   pdftotext 打乱,只确认了 LUP.1~5.5 规则族与"maximum latch-up rule"概念
   存在。需人工查 PDF 第 10.1 节。
5. **dbu1000 GDS 生成日志未找到**:定性"来源不明",旁证(UNITS 10:1、
   mtime、脚本功能)已记录在 manifest §4。
6. **EDAServer 侧 lmstat 从 Ubuntu 远程查询未尝试**:两机不同网段
   (10.x vs tailscale 100.x),端口可达性未验证,收益低放弃。
7. Calibre 裸 `-version` 因厂商 wrapper 引用缺失的 Calibre2015 文件而失败
   (记录在案);以 08-03 成功运行日志替代版本证据,未再深查 wrapper。

**时间预算内完成;基线目录零写入,全部结论附命令与原始输出(本报告 + manifest)。**

---

## 附录(2026-08-06 追加):HVT 库完整性核查 + 站内备选工艺库调查

### A1. tcbn65lphvt(HVT)库级交付:**齐全,且是 65nm 三个 VT 变体里唯一齐全的**

核查对象:`/home/sxw/PDK/tcbn65lphvt_200b/AN61001_20100906/TSMCHOME/digital/`(EDAServer)。

| 交付项 | 实测 | 备注 |
|---|---|---|
| Liberty | NLDM + CCS + ECSM 三套齐;**文本 `.lib` ×127,`.db` ×2,738**,NLDM 每角 .lib/.db 成对 | RVT 全量交付(`/ssd0/…/tcbn65lp_200b`)`.lib` 仅 1 个且是 `cds.lib` 配置文件,timing 只有 CCS `.db` ×2,657 —— "RVT 无文本 Liberty"在完整交付上再次证实 |
| LEF | ×7(5~9 层金属方案,含 6lmT1) | 855 macro |
| GDS | `tcbn65lphvt.gds` | ✓ |
| 仿真模型 | `tcbn65lphvt.v` + `tcbn65lphvt_pwr.v`(Front_End/verilog),另有 vital | ✓ 门级仿真可用 |
| SPICE/CDL | `tcbn65lphvt_200a.spi` + `_lpe.spi` | LVS 用的单元级网表在 |
| Milkyway | tf ×7 + tluplus 全角 + captable 全角 | ✓ |
| **天线规则** | `Back_End/milkyway/tcbn65lphvt_200a/clf/antennaRule_n65_{5..9}lm.tcl/.scm` + `antenna_tcbn65lphvt.clf` **就在 HVT 自己的交付树里**;`antennaRule_n65_6lm.tcl` sha256 `409ad799…5ba8ffe` 与 RVT 版**逐字节一致**(工艺级规则,VT 无关) | 任务 2 的主候选文件 HVT 线本来就有 |
| 二极管/filler | ANTENNAHVT、FILL*HVT(Innovus 线已实际使用) | ✓ |
| 文档 | databook 全角 PDF ×21(DB_TCBN65LPHVT_*.pdf) | ✓ |

**但三个工艺级缺口 HVT 同样存在(换 VT 不解决)**:
1. tap/endcap:HVT LEF 855 macro 的 CLASS 语句 861 条**全部 `CLASS CORE`**(实测,与 RVT 完全一样)——没有 WELLTAP/ENDCAP master,是这代库的架构而非 HVT 缺项;
2. **Calibre LVS deck(CN65S)全站没有** —— RVT/HVT/LVT 共同缺;
3. latch-up 间距数值仍需人工查 TN65CLDR001 第 10.1 节。
Calibre DRC/ANT deck 是工艺级(CN65S),对 HVT 同样适用,已被 08-03 运行验证。

另:**LVT(`tcbn65lplvt_200b`)在 /ssd0 树里只有 Documentation,库本体为空**(.lib/.lef/.gds 全 0)——不可用。

### A2. 站内其他工艺库调查(/ssd0/PDKs 全目录)

| 节点 | 性质 | 数字 std cell | Calibre LVS | 结论 |
|---|---|---|---|---|
| tsmc40(CRN40ULP) | Virtuoso RF/混合信号 iPDK(models/iDeck/CCI) | **无** | 仅 Assura auLvs(器件级) | 做不了数字 RTL→GDS |
| tsmc28 / tsmc28_mm(CLN28HPC+) | 同上 iPDK | **无** | CCI 用 calibre_cci.lvs,非逻辑全 deck | 同上 |
| local_tsmc28(CRN28HPC+ RF) | 同上 iPDK | **无** | PyCell 教学配置 | 同上 |
| simc40 | SMIC40LL(非 TSMC) | 无 | auLvs | 不适用 |
| HJTC110 | 目录为空 | — | — | — |
| otherPDK | "工艺库大全.rar" 未解压 | 未知 | 未知 | 未探查(压缩包) |
| **UMC40**(非 TSMC) | **完整数字链**:fsh0l_ers GENERIC_CORE(synthesis `.db` 多角 + verilog + LEF ×多金属方案 + 全 GDS + milkyway LM)| ✓ | **✓ 真 Calibre LVS deck**:`RuleDecks/Calibre/LVS/macro/macro.cal.lvs` + 应用笔记/QA 报告;另有 DRC、LPE deck | 站内唯一能 DRC+LVS+LPE 闭环的数字库,但要换厂商换节点 |
| /home/sxw/stdlib/tsmc40_std | 是**表征课程项目**(CSV/教程/图),不是库交付 | — | — | 与本项目无关 |

**结论:没有任何其他 TSMC 节点具备数字标准单元库;65nm(RVT .db 线 / HVT .lib+.db 线)仍是唯一可行的 TSMC 选择。LVS 闭环若为硬要求,站内唯一出路是 UMC40(换厂商)或外部获取 CN65S LVS deck。**

---

## 第五部分勘误(2026-08-07,用户指出 ~/cadence 未覆盖后补查)

昨晚工具普查漏了 `/home/soleil/cadence`,补查结果修正一条结论:

1. **"soleilUbuntu 无 calibre"有误** —— 本机存在完整的 **Calibre 2015.2**
   安装(`~/cadence/calibre2015/aoi_cal_2015.2_36.27/`,与 EDAServer 的
   Calibre2015 同版本),且二进制在 Ubuntu 24.04 上**可执行**
   (`calibre -version` 正常打印 v2015.2_36.27,exit=0)。
2. 但 **本机无任何 Mentor license**:`ocad` 包(Open-CAD 打包环境,2020)
   自带 lmgrd 框架,其 cds/syn/cli 三个 license.dat 全为 **0 字节占位**,
   mgc(Calibre)服务行被注释、mgc.licenses 仅 1 行无 FEATURE;家目录无
   其他 Mentor license。→ **本机 Calibre 现状 = 有安装、无授权,仍不可跑**。
3. 其余目录:IC617(Virtuoso)、INNOVUS201(Innovus 20.10,HVT 线在用)、
   INNOVUS20(bin 为空)、MMSIM151(Spectre);无 Tempus/PVS/Quantus,
   时序签核(PT 仅 EDAServer 有)结论不变。

签核分工维持:PT 与 Calibre 均去 EDAServer。新增一个可选项:若日后取得
Mentor license,本机 2015.2 可承担 65nm deck(2.3a 时代);28nm 的 18a
deck 对 2015.2 是否够新需查 deck 的 Recommended_tool_version。

## 第五部分补充:EDAServer 签核工具实证(2026-08-07,真实启动+真实签 license)

之前只有"二进制存在+历史运行"两级证据;应用户要求做了实签验证:

**pt_shell(PrimeTime O-2018.06-SP1)** —— ✅ 可用,但有环境坑:
- 默认登录环境下启动**失败**:`Checkout of PrimeTime license failed: No such feature exists`,
  因为 `~/.bashrc` 把 `LM_LICENSE_FILE` 指到 Cadence license(内无 PT feature),
  而 Synopsys 环境行是注释掉的。
- 修正环境后启动成功(banner → `pt_shell>` 提示符 → 干净退出):
  `export SNPSLMD_LICENSE_FILE=@localhost`(本机 snpslmd 守护进程在跑)
  + `unset LM_LICENSE_FILE`。此配方必须写进 PT 签核脚本。
  (另有无害告警 PT-063:Library Compiler 路径未设。)

**Calibre 2023.2** —— ✅ 可用,完整实证:
- 最小 DRC deck(65nm 单元库 GDS,PRIMARY=INVD1,1 条规则)完整跑通:
  log 明确记录 `mgc_s license acquired (calibrehdrc requested)`,
  `CALIBRE::DRC-H COMPLETED`,summary 落盘,REAL_EXIT=0。
- 环境配方(与 run_block_signoff_final.sh 一致):
  `CALIBRE_HOME=MGC_HOME=/ssd0/mentor/Calibre2023/aoj_cal_2023.2_16.9`
  + `MGLS_LICENSE_FILE=/ssd0/mentor/license/license.dat`。
- 注:检验用注意 `REAL_EXIT` 要在无管道截断下取;`head` 截管会 SIGPIPE 出假象。
