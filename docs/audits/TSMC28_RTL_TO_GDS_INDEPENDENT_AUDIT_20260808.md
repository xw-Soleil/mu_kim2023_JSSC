# TSMC 28 nm HPC+ RTL-to-GDS 全流程独立技术审查报告

- 审查日期：2026-08-08
- 审查对象：PDE 加速器 TSMC 28 nm HPC+ 数字后端实现
- 条件实现基线：`flow/local_runs/icc2_28nm_r2_20260808/`
- 条件综合基线：`flow/local_runs/dc28_r2_20260807/`
- 签核证据集：`flow/local_runs/icc2_28nm_r2_20260808/signoff/`
- 证据原则：README、worklog、总结和 commit message 仅用于定位断言，不作为技术证据；判定只引用原始工具日志、报告、产物和可核验源代码。
- 操作边界：审查期间未启动任何 EDA 工具，未访问远端执行任务；需要重新运行工具才能回答的问题均标记为“无法验证（需运行工具）”。

判定语义：**证实**表示现有原始证据直接支持断言；**证伪**表示原始证据与断言冲突；**无法验证**表示证据缺失、来源链不能闭合，或必须重新运行工具才能判断。

## 第一部分：流程完整性评估

### 1.1 总体结论

项目已形成一条真实可审计的 **RTL -> DC -> ICC2 -> GDS/DEF/netlist/SPEF -> PrimeTime/Calibre** 流程，不是仅靠文档描述的“纸面流程”。综合、布局布线、寄生导出、独立 STA、Calibre LVS 和 Calibre Antenna 均有原始日志或报告支撑。

但“全流程完成”不能等同于“签核通过”或“可流片”：Calibre DRC 原始 summary 明确产生 **98 个结果**，AOCV 下 BC hold 有 **654** 个违例，WC 下还有 **94** 个 hold 违例；最终 ICC2 仍有 2 个 max-transition 和 5/6 个 max-capacitance 口径的电气约束问题。当前结果应定性为 **完成了较完整的 block-level 后端实现与签核试跑，但未达到 tapeout-ready signoff**。

### 1.2 标准 RTL-to-GDS 环节对照

