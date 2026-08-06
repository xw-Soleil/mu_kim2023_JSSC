# BASELINE_MANIFEST — full_clean_20260804（条件基线冻结记录）

- 冻结日期：2026-08-06（soleilUbuntu 本机执行,只读采集）
- 基线根：`flow/local_runs/full_clean_20260804/`（下文相对路径均以此为根）
- 仓库 HEAD（冻结时刻）：`f86c4cf chore: keep Claude instruction bridge minimal`
- 性质声明：本文件把**当前磁盘上的字节**记录在案,使后续任何改动可被发现。
  它**不构成**正式 release 认证——2026-08-05 独立审查确认的"无 immutable
  release manifest"缺口由本文件部分弥补,但流片签核不通过的结论不变。
- 所有哈希均为 `sha256sum` 原始输出;时间为文件 mtime（CST）。

## 1. 交付物哈希

| sha256 | 大小(B) | mtime | 路径 |
|---|---:|---|---|
| `fbd491f3946ce4cbaadd065894937d9206ff24884bc74cc6eab8a7d23b710720` | 129,272,622 | 08-04 16:53:19 | `icc2/results/icc2/pde_chip_top_safe.gds`（ICC2 原始流出,10000 dbu/µm = 0.1 nm 格点） |
| `752ca81f5d5dab5d738dcd7825d19f4e67fd59b71203c587803acee11fa52bf0` | 121,962,194 | 08-04 16:54:00 | `icc2/results/icc2/pde_chip_top_safe.clean_20260804.dbu1000.gds`（1000 dbu/µm = 1 nm;来源见 §4） |
| `e84c48335f21e327633410b212bb996b29e9a246d85df60bb168040e0ab5053c` | 133,426,296 | 08-04 16:53:12 | `icc2/results/icc2/pde_chip_top_safe.def` |
| `722e0329456fb60f2a1d26d6ce1a0aa5be5a8455f574fe0f675f6afe098d06dc` | 34,167,241 | 08-04 16:53:09 | `icc2/results/icc2/pde_chip_top_safe.postroute.v` |
| `82de584c000aa134999ee2c56b74b2545c69a2d1fa4038ad1e2a903cd8ebb518` | 279,637,133 | 08-04 16:53:15 | `icc2/results/icc2/pde_chip_top_safe.WC.spef.RC_WORST_125.spef` |
| `3499f988676f05e5e7d563ca7103ec7f929f3c6cf0a2616654e20b27297ccbf3` | 281,987,265 | 08-04 16:53:18 | `icc2/results/icc2/pde_chip_top_safe.BC.spef.RC_BEST_0.spef` |
| `9465038f4c53416e996aebb908d87edd06a5c0065901b513bdbbc658689e8e5c` | 204 | 08-04 16:53:12 | `icc2/results/icc2/pde_chip_top_safe.WC.spef.spef_scenario` |
| `18b97e9fa82957090d74013401bfc80e2d52db96e4eb759ba0f62a5508333f53` | 603 | 08-04 16:53:15 | `icc2/results/icc2/pde_chip_top_safe.BC.spef.spef_scenario` |
| `3a6466deeeb475a52e3c535b98162f2351084e010b8288d71199190100792be6` | 9,312 | 08-04 15:42:02 | `dc/results/pde_chip_top_safe.sdc` |
| `0b2ee4fa9eacd5015d83cfb7f5da8fac5806b53e09b0aec0b1ac257283632daa` | 11,594,246 | 08-04 15:42:02 | `dc/results/pde_chip_top_safe.v`（DC 网表,P&R 输入） |
| `6370b6b5aaf5b0b8a43f017dd2cf3c4f3dcd5a16971f6ff23aec4f81c38e70ae` | 48,273,851 | 08-04 16:51:22 | `icc2/work/icc2/pde_chip_top_safe.dlib/pde_chip_top_safe/design.ndm`（最终数据库,由 clean_r3 的 save_lib 写出） |

