# 流程名词与脚本导读(28nm 全链路)

面向读者:需要向老师解释"每个脚本在做什么、每个名词是什么意思"的本项目学生。范围:TSMC 28nm HPC+ 线的综合(DC)→ 布局布线(ICC2,s01–s07b)→ 签核(PT + Calibre)。每一节都给出对应文件路径,建议对照源码阅读;运行记录见 flow/ 下各 `*_2026-*.md`。

## 1. 全链路一页总览

数据流:RTL(src/)+ 时序约束 → **DC 综合**产出门级网表 `.v` 与约束 `.sdc` → **ICC2** 读入网表与工艺库,经布图、布局、时钟树、布线、修复,产出版图数据库(NDM design library)与交付六件套:GDS(版图)、DEF(物理网表)、postroute.v(布线后网表)、SPEF×2(寄生)、SDF(延迟)→ **签核**用独立工具重验:PT 做静态时序(读 postroute.v + SDC + SPEF),Calibre 做物理验证(读 GDS + 由网表转换的 SPICE 源)。

工艺数据从哪来:标准单元库 tcbn28hpcplusbwp40p140(时序用 .db/NLDM,物理用编好的 NDM),GPIO 库 tphn28hpcpgv18,bond pad 库 tpbn28v,RC 抽取表 TLUplus,PRTF(工艺参考流程包,含 antenna 规则与 GDS 输出层映射表),Calibre 规则 deck(DRC/ANT/LVS/装配)。

两个顶层:`pde_chip_top_safe` 是 core-only 顶层(无 pad),`pde_chip_pads` 是整芯片顶层(SPI 接口 + 9 信号 pad + 21 IO pad 环 + bond pad)。所有脚本用环境变量 `PDE_TOP` 切换,整芯片分支以 `IS_CHIP` 条件化,core 路径行为不变——这是"新增功能不破坏已验证路径"的工程习惯。

## 2. 脚本逐个导读

### 综合:flow/dc28/synth28.tcl(runner:run_dc28.sh)

读 RTL 与库 → `create_clock` 建立时钟约束(6ns)→ `compile_ultra -no_autoungroup` 综合(映射+优化一体,`-no_autoungroup` 保持模块层次不被打散,便于后续按层次定位)→ `write_file`(网表)+ `write_sdc` + `write_sdf`。pad 级顶层时,GPIO 库只参与链接(link-only,不许 DC 优化 pad),pad 实例 `dont_touch`,边界约束从"核内视角"切到"板级视角"(输入驱动/输出负载改由 pad 承担)。

### 公共层:flow/icc2_28nm/pnr28_common.tcl 与 run_stage.sh

`pnr28_common.tcl` 是所有阶段共享的头文件:环境变量解析(顶层、库路径、输出目录)、`IS_CHIP` 判定、PG 引脚批量连接助手 `connect_named_pg_pins`、芯片级 LVS 计数过滤器 `chip_lvs_counts`(见 §3 豁免)。`run_stage.sh` 在 distrobox 容器内起 `icc2_shell -batch` 跑单个阶段,成功判据不是退出码而是日志里的 `PDE28_STAGE_DONE` 标记——工具崩溃时退出码不可靠,产物标记才可靠。

### s01_setup.tcl:建库与 MMMC

`create_lib` 建设计库(挂标准单元 NDM;整芯片再挂 IO/bond NDM)→ `read_verilog` 读网表 → 建 **MMMC**(多模多角):`create_corner` 两个工艺角(WC=ssg 慢角 0.9V/−40°C、BC=ffg 快角 0.99V/−40°C),`create_scenario` 两个场景(FUNC_WC 管 setup,FUNC_BC 管 hold),`read_parasitic_tech` 挂 TLU+ 的 RC_WORST/RC_BEST → `set_app_options` 定布线层窗口(信号 M1–M6,M8/M9 留给电源)→ source PRTF 的 antenna 规则。整芯片分支:pad 实例 `set_dont_touch` 并断言 9 只信号 pad 都在。

### s02_floorplan.tcl / s02_floorplan_chip.tcl:布图