| 环节 | 状态 | 原始证据 | 对结论的影响 |
|---|---|---|---|
| 行为级模型 | 做了但证据不完整 | `sim/ref/golden_model.py:1-14` 是 Python 位精确模型；`sim/ref/dsm_sweep.py:1-11` 是 Python 扫描脚本 | 能证明模型代码存在，不能证明“MATLAB 仿真完成”；无保留运行日志、输入集和结果清单 |
| RTL 设计 | 已做 | `src/pe/pe_top.sv:107-158` 有双颜色 residue bank、DSM 和共享 ALU；`src/pe_array/pde_tcu.sv:113-131` 有动态精度决策 | 能证明两项优化进入了可综合 RTL |
| RTL 仿真/回归 | 做了 testbench，执行证据不完整 | `tb/tb_pde_top.sv:38-70` 建立动态/固定精度 A/B；`tb/tb_pde_top.sv:158-216` 定义通过条件 | 没有保留 simulator log、seed、波形摘要或回归清单，功能正确性和覆盖率无法独立复核 |
| Lint、CDC/RDC | 未见执行证据 | 28 nm run 中无对应原始报告 | 单时钟降低 CDC 风险，但 reset crossing、lint waiver 和结构规则仍未形成门禁 |
| 逻辑综合 | 已做 | `flow/local_runs/dc28_r2_20260807/reports/dc.local.log:2-14,538`；`.../qor.rpt:13-15,28,50` | DC T-2022.03-SP2 在 6 ns 下完成 compile_ultra，综合面积和网表有证据 |
| 形式等价 | 未做或未留证据 | 28 nm DC/ICC2 证据集中无 Formality/LEC 执行结果 | RTL -> 综合网表、综合网表 -> P&R 网表的功能等价未闭环，是签核缺口 |
| DFT/ATPG | 未做或未留证据 | DC banner 出现 DFT Compiler，但无 scan insertion、dft_drc、ATPG 报告 | 现有 `scan_*` 更像架构读出接口，不能替代制造测试链；影响芯片级可测性结论 |
| Floorplan/PG/tap/boundary | 已做 | `.../s02_floorplan.log:125-204` 插入 878 个 boundary、3073 个 tap；`.../s07_pg_connectivity.rpt:15-35` PG floating 均为 0 | block-level 物理基础完整；但无 pad ring，`.../s07_design.rpt:63-67` 显示 pad/corner pad 为 0 |
| Placement/CTS/routing | 已做 | `.../s07_finish.log:160-173,190-211`；`.../s07_routes.rpt:271,391,396` | ICC2 内部 setup/hold、route DRC、open、short、antenna 门禁值为 0 |
| 电气约束收敛 | 不完整 | `.../s07_constraints.rpt:63,87,97` 总计 7 个约束违例；`.../s07_qor.rpt:170-172` 另以 8 个 nets 计数 | 说明“route clean”不等于所有 design-rule constraints clean |
| GDS/DEF/netlist/SPEF/SDF 导出 | 已做 | `.../s07_finish.log:226-304,322-324`；相应产物存在于 `results/` | 交付物确实由该 ICC2 run 写出 |
| PrimeTime post-route STA | 已做但覆盖/方法需限定 | `.../signoff/pt/pt_WC_base.log:72-105,181-183`；`pt_BC_base.log:72-105,177-179` | 独立工具读取 postroute netlist、SPEF、SDC 并完成；baseline 四类零违例，但不是 AOCV clean |
| Recovery/removal | 已做，非空检查 | `.../signoff/pt/WC_analysis_coverage.rpt:10-18` | 各 16,227 checks 中 16,225 tested/met，2 untested；不是“No paths”式假通过 |
| AOCV | 已做但未收敛 | `.../signoff/pt/BC_aocv_analysis_coverage.rpt:10-18`；`WC_aocv_analysis_coverage.rpt:10-18` | AOCV 确实绑定并改变结果，但暴露 hold 违例，不能声称 variation-aware signoff 通过 |
| SI/crosstalk | 未见独立签核证据 | PT 脚本和保留报告未给出 SI enabled/噪声报告 | 影响高置信度时序与噪声结论 |
| Calibre DRC | 已运行但未通过 | `.../signoff/calibre_drc/DRC.rep:2865-2871` | 2415 checks、98 results；“DRC 签核通过”被证伪 |
| Calibre LVS | 已运行并得到 CORRECT | `.../signoff/calibre_lvs/lvs.rep:25-45,1083-1109` | 端口、net 和主 MOS 实例最终匹配；过滤项需保留方法说明 |
| Calibre Antenna | 已运行并为 0 | `.../signoff/calibre_ant/DRC.rep:189-195` | 109 checks、0 results；这一结论比 ICC2 内部 antenna 更可信 |
| IR drop / EM | 未做或未留证据 | 28 nm 证据集中无 RedHawk/Voltus/PrimeRail/PG EM 报告 | PG connectivity 不能替代 IR/EM；影响供电可靠性和流片结论 |
| 门级仿真/SDF | 产物有，执行证据无 | `.../s07_finish.log:298-301` 写 SDF；无 GLS 日志 | 时序网表行为、X 传播和 reset 时序未在仿真层闭环 |
| 封装/IO/ESD/pad ring | 未做 | `.../s07_design.rpt:63-67` pad/corner pad 均为 0 | 当前是 core/block 版图，不应表述为完整芯片 tapeout 数据库 |

### 1.3 环节衔接与版本来源

DC 到 ICC2 的衔接有直接证据：ICC2 setup 明确读取 `dc28_r2_20260807` 的网表和 SDC（`flow/local_runs/icc2_28nm_r2_20260808/reports/s01_setup.log:41-49,99-108`）。ICC2 final 又在同一 run 中写出 postroute netlist、DEF、两角 SPEF、SDF 和 GDS（`.../s07_finish.log:226-304,322-324`）。这一段 provenance 是清楚的。

PrimeTime 日志显示它从远端 signoff work tree 读取 postroute netlist、SPEF 和同名 SDC（`.../signoff/pt/pt_BC.log:30-41,63-106`），Calibre 报告也记录了同一轮次目录中的 GDS（`.../signoff/calibre_drc/DRC.rep:7-12`、`.../signoff/calibre_ant/DRC.rep:7-12`）。但本地归档没有保留远端 `inputs/` 副本及逐输入 SHA256 manifest，因此不能从当前证据证明远端输入与本地 `results/` **逐字节相同**。结论是：名称、轮次和时间链一致，内容同一性仍为 **无法验证（需在远端对输入与本地产物计算 SHA256）**。

## 第二部分：逐条核对表

