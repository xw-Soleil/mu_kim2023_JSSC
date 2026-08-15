# 整芯片签核记录 — PT + Calibre DRC/ANT/WB/LVS(pde_chip_pads,2026-08-15)

对象:`flow/local_runs/icc2_28nm_chip_20260815c/results/pde_chip_pads.gds`(685×685µm,21 IO pad + 21 CUP bond pad,六 ICC2 硬门全零,dbu 0.1nm)。执行机 EDAServer(PT O-2018.06-SP1,Calibre v2015.2_36.27),权威工作树 `EDAServer:/home/sxw/PDE/pde28_signoff/20260815_chip/`,本地镜像与逐文件 sha256 见同目录 `signoff/MANIFEST.md`、`signoff/derived_inputs.sha256`。体例先证据后判定;所有 deck 改动仅在工作副本,diff 归档 `signoff/calibre/runset_vs_20260807.diff` 及各运行目录。

## 1. 结论一览

| 项 | 结果 | 判定 |
|---|---|---|
| PT WC(setup+recovery+DRV) | WNS=0 TNS=0 NVP=0,24,016 端点 100% 覆盖 | 通过 |
| PT BC(hold+removal) | WNS=0 TNS=0 NVP=0 | 通过 |
| Calibre ANT(109 规则) | 0 | 通过 |
| Calibre 逻辑 DRC(IP 排除法,2,707 规则) | 1,031 项,全部归入三个记录在案的豁免组(§4),间距/宽度/via/井等制造规则 0 | 有条件通过(与 R1 同口径:无 dummy fill 不可直接流片,fill 已由教师明确裁掉) |
| Calibre CN28_WIRE_BOND(bond pad 装配 deck,首次激活) | **0** | 通过 |
| Calibre LVS | 器件 100% 配对(MOS 1,583,130/1,583,130 变换后全配),9 信号端口全对;PG 域处置见 §5 | 见 §5 |

ICC2 侧两类豁免的仲裁结果:"opens" 主体闭环(VDD/VSS 主网各 ~132 万连接、核↔pad 贯通,即 strap→bond 厚板→pad strip 的路径被 Calibre 证实导通);hairline "shorts" 闭环(逻辑 DRC 在环区零短路类违例,WB deck 全零)。

## 2. PT(Stage G′)

`flow/signoff28/pt_sta28.tcl` 本轮参数化(PDE_TOP 驱动、IS_CHIP 分支加 IO NLDM 两角、PAD50GU 黑盒断言限定 LNK-005/LNK-043 且仅允许 PAD50GU、时钟 ideal 释放改为按时钟源端口推导——原硬编码 `clk` 带 `-quiet`,在 pad 顶层会静默漏掉 PAD_CLK 使时钟网络保持 ideal,属隐蔽正确性缺陷,已修)。老顶层路径逐字不变。两角报告 `signoff/pt/reports/`;时钟路径实测经 `u_pad_clk` PAD→C 弧(0.59ns pad 延迟入网);untested 5 端点 = 复位同步器 D 脚 constant-disabled SDF 条件检查(前轮同类)。AOCV 遍未跑(教师已裁掉该方向)。

## 3. DRC 洪水的根因链(全部实验可复现,细节脚本/坐标见运行目录)

首跑(FULL_CHIP+WIRE_BOND 开、AP_28K 关,LAYOUT=整芯片)766,315 项,其中 VIA5/VIA6 的 S.1/S.2/W.1/EN 约 75 万。定位实验序列:① vendor PAD50GU 单体(1nm 域)全零;② 从芯片 GDS 抽出的 PAD50GU(0.1nm 域)全零——排除精度域;③ 真实子集 bond pad+宿主 frame 复现 263,823 ≈ 全芯片 263,851;④ 去 bond pad 的整芯片仍 276,766——bond pad 非充分条件;⑤ KLayout 显微:落点条区两套 via 阵列(IO pad 0.05µm/0.17 栅距 vs bond pad 0.1µm/0.23 栅距)交错且 10µm² 内 70 处部分重叠,W.1 的 96,362 项即融并畸形;⑥ vendor IO GDS 的 via/M6/M7 datatype 全为 0 = deck 的 NOUSE 层(TSMC 逻辑 deck 对其自家 IO IP 内部原生不可见),我们 write_gds 经 PRTF map 归一化为 dt20/80 才使其被检查。结论:洪水 = 代工厂已验证 IP 内部被非预期点亮,非本设计几何错误。