core 版:`initialize_floorplan` 定方形 core(利用率 0.70)→ 摆引脚 → boundary/tap cell → PG:M9 横 + M8 竖的 1.6µm 电源环、M1 follow-pin 电源轨、VDD/VSS 物理端子。芯片版(新文件,core 版不动):die 精确 685×685(`-boundary` 多边形,`-side_length` 会吸附 site 网格造成 684.96)→ 按环表显式坐标摆 21 pad + 4 corner(带 bbox 断言防旋转语义歧义)→ 逐缝隙 IO guide + `create_io_filler_cells` 填 filler(整条 guide 会把 filler 铺到 pad 上,这是首链 32 个短路的教训)→ 环连续性审计(缝隙+重叠双检)→ PG 环/轨照抄 core 版 → 四只核电源 pad 用 1.6µm M8/M9 细指 strap 接到环(粗 strap 的胖 via 表 tf 里没有,细指+自动 via 是唯一通路)→ 9 个 PAD_* 端口在 M7 建 terminal。

### s03_place.tcl:布局

`check_design -checks pre_placement_stage` 前置体检 → `place_opt`:全局布局、合法化、preCTS 时序优化一体。此时时钟还是 ideal(理想网络,不计时钟树延迟),所以只有 setup 有意义,hold 要等时钟树建好才真实。

### s04_cts.tcl:时钟树综合(CTS)

`clock_opt`:建时钟树(clock tree synthesis)+ postCTS 优化。时钟从 ideal 变 **propagated**(真实传播延迟),此后 skew/latency 进入所有时序计算,hold 检查开始有效。本项目在这里做时钟与复位树普查(`report_reset_tree`:复位扇出锥里有多少缓冲/反相器),并强制报告 recovery/removal(异步复位的"恢复/移除"检查,DC 与 PT 的开关语义不同,是 G.3 教训)。

### s05_route.tcl + s05b_antenna_fix.tcl:布线与天线修复

`route_auto`(全局+轨道+详细布线)→ `route_opt`(布线后第一轮优化)→ `check_routes -open_net -drc -antenna` 检查。s05b 存在的原因:这个版本的 ICC2 里 antenna 规则**不跨会话持久**(save_lib 再 open_lib 后 report_antenna_rules 为空),所以要重新 source 规则再 `route_detail -incremental true`,让天线检查与二极管插入真正在成品布线上执行。

### s06_postroute.tcl + s06b_open_fix.tcl:布线后收敛

s06 用"加压再撤压"手法收 hold:临时 `set_clock_uncertainty -hold 0.10/0.05`(额外悲观,不是放松)驱动 `route_opt` 留出余量,然后撤掉;再用 `route_detail -incremental` 迭代把 DRC 收零(首链 route_opt 留下 113 DRC + 73 短路直到 s07 才暴露,是 R2 教训:每级要有自己的 check_routes 门槛)。s06b 是开路收尾:`route_eco -open_net_driven` 修 check_lvs 才统计得到的开路;整芯片分支先 `connect_named_pg_pins`(CTS/hold 修复新插的单元 PG 引脚还没绑网,否则 check_lvs 把引脚压轨全记成短路)。

### s07_finish.tcl(+ s07b_repair.tcl):硬门与交付

插标准单元 filler → 全套报告 → **六硬门**:setup 违例=0、hold 违例=0、几何 DRC=0、antenna=0、开路=0、短路=0,任何一项不为零就报错退出、不写 GDS(65nm 的教训:绝不带着时序违例流 GDS)。过门后才插 21 只 bond pad(其 CUP 版图与宿主 pad 合法重叠,先插会被 check_lvs 记 10 万+ 假短路)→ 写交付六件套。s07b 是首链失败后的修复脚本(M2 短路、PG 端子),保留作历史记录。

### 签核:flow/signoff28/pt_sta28.tcl(+ run_pt28.sh)与 Calibre

PT:每角一个会话(WC 管 setup/recovery/DRV,BC 管 hold/removal),读 postroute.v + SDC + 对应 SPEF,`remove_ideal_network` 释放时钟源端口(按时钟定义推导端口名,pad 顶层是 PAD_CLK)+ `set_propagated_clock`,OCV+CRPR 口径与 ICC2 对齐。Calibre 在 EDAServer:DRC(逻辑 deck,对代工厂 IP 用 EXCLUDE CELL)、ANT、装配 deck(CN28_WIRE_BOND,管 bond pad 排布)、LVS(v2lvs 把网表转 SPICE 源再与 GDS 提取结果比对)。签核记录见 flow/SIGNOFF_28NM_2026-08-07.md 与 flow/SIGNOFF_CHIP_28NM_2026-08-15.md。

## 3. 名词表

### 时序类