GDS 单位由 GDS 头部 UNITS 记录直接解析（python 读二进制,非叙述）：
`pde_chip_top_safe.gds` user_unit=0.0001, 1e-10 m/dbu → **10000 dbu/µm**;
`...dbu1000.gds` user_unit=0.001, 1e-9 m/dbu → **1000 dbu/µm**。

## 2. 权威报告集判定（两套 final report 的关系）

- **`icc2/reports/icc2/final/`（嵌套,17 个文件,mtime 16:52:31 前后）是权威集**。
- `icc2/reports/icc2/final_*.rpt`（扁平,13 个文件,mtime 16:39:16–16:40:00）
  是**过期集**,不要引用。

证据链（全部来自文件 mtime 与日志原文）：

1. 16:39–16:40 扁平 `final_*.rpt` 由主 P&R 会话自身的报告尾巴写出
   （`pnr.local.log` 337–416 行有对应 `redirect -file [file join $REPORT_DIR final_*.rpt]`
   命令,该 log 的 mtime 16:40:15,末行 `PDE_ICC2_DONE`）。
2. 之后又跑了三轮清理：closure1（16:42–16:43,`clean_r1.launcher.log`）、
   closure2(16:45–16:47)、clean_r3(16:50–16:51,`clean_r3.launcher.log` 末行
   `PDE_CLEAN_R3_DONE` + `save_lib` → design.ndm mtime 16:51:22)。
   即扁平报告集描述的是 clean_r1/r3 修复**之前**的数据库。
3. 最终写出会话 16:52:07–16:53:20（`writeout.launcher.log`:
   `=== eco10 stage3 尝试 1/25 开始 ... 04:52:07 PM` … `RESULT: OK`）执行
   `flow/local/eco10_stage3_writeout.tcl`,其 report_dir 来自环境变量:
   `set report_dir [require_env PDE_ECO10_REPORT_DIR]`（final.console.log 第 49 行）。
4. 该环境变量的值由启动脚本 `flow/local/run_clean_writeout.sh` 设定:
   `export PDE_ECO10_REPORT_DIR=${PDE_ECO10_REPORT_DIR:-$ECO10_ROOT/reports/icc2/final}`,
   其中 `ECO10_ROOT=$PDE_REPO_ROOT/flow/local_runs/full_clean_20260804/icc2`。
   → **report_dir 解析到嵌套 `reports/icc2/final/`**。嵌套集文件 mtime
   （16:52:31±）落在该会话窗口内,交付物（GDS/DEF/netlist/SPEF,16:53:09–19）
   同会话写出,与 `PDE_ECO10_S3_DONE` 行的绝对路径一致。

嵌套权威集 17 个文件的逐一 sha256：

```
adb86d2aa710aecfbeeb422ddbf314f93d008f74392beccab52fd2b7eed355d2  final_clock_qor.rpt
81083bb432c93284d91ae3753f95eebe7408342dea0f6962502870033b67b4b1  final_congestion.rpt
3101f5281b8d410941cba034a78bdb21f202c02c66ae9a2ff9bbb0de8413daee  final_constraints.rpt
94c34b678ff51b429bdf54529454fe3f75f62581e88059c6f29eb459db2da65e  final_design.rpt
0745b26bc5ce53e5ffb33bfaefae047bd0a7be52d1ef2a27c88a5e88a8dc843f  final_hold_timing.rpt
3e56a224823c86625fe4675b89be415333f4277fe5fb915e9f38ea0cf58b8bb1  final_hold_violations_4d.rpt
8ca2617c27b6cd7e7831eab65cd2a44c61ed5cd74507ed0c1fe6f7a69640879e  final_hold_worst_4d.rpt
5ad1bae9c5b9b09b7e45ccfdfd5d798e0e9bc1cc85ae1c0d045a5876254f88b8  final_legality.rpt
9acb0869c1cce62cff89f20295276065ea9bdc504d51ed07680f66757c9abbb3  final_lvs.rpt
cc9734cadf21135c3730dc581a39339c992f40d14a06e12d2b8d54a8d50235fe  final_pg_connectivity.rpt
f393ca161ef73d09cae4ef7215952a01047cc9d140b168b6caa474864c88fb47  final_power.rpt
73066277298ee682fffc820a9a0a957664a8681b00d443d1c93af9ec61904d95  final_qor.rpt
24526082ee72377273df1b24e37fb2be69941cc1b3fc38fc34f81bea8c024e66  final_routes.rpt
9945e0ecdc21cdf34697011aad04133cdeccd4845c57fde039ac52929ff76008  final_setup_timing.rpt
e57104958a2abffb38602078518ac73d4752e8212f253161dddb4a420351c00f  final_setup_violations_4d.rpt
22d08a50fb39249f69ef845a9f7795004961beb29f9cb003657f362f351a9854  final_setup_worst_4d.rpt
657c418243a89c82731c799c0543d53eb406425db810e8a25435eb075e74147e  final_utilization.rpt
```


