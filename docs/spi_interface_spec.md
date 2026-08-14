# SPI 配置接口规格(spi_cfg_bridge / pde_chip_top_spi)

版本 draft-1(2026-08-14)。评审通过前不写 RTL。本文所有对现有设计的断言均标注 RTL 行号,行号基于当前 main(`6b7ff3e`)。

## 0. 设计决策摘要

| 决策 | 结论 | 依据 |
|---|---|---|
| 接口形态 | SPI-lite 从机,4 线(SCLK/CS_N/MOSI/MISO),mode 0,40bit 定长帧 | 芯片内部已有验证过的 16bit 寄存器总线(cfg bus),定长帧是它最薄的串行化包装;host 侧任何 MCU/FTDI 原生支持 |
| 时钟策略 | **核时钟过采样**,整芯片保持单时钟域;SCLK 不定义为时钟 | 消除第二时钟域的 CTS/CDC/false_path 签核面;正确性由 §5 的不等式保证 |
| 内核改动 | **零**。`pde_chip_top_safe` 及以下不动,新顶层 `pde_chip_top_spi` = 桥 + safe top 例化 | 保护既有 8 个回归目标与两轮后端结论 |
| 结果读出 | `scan_out/scan_valid/scan_last` 保留为专用引脚,配合**慢时钟读出模式**(§6.3) | scan 流无反压、以核时钟每拍 1 位连续吐出(`pde_chip_top.sv:240-259`),SPI 转发需 6400bit 缓冲,不值得 |

## 1. 引脚表(整芯片 9 根信号)

| 引脚 | 方向 | 功能 | pad 选型建议(tphn28hpcpgv18) | 上下拉 |
|---|---|---|---|---|
| clk | in | 核时钟,台架供给,0~167MHz 任意频率(全静态设计) | PDDW04DGZ(非 Schmitt;最高翻转频率待查 databook,见 IO_SURVEY 待决项) | 下拉 |
| rst_n | in | 异步复位,低有效;释放同步已在片内(`pde_chip_top_safe.sv:60-68`) | PDDW04**S**DGZ(Schmitt) | 下拉(悬空默认保持复位,台架安全) |
| SCLK | in | SPI 时钟,≤ f_core/8(§5) | PDDW04**S**DGZ(Schmitt,抗板级振铃) | 下拉 |
| CS_N | in | SPI 片选,低有效,帧定界 | PDUW04**S**DGZ(Schmitt) | **上拉**(悬空默认未选中) |
| MOSI | in | 主出从入,MSB first | PDDW04**S**DGZ(Schmitt) | 下拉 |
| MISO | out | 从出主入;点对点假设,常驱动(可选 CS_N 门控三态,v1 不做) | PDDW04DGZ 配为输出 | — |
| scan_out | out | 解串行读出数据位 | PDDW04DGZ 配为输出 | — |
| scan_valid | out | 读出有效窗(与 scan_out 同拍采样,`pde_chip_top.sv:255-258`) | PDDW04DGZ 配为输出 | — |
| scan_last | out | 末位单拍脉冲 | PDDW04DGZ 配为输出 | — |

双向 pad 配置约定(databook 9.12 真值表实证,2026-08-14 关闭 D3):**OEN 低有效**——输入用法 OEN=1(驱动器三态,PAD→C 进核)、输出用法 OEN=0(PAD=I 出核);**REN 低有效**——输入 pad REN=0 使能上/下拉,输出 pad REN=1 关拉。接线实现见 `src/pe_array/pde_chip_pads.sv`,已经 vendor 行为模型仿真验证(make spi8pads)。

## 2. 硬性条款(写给台架操作者)

