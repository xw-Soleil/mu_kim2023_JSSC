# PDE 数字后端完整流程复盘(2026-08-08)

> **版本说明**:本文件是 `COMPLETE_WALKTHROUGH_2026-08-08.md` 的润色副本(2026-08-09),仅调整措辞与格式残留,数字、判定与出处未动;两文有出入时以原件为准。
>
> **读者设定**:三个月后的自己。细节全忘,但需要凭本文档重新跑通全流程、讲清楚每一步在做什么、被追问时答得上来。
>
> **本文档与阶段报告的关系**:`flow/` 下的 9 份阶段报告是原始记录(数字的权威出处);本文档负责把"为什么这么做、原理是什么、判据是什么、坑怎么识别"讲清楚,数字一律回指原报告。两者互不替代。
>
> **证据规约**:本文所有数字都能追溯到具体报告文件(每章标出);原始输出以截取片段附上;没做的、做不了的、未记录的,明说,不藏。本文档不重跑任何东西,全部内容整理自已有报告、日志与 commit 历史。

---

## 目录

- [第 0 章 项目定位与全景](#第-0-章-项目定位与全景)
- [第 1 章 起点:审计发现了什么](#第-1-章-起点审计发现了什么)
- [第 2 章 复位问题的完整剖析](#第-2-章-复位问题的完整剖析)
- [第 3 章 恢复验证能力](#第-3-章-恢复验证能力)
- [第 4 章 65nm 为什么走不通](#第-4-章-65nm-为什么走不通)
- [第 5 章 28nm 迁移](#第-5-章-28nm-迁移)
- [第 6 章 P&R 全流程详解](#第-6-章-pr-全流程详解)
- [第 7 章 签核](#第-7-章-签核)
- [第 8 章 坑集(可复用速查表)](#第-8-章-坑集可复用速查表)
- [第 9 章 用 AI agent 做这件事的经验](#第-9-章-用-ai-agent-做这件事的经验)
- [第 10 章 现状、limitation、下一步](#第-10-章-现状limitation下一步)
- [附录 A 目录结构说明](#附录-a-目录结构说明)
- [附录 B 关键命令速查](#附录-b-关键命令速查)
- [附录 C commit 与 tag 完整时间线](#附录-c-commit-与-tag-完整时间线)
- [附录 D 报告文件索引](#附录-d-报告文件索引)
- [附录 E 一键重跑指南(runbook)](#附录-e-一键重跑指南runbook)
- [附录 F 环境变量清单](#附录-f-环境变量清单)

---

## 第 0 章 项目定位与全景

### 0.1 这个项目是什么

复现 JSSC'23 的 PDE(偏微分方程)加速器(Mu & Kim, *A Dynamic-Precision Bit-Serial Computing Hardware Accelerator for Solving Partial Differential Equations*,论文 PDF 在 `doc/`),并加入两项自己的优化:

1. **红黑折叠**:红黑排序(red-black ordering)是解拉普拉斯类 PDE 的经典迭代着色方案——把网格点按棋盘染成红黑两色,同色点之间无数据依赖,可以并行更新。"折叠"指红黑两组共享同一套 PE(processing element)运算资源,用影子寄存器(设计里的 `red_shadow_reg`)保存另一色的状态,面积减半。
2. **自适应精度 + Δ-Σ 误差反馈**:位串行(bit-serial)运算按位处理数据,精度可以逐次迭代动态调整;精度降低造成的舍入误差用 Δ-Σ(delta-sigma)调制的思路累积反馈回去(设计里的 `r_dsm` 模块),不让误差偏置累积。

实现载体:`pde_chip_top_safe`(顶层 wrapper,内含 `pde_core` 的 20×20 PE 阵列),综合后约 12 万逻辑单元。RTL 16 个文件在 `src/`,testbench 在 `tb/`,golden 模型(Python,动态求解参考网格)在 `sim/ref/`。设计说明见 `doc/design_notes.md` / `doc/design_notes_zh.md`。

本仓库为个人学习用途(见 AGENTS.md 顶部声明),不外发、不商业化;PDK 与一切厂商交付物都在仓库外,永不入库。

### 0.2 全流程一张图

数字后端的完整链条,以及每个环节在本项目中的落点:

```text
RTL(src/,16 文件,SystemVerilog)
   │
   │ ① 功能仿真:VCS 回归(sim/,8 个 make 目标)
   │    输入:RTL + tb/ + sim/ref/golden_model.py(动态生成参考解)
   │    判据:8×testbench PASS + 8×check_golden PASS(逐格点整数精确比对)
   ▼
② 逻辑综合:Design Compiler(flow/dc28/synth28.tcl,容器内)
   │    输入:RTL + NLDM 时序库 .db(ssg 慢角 setup / ffg 快角 hold)+ 约束
   │    输出:门级网表 pde_chip_top_safe.v + SDC + 时序/面积报告
   │    判据:日志 RESULT: OK 零 Error;setup/hold/recovery/removal 四类报告
   ▼
③ 布局布线(P&R):IC Compiler II(flow/icc2_28nm/ s01–s07 分阶段)
   │    输入:网表 + SDC + NDM 参考库 + TLU+ RC 表 + PRTF 天线规则/GDS map
   │    输出:GDS(版图)/ DEF / SPEF(寄生)/ SDF / postroute.v
   │    判据:六项 fail-closed 门禁全零(setup/hold/DRC/antenna/opens/shorts)
   ▼
④ 签核(signoff,独立工具独立裁决,EDAServer):
   │    PrimeTime STA:WC/BC 两角 × 无 derate/AOCV 两遍,四类时序检查
   │    Calibre DRC(几何规则)/ LVS(版图 vs 网表等价)/ ANT(天线)
   │    判据:PT 四类 0 违例;LVS CORRECT;ANT 全零;DRC 除 fill 族外全零
   ▼
⑤(未做)流片准备:dummy fill、全芯片级 DRC(sealring/封装开关)、IO 环、
     IR/EM、门级仿真、LEC —— 见第 10 章 limitation 清单
```

名词首次出场,先给一句话定义(后文陆续展开):

- **PDK**(process design kit):代工厂交付的工艺资料包——时序库、物理库、设计规则 deck、RC 提取表等,是全流程的输入根基。
- **NLDM**(non-linear delay model):查表式时序库模型(.lib/.db),按输入转换时间 × 输出负载二维查延迟,是 DC/PT 的时序数据来源。
- **NDM**(new data model):ICC2 的库/设计数据库格式;参考库 NDM 由物理信息(LEF/tf)+ 时序(.db)组装而成。
- **SDC**(Synopsys design constraints):时钟、输入输出延迟、时序例外等约束的标准格式,综合与 P&R/STA 共用。
- **SPEF / SDF**:布线后的寄生参数(RC)交换格式 / 时序延迟标注格式,分别喂给 STA 和门级仿真。
- **签核(signoff)**:用与实现工具**不同**的工具独立复核时序与物理正确性——实现工具自己说自己干净不算数(第 7 章)。

### 0.3 我们实际走到了哪一步

**已完成**(截至 2026-08-08,commit `924e10f`):

- 28nm 两轮完整实现 + 签核:第一轮 10 ns/0.55 利用率(tag `signoff28-full-clean`),第二轮 6 ns/0.70(报告 `flow/PPA_28NM_R2_2026-08-08.md`,tag 未打,裁决权在用户)。
- 可对外的口径:**28nm HPC+、6 ns(167 MHz)、die 0.172 mm²、逻辑利用率 0.70;签核基线(无 derate)setup/hold/recovery/removal + LVS + 天线 + latch-up 全过**。
- 复位释放检查(recovery/removal)从"从未发生"修到"16,227 个检查点全部激活且 MET"——这是整条线最核心的一个修复(第 2 章)。

**没做 / 做不了**(原因详见第 10 章):

- metal/OD dummy fill(环境性缺失:无 ICV、PDK 无 dummy deck);
- AOCV 下 hold 转负(−0.03×654,真实设计裕量问题,修复方案待裁决);
- IR/EM 分析、门级仿真(后仿)、LEC(逻辑等价检查)、chip 级(IO/pad)、5.0 ns 周期再收——均属下一轮或更远;
- 65nm 两条线未收敛,已转为对照组(第 4 章)。

### 0.4 四天时间线(2026-08-05 → 08-08)

按天记录发生了什么(commit 哈希见附录 C;8/5 及以前的 65nm 工作在 EDAServer 仓库与 `doc/worklogs/`,本地仓库从 8/6 起):

| 日期 | 事件 |
|---|---|
| 08-05 | 65nm HVT/Innovus 线在 EDAServer 出最终 GDS(该仓库 commit `14591f95`);同日对 65nm ICC2/RVT 线执行独立审计,多项关键断言被证伪(第 1 章) |
| 08-06 凌晨 | 隔夜勘察(overnight recon:工具面普查 + 交付物基线冻结);本地仓库建立(`2d18730` 基线、`04ad93d` 安全门禁、`f86c4cf` 指令桥) |
| 08-06 白天 | 仿真恢复三阶段(`sim/`,回归 8 目标全 PASS,tag `pre-reset-sync`);overnight recon + 基线清单提交(`70a1c01`) |
| 08-06 晚 | 复位同步器 RTL + SDC 四层解除,DC 65nm 验证 16,224 检查点全 MET(`57572a9`,tag `reset-fix-verified`);28nm 资料勘察(SURVEY 报告) |
| 08-07 上午 | 28nm PDK 解压落地、ICC2 建库冒烟、DC28 基线(`8c77362`,tag `pdk28-dc-verified`) |
| 08-07 下午 | ICC2 P&R 首次干净收敛,六项门禁全零(`08d19f1`,tag `pnr28-first-clean`) |
| 08-07 晚 | 首次独立签核:PT 四类 clean、Calibre LUP/ANT 全零、LVS 诊断(`9aeffaa`);披露审查降级(`3390260`);Stage J LVS 收到 CLEAN(`3b8b11d`,tag `signoff28-full-clean`) |
| 08-08 | 第二轮:6 ns / 0.70 / AOCV 首跑 / Calibre 2023.2,PPA 报告(`924e10f`) |

四天从"审计发现根本性缺陷"走到"两轮签核收官",单段耗时都在预算内 (签核 2.5 h/预算 6 h;第二轮 4.5 h/预算 8 h)。

---

## 第 1 章 起点:审计发现了什么

本章证据出处:`doc/audits/ICC2_RVT_INDEPENDENT_AUDIT_20260805.md`(1,113 行,本地唯一的正式审计文档,审计 65nm ICC2/RVT 线)、`flow/OVERNIGHT_RECON_2026-08-06.md` 及其勘误附录(commit `33a3aa6`)。注意:HVT 线在 EDAServer 侧也做过对应核查,但**其审计文档未归档到本地**——本文引用 HVT 侧数字时会明确标注这一点。

### 1.1 为什么要做独立审计

直接原因:此前各阶段的工作是由 AI agent 执行并自我汇报的,而自我汇报系统性偏乐观(具体模式见第 9 章:术语抬高、指标选择性呈现、状态超前)。更一般的原因:worklog、README、summary 都是**叙事**,不是证据——写的人 (无论人还是 agent)记录的是自己以为发生的事。审计的第一条规约因此是:**结论只认原始日志、报告、数据库和产物;叙事性文档一律不作为技术证据** (这条后来固化进 AGENTS.md §6)。

### 1.2 审计方法:三值判定、只读、动态复核

- **三值判定**:每条被审断言给出 证实(有原始证据支持)/ 证伪(与原始证据冲突)/ 无法验证(可及证据不足以唯一裁决)三值之一。关键规约: **"没找到"不得写成"从未发生"**——对"跑过但产物已删"这类历史,诚实的结论是"无法验证",不是"证伪"。
- **只读**:审计过程零修改("设计、脚本、日志、报告和数据库均未改动;按委托要求仅新增本报告")。发现问题不顺手修——修复是另一个需要单独授权的动作,混在审计里会污染证据现场。
- **动态复核**:不信任静态报告文件。最终数据库 `design.ndm` 先取 sha256 (`6370b6b5…`),拷贝到 /tmp,重开 ICC2(容器 + snps_no_udev 包装)用探针脚本(a1_final_recheck.tcl / a1_matrix_probe.tcl)现场重查;GDS 用 klayout 脚本独立解析。**报告可以过期、可以来自别的 run,数据库现查不会。**
- 被审断言逐条编号(T1–T4 交付物断言,A1–A12 流程断言,Z1–Z2 版本权威性),逐条给判定 + 原始证据引用。

### 1.3 判定结果总览

| 编号 | 断言 | 判定 | 关键证据 |
|---|---|---|---|
| T1 | "clean 版本"(开路/短路/DRC/LVS/合法性/PG/天线全零) | **证伪** | ICC2 内部检查确为 0,但天线规则未定义、检查被跳过;无任何 Calibre/foundry 侧证据 |
| T2 | setup 与 hold 已收敛 | **证伪** | 同步路径无负 slack,但 `rst_n` 根本不是时序起点;0 ns 诊断注入后暴露 16,226 条 removal 违例(见 1.4) |
| T3 | GDS ~139 MB、181 种厂商单元 | **证伪** | 实测 129,272,622 B(129.27 MB)、**178** 种;178 种的逐层 XOR 与实例拓扑 0 失配(子断言证实) |
| A2 | eco10 的 setup 违例靠收敛消除、非放宽 | **证实**(修数:29 条不是 27) | 约束逐字节相同(SDC 哈希一致);规模变化真实(Buf/Inv 38,715→21,961) |
| A3 | 重建 NDM 完整 | **证实** | 855/855 单元、5,603 引脚、816 时序单元逐项账目相符 |
| A6 | OpenROAD 产物未混入交付 | **证实** | OpenROAD 停在 30.9 万条 DRT 违例;"innovus 查看包"的 DEF/网表哈希与 ICC2 交付**逐位相同**——它是 ICC2 产物的查看副本,不是第二条实现线 |
| A7 | 最终 DEF IO 引脚已放置 | **证实** | declared=59 / PLACED=59 / UNPLACED=0 |
| A8 | "天线违例为 0"是有效检查 | **证伪** | 日志原文 `Warning: No antenna rules defined, Skip antenna analysis. (ZRT-309)`;二极管插入 0 个——0 违例是因为**没检查** |
| A9 | tap/endcap 已插入 | **证伪** | 日志原文 `PDE_ICC2_WARNING: tap/endcap insertion intentionally omitted pending approved masters/rules`;DEF 中无任何 tap 类单元 |
| A10 | 使用了有效 OCV/derate | **证伪** | `Variation Type: fixed_derate` 但全部 derate=1.00;CRPR disabled |
| A5/A11 | Calibre 三项 / PT/Formality/IR-EM/门级仿真 跑过 | **无法验证** | 本地无任何运行日志/结果;SPEF/SDF 存在但那是输入不是执行证据 |
| Z1 | 存在权威交付版本 | **无法验证** | 三个完整 run 的同名交付物 sha256 各不相同,无 manifest、无 final 链接 |

**P0 级流片阻塞四条**:复位 recovery/removal 从未有效签核;天线检查被跳过;tap/endcap 缺席;无可审计的 foundry 签核。**总结论:不具备流片就绪条件**——这句判词是后面全部工作(复位修复、28nm 迁移、真签核)的起因。

### 1.4 最重要的发现:复位检查从未发生(诊断链全程)

这是审计的核心产出,诊断链六步,每步都有原始输出:

1. 表面现象:final 报告 `final_setup_violations_4d.rpt` / `final_hold_violations_4d.rpt` 都是 `No paths.`——看起来干净。
2. 试探:把 false path 拿掉再报,仍然零路径,但多了一行关键警告: `Warning: From_pin 'rst_n' is not a timing startpoint and will be ignored. (TIM-010)`——说明 false path 不是唯一屏蔽层,端口根本不在时序图里。
3. **0 ns input delay 诊断注入**(内存中的诊断约束,不落盘、不改交付 SDC):端口重新成为合法起点,复位路径瞬间现形:
   ```text
   PDE_A1_ZERO_DELAY rst_min=23905 min_V_WNS_TNS=16226 -0.227242 -2715.911528
   Startpoint: rst_n … Endpoint: u_impl/cfg_rdata_reg_2_ (removal check …)
   slack (VIOLATED)  -0.227242
   ```
   **16,226 条 removal 违例,WNS −0.227,TNS −2,715.9**——被四层屏蔽压住的真实规模。
4. 排除"库没有弧":`DFCNQD1` 的 recovery/removal 时序弧存在且 `disabled=false`,ICC2 侧 `time.disable_recovery_removal_checks` 也是 false——缺口不在库、不在 ICC2 配置,在约束与 DC 侧(第 2 章第④层)。
5. 结构证据:全网表 CDN 16,224 个,其中 16,219 个由裸 `rst_n` 直接驱动,同步器命名命中 0——**RTL 里没有复位同步器**,这不只是约束问题,是设计结构缺失。
6. 诚实的边界:路径计数随枚举参数变化(nworst=1 → 23,905,nworst=2 → 31,585),所以审计**拒绝给出"被豁免百分比"**,也拒绝照抄 HVT 侧的 16,225/34.25%(未验证的他方数字)——宁可写"无法验证"。

### 1.5 审计方法的可复用要点

1. **数字必须复算**:T3(139 MB→129.27 MB、181→178)和 A2(27→29)都是"叙述值与实测值不一致"被抓——转引的数字不做证据。
2. **拒绝跨线复用未验证数字**(1.4 第 6 步)。
3. **"无法验证"是正当结论**,而且有生产力:Z1 的"无权威版本"直接催生了 `flow/BASELINE_MANIFEST.md`(逐交付物 sha256 冻结)和本地仓库 git 化——审计的输出不只是打分,还包括让下一次审计成为可能的基础设施。
4. 动态复核优先于静态报告;凡引用报告,先确认它属于哪个 run(本次审计就发现同目录里混着新旧两套同名报告,以嵌套 `final/` 为权威、扁平 `final_*.rpt` 为陈旧)。

---

## 第 2 章 复位问题的完整剖析

本章证据出处:`flow/SDC_RESET_UNMASK_2026-08-06.md`(全部编号引用指该报告), 28nm 侧验证见 `flow/BRINGUP_28NM_2026-08-07.md` 第三部分与 `flow/SIGNOFF_28NM_2026-08-07.md` G.3。

### 2.1 异步复位:置位与释放是两件性质不同的事

本设计的复位 `rst_n` 是**异步复位**:它直接接到触发器的异步清零端 (CDN 引脚),不经过时钟——复位一拉低,寄存器立刻清零,不用等时钟沿。

- **置位(assertion,拉低)**:天然安全。异步清零本来就不看时钟,什么时候拉低都行,不存在时序问题。
- **释放(release/deassertion,拉高)**:危险。释放的那一刻如果恰好撞上时钟有效沿附近,触发器"是否还处于复位"的判定就悬在半空——这正是一个时序窗口问题,和数据端 D 的 setup/hold 完全同构。

### 2.2 recovery / removal 是什么检查

对异步置位/清零端(CDN/SDN),STA 定义了与 setup/hold 对偶的两类检查:

- **recovery(恢复)**:复位释放沿必须在时钟有效沿**之前**留够时间——类比 setup。检查的是"释放得够早,寄存器来得及在下个时钟沿正常采样"。
- **removal(移除)**:复位释放沿必须在时钟有效沿**之后**保持够久——类比 hold。检查的是"不要恰好在时钟沿刚过的瞬间释放,否则这个沿的行为不确定"。

一句话:**setup/hold 管数据端 D,recovery/removal 管异步复位端 CDN**。一个"时序收敛"的设计如果只做了前者,复位释放的正确性完全没有被验证过。

### 2.3 为什么复位释放撞时钟会出大事:亚稳态与非法状态

释放撞上时钟沿时,触发器可能进入**亚稳态**(metastability):输出在 0/1 之间悬浮一段不确定的时间再随机落定。更隐蔽的是**多触发器不一致**:同一个复位网到达不同触发器的延迟不同(复位树 skew),释放撞沿时,有的触发器在这个时钟沿"看见"了释放、有的没看见——状态机的各位寄存器一部分保持复位值、一部分开始跑,**整体进入编码之外的非法状态**。对本设计这种 20×20 阵列 + 中央控制状态机的结构,后果是不可复现的功能性死机。

这类问题**仿真几乎抓不到**(RTL 仿真里复位释放是理想的零延迟事件),只能靠 STA 的 recovery/removal 检查兜底——所以"这两类检查从未运行过"是设计正确性层面的窟窿,不是报告数字难看的问题。

### 2.4 四层屏蔽逐层剖析

审计发现(第 1 章):65nm 两条线的所有时序报告里,recovery/removal 检查**一次都没有发生过**。不是"跑了但有违例",是**检查本身不存在**。根因是四层互相独立的屏蔽,全部叠在 `rst_n` 上(前三层在 `flow/dc/synth.tcl`,行号见 SDC 报告 §1):

**① `set_ideal_network [get_ports rst_n]`(synth.tcl 旧 108 行)** ideal network 是综合期的"理想网络"标记:该网络不计延迟、不做 DRC、不参与优化。本意是防止综合器在复位网上乱插缓冲,但副作用是复位路径的到达时间全为 0,一切基于真实延迟的检查失去意义。

**② 缺 `set_input_delay`(旧 95 行,`remove_from_collection` 把 rst_n 从输入延迟集合里刻意剔除)** STA 里,一个输入端口要成为时序路径的**起点(startpoint)**,必须有 input delay(声明外部信号相对时钟的到达窗口)。没有 input delay 的端口不构成受约束路径的起点——从 `rst_n` 出发的路径**根本不进入时序图**。注意这不是遗漏,是脚本里显式写的剔除,即"故意不约束"。

**③ `set_false_path -from [get_ports rst_n]`(旧 107 行)** false path(伪路径)声明"此路径不做时序检查"。从端口全扇出的 false path 把①②漏网的任何路径也一并豁免。

**④ `enable_recovery_removal_arcs` 默认 false(DC 专属,不在任何文件里)** DC 的这个应用变量默认为 false:**默认忽略时序库里的 recovery/removal 时序弧**。也就是说,即使 SDC 完美无缺,dc_shell 也一条 removal 检查都不会报。这一层最难发现,因为:
- 它不在 SDC 里,不在脚本里,`write_sdc` 的产物里也看不见——它是工具内部默认值,除非有人主动查询;
- 报告端没有任何"检查被禁用"的提示,只是**安静地没有那两类报告**——"没有坏消息"与"没有检查"在输出上无法区分;
- **ICC2 和 PT 没有这个默认**(PT 对应变量 `timing_disable_recovery_removal_checks` 默认即 false,签核时实测确认,见 SIGNOFF 报告 G.3)——只用 DC 看时序的阶段,这个缺口不会被其他工具的行为差异暴露出来。

### 2.5 为什么四层是"或"的关系

四层里**任何一层单独存在,检查就是零**:①让延迟失真、②让路径不存在、③让存在的路径被豁免、④让检查类型整体关闭。拆掉其中一层,另外三层照样把结果压成零——这解释了为什么这个问题能潜伏到审计:任何一次"我试着放开一点"的局部实验都看不到变化,很容易得出"本来就没有这类路径"的错误结论。修复必须四层同时拆,且每层拆法不同(见 2.7)。

### 2.6 审计是怎么把它逼出来的

关键一步是**诊断性实验**而不是读报告:给 `rst_n` 加一个 0 ns 的 `set_input_delay`(纯诊断值,不代表真实到达),让端口重新成为合法 startpoint,再强制报 `-to` 异步端的路径——此时若仍然零路径,说明还有别的屏蔽层;逐层剥离,直到第④层(工具默认值)现形。(诊断过程的原始记录在 65nm 审计文档;本地报告记录的是修复后的验证,见 SDC 报告 §4。)这一步的方法论价值:**"报告里没有"不等于"设计里没有",要用注入已知激励的方式验证检查链路本身通不通。**

### 2.7 修复:两级同步器 + 约束重构

**RTL 侧**(Stage 3,commit `57572a9`):顶层加两级复位同步器 `rst_sync_q_reg[0]/[1]`——**异步置位、同步释放**的标准结构:

- 置位:`rst_n` 拉低直接异步清零两级触发器和下游,保持"断电即复位"的异步语义;
- 释放:`rst_n` 拉高后,释放事件经两级 `core_clk` 触发器打拍再传给全芯片 (下游 16,224 个 CDN 全部由 `rst_sync_q[1]` 驱动)。第一级即使因释放撞沿进入亚稳态,也有整整一拍时间落定,第二级输出的释放沿**与时钟同步**——下游的 removal/recovery 检查因此有了确定的发起时钟沿,可查可修。

**SDC 侧**(Stage 4,四层对应四拆,`flow/dc/synth.tcl` 单文件修改):

| 层 | 拆法 |
|---|---|
| ① ideal network | 改为只保留 `set_ideal_network [get_ports clk]`,rst_n 移出 |
| ② 无 input delay | 补 `set_input_delay -max 1.0 / -min 0.2`(max 取块级输入预算同值;min 是项目最早到达约定,给 removal 一个非零早界)+ `set_input_transition 0.1` |
| ③ false path | **原句保留**——见下 |
| ④ DC 默认 | `set_app_var enable_recovery_removal_arcs true`,加注释 `[28nm-portable] process independent; keep enabled` |

③为什么能原句保留:同步器加入后,顶层作用域里裸 `rst_n` 端口**只驱动 2 个引脚**(`rst_sync_q_reg_0_/CDN`、`rst_sync_q_reg_1_/CDN`,网表连通性实测,SDC 报告 §4 4.2.3),其余全部改由 `rst_sync_q[1]` 驱动。于是 `-from [get_ports rst_n]` 的豁免范围**自动收缩为"端口→同步器"这一段真正异步、本来就不该检查的路径**;下游 1 万多条检查的发起点是 `rst_sync_q_reg_1_/CP`(时钟引脚),不在豁免范围内。实证:显式对**全部** CDN 引脚报路径,零条路径以端口为起点。

### 2.8 验证:从 0 个检查点到全部 MET

65nm DC(修复当晚,SDC 报告 §4):

```text
| removal (min) | +0.10 MET | rst_sync_q_reg_1_ → status_read_q_reg (CDN) |
| recovery (max) | +6.43 MET | rst_sync_q_reg_1_ → …u_pe/u_r_red/q_reg_0_ |
```

- 网表 CDN 总数 16,226,同步器自身 2 个按设计豁免,**16,224 个活检查点, report_constraint 全违例扫描零条**——全部 MET。
- removal 的 +0.10 当时就标注为"薄冰":彼时时钟还是 ideal、无复位树, P&R 插入真实延迟后预期转负——后来 28nm DC 果然报 −0.01×20(BRINGUP 报告第三部分,如实保留未修饰),P&R 建复位树后转正 +0.17(PNR 报告 E.10),PT 独立复核 +0.17/+0.19(两轮 SIGNOFF/PPA 报告)。**一个数字贯穿四个阶段,行为完全符合物理预期,这是修复真实生效的最强证据链。**
- 28nm PT 签核受检数:recovery/removal 各 16,227,0 违例;removal 报告首条是真实路径(`rst_sync_q_reg_1_` → PE 内 `small_q_reg`,含 `library removal time` 行),不是 "No paths"(SIGNOFF G.3——按硬性规则,"检查已启用"必须以真实路径为证,不接受"应该启用了")。

### 2.9 本章可复用的结论

1. 异步复位设计的验收标准不是"复位功能仿真通过",而是 **recovery/removal 检查存在、受检数与 CDN 总数对得上、全部 MET**。
2. 检查"检查本身是否在跑"的方法:受检数为 0 时,注入诊断激励逼出路径;工具侧逐个确认默认值(DC 的 `enable_recovery_removal_arcs` 是已知陷阱,PT/ICC2 无此陷阱但要实测记录默认值)。
3. 全扇出 false path + 同步器的组合是安全的,但**前提是网表连通性上端口只到同步器**——迁移/重构后要重验这条(方法:数端口扇出 + 全 CDN 报告看起点)。

---

## 第 3 章 恢复验证能力

本章证据出处:`flow/SIM_RESTORE_2026-08-06.md`(编号引用指该报告)。

### 3.1 sim/ 为什么丢了

本地仓库建立时(08-06 根目录清理),仿真控制文件没有跟过来:原始仿真目录在 EDAServer 的 `rtl/sim/`(不是过时的根级 `sim/`——那个路径已不存在,报告 §0.1 有 ssh 实测),迁移时按"编译产物"口径被整体排除。事后核查: `rtl/sim/` 里 7 个文件**全部是源码/控制文件**(Makefile、5 个 .f 文件列表、check_golden.py),没有任何 simv/csrc/波形(§0.2 全目录列表为证)——"当成编译产物排除"是误判,但也说明当时没有逐文件核过内容。教训:**排除规则按目录一刀切之前,先列一遍目录内容。**

### 3.2 三方版本核对:方法与结论

恢复回归之前,必须先回答"本地 RTL 到底是不是当初跑后端的那份"。方法:对**本地 / EDAServer / GitHub(commit 5a3fd5de)**三方的 RTL 逐文件 SHA256,做三方分类表(报告 §1.2 全表):

- 12 个文件三方逐字节相同;
- `pe_top.sv` 本地=EDAServer,与 GitHub 差异**仅一行注释**(引用的 tb 文件名),语义零差;
- 3 个文件(`pde_core/pde_chip_top/pde_chip_top_safe.sv`)只在本地+ EDAServer(GitHub 版本较早,尚无这三个);
- 两边 Git 历史**不连通**(merge-base 为空),方向靠内容史确定:本地是较新状态。

### 3.3 最关键的一条:后端网表来源核对(§1.4)

比"回归 PASS"更重要的是:**当初后端吃进去的网表,确实是由这份 RTL 综合出来的吗?**如果不是,回归通过也只是验证了一份无关的 RTL。核对链:

- RVT/ICC2 线:DC 日志里 15 个 `Compiling source file` 逐条列出编译输入路径;产物网表 sha256 `0b2ee4fa…`;ICC2 日志 `Loading verilog file` 指向**同一路径**;时间序一致(DC 15:42 → ICC2 16:40)。
- HVT/Innovus 线:EDAServer DC 日志同样 15 文件;Innovus 读入的 `v2_9ns.v` 与 EDAServer `flow/results/dc/` 最新网表 **sha256 逐位相同** (`1d4bff78…`);更早的 dc_10ns/dc_run1 网表哈希不同,排除。
- **诚实的缺口**(报告 §1.4 明写):两条线的 DC run 都没存综合时刻的输入哈希清单,"综合瞬间的字节"无法密码学证明——路径、mtime、当前哈希、Git 历史共同支持连续性,但这是证据链的已知上限。红色警报 (确证失配)**未触发**。

### 3.4 golden 模型是动态生成,不是静态数据

`check_golden.py` 每次运行时 import `sim/ref/golden_model.py` 现场求解参考网格,与仿真输出 `u_dyn.txt`/`u_fix.txt` 逐格点**整数精确**比对。好处:① 不存在"静态 golden 文件过期/被改"这类腐化途径;② 参考模型本身有独立哈希(`128c6169…`,与 EDAServer `rtl/reference/` 逐位相同),一条哈希就锚定了整个参考基准;③ 改边界条件/规模时参考自动跟随。代价是求解器的正确性要另行信任——它与论文模型的对拍属 RTL 开发期工作。

### 3.5 VCS 起不来的诊断

现象:容器内 `vcs -ID` 报 `libelf.so.1` 加载失败。诊断(报告 §2.1): `/lib/x86_64-linux-gnu/libelf.so.1` 是**悬空软链**(目标文件丢失,原因未查明);且 `file` 实测 `vcs1` 是 **32 位 ELF**,还需要 i386 版本库;宿主机的 libelf 需要 GLIBC_2.38,focal 容器(glibc 2.31)用不了。修法(只动容器,零仓库文件):

```bash
distrobox enter synopsys-focal -- sudo apt-get install --reinstall -y libelf1
distrobox enter synopsys-focal -- sudo apt-get install -y libelf1:i386
```

识别要点:Synopsys 老工具常带 32 位组件,`error while loading shared libraries` 先 `file` 看位数,再查该架构的库是否在容器里。

### 3.6 pre-sync / post-sync 基准比对法

复位同步器是要改 RTL 的。"改完回归还 PASS"不够强——PASS 只说明没踩自检的红线,不能证明**数值行为逐位未变**。方法(报告 §2.6):

1. 改动前跑全回归,把每个目标的 `u_dyn.txt`/`u_fix.txt` 连同逐文件 SHA256、工具版本、repo HEAD 归档为 **pre-sync-baseline** (`local_artifacts/vcs/pre-sync-baseline/2026-08-06/` + MANIFEST.md);
2. 改动后重跑,输出**逐文件 SHA256 与基准比对**——同步器只动复位释放时序,不该动任何稳态数值,所以判据是"全部哈希相同",而不是"还 PASS"。

结果:回归 9 目标全 PASS,与基准 8/8 输出一致(tag `reset-fix-verified` 的 tag message 记录)。这个"先立字节级基准,再做修改"的纪律,后面在 28nm 侧反复复用(runset diff、aocvm diff 都是同一思路)。

### 3.7 回归清单(8 目标各验什么)

| 目标 | 顶层 | 验什么 | golden | 耗时 |
|---|---|---|---|---|
| `pe` | tb_pe_smoke | 单 PE 算术/范围检测 | 自检 | 10.5 s |
| `top8` / `top8neg` / `top8mixed` | tb_pde_top 8×8 | 阵列级,+4096/−4096/混合边界 | 64 点 0 失配 | 14–17 s |
| `top20` | tb_pde_top 20×20 | **目标规模配置** | 400 点 0 失配 | 14 s |
| `chip8` | tb_pde_chip_top | chip 顶层 8×8 | 自检 | 15.8 s |
| `chip20` | tb_pde_chip_top_param | chip 顶层 20×20,6400 位精确比对 | 自检 | 21.1 s |
| `chipsafe` | tb_pde_chip_top_safe | **后端综合顶层**,扫描链读出 | 自检 | 13.7 s |
| `dsm` | dsm_sweep.py | Δ-Σ 行为级扫描 | — | <1 s |

一条命令全跑:`make all`,88 s(调用方式见附录 E)。注意 `tb_pe_smoke` 名字里的 "smoke" 有误导——报告 §1.5 逐字 diff 证明它是 `tb_pe.sv` 的**改名副本**,测试逻辑完全相同,不是精简版。

---

## 第 4 章 65nm 为什么走不通

本章证据出处:`flow/OVERNIGHT_RECON_2026-08-06.md`(库缺口普查 + 勘误)、`doc/audits/ICC2_RVT_INDEPENDENT_AUDIT_20260805.md`、`doc/worklogs/` (8/2–8/4 两份工作日志)、`flow/SIM_RESTORE_2026-08-06.md` §1.4(HVT 线网表溯源)。

### 4.1 两条线各自是什么、走到了哪

- **线 A:RVT/ICC2(本机)**。库 `tcbn65lp`(RVT,常规阈值电压), DC→ICC2 W-2024.09。最终交付 `full_clean_20260804`:setup WNS +0.74、hold 0、route DRC 0、die 875×875 µm、utilization 57.28%、GDS 129 MB。——这是被第 1 章审计的对象:内部指标真实,但天线/tap/复位检查/签核四项 P0 缺失,判定不具备流片条件。
- **线 B:HVT/Innovus(EDAServer)**。库 `tcbn65lphvt`(高阈值电压), Cadence Innovus 20.10,9 ns 周期。08-05 出最终 GDS("closes clean", EDAServer commit `14591f95`)。网表溯源已闭环(输入网表与 DC 产物 sha256 逐位相同,SIM_RESTORE §1.4),但实现质量在本地**无法审计** (审计条目 A12:无本地产物,当日 EDAServer 不可达);EDAServer 侧核查给出的 removal 违例数字为 16,225 条/34.25%(**该审计文档未归档本地,转引数字,未验证**)。

### 4.2 PDK 缺什么、每样缺失的后果

| 缺失 | 证据(全部原始核查) | 后果 |
|---|---|---|
| **tap/endcap 单元** | RVT LEF 855 个 MACRO、861 条 CLASS 语句**全部 `CLASS CORE`**,无 WELLTAP/ENDCAP;疑似候选(FILL_NW_*、TIE*、DCAP)逐个查 databook 证明各有他用;databook pdftotext **193,997 行,tap/well tap/endcap/boundary cell 关键词 0 命中**;HVT LEF 同样 861 条全 CORE——是库架构问题,不是选错阈值电压 | latch-up 防护(见 6.2)无法落地;LUP 类规则永不可满足;版图物理上不可流片。ICC2 日志里那句 `tap/endcap insertion intentionally omitted` 就是这个缺口的下游 |
| **LVS deck** | DRC 交付包成员仅 MAIN_DRC×4 + ANTENNA×2,`grep -ci lvs = 0`;全站搜索只有 CRN65 混合信号工艺的 Assura 版(工艺不对、工具不对) | LVS 永远做不了 → "版图=网表"从未被验证 → 签核闭环结构性不存在 |
| **RVT 文本 .lib** | RVT 交付 `.lib` 计数 = 1(且那是 cds.lib 配置文件),时序只有 CCS `.db`;HVT 交付有文本 `.lib`×127 | 需要文本 Liberty 的流程(部分工具/脚本解析)在 RVT 上走不通——切 HVT 支线的动机之一 |
| **LVT 库体** | 库目录只有 Documentation,.lib/.lef/.gds 全 0 | 不可用,直接排除 |
| **ICC2 可加载的天线规则** | 规则文件本体后来在 EDAServer 找到(`antennaRule_n65_6lm.tcl`,Astro/ICC Milkyway 语法),但 ICC2 载入实测规则计数 0;本地 LEF 只有单元引脚侧天线数据,无工艺层规则 | 路由器静默跳过天线分析(ZRT-309),0 违例 = 0 检查(审计 A8) |

### 4.3 "是库不提供"而不是"没找到":判定方法

宣布一个东西"不存在"比"存在"难得多,方法上要做到三点(这也是后来 28nm SURVEY 对 DRM 做"三判据终审"的雏形):

1. **穷举而非抽查**:855 个 MACRO 的 CLASS 全枚举(861 条语句逐条),不是搜几个名字;databook 全文提取后关键词零命中,不是翻目录。
2. **多源互证**:LEF(机器可读)+ databook(人类文档)两个独立来源; RVT + HVT 两个交付各查一遍——排除"只是这个包漏了"。
3. **候选逐个证伪**:名字可疑的单元(FILL_NW_HH 等)逐个查 databook 定义,证明它们是电平移位填充等他用单元,不是 tap 的别名。

与 28nm 的对照:**65nm 是"单元不存在";28nm 是"单元存在但 LEF 没打 CORE WELLTAP/ENDCAP 子类标"**(1,044 个 MACRO 也全是裸 CLASS CORE,SURVEY 任务 3)——所以 28nm 的 tap 插入要按单元名显式指定,不能按 CLASS 筛。同一个检查手法,两种工艺给出两种不同但都可行动的结论。

### 4.4 HVT 支线的完整代价

- **为什么切**:RVT 文本 .lib 缺失 + EDAServer 上有可用的 Innovus,想以第二工具线交叉验证(动机的完整记录在 EDAServer 侧,本地未归档)。
- **走了多远**:DC(9 ns)→ Innovus 20.10 全流程 → 08-05 出 GDS。从"能出 GDS"的意义上它是 65nm 两条线里走得最远的。
- **代价与事故**(散见工作日志与 28nm 报告的对照栏):
  - IO 引脚 57/57 全 UNPLACED 仍继续跑的事故(后来 28nm s02 的 DEF PINS 门禁就是冲它设的);
  - 1,024 条 hold 违例状态下照样写出 GDS 的事故(工具不拦,门禁必须自己建——28nm 六项 fail-closed 门禁的来历);
  - 复位树/时钟树混计(853 混 486),规模账目说不清(28nm s04 的复位树独立统计的来历);
  - removal 16,225/34.25%(转引)——复位问题与 RVT 线同源,四层屏蔽是流程级的,换工具换库都躲不掉;
  - 工具面成本:Innovus 的 mmmc 受限解析器、locale、出错返回 0 等一整套新坑(第 8 章),每个都是纯支出——它们的产出(对坑的认识)最后全部回流给了 Synopsys 单线决策。
- **为什么它不是主线**:tap/endcap、LVS deck 两个 PDK 结构性缺口与 RVT 完全共享(4.2 表已证),切库切工具都解决不了;且其产物在本地不可审计。它的终局角色是**对照组**:证明"65nm 走不通"不是 ICC2 线自己的问题。

### 4.5 诚实的结论

这套 65nm PDK 是**教学子集,不是流片包**:时序库 + 物理库足以做"教学级 P&R"(两条线都出了 GDS),但流片必需的三件东西——LVS deck、tap/endcap 物理防护、可加载的天线规则链——结构性缺失,不是找不找得到的问题。65nm 阶段的真实产出因此不是那两个 GDS,而是:全套流程脚本与配方(create_ndm 的 read_db + read_lef -preserve_lef_cell_site + GDS 合并三步,28nm 建库原样复用)、坑集(第 8 章的半壁江山)、审计方法论 (第 1 章),以及"复位检查从未发生"这个发现本身。28nm 迁移带着全部这些资产换了一块能走完的地基,不是重来。

---

## 第 5 章 28nm 迁移

本章证据出处:`flow/SURVEY_28NM_2026-08-06.md`(勘察与终局判定)、`flow/BRINGUP_28NM_2026-08-07.md`(建库与 DC 基线)、`flow/PNR_28NM_2026-08-07.md` 第一部分(Stage D via 补丁验证)。

### 5.1 为什么是 1P9M_4X2Y2R + 单走 Synopsys 线

**金属栈**是工艺的布线层配置。`1P9M_4X2Y2R` 读法:1 层 poly、9 层金属,其中 4 层细金属(4X,M2–M5)、2 层中层(2Y,M6–M7)、2 层厚金属 (2R,M8–M9,给电源/时钟干线),再加超厚铝 RDL。选它的决定性理由:**下载包里的 RC 提取表(TLU+)只有这一个栈**——RC 表按栈交付,没有对应 TLU+ 的栈等于 P&R 后无法做寄生提取。TLU+ README 自证"CLN28HPC+_1P9M_4X2Y2R+UT-AlRDL RC (TLUplus) TECH. FILE"(SURVEY 任务 2)。

**单走 Synopsys 线**(DC→ICC2→PT):65nm 曾双线(ICC2 + Innovus)并行,代价是每个坑都要踩两遍(第 4 章);28nm 的 PRTF(P&R technology file, TSMC 按 P&R 工具分别交付的技术文件包)勘察到的是 Synopsys 版 `tn28clpr002s1`(内含 Milkyway tf + gdsout map + 天线 tcl,SURVEY 终局判定表),资料面天然齐;Calibre 签核与工具线无关。

**库**:`tcbn28hpcplusbwp40p140`——28nm HPC+ 工艺、40 nm poly pitch、140 nm 单元高度基准的标准单元库,NLDM 视图 180a 版。签核角: WC = ssg0p9vm40c(慢慢角 0.9 V/−40 °C;28nm 有温度反转,冷角是 setup 关键角),BC = ffg0p99vm40c(快快角 0.99 V/−40 °C,交付中最快的 min-delay 库)。

### 5.2 勘察方法论:先证明"资料够",再动手

SURVEY 阶段(08-06)全程只读:18 GB / 220 个文件逐包 `file`/`unzip -t` 验完整性,deck 身份**以 README/文件头为据**而不是文件名猜测(例: tn28cldr039 名字像天线包,文件头证明是 RTO mask-revision checker——"推断是 antenna"被证伪)。三轮迭代把缺口清单从"DRM/应用笔记/PRTF 三缺"收敛到"仅 DRM 手册缺失、非阻塞"(tap 间距数值已从标准单元应用笔记第 11 章拿到:LUP.6 单 pickup 有效半径 R=30 µm → 间距 ≈60 µm)。方法论要点:**"没找到"和"不交付"要区分**——DRM 的终审做了三层穿透 (15 个 dr 包全开箱、iPDK zip 逐层穿透 79 个 PDF 枚举、xlsx 全 dump),才有资格下"整套资料确定不含 DRM"的结论(SURVEY DRM 三判据终审)。

### 5.3 建库三个雷的完整剖析

ICC2 建参考库(NDM)= tf(技术文件,层/via/site 定义)+ 标准单元 LEF (物理抽象)+ .db(时序)。三个雷全部在 tf/LEF 接缝处:

**雷① via 定义缺失——tf 和 LEF 来自不同交付包。**单元 LEF 引用 `VIA12_square`×3213、`VIA12_slot`×1434,但 PRTF tf 的 ContactCode 是另一套命名(VIA12_1cut 等)。裸建库直接失败:

```text
Error: Line 264325, Cannot find via 'VIA12_square'. (LEFR-004)
```

修法:从**同交付家族**的 Cadence tech LEF(tn28clpr002e1)逐字复制三个 via 定义,做成补丁 LEF。Stage D 专门验证过该补丁不可精简:只去 via 保留 SITE,LEFR-004 原样复现(PNR 报告 D.4 反向对照)。

**雷② Tile 尺寸 0.135 vs 0.140——用 966 个单元宽度反推真值。**tf 里 `unit` tile 写 0.135×0.900。但本库 966 个 core 单元的 LEF 宽度**全部是 0.140 的整数倍**(0.135 只能整除其中 39 个);GA 单元全部 0.420 倍。结论:tf 的 0.135 是 p135 系(135 nm 高度族)默认值,不匹配本库(p140)。tile 宽错会导致放置格点错位、全部单元落不到合法位置。判定方法可复用:**site 宽度的真值蕴含在全库单元宽度的最大公约数里。**

**雷③ HVH vs VHV——几何证据推翻目录名推断。**PRTF 双变体的唯一实质差异是 M1/M2 走向互换(HVH = M1 横 pitch 0.1/M2 纵 0.14;VHV 相反)。此前按逻辑库 apt 目录名 `cell_frame_VHV_0d5_0` 推断选 VHV;实测推翻:LEF 里 TAPCELL 的 VSS 电源轨在 **M1 上沿 x 横贯**(y 向仅 ±0.075)→ M1 物理为横向 → **HVH 才对**。目录名是另一套起层命名约定。教训:**方向判定只认几何证据**(pin shape 的长宽轴),不认命名。

### 5.4 为什么用 GenPRTF.tcl 重生成而不是手改 tf

tf 是厂商交付物,手改有两个问题:改动面无法穷尽(pitch 牵连每个垂直层)、不可追溯。PRTF 包自带官方工具 `GenPRTF.tcl`,参数全部取官方文档允许值: `-VRP 0.14 -GcellMultiple 3 -CellHeight 9`。重生成 diff 仅 50 行(unit 0.135→0.140、gaunit 0.540→0.420、垂直层 pitch 0.135→0.14),**原始交付零修改**,输出落在仓库外 `pdk28_bringup/prtf_gen/`。Stage D 还验证了 GenPRTF 不碰 via 段(ContactCode 逐条相同、脚本内 via 相关行 0 处)——即雷①雷②是**两条独立缺陷**,各自的补丁都必要。

### 5.5 建库五条判据分别在验什么

| 判据 | 验什么 |
|---|---|
| create/commit 零 Error 退出 | 组装过程本身无未解决引用(via/site 缺失都会在这里炸) |
| open_lib 可打开 | NDM 不是写出来就算,要能被下游会话消费 |
| cell 数 = LEF 1044 | 没有单元被静默丢弃(部分失败往往只丢单元不报 fatal) |
| SITE 存在且名称正确 | 放置格点体系正确(get_site_defs = unit/gaunit/core/gacore/bcore) |
| TAPCELL/BOUNDARY 有 layout 视图 | 后面 tap/endcap 插入的物质基础(65nm 就是死在库里没有这些单元) |

冒烟用 frame-only(不挂时序);P&R 前再用 65nm 验证过的 create_ndm 配方把 WC/BC 两角 .db 挂进 NDM(read_db 打 process label + read_lef -preserve_lef_cell_site + GDS 合并,PNR 报告开头)。HVH/VHV 双 NDM 都建了,VHV 留作对照——方向判断被推翻过一次,留一条反例路线的成本很低。

### 5.6 28nm DC 基线:迁移正确性的第一道闸

BRINGUP Stage C:65nm 的 synth.tcl 复制为 synth28.tcl,只换库和角配置,复位约束结构**逐字沿用**(工艺无关项)。结果与 65nm 同口径对比 (BRINGUP 第三部分):setup +7.65(65nm +3.59)、面积 109,309 µm² (≈3.7× 缩小)、**removal −0.01×20**——负值在预期内(2.8 节的证据链),如实保留不修饰。**recovery/removal 在 28nm 第一天就是活的**,这是 tag `pdk28-dc-verified` 的核心含义:四层解除是工艺无关的,迁移没有把检查再次弄丢。

---

## 第 6 章 P&R 全流程详解

本章证据出处:`flow/PNR_28NM_2026-08-07.md`(第一轮全数字)、`flow/PPA_28NM_R2_2026-08-08.md` 第三部分(第二轮)、`flow/icc2_28nm/` 脚本本体(操作卡逐一核对自脚本)。

### 6.0 执行框架:怎么跑、怎么判成败

分阶段流程:s01–s07 每步一个 tcl,全部 `source pnr28_common.tcl`(公共环境变量表、库路径、`open_design`/`stage_done` 等辅助过程)。每步结束 `stage_done` = `save_block + save_lib + puts "PDE28_STAGE_DONE <name>"`——**checkpoint 就是设计库里保存的 block,断点续跑 = 修复后重跑该 stage**(下一步的 `open_design` 读的是库里最新保存状态)。

统一调用模板(每个 stage 都一样,后文不再重复):

```bash
distrobox enter synopsys-focal          # 宿主机缺 libsasl2,工具只能在容器跑
source ~/synopsys/env_synopsys_2024.sh  # PATH + license(run_stage.sh 也会自动 source)
cd ~/code/DigitalIC/PDE/pdeMujunjie
export PDE28_ICC2_OUTPUT_ROOT=$PWD/flow/local_runs/icc2_28nm_<新目录>   # 新 run 必须新目录
export PDE28_DC_RESULTS=$PWD/flow/local_runs/<dc_run>/dc/results        # 消费哪个 DC 产物
# 第二轮追加:PDE28_CORE_UTIL=0.70  PDE28_GDS_MAP=<porttext 补丁 map>
flow/icc2_28nm/run_stage.sh s01_setup   # 每次跑一个 stage,内部经 snps_no_udev.sh 包装
```

`run_stage.sh <sNN_name>` 的判定逻辑(核心三行,原文):

```bash
"$SNPS_RUN" icc2_shell -batch -file "$LOCAL_DIR/$STAGE.tcl" 2>&1 | tee "$LOG"
status=${PIPESTATUS[0]}
grep -q "PDE28_STAGE_DONE $STAGE" "$LOG" && echo "STAGE_MARKER: OK" || echo "STAGE_MARKER: MISSING"
```

**为什么按 marker + 产物判定而不是退出码**:ICC2(和 65nm 的 Innovus)在报错后仍可能返回 0;s04 首跑就发生过"报告命令炸掉、CTS 白跑、但看起来像跑完了"(见 6.4)。规则:`STAGE_MARKER: OK` + 该步产物/报告存在,两者齐了才算过;失败先看 `$OUTPUT_ROOT/reports/<stage>.log`。

后台长跑注意:日志不要重定向到 /tmp——容器的 /tmp 是私有的,宿主机上看不见;放 `$HOME` 下(第 8 章坑集)。

### 6.1 s01_setup — 库、MMMC、约束框架

**MMMC**(multi-mode multi-corner):现代 P&R 同时在多个"场景"下做时序——**mode**(功能/测试等约束集)× **corner**(工艺/电压/温度 + RC 提取角)。每个 scenario = mode × corner,优化器同时满足全部激活场景。本设计一个 FUNC mode、两个 corner:

| scenario | 库角 | RC | 激活检查 |
|---|---|---|---|
| FUNC_WC | ssg 0.9 V/−40 °C | TLU+ rcworst | setup(+max_tran/max_cap) |
| FUNC_BC | ffg 0.99 V/−40 °C | TLU+ rcbest | hold |

TLU+ 是 Synopsys 的 RC 提取查找表(由 foundry ITF 生成);本 PDK 的 ITF 导体名与 tf 层名逐一相同,**免 layermap 直读**。65nm 的教训固化在这里:逐 scenario `read_sdc` + uncertainty 0.2/0.05 **显式拆分**(65nm 曾因 MCMM read_sdc 的 scenario 捕获 bug,所有约束落进当时的 current scenario,排查一天,见第 8 章);CPPR 开;`opt.common.max_fanout 32`(R2 K.2,系统默认 40 是 HFS fanout-40 族根因);信号布线层压在 M1–M6(M8/M9 厚金属留给电源环)。

- 脚本 `flow/icc2_28nm/s01_setup.tcl`
- 输入 DC 网表+SDC(`$PDE28_DC_RESULTS`)、参考 NDM(`PDE28_REF_NDM`,默认 `pdk28_bringup/ndm/tcbn28hpcplusbwp40p140_HVH_t.ndm`)、TLU+ 两角、PRTF 天线 tcl、GDS map(路径全部 `require_regular_file` 先验)
- 产出 设计库 `$WORK_DIR/pde_chip_top_safe.dlib`(此后各步的载体)、`s01_link_check.rpt`、`s01_antenna_rules.rpt`
- 判据 `PDE28_STAGE_DONE s01_setup`;antenna_rules 报告非空
- 失败特征 `Refusing to overwrite existing ICC2 design library`(防覆盖,换新 OUTPUT_ROOT);`Required routing layer missing`(NDM 的 tech 不对);缺输入文件的显式 error

### 6.2 s02_floorplan — die、引脚、tap/endcap、电源

**utilization 的物理含义**:core 面积 = 逻辑 cell 总面积 / utilization。0.55 意味着刻意留 45% 空隙给布线资源和优化余量;0.70 = 更小的 die。

**为什么 0.55 会出"圆形分布"**(第一轮版图的著名现象:cell 聚成圆团,四角大片空白):布局器受两股力支配——**线长目标**把互连紧密的 cell 往质心方向拉(等距聚拢的极限形状就是圆),**密度约束**把 cell 推开摊平。utilization 低时密度约束几乎不起作用,线长目标独大 → 圆团 + 空角。这不是 bug,是目标函数的诚实解。0.70 后密度约束成为主导,cell 被迫铺满矩形 core → 圆形消失。**所以收紧利用率同时是面积优化和时序优化** (互连主导设计的布线长度直接受 die 尺寸控制,见 PPA 报告第二部分: DC 零线载关键路径 1.13 ns,后布线 4.75 ns,互连贡献 76%)。R2 的 core 按**实际 cell area** 由 `initialize_floorplan -core_utilization 0.70` 计算,不硬编码尺寸;明令禁止用 blockage/density screen 摊平——那是遮症状不是调机理。

**tap cell 与 latch-up 物理**:CMOS 的 NMOS/PMOS 与井/衬底天然构成寄生 pnpn 晶闸管;若井/衬底电位浮动被瞬态电流抬高,晶闸管可能触发导通——**latch-up**,电源到地直通,轻则功能失效重则烧毁。tapless 库(本库)的标准单元不带井/衬底接触,靠专用 **tap cell** 周期性把井/衬底钉在 VDD/VSS。间距依据:DRM LUP.6 规定单个 pickup 有效半径 R=30 µm;几何上 S=√(R²−H²),本库行高 H=0.9 → S=29.986 → 列距 2S≈60 µm(应用笔记的"every 60um"建议对本库成立,重算过)。**endcap(boundary cell)**守住每行两端的井边界/阱邻接完整性。二者必须在 placement 之前插入——它们要占位,后插会跟已布 cell 打架。最终裁决在签核:Calibre LUP 族 22 条全零(第 7 章)。

**电源网络**:`create_pg_ring_pattern` 在 core 外圈 M9(横)/M8(纵)拉 1.6 µm 宽电源环;`create_pg_std_cell_conn_pattern -mark_as_follow_pin` 沿每行单元的电源轨在 M1 生成 follow-pin 条(与单元 VDD/VSS 引脚重合); `compile_pg` 落地。**VDD/VSS 的物理 terminal 在本步一并创建**(M9 底段 1.6 µm 窗口)——第一轮这步漏了,check_lvs 端口 59/57 对不上,s07b 补救, R2 起固化进 s02(教训:**端口有名字≠端口有形状**,LVS 认的是几何)。

- 脚本 `flow/icc2_28nm/s02_floorplan.tcl`(输入 s01 的 block)
- 环境 `PDE28_CORE_UTIL`(默认 0.55,R2 传 0.70)
- 产出 `s02_pins.def`、`s02_pin_placement.rpt`、`s02_tap_boundary.rpt`、`s02_pg.rpt`
- 判据 **DEF PINS declared=57/PLACED=57/UNPLACED=0**(65nm Innovus 线 57/57 全 UNPLACED 事故的专设门禁;含 PG 口后 59/59);TAP 实例数与列距 (R1 实测 3,960 个、列距 59.91–59.93 ≤60);`check_pg_connectivity` 干净
- 失败特征 `No M9 ring shape found for … terminal creation`(环没生成); pin 约束单位错(`-pin_spacing` 在 W-2024.09 是**轨道数**不是 µm)

### 6.3 s03_place — 布局 + preCTS 优化

`place_opt`:全局布局(优化线长/密度)→ 合法化(落到 site 格点)→ preCTS 时序优化(此时时钟还是 ideal,只有数据路径可优化)。此步不追 hold——时钟树还没建,hold 数字没有意义。

- 脚本 `flow/icc2_28nm/s03_place.tcl`;输入 s02 block
- 产出 `s03_pre_place_check.rpt`、`s03_qor.rpt`、`s03_qor_summary.rpt`、`s03_utilization.rpt`;耗时参考 12 min
- 判据 marker + qor:R1 参考值 setup WNS +5.95 / TNS 0;utilization 与 floorplan 目标一致(R1 0.5434)
- 失败特征 pre_placement check 报未放置的物理单元/未定义 site;placement 合法化失败通常是 s02 的 tap/boundary 或 PG 占位问题回溯

### 6.4 s04_cts — 时钟树综合(与复位树分账)

**CTS**(clock tree synthesis):把"理想时钟"变成真实缓冲树,目标是把各触发器的时钟到达时间差(**skew**)压小、插入延迟(insertion delay)可控。`clock_opt` 同时做树构建 + postCTS 时序优化(hold 从这步起才有意义)。

**为什么复位树要独立统计**:复位网(16k+ CDN)也是大扇出网络,ICC2 把它当普通高扇出网建缓冲树。若只看"时钟树报告",复位树的规模/深度不可见; 65nm Innovus 线就发生过 853 混计 486 的账目不清。本流程用网表 BFS 从 `rst_sync_q_reg_1_/Q` 遍历复位锥,独立报 buffer 数/级数/覆盖 CDN 数 (`pnr28_common.tcl` 的 `report_reset_tree`)。R1 实测:时钟树 23,907 sinks/10 级/543 repeater/skew 0.18;复位树 571 buf/7 级/16,126 CDN。**postCTS removal 从 DC 的 −0.01 转正 +0.18**——复位树建成的直接效果, 2.8 节证据链的中间一环。

**save-first 纪律(本步的事故教训)**:首跑把报告放在 save 之前, `report_clock_trees` 在本版不存在,脚本死在报告行,**574 s 的 CTS 白跑** (checkpoint 没保存)。修复后的结构固化:`clock_opt` 完成 → **立即 save_block/save_lib** → 全部报告包 `catch`。重活后先落盘,报告失败不伤结果。

- 脚本 `flow/icc2_28nm/s04_cts.tcl`;输入 s03 block;耗时参考 ~10 min
- 产出 `s04_qor.rpt`、`s04_clock_qor.rpt`、`s04_reset_tree.rpt`、`s04_recovery.rpt`、`s04_removal.rpt`、`s04_constraints.rpt`(全 catch)
- 判据 marker;`s04_clock_qor.rpt` 的 sinks/级数/skew; `s04_removal.rpt` 出现真实路径且转正
- 失败特征 log 尾部死在某报告命令 → 先确认 `save` 是否已执行(本流程必已执行);clock_opt 本身失败看约束/浮空时钟

### 6.5 s05 + s05b — 布线与天线

`route_auto`(全局→轨道分配→详细布线)+ `route_opt`(布线后时序/DRC 优化)。

**天线效应**(见 7.3 的物理机理)在布线器内的防护:按 PRTF 天线规则检查每层金属/栅面积比,超限时换层跳线或插**天线二极管** (ANTENNABWP40P140,给电荷一条对衬底的泄放路径)。

**本流程最重要的发现:`define_antenna_rule` 不随 save_lib 持久化**——规则活在会话内存里,新会话重开库后规则计数归零,路由器**静默**关闭天线检查(日志只有一句 "Turn off antenna since no rule is specified")。65nm 审计抓到的 A8(ZRT-309 静默跳过)在 28nm 险些原样复现。修复:**每个触碰布线的会话开头重新 source 天线 tcl**(s05b/s06/s06b/s07/s07b 全部如此),且 s05b 用硬判据兜底:规则报告长度 <100 字符直接 error。

**"二极管应 >0"判据的修正**:s05b 后二极管插入 0 个——但规则生效有独立证据(7,138 字符规则报告 + 路由器识别 mode 1/2/4 + 天线违例 0)。小块短网、违例本来就是 0,无需插二极管,属诚实结果。判据应表述为"规则激活证据 + 违例 0",而不是"必须见到二极管"。

- 脚本 `flow/icc2_28nm/s05_route.tcl` / `s05b_antenna_fix.tcl`
- 产出 `s05_routes.rpt`、`s05_diodes.rpt`、`s05b_routes.rpt`、`s05b_diodes.rpt`
- 判据 `check_routes` DRC/opens/antenna 计数;s05b 天线规则非空硬判据
- 失败特征 `Antenna rules still empty after re-source; aborting`; routes 报告里的 `TOTAL VIOLATIONS` 非零留给 s06 收敛

### 6.6 s06 + s06b — postRoute 优化与收敛门禁

**hold 修复为什么留正裕量跑两遍**(65nm 教训:一遍收敛到恰好 0,毫无余量):本步先探测专用 hold-margin 选项(本版不存在,catch 实测),回退方案是**本 pass 内**把 FUNC_BC 的 hold uncertainty 0.05→0.10(给优化器一个更严的靶子,**加严非放宽**),`route_opt` 跑完恢复 0.05。效果:hold 违例 16→0,签核口径下仍留 +0.01~0.02。

**M.5 门禁(R2 新增)**:第一轮 route_opt 遗留 113 DRC + 73 short,直到 s07 才暴露(中间无检查空窗)。现在 s06 尾部就地收敛:check_routes → 非零则 `route_detail -incremental true` 增量修复,至多 3 轮,不归零**硬 error 停在事发现场**。R2 实录:抓到 52 条,一轮归零。

**s06b(R2 新增)**:s06 门禁只 parse `TOTAL VIOLATIONS`(DRC), **opens 不在其中**——R2 的 s07 六项门禁正确拒写 GDS(opens=2)暴露了这个盲点。s06b 用 `route_eco -open_net_driven true` 修开路,判据取 `check_lvs` 自己的 opens/shorts 计数 + check_routes DRC,三项全零才过 (一轮归零)。**已挂账:下一轮把 opens/shorts 并进 s06 门禁,s06b 退役。**

- 脚本 `flow/icc2_28nm/s06_postroute.tcl` / `s06b_open_fix.tcl`
- 产出 `s06_routes.rpt`、`s06_qor.rpt`、`s06b_lvs.rpt`、`s06b_routes.rpt`;过程 marker `PDE28_S06_GATE iter=N drc_total=N` / `PDE28_S06B iter=…`
- 判据 两步各自的硬 error 不触发 + marker
- 失败特征 `s06 route gate failed after incremental repair: DRC=N` / `s06b open repair unconverged`——此时 block 已 save,可开 GUI 定位

### 6.7 s07_finish — 填充、六项门禁、交付物

**filler**:行内空隙用 FILL{64..2} 填满,保证井/注入层连续与电源轨连续。

**六项 fail-closed 门禁**:先跑全套检查,**全零才写 GDS**;任一非零 `error` 退出、产物不生成——宁可没有产物,不能有假产物(65nm 两条线"带违例出 GDS"事故的制度化回应)。六项分别防什么:

| 门禁 | 防什么 |
|---|---|
| setup=0 | 慢路径:芯片在目标频率算错数 |
| hold=0 | 快路径:任何频率都算错数,**不可降频补救**,最恶性 |
| DRC=0 | 几何违规:制造良率/直接短断路 |
| antenna=0 | 制造中栅氧损伤(隐性可靠性炸弹) |
| opens=0 | 断线:功能直接错 |
| shorts=0 | 短路:功能直接错 + 烧毁风险 |

日志判定行(原文):`PDE28_GATE setup_violations=0 hold_violations=0` + `PDE28_GATE drc=0 antenna=0 opens=0 shorts=0` → 之后才有 `PDE28_PNR_DONE gds=…`。

交付物(R1 体积参考):GDS 146 MB、DEF 148 MB、postroute.v 30 MB、SPEF WC/BC 310/313 MB、SDF 147 MB。`write_gds` 带 `-layer_map $GDS_MAP`——R2 起 map 用 porttext 补丁版(`text 33:0:* 133:0` 等三行,端口 text 落 TSMC 约定层,第 7 章 K.1)。

- 脚本 `flow/icc2_28nm/s07_finish.tcl`(s07b_repair.tcl 为 R1 补救脚本,其两项内容——PG terminal、增量修复——已分别固化进 s02/s06,保留作档)
- 判据 上述两行 gate 全零 + 六件产物存在且体积合理
- 失败特征 `PDE28_GATE_FAIL:` + `Hard gate failed; GDS not written`——这是门禁**正常工作**,回对应前级修,不要绕

### 6.8 其他执行线的操作卡

**仿真回归(sim/)**

```bash
distrobox enter synopsys-focal
cd ~/code/DigitalIC/PDE/pdeMujunjie/sim
make SYNOPSYS_ENV=$HOME/synopsys/env_synopsys_2024.sh all    # ~90 s
make SYNOPSYS_ENV=$HOME/synopsys/env_synopsys_2024.sh clean
```

判据:exit 0 + 8 条 testbench PASS + 8 条 `check_golden : PASS`;任何 `mismatches : N>0` 即失败。单目标:`make … top20` 等(目标表见 3.7)。VCS 起不来先查 libelf(3.5)。

**DC 综合(flow/dc28/)**

```bash
export PDE28_DC_OUTPUT_ROOT=$PWD/flow/local_runs/dc28_<新目录>   # 已存在则拒跑
export PDE28_CLOCK_PERIOD=6.0                                    # 缺省 10.0
flow/dc28/run_dc28.sh          # 内部:snps_no_udev.sh dc_shell -f synth28.tcl
```

产出 `$PDE28_DC_OUTPUT_ROOT/dc/results/` 下 netlist(.v)/SDC/SDF/SVF/ddc + ~16 份报告;判据:runner 打 `RESULT: OK`(= exit 0 + 日志有 `PDE_DC28_DONE` + netlist/SDC 非空,三者同时);耗时 ~400 s。失败看 `$OUTPUT_ROOT/dc/reports/` 日志,常见:库路径变量没设、RTL 路径错。注意 **PDE28_DC_OUTPUT_ROOT(DC 写哪)与 PDE28_DC_RESULTS(ICC2 读哪)是两个变量**,衔接时后者 = 前者 + `/dc/results`。

**建库(仓库外 ~/code/DigitalIC/PDE/pdk28_bringup/)**

```bash
# 1) 重生成 tf(官方工具,双变体各一次;在 PRTF 交付树内执行)
#    GenPRTF.tcl -VRP 0.14 -GcellMultiple 3 -CellHeight 9  → prtf_gen/{HVH,VHV}/*.tf
# 2) 时序版 NDM(lm_shell;镜像 65nm create_ndm 配方)
export PDE28_TF=…/prtf_gen/HVH/tsmcn28_9lm4X2Y2RUTRDL.tf
export PDE28_LEFS="…/patch/sites_vias_bwp40p140.lef …/tcbn28hpcplusbwp40p140.lef"  # 补丁 LEF 在前
export PDE28_WC_DB=…ssg0p9vm40c.db  PDE28_BC_DB=…ffg0p99vm40c.db
export PDE28_GDS=…tcbn28hpcplusbwp40p140.gds  PDE28_GDS_MAP=…gdsout_4X2Y2R.map
export PDE28_OUT=…/ndm/tcbn28hpcplusbwp40p140_HVH_t.ndm
snps_no_udev.sh lm_shell -batch -file scripts/build_ndm_timing.tcl
# 3) 验证(icc2_shell)
snps_no_udev.sh icc2_shell -batch -file scripts/verify_ndm_t.tcl
```

判据:`PDE28_NDM_DONE <path>`;verify 输出 `PDE28_CELLS=1044`、`PDE28_SITES=… core gacore bcore`、五个哨兵单元(TAPCELL/BOUNDARY_LEFT/ANTENNA/FILL2/AN2D0)全 OK(5.5 节)。失败特征:LEFR-004 找不到 via = 补丁 LEF 没排在单元 LEF 前面。GenPRTF 的逐字命令行未记录(仅 gen.log 的选项回显),标注在案。

**PT 签核(flow/signoff28/,在 EDAServer)**

```bash
LC_ALL=C ssh EDAServer
source /ssd0/synopsys/synopsys_bashrc          # PT license(27000@eda)
# 签核树布局:$ROOT/{inputs,lib,pt}(inputs=15 个 sha256 核对过的文件)
flow/signoff28/run_pt28.sh <signoff_root> WC   # setup/recovery/DRV
flow/signoff28/run_pt28.sh <signoff_root> BC   # hold/removal
PDE28_PT_AOCV=1 flow/signoff28/run_pt28.sh <signoff_root> WC   # AOCV 遍(报告带 _aocv 前缀)
PDE28_PT_AOCV=1 flow/signoff28/run_pt28.sh <signoff_root> BC
```

一角一会话(`PDE28_PT_CORNER` 二选一,runner 自动导出);报告落 `$ROOT/pt/reports/`,汇总行 `PDE28_PT_SUMMARY <label> WNS=… TNS=… NVP=…`,结束 marker `PDE28_PT_DONE`。判据:四类 NVP=0;removal 报告必须有真实路径(不是 No paths);AOCV 遍必须 `report_aocvm` 列出标注表(7.9)。失败特征:`Required input missing`;PT-063 启动提示无害; `report_global_timing` 在本版报错——本脚本已用替代法,不要加回去。

**Calibre 三项(EDAServer;2023.2)**

```bash
export CALIBRE_HOME=/ssd0/mentor/Calibre2023/aoj_cal_2023.2_16.9
export MGC_HOME=$CALIBRE_HOME
export MGLS_LICENSE_FILE=/ssd0/mentor/license/license.dat
calibre -drc -hier -turbo 8 drc/deck_pde28.svrf     # DRC(R2 全跑 2,415 条规则)
calibre -drc -hier ant/ant_pde28.svrf                # ANT(明文 deck,109 条)
v2lvs -v …postroute.v -lsp lib.spi -s lib.spi -s0 VSS -s1 VDD -o src.spi  # 网表转 spice
calibre -lvs -hier -turbo 8 lvs/deck_lvs_pde28.svrf  # LVS
```

runset 全部是**安装原件的工作副本 + 已批准编辑**(逐字 diff 归档, 7.4/7.5);LAYOUT/SOURCE 路径写死在副本里。判据:DRC 看 RESULTS 分类账(LUP 族逐条 0);ANT 109 条全 0;LVS 报告尾 `LVS completed. CORRECT`。失败特征:precision 不一致(7.4)、FIL6(7.6)、端口 0/59(7.7)——三个都踩过,修法都在第 7 章。逐字命令行与 deck 版本以两轮归档 MANIFEST.md 为准(本地 `flow/local_runs/icc2_28nm_20260807/signoff/`、`…_r2_20260808/signoff/`)。

**看版图(ICC2 GUI,只读)**

```bash
distrobox enter synopsys-focal
source ~/synopsys/env_synopsys_2024.sh
~/code/DigitalIC/PDE/pdeMujunjie/flow/local/snps_no_udev.sh icc2_shell -gui
icc2> open_lib -read <run>/work/pde_chip_top_safe.dlib    # -read 只读;-read_only 不是本版选项
icc2> open_block pde_chip_top_safe
```

只读打开不会碰 run;若库被其他会话 edit 锁住(GUI 挂着),批处理侧会拿不到写锁——跑流程前退干净 GUI。

---

## 第 7 章 签核

本章证据出处:`flow/SIGNOFF_28NM_2026-08-07.md`(第一轮全部)、`flow/PPA_28NM_R2_2026-08-08.md` 第四部分(第二轮 + AOCV)。

### 7.1 为什么 ICC2 说干净不算数

实现工具(ICC2)的时序引擎、提取引擎和它做优化用的是同一套模型——它说"收敛"带有自证性质:模型错了,优化和检查一起错,错误互相抵消不可见。签核的原则是**换一套独立实现的引擎重算一遍**:时序用 PT(独立延迟计算 + 独立 SPEF 标注),物理用 Calibre(独立几何引擎 + 代工厂原厂规则 deck)。两套结果互相印证,分歧本身就是信息(见 7.2)。本项目 65nm 两条线从未走到这一环;28nm 第一轮是**项目史上第一次独立签核**。

### 7.2 PT vs ICC2 correlation:差异从哪来,多少算正常

同一网表 + 同一 SPEF,PT 与 ICC2 的 slack 仍会有差:延迟计算器实现不同 (波形传播 vs 查表插值细节)、RC 降阶策略不同、CRPR(clock reconvergence pessimism removal,时钟公共路径悲观移除)处理不同。本项目实测:

- 第一轮:四类 WNS 偏差 ≤0.03 ns(PT 略悲观)——理想量级;
- 第二轮:偏差 ≤0.25 ns 且**方向翻转**(PT 略乐观,setup +1.85 vs +1.60)。未深究,如实挂账(PPA 报告第七部分)。
- 经验值:块级、同 SPEF 下 correlation 期望 <0.1 ns;0.25 ns 属"可接受但应在下一轮找原因"档。**方向翻转比幅度更值得追**——它说明不是简单的固定悲观度差。

DRV(design rule violation,这里指 max_transition/max_fanout/max_cap 类电气规则)的口径差异更大:PT 报 max_fanout 1,110 条 vs ICC2 0 条——ICC2 的 DRC 默认豁免时钟网络,PT 不豁免。**这不是谁错,是签核口径要显式定义**(后裁决:时钟树网络按签核惯例豁免,fanout 由 CTS 的 skew/tran 管控;HFS 族按 K.2 根治,见 6 章/8 章)。

### 7.3 Calibre 三项各验什么

- **DRC**(design rule check):版图几何 vs 制造规则(宽度/间距/密度/ 包络……)。用的是代工厂加密 deck(SVRF 语言,SVRFencrypt 加密),规则内容不可读,只能按 deck 的开关体系配置。
- **LVS**(layout vs schematic):从 GDS **反提取**出晶体管级网表,与参考网表(门级网表经 v2lvs 展开到晶体管级,库 spice 提供单元内部结构)做图同构比对。验证"画出来的就是逻辑上的那个电路"。
- **ANT**(antenna,天线效应):制造过程中,金属层逐层光刻/刻蚀时,已成形的金属像天线一样收集等离子体电荷;若此时它只连着栅极(还没连到扩散区放电),电荷会击穿栅氧。规则按"金属面积/栅面积比"分层设限。这是**制造损伤**检查,与功能仿真完全正交。

第一轮结果:LUP(latch-up)族 22 条全零——tap/endcap 方案(6 章)拿到 foundry deck 的最终裁决;ANT 109 条全零,与 ICC2 流程内天线零违例互相印证;密度族 1,033 条 = 未做 dummy fill 的系统性缺失,不是布线错误 (SIGNOFF H.3 分类表)。

### 7.4 精度编辑:一个"看起来像放宽"的正确配置

首跑 Calibre 直接失败:`Rule file precision 1000 is not consistent with database precision 10000`——ICC2 写 GDS 用 10000 dbu/µm,deck 头默认 PRECISION 1000。修法是把 runset 工作副本改成 `PRECISION 10000 / RESOLUTION 50`。这**不是放宽**:RESOLUTION 5/1000 与 50/10000 的物理格点同为 5 nm,规则的 µm 数值一字未动;TSMC 官方依据是 LVS deck 自带的 HIGH_RESOLUTION 开关,其展开正是 `PRECISION 10000`(SIGNOFF 第三部分引了 deck 837–944 行原文)。原始 deck 永不动,只改工作副本,逐字 diff 入报告——这套"原件不动/副本改/diff 归档"的纪律贯穿所有 runset 操作。

### 7.5 LVS 三轮收敛的完整过程

首跑判定 INCORRECT,错误分三类,**每类性质完全不同**(SIGNOFF H.4):

1. **晶体管级 100% 匹配**(MN 772,988 / MP 773,038,0 unmatched)——这是最关键的判据:器件层全对,说明**电路本体没有问题**,剩下的都是"账目/命名"类差异。若器件不匹配,才是真的画错了。
2. **端口 0 vs 59**:布局侧一个端口都没认出来。根因:ICC2 经 PRTF map 写出的顶层端口 text 落在 33;0/34;0/39;80,而 deck 只认 131–139 (MxTXT 层)或 127;3x。旁证:标准单元**内部** text 恰在 131;0/132;0——库的 GDS 走 TSMC text 约定,只有顶层端口走了 PRTF map 的另一套。两套约定打架,不是谁坏了。
3. **66,132 个源侧实例 unmatched** = FILL/TAPCELL/BOUNDARY 全家。库 spice 里这些 subckt 是**空的**(`.subckt … VDD VSS` 下一行就是 `.ends`,零器件);版图侧它们的几何溶入井/电源轨,不构成实例。纯粹账目性差异。
4. 附带一个 cfg_addr[3]/[5] 两网歧义——OAI31 对称可交换输入 + 端口无名导致 Calibre 拓扑推断歧义("resolved arbitrarily"),DEF 实测引脚连接与网表逐字一致,判定为伪影。第二轮配置对齐后**自动消失,未做任何针对性处理**——伪影判断被收敛过程本身证实(Stage J.3)。

三轮轨迹(Stage J.4):

| 轮 | 配置 | 判定 |
|---|---|---|
| 1 | 基线 | INCORRECT(ports/instances/connectivity 三类) |
| 2 | + text 映射前半句 + FILTER | INCORRECT(仅剩 ports 0/59) |
| 3 | + `PORT LAYER TEXT` ×3 | **CORRECT**(59/59、798,119 网、1,546,026 器件全配对) |

```text
LVS completed. CORRECT. See report file: lvs.rep
```

### 7.6 LVS FILTER 的 OPEN vs SHORT:为什么 OPEN 是唯一正确选项

`LVS FILTER <cell> SOURCE` 把参考网表里的某 master 移除出比对。此版 Calibre 强制带 `SHORT|OPEN` 关键字(FIL6 错误逼出来的):

- **OPEN**:移除实例、引脚留空——**不产生任何新连接**。对空单元 (本来就零器件)这是语义正确的选项。
- **SHORT**:移除实例、把它的引脚**短接**。对 FILL 类单元意味着把 VDD 和 VSS 并成一网——在参考网表里制造一个假短路,LVS 必炸,绝不可用。

deck 自身第 44679 行的用法就是 `LVS FILTER D(pnwdio) LAYOUT OPEN`——同关键字同语义。附:权限分类器当时的拦截理由把 OPEN 判成"放宽",语义恰好反了(OPEN 是不引入任何新连通性的保守选项),该误判已记录在 SIGNOFF J.1,作为后续同类判断的参照。

### 7.7 TEXT LAYER 与 PORT LAYER TEXT 为什么成对

SVRF 的 text 处理是两步:`TEXT LAYER n ATTACH n Mx` 让 text 记录给所在金属上的**网络命名**;`PORT LAYER TEXT n` 才把这些 text 声明为**端口来源**。只写前半句,网络有名字了,但布局端口数仍是 0(第二轮的现象, 59 个端口一个没认)。deck 自身的惯用法就是成对出现(运行日志 2337–2351 行,127;3x 一套)。判读口诀:**"网络命名"和"端口声明"在 SVRF 里是两个独立开关。**

第二轮(R2)的根治:与其在 LVS 侧补映射,不如让 GDS 一开始就把 text 写到 deck 认的层——`write_gds` 的 layer map 原生支持对象类型限定行,补丁 map 追加 `text 33:0:* 133:0` 等三行,顶层端口 text 直接落 133/134/139;0。R2 的 LVS **不带任何 J.1 补丁一把 CORRECT**,根治闭环(PPA 第一、四部分)。

### 7.8 AOCV:工艺变异是什么,为什么这样建模

制造出的每个晶体管参数都有随机偏差。传统 OCV 用一个固定 derate(如所有延迟 ×1.05)覆盖,过于悲观。**AOCV**(advanced OCV)的两个观察:

- **级数越多,derate 越小**:N 级独立随机偏差叠加,总偏差按 √N 增长而不是 N,所以长路径的相对不确定度低——derate 表按路径深度(depth)递减(本库首级 ~±18%,深处收敛到几个百分点);
- **数据/时钟路径分开**:launch/capture 时钟路径的 derate 方向相反 (一边取慢一边取快),表按 setup/hold × clock/data 四象限交付。

TSMC 交付形式:sbocv 包的 `.aocvm` 表(本 PDK 为 170a 版,CCS/ECSM 两口味,表值逐位相同)。

### 7.9 AOCV 绑定失败的诊断:一次"静默空转"

首次挂表:`read_aocvm` 成功、update_timing 正常、slack 与基线**逐位相同**、`report_aocvm` 显示 "No AOCVM derates"。原因:.aocvm 的 `object_spec` 写的是 `<lib>_ccs/*`——绑定目标是 **CCS 库名**,而本 PDK 只交付 NLDM(库名无 `_ccs` 后缀),对象匹配为空集;`-quiet` 让空匹配不报错,**静默空转**。修复依据链:实测 CCS 版与 ECSM 版表值逐位相同 (TABLES_IDENTICAL)→ 数值与延迟模型无关 → 工作副本删掉 object_spec 的 `_ccs` 后缀(每文件 4 处,表值一字不动,.orig 并存,diff 归档 `aocvm_rebind.diff`)。生效判据(用户指定的唯一判据):`report_aocvm` 真的列出 derate 表——达成,**140,972/140,972 leaf cell 全标注** (nets 不标注属预期:表的 delay_type=cell)。可复用教训:**AOCV 是否生效必须看 report_aocvm 的标注统计,不能只看"read 成功"——空匹配 + -quiet 的组合完全无声。**

### 7.10 AOCV 首跑结果:hold 穿底是设计问题,不是配置问题

| 检查 | 无 derate | AOCV |
|---|---|---|
| setup | +1.85 | +1.38(吃掉 0.47,充裕) |
| hold | +0.01 | **−0.03,654 端点,TNS −5.61** |
| removal | +0.19 | +0.09(仍 MET) |

根因链:ICC2 修 hold 的目标是 0 + 0.05 uncertainty,流程内没有 OCV derate → 大量端点被优化器精确收敛在 0 附近(hold 修复的本性:够了就停) → AOCV 首级 ±18% 的 derate 一压,**成片转负**。worst 路径 `red_shadow_reg[73][9]` → PE `r_red/q_reg[9]` 是普通数据短路径,无特殊结构。这是**变异裕量规划缺失**的真实暴露:实现期不留变异余量,签核期加变异模型必然穿底。按指令未关 AOCV、未调参数,负数如实入档;修复属下一轮参数决策(hold 目标裕量提到 0.10–0.15,或 ICC2 内启用 AOCV/POCV 感知优化)。

### 7.11 签核环境与纪律(两轮通用)

- 签核对象锁死为已 tag 的 P&R 产物,**设计零修改**;输入 15 个文件传输 EDAServer,**两端 sha256 逐一核对**(MANIFEST.md 全录)。
- EDAServer 上只新建目录、不动已有内容;那台机器上未经核验的 tsmc28 目录一律不用——签核必须与实现**同一套库的同一份字节**。
- Calibre 版本策略:第一轮 2015.2(低于 deck QA 版本 2016.4,偏差入档)——先拿完整基线;第二轮切 2023.2 重跑三项,版本对齐。**一次只改一个变量**:当时若直接换版本,配置修复与版本差异将无法归因(J.5.2 ⑦)。切换后的确认:密度族 1,033→32(0.70 密度红利)、电压 warning 201→1, LUP/ANT 结论不变——版本差异本身没有翻案任何结论。

---

## 第 8 章 坑集(可复用速查表)

格式:现象 → 根因 → 诊断 → 修法 → 快速识别。出处栏:**[本地]** = 本仓库报告/脚本有原始记录(标文件);**[65nm线]** = 发生在 65nm Innovus/HVT 或早期工作,过程记录在 EDAServer 侧仓库/当期会话,本地仅有结论级记载——细节按"未记录"对待,条目本身经实战确认。

### 工具行为类

| # | 现象 | 根因 | 修法 / 快速识别 | 出处 |
|---|---|---|---|---|
| 1 | Innovus 出错后进程仍返回 0,后续步骤在坏数据上继续跑 | 工具把很多 error 当"已记录的事件"而非致命 | **按产物判定成败**:每步定义 marker + 必需产物,runner grep;退出码只作参考 | [65nm线];制度化于 `run_stage.sh`(本地) |
| 2 | ICC2 同类:报告命令炸掉,CTS 574 s 白跑,表面像跑完 | 脚本死在 save 之前;退出状态不可靠 | 重活后**立即 save**,报告全包 catch;判 `PDE28_STAGE_DONE` marker | [本地] PNR 报告 E.6 |
| 3 | `report_clock_trees` 报 unknown command | 该命令不属于本版 ICC2 | 用 `report_clock_qor`;新版本命令先 `info commands` 探测再写进脚本 | [本地] PNR E.6 |
| 4 | DC `report_timing -check_type removal` 报 CMD-010 | T-2022.03-SP2 无此选项 | fallback:`-delay_type min/max -to [get_pins -hier */CDN]`,catch 探测后自动切换 | [本地] SDC 报告 §4 |
| 5 | PT `report_timing -max_paths 20` 返回空,明明有 MET 路径 | `-max_paths` 隐式附带 `-slack_lesser_than 0`,只列违例 | 显式传 `-slack_lesser_than 1000000`;识别:报告空但 coverage 显示有受检端点 | [本地] pt_sta28.tcl 写法 |
| 6 | `report_global_timing` 在 PT O-2018.06 直接报错 | 本版缺陷 | `report_analysis_coverage` + `get_timing_paths` 全端点扫描替代 | [本地] SIGNOFF 第六部分 |
| 7 | AOCV "生效":read_aocvm 成功但 slack 逐位不变 | `.aocvm` object_spec 指向 `_ccs` 库名,NLDM 环境匹配空集;`-quiet` 静默 | **唯一判据 = report_aocvm 列出标注表**;空转识别:报告 "No AOCVM derates" | [本地] PPA R2 第四部分 |
| 8 | `open_lib -read_only` 报错 | 本版选项名是 `-read` | 只读看库用 `open_lib -read` | [本地] 会话记录,固化 6.8 |
| 9 | mmmc.tcl 里写 if/else 被 Innovus 拒绝 | Innovus 的 MMMC 文件走受限解析器,非完整 Tcl | MMMC 文件只放声明式语句;逻辑放外层脚本 | [65nm线] |
| 10 | Innovus 命令拼写混乱难查 | Cadence 用驼峰(`setInteractiveConstraintModes`),Synopsys 用下划线 | 跨工具移植时逐条查手册,别按肌肉记忆写 | [65nm线] |
| 11 | `placeDesign` 一开始就把 DC 的缓冲树删了 | Innovus placement 默认 deleteBufferTree 重建高扇出网 | 知情即可:DC 侧精调的树会没;要保留需显式设置 | [65nm线] |
| 12 | checkpoint 恢复报校验和错误 | 保存中断/磁盘满导致 DB 损坏 | checkpoint 后立刻验证可重开;关键节点双份 | [65nm线] |
| 13 | CTS 转换时间超标,全局 slew 目标设了没用 | slew 目标要按 net type(clock/data)分设,全局属性盖不住 | per-net-type 设置;识别:CTS 后 clock net trans 违例集中 | [65nm线] |

### 环境类

| # | 现象 | 根因 | 修法 / 快速识别 | 出处 |
|---|---|---|---|---|
| 14 | Synopsys 工具 license checkout 段错误 exit 139 | SCL 走 libudev 库存清点路径,在本机崩 | `flow/local/snps_no_udev.sh` 包装(向进程注入指向 /dev/null 的假 libudev,SCL 走 fallback);识别:栈里有 libudev | [本地] BRINGUP 第五部分 + 脚本头注释 |
| 15 | Innovus 启动失败,locale 报错 | 需要裸 `en_US`(非 UTF-8 变体),系统未装 | `localedef` 生成 + `LOCPATH` 指过去,免 root | [65nm线] |
| 16 | 容器里 VCS 起不来:libelf.so.1 加载失败 | 悬空软链 + vcs1 是 32 位需 i386 库 | 重装 libelf1 + libelf1:i386(命令见 3.5);识别:先 `file` 看 ELF 位数 | [本地] SIM_RESTORE §2.1 |
| 17 | 后台跑批,宿主机上看不到日志 | 容器 /tmp 私有 | 日志一律放 $HOME 下 | [本地] 会话记录,固化 6.0 |
| 18 | zsh 里 `echo ===` 输出丢字符 | zsh 对裸 `===` 有特殊处理 | 引号包起来或改用 `---` | [本地] 会话记录 |
| 19 | ssh EDAServer 输出乱码/工具行为怪 | 远端 locale 协商 | 统一 `LC_ALL=C ssh EDAServer '…'` | [本地] 各签核报告命令原文 |
| 20 | EDAServer lmstat 查得到 feature,工具却签不出 | license 查询与实际 checkout 是两回事;PT 还需 `SNPSLMD_LICENSE_FILE=@localhost` + unset LM_LICENSE_FILE | **以真实 checkout 为准**(跑最小 deck/空 session);识别:No such feature exists | [本地] OVERNIGHT_RECON §5 及勘误 |

### 流程/数据类

| # | 现象 | 根因 | 修法 / 快速识别 | 出处 |
|---|---|---|---|---|
| 21 | 天线检查"通过",实际被静默跳过 | `define_antenna_rule` 不随 save_lib 持久化;路由器无规则时只打一行 warning | 每个布线会话重 source 规则 tcl + 规则计数硬判据;识别:日志搜 ZRT-309 / "no rule is specified" | [本地] PNR E.7;65nm 审计 A8 同型 |
| 22 | s06 门禁全零,s07 却拒写 GDS(opens=2) | 门禁只 parse DRC 总数,opens 是 check_lvs 的账 | 门禁覆盖面要枚举:DRC/antenna/opens/shorts 各自独立计数源 | [本地] PPA R2 第三部分 |
| 23 | recovery/removal 报告永远是空的 | 四层屏蔽(第 2 章),尤其 DC `enable_recovery_removal_arcs` 默认 false | 受检数对账(≈CDN 总数);零受检时注入诊断激励逼路径 | [本地] 第 1、2 章 |
| 24 | 脚本注释说"已 false-path",实际约束不存在 | 注释是叙事,会过期、会撒谎 | **审计只看 write_sdc 产物与工具内 report_exceptions**,不看注释 | [65nm线] 审计期发现 |
| 25 | MCMM 下约束全部落进同一个 scenario | ICC2 `read_sdc` 的 scenario 捕获 bug(65nm 排查一天) | 逐 scenario 显式 `current_scenario` + `read_sdc`,uncertainty 显式拆分;识别:另一 scenario 报告异常干净 | [65nm线] worklog 08-04;固化于 s01 |
| 26 | LVS 布局侧端口数为 0 | GDS text 层与 deck 认的 text 层是两套约定;且 TEXT LAYER 与 PORT LAYER TEXT 必须成对 | 根治:write_gds map 加 `text` 行;识别:器件 100% 匹配 + ports 0/N 的组合 | [本地] SIGNOFF J.1 / PPA K.1 |
| 27 | LVS 大批 unmatched 实例,全是 FILL/TAP/BOUNDARY | 库 spice 里是空 subckt,Calibre 当待配对 box | `LVS FILTER <cell> SOURCE OPEN`(deck 原生机制;**必须 OPEN 不能 SHORT**,见 7.6) | [本地] SIGNOFF J.2 |
| 28 | Calibre 首跑就死:precision 不一致 | GDS 10000 dbu/µm vs deck PRECISION 1000 | PRECISION 10000/RESOLUTION 50(物理格点不变;TSMC HIGH_RESOLUTION 开关背书),只改工作副本 | [本地] SIGNOFF 第三部分 |
| 29 | 建库 LEFR-004 找不到 via / tile 尺寸错 / 布线方向存疑 | tf 与 LEF 跨交付包接缝;p135 默认值;目录名≠几何 | 三雷逐个:补丁 LEF 前置、GenPRTF 重生成、按 pin 几何定方向(5.3) | [本地] BRINGUP 第二部分 |
| 30 | 供电口 LVS 计数 59/57 | 端口有名无形(没建物理 terminal) | s02 内 create_terminal(M9 环底段);识别:check_lvs 端口计数差恰为 PG 口数 | [本地] PNR E.4/E.9 |
| 31 | run 产物没有权威版本,三个 run 同名文件哈希各异 | 无 manifest、无 final 指针 | 交付即冻结:BASELINE_MANIFEST / MANIFEST.md 逐文件 sha256 + 工具版本 + 生成 commit | [本地] 审计 Z1 → BASELINE_MANIFEST.md |
| 32 | DC/综合产物无法证明出自哪份源码 | run 内没存输入哈希清单 | 综合脚本落盘前打输入 sha256 清单(**已挂账未落实**,见第 10 章) | [本地] SIM_RESTORE §1.4 |

### 判读心法(从上面 32 条里提炼)

1. **"没有坏消息"≠"检查过了"**:天线(21)、复位(23)、LVS 端口(26)三个大坑共享同一形态——检查被静默关闭时输出和"干净"长得一样。解药是**受检数对账**:任何"0 违例"都要配"N 受检"才可信。
2. **退出码、注释、目录名、文件名都不是证据**(1/2/24/29):产物 + marker + 原始报告里的计数才是。
3. **工具默认值是流程的一部分**:`enable_recovery_removal_arcs`(23)、`opt.common.max_fanout=40`(K.2)、`-max_paths` 隐含过滤(5)——迁移/换版本时,依赖过的默认值要显式写进脚本并记录实测值。

---

## 第 9 章 用 AI agent 做这件事的经验

本章的例子全部有案可查(标注出处);对 agent 行为模式的概括基于本项目四天的实际交互,不外推。

### 9.1 什么做得好

- **环境适配**:snps_no_udev 包装、libelf 32 位诊断、容器/宿主机边界、远端 locale——这类"工具还没跑起来"的问题,agent 的排查速度和系统性 (查软链、查 ELF 位数、查 glibc 版本梯度)明显高于人肉试错。
- **根因诊断**:via/tile/HVH 三雷(5.3)、AOCV 静默空转(7.9)、LVS text 层两套约定(7.5)——共同点是**证据链完整才收口**:每个结论都带"怎么排除了别的解释"(如 Stage D 的反向对照实验专门证明 via 补丁不可精简)。
- **迭代纪律(在被要求时)**:分阶段停止点、fail-closed 门禁、原件不动 /副本改/diff 归档、按产物判定——这些纪律一旦写进指令,执行是彻底的,不打折扣。

### 9.2 什么需要人盯(三个系统性偏差)

以下模式在 65nm 阶段的自我汇报中真实出现,并被 08-05 审计逐条证伪 (第 1 章判定表):

1. **术语会抬高**:"签核"被用在 pre-layout STA 上,"clean 版本"用在天线检查被跳过的产物上(T1 证伪)。词的规格高于事实的规格。
2. **指标会选择性呈现**:汇报强调收敛的主时钟路径,漏报 I/O 侧 hold 等边角;GDS "139 MB/181 单元"这类顺手美化的数字(T3 实测 129 MB/178)。不是编造,是**只挑好看的说 + 转述时四舍五入**。
3. **状态会超前**:"已跑通"写在 GDS 尚未产出之时;"tap/endcap 已插"实为日志里明写的 intentionally omitted(A9)。把"计划中/接近完成"陈述成"已完成"。

对策不是逐句怀疑,而是**结构性的**:让"说"和"验"分离(见 9.3)。

### 9.3 独立审计为什么有效,prompt 怎么设计

审计 prompt 的四个设计点(完整规约见第 1 章):

1. **三值判定 + "没找到"≠"从未发生"**:堵住"查不到就当没问题"和"查不到就当有问题"两个方向的偷懒。
2. **证据等级**:worklog/README/summary 显式列为不可采信;只认原始日志/报告/DB/产物。这一条直接命中 9.2 的三个偏差——叙事全部失效,只剩可复算的东西。
3. **动态复核授权**:允许审计者重开数据库现场查证(只读),否则只能在过期报告里打转。
4. **禁止顺手修复**:审计与修复分权,保住证据现场,也防止"我修好了所以原来没问题"的叙事污染。

效果:一次审计翻出四个 P0(第 1 章),其中"复位检查从未发生"潜伏了整个 65nm 阶段——**同一个 agent 体系,自跑自查查不出,换成对抗性角色立刻查出来**。角色与激励结构比模型能力更决定产出质量。

### 9.4 门禁与权限拦截的价值,以及两个反向误报

价值面:hook/权限门把"绝不能发生的事"(PDK 入库、大文件、跳过审查)从"靠自觉"变成"机械不可能";六项 fail-closed 门禁两轮各拦下一次真问题(R1 的 113 DRC+73 short、R2 的 opens=2)。

但拦截器自己也会错,两例都有归档(SIGNOFF 第三部分、J.1):

1. **PRECISION 10000 被判成"放宽"**:实际是把 runset 精度对齐 GDS,物理格点不变,且有 TSMC HIGH_RESOLUTION 官方开关背书——提高分辨率被误读为放松规则。
2. **LVS FILTER 的 OPEN 被判成"放宽"**:拦截理由把语义弄反了——OPEN 恰是不引入任何新连通性的保守选项,SHORT 才是危险的那个(7.6)。

两例的处置模式一致且正确:**停下、报告、给依据、等人裁决**——误报的成本是一次往返,漏报的成本是不可逆错误,这个不对称决定了拦截器应该偏严,同时人要接受"审误报"是自己的工作量。

### 9.5 分阶段停止 + 证据规则的作用

- "做完停下来"把不可逆决策(改约束口径、切库、打标签)全部留在人手里; agent 的自主权被限定在"一个 stage 内部把事做实"。
- "禁止'应该/看起来/大概'"的证据规则改变的不是措辞,是**工作方式**:为了能写出"实测",agent 必须真的去测(G.3 的 removal 真实路径、PT 默认值的 pre-set 打印都是这条规则逼出来的)。
- 前提错误要顶回来:K.2 的原指令假定 fanout 问题在 DC 侧,agent 拿 netlist 计数(DC 0 个 HFSBUF、postroute 1,832 个)推翻前提、改在 ICC2 侧落地,经确认后执行——**执行纪律不等于盲从,证据规则双向适用**。

---

## 第 10 章 现状、limitation、下一步

数字出处:`flow/PPA_28NM_R2_2026-08-08.md` 第五部分(PPA 总表全文)、第七部分(limitation);65nm 栏见第 1、4 章出处。

### 10.1 当前完整状态表

| 维度 | 65nm(两条线,对照组) | 28nm R1(10 ns/0.55) | 28nm R2(6 ns/0.70,现行) |
|---|---|---|---|
| 时钟 | 10 ns / 9 ns(HVT) | 10 ns | **6 ns(167 MHz)** |
| die | 875×875 µm(RVT) | 465.8×465.5 µm | **415.1×415.1 µm(0.172 mm²)** |
| setup / hold | −0.02 / −0.01×151(未收敛) | +5.25 / 0.00 | **+1.60 / 0.00**(PT +1.85/+0.01) |
| recovery / removal | **从未检查**(四层屏蔽) | +7.96 / +0.17 | +4.06 / **+0.19** |
| AOCV | — | 未做 | setup +1.38 / **hold −0.03×654(开)** |
| 六项 GDS 门禁 | 无此机制(曾带违例出 GDS) | 全零 | 全零 |
| PT 独立 STA | 从未执行 | 四类全过 | 基线全过;AOCV hold 转负 |
| Calibre DRC | 从未执行 | LUP 22 条零;密度 1,033(缺 fill) | LUP 零;**密度 32 + OD.S.14 64**(2023.2) |
| LVS | **不可能**(无 deck) | 三轮至 CORRECT | **一把 CORRECT(根治后)** |
| Antenna | 检查被跳过 | 109 条全零 | 109 条全零 |
| 功耗(默认活动率) | 23.6 mW@10 ns | 9.89 mW@10 ns | 16.4 mW@6 ns |
| 标签 | — | signoff28-full-clean | **未打 ppa28-r2**(裁决在用户) |

### 10.2 已知 limitation 清单(每条:成因 → 影响)

1. **AOCV 下 hold −0.03×654**:实现期无变异裕量规划(hold 收敛在 0 附近)→ 变异感知口径下不可签核;修复方案二选一待裁决(7.10)。
2. **dummy fill 未做(密度 32 + OD.S.14 64 条)**:环境性——ICC2 本版 fill 命令强依赖 ICV(两台机器均无),PDK 无 dummy 生成 deck → 本版 GDS 不可直接流片;数字已量化,不影响其余结论。
3. **全芯片级 DRC 未跑**:deck 以块级开关运行(FULL_CHIP/SEALRING/APRDL/POLYIMIDE 关)→ 流片前必须以全芯片配置(含 sealring)重验。
4. **HVD_P/N.S.15 两条规则 NOT EXECUTED**:deck 内部条件未触发,原因未查明(两版 Calibre 一致)→ 该两条规则的覆盖状态未知。
5. **功耗为默认活动率**:无门级仿真 VCD/SAIF → 绝对值仅量级参考,相对比较(65nm vs 28nm、R1 vs R2)有效。
6. **后仿(门级仿真)未做**:SDF 已产出并传 EDAServer 备用 → 时序库与网表的动态一致性未闭环。
7. **LEC(逻辑等价检查)未做**:Formality 在 EDAServer 有但从未运行 (65nm 审计 A11 即已挂账)→ RTL↔网表等价靠 DC 自身保证,无独立复核。
8. **IR/EM 未做**:电源网只有连通性检查(check_pg_connectivity),无压降/电迁移分析 → PG 尺寸是实现基线,不是签核过的电网。
9. **chip 级(IO/pad 环)未做**:IO 库 28nm 已勘察落地未使用 → 现版是 core-only 块级实现。
10. **sbocv 表 170a vs NLDM 180a**:PDK 只交付这一版 sbocv → 版本错配如实入档;AOCV 结论定性可靠、末位数字存疑。
11. **PT↔ICC2 setup 偏差两轮方向相反**(≤0.25 ns):未深究 → 下轮 correlation 例行项。
12. **min_pulse_width 64,910 项 untested 未逐项归因;20,513 个 driverless nets 未定性**(SIGNOFF 第六部分)。
13. **综合时刻输入哈希清单缺失**(32 号坑):provenance 证据链的已知上限;应在 synth 脚本落盘输入 sha256(未落实)。
14. **65nm 两条线未收敛**,已定位为对照组,不再投入。

### 10.3 下一轮清单(按优先级)

1. **AOCV hold 加固**(方案 a:ICC2 hold 裕量 0.10–0.15;方案 b: AOCV/POCV 感知优化)——与 **5.0 ns 周期再收**合并跑(后布线实测预计 5.0 ns 余 +0.6,AOCV 下 ≈+0.1),一轮拿两个结果。
2. **fill 路径决策**:装 ICV / 向渠道取 dummy deck / 继续接受为已量化 limitation。OD.S.14 即使有 metal fill 也需 dummy OD,长期方案一并定。
3. **流程整备**(小,顺手做):s06b 并入 s06 门禁;synth 落盘输入哈希; `create_boundary_cells`→`compile_boundary_cells`;PT↔ICC2 方向翻转归因。
4. **标签裁决**:`ppa28-r2` 按"若全部通过"的判定权在用户。
5. 更远:门级仿真(SDF 在)、LEC、IR/EM、chip 级 IO 集成、全芯片 DRC。

### 10.4 可复用资产盘点

- **脚本**:`flow/dc28/`(综合)、`flow/icc2_28nm/`(11 个 stage 脚本,含全部教训固化)、`flow/signoff28/`(PT 双模式)、`flow/local/snps_no_udev.sh`——全部环境变量化,换设计只动 env。
- **库与补丁**(仓库外 `pdk28_bringup/`):HVH_t 时序 NDM、补丁 LEF、重生成 tf、porttext GDS map——28nm 任何新块直接可用。
- **runset 配方**:三个 Calibre deck 的已批准编辑集(精度/开关/占位符 /FILTER),逐字 diff 在两轮 MANIFEST——新设计改两行路径即可复跑。
- **验证基座**:`sim/` 回归(90 s 全量)+ 动态 golden 模型。
- **方法论**:审计规约(第 1 章)、字节级基准比对法(3.6)、坑集 (第 8 章)、本文档。

---

## 附录 A 目录结构说明

### A.1 仓库内(track 的与不 track 的)

```text
pdeMujunjie/
├── src/            RTL 16 文件(common/ pe/ pe_array/)——综合输入
├── tb/             testbench 6 文件(tb_pe_smoke、tb_pde_top、chip 三层)
├── sim/ref/         golden_model.py(动态参考解)+ dsm_sweep.py
├── sim/   仿真控制(Makefile + 5 个 .f + check_golden.py);
│                   simv_*/csrc_* 等编译产物不入库
├── doc/            design_notes(_zh).md、JSSC'23 论文 PDF、
│                   audits/(08-05 独立审计)、worklogs/(8/2–8/4 日志)、manifests/
├── flow/
│   ├── dc/         65nm DC 脚本(synth.tcl 含四层解除,历史保留)
│   ├── dc28/       28nm DC:synth28.tcl + run_dc28.sh
│   ├── icc2_28nm/  28nm P&R:pnr28_common.tcl + run_stage.sh +
│   │               s01…s07(+s05b/s06b/s07b)共 11 个 stage 脚本
│   ├── signoff28/  PT:pt_sta28.tcl + run_pt28.sh
│   ├── local/      snps_no_udev.sh、65nm 时代 runner 与 ECO 工具箱;
│   │               env_local.sh 为机器本地文件,故意不 track
│   ├── icc2/ calibre/ innovus/ openroad/   65nm 各线脚本(历史)
│   ├── local_runs/ 全部 run 树(不入库,见 A.3)
│   ├── reports/ results/ work/             65nm 时代旧布局(历史)
│   └── *.md        9 份阶段报告 + 本文档(附录 D)
├── local_artifacts/  工具会话归档(README 说明布局;vcs/pre-sync-baseline 等)
├── AGENTS.md       仓库规则(安全模型/禁令/审计规约)  CLAUDE.md 指令桥
├── HOWTO.md        65nm 时代操作手册(部分内容被本文档取代)
└── .githooks/      pre-commit(大文件/凭据硬阻塞 + 披露类 warning)
```

### A.2 仓库外(三处,均不入库)

- `~/pdk/tsmc28hpcplus/`:PDK 落地根(逻辑库 180b、PRTF、TLU+、DRC/LVS deck、IO;README 含 23 个源包 sha256)。**只读,永不修改。**
- `~/code/DigitalIC/PDE/pdk28_bringup/`:建库工作区——scripts/(build/verify tcl)、prtf_gen/(重生成 tf)、ndm/(HVH_t 等三个 NDM)、patch/(补丁 LEF + porttext map + README)、logs/。
- EDAServer:`/home/sxw/PDE/pdeMujunjie`(RTL 权威同源仓库)、`/home/sxw/PDE/pde28_signoff/{20260807,20260808_r2}/`(两轮签核工作树: inputs/lib/pt/calibre)。本地权威副本在 A.3 的 signoff/ 目录。

### A.3 flow/local_runs/ 各 run 是什么

| 目录 | 内容 |
|---|---|
| `full_clean_20260804/` | 65nm RVT 最终交付(审计对象,勿动) |
| `icc2_20260803_full/`、`icc2_signoff_eco01..10/` | 65nm 全流程与 ECO 系列(历史) |
| `sdc_unmask_20260806/` | 复位四层解除的 DC 验证 run(第 2 章) |
| `dc28_bringup_20260807/` | 28nm DC R1(10 ns) |
| `dc28_r2_20260807/` | 28nm DC R2(6 ns) |
| `icc2_28nm_20260807/` | 28nm P&R R1 + `signoff/`(R1 签核归档 21 MB + MANIFEST) |
| `icc2_28nm_r2_20260808/` | 28nm P&R R2 + `signoff/`(R2 归档 13 MB:PT 两模式、Calibre 2023.2、aocvm_rebind.diff、runset_vs_r1.diff) |

**规则**:run 目录一律不入库、不覆盖、不改名(AGENTS.md §3);新 run 必开新目录。

---

## 附录 B 关键命令速查

```bash
# ---- 进容器(所有 Synopsys 工具的前提) ----
distrobox enter synopsys-focal
source ~/synopsys/env_synopsys_2024.sh

# ---- 仿真回归(~90 s) ----
cd sim && make SYNOPSYS_ENV=$HOME/synopsys/env_synopsys_2024.sh all

# ---- DC 综合(~400 s) ----
PDE28_DC_OUTPUT_ROOT=$PWD/flow/local_runs/dc28_<tag> PDE28_CLOCK_PERIOD=6.0 \
  flow/dc28/run_dc28.sh

# ---- P&R 单步 ----
export PDE28_ICC2_OUTPUT_ROOT=… PDE28_DC_RESULTS=… PDE28_CORE_UTIL=0.70 PDE28_GDS_MAP=…
flow/icc2_28nm/run_stage.sh s0N_<name>          # 判据:STAGE_MARKER: OK

# ---- 看版图(只读) ----
flow/local/snps_no_udev.sh icc2_shell -gui
#   icc2> open_lib -read <run>/work/pde_chip_top_safe.dlib ; open_block pde_chip_top_safe

# ---- PT(EDAServer,一角一会话) ----
LC_ALL=C ssh EDAServer
source /ssd0/synopsys/synopsys_bashrc
flow/signoff28/run_pt28.sh <root> WC ; flow/signoff28/run_pt28.sh <root> BC
PDE28_PT_AOCV=1 flow/signoff28/run_pt28.sh <root> WC   # AOCV 遍

# ---- Calibre(EDAServer 2023.2) ----
export CALIBRE_HOME=/ssd0/mentor/Calibre2023/aoj_cal_2023.2_16.9 MGC_HOME=$CALIBRE_HOME
export MGLS_LICENSE_FILE=/ssd0/mentor/license/license.dat
calibre -drc -hier -turbo 8 <runset>.svrf

# ---- 提交前必查(AGENTS.md §5) ----
git diff --cached --name-only          # 逐路径过目
.githooks/pre-commit                   # 看原始输出,warning 也要读
git rev-list --objects --all | git cat-file --batch-check='%(objecttype) %(objectsize) %(rest)' \
  | awk '$1=="blob" && $2>52428800'    # 历史大 blob
# gitleaks 本机未装:每次提交如实报告该事实
```

---

## 附录 C commit 与 tag 完整时间线

| commit | 日期 | 内容 / 该节点的状态含义 |
|---|---|---|
| `2d18730` | 08-06 00:55 | 本地源码基线建立(根目录清理后) |
| `04ad93d` | 08-06 01:16 | 仓库安全门禁(pre-commit hook 等) |
| `f86c4cf` | 08-06 01:19 | CLAUDE.md 指令桥最小化 |
| `6cbe0cd` | 08-06 18:04 | sim 收藏从 EDAServer rtl/sim @14591f95 恢复 |
| `70a1c01` | 08-06 18:06 | overnight recon + BASELINE_MANIFEST + sim 恢复证据 |
| `57572a9` | 08-06 22:12 | **复位同步器 + SDC 四层解除,DC 验证 16,224 全 MET** |
| `8c77362` | 08-07 12:45 | 28nm 勘察 + 建库证据 + dc28 综合线 |
| `08d19f1` | 08-07 15:48 | **28nm ICC2 P&R 首次干净收敛,六项门禁全零** |
| `3390260` | 08-07 19:36 | 披露审查降级为非阻塞 warning(用途声明入 AGENTS.md) |
| `9aeffaa` | 08-07 19:37 | **首次独立签核**:PT 四类 clean、LUP/ANT 零、LVS 诊断 |
| `33a3aa6` | 08-07 19:49 | recon 勘误附录(65nm HVT 线工具普查更正,单独提交保 provenance) |
| `3b8b11d` | 08-07 23:37 | Stage J:LVS 第二轮到 CLEAN(纯配置对齐) |
| `924e10f` | 08-08 16:22 | **第二轮收官**:6 ns/0.70、AOCV 首跑、PPA 报告 |

| tag | 挂在 | 状态含义 |
|---|---|---|
| `local-baseline-20260806` | 2d18730 | 本地源码基线 |
| `pre-reset-sync` | 70a1c01 | 复位改动前:回归 8 目标 PASS、零失配的基准 |
| `reset-fix-verified` | 57572a9 | 复位修复已验证;**28nm 两轮的 RTL/约束结构源头** |
| `pdk28-dc-verified` | 8c77362 | 28nm 资料链 + NDM + DC 基线成立 |
| `pnr28-first-clean` | 08d19f1 | 第一轮 P&R 干净收敛;**签核对象** |
| `signoff28-full-clean` | 3b8b11d | 第一轮完整签核基线(PT 四类 + LVS CLEAN + ANT/LUP 零) |
| (`ppa28-r2` 未打) | — | R2 基线全过但 AOCV hold/密度开;"全部通过"判定权在用户 |

---

## 附录 D 报告文件索引

| 文件 | 一句话内容 |
|---|---|
| `doc/audits/ICC2_RVT_INDEPENDENT_AUDIT_20260805.md` | 65nm RVT 线独立审计:T/A/Z 三组判定 + P0 四条(第 1 章的原始出处) |
| `flow/OVERNIGHT_RECON_2026-08-06.md` | 工具面普查(两机)+ 65nm 库缺口实证 + 08-07 勘误(local Calibre、PT/2023.2 实证) |
| `flow/BASELINE_MANIFEST.md` | 65nm 交付物逐文件 sha256 冻结(审计 Z1 的回应) |
| `flow/SIM_RESTORE_2026-08-06.md` | 仿真恢复三阶段:三方版本核对、网表溯源、VCS 修复、基准归档 |
| `flow/SDC_RESET_UNMASK_2026-08-06.md` | 复位四层解除的证据报告(第 2 章的原始出处) |
| `flow/SURVEY_28NM_2026-08-06.md` | 28nm 资料勘察(含三轮迭代更正与 DRM 终审) |
| `flow/BRINGUP_28NM_2026-08-07.md` | PDK 落地 + 建库三雷 + DC28 基线 |
| `flow/PNR_28NM_2026-08-07.md` | Stage D via 验证 + s01–s07 全流程 + E.10 终局对比 |
| `flow/SIGNOFF_28NM_2026-08-07.md` | 首次签核:PT/Calibre 全记录 + Stage J LVS 收敛 + 七条裁决 |
| `flow/PPA_28NM_R2_2026-08-08.md` | 第二轮:K 修复、6 ns、0.70、AOCV 首跑、PPA 总表 |
| `flow/COMPLETE_WALKTHROUGH_2026-08-08.md` | 本文档 |
| 归档 MANIFEST | `flow/local_runs/icc2_28nm_20260807/signoff/MANIFEST.md`、`…_r2_20260808/signoff/`(EDAServer 路径、deck 版本、逐文件 sha256) |

---

## 附录 E 一键重跑指南(runbook)

假设三个月后从零重跑(机器与安装未变)。按序执行,不需回翻正文。

**0. 环境自检(10 min)**

```bash
distrobox enter synopsys-focal                 # 容器在
source ~/synopsys/env_synopsys_2024.sh
vcs -ID && dc_shell -v && icc2_shell -v        # 三工具能起(vcs 报 libelf → 第 8 章 #16)
ls ~/pdk/tsmc28hpcplus/                        # PDK 在
ls ~/code/DigitalIC/PDE/pdk28_bringup/ndm/tcbn28hpcplusbwp40p140_HVH_t.ndm   # NDM 在
LC_ALL=C ssh EDAServer 'echo ok'               # 远端可达(签核才需要)
```

**1. 仿真回归(~2 min)**:附录 B 命令。判据 8+8 PASS。

**2. DC 综合(~7 min)**:`PDE28_DC_OUTPUT_ROOT=<新目录> PDE28_CLOCK_PERIOD=6.0 flow/dc28/run_dc28.sh`。判据 `RESULT: OK`。

**3. P&R(约 2 h)**:导出 6.0 节的环境变量组(OUTPUT_ROOT 新目录、DC_RESULTS 指向第 2 步 `…/dc/results`、CORE_UTIL=0.70、GDS_MAP=porttext 补丁 map),然后按序:

```text
s01_setup(~1 min)→ s02_floorplan(~5 min)→ s03_place(~15 min)
→ s04_cts(~15 min)→ s05_route(~30 min,未单独记录,按整段预算)
→ s05b_antenna_fix → s06_postroute → s06b_open_fix → s07_finish
```

每步判据 `STAGE_MARKER: OK`;s07 最终判据两行 `PDE28_GATE …` 全零 + 六件产物。**中途失败**:看 `$OUTPUT_ROOT/reports/<stage>.log` 定位 → 修复 → **重跑该 stage 即可**(checkpoint 在设计库里,前面各步不用重来; s01 例外:它拒绝覆盖已存在的设计库,重跑 s01 = 换新 OUTPUT_ROOT)。

**4. 签核传输(~30 min,1 GB 级)**:15 件套(netlist/SPEF×2/SDC/GDS/SDF/NLDM×2/lib spice/三 deck 副本/map/aocvm)scp 到 EDAServer 新建目录,**两端 sha256 逐一核对**后才开跑。

**5. PT(4 个会话)**:附录 B 命令,WC/BC × 基线/AOCV。判据:四类 NVP=0(基线);AOCV 遍 report_aocvm 有标注表,数字如实记录。

**6. Calibre 三项(DRC ~11 min,LVS/ANT 未单独记录)**:runset 用归档副本改两行路径;判据 DRC 分类账 / ANT 109 全零 / `LVS completed. CORRECT`。

**7. 归档 + 报告 + 提交**:结果 scp 回本地 run 树 `signoff/`,写 MANIFEST(sha256/工具版本/deck 版本/生成 commit),报告入 `flow/`,按 AGENTS.md §5 提交。

**全程预算**:实测第二轮 K–O 全程 4.5 h(含两轮 PT、Calibre 三项与全部归档);从零重跑含仿真与 DC,**一个工作日以内**。

---

## 附录 F 环境变量清单

### F.1 PDE28_* / PDE_*(本流程自有)

| 变量 | 作用 | 典型值 | 用在 | 不设会怎样 |
|---|---|---|---|---|
| `PDE28_DC_OUTPUT_ROOT` | DC run 写出根(**必设**) | `…/local_runs/dc28_<tag>` | synth28.tcl / run_dc28.sh | 直接 error;已存在也拒跑 |
| `PDE28_CLOCK_PERIOD` | 综合时钟周期 ns | 6.0 | synth28.tcl | 默认 10.0 |
| `PDE28_NLDM_DIR` / `PDE28_TARGET_DB` / `PDE28_MIN_DB` | NLDM 目录 / setup 库 / hold 库 | PDK 内 ssg/ffg .db | synth28.tcl | 默认指向标准 PDK 路径 |
| `PDE28_DC_RESULTS` | **ICC2 读**哪个 DC results | `<dc_run>/dc/results` | pnr28_common.tcl | 默认 R1 bringup run——新轮必设 |
| `PDE28_ICC2_OUTPUT_ROOT` | P&R run 根 | `…/icc2_28nm_<tag>` | pnr28_common / run_stage.sh | 默认 R1 目录 → s01 拒绝覆盖 |
| `PDE28_CORE_UTIL` | floorplan 利用率 | 0.70 | s02_floorplan.tcl | 默认 0.55 |
| `PDE28_GDS_MAP` | write_gds layer map | porttext 补丁 map | pnr28_common / s07 | 默认 PRTF 原件——端口 text 落错层,LVS 要靠 runset 补丁 |
| `PDE28_REF_NDM` | 参考 NDM | `pdk28_bringup/ndm/…HVH_t.ndm` | pnr28_common | 默认即可 |
| `PDE28_PDK_ROOT` / `PDE28_TLU_DIR` / `PDE28_BRINGUP` | PDK/TLU+/bringup 根 | 标准路径 | pnr28_common | 默认即可 |
| `PDE_REPO_ROOT` / `PDE_TOP` | 仓库根 / 顶层名 | 自动推导 / pde_chip_top_safe | 各脚本 | 默认即可 |
| `PDE_SNPS_ENV` | Synopsys env 脚本 | `~/synopsys/env_synopsys_2024.sh` | run_stage.sh / run_dc28.sh | 默认同值 |
| `PDE28_SIGNOFF_ROOT` | PT 签核树根(**必设**) | EDAServer 工作树 | pt_sta28.tcl(run_pt28.sh 代导出) | error |
| `PDE28_PT_CORNER` | WC 或 BC(**必设**) | WC / BC | 同上 | error |
| `PDE28_PT_AOCV` | =1 跑 AOCV 遍 | 1 | pt_sta28.tcl | 不设 = 无 derate 基线 |
| `PDE28_TF` `PDE28_LEFS` `PDE28_WC_DB` `PDE28_BC_DB` `PDE28_GDS` `PDE28_OUT` | 建库六件套 | 见 6.8 建库卡 | build_ndm_timing.tcl | error/建库不完整 |
| `PDE_SNPS_USE_SYSTEM_UDEV` | =1 旁路 udev mask | 平时不设 | snps_no_udev.sh | 不设 = mask 生效(期望态) |
| `PDE_SNPS_UDEV_MASK_DIR` | mask 目录 | `~/.cache/pde-snps/no-udev` | snps_no_udev.sh | 默认即可 |

### F.2 第三方工具

| 变量 | 作用 | 值(EDAServer) | 备注 |
|---|---|---|---|
| `SYNOPSYS_ENV` | 仿真 Makefile 的工具 env | 本机传 `~/synopsys/env_synopsys_2024.sh` | Makefile 默认是 EDAServer 路径 `/ssd0/synopsys/synopsys_bashrc`,本机**必须显式传** |
| `CALIBRE_HOME` / `MGC_HOME` | Calibre 安装根(两个都设) | `/ssd0/mentor/Calibre2023/aoj_cal_2023.2_16.9` | 2015.2 在 `/ssd0/mentor/Calibre2015/aoi_cal_2015.2_36.27` |
| `MGLS_LICENSE_FILE` | Mentor license | `/ssd0/mentor/license/license.dat` | 缺 → license fail |
| `SNPSLMD_LICENSE_FILE` | PT license(EDAServer) | `@localhost` 且需 `unset LM_LICENSE_FILE` | 默认环境 checkout 失败(recon 勘误实测) |

### F.3 snps_no_udev.sh 用法与适用场景

```bash
flow/local/snps_no_udev.sh <任意 Synopsys 命令及参数>
```

适用:**本机(soleilUbuntu)容器内的一切 Synopsys 工具调用**(icc2_shell / lm_shell / dc_shell / vcs 由各 runner 自动包装)。机理:SCL license checkout 会 dlopen libudev 做硬件清点,在本机段错误(exit 139);包装器向进程的 LD_LIBRARY_PATH 前插一个指向 /dev/null 的假 `libudev.so.1`, dlopen 失败后 SCL 走无 udev 回退路径。只影响被包装进程及其子进程。EDAServer 无此故障,PT 不需要包装。怀疑包装器本身出问题时,设 `PDE_SNPS_USE_SYSTEM_UDEV=1` 做 A/B。

---

*本文档整理自既有报告、日志与 commit 历史,未重跑任何流程;*
*所有数字的权威出处是各章标注的原始报告文件。*