## 3. 生成命令与时间线（原始日志出处）

| 时间(08-04) | 事件 | 证据文件 |
|---|---|---|
| 15:42 | DC 综合写出网表/SDC | `dc/results/*`（mtime）,`dc/reports/dc.local.log` |
| ~16:12–16:40 | 主 P&R（1654 s,峰值 4848 MB）+ 扁平报告尾巴 | `icc2/reports/icc2/pnr.local.log` |
| 16:42–16:47 | closure1 / closure2 清理轮 | `clean_r1.launcher.log`,`closure1/`,`closure2/` |
| 16:50–16:51 | clean_r3（末网修复 + save_lib → design.ndm） | `clean_r3.launcher.log` |
| 16:52–16:53 | `run_clean_writeout.sh` → `eco10_stage3_writeout.tcl`:嵌套 final 报告 + GDS/DEF/netlist/SPEF | `writeout.launcher.log`,`final.console.log` |
| 16:54:00 | `...dbu1000.gds` 出现 | 仅 mtime;无执行日志（见 §4） |

## 4. `pde_chip_top_safe.clean_20260804.dbu1000.gds` 的来源

**结论:来源不明（无原始执行日志）。**

- 搜索过:整个 run 目录、`flow/local/`、`local_artifacts/`、`doc/`
  （`grep -rln "dbu1000"`,命中仅 `doc/worklogs/CLAUDE_UBUNTU_WORKLOG_2026-08-04.md`
  与 `doc/audits/ICC2_RVT_INDEPENDENT_AUDIT_20260805.md`,两者均为叙述,不是执行日志）;
  `~/.bash_history`、`~/.zsh_history`（`grep "dbu1000\|rescale_gds\|klayout"`,
  仅 2025-12 的两条无关 klayout 记录）。
- 可核实的旁证（非证明）:文件 mtime 16:54:00 晚于 ICC2 写出 41 秒;UNITS 实测
  1000 dbu/µm,与原始 GDS 10000 dbu/µm 呈 10:1,符合 `flow/local/rescale_gds.py`
  （KLayout,`klayout -b -r rescale_gds.py -rd inp=... -rd outp=...`）的功能描述与
  HOWTO 3.7 流程,但**没有该命令的 stdout/日志留存**。

## 5. 复核命令（任何人可重跑）

```bash
cd /home/soleil/code/DigitalIC/PDE/pdeMujunjie/flow/local_runs/full_clean_20260804
sha256sum icc2/results/icc2/* dc/results/pde_chip_top_safe.{v,sdc} \
  icc2/work/icc2/pde_chip_top_safe.dlib/pde_chip_top_safe/design.ndm
sha256sum icc2/reports/icc2/final/*.rpt
```
与本文件不一致 = 基线被改动。