| 断言 | 判定 | 证据（文件+行） |
|---|---|---|
| MATLAB 行为级模拟已完成 | **证伪** | 当前所谓 `sim/ref/` 下保留的是 Python：`sim/ref/golden_model.py:1-14`、`sim/ref/dsm_sweep.py:1-11`；无 `.m`、MATLAB 原始日志或结果集 |
| 位精确行为模型存在，并建模红黑顺序和一阶 Delta-Sigma 反馈 | **证实** | `sim/ref/golden_model.py:3-12,21-45` |
| RTL 设计已完成到可综合顶层 | **证实** | DC 成功 elaborate/compile；参数包括 20x20、DSM 和动态精度：`flow/local_runs/dc28_r2_20260807/reports/dc.local.log:216-379,538` |
| 逻辑综合完成 | **证实** | DC 版本与 compile_ultra：`.../dc.local.log:2-14,538`；6 ns、面积 109308.65 um2：`.../qor.rpt:13-15,50` |
| ICC2 P&R 完成并导出 GDS | **证实** | 内部门禁后执行 write_verilog/DEF/SPEF/SDF/GDS，并输出完成标志：`flow/local_runs/icc2_28nm_r2_20260808/reports/s07_finish.log:190-211,226-324` |
| die 约 0.172 mm2 | **证实** | DEF 为 415.08 um x 415.10 um，面积约 0.1723 mm2：`.../results/pde_chip_top_safe.def:15` |
| 工作频率约束为 6 ns | **证实** | `flow/local_runs/dc28_r2_20260807/results/pde_chip_top_safe.sdc:33-35` |
| 最终利用率为 0.70 | **证伪** | 0.70 是 floorplan target：`.../s02_floorplan.log:46,55,61`；放置后为 0.6933：`.../s03_utilization.rpt:7`；最终 report_utilization 为 0.8418：`.../s07_utilization.rpt:7` |
| PrimeTime 独立 STA 的 setup/hold/recovery/removal 为零违例 | **证实** | baseline constraint summary 四类均 MET：`.../signoff/pt/WC_constraint_summary.rpt:22-27`、`BC_constraint_summary.rpt:22-27` |
| PrimeTime 四类检查覆盖完全、没有 untested | **证伪** | 四类共 80,268 checks，80,262 met，6 untested：`.../signoff/pt/WC_untested.rpt:11-18`；原因见 `:24-29` |
| Recovery/removal 实际发生，不是报告空跑 | **证实** | 各 16,227 checks 中 16,225 met、2 untested：`.../signoff/pt/WC_analysis_coverage.rpt:10-18`；recovery 真实 path 示例：`WC_recovery_paths.rpt:16-61` |
| false_path 没有大面积掩盖内部 reset release | **证实** | SDC 只从外部 `rst_n` 起点 false-path：`.../results/pde_chip_top_safe.sdc:40-42`；内部同步释放仍测试 16,225 个 endpoint，仅同步器自身 2 个 async pins 被排除：`.../signoff/pt/WC_untested.rpt:24-29` |
| PrimeTime baseline 是所有约束零违例 | **证伪** | WC 仍有 max-transition 0.37、max-fanout 9347，并提示 max-cap：`.../signoff/pt/WC_constraint_summary.rpt:29-32`；BC 也有 max-fanout：`BC_constraint_summary.rpt:29-32` |
| AOCV 已真正加载并绑定 | **证实** | 脚本开启 AOCVM 并 read_aocvm：`flow/signoff28/pt_sta28.tcl:76-83`；报告显示 140,972/140,972 leaf cells fully annotated：`.../signoff/pt/BC_aocv_aocvm_tables.rpt:13-19` |
| AOCV 下有 654 条 hold 违例 | **证实** | BC：WNS -0.0298 ns、TNS -5.6100 ns、NVP 654：`.../signoff/pt/pt_BC.log:179`；coverage 同样记录 654：`BC_aocv_analysis_coverage.rpt:10-18` |
| AOCV 仅有 654 条 hold 违例 | **证伪** | WC AOCV 还记录 94 个 hold check 违例：`.../signoff/pt/WC_aocv_analysis_coverage.rpt:10-18`；因此 654 只对应 BC 口径 |
| Calibre DRC 已签核通过 | **证伪** | `.../signoff/calibre_drc/DRC.rep:2865-2871` 明确为 2415 checks、98 results；非零规则见 `:470,494,1253-1369,2049-2221` |
| Calibre DRC 确实运行了完整数量级的规则，而非空检查 | **证实** | 日志记录 2415 checks、98 results 并正常完成：`.../signoff/calibre_drc/drc_pde28.log:161605-161613` |
| Calibre DRC deck 执行没有规则求值异常 | **证伪** | summary 记录 INSIDE CELL 参数未找到、STAMP missing connections 和大量 DFM PROPERTY `MIN(...) undefined`：`.../signoff/calibre_drc/DRC.rep:28-56` |
| Calibre LVS 已运行且 top-level CORRECT | **证实** | `.../signoff/calibre_lvs/lvs.rep:25-45`；最终 59 ports、799647 nets、774623 主 MOS 两侧匹配：`:1083-1109` |
| LVS FILTER 把主逻辑器件全部掩盖后才通过 | **证伪** | filter 仅列 pnwdio、boundary/filler/tap：`.../signoff/calibre_lvs/lvs.rep:217-229`；主 MN 774623 对 774623 且 unmatched=0：`:1083-1109` |
| LVS 过滤不需要进一步审查 | **证伪** | 报告仍显示 41437 个 source instances 被过滤、19801 个无 pin nets 被删除、23 个 nets 任意匹配：`.../signoff/calibre_lvs/lvs.rep:1117-1128`；这不推翻 CORRECT，但必须形成 waiver/rationale |
| Calibre Antenna 已运行且为零 | **证实** | 109 checks、0 results，且有真实 GDS geometry 统计：`.../signoff/calibre_ant/DRC.rep:33-77,189-195` |
| ICC2 内部 antenna 对所有网络均完成检查 | **证伪** | 36 个 top-port 网络因 gate area 信息不足被跳过：`.../reports/s07_routes.rpt:181-217`；其余分区检查完成并报告 0：`:222-271,396` |
| ICC2 内部 route/LVS/legality/PG clean | **证实** | route DRC/open/antenna 为 0：`.../s07_routes.rpt:271,391,396`；short/open 为 0：`.../s07_lvs.rpt:27-28`；legality succeeded：`.../s07_legality.rpt:143-146`；PG floating 为 0：`.../s07_pg_connectivity.rpt:15-35` |
| 最终设计所有电气 design-rule constraints clean | **证伪** | 2 max-transition、5 max-cap、总计 7：`.../s07_constraints.rpt:63,87,97`；QoR 另一计数口径为 2 trans、6 cap：`.../s07_qor.rpt:170-172` |
| 签核网表/SPEF/GDS 可证明与本地 ICC2 产物逐字节相同 | **无法验证** | PT/Calibre 报告只保存远端输入路径：`.../signoff/pt/pt_BC.log:30-48`、`.../signoff/calibre_drc/DRC.rep:7-12`；本地没有对应 signoff input manifest/hash。需对远端 inputs 与本地 results 逐项 SHA256 |
| PDK 原件未被修改 | **无法验证** | `.../signoff/aocvm_rebind.diff:1-32` 证明 AOCVM object_spec 被改写；PT 从 signoff work tree `lib/` 读取，支持“工作副本”说法（`pt_BC.log:30-41,124`），但无原件/副本 hash manifest，不能证明原 PDK 未被动过 |
| AOCV 改写有独立补丁且生效 | **证实** | 补丁独立保留：`.../signoff/aocvm_rebind.diff:1-32`；140972 leaf cells fully annotated：`.../signoff/pt/BC_aocv_aocvm_tables.rpt:13-19` |
| 两轮 28 nm 是严格单变量对照 | **证伪** | R1 读取 bringup 网表且 floorplan target 0.55：`.../icc2_28nm_20260807/reports/s01_setup.log:41-49`、`s02_floorplan.log:42-51`；R2 换为 r2 网表、6 ns SDC、target 0.70：`.../icc2_28nm_r2_20260808/reports/s01_setup.log:41-49`、`s02_floorplan.log:46-61` |
| 28 nm 与 65 nm PPA 可以直接归因于工艺 | **证伪** | 65 nm 约束为 10 ns、利用率 0.5728、die 875 um x 875 um：`.../full_clean_20260804/dc/results/pde_chip_top_safe.sdc:34`、`.../final_utilization.rpt:7`、`.../pde_chip_top_safe.def:15`；28 nm 为 6 ns 且 floorplan/最终利用率口径不同 |
| 红黑折叠实际进入 RTL | **证实** | 一个 PE 内有 `r_red_q`、`r_black_q` 两 bank，共享 `u_alu`，按 phase 选择：`src/pe/pe_top.sv:107-158` |
| 自适应精度实际进入 RTL | **证实** | 12/8/4 fit 检测：`src/pe/r_status.sv:33-40`；全阵列精度选择与只缩不扩：`src/pe_array/pde_tcu.sv:113-131` |
| 一阶 Delta-Sigma 误差反馈实际进入 RTL | **证实** | 独立 red/black remainder state 和反馈：`src/pe/r_dsm.sv:30-55`；PE 实例化并回接 ALU：`src/pe/pe_top.sv:150-166` |
| 折叠 vs 不折叠有面积/功耗/吞吐量对照 | **无法验证** | 当前只有 folded 实现；未找到 unfolded 综合/P&R 原始报告。需用同一 RTL 功能、同一 PDK/约束/活动率分别综合实现 |
| 动态精度 vs 固定精度有量化结果 | **无法验证** | testbench 已搭 A/B：`tb/tb_pde_top.sv:38-70,163-175`，但没有保留执行日志或结果表。需运行回归并保留 cycles/updates/error |
| DSM on/off 有量化误差收益 | **无法验证** | 扫描脚本存在：`sim/ref/dsm_sweep.py:3-11,19-39`，但无原始运行输出；需运行并保留输入、版本、输出 |
| 当前门禁为全流程 fail-closed | **证伪** | ICC2 门禁只解析 setup/hold 和 route/open/short/antenna：`.../s07_finish.log:176-220`，未阻止 7 个电气约束问题；PT 脚本输出 summary 后无违例 gate、直接 DONE/exit：`flow/signoff28/pt_sta28.tcl:102-143` |
| 项目列出的 limitation 完整 | **证伪** | 自述只列 Poisson test、multigrid、重配置、双时钟和复位重启：`doc/design_notes_zh.md:368-383`；未覆盖 DRC 98、AOCV hold、DRV、IR/EM、LEC、DFT、GLS、signoff provenance 等当前主要风险 |