- **setup / hold**:触发器对数据的两个时间窗要求——时钟沿前数据须稳定(setup,路径太慢则违例)、时钟沿后数据须保持(hold,路径太快则违例)。setup 靠慢角查、hold 靠快角查,所以要 MMMC 两个场景。
- **WNS / TNS / NVP**:最差负裕量、负裕量总和、违例路径数。三个都为零才算时序干净。
- **recovery / removal**:异步复位撤除相对时钟沿的 setup/hold 类似物。本项目复位经两级同步器,这两项检查覆盖同步器之后的异步清零脚。
- **CTS(时钟树综合)**:把一根时钟从源端通过缓冲树分发到几万个触发器,控制 skew(叶子间到达差)与 latency(源到叶延迟)。CTS 之前时钟按 ideal(零延迟理想网络)处理,之后按 propagated(真实延迟)处理——签核时忘记释放 ideal 会漏查整棵时钟树,这正是 pt_sta28.tcl 里那处硬编码 `clk` 的隐患。
- **OCV / AOCV / CRPR**:片上偏差建模。OCV 给 launch/capture 路径不同快慢假设;AOCV 按路径深度与距离查表给 derate(浅路径更悲观);CRPR 扣除时钟公共段被重复计算的悲观。本项目基线 OCV+CRPR 不加 derate,与 ICC2 口径可比;AOCV 表是库交付的 .aocvm(方向已裁掉)。
- **DRV(max_transition / max_capacitance)**:约束类"设计规则"——信号沿不能太缓、节点电容不能太大,否则延迟模型失真且有 SI 风险。PT 在 WC 角随 setup 一起查。
- **SDF**:标注每条弧延迟的交换格式,给门级仿真用;SDC 是约束(时钟、IO 延迟、例外),两者别混。

### 库与模型类

- **NLDM / CCS**:标准单元时序模型。NLDM 是查表(输入沿×负载→延迟),CCS 是电流源模型(更精确,文件更大)。.lib 是文本,.db 是编译后二进制,DC/PT 吃 .db。
- **NDM**:ICC2 的库/设计容器(目录形式),由 lm_shell 把 .db(时序)+ LEF 或 GDS(物理)编译而成。设计本身也存成 NDM design library,分阶段脚本每级 open/save 的就是它。
- **LEF**:物理抽象——单元尺寸、引脚形状、阻挡层,不含晶体管细节。本项目给 bond pad 手写过最小 LEF(CLASS COVER、无 OBS,因为 OBS 会挡核电源 strap)。
- **TLUplus**:RC 抽取查找表,按角(rcworst/rcbest)给互连电阻电容,ICC2 布线评估与 SPEF 导出都靠它。
- **SPEF**:布线后互连寄生(R/C 网络)的标准交换格式,ICC2 `write_parasitics` 导出、PT `read_parasitics` 读入,文件名后缀带寄生角与温度(如 RC_WORST_-40)。
- **MMMC / corner / scenario**:多模多角框架。corner=工艺电压温度组合 + RC 角;mode=一套约束;scenario=mode×corner 并声明查什么(setup 或 hold)。

### 布图与物理类

- **site / row**:布局的格点单位与行。`-site_def core` 必须显式指定,因为 NDM 里同时存了 tf 自带的 unit tile 与标准单元 site。
- **tap cell**:阱接触单元,按间隔阵列摆放,把 N 阱/P 衬底接到电源,防 **LUP(闩锁,latch-up)**——寄生双极管对被触发后在电源与地之间形成低阻通路,轻则功能翻转重则烧毁;衬底/阱电位钉住就不易触发。Calibre deck 里有一族 LUP 规则,R1 已全零。
- **boundary cell(endcap)**:行两端的封边单元,保证边界处阱/注入的连续性与光刻环境一致。
- **PG ring / follow-pin rail / strap**:电源环(粗金属绕 core)、跟随单元电源引脚的 M1 轨、连接环与轨(或环与 pad)的竖直/水平带。follow-pin 意思是轨的位置由单元行的 VDD/VSS 引脚位置决定。
- **utilization(利用率)**:标准单元面积 / core 面积。本项目 0.70(R2 收紧,互连主导时序时小盒子既省面积又利时序);太高会拥塞布不通。
- **congestion(拥塞)**:局部布线需求超过轨道供给。布局阶段用 GRC 图评估。

### 布线与制造类