1. **频率上限**:f_SCLK ≤ f_core/8。f_core=167MHz 时 SCLK 额定 10MHz、上限 20MHz;慢时钟读出模式下 f_core 降低,SCLK 必须同比例降。
2. **上电与复位次序**:电源(VDDIO/VDD 按 RN 170A 要求 ramp >10µs)→ clk 起振 → rst_n 拉低保持 ≥4 个 clk 后释放 → 才允许第一笔 SPI 帧。clk 停止时 SPI 无效(过采样逻辑不工作)。
3. **一次复位一题**:求解 FSM 的 S_DONE 无返回 S_IDLE 的路径(`pde_tcu.sv:140-150`),START 与 payload 写在 done 之后被永久拒绝(`pde_chip_top.sv:144`,`writable=!busy&&!done&&!scan_active`)。换题必须翻转 rst_n。
4. **CS_N 帧间必须回高**:每帧恰好 40 个 SCLK 上升沿;帧间 CS_N 高电平 ≥8 个核周期(任何正常 host 天然满足)。

## 3. 帧格式(40bit 定长,mode 0,MSB first)

```
bit:      1        8 9              24 25             40
        ┌──────────┬──────────────────┬─────────────────┐
MOSI    │ CMD[7:0] │    ADDR[15:0]    │   DATA[15:0]    │   CPOL=0, CPHA=0:
        └──────────┴──────────────────┴─────────────────┘   上升沿采样,下降沿换数
MISO      0 ........ 0                 │ RDATA[15:0]     │   (读帧时)
CS_N    ▔\___________________________________________________/▔
```

- **CMD[7]**:1=写,0=读。**CMD[6:0]**:保留,必须为 0,非零整帧丢弃(不发 cfg 事务,为将来命令空间留位)。
- **写帧**:桥在第 40 个上升沿检出后发一笔 cfg 写(`cfg_valid=cfg_write=1`,单拍;总线 `cfg_ready≡1` 恒接受,`pde_chip_top.sv:123`)。
- **读帧**:桥在第 24 个上升沿(ADDR 收齐)后发 cfg 读;读数据固定 1 核拍返回且保持(`pde_chip_top.sv:233-234`),装入输出移位器;RDATA[15] 自第 24 位后的下降沿起在 MISO 上出现,master 在第 25~40 上升沿采样。时间裕量:10MHz 下一个 SCLK 位 = 100ns ≥16 核拍,读返回(约 4 核拍)远早于需要。读帧的 DATA 相位 MOSI 内容被忽略。
- **异常帧**:CS_N 提前回高(<40 沿)→ 整帧静默丢弃,不发事务;>40 沿 → 第 40 沿即已执行,多余沿忽略。桥不设自己的错误寄存器——帧完整性由 host 保证,TB 用 SVA 钉死(§8)。

## 4. 寄存器映射(照录现有 cfg 空间,20×20 配置)

| 地址 | 名称 | 访问 | 说明 |
|---|---|---|---|
| 0x0000 | CONTROL | W(脉冲) | bit0=START(要求 cfg_complete=1)/ bit1=READ(要求 done 且无扫描)/ bit2=清 sticky 错;bit0+bit1 同写=冲突拒绝;[15:3] 非零被 wrapper 原子拒绝并置 wrapper 错(`pde_chip_top_safe.sv:70-82`);读返回恒 0x0000 |
| 0x0001 | STATUS | R | 位表见下 |
| 0x0002/3 | UPD_LO/HI | R | 更新次数 32bit;lo/hi 两次读**非原子**,只在 done 后读 |
| 0x0004/5 | CYC_LO/HI | R | 周期数 32bit;同上;S_READ 期间不计数(`pde_tcu.sv:170`),慢时钟读出不污染该值 |
| 0x0006/7 | NROW/NCOL | R | 参数常量 20/20,可当 ID/discovery 用 |
| 0x1000+i | RED[i] | W/R | i=0..199,残差红 bank 初值(常规灌 0);读返回 shadow,写前读为 X(shadow 无复位,`pde_chip_top.sv:53-54`) |
| 0x2000+i | BLACK[i] | W/R | i=0..199,黑 bank 初值 |
| 0x3000+i | NORTH[i] | W/R | i=0..19,北边界,Q8.7 有符号 |
| 0x3400+i | SOUTH[i] | W/R | i=0..19 |
| 0x3800+i | WEST[i] | W/R | i=0..19 |
| 0x3C00+i | EAST[i] | W/R | i=0..19 |