## 第三部分：发现的问题（按严重程度排序）

### P0：阻断“签核通过/可流片”结论

1. **Calibre DRC 未通过。** 原始 summary 是 2415 个 rule checks、98 个 results，不是 0（`flow/local_runs/icc2_28nm_r2_20260808/signoff/calibre_drc/DRC.rep:2865-2871`）。其中 2 个是显式 WARNING checks，其余包含 OD/PO/metal density 等结果；在没有逐条 waiver 和 foundry 接受依据时，不能写成 DRC clean。

2. **AOCV hold 未收敛。** BC 为 WNS -0.0298 ns、TNS -5.6100 ns、654 paths（`.../signoff/pt/pt_BC.log:179`）；WC 的 coverage 还列出 94 个 hold violations（`WC_aocv_analysis_coverage.rpt:10-18`）。这不是“已知环境 limitation”，而是当前 variation-aware timing 下的真实设计/实现违例。

3. **签核输入的逐字节 provenance 未闭合。** 本地保留了远端报告，却没有把远端 `inputs/` 的网表、SDC、SPEF、GDS checksum manifest 一并归档。现有证据能证明文件名和轮次一致，不能证明 PrimeTime/Calibre 检查的就是本地当前交付字节。

4. **当前不是完整 chip-level tapeout 数据库。** 最终报告显示 pad cells 和 corner pad cells 均为 0（`.../reports/s07_design.rpt:63-67`）；没有 pad ring、IO/ESD、封装接口与相应 top-level LVS/DRC。应表述为 core/block GDS。