处置(业界标准 IP 方法学):逻辑 deck 工作副本加 16 条 `EXCLUDE CELL`(15 IO master + PAD50GU),bond/pad 复合叠层交由 TSMC 专用装配 deck `CN28_WIRE_BOND_9M_4X2Y2R.15a`(T-N28-CL-DR-017 v1.5a,取自 iPDK 交付包,开关 PITCH_50_SINGLE+HALF_NODE,PRECISION 10000/RESOLUTION 50)核查——后者 **0 违例**,即 pad 节距、AP/CB 开窗、bond 叠层全部符合装配规则(D5/D6 首次激活即通过)。

## 4. 逻辑 DRC 残余 1,031 项的豁免组

1. **无 dummy fill 族(R1 同根,教师已裁掉 fill)**:M1-M5.DN.6=539、M2-M9.DN.1=8、Mx.DN.7=4、OD/PO/SSD.DN 族=6、DM1-DM9.R.1/DOD/DPO.R.1=11、SR_D*.DN/R=6、OD.S.14=70(样本坐标 x≈75.05 竖带 = IO 环与 core 之间空白带,与 R1 的 die 边带同性质)。
2. **警示类(非制造规则)**:MATCH.WARN.1=178 与 IO_CONNECT_CORE_NET_VOLTAGE_IS_CORE:WARNING1=178(chip 级提示)、DIODMY_L:WARNING=1;MOM.R.2=1(规则原文:芯片内无 MOM 单元即可豁免——本设计无 MOM)。
3. **PO.R.19 浮栅=30**:规则仅整芯片模式激活(R1 未跑过);抽样定位全部落在 DFCNQD1/DFSNQD1 标准单元内部(如 (140.16,305.18)、(278.06,308.77)),网表零空引脚(`( )` 计 0),属标准单元内部结构在 whole-chip 浮栅扫描下的已知报出;标准单元为代工厂已验证 IP,与 §3 同口径记录。

除上述三组外,全部间距/宽度/包络/via/井/LUP 规则为 0。

## 5. LVS(Stage H′)

源网表:v2lvs(核库 110a .spi + IO 库 110a .spi + 空 subckt(PFILLER*/PCORNER_G/PAD50GU,引脚照抄网表)+ deck 配套 `source.added` 器件定义 162 条),50 条大小写重名告警与 R1 同类(CASE=YES 下无害)。runset 副本增补(逐字见 diff):37;20→M7 端口 text 映射(J.1 同款成对写法,借层 896)、7 条 `LVS FILTER ... SOURCE OPEN`(物理-only 单元)。

**全器件比对(lvs_txt 运行)**:变换后 MOS 1,583,130/1,583,130 全配,9 信号端口全对;残余差异全部聚焦 PG/ESD 域:VDD/VSS 主网两侧各 ~131.9 万连接仅差 ~761 连接,全部位于电源 pad(PVDD1/PVDD2/PVDD2POC/PVSS1)内部器件的 bulk/source/drain 与 ESD 二极管端子。根因链:vendor .spi 无 .GLOBAL(0 条),源侧连通全靠 subckt 引脚;而我们流出的 GDS 在 write_gds 时有 11 个 vendor 标注层(189/191-198/250/251,GDS-045 记录在 s07 日志)因 PRTF map 无对应行而被丢弃,IO pad 内部(含 1.8V/HIA 器件区)在流出物中的复制不完整;加之 VSSPST 总线按设计被 4 只 PVSS3 切段(其 .spi 引脚表无 VSSPST,为五总线中唯一切断者),源侧单网 vs 版图弧段天然不一致。PG 网命名用标注 text 注入副本 `pde_chip_pads_lvstext2.gds`(133/134/137/138 Mx_PIN 层,7 条,VDD/VSS 锚在本设计 create_pg_strap 指条上,坐标逐条对 LEF 总线几何/strap 实测核准;掩膜层零改动,sha256 入册)。