STATUS 位表(`pde_chip_top.sv:179-181` + wrapper 覆盖 `pde_chip_top_safe.sv:140-146`):

| 位 | 名 | 语义 |
|---|---|---|
| 0 | busy | 求解或扫描进行中(**扫描算 busy**,`pde_tcu.sv:99`) |
| 1 | done | S_DONE;**扫描期间掉低**——轮询"解完"认 bit1,跟踪扫描认 bit5 |
| 2 | converged | 收敛(相对 MAX_UPDATES 截止) |
| 4:3 | prec | 终态精度 00=16b 01=12b 10=8b 11=4b |
| 5 | scan_active | 扫描窗 |
| 6 | cfg_error | sticky;同拍 set 优先于 clear(`pde_chip_top.sv:235-236`);wrapper 错并入此位 |
| 7 | cfg_complete | 480 字(200+200+4×20)全部写过至少一次 |
| 8 | scan_used | 破坏性读已发生(wrapper,`pde_chip_top_safe.sv:131-136`) |

已知陷阱(桥/host 双方都要遵守):写 0x0001-0x0007 是错误而非空操作;非法地址读会正常返回 0x0000 且置错;错误只有一个 sticky 位无逐笔报告——推荐"清错→突发→查 STATUS"的批处理模式;CONTROL 无读回,禁止读改写。

## 5. 过采样 CDC 设计与正确性论证

三路输入(SCLK/CS_N/MOSI)各过 2 级同步器,第 3 级组合出边沿检测(`rise = q2 & ~q3`)。核 6ns、SCLK 额定 10MHz(半周期 50ns ≈ 8.3 核拍)条件下:

1. **不漏沿**:检出一个沿只需高、低各被采到一拍;半周期 ≥4 核拍即可,实际 8.3 拍。由此得硬上限 f_SCLK ≤ f_core/8。
2. **不采错位**:mode 0 下 master 在下降沿换 MOSI,数据在采样沿两侧各稳定半个周期(±50ns);SCLK 与 MOSI 两条同步链的延迟差 ≤1 核拍(6ns)≪ 50ns 保护带。此为时序不等式,非概率论证。
3. **亚稳态**:唯一概率项,与任何跨域方案(含双时钟域 SPI)同源;2 级同步器在 167MHz 采 10MHz 信号的 MTBF 为天文量级,且本设计片内已有同型先例(rst_n 两级同步器)。过采样方案的同步器数量少于双域方案,该维度只优不劣。

桥的复位:`pde_chip_top_safe` 的复位同步器是其内部私有(raw rst_n 唯一负载,`pde_chip_top_safe.sv:56-59`),桥在新顶层内**自带同型 2 级复位同步器**,不与内核共享,内核不动。

## 6. 桥结构与操作序列

### 6.1 桥的组成(预计 ~120 行 RTL)

输入同步器 ×3 → 边沿检测 → 6bit 位计数器 → 40bit 输入移位器 → 16bit 输出移位器 → 帧 FSM(3 态:IDLE=CS 高 / FRAME=计数采位,第 24 沿后若读帧发 cfg 读、第 40 沿发写事务 / WAIT=忽略多余沿等 CS 回高)。MISO 在检出的下降沿更新。

### 6.2 host 标准序列(一题)

1. 上电、clk 起、复位释放(§2.2)
2. 480 个写帧灌配置:RED 0x1000+0..199=0,BLACK 0x2000+0..199=0,四边界 0x3000/3400/3800/3C00+0..19=边界值(顺序任意,重复写允许——valid 位 set-only)
3. 读 STATUS:验 bit7=1、bit6=0(有错则写 CONTROL=0x0004 清后重灌)
4. 写 CONTROL=0x0001(START;内部同拍锁存 shadow 并启动,`pde_chip_top.sv:148-150`)
5. 轮询 STATUS 至 bit1=1(20×20 动态精度典型 ~10µs @167MHz;bit2 报收敛质量)
6. 读 0x0002/3/4/5 四个计数器(性能数据:更新数与周期数)
7. **慢时钟读出**:clk 降至 ~1MHz,SCLK 相应降至 ≤125kHz
8. 写 CONTROL=0x0002(READ);scan_valid 于命令接受次拍拉高,连续 6400 拍每拍 1 位;host 按 §6.3 规则组词
9. 翻转 rst_n,回到第 2 步做下一题