### P1：高严重度方法和签核缺口

5. **【报告显示通过、但检查未完全发生】PT 四类“零违例”仍有 6 个 untested checks。** 两个 setup/hold check 因 constant_disabled，四个 synchronizer recovery/removal check 因 false_paths（`.../signoff/pt/WC_untested.rpt:18-29`）。这六项有可解释的结构原因，且 16,225 个内部 recovery/removal endpoint 确实被检查，所以不是大面积掩盖；但“100% 全覆盖”仍然不成立。

6. **【报告显示通过、但检查未完全发生】ICC2 antenna 跳过 36 个 top-port nets。** `s07_routes.rpt` 明确列出这些网络缺 gate-area 信息并跳过（`:181-217`）。外部 Calibre antenna 的 109 checks/0 results 补强了结论，但 ICC2 的“0 antenna”自身不能单独作为全覆盖证据。

7. **Calibre DRC 不仅非零，还存在规则求值 warning。** INSIDE CELL 参数未定位、STAMP missing connections，以及数万次 `MIN(...) undefined`（`.../calibre_drc/DRC.rep:28-56`）。这些可能属于不适用 DFM 分支，也可能意味着部分检查退化；在 deck/runset 配置审核前不能自动忽略。

8. **缺少 IR/EM、形式等价、DFT/ATPG、门级仿真和 SI/noise 证据。** 对研究原型可作为后续工作；对“全流程签核”则是实质缺项。

