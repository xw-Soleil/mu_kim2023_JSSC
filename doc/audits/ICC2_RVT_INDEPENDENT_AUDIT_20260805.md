# TSMC 65 nm RVT / Synopsys ICC2 数字后端独立审查报告

- 审查日期：2026-08-05（Asia/Shanghai）
- 本地项目：/home/soleil/code/DigitalIC/PDE/pdeMujunjie
- 条件审查基线：flow/local_runs/full_clean_20260804
- 最终报告集：flow/local_runs/full_clean_20260804/icc2/reports/icc2/final
- 最终数据库：flow/local_runs/full_clean_20260804/icc2/work/icc2/pde_chip_top_safe.dlib/pde_chip_top_safe/design.ndm
- ICC2 复核目录：/tmp/icc2_audit_1785936929
- 证据原则：README、worklog、总结文档未作为技术证据；判定只引用原始日志、报告、数据库和产物。
- 写入边界：设计、脚本、日志、报告和数据库均未改动；按委托要求仅新增本报告。

判定语义：**证实**表示核查项的正向条件有原始证据；**证伪**表示断言与原始证据冲突；**无法验证**表示可访问证据不能唯一回答。对“曾运行但产物后来被删除”一类不可证伪历史，不以“没找到”冒充“从未发生”。

## 第一部分：权威版本认定

### Z1　15 个 run 中的最终交付版本

**结论：正式“权威版本”无法验证；后续审查有条件地以 full_clean_20260804 为唯一基线。**

没有找到不可变 release manifest、current/final 符号链接或带签名/校验和的交付清单，因此目录名不能证明权威性。选择 full_clean_20260804 作为条件基线的依据是：它比 eco10 更新、保留的交付物最完整、其 PNR 日志证明从该 run 自己的 DC 网表和 SDC 新建 ICC2 design，而且 16:52–16:53 的 final.console 明确生成了嵌套 final 报告和原始 GDS/DEF/netlist/SPEF。

完整命令：

~~~bash
find flow/local_runs -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort
~~~

原始输出：

~~~text
antenna_tech_lef_probe_20260803
antenna_tech_lef_probe_overwrite_20260803
dc
full_clean_20260804
icc2_20260803_full
icc2_signoff_eco01
icc2_signoff_eco02
icc2_signoff_eco03
icc2_signoff_eco04
icc2_signoff_eco05
icc2_signoff_eco06
icc2_signoff_eco07
icc2_signoff_eco08
icc2_signoff_eco09
icc2_signoff_eco10
~~~

完整命令：

