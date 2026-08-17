# R3 整芯片轮审计委托与证据地图(2026-08-15)

给独立审计 agent 的入口文档。按仓库 AGENTS.md §6 的证据原则:本文与所有 `*_2026-08-*.md` 记录都是**叙述**,不得作为技术证据;判定只能引用原始日志、报告、数据库与产物。本文的作用是把每条声明指到原始证据的存放位置,并主动披露已知薄弱点。

## 1. 审计范围与基线

- 时段与范围:2026-08-14 至 08-15,阶段 D(ICC2 整芯片 P&R)+ 阶段 E(EDAServer 独立签核)+ 配套文档。此前的 R1/R2 已有独立审计(本目录另两份报告),不在本次范围。
- 实现基线(运行目录,未跟踪):`flow/local_runs/icc2_28nm_chip_20260815c/`(work/ 设计库、reports/ 各级日志与报告、results/ 交付六件套、signoff/ 签核镜像)。前身失败运行 a/b 与语法试探 `flow/local_runs/icc2_28nm_synprobe_20260814/`(probe1-25)保留供追溯。
- 综合输入基线:`flow/local_runs/dc28_pads_20260814/results/pde_chip_pads.{v,sdc}`。
- 库侧(仓库外,本机):`~/code/DigitalIC/PDE/pdk28_bringup/`——ndm/(tphn28hpcpgv18.ndm、tpbn28v.ndm、核库)、lef/tpbn28v_pad50gu.lef(手写最小 LEF,vendor 衍生物,永不入库)、scripts/(build_ndm_*.tcl 编库配方)、logs/。
- 远端权威签核树:`EDAServer:/home/sxw/PDE/pde28_signoff/20260815_chip/`(ssh 别名见 ~/.ssh/config;inputs/ lib/ pt/ calibre/{drc,drc_ipx,wb,lvs,lvs_txt,lvs_box,ant,以及诊断性 drc_*} bin/ logs/)。两个旧树 20260807、20260808_r2 属 R1/R2,只读、勿动。
- 本地签核镜像:`flow/local_runs/icc2_28nm_chip_20260815c/signoff/`——MANIFEST.md(传输双端 sha256 与运行清单)、derived_inputs.sha256(派生 GDS 哈希)、calibre/(runset diff 与回传报告)、pt/(两角全套报告与日志)。

## 2. 本轮仓库改动(commit 清单)

- `043bb3e` flow/icc2_28nm 整芯片阶段(pnr28_common/s01/s02_floorplan_chip/s06b/s07,529 行)
- `334f68a` flow/FULLCHIP_28NM_2026-08-15.md + IO_SURVEY 收口
- `6bbf46a` flow/signoff28/pt_sta28.tcl 参数化(PDE_TOP、IO 库、黑盒断言、时钟 ideal 释放修复)
- `b731e0a` flow/SIGNOFF_CHIP_28NM_2026-08-15.md(签核记录)
- `e654256` docs/flow_primer_zh.md(流程导读)
- `2632541` flow/R3_FULLCHIP_2026-08-15.md + README 状态节;本地 tag `fullchip28-signoff`

## 3. 声明→证据映射