9. **AOCV collateral 被改写后虽已绑定，但方法授权不足。** diff 将 `_ccs` library object_spec 改绑到当前库名（`.../signoff/aocvm_rebind.diff:1-32`），工具报告 140,972 个 leaf cells 全绑定。技术上“生效”已证实，但跨 collateral release/model 的等价性和 foundry 认可没有原始依据，论文或流片材料必须披露。

### P2：中严重度质量问题

10. **最终 ICC2 仍有电气约束违例。** `s07_constraints.rpt` 报 2 max-transition、5 max-cap、总计 7；`s07_qor.rpt` 以 nets 口径报 2/6。GDS 门禁没有覆盖这些项。

11. **LVS CORRECT 可信，但 filter/ambiguity 需要正式说明。** 主 MOS 774,623 对 774,623 且 unmatched=0，说明不是“把逻辑器件全滤掉”；然而 41,437 source instances 被过滤、23 nets arbitrarily matched，应该逐项映射到 filler/tap/boundary 和全局电源命名规则，形成可审计 waiver。

12. **最终利用率陈述混淆 target、placement 和 final。** 0.70 是 floorplan target，placement report 为 0.6933，最终利用率为 0.8418。三者都可合理存在，但论文/答辩只能选定一个明确定义的口径。

13. **功耗数字不是签核功耗。** DC power 使用 low-effort zero-delay switching propagation（`flow/local_runs/dc28_r2_20260807/reports/power.rpt:1`），总动态功耗约 13.294 mW（`:1645-1651`），没有真实 workload SAIF/VCD、post-route parasitic power 或 IR/EM 支撑。

### P3：论证与可重复性问题

14. **“MATLAB 完成”与仓库事实不符。** 当前是 Python 模型和 Python sweep；没有 MATLAB 文件和运行记录。可以改称“Python 位精确行为模型已实现”，或补齐真实 MATLAB 基线。

15. **两项优化缺乏完整量化对照。** 源代码足以证明功能机制存在，但没有 unfolded vs folded 的同约束 PPA，也没有保留动态/固定精度、DSM on/off 的原始运行结果。架构存在不等于收益已经论证。

16. **两轮 28 nm 和 65/28 nm 比较未控制变量。** 28 nm R1/R2 同时改变网表、周期和 utilization target；65 nm 又是 10 ns、不同利用率和不同流程成熟度。现有数字只能作为工程迭代记录，不能用于单因素归因。

## 第四部分：方法论评价

### 4.1 严谨的地方

1. **原始产物链条较完整。** DC、ICC2、PT、Calibre 均有真实工具版本、日志和报告，不是只有 README 结论。

2. **reset 问题处理比常见课程项目严谨。** RTL 加入两级异步置位/同步释放结构（`src/pe_array/pde_chip_top_safe.sv:56-68`）；PT 显式开启 recovery/removal 并提供 coverage，能证明检查不是空跑。

3. **AOCV 是否生效有正向判据。** 不只看脚本中的 `read_aocvm`，还保存 `report_aocvm`，证明 140,972 个 leaf cells fully annotated；同时诚实暴露 hold 违例。

4. **ICC2 内部门禁有 fail-closed 的雏形。** setup/hold、route DRC、antenna、open、short 计数解析失败时默认 -1，非零即 error（`.../s07_finish.log:176-220`）。这比只生成报告不判断结果更好。

5. **物理实现细节超出一般 RTL 课程项目。** tap/boundary、PG、CTS、详细布线、SPEF、GDS、外部 LVS/antenna 都被实际推进，并保留了失败和修复过程中的原始证据。

### 4.2 薄弱的地方

1. **门禁范围不完整。** 内部门禁未覆盖 max-transition/max-cap、recovery/removal coverage、AOCV、Calibre DRC/LVS/Antenna、IR/EM；PT runner 也不因负 slack 退出失败。结果是检查失败后仍能出现 DONE marker 和交付物。

2. **约束历史既有收紧也有放宽。** 28 nm bringup 的 10 ns 被 R2 收紧到 6 ns（`.../dc28_bringup_20260807/.../pde_chip_top_safe.sdc:33` 对 `.../dc28_r2_20260807/...:33`）；早期统一 0.2 ns uncertainty 后来拆成 setup 0.2/hold 0.05（`flow/local_runs/dc/results/pde_chip_top_safe.sdc:35` 对 `.../dc28_r2_20260807/...:34-35`），其中 hold uncertainty 是放宽。这个拆分可能符合方法学，但必须作为约束变更披露，不能把前后 hold 改善全归因于实现。