~~~bash
for d in flow/local_runs/*; do [ -d "$d" ] || continue; n=$(basename "$d"); g=$(find "$d" -type f -name '*.gds' | wc -l); f=$(find "$d" -type f -name '*.def' | wc -l); v=$(find "$d" -type f -name '*.postroute.v' | wc -l); s=$(find "$d" -type f -name '*.spef' | wc -l); m=$(find "$d" -type f -name design.ndm | wc -l); r=$(find "$d" -type f -path '*/reports/icc2/final/*' | wc -l); printf '%-42s GDS=%s DEF=%s POSTROUTE_V=%s SPEF=%s DESIGN_NDM=%s FINAL_REPORTS=%s\n' "$n" "$g" "$f" "$v" "$s" "$m" "$r"; done
~~~

原始输出片段：

~~~text
full_clean_20260804                        GDS=2 DEF=1 POSTROUTE_V=1 SPEF=2 DESIGN_NDM=1 FINAL_REPORTS=17
icc2_20260803_full                         GDS=2 DEF=1 POSTROUTE_V=1 SPEF=2 DESIGN_NDM=1 FINAL_REPORTS=0
icc2_signoff_eco04                         GDS=0 DEF=0 POSTROUTE_V=0 SPEF=0 DESIGN_NDM=1 FINAL_REPORTS=0
icc2_signoff_eco05                         GDS=0 DEF=0 POSTROUTE_V=0 SPEF=0 DESIGN_NDM=1 FINAL_REPORTS=0
icc2_signoff_eco06                         GDS=0 DEF=0 POSTROUTE_V=0 SPEF=0 DESIGN_NDM=1 FINAL_REPORTS=0
icc2_signoff_eco07                         GDS=0 DEF=0 POSTROUTE_V=0 SPEF=0 DESIGN_NDM=1 FINAL_REPORTS=0
icc2_signoff_eco08                         GDS=0 DEF=0 POSTROUTE_V=0 SPEF=0 DESIGN_NDM=1 FINAL_REPORTS=0
icc2_signoff_eco09                         GDS=0 DEF=0 POSTROUTE_V=0 SPEF=0 DESIGN_NDM=1 FINAL_REPORTS=0
icc2_signoff_eco10                         GDS=2 DEF=1 POSTROUTE_V=1 SPEF=2 DESIGN_NDM=1 FINAL_REPORTS=17
~~~

时间戳和体量只作为辅助证据，不单独作为权威证明。完整命令：

~~~bash
find flow/local_runs -mindepth 1 -maxdepth 1 -type d -printf '%TY-%Tm-%Td %TH:%TM:%TS %f\n' | sort
du -sh flow/local_runs/* | sort -h
find flow/local_runs/full_clean_20260804/icc2/results/icc2 -maxdepth 1 -type f -printf '%TY-%Tm-%Td %TH:%TM:%TS %s %p\n' | sort
~~~

原始输出片段：

~~~text
2026-08-03 14:53:40.8510049120 icc2_20260803_full
2026-08-04 15:21:01.8161105840 icc2_signoff_eco10
2026-08-04 15:42:06.7192500230 full_clean_20260804

1.1G    flow/local_runs/icc2_20260803_full
1.1G    flow/local_runs/icc2_signoff_eco10
1.3G    flow/local_runs/full_clean_20260804

2026-08-04 16:53:09.0572834090 34167241 flow/local_runs/full_clean_20260804/icc2/results/icc2/pde_chip_top_safe.postroute.v
2026-08-04 16:53:12.5243628920 133426296 flow/local_runs/full_clean_20260804/icc2/results/icc2/pde_chip_top_safe.def
2026-08-04 16:53:15.3714281080 279637133 flow/local_runs/full_clean_20260804/icc2/results/icc2/pde_chip_top_safe.WC.spef.RC_WORST_125.spef
2026-08-04 16:53:18.2154932060 281987265 flow/local_runs/full_clean_20260804/icc2/results/icc2/pde_chip_top_safe.BC.spef.RC_BEST_0.spef
2026-08-04 16:53:19.6945270410 129272622 flow/local_runs/full_clean_20260804/icc2/results/icc2/pde_chip_top_safe.gds
2026-08-04 16:54:00.8314630230 121962194 flow/local_runs/full_clean_20260804/icc2/results/icc2/pde_chip_top_safe.clean_20260804.dbu1000.gds
~~~

没有 formal final/current 指针或 release manifest。完整命令：

~~~bash
find flow/local_runs -type l -printf '%p -> %l\n'
find flow/local_runs -type f \( -iname '*release*manifest*' -o -iname '*delivery*manifest*' -o -iname '*final*manifest*' \) -printf '%p\n'
~~~

原始输出：

~~~text
[无输出]
~~~

完整命令：

~~~bash
rg -n -C 3 'Reading Verilog into new design|PDE_ICC2_DONE' flow/local_runs/full_clean_20260804/icc2/reports/icc2/pnr.local.log
~~~

原始输出：

~~~text
465-PDE_ICC2: netlist=/home/soleil/code/DigitalIC/PDE/pdeMujunjie/flow/local_runs/full_clean_20260804/dc/results/pde_chip_top_safe.v
466-PDE_ICC2: sdc=/home/soleil/code/DigitalIC/PDE/pdeMujunjie/flow/local_runs/full_clean_20260804/dc/results/pde_chip_top_safe.sdc
467-PDE_ICC2: ref_ndm=/home/soleil/code/DigitalIC/PDE/pdeMujunjie/flow/work/icc2/ref_rebuilt/tcbn65lp_6lmT1.ndm
468:Information: Reading Verilog into new design 'pde_chip_top_safe' in library 'pde_chip_top_safe.dlib'. (VR-012)
469-Loading verilog file '/home/soleil/code/DigitalIC/PDE/pdeMujunjie/flow/local_runs/full_clean_20260804/dc/results/pde_chip_top_safe.v'
470-Number of modules read: 1606
471-Top level ports: 57
--
14037:PDE_ICC2_DONE gds=/home/soleil/code/DigitalIC/PDE/pdeMujunjie/flow/local_runs/full_clean_20260804/icc2/results/icc2/pde_chip_top_safe.gds def=/home/soleil/code/DigitalIC/PDE/pdeMujunjie/flow/local_runs/full_clean_20260804/icc2/results/icc2/pde_chip_top_safe.def netlist=/home/soleil/code/DigitalIC/PDE/pdeMujunjie/flow/local_runs/full_clean_20260804/icc2/results/icc2/pde_chip_top_safe.postroute.v
~~~

三个完整 run 的同名交付物不是同一版本。完整命令：

~~~bash
find flow/local_runs/icc2_20260803_full/results/icc2 flow/local_runs/icc2_signoff_eco10/results/icc2 flow/local_runs/full_clean_20260804/icc2/results/icc2 -maxdepth 1 -type f \( -name 'pde_chip_top_safe.gds' -o -name 'pde_chip_top_safe.def' -o -name 'pde_chip_top_safe.postroute.v' \) -print0 | sort -z | xargs -0 sha256sum
~~~

原始输出：

~~~text
e84c48335f21e327633410b212bb996b29e9a246d85df60bb168040e0ab5053c  flow/local_runs/full_clean_20260804/icc2/results/icc2/pde_chip_top_safe.def
fbd491f3946ce4cbaadd065894937d9206ff24884bc74cc6eab8a7d23b710720  flow/local_runs/full_clean_20260804/icc2/results/icc2/pde_chip_top_safe.gds
722e0329456fb60f2a1d26d6ce1a0aa5be5a8455f574fe0f675f6afe098d06dc  flow/local_runs/full_clean_20260804/icc2/results/icc2/pde_chip_top_safe.postroute.v
7f60eac2917e61b579f7c2c98dcaecda6acbc3afe0f03b6e1828c5288a2d4591  flow/local_runs/icc2_20260803_full/results/icc2/pde_chip_top_safe.def
1396cdbbee9f3a14b3dc532b48182adc40ce24de7377a03b3bcc56042b82fd4b  flow/local_runs/icc2_20260803_full/results/icc2/pde_chip_top_safe.gds
e235549db412d7f032e9e78df0ba3adc395a2998a205a5a7ddfaf98e00ef781f  flow/local_runs/icc2_20260803_full/results/icc2/pde_chip_top_safe.postroute.v
55fab98f102f1503f0aa0a4a00f6c27a354cea19e36fcc29ee5e413cf53ab35d  flow/local_runs/icc2_signoff_eco10/results/icc2/pde_chip_top_safe.def
3ee39eef6c81437ff96ab823614fee8d72fcd97dd14844e9e396be6fc55b1e22  flow/local_runs/icc2_signoff_eco10/results/icc2/pde_chip_top_safe.gds
0f93c2d964550c70d0e11af40d10107f9df12d8bcba51afc905059dcb49dcea2  flow/local_runs/icc2_signoff_eco10/results/icc2/pde_chip_top_safe.postroute.v
~~~

同一 full_clean run 内还有两套同名 final 报告。根目录报告是 16:39，嵌套 final 报告是 16:52–16:53，且哈希不同。final.console 将 report_dir 明确解析到嵌套目录，所以本审查只使用嵌套集合。

完整命令：

~~~bash
rg -n -C 2 'set report_dir|open_lib' flow/local_runs/full_clean_20260804/icc2/reports/icc2/final.console.log
sha256sum flow/local_runs/full_clean_20260804/icc2/reports/icc2/final_qor.rpt flow/local_runs/full_clean_20260804/icc2/reports/icc2/final/final_qor.rpt flow/local_runs/full_clean_20260804/icc2/reports/icc2/final_routes.rpt flow/local_runs/full_clean_20260804/icc2/reports/icc2/final/final_routes.rpt
~~~

原始输出：

~~~text
49:set report_dir [require_env PDE_ECO10_REPORT_DIR]
50-/home/soleil/code/DigitalIC/PDE/pdeMujunjie/flow/local_runs/full_clean_20260804/icc2/reports/icc2/final
63:open_lib $design_lib
64-Information: Loading library file '/home/soleil/code/DigitalIC/PDE/pdeMujunjie/flow/local_runs/full_clean_20260804/icc2/work/icc2/pde_chip_top_safe.dlib' (FILE-007)
12adb881aaf8ce6c37f21afe265373b66a7090d40c1d7ed92bb564b83bc09e3f  flow/local_runs/full_clean_20260804/icc2/reports/icc2/final_qor.rpt
73066277298ee682fffc820a9a0a957664a8681b00d443d1c93af9ec61904d95  flow/local_runs/full_clean_20260804/icc2/reports/icc2/final/final_qor.rpt
6ed539808f794b22cf1cfac55844fdc9726998cb8b26bbf33c34d770e2e9a421  flow/local_runs/full_clean_20260804/icc2/reports/icc2/final_routes.rpt
24526082ee72377273df1b24e37fb2be69941cc1b3fc38fc34f81bea8c024e66  flow/local_runs/full_clean_20260804/icc2/reports/icc2/final/final_routes.rpt
~~~

原始 pde_chip_top_safe.gds 是 final.console 的 write_gds 目标；后续 clean_20260804.dbu1000.gds 没有对应的保留执行日志，因此不把文件名当作权威声明。

#### eco04–eco09 污染范围

这些废弃 run 的数据库确实被后续“历史审计”与 uncertainty A/B 报告打开过；这些报告中的数字不能作为最终版本证据。

完整命令：

~~~bash
rg -n 'icc2_signoff_eco0[4-9]' . --glob '!flow/local_runs/icc2_signoff_eco0[4-9]/**' --glob '!*.md' --glob '!*.rst' --glob '!*.txt' | sed -n '1,200p'
~~~

原始输出片段：

~~~text
./flow/reports/icc2/uncertainty_ab_20260803/console.log:73:Information: Loading library file '/home/soleil/code/DigitalIC/PDE/pdeMujunjie/flow/local_runs/icc2_signoff_eco09/work/icc2/pde_chip_top_safe.dlib' (FILE-007)
./flow/reports/icc2/history_audit_20260803/eco04.console.log:42:Information: Loading library file '/home/soleil/code/DigitalIC/PDE/pdeMujunjie/flow/local_runs/icc2_signoff_eco04/work/icc2/pde_chip_top_safe.dlib' (FILE-007)
./flow/reports/icc2/history_audit_20260803/eco05.console.log:42:Information: Loading library file '/home/soleil/code/DigitalIC/PDE/pdeMujunjie/flow/local_runs/icc2_signoff_eco05/work/icc2/pde_chip_top_safe.dlib' (FILE-007)
./flow/reports/icc2/history_audit_20260803/eco06.console.log:42:Information: Loading library file '/home/soleil/code/DigitalIC/PDE/pdeMujunjie/flow/local_runs/icc2_signoff_eco06/work/icc2/pde_chip_top_safe.dlib' (FILE-007)
./flow/reports/icc2/history_audit_20260803/eco07.console.log:42:Information: Loading library file '/home/soleil/code/DigitalIC/PDE/pdeMujunjie/flow/local_runs/icc2_signoff_eco07/work/icc2/pde_chip_top_safe.dlib' (FILE-007)
./flow/reports/icc2/history_audit_20260803/eco08.console.log:42:Information: Loading library file '/home/soleil/code/DigitalIC/PDE/pdeMujunjie/flow/local_runs/icc2_signoff_eco08/work/icc2/pde_chip_top_safe.dlib' (FILE-007)
./flow/reports/icc2/history_audit_20260803/eco09.console.log:42:Information: Loading library file '/home/soleil/code/DigitalIC/PDE/pdeMujunjie/flow/local_runs/icc2_signoff_eco09/work/icc2/pde_chip_top_safe.dlib' (FILE-007)
~~~

最终 run、eco10、正式脚本范围内没有废弃 run 的实际 artifact path：

~~~bash
rg -n 'local_runs/icc2_signoff_eco0[4-9]' flow/local_runs/full_clean_20260804 flow/local_runs/icc2_signoff_eco10 flow/local flow/icc2 flow/calibre flow/openroad || true
~~~

原始输出：

~~~text
[无输出]
~~~

脚本注释中仍有 “mirrors the proven eco04 session” 等文字，但没有加载废弃数据库。污染范围因此限定为 history_audit_20260803 与 uncertainty_ab_20260803 等历史分析；没有原始证据表明 full_clean 的数据库或交付物直接继承 eco04–eco09 artifact。

### Z2　soleilUbuntu 与 EDAServer 是否一致

**结论：无法验证。** EDAServer 路径未挂载，主机名也不能解析，因此无法取得远端 commit、文件大小或校验和。不能证明“两地一致”，也不能证明“已经分叉”。

完整命令：

~~~bash
if [ -d /home/sxw/PDE/pdeMujunjie ]; then stat -c '%F %n' /home/sxw/PDE/pdeMujunjie; else echo '/home/sxw/PDE/pdeMujunjie: NOT_MOUNTED'; fi
getent hosts EDAServer || true
ssh -o BatchMode=yes -o ConnectTimeout=10 EDAServer 'cd /home/sxw/PDE/pdeMujunjie && pwd && git rev-parse HEAD'
~~~

原始输出：

~~~text
/home/sxw/PDE/pdeMujunjie: NOT_MOUNTED
ssh: Could not resolve hostname edaserver: Temporary failure in name resolution
~~~

本地条件基线校验和如下，供远端恢复访问后逐项比对。完整命令：

~~~bash
sha256sum flow/local_runs/full_clean_20260804/icc2/results/icc2/pde_chip_top_safe.gds flow/local_runs/full_clean_20260804/icc2/results/icc2/pde_chip_top_safe.def flow/local_runs/full_clean_20260804/icc2/results/icc2/pde_chip_top_safe.postroute.v flow/local_runs/full_clean_20260804/icc2/results/icc2/pde_chip_top_safe.WC.spef.RC_WORST_125.spef flow/local_runs/full_clean_20260804/icc2/results/icc2/pde_chip_top_safe.BC.spef.RC_BEST_0.spef flow/local_runs/full_clean_20260804/dc/results/pde_chip_top_safe.sdc flow/local_runs/full_clean_20260804/icc2/work/icc2/pde_chip_top_safe.dlib/pde_chip_top_safe/design.ndm
~~~

原始输出：

~~~text
fbd491f3946ce4cbaadd065894937d9206ff24884bc74cc6eab8a7d23b710720  flow/local_runs/full_clean_20260804/icc2/results/icc2/pde_chip_top_safe.gds
e84c48335f21e327633410b212bb996b29e9a246d85df60bb168040e0ab5053c  flow/local_runs/full_clean_20260804/icc2/results/icc2/pde_chip_top_safe.def
722e0329456fb60f2a1d26d6ce1a0aa5be5a8455f574fe0f675f6afe098d06dc  flow/local_runs/full_clean_20260804/icc2/results/icc2/pde_chip_top_safe.postroute.v
82de584c000aa134999ee2c56b74b2545c69a2d1fa4038ad1e2a903cd8ebb518  flow/local_runs/full_clean_20260804/icc2/results/icc2/pde_chip_top_safe.WC.spef.RC_WORST_125.spef
3499f988676f05e5e7d563ca7103ec7f929f3c6cf0a2616654e20b27297ccbf3  flow/local_runs/full_clean_20260804/icc2/results/icc2/pde_chip_top_safe.BC.spef.RC_BEST_0.spef
3a6466deeeb475a52e3c535b98162f2351084e010b8288d71199190100792be6  flow/local_runs/full_clean_20260804/dc/results/pde_chip_top_safe.sdc
6370b6b5aaf5b0b8a43f017dd2cf3c4f3dcd5a16971f6ff23aec4f81c38e70ae  flow/local_runs/full_clean_20260804/icc2/work/icc2/pde_chip_top_safe.dlib/pde_chip_top_safe/design.ndm
~~~

## 第二部分：逐条判定表

表中 E-* 指向本节后续的“完整命令 + 原始输出片段”，属于该行证据的一部分。

| 编号 | 断言/核查项 | 判定 | 证据（命令 + 原始输出） |
|---|---|---|---|
| T1 | 存在 0 open、0 short、0 route DRC、LVS、legality、PG、antenna 全干净版本 | **证伪** | E-T1：ICC2 内部 open/short/route DRC/legality/PG 为 0；同一原始报告明确写明 antenna rules 未定义且跳过。Calibre/foundry LVS 无执行证据。 |
| T2 | setup 与 hold 均已收敛 | **证伪** | E-T2、E-A1：现有约束下同步路径无负 slack，但 rst_n 不是 timing startpoint；补齐 0 ns 输入延迟后出现 16,226 条 removal 违例。 |
| T3 | GDS 约 139 MB，含 181 个厂商单元，逐层图形一致 | **证伪** | E-T3：最终原始 GDS 为 129,272,622 bytes；使用 178 个厂商单元，不是 181。178 个实际使用厂商单元的逐层几何 XOR 与实例拓扑均为 0 mismatch。 |
| T4 | ICC2 工作区自 HVT 线开工后未被改动 | **无法验证** | E-T4：本地不是 git 仓库，无 HVT 开工基准哈希；mtime 可变；EDAServer git 不可访问。 |
| A1 | rst_n false_path 不会掩盖有效 recovery/removal 签核 | **证伪** | E-A1：例外存在；删除后仍无 reset path，因为 rst_n 无 input delay、不是 startpoint；诊断性 0 ns delay 暴露 removal WNS −0.227242 ns、TNS −2715.911528 ns、16,226 条违例。 |
| A2 | eco10 的 setup 违例在最终版通过实现收敛而非约束放宽消失 | **证实** | E-A2：原始记录是 29 条而非 27 条；时钟周期、uncertainty、I/O delay、false_path、derate/AOCV/POCV 相关行完全相同；实现规模显著变化，最终 WNS +0.7430 ns。 |
| A3 | 重建 NDM 在 cell/layout/pin/timing arc/SITE 维度完整 | **证实** | E-A3：LEF/GDS/NDM layout 均 855 cells，layout pins 均 5603；两份原始 DB 与 NDM 均 816 timing cells，逐 cell pin/arc manifest 字节相同；855/855 frame 存在，SITE core 存在。 |
| A4 | snps_no_udev.sh 只影响 license checkout，不影响计算行为 | **无法验证** | E-A4：它不拦截任何符号，而是令 libudev.so.1 指向 /dev/null，使 dlopen 失败；LD_LIBRARY_PATH 作用于整个进程及子进程。无可运行的 unwrapped A/B 对照。 |
| A5 | Calibre DRC/LVS/Antenna 实际运行并通过 | **无法验证** | E-A5：本地没有日志、summary、RDB 或 pass marker；脚本存在不构成运行证据。现有 runner 仅支持 DRC/Antenna，不含 LVS。签核上必须按“未证明执行”处理。 |
| A6 | OpenROAD 与 ICC2 的角色和最终产物来源可区分，未把 OpenROAD 结果混入 ICC2 final | **证实** | E-A6：OpenROAD v27 日志未到 hard-pass，flow/results/openroad 不存在；full_clean final.console 直接生成全部最终交付物。Innovus 命名的查看包内 DEF/netlist 哈希反而与 ICC2 final 完全相同。 |
| A7 | 最终 DEF 的 IO pins 已放置 | **证实** | E-A7：59/59 PINS 均 PLACED；FIXED=0、UNPLACED=0；其中 57 个 signal/clock，另有 VDD/VSS。 |
| A8 | 天线零违例是有效检查结果 | **证伪** | E-A8：脚本要求二极管插入，但最终 ANTENNA instance=0，route report 明确跳过 antenna analysis。 |
| A9 | tap/endcap 已插入 | **证伪** | E-A9：LEF 无候选 master，DEF 只有功能 TIEL，无 tap/endcap；PNR 原始日志明确写“intentionally omitted”。 |
| A10 | 使用了有效 OCV/POCV 或非 1.00 derate | **证伪** | E-A10：Variation Type 虽显示 fixed_derate，但所有 clock/data net/cell/check derate 均为 1.00；SI 与 CRPR 均 disabled。 |
| A11 | PrimeTime+SPEF、Formality、Calibre 全 deck、IR/EM、门级仿真均已执行 | **无法验证** | E-A11：所有保留执行日志中，PT/Formality/Calibre/门级仿真命中为 0；IR/EM 唯一命中只是 help 文本。输入 SDF/SVF/SPEF 的存在不是工具执行证据。 |
| A12 | 能与独立 Innovus/HVT 线做可信数量级交叉比对 | **无法验证** | E-A12：本地无 HVT 实现产物，EDAServer 不可达；题面给出的 HVT 数字是未经本审查验证的断言，不能填入证据栏。 |

### E-T1　物理检查原始证据

完整命令：

~~~bash
sed -n '76,86p;168,184p' flow/local_runs/full_clean_20260804/icc2/reports/icc2/final/final_routes.rpt
sed -n '22,32p' flow/local_runs/full_clean_20260804/icc2/reports/icc2/final/final_lvs.rpt
sed -n '52,72p;116,126p' flow/local_runs/full_clean_20260804/icc2/reports/icc2/final/final_legality.rpt
sed -n '1,80p' flow/local_runs/full_clean_20260804/icc2/reports/icc2/final/final_pg_connectivity.rpt
~~~

原始输出片段：

~~~text
Warning: No antenna rules defined, Skip antenna analysis. (ZRT-309)
DRC-SUMMARY:
        @@@@@@@ TOTAL VIOLATIONS =      0
Verify Summary:
Total number of nets = 114393, of which 0 are not extracted
Total number of open nets = 0, of which 0 are frozen
Total number of DRCs = 0
Total number of antenna violations = no antenna rules defined
Total number of tie to rail violations = not checked

Total number of input nets is 114403.
Total number of short violations is 0.
Total number of open nets is 0.
Total number of floating route violations is 0.

TOTAL 0 Violations.
check_legality for block design pde_chip_top_safe succeeded!

Number of Standard Cells: 270471
Number of VDD Wires: 242
Number of VDD Vias: 2384
  Number of floating wires: 0
  Number of floating vias: 0
  Number of floating std cells: 0
  Number of floating terminals: 0
Number of VSS Wires: 242
Number of VSS Vias: 2384
  Number of floating wires: 0
  Number of floating vias: 0
  Number of floating std cells: 0
  Number of floating terminals: 0
~~~

final_lvs.rpt 来自 final.console 中的 ICC2 check_lvs，不是 Calibre LVS：

~~~text
135:redirect -file [file join $report_dir final_lvs.rpt] {
136-  check_lvs -checks all -max_errors 200
~~~

### E-T2　最终约束下的同步时序证据

完整命令：

~~~bash
sed -n '1,24p' flow/local_runs/full_clean_20260804/icc2/reports/icc2/final/final_setup_violations_4d.rpt
sed -n '1,24p' flow/local_runs/full_clean_20260804/icc2/reports/icc2/final/final_hold_violations_4d.rpt
rg -n 'slack \(MET\)|data arrival time|clock uncertainty|library hold time' flow/local_runs/full_clean_20260804/icc2/reports/icc2/final/final_setup_worst_4d.rpt flow/local_runs/full_clean_20260804/icc2/reports/icc2/final/final_hold_worst_4d.rpt
~~~

原始输出片段：

~~~text
Report : timing
        -delay_type max
        -slack_lesser_than 0.0000
No paths.

Report : timing
        -delay_type min
        -slack_lesser_than 0.0000
No paths.

final_setup_worst_4d.rpt:77:  slack (MET)  0.7430
final_hold_worst_4d.rpt:43:   slack (MET)  0.0004
~~~

这只证实当前例外集合下同步 setup/hold 无负 slack；不能覆盖 E-A1 中根本未形成路径的 reset recovery/removal。

### E-T3　GDS 大小、厂商单元和逐层几何

完整命令：

~~~bash
stat -c '%s %n' flow/local_runs/full_clean_20260804/icc2/results/icc2/pde_chip_top_safe.gds flow/local_runs/full_clean_20260804/icc2/results/icc2/pde_chip_top_safe.clean_20260804.dbu1000.gds
awk 'BEGIN{for(i=1;i<=2;i++){b=(i==1?129272622:121962194); printf "%d bytes = %.2f MB = %.2f MiB\n",b,b/1000000,b/1048576}}'
/usr/bin/klayout -b -r /tmp/icc2_audit_1785936929/gds_audit.py -rd final_gds=/home/soleil/code/DigitalIC/PDE/pdeMujunjie/flow/local_runs/full_clean_20260804/icc2/results/icc2/pde_chip_top_safe.gds -rd ref_gds=/home/soleil/code/DigitalIC/stdlib/tsmc65/tcbn65lp_200b/Back_End/gds/tcbn65lp_200a/tcbn65lp.gds
~~~

原始输出：

~~~text
129272622 flow/local_runs/full_clean_20260804/icc2/results/icc2/pde_chip_top_safe.gds
121962194 flow/local_runs/full_clean_20260804/icc2/results/icc2/pde_chip_top_safe.clean_20260804.dbu1000.gds
129272622 bytes = 129.27 MB = 123.28 MiB
121962194 bytes = 121.96 MB = 116.31 MiB

PDE_GDS_FINAL path=/home/soleil/code/DigitalIC/PDE/pdeMujunjie/flow/local_runs/full_clean_20260804/icc2/results/icc2/pde_chip_top_safe.gds bytes=129272622 dbu=0.0001 cells=195 tops=1 layers=23
PDE_GDS_REF path=/home/soleil/code/DigitalIC/stdlib/tsmc65/tcbn65lp_200b/Back_End/gds/tcbn65lp_200a/tcbn65lp.gds bytes=8973016 dbu=0.001 cells=855 tops=855 layers=16
PDE_GDS_TOP_FINAL pde_chip_top_safe
PDE_GDS_INTERSECTION common=178 final_only=17 ref_only=677
PDE_GDS_FINAL_ONLY $$VIA12 $$VIA12_2000_2000_1_2 $$VIA12_2000_2000_1_8 $$VIA12_2000_2000_2_1 $$VIA12_HV $$VIA23 $$VIA23_2000_2000_1_8 $$VIA34 $$VIA34_2000_2000_1_8 $$VIA45 $$VIA45_2000_2000_1_2 $$VIA45_2000_2000_1_8 $$VIA45_2000_2000_2_1 $$VIA56 $$VIA56_7000_7000_1_2 $$VIA56_9200_7000_2_2 pde_chip_top_safe
PDE_GDS_GEOM common_cells=178 compared_cell_layer_pairs=1457 mismatches=0 inst_mismatches=0 target_dbu=0.0001
~~~

195 个 final GDS cell = 178 个源 GDS 厂商 cell + 16 个 ICC2 生成的 $$VIA helper cell + 1 个 top。逐层一致性子断言仅对实际使用的 178 个厂商 cell 得到证实。

### E-T4　工作区不可追溯性

完整命令：

~~~bash
git status --short
find flow/icc2 flow/work/icc2 flow/innovus -type f ! -name '*.md' ! -name '*.txt' -printf '%TY-%Tm-%Td %TH:%TM:%TS %p\n' | sort | tail -25
~~~

原始输出片段：

~~~text
fatal: not a git repository (or any parent up to mount point /)
Stopping at filesystem boundary (GIT_DISCOVERY_ACROSS_FILESYSTEM not set).

2026-08-03 14:24:53.5447571040 flow/icc2/create_ndm.tcl
2026-08-03 14:25:52.3725967080 flow/work/icc2/ref_rebuilt/tcbn65lp_6lmT1.ndm/reflib.ndm
2026-08-04 16:12:27.2852817950 flow/icc2/pnr.tcl
2026-08-04 23:41:13.5894766670 flow/innovus/view_design.tcl
2026-08-04 23:41:25.5951209450 flow/innovus/pde_innovus_view.tgz
~~~

mtime 不是不可变证据，也没有“HVT 开工时”的 ICC2 tree hash；因此 T4 不能由这些时间戳证实。

### E-A1　rst_n false_path 内存复核

#### 1. 临时副本与执行命令

原数据库和 /tmp 副本的 design.ndm 哈希完全相同：

~~~bash
sha256sum flow/local_runs/full_clean_20260804/icc2/work/icc2/pde_chip_top_safe.dlib/pde_chip_top_safe/design.ndm /tmp/icc2_audit_1785936929/pde_chip_top_safe.dlib/pde_chip_top_safe/design.ndm
~~~

~~~text
6370b6b5aaf5b0b8a43f017dd2cf3c4f3dcd5a16971f6ff23aec4f81c38e70ae  flow/local_runs/full_clean_20260804/icc2/work/icc2/pde_chip_top_safe.dlib/pde_chip_top_safe/design.ndm
6370b6b5aaf5b0b8a43f017dd2cf3c4f3dcd5a16971f6ff23aec4f81c38e70ae  /tmp/icc2_audit_1785936929/pde_chip_top_safe.dlib/pde_chip_top_safe/design.ndm
~~~

正式复核的完整命令：

~~~bash
distrobox enter synopsys-focal -- bash -lc 'set -o pipefail; cd /tmp/icc2_audit_1785936929; source /home/soleil/code/DigitalIC/PDE/pdeMujunjie/flow/local/env_local.sh; /home/soleil/code/DigitalIC/PDE/pdeMujunjie/flow/local/snps_no_udev.sh icc2_shell -f /tmp/icc2_audit_1785936929/a1_final_recheck.tcl 2>&1 | tee /tmp/icc2_audit_1785936929/a1_final_recheck.console.log'
~~~

原始输出关键标记：

~~~text
PDE_A1_BEGIN dlib=/tmp/icc2_audit_1785936929/pde_chip_top_safe.dlib scenarios=FUNC_BC FUNC_WC
PDE_A1_BASE total_max=23926 total_min=23926 rst_max=0 rst_min=0
PDE_A1_RESET_PATH_RETURN 1
PDE_A1_RESET_ONLY total_max=23926 total_min=23926 rst_max=0 rst_min=0 max_V_WNS_TNS=0 0.0 0.0 min_V_WNS_TNS=0 0.0 0.0
PDE_A1_ZERO_DELAY rst_max=0 max_V_WNS_TNS=0 0.0 0.0 rst_min=23905 min_V_WNS_TNS=16226 -0.227242 -2715.911528
PDE_A1_LIB_CHECK_ARCS count=4
PDE_A1_LIB_ARC from=tcbn65lp_6lmT1/DFCNQD1/CP to=tcbn65lp_6lmT1/DFCNQD1/CDN sense=recovery_rise_clk_rise disabled=false
PDE_A1_LIB_ARC from=tcbn65lp_6lmT1/DFCNQD1/CP to=tcbn65lp_6lmT1/DFCNQD1/CDN sense=removal_rise_clk_rise disabled=false
PDE_A1_LIB_ARC from=tcbn65lp_6lmT1/DFCNQD1/CP to=tcbn65lp_6lmT1/DFCNQD1/CDN sense=recovery_rise_clk_rise disabled=false
PDE_A1_LIB_ARC from=tcbn65lp_6lmT1/DFCNQD1/CP to=tcbn65lp_6lmT1/DFCNQD1/CDN sense=removal_rise_clk_rise disabled=false
time.disable_recovery_removal_checks bool       false      --           --           false          global     normal     --
PDE_A1_DONE
~~~

#### 2. 例外存在；仅删除例外仍然没有 reset timing path

完整命令：

~~~bash
cat /tmp/icc2_audit_1785936929/a1_baseline_exceptions.rpt
cat /tmp/icc2_audit_1785936929/a1_reset_only_exceptions.rpt
cat /tmp/icc2_audit_1785936929/a1_reset_only_rst_min.rpt
nl -ba flow/local_runs/full_clean_20260804/dc/results/pde_chip_top_safe.sdc | sed -n '28,48p'
~~~

原始输出片段：

~~~text
#  /home/soleil/code/DigitalIC/PDE/pdeMujunjie/flow/local_runs/full_clean_20260804/dc/results/pde_chip_top_safe.sdc, line 41
set_false_path -from [get_ports {rst_n}]

[reset_path 后 report_exceptions 中无例外行]

Warning: From_pin 'rst_n' is not a timing startpoint and will be ignored. (TIM-010)
No paths.

32  set_ideal_network [get_ports clk]
33  set_ideal_network [get_ports rst_n]
34  create_clock [get_ports clk]  -name core_clk  -period 10  -waveform {0 5}
35  set_clock_uncertainty -setup 0.2  [get_clocks core_clk]
36  set_clock_uncertainty -hold 0.05  [get_clocks core_clk]
41  set_false_path   -from [get_ports rst_n]
42  set_input_delay -clock core_clk  1  [get_ports cfg_valid]
~~~

rst_n 没有 input delay。由此，严格按最终 SDC 做“有/无 false_path”比较，路径总数是 max 23926→23926、min 23926→23926，reset 路径 0→0。这个 0 差值不是“例外没有豁免路径”的证据，而是 reset 没有成为 timing startpoint。最终约束下的豁免条数及占比因此 **无法验证**。

为了检查计数是否依赖 timing-path 枚举口径，又在同一个 /tmp 内存副本中，以明确的 0 ns min/max input delay、删除例外后用 nworst=2 查询。完整命令：

~~~bash
distrobox enter synopsys-focal -- bash -lc 'set -o pipefail; cd /tmp/icc2_audit_1785936929; source /home/soleil/code/DigitalIC/PDE/pdeMujunjie/flow/local/env_local.sh; /home/soleil/code/DigitalIC/PDE/pdeMujunjie/flow/local/snps_no_udev.sh icc2_shell -f /tmp/icc2_audit_1785936929/a1_matrix_probe.tcl 2>&1 | tee /tmp/icc2_audit_1785936929/a1_matrix_probe.console.log'
~~~

原始输出：

~~~text
PDE_A1_MATRIX scenario=FUNC_WC delay=max all=0 0.0 0.0 violations=0 0.0 0.0
PDE_A1_MATRIX scenario=FUNC_WC delay=min all=0 0.0 0.0 violations=0 0.0 0.0
PDE_A1_MATRIX scenario=FUNC_BC delay=max all=0 0.0 0.0 violations=0 0.0 0.0
PDE_A1_MATRIX scenario=FUNC_BC delay=min all=31585 -0.227242 -2715.911528 violations=16226 -0.227242 -2715.911528
PDE_A1_MATRIX_DONE
~~~

nworst=1 给出 23,905 个 reset endpoint path，nworst=2 给出 31,585 条 path，证明“总路径数”随枚举参数变化。可复现、口径清楚的数是：**受影响 reset endpoint 数为 23,905；最终 SDC 下的豁免路径百分比无法验证**。不能把 23,905 除以某个未定义的“总路径数”伪造百分比，也不能照搬 HVT 线的 16,225/34.25%。

#### 3. 诊断性 0 ns 输入延迟暴露 removal 违例

这里的 0 ns input delay 是内存诊断约束，不冒充交付 SDC。完整命令：

~~~bash
sed -n '1,48p' /tmp/icc2_audit_1785936929/a1_zero_delay_rst_min_worst.rpt
rg -n 'NEX-020' /tmp/icc2_audit_1785936929/a1_zero_delay_update.log
~~~

原始输出片段：

~~~text
Startpoint: rst_n (input port clocked by core_clk)
Endpoint: u_impl/cfg_rdata_reg_2_ (removal check against rising-edge clock clocked by core_clk)
Mode: FUNC
Corner: BC
Scenario: FUNC_BC
Path Type: min

clock network delay                             0.322952      0.322952
input external delay                           0.000000      0.322952
u_impl/cfg_rdata_reg_2_/CDN (DFCNQD1)          0.000000      0.322952
data arrival time                                            0.322952
clock network delay                             0.409679      0.409679
clock uncertainty                              0.050000      0.459679
library hold time                              0.090523      0.550203
slack (VIOLATED)                                            -0.227242

Warning: Net 'rst_n' is exceeding threshold (over 1000 pins) and will be skipped. (NEX-020)
~~~

最差项明确是 **removal check**。RVT NDM 内 recovery/removal arcs 均存在且 disabled=false，但本实验在任何 scenario/delay_type 组合下都没有生成 recovery path，因此 recovery WNS/TNS **无法验证**；不能将 “0 条”解释为通过。另一个独立缺口是提取器因 fanout 超过 1000 跳过 rst_n，reset insertion/parasitic delay 没有被完整提取。

#### 4. reset 直接连接 CDN，没有同步器证据

完整命令：

~~~bash
printf 'CDN_total='; rg -o '\.CDN[[:space:]]*\(' flow/local_runs/full_clean_20260804/icc2/results/icc2/pde_chip_top_safe.postroute.v | wc -l
printf 'CDN_rst_n='; rg -o '\.CDN[[:space:]]*\([[:space:]]*rst_n[[:space:]]*\)' flow/local_runs/full_clean_20260804/icc2/results/icc2/pde_chip_top_safe.postroute.v | wc -l
printf 'CDN_rst_ni='; rg -o '\.CDN[[:space:]]*\([[:space:]]*rst_ni[[:space:]]*\)' flow/local_runs/full_clean_20260804/icc2/results/icc2/pde_chip_top_safe.postroute.v | wc -l
printf 'rst_ni_from_rst_n='; rg -o '\.rst_ni[[:space:]]*\([[:space:]]*rst_n[[:space:]]*\)' flow/local_runs/full_clean_20260804/icc2/results/icc2/pde_chip_top_safe.postroute.v | wc -l
printf 'reset_sync_name_hits='; n=$(rg -i -o 'reset[_]?sync|rst[_]?sync|sync[_]?reset|synchronizer' flow/local_runs/full_clean_20260804/icc2/results/icc2/pde_chip_top_safe.postroute.v | wc -l); echo "$n"
~~~

原始输出：

~~~text
CDN_total=16224
CDN_rst_n=16219
CDN_rst_ni=5
rst_ni_from_rst_n=1
reset_sync_name_hits=0
~~~

文本网表包含层次模块定义，所以 16,224 不是 elaborated flop 总数；ICC2 live design 的 sequential/reset endpoint 数是 23,905。两种证据一致表明 reset 直接进入 DFCNQD1/CDN 或经层次端口改名为 rst_ni 后进入 CDN；没有同步器命名或结构证据。

### E-A2　eco10 setup 违例去向与约束比较

题面所称 27 条与原始 report 不符；原始数是 29。

完整命令：

~~~bash
sed -n '32,44p' flow/local_runs/icc2_signoff_eco10/reports/icc2/uncertainty_fix/after_qor.rpt
printf 'startpoints='; rg -c '^  Startpoint:' flow/local_runs/icc2_signoff_eco10/reports/icc2/uncertainty_fix/after_setup_violations_4d.rpt
rg -n 'slack \(VIOLATED\)' flow/local_runs/icc2_signoff_eco10/reports/icc2/uncertainty_fix/after_setup_violations_4d.rpt | head -3
~~~

原始输出：

~~~text
Critical Path Length:             10.16
Critical Path Slack:              -0.21
Critical Path Clk Period:         10.00
Total Negative Slack:             -2.79
No. of Violating Paths:              29
startpoints=29
71:  slack (VIOLATED)  -0.2076
131: slack (VIOLATED)  -0.2066
190: slack (VIOLATED)  -0.1982
~~~

完整命令：

~~~bash
for f in flow/local_runs/icc2_signoff_eco10/reports/icc2/closure1/s2_entry_FUNC_WC.sdc flow/local_runs/icc2_signoff_eco10/reports/icc2/closure1/s2_entry_FUNC_BC.sdc flow/local_runs/full_clean_20260804/icc2/reports/icc2/closure2/s2_entry_FUNC_WC.sdc flow/local_runs/full_clean_20260804/icc2/reports/icc2/closure2/s2_entry_FUNC_BC.sdc; do echo "$f"; rg 'create_clock|set_clock_uncertainty|set_timing_derate|set_(input|output)_delay|set_false_path|set_(aocv|pocv)' "$f" | sed 's/[[:space:]]\+/ /g' | sha256sum; rg -c '^set_input_delay' "$f"; rg -c '^set_output_delay' "$f"; done
~~~

原始输出：

~~~text
flow/local_runs/icc2_signoff_eco10/reports/icc2/closure1/s2_entry_FUNC_WC.sdc
835699bdecd4fb9b23e8e1571e2d5dbb336af355d080feb79dca263d54be1a79  -
34
21
flow/local_runs/icc2_signoff_eco10/reports/icc2/closure1/s2_entry_FUNC_BC.sdc
835699bdecd4fb9b23e8e1571e2d5dbb336af355d080feb79dca263d54be1a79  -
34
21
flow/local_runs/full_clean_20260804/icc2/reports/icc2/closure2/s2_entry_FUNC_WC.sdc
835699bdecd4fb9b23e8e1571e2d5dbb336af355d080feb79dca263d54be1a79  -
34
21
flow/local_runs/full_clean_20260804/icc2/reports/icc2/closure2/s2_entry_FUNC_BC.sdc
835699bdecd4fb9b23e8e1571e2d5dbb336af355d080feb79dca263d54be1a79  -
34
21
~~~

实际关键行在两者中相同：

~~~text
create_clock -name core_clk -period 10 -waveform {0 5} [get_ports {clk}]
set_false_path -from [get_ports {rst_n}]
set_clock_uncertainty -setup 0.2 [get_clocks {core_clk}]
set_clock_uncertainty -hold 0.05 [get_clocks {core_clk}]
~~~

derate/AOCV/POCV 命令均无命中；输入延迟 34 行、输出延迟 21 行。实现规模则发生实质变化：

~~~bash
rg -n 'Leaf Cell Count|Buf/Inv Cell Count|Cell Area \(netlist\)' flow/local_runs/icc2_signoff_eco10/reports/icc2/uncertainty_fix/after_qor.rpt flow/local_runs/full_clean_20260804/icc2/reports/icc2/final/final_qor.rpt
~~~

~~~text
flow/local_runs/full_clean_20260804/icc2/reports/icc2/final/final_qor.rpt:116:Leaf Cell Count:                 111354
flow/local_runs/full_clean_20260804/icc2/reports/icc2/final/final_qor.rpt:117:Buf/Inv Cell Count:               21961
flow/local_runs/full_clean_20260804/icc2/reports/icc2/final/final_qor.rpt:153:Cell Area (netlist):                         418753.44
flow/local_runs/icc2_signoff_eco10/reports/icc2/uncertainty_fix/after_qor.rpt:49:Leaf Cell Count:                 128122
flow/local_runs/icc2_signoff_eco10/reports/icc2/uncertainty_fix/after_qor.rpt:50:Buf/Inv Cell Count:               38715
flow/local_runs/icc2_signoff_eco10/reports/icc2/uncertainty_fix/after_qor.rpt:86:Cell Area (netlist):                         479063.52
~~~

所以在用户指定的约束字段上没有放宽证据；29 条 setup 违例随 fresh synthesis/implementation 与后续优化消失。

### E-A3　重建 NDM 完整性

重建日志和 workspace check 均留存。完整命令：

~~~bash
rg -n 'PDE_NDM: (LEF|GDS)|created 855 frames|Workspace check succeeded|PDE_NDM_DONE' flow/reports/icc2/create_ndm.local.log flow/reports/icc2/create_ndm.check_workspace.rpt
~~~

原始输出：

~~~text
create_ndm.local.log:94:PDE_NDM: LEF=/home/soleil/code/DigitalIC/stdlib/tsmc65/tcbn65lp_200b/Back_End/lef/tcbn65lp_200a/lef/tcbn65lp_6lmT1.lef
create_ndm.local.log:96:PDE_NDM: GDS=/home/soleil/code/DigitalIC/stdlib/tsmc65/tcbn65lp_200b/Back_End/gds/tcbn65lp_200a/tcbn65lp.gds
create_ndm.local.log:2122:PDE_NDM_DONE ref_ndm=/home/soleil/code/DigitalIC/PDE/pdeMujunjie/flow/work/icc2/ref_rebuilt/tcbn65lp_6lmT1.ndm
create_ndm.check_workspace.rpt:5353:... created 855 frames
create_ndm.check_workspace.rpt:5355:Workspace check succeeded!
~~~

live report_lib 原始片段：

~~~text
Full name: /home/soleil/code/DigitalIC/PDE/pdeMujunjie/flow/work/icc2/ref_rebuilt/tcbn65lp_6lmT1.ndm:tcbn65lp_6lmT1
Design count: 855
Pane count: 2
Pane 0:
  Process label: WC
  Source .db file:
    /home/soleil/code/DigitalIC/stdlib/tsmc65/tcbn65lp_200b/Front_End/timing_power_noise/CCS/tcbn65lpwc_ccs.db
Pane 1:
  Process label: BC
  Source .db file:
    /home/soleil/code/DigitalIC/stdlib/tsmc65/tcbn65lp_200b/Front_End/timing_power_noise/CCS/tcbn65lpbc_ccs.db
~~~

完整集合比较命令：

~~~bash
wc -l /tmp/icc2_audit_1785936929/ref_lef_cells.txt /tmp/icc2_audit_1785936929/ref_gds_cells.txt /tmp/icc2_audit_1785936929/ndm_layout_cells.txt /tmp/icc2_audit_1785936929/ref_lef_pins.txt /tmp/icc2_audit_1785936929/ndm_layout_pins.txt /tmp/icc2_audit_1785936929/tcbn65lpwc_ccs_manifest.tsv /tmp/icc2_audit_1785936929/tcbn65lpbc_ccs_manifest.tsv /tmp/icc2_audit_1785936929/ndm_timing_manifest.tsv
cmp -s /tmp/icc2_audit_1785936929/ref_lef_cells.txt /tmp/icc2_audit_1785936929/ref_gds_cells.txt; echo "LEF_vs_GDS_cmp=$?"
cmp -s /tmp/icc2_audit_1785936929/ref_lef_cells.txt /tmp/icc2_audit_1785936929/ndm_layout_cells.txt; echo "LEF_vs_NDM_layout_cmp=$?"
cmp -s /tmp/icc2_audit_1785936929/ref_lef_pins.txt /tmp/icc2_audit_1785936929/ndm_layout_pins.txt; echo "LEFpin_vs_NDMpin_cmp=$?"
cmp -s /tmp/icc2_audit_1785936929/tcbn65lpwc_ccs_manifest.tsv /tmp/icc2_audit_1785936929/ndm_timing_manifest.tsv; echo "WC_vs_NDM_timing_cmp=$?"
cmp -s /tmp/icc2_audit_1785936929/tcbn65lpbc_ccs_manifest.tsv /tmp/icc2_audit_1785936929/ndm_timing_manifest.tsv; echo "BC_vs_NDM_timing_cmp=$?"
~~~

原始输出：

~~~text
855  ref_lef_cells.txt
855  ref_gds_cells.txt
855  ndm_layout_cells.txt
5603 ref_lef_pins.txt
5603 ndm_layout_pins.txt
816  tcbn65lpwc_ccs_manifest.tsv
816  tcbn65lpbc_ccs_manifest.tsv
816  ndm_timing_manifest.tsv
LEF_vs_GDS_cmp=0
LEF_vs_NDM_layout_cmp=0
LEFpin_vs_NDMpin_cmp=0
WC_vs_NDM_timing_cmp=0
BC_vs_NDM_timing_cmp=0
~~~

manifest 逐 cell 包含 cell name、pin 数和集合、timing arc 数和 from/to/sense/when；cmp=0 不只是总数相同。39 个 physical-only cell 正好解释 855−816，没有把它们误判为 timing cell 丢失。完整命令及输出：

~~~bash
rg -n 'PDE_NDM_MANIFEST|PDE_SRC_MANIFEST' /tmp/icc2_audit_1785936929/ndm_manifest.console.log /tmp/icc2_audit_1785936929/source_db_manifest.console.log
awk 'BEGIN{inlist=0;n=0;yes=0} /^   Cell[[:space:]]+Panes/{inlist=1;next} inlist&&/^   -+/{next} inlist&&/^   [A-Za-z0-9_$]/{n++; for(i=2;i<=NF;i++)if($i=="YES"){yes++;break}} END{printf "cell_rows=%d frame_exist_yes=%d\n",n,yes}' /tmp/icc2_audit_1785936929/ref_cell_summary.rpt
~~~

~~~text
PDE_NDM_MANIFEST requested=816 found=816 missing=0
PDE_SRC_MANIFEST lib=tcbn65lpwc_ccs cells=816
PDE_SRC_MANIFEST lib=tcbn65lpbc_ccs cells=816
PDE_SRC_MANIFEST_DONE
cell_rows=855 frame_exist_yes=855
~~~

SITE 也来自 live NDM 查询：

~~~text
PDE_AUDIT_SITES count=8 names=gaunit unit core bcore bcoreExt ccore dcore gacore
~~~

该结论只证实结构完整性，不把 warning 当作不存在。workspace check 有大量 routing-blockage/frame warning：

~~~bash
printf 'workspace_warning_lines='; rg -c '^Warning:' flow/reports/icc2/create_ndm.check_workspace.rpt
printf 'FRAM065='; rg -c '\(FRAM-065\)' flow/reports/icc2/create_ndm.check_workspace.rpt
printf 'FRAM066='; rg -c '\(FRAM-066\)' flow/reports/icc2/create_ndm.check_workspace.rpt
~~~

~~~text
workspace_warning_lines=2880
FRAM065=989
FRAM066=256
~~~

这些 warning 需要 foundry/library owner 处置，但没有推翻本次 cell/pin/arc/frame 集合一致性结果。

### E-A4　snps_no_udev.sh 影响面

完整命令：

~~~bash
nl -ba flow/local/snps_no_udev.sh
ls -l /home/soleil/.cache/pde-snps/no-udev/libudev.so.1
readelf -Ws /home/soleil/.cache/pde-snps/no-udev/libudev.so.1 2>&1 || true
ldd /home/soleil/synopsys/icc2/W-2024.09/linux64/bin/icc2_exec 2>/dev/null | rg -i 'udev' || echo ICC2_EXEC_LDD_UDEV_NONE
rg -n 'udev_get_userdata|udev_enumerate_scan_devices|Fatal' flow/reports/icc2/finish.console.log | head -20
~~~

原始输出片段：

~~~text
20  mkdir -p "$MASK_DIR"
23  if [ -L "$MASK_LIB" ]; then
32      ln -s /dev/null "$MASK_LIB"
35  export LD_LIBRARY_PATH="$MASK_DIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
36  exec "$@"

lrwxrwxrwx 1 soleil soleil 9 Aug  3 13:03 /home/soleil/.cache/pde-snps/no-udev/libudev.so.1 -> /dev/null
readelf: Error: '/home/soleil/.cache/pde-snps/no-udev/libudev.so.1' is not an ordinary file
ICC2_EXEC_LDD_UDEV_NONE
flow/reports/icc2/finish.console.log:24:Fatal: Internal system error, cannot recover.
flow/reports/icc2/finish.console.log:38:udev_get_userdata+72
flow/reports/icc2/finish.console.log:42:udev_enumerate_scan_devices+660
~~~

实际“拦截的符号数”是 **0**：/dev/null 不是 ELF shared object，不能导出符号。wrapper 的机制是让可选 libudev dlopen 失败，而不是提供假的函数实现。它解决了已观察到的 udev crash，但 LD_LIBRARY_PATH 对整个 wrapped process 及其 children 生效。由于 unwrapped ICC2 会崩溃，无法取得相同数据库/相同命令的计算 A/B；“只影响 license checkout”无法验证。

### E-A5　Calibre 是否实际运行

完整命令：

~~~bash
find flow/reports/calibre -maxdepth 3 -type f -printf '%p\t%s\n' 2>/dev/null
find flow -type f \( -iname '*.summary' -o -iname '*.rdb' -o -iname '*calibre*.log' -o -iname '*drc*.results' -o -iname '*lvs*.report*' -o -iname '*antenna*.report*' \) -printf '%p\t%s\n' | sort
rg -n 'PDE_CALIBRE_RUN_START|PDE_CALIBRE_ZERO_RESULTS_PASS|PDE_CALIBRE_BLOCK_ZERO_HARD_PASS' flow --glob '!*.md'
~~~

原始输出：

~~~text
[前两个 find 无输出]
flow/calibre/run_block_signoff_final.sh:44:  echo "PDE_CALIBRE_RUN_START kind=$kind deck=$deck gds=$PDE_GDS top=$PDE_TOP"
flow/calibre/run_block_signoff_zero_v3.sh:81:  echo "PDE_CALIBRE_ZERO_RESULTS_PASS kind=$kind summary=$summary"
flow/calibre/run_block_signoff_zero_v3.sh:91:echo "PDE_CALIBRE_BLOCK_ZERO_HARD_PASS mode=$mode gds=$PDE_GDS top=$PDE_TOP"
~~~

命中全在脚本源码，不在运行日志。streamout_hardpass_manifest_v3.sh 也不是 DRC/LVS runner：

~~~bash
nl -ba flow/calibre/streamout_hardpass_manifest_v3.sh | sed -n '1,88p'
nl -ba flow/calibre/run_block_signoff_final.sh | sed -n '1,60p'
nl -ba flow/calibre/run_block_signoff_zero_v3.sh | sed -n '55,95p'
nl -ba flow/calibre/block_signoff_config.sh | sed -n '6,35p'
~~~

原始输出片段：

~~~text
streamout_hardpass_manifest_v3.sh:
4  # Stream out only an OpenROAD final DEF whose exact identity and checksum are
8  repo_root=/home/sxw/PDE/pdeMujunjie
22 if [[ ! -s "$manifest" ]] || ! grep -Fxq PDE_OPENROAD_PHYSICAL_HARD_PASS "$manifest"; then
88 echo "PDE_GDS_STREAMOUT_PASS tag=$tag tagged=$tagged_gds canonical=$canonical_gds"

run_block_signoff_final.sh:
8  case "$mode" in
9    drc|antenna|all) ;;
45 "$calibre_bin" -drc -hier -turbo "$PDE_CALIBRE_TURBO" "$deck" 2>&1 | tee "$log"
51 echo "PDE_CALIBRE_REVIEW_REQUIRED kind=$kind (process exit alone does not mean zero violations)"

run_block_signoff_zero_v3.sh:
66 if (!found || malformed) exit 2
67 if (nonzero) exit 1
81 echo "PDE_CALIBRE_ZERO_RESULTS_PASS kind=$kind summary=$summary"

block_signoff_config.sh:
11 : "${PDE_GDS:=${PDE_REPO_ROOT}/flow/results/openroad/pde_chip_top_safe.gds}"
~~~

阈值没有被放宽：v3 对每个可解析 TOTAL 数值要求为 0；但普通 final runner 只要求 summary 文件存在并明确要求人工 review。两者都只支持 DRC/Antenna，不包含 LVS。由于历史执行后删除产物在逻辑上不可排除，严格判定是“无法验证是否曾运行”；当前可审计交付中 **没有 Calibre DRC/LVS/Antenna 的通过证据和违例数**。

### E-A6　OpenROAD 角色、失败状态与产物来源

完整命令：

~~~bash
if [ -d flow/results/openroad ]; then find flow/results/openroad -maxdepth 1 -type f -printf '%f\t%s\n' | sort; else echo 'flow/results/openroad: NOT_PRESENT'; fi
rg -n 'PDE_OPENROAD_PHYSICAL_HARD_PASS' flow/reports/openroad || echo 'NO_PASS_MARKER_IN_OPENROAD_REPORTS'
rg -n '\[ERROR GRT-0116\]|Number of violations|Completing 30%' flow/reports/openroad/30_grt_buffd2_strict_s1_v27.log flow/reports/openroad/40_drt_buffd2_s1_v27.log flow/reports/openroad/40_drt_buffd2_s2_v27.log | sed -n '1,80p'
~~~

原始输出：

~~~text
flow/results/openroad: NOT_PRESENT
NO_PASS_MARKER_IN_OPENROAD_REPORTS
flow/reports/openroad/30_grt_buffd2_strict_s1_v27.log:10:[ERROR GRT-0116] Global routing finished with congestion.
flow/reports/openroad/40_drt_buffd2_s1_v27.log:240:    Completing 30% with 74734 violations.
flow/reports/openroad/40_drt_buffd2_s1_v27.log:256:[INFO DRT-0199]   Number of violations = 308695.
flow/reports/openroad/40_drt_buffd2_s1_v27.log:294:    Completing 30% with 284138 violations.
flow/reports/openroad/40_drt_buffd2_s2_v27.log:240:    Completing 30% with 74128 violations.
flow/reports/openroad/40_drt_buffd2_s2_v27.log:256:[INFO DRT-0199]   Number of violations = 309668.
~~~

OpenROAD v27 Tcl 只有在 post-fill DRT、antenna、PG 等检查完成后才写最终文件和 pass marker；现有日志没有到达该行。

所谓 flow/innovus/pde_innovus_view.tgz 不是另一条 HVT 实现，而是 ICC2/RVT viewer bundle。完整命令：

~~~bash
tar -tzvf flow/innovus/pde_innovus_view.tgz
tar -xOf flow/innovus/pde_innovus_view.tgz pde_chip_top_safe.def | sha256sum
tar -xOf flow/innovus/pde_innovus_view.tgz pde_chip_top_safe.postroute.v | sha256sum
tar -xOf flow/innovus/pde_innovus_view.tgz tcbn65lp_6lmT1.lef | sha256sum
sha256sum flow/local_runs/full_clean_20260804/icc2/results/icc2/pde_chip_top_safe.def flow/local_runs/full_clean_20260804/icc2/results/icc2/pde_chip_top_safe.postroute.v /home/soleil/code/DigitalIC/stdlib/tsmc65/tcbn65lp_200b/Back_End/lef/tcbn65lp_200a/lef/tcbn65lp_6lmT1.lef
~~~

原始输出片段：

~~~text
-rw-r--r-- soleil/soleil 133426296 2026-08-04 16:53 pde_chip_top_safe.def
-rw-r--r-- soleil/soleil  34167241 2026-08-04 16:53 pde_chip_top_safe.postroute.v
-rw-rw-r-- soleil/soleil   2694385 2019-01-05 11:51 tcbn65lp_6lmT1.lef
-rw-rw-r-- soleil/soleil      1098 2026-08-04 23:41 view_design.tcl
e84c48335f21e327633410b212bb996b29e9a246d85df60bb168040e0ab5053c  -
722e0329456fb60f2a1d26d6ce1a0aa5be5a8455f574fe0f675f6afe098d06dc  -
dde3fe83f6c167a4f751676de0e8671bc7054047416296c4f3d46f58ed190445  -
e84c48335f21e327633410b212bb996b29e9a246d85df60bb168040e0ab5053c  flow/local_runs/full_clean_20260804/icc2/results/icc2/pde_chip_top_safe.def
722e0329456fb60f2a1d26d6ce1a0aa5be5a8455f574fe0f675f6afe098d06dc  flow/local_runs/full_clean_20260804/icc2/results/icc2/pde_chip_top_safe.postroute.v
dde3fe83f6c167a4f751676de0e8671bc7054047416296c4f3d46f58ed190445  /home/soleil/code/DigitalIC/stdlib/tsmc65/tcbn65lp_200b/Back_End/lef/tcbn65lp_200a/lef/tcbn65lp_6lmT1.lef
~~~

因此条件基线的 GDS/DEF/netlist/SPEF 与 final reports 都来自 ICC2。没有发现把 OpenROAD 数字写进嵌套 ICC2 final report 的证据；但 Calibre 默认配置指向 OpenROAD GDS、而 viewer 包目录名叫 innovus，这两处命名/默认值构成后续人工混用风险。

### E-A7　DEF IO pin 状态

完整命令：

~~~bash
awk 'BEGIN{in_pins=0; fixed=placed=unplaced=cover=other=parsed=pg=sig=0} /^PINS [0-9]+ ;/{in_pins=1; declared=$2; next} /^END PINS/{in_pins=0} in_pins&&/^ - /{parsed++} in_pins&&/\+ FIXED /{fixed++} in_pins&&/\+ PLACED /{placed++} in_pins&&/\+ UNPLACED/{unplaced++} in_pins&&/\+ COVER /{cover++} in_pins&&/\+ USE (POWER|GROUND)/{pg++} in_pins&&/\+ USE (SIGNAL|CLOCK)/{sig++} END{other=parsed-fixed-placed-unplaced-cover; printf "declared=%d parsed=%d FIXED=%d PLACED=%d UNPLACED=%d COVER=%d OTHER=%d PG=%d SIGNAL_OR_CLOCK=%d\n",declared,parsed,fixed,placed,unplaced,cover,other,pg,sig}' flow/local_runs/full_clean_20260804/icc2/results/icc2/pde_chip_top_safe.def
~~~

原始输出：

~~~text
declared=59 parsed=59 FIXED=0 PLACED=59 UNPLACED=0 COVER=0 OTHER=0 PG=2 SIGNAL_OR_CLOCK=57
~~~

与题面提到的 HVT 57 个信号 pin 口径对应时，ICC2/RVT 的 57 个 signal/clock pin 全部有 PLACED 坐标；额外两个是 VDD/VSS。ICC2/RVT 不存在 “57 个 pin 全部 UNPLACED” 缺陷。

### E-A8　天线规则、LEF 属性和二极管数量

完整命令：

~~~bash
awk 'function finish(){if(!pin)return; if((dir=="INPUT"||dir=="INOUT")&&use!="POWER"&&use!="GROUND"){sig++; if(gate)withgate++; else {missing++; misslist=misslist macro "/" pin " "}} if(diff)withdiff++; pin=""} /^MACRO[[:space:]]/{macro=$2} /^[[:space:]]+PIN[[:space:]]/{finish(); pin=$2; dir=""; use=""; gate=0; diff=0; next} pin&&/^[[:space:]]+DIRECTION[[:space:]]/{dir=$2} pin&&/^[[:space:]]+USE[[:space:]]/{use=$2} pin&&/ANTENNAGATEAREA/{gate=1; gatestmt++} pin&&/ANTENNADIFFAREA/{diff=1; diffstmt++} pin&&$1=="END"&&$2==pin{finish()} END{finish(); printf "signal_input_or_inout=%d with_ANTENNAGATEAREA=%d missing=%d\nmissing_list=%s\nANTENNAGATEAREA_statements=%d\n",sig,withgate,missing,misslist,gatestmt}' /home/soleil/code/DigitalIC/stdlib/tsmc65/tcbn65lp_200b/Back_End/lef/tcbn65lp_200a/lef/tcbn65lp_6lmT1.lef
rg -c 'ANTENNADIFFAREA' /home/soleil/code/DigitalIC/stdlib/tsmc65/tcbn65lp_200b/Back_End/lef/tcbn65lp_200a/lef/tcbn65lp_6lmT1.lef
def=flow/local_runs/full_clean_20260804/icc2/results/icc2/pde_chip_top_safe.def; printf 'ANTENNA_instances='; sed -n '/^COMPONENTS /,/^END COMPONENTS/p' "$def" | awk '$1=="-"&&$3=="ANTENNA"{n++} END{print n+0}'
rg -n 'antenna|diode' flow/icc2/pnr.tcl
rg -n 'No antenna rules|Total number of antenna violations' flow/local_runs/full_clean_20260804/icc2/reports/icc2/final/final_routes.rpt
~~~

原始输出片段：

~~~text
signal_input_or_inout=2860 with_ANTENNAGATEAREA=2859 missing=1
missing_list=ANTENNA/I
ANTENNAGATEAREA_statements=2865
1032
ANTENNA_instances=0

281:set_app_options -name route.detail.antenna -value true
282:set_app_options -name route.detail.diode_libcell_names -value {ANTENNA}
283:set_app_options -name route.detail.insert_diodes_during_routing -value true
284:set_app_options -name route.detail.antenna_fixing_preference -value use_diodes

80:Warning: No antenna rules defined, Skip antenna analysis. (ZRT-309)
179:Total number of antenna violations = no antenna rules defined
~~~

ANTENNA/I 的原始 LEF 定义是：

~~~text
MACRO ANTENNA
    PIN I
        ANTENNADIFFAREA 0.1066 ;
        DIRECTION INPUT ;
~~~

专用 diode pin 使用 ANTENNADIFFAREA、没有 ANTENNAGATEAREA；普通 signal input/inout 中除该 diode pin 外，2,859/2,859 均有 gate area。问题不是普通输入 gate area 大面积缺失，而是 ICC2 没有加载 antenna rules，最终也没有插入任何 ANTENNA cell。**“0 antenna violation”不是计算出的 0。**

### E-A9　tap/endcap

完整命令：

~~~bash
lef=/home/soleil/code/DigitalIC/stdlib/tsmc65/tcbn65lp_200b/Back_End/lef/tcbn65lp_200a/lef/tcbn65lp_6lmT1.lef
rg '^MACRO ' "$lef" | rg -i 'TAP|ENDCAP|BOUND|WELLTIE|WELL_TIE' || echo 'LEF_TAP_ENDCAP_CANDIDATES=NONE'
sed -n '/^COMPONENTS /,/^END COMPONENTS/p' flow/local_runs/full_clean_20260804/icc2/results/icc2/pde_chip_top_safe.def | awk '$1=="-"{c[$3]++} END{for(m in c) if(m~/TAP|ENDCAP|BOUND|WELLTIE|WELL_TIE|TIE/) print m,c[m]}' | sort
sed -n '/^COMPONENTS /,/^END COMPONENTS/p' flow/local_runs/full_clean_20260804/icc2/results/icc2/pde_chip_top_safe.def | awk '$1=="-"&&$3~/^FILL/{c[$3]++} END{for(m in c) print m,c[m]}' | sort -V
rg -n 'tap/endcap' flow/local_runs/full_clean_20260804/icc2/reports/icc2/pnr.local.log
~~~

原始输出：

~~~text
LEF_TAP_ENDCAP_CANDIDATES=NONE
TIEL 1
FILL1 44269
FILL2 41420
FILL4 36434
FILL8 21808
FILL16 9749
FILL32 2620
FILL64 2817
636:PDE_ICC2_WARNING: tap/endcap insertion intentionally omitted pending approved masters/rules
~~~

TIEL 是逻辑 tie-low cell，不是 well tap。FILL* 的存在也不能证明 substrate/well tie。该实现没有建立 foundry 要求的 well/substrate contact spacing 与边界封装证据，因此 latch-up 防护未实现/未验证，属于流片阻断项。

### E-A10　分析模式与 derate

完整命令：

~~~bash
cat /tmp/icc2_audit_1785936929/a1_derate_FUNC_WC.rpt
cat /tmp/icc2_audit_1785936929/a1_derate_FUNC_BC.rpt
sed -n '34,50p' flow/local_runs/full_clean_20260804/icc2/reports/icc2/final/final_qor.rpt
awk 'BEGIN{arrival=9.8498; launch=0.8033; slack=0.7430; data=arrival-launch; printf "data_delay=%.4f-%.4f=%.4f ns\n",arrival,launch,data; for(i=3;i<=5;i++){extra=data*i/100; printf "%d%%: extra=%.6f ns, estimated_slack=%.6f ns\n",i,extra,slack-extra}}'
~~~

原始输出片段：

~~~text
Timing derate for corner WC
  Net delay static      1.00      1.00      1.00      1.00      1.00      1.00      1.00      1.00
  Net delay dynamic     1.00      1.00      1.00      1.00      1.00      1.00      1.00      1.00
  Cell delay            1.00      1.00      1.00      1.00      1.00      1.00      1.00      1.00
  Cell check            1.00      1.00      1.00      1.00      1.00      1.00      1.00      1.00

Timing derate for corner BC
  Net delay static      1.00      1.00      1.00      1.00      1.00      1.00      1.00      1.00
  Net delay dynamic     1.00      1.00      1.00      1.00      1.00      1.00      1.00      1.00
  Cell delay            1.00      1.00      1.00      1.00      1.00      1.00      1.00      1.00
  Cell check            1.00      1.00      1.00      1.00      1.00      1.00      1.00      1.00

Signal Integrity Analysis:                 disabled
Timing Window Analysis:                    disabled
Variation Type:                            fixed_derate
Clock Reconvergence Pessimism Removal:     disabled

data_delay=9.8498-0.8033=9.0465 ns
3%: extra=0.271395 ns, estimated_slack=0.471605 ns
4%: extra=0.361860 ns, estimated_slack=0.381140 ns
5%: extra=0.452325 ns, estimated_slack=0.290675 ns
~~~

计算口径为 final_setup_worst_4d.rpt 的 data arrival 9.8498 ns 减 launch clock network 0.8033 ns，得到 9.0465 ns data delay；从原始 slack 0.7430 ns 扣除 3/4/5%。三个简化估算值均为正，但它们不是 OCV/POCV STA，未包含 clock/check/corner 相互作用，不能替代签核。

### E-A11　未执行或未留证据的签核项

完整命令：

~~~bash
for q in PRIMETIME FORMALITY CALIBRE IR_EM GATE_SIM; do case "$q" in PRIMETIME) pat='(^|[ /])(pt_shell|primetime)([ /]|$)|PrimeTime.*Version|read_(parasitics|spef)' ;; FORMALITY) pat='(^|[ /])(fm_shell|formality)([ /]|$)|Formality.*Version' ;; CALIBRE) pat='Calibre.*(DRC|LVS|Antenna)|MGC_HOME.*calibre|PDE_CALIBRE_RUN_START' ;; IR_EM) pat='analyze_power_grid|check_power_grid.*(IR|EM)|RedHawk|Voltus|PrimeRail' ;; GATE_SIM) pat='(^|[ /])(vcs|xrun|vsim|iverilog)([ /]|$)|SDF.*annotat|gate.level simulation' ;; esac; echo "$q"; n=$(find flow -type f \( -name '*.log' -o -name '*.rpt' -o -name '*.out' -o -name '*.console' -o -name '*.console.log' \) -print0 | xargs -0 rg -l -i "$pat" 2>/dev/null | wc -l); echo "matching_retained_execution_files=$n"; done
find flow -type f \( -name '*.log' -o -name '*.rpt' -o -name '*.out' -o -name '*.console' -o -name '*.console.log' \) -print0 | xargs -0 rg -n -i 'analyze_power_grid|check_power_grid.*(IR|EM)|RedHawk|Voltus|PrimeRail' 2>/dev/null | head -30
stat -c '%s %n' flow/local_runs/full_clean_20260804/dc/results/pde_chip_top_safe.sdf flow/local_runs/full_clean_20260804/dc/results/pde_chip_top_safe.svf flow/local_runs/full_clean_20260804/icc2/results/icc2/pde_chip_top_safe.WC.spef.RC_WORST_125.spef flow/local_runs/full_clean_20260804/icc2/results/icc2/pde_chip_top_safe.BC.spef.RC_BEST_0.spef
~~~

原始输出：

~~~text
PRIMETIME
matching_retained_execution_files=0
FORMALITY
matching_retained_execution_files=0
CALIBRE
matching_retained_execution_files=0
IR_EM
matching_retained_execution_files=1
GATE_SIM
matching_retained_execution_files=0
flow/reports/openroad/help_pgterm.log:17:===== HELP analyze_power_grid =====
flow/reports/openroad/help_pgterm.log:18:analyze_power_grid -net net_name [-corner corner] [-error_file error_file]

230838931 flow/local_runs/full_clean_20260804/dc/results/pde_chip_top_safe.sdf
142848 flow/local_runs/full_clean_20260804/dc/results/pde_chip_top_safe.svf
279637133 flow/local_runs/full_clean_20260804/icc2/results/icc2/pde_chip_top_safe.WC.spef.RC_WORST_125.spef
281987265 flow/local_runs/full_clean_20260804/icc2/results/icc2/pde_chip_top_safe.BC.spef.RC_BEST_0.spef
~~~

唯一 IR_EM 命中是帮助文本，不是执行。结论逐项为：PrimeTime post-route SPEF STA、Formality、Calibre full deck/LVS、IR drop/EM、门级仿真均 **没有可审计执行证据**。SPEF/SDF/SVF 只是输入或中间产物，不能替代对应工具的 log/report/pass result。若历史结果被移走，本地无法证明“从未运行”；但当前交付不能据此过签核门。

### E-A12　与 Innovus/HVT 线的可比性

完整命令：

~~~bash
rg --files . | rg -i '(^|/)(innovus|hvt)(/|[^/]*)|innovus|hvt' | sort
awk 'BEGIN{in_c=0} /^COMPONENTS /{decl=$2;in_c=1;next} /^END COMPONENTS/{in_c=0} in_c&&$1=="-"{n++;m[$3]=1} END{for(x in m)u++; printf "declared=%d parsed=%d unique_masters=%d\n",decl,n,u}' flow/local_runs/full_clean_20260804/icc2/results/icc2/pde_chip_top_safe.def
sed -n '20,38p;23950,23972p' flow/local_runs/full_clean_20260804/icc2/reports/icc2/final/final_clock_qor.rpt
~~~

原始输出片段：

~~~text
./flow/innovus/pde_innovus_view.tgz
./flow/innovus/view_design.tcl

declared=270471 parsed=270471 unique_masters=178

### Mode: FUNC, Scenario: FUNC_BC
core_clk                                M,D     23905      6      488   1770.84   1770.84      0.41      0.18         0         0  140349.64
### Mode: FUNC, Scenario: FUNC_WC
core_clk                                M,D     23905      6      488   1770.84   1770.84      0.93      0.46         0         0  140349.64
~~~

本地唯一 Innovus 命名资产已在 E-A6 证明是 ICC2/RVT 查看包，不含 HVT implementation database/report。远端又因 Z2 不可访问，因此 HVT 一列不能独立填写。

## 第三部分：按严重程度排序的问题

### P0 / 流片阻断

1. **【报告显示通过、但检查根本没发生】reset recovery/removal 未形成有效签核。** final setup/hold violation report 写 No paths；删除 false_path 后 rst_n 仍被 TIM-010 判为非 startpoint。补齐 0 ns 输入延迟后，23,905 个 reset endpoint 中 16,226 个 removal 违例，WNS −0.227242 ns、TNS −2715.911528 ns；最差项是 removal。rst_n 还被 NEX-020 跳过寄生提取。

2. **【报告显示通过、但检查根本没发生】antenna 分析被跳过。** final_routes.rpt 同时包含 TOTAL VIOLATIONS=0 与 “No antenna rules defined, Skip antenna analysis”；最终二极管数为 0。T1 的“antenna 干净”被证伪。

3. **tap/endcap 未插入。** PNR 日志明确记录 intentionally omitted，加载 LEF 中也没有候选 master。没有 foundry well/substrate tie spacing 和边界封装证据，latch-up 防护不成立。

4. **foundry signoff 没有可审计通过证据。** Calibre DRC/LVS/Antenna 没有 log/summary/RDB/pass marker；现有 block runner 根本不支持 LVS。ICC2 check_lvs/check_routes 不能替代 Calibre 全 deck。

### P1 / 高严重度

5. **权威版本与双机一致性未建立。** 无 immutable release manifest；同一 full_clean 内有两套哈希不同的 final reports 和两个 GDS；EDAServer 无法解析，远端 checksum 无法取得。

6. **关键签核链缺失。** 没有 PrimeTime+SPEF、Formality、IR/EM、门级仿真的可审计执行证据。

7. **没有实际时序 derate/OCV/POCV。** 所有 derate=1.00，SI/CRPR 均关闭。简化 5% data-only 估算尚有 +0.290675 ns，不构成 OCV 签核。

8. **reset 架构未隔离异步释放。** 网表直接将 rst_n/rst_ni 接到 CDN，没有同步器证据，也没有 reset tree；这是 A1 问题的结构来源。

### P2 / 中严重度

9. **最终 QoR 仍有 2 个 max-transition violation。** final_qor.rpt 的 Nets with Violations=2、Max Trans Violations=2；“全规则干净”不能扩展到所有 design-rule constraints。

10. **NDM 结构完整，但 workspace warning 数量很大。** 2,880 条 warning 中 FRAM-065=989、FRAM-066=256；需要 library/foundry owner 逐类关闭。

11. **snps_no_udev 计算等价性没有 A/B。** wrapper 实际令 dlopen 失败，影响范围是整个进程环境；不能把“只影响 license”当成已证实事实。

12. **工具来源命名易误导。** Innovus 命名 viewer 包实际含 ICC2/RVT 产物，Calibre 默认输入又指向 OpenROAD。当前 final report 未发现混写，但后续人工取数存在 provenance 风险。

13. **GDS 规格陈述错误。** 原始 final GDS 是 129.27 MB/123.28 MiB、178 个厂商 cell，不是约 139 MB/181；几何一致性子项则通过。

## 第四部分：ICC2/RVT 与 Innovus/HVT 对比

| 指标 | ICC2/RVT（本次原始证据） | Innovus/HVT（本次原始证据） | 判定 |
|---|---:|---:|---|
| 单元数 | 111,354 leaf functional cells；270,471 DEF components；178 unique masters | 无法验证 | 两种 ICC2 数字口径不同，不能混用；HVT 无原始 report |
| Die | 875 µm × 875 µm | 无法验证 | HVT 无 DEF |
| 密度 | 57.28% | 无法验证 | HVT 无 utilization report |
| Setup WNS/TNS | +0.7430 ns / 0（当前例外下） | 无法验证 | ICC2 同步路径通过；reset recovery 不在该数字内 |
| Hold WNS/TNS | +0.0004 ns / 0（当前例外下） | 无法验证 | ICC2 reset 诊断另为 −0.227242 ns / −2715.911528 ns、16,226 removal violations |
| 时钟树 | 23,905 sinks；6 levels；488 repeaters；BC/WC max latency 0.41/0.93 ns；skew 0.18/0.46 ns | 无法验证 | HVT 无 clock-tree report |
| rst_n false_path 豁免路径 | 最终 SDC 下无法验证；0 ns 诊断中 23,905 endpoint paths（nworst=1），31,585 paths（nworst=2） | 无法验证 | 未定义共同枚举口径，不能计算可信占比或比较数量级 |

ICC2/RVT 的数值在**本次可访问范围内更可审计**，因为数据库、tool log、final report 和交付物都在本地且能做内存复核。这不等于 ICC2/RVT 更接近流片：A1、A8、A9 与 A11 已给出直接反证。

Innovus/HVT 的题面参考值没有对应原始文件，且 EDAServer 不可达，因此本次不能认定其可信，也不能断言其实现错误。若必须指出当前哪一列“不可信”，则是 **HVT 数字陈述在本次审查中不具备证据资格**；原因是原始来源不可访问，不是因为数值大小本身。

## 第五部分：流片就绪度结论

**结论：不具备流片就绪条件。**

这不是仅由“证据不足”导致的保守结论；已有原始证据直接确认三项阻断事实：

- reset recovery/removal 没有在交付约束下形成有效检查，诊断条件下存在 16,226 条 removal 违例；
- antenna analysis 因无规则被工具明确跳过，且零二极管；
- tap/endcap 被明确省略。

除此之外，Calibre full-deck/LVS、PrimeTime+SPEF、Formality、IR/EM、门级仿真以及两地 checksum 一致性均没有可审计通过证据。即使 ICC2 内部 open/short/route DRC/legality/PG 和当前同步 setup/hold 报告为 0，也不能抵消上述阻断项。

本报告的最终证据边界是：**full_clean_20260804 可作为当前唯一可审计候选版本，但不是已证明的正式权威 release；其流片签核不通过。**