耗时估算:配置 480 帧 @10MHz ≈ 2.5ms;求解 ~1039 拍 @6ns ≈ 6µs;读出 6400 拍 @1MHz ≈ 6.4ms。单题 <10ms。

### 6.3 scan 流数据结构(照录现有 TB 契约)

位序:词内 **LSB first**(TB `scan_shift = {scan_out, scan_shift[15:1]}`,`tb_pde_chip_top.sv:240`);词序:**倒行主序**,首词=格点 399(末行末列),末词=格点 0;格点 idx→(row=idx/20, col=idx%20)。总量 6400 位=400 词。scan_last 与末位同拍单脉冲。scan_out/scan_valid 同沿采样(无相对延迟,`sol_acc.sv:48`)。

## 7. SDC 约束写法(阶段 C 落地)

- 不给 SCLK/CS_N/MOSI 定义时钟;三根输入 pad→首级同步器触发器段落 `set_max_delay 3.0`(把 §5.2 的"延迟差 ≤1 拍"变成 STA 检查项),并 `set_false_path` 掐掉其到功能逻辑的伪路径分析
- 首级同步器对加 `size_only`/保持相邻摆放的物理约束(ICC2 阶段)
- MISO 输出:同步域到端口 `set_max_delay`(宽松,10MHz 半周期 50ns);scan 三根按 clk 常规 `set_output_delay`(慢时钟读出模式裕量巨大)
- 时钟结构不变:全芯片仍只有 clk 一棵树,现有 SDC 其余条目原样沿用

## 8. 验证计划(阶段 B 交付,全绿为过关判据)

1. **新 TB** `tb_pde_chip_top_spi`:SPI master BFM(task 级:`spi_write(addr,data)` / `spi_read(addr,rdata)`),SCLK 与 clk **相位随机 + 逐沿抖动**;8×8 与 20×20 全流程(§6.2 九步)走 SPI 口,解出网格经既有 `ref/check_golden.py` 逐点整数比对
2. **频率扫描**:SCLK = 10/16/20MHz 必须全绿,30/40MHz 找到破坏点——证明余量实测而非纸面
3. **SVA**:物理 SCLK 上升沿(CS 低期间)与桥检出沿一一对应;每写帧恰好 1 个 cfg_valid 脉冲;位计数器不越 40
4. **异常路径**:短帧丢弃(无 cfg_valid)、CMD 保留位非零丢弃、经 SPI 写非法地址→STATUS bit6 置起→0x0004 清除
5. **时钟切换排练**:DONE 后仿真内把 clk 周期 6ns→60ns(SCLK 同比例降)完成读出,证明变频操作安全(台架用更大比例,原理相同)
6. **回归保护**:既有 8 个 make 目标(pe/top8×3/top20/chip8/chip20/chipsafe)保持全绿,内核零改动的机械验证
7. (阶段 D)布线后 SDF 门级仿真过一遍 §6.2 序列

## 9. 开放项(评审时定)

1. MISO 是否要 CS_N 门控三态(多从共享总线才需要;v1 建议常驱动)
2. 慢时钟读出的台架换挡时机:本 spec 定为"DONE 之后、READ 命令之前",换挡期间 SPI 静默 ≥8 个新周期
3. ~~pad 驱动强度~~ 已关闭(2026-08-14):databook 实测 4mA 输出 TP ≈1.2ns+0.055ns/pF,20pF 负载 ≈2.3ns,对 MISO ≤20MHz 与慢时钟读出裕量巨大;台架上电条款从 databook 表 2.1 取值——VDD ramp ≥50µs、VDDIO ramp ≥100µs(slew 上限 0.018V/µs,比 RN 的 10µs 更严)