3. **对照实验未锁变量。** R1 -> R2 同时改变周期 10 -> 6 ns、floorplan utilization 0.55 -> 0.70、综合网表和实现结果。die 从约 0.217 mm2 缩到约 0.172 mm2 是真实的，但不能单独归因于某项优化。

4. **release 证据缺少 manifest。** 应把 top、commit SHA、工具版本、corner、输入/输出 SHA256、deck/runset 版本和 waiver 清单放在同一不可变 release manifest 中。当前报告复制自远端，但输入本体和 hash 未归档。

5. **PDK 衍生补丁的治理不够。** AOCVM diff 和 runset diff 被独立保存，这是优点；但没有原件 hash、补丁应用脚本/命令、批准依据和 patched-file hash。`runset_vs_r1.diff:9-18` 还显示删除了 M3/M4/M9 text mapping，必须解释其 LVS 合法性。

6. **行为/RTL 验证证据弱于后端证据。** 有 testbench 和 golden model，但没有可复现 regression result、functional coverage、assertion summary 或 seed list。对一个宣称架构创新的项目，这个证据重心倒置。

### 4.3 学术与工程价值

红黑折叠、自适应精度和一阶 Delta-Sigma 不是只写在文档里：RTL 中确有双 bank 共享计算单元、全阵列残差 fit reduction、4/8/12/16-bit 精度切换，以及独立 red/black remainder feedback。综合日志也显示这些参数在 20x20 实例中启用。因此，“实现了这些机制”是可信的。

但“这些机制带来了多少收益”尚未建立。折叠没有 unfolded baseline；动态精度 A/B 只有 testbench 源码、没有保留结果；DSM sweep 只有脚本、没有原始输出；功耗又是 vectorless DC estimate。当前可发表的内容是 **实现方法和工程经验**，还不是经过严格实验支撑的 PPA/数值精度贡献。

与 JSSC'23 论文比较时，可比项仅限于在明确相同问题规模、边界条件、停止准则和位宽定义下的算法误差、update/cycle 数、PE 数和架构功能。不可直接比较或归因的项包括绝对面积、频率、功耗、能效、利用率和 tapeout signoff 状态，因为工艺、库、V/T corner、时钟约束、物理目标、活动率、IO/pad 范围和版图完成度均不同。论文若比较，应同时给出原始值与归一化值，并把“core-only estimate”和“silicon measurement”分栏。

最可能在投稿或答辩中被追问的三个点是：

1. **签核为何声称通过，而 Calibre DRC 有 98 results、AOCV hold 有 654/94 violations？**
2. **红黑折叠、动态精度和 DSM 的独立收益在哪里，是否有同约束、同 workload、同停止准则的 ablation？**
3. **与 JSSC'23 的 PPA/精度比较是否同口径，为什么没有真实活动率功耗、unfolded baseline 和 post-layout/硅后数据？**

## 第五部分：项目实际水平判定

### 5.1 水平定位

作为研究生阶段的芯片设计项目，当前水平可定为：**较强的研究型数字后端原型，明显高于一般课程作业，但未达到可流片签核或高水平论文实验闭环。**

超出一般预期的部分：

- 不仅完成 RTL 和 DC，还把约 18 万逻辑/物理单元规模的设计推进到 ICC2 GDS、两角 SPEF、独立 PT 和 Calibre；
- 对 reset recovery/removal、AOCV 是否真实绑定、Calibre LVS filter 等容易“假通过”的位置做了较深入处理；
- 两项优化确实落入参数化、可综合 RTL，而不是停留在 MATLAB/框图；
- 原始失败证据被保留，包括 DRC 非零和 AOCV hold 退化，这对工程审查很重要。

不足之处：

- Calibre DRC 和 AOCV hold 仍是明确失败项，不能称 signoff complete；
- 无 IR/EM、LEC、DFT/ATPG、GLS、SI/noise，且没有 pad ring，因此离完整芯片流片还有明显距离；
- 功能验证、数值正确性和架构 ablation 的证据显著不足；
- PPA 比较没有控制变量，最终 utilization 又混用了 target/placement/final 三种口径；
- 远端签核输入与本地交付没有 checksum manifest，release provenance 不完整。

### 5.2 是否够投稿或答辩

**答辩：有条件地够。** 前提是准确表述为“完成 TSMC 28 nm core/block 后端实现及多项签核试跑”，主动披露 DRC 98、AOCV hold、无 pad/IR/EM/LEC 等限制，并把贡献重点放在架构实现、reset/STA 方法和后端工程闭环。若继续声称“PrimeTime/Calibre 全签核、可流片”，则证据不足，且会被原始报告直接反驳。