- **天线效应(antenna effect)**:制造中逐层刻蚀时,已成形的长金属像天线一样收集等离子体电荷,电荷经唯一放电路径——栅氧——泄放,可能击伤栅氧。修法:换层跳线打断长金属,或在网上挂反偏**天线二极管**提供放电旁路。ICC2 按 PRTF 规则算每个栅的天线比并自动插二极管;Calibre ANT deck 独立重验(109 规则)。
- **几何 DRC**:间距/宽度/包络/密度等制造规则。ICC2 的 check_routes 查的是布线器视角的子集,签核以 Calibre 全 deck(2,707 规则)为准。
- **dummy fill / CMP**:化学机械抛光要求各层金属/OD/PO 密度均匀,不足处要填虚设图形。本项目未做 fill(教师裁定),密度族违例(DN 规则)作为记录在案的豁免组保留——这也是"本版不可直接流片"的唯一制造性原因。
- **GDS / dbu / datatype**:版图交换格式;dbu 是数据库最小单位(本项目 0.1nm,精度 10000/µm,Calibre deck 须同步 PRECISION);layer:datatype 是层号+子类型,TSMC 4X2Y2R 约定 Y/R 层金属与 via 用 datatype 20/80,datatype 0 是 deck 的 NOUSE(不检查)层——vendor IO IP 内部就用 dt0 编码,签核对 IP 要用 EXCLUDE CELL(DRC)/LVS BOX(LVS)方法学,详见 SIGNOFF_CHIP 记录 §3。

### 签核与 IO 环类

- **STA(静态时序分析)**:不打激励、按图遍历所有路径求最差情形。PT 是签核 STA 的事实标准,和 ICC2 内建时序器互为独立证据。
- **LVS**:版图与网表一致性。layout 侧从 GDS 提取器件与连接,source 侧由 **v2lvs** 把 Verilog 网表+库 SPICE(.spi)转成 SPICE;比对器件数、网络、端口。物理-only 单元(filler/bond pad)用空 subckt + `LVS FILTER` 处理;端口靠版图上的 text 标注认名。
- **pad / IO 环**:GPIO 单元(信号 pad 带电平转换与 ESD,电源 pad 供电),沿 die 四边成环,单元间靠贴边(abutment)把五条总线连续起来:VDD/VSS(核电源)、**VDDPST/VSSPST**(IO 后级电源,1.8V 域)、**POC**(power-on-control,上电时序控制信号)。PVSS3 是唯一切断 VSSPST 总线的单元,用于 ESD 域隔离。
- **ESD**:静电放电防护。pad 内的箝位管与二极管把静电能量导到电源轨,要求每个总线分段都有供电 pad 覆盖——这就是环表设计时"数字 IO 与 corner 之间必隔 PVSS2/3"一类规则的来源。
- **CUP / bond pad**:circuit-under-pad,键合盘直接叠在 pad 电路上方(tpbn28v 库),内建 via 阵列把 M8/M9 厚板接到 pad 的落点条。装配正确性由专用 deck(CN28_WIRE_BOND)判定,逻辑 deck 不裁复合区。

备注:AOCV 加严、dummy fill、5ns 重收敛三个方向已由教师裁定不做,名词表仍收录相关概念以备提问。

## 4. 答辩速答(十问)

1. 为什么分两个场景?——setup 在慢角最差、hold 在快角最差,一套场景查不全。
2. 为什么 CTS 之后 hold 才有意义?——hold 违例主要由时钟 skew 造成,ideal 时钟下 skew 为零。
3. tap cell 防什么?——闩锁(LUP):钉住阱/衬底电位,抬高寄生双极管触发门槛。
4. 天线二极管为什么能修天线违例?——给积累电荷提供不经栅氧的放电旁路。
5. 为什么 s05b 要重新 source 天线规则?——该版 ICC2 的天线规则不随库持久化,新会话是空的。
6. s06 的 +50ps hold uncertainty 是放松吗?——相反,是临时加压让优化器留余量,收敛后撤掉。
7. SPEF 和 SDF 的区别?——SPEF 是寄生 RC(给 STA 算延迟),SDF 是算好的延迟(给门级仿真)。
8. 六硬门是哪六个?——setup、hold、几何 DRC、antenna、开路、短路,全零才写 GDS。
9. bond pad 为什么最后才插?——它与宿主 pad 的合法重叠会被连通性检查记成海量假短路,先过电气硬门再插。
10. 签核为什么不用 ICC2 自己的检查?——实现工具与验证工具要独立:PT 与 Calibre 是另一套引擎、另一套规则来源,这才构成签核证据。