| 声明 | 原始证据位置 |
|---|---|
| ICC2 六硬门全零(setup/hold/DRC/antenna/开路/短路),die 685×685,util 0.7806 | `…20260815c/reports/s07_finish.log` 的 `PDE28_GATE`/`PDE28_PNR_DONE` 行;s07_qor/s07_routes/s07_lvs 等 .rpt;DEF 的 DIEAREA |
| GDS 含 21 bond pad 且端口 text 在 37;20 | `results/pde_chip_pads.gds` 本体(可用 KLayout 复核);s07 日志 write_gds 段(GDS-045 丢层警告 11 条也在此) |
| PT 两角全零、24,016 端点覆盖、pad 弧入网 | `signoff/pt/pt_{WC,BC}.log` 的 `PDE28_PT_SUMMARY`/`PDE28_PT_DONE` 行;`signoff/pt/reports/`(annotation/coverage/untested/constraint/paths);远端 pt/ 同源 |
| Calibre ANT 0 | `signoff/calibre/ant/ANT.rep`(TOTAL 行);远端 calibre/ant/ 含逐规则 .rep |
| 逻辑 DRC 首跑 766,315 → IP 排除后 1,031 | `signoff/calibre/drc/DRC_fullchip_raw.rep` 与 `signoff/calibre/drc_ipx/DRC_ipx.rep` 的 RULECHECK 行(可重新聚合复算);deck 副本 `signoff/calibre/drc_ipx/deck_ipx.svrf`(EXCLUDE CELL 16 条);对 20260807 基线的全部 runset 改动:`signoff/calibre/runset_vs_20260807.diff` |
| DRC 洪水根因(vendor dt0 NOUSE 编码被流出归一化点亮;bond/IO 两套 via 阵列交错) | 远端诊断运行目录 calibre/drc_padonly、drc_padchip、drc_iocell、drc_bp_frames、drc_b*、drc_nobp 各自的 deck 与 DRC.rep;vendor GDS 原件(层表可自行用 KLayout 复核 dt):IO=`~/pdk/tsmc28hpcplus/IO/tphn28hpcpgv18_170a/TSMCHOME/digital/Back_End/gds/tphn28hpcpgv18_110a/mt_2/9lm/tphn28hpcpgv18.gds`,bond=`…/tpbn28v_140b/…/cup/9m/9M_4X2Y2R/tpbn28v.gds` |
| CN28_WIRE_BOND 装配 deck 全零 | `signoff/calibre/wb/WB.rep` + 工作副本 `wb_pde28.svrf`(开关差异对 iPDK 原件 `~/pdk/tsmc28hpcplus/iPDK_CLN28HPCplus_2p2a/1P9M_4X2Y2R/CN28_WIRE_BOND_9M_4X2Y2R.15a` 可 diff) |
| LVS:158 万 MOS 全配、9 端口全对、PG 域残差具名 | `signoff/calibre/lvs/lvs_v1_full.rep`(全器件首跑)、`lvs_txt_named.rep`(PG text 命名版,主证据)、`lvs_box.rep`(黑盒对照)、`deck_lvs_box.svrf`、`v2lvs.log`;远端 lvs*/ 目录含 svdb(可用 calibre -query 复查网络组成) |
| 传输完整性 | `signoff/MANIFEST.md` §1-§2 逐文件 sha256(双端已核对);派生物哈希 `signoff/derived_inputs.sha256` |

## 4. 主动披露的薄弱点(建议审计优先覆盖)

1. LVS 终判 INCORRECT 如实保留;"零未解释项"依赖的归因链(11 个丢层→pad 内部岛 761 连接;PVSS3 切段→总线弧)值得独立复核,尤其丢层影响面只在 LVS 域评估过,未做逐层内容审计。
2. 诊断过程有两次对照实验因对照物内容丢失而作废(KLayout delete_cell_rec 连带删除、clip 变体伪影),已在 SIGNOFF_CHIP §7 与 MANIFEST §4 披露;有效结论均来自复跑,但审计应确认作废实验未混入证据链。
3. 派生 GDS(chip_nobp、lvstext2)声称"只删 bond pad 实例/只加 7 条标注 text、掩膜层零改动"——可用 KLayout XOR 对原 GDS 独立验证。
4. 逻辑 DRC 残余中 PO.R.19(30 条)的"标准单元内部"归类只抽样定位了 3 条;密度族豁免依赖教师"不做 fill"的裁定,属方向性决策而非技术证明。
5. PVSS3/PVSS2 的 ESD 供电覆盖结论基于 .spi 引脚表推理与 TSMC 命名惯例,无 databook 佐证(交付包内无文档)。
6. PT 黑盒了 21 只 PAD50GU(纯物理件,无时序模型),该处理的正当性可复核 pt 日志 LNK-043 清单。

## 5. 建议核查程序

1. 依 AGENTS §6:绕过一切 .md 叙述,直接打开 §3 表中的 .rep/.log/GDS 复算关键数字(RULECHECK 行聚合、PDE28_GATE 行、PT SUMMARY 行)。
2. 抽验哈希:对 MANIFEST 所列文件本地重算 sha256;远端可经 `ssh EDAServer` 只读复算。
3. 版图类声明用 KLayout 独立复核(层表、bond pad 位置、text 层、派生物 XOR)。
4. 写入边界:审计只新增报告(建议放本目录),不动运行目录、远端树与 pdk28_bringup;两个旧远端树是 R1/R2 审计基线,严禁改动。
5. 工具环境速查(容器、license、路径):`local_artifacts/TOOLCHAIN.md`(未跟踪,仅本机)。