**投稿：当前不足以支撑以 PPA/芯片实现为核心贡献的高水平期刊或会议。** 可作为设计方法、教育/工程实践或早期架构论文基础；要支撑正式架构论文，至少需要严格 ablation、可复现功能/数值结果、统一比较口径和 clean signoff。要支撑芯片论文，还需要完整 chip top、IR/EM/DFT/ESD/封装与硅后测量。

## 第六部分：改进建议（按性价比排序）

1. **先改口径，不花工具时间。** 将当前状态统一写成：ICC2 internal route/LVS clean；PT baseline 四类零违例但 6 checks untested；Calibre LVS CORRECT、Antenna 0；Calibre DRC 98 results；AOCV BC/WC hold 未收敛。明确区分 floorplan target 0.70、placement 0.6933、final 0.8418。

2. **把所有门禁改成 fail-closed。** ICC2 加入 max-transition/max-cap、legality、PG 和 recovery/removal coverage；PT 对 setup/hold/recovery/removal 的 NVP、untested 白名单和 AOCV NVP 设退出条件；Calibre runner 对 DRC result count、LVS CORRECT、antenna result count 和 runtime warning policy 设硬门禁。任何 gate fail 都不得生成 release marker。

3. **关闭 AOCV hold。** 先以 BC 654 paths 为主目标做 hold ECO，再检查 WC 94 paths；每轮固定 SDC、AOCV table、corner、SPEF 和 utilization，不得通过 uncertainty/false_path 放宽清零。验收应同时看 WNS、TNS、NVP 和 setup 回归。

4. **处理 Calibre DRC 98 results。** 将 98 项分成真实几何/密度错误、block-level 不适用规则、缺 top-level IO/pad 导致项和可正式 waiver 项。修复后使用同一份有版本/hash 的 deck 重跑；对 `MIN(...) undefined` 等 warning 取得 PDK/EDA owner 解释。预期验收是 0 unwaived results，而不是“工具完成”。

5. **建立 release manifest。** 对 DC netlist/SDC、ICC2 NDM、postroute netlist、DEF、WC/BC SPEF、SDF、GDS、PT reports、Calibre reports、deck/runset 和 AOCVM work copy记录 SHA256、工具版本、corner、生成脚本 commit 和 waiver。远端运行前后都计算 hash，证明签核输入就是交付物。

6. **补最关键的三组 ablation。** 同一 commit、同一 6 ns、同一 PDK/corner、同一 workload 下运行：folded vs unfolded；dynamic vs fixed 16-bit；DSM on vs off。至少报告 area、cell count、Fmax/同频 slack、cycles、updates、数值误差和基于同一 SAIF/VCD 的功耗。每组只改一个变量。

7. **把现有 testbench 变成可审计回归。** 保存 simulator/version、命令、seed、测试矩阵、PASS/FAIL、cycles/updates/error CSV 和 golden-model hash；覆盖 Poisson initial condition、负数舍入、精度边界、DSM remainder、reset release 和 back-to-back transaction。

8. **补低成本高价值签核。** 先做 RTL-to-DC 和 DC-to-postroute formal equivalence，再做带 SDF 的最小门级 smoke regression。两者通常比 IR/EM 成本低，却能显著增强“后端没有改坏功能”的可信度。

9. **再补 chip-level 项。** 若目标真是流片，增加 pad ring/IO/ESD、DFT/scan/ATPG、post-route SI/noise、vector-based power、IR drop/EM、完整 top-level DRC/LVS/Antenna 和封装约束。若目标只是论文 block prototype，应明确排除这些范围，避免过度声称。

10. **重做论文对比表。** 每个数字标注工艺、V/T、corner、时钟、core/chip 范围、是否 post-layout、是否 measured、活动率来源和停止准则；跨 65/28 nm 只作带归一化和限制说明的辅助比较，不把差值直接归因于架构优化。

最终结论：**该项目已经完成了一次有真实工具证据的 28 nm block-level RTL-to-GDS 实现，并完成 PT、LVS、Antenna 和 AOCV 的实质性检查；但 Calibre DRC 非零、AOCV hold 未收敛、关键签核环节和实验对照仍缺失，因此不能认定为“全签核完成”或“可流片”。作为研究生工程项目水平较强；作为投稿中的芯片实现证据，仍需补齐签核闭环和量化 ablation。**