**黑盒对照(lvs_box 运行)**:15 个 IO master 以 `LVS BOX` 黑盒比对,判定形态与全器件版一致——黑盒消不掉"网表单网 vs 环形分段"的建模差,故以全器件版为主证据。**LVS 终判:INCORRECT 判定如实保留,但全部差异类均有具名根因与证据,零未解释项**:① VDD/VSS 主网 761 连接差 = IP 内部复制不完整(11 个被丢弃的 vendor 层);② VDDPST/VSSPST/POC = 网表把环总线建成单网,而物理环按 TSMC IO 架构分段(PVSS3 为五总线中唯一切断 VSSPST 者,且每弧段两端均有 PVSS3/PVSS2 供电,ESD 供电覆盖成立——依据引脚表证据与 TSMC 命名惯例,databook 最终确认列入待办);③ 每 pad ESD 器件岛为同根。这属网表建模演进项(下一轮),非版图缺陷。

## 6. ICC2 豁免仲裁闭环

1. ICC2 check_lvs "opens"(VDD/VSS/VSSPST 等五 PG 网):Calibre 全器件比对证实 VDD/VSS 主网核↔pad 单网贯通(strap 指条→bond 厚板→pad strip 路径真实导通,~132 万连接两侧仅差 pad 内部 IP 复制类 761 连接);VSSPST 分段为 PVSS3 设计行为。ICC2 侧该豁免口径成立。
2. ICC2 hairline "shorts"(160 条环单元贴边线):逻辑 DRC(IP 排除后)短路/间距类制造规则 0,WB deck 0。豁免口径成立。
3. bond pad 后置插入(s07 硬门后)的方法学得到印证:逻辑 deck 本就不裁 CUP 复合区(两套 via 阵列栅距 0.23/0.17 不可通约,任意对位必交叠),装配正确性由 WIRE_BOND 专用 deck 判定,而其结果为全零。

## 7. 工具教训(本轮新增)

- TSMC 4X2Y2R 的 GDS datatype 约定:Y/R 层金属与 via 用 dt20/80,dt0 是 deck 的 NOUSE("datatype check")层;vendor IO IP 内部即以 dt0 编码从而对逻辑 deck 不可见——经任何会归一化 datatype 的流出路径(如 PRTF map)都会"点亮"IP 内部,签核必须配 EXCLUDE CELL/LVS BOX 的 IP 方法学。
- write_gds 的 GDS-045(层无映射丢弃)警告不可轻放:丢的 11 个 vendor 层使 IO pad 内部在流出物中不完整,直接表现为 LVS 的 pad 内部岛。
- Calibre 该版 `EXCLUDE CELL`/`LVS BOX`/`LVS FILTER` 追加须放在 `tvf::VERBATIM { }` 内(deck 为 TVF 语境),裸 SVRF 行会被 Tcl 解释器报 "invalid command name ://"。
- KLayout 批处理坑:`Layout.clip` 生成的变体单元名与切边伪影会污染对照实验;`Instance` 删除要用收集后 `.delete()`,`delete_cell_rec` 会连带子树;对照实验前必须复核对照物的平铺形状数(本轮两个"干净对照"均曾因内容丢失而失效)。
- Calibre query server(`calibre -query svdb`)可批量取网层组成/引脚/xref,是无 GUI 环境下替代 RVE 的有效手段。

## 8. 待办(下一轮)

- 流出物完整化:为 11 个被丢弃的 vendor 层扩展 write_gds map(或 IO IP 走引用合并流),消除 LVS 的 IP 复制类差异。
- 网表建模演进:环总线按物理弧段建模(VSSPST 分段、每 pad ESD 岛)或采用 vendor 推荐的 pad frame netlist,冲击 LVS CORRECT;PVSS3/PVSS2 的 ESD 供电覆盖对 databook 做最终确认。
- PG text 正式化:s07 出流程内置五 PG 网端口 text(替代签核侧标注注入)。
- dummy fill 维持不做(教师裁定);若将来恢复流片路径须先补 fill 再重验密度族。
- 流程名词导读文档(`docs/`,交付前过 remove-chinese-ai-tics);R3 报告与 tag。
