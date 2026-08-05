# 给 2026-08-02 旧 NDM 流出的 ICC2 GDS 补齐厂商标准单元几何。
#
# 背景：ICC2 write_gds 出来的版图布线和通孔都是完整的（$$VIA23 等 47 万次放置，
# 与 DEF 里的引用数一一对应），标准单元也都正确摆放，唯独缺单元内部几何 ——
# 旧建库先 read_lef、后 read_gds，855 个同名 physical block 触发 LM-058，工具
# 保留 LEF frame 而丢弃 GDS layout。新 ref_rebuilt NDM 已修复，流出的 GDS 不需要
# 再运行本脚本；本脚本仅用于复现/处理旧结果。
#
# 为什么不走 fdi2gds：那条路从 DEF 出发，而 ICC2 写的 DEF 用的是技术库里的通孔名
# （VIA12/VIA23/VIA12_HV…），LEF 和 DEF 的 VIAS 段都没定义，fdi2gds 会把
# 上百万个通孔连同布线整段丢弃（"The routing for this net was ignored"），
# 金属与栅极断开，天线检查会得到虚假的全零结果。
#
#   klayout -b -r merge_gds.py -rd design=<icc2_1000dbu.gds> -rd cells=<tcbn65lp.gds> -rd outp=<merged.gds>

import pya

design = globals()["design"]
cells = globals()["cells"]
outp = globals()["outp"]

ly = pya.Layout()
ly.read(design)
print("DESIGN dbu=%.6g cells=%d top=%s" % (ly.dbu, ly.cells(), ly.top_cell().name))

lib = pya.Layout()
lib.read(cells)
print("CELLLIB dbu=%.6g cells=%d" % (lib.dbu, lib.cells()))

if abs(ly.dbu - lib.dbu) > 1e-12:
    print("FATAL dbu 不一致，合并会缩放几何：design=%g lib=%g" % (ly.dbu, lib.dbu))
    raise SystemExit(1)

# 找出"被引用但没有几何、也没有子引用"的空壳单元
ghosts = []
for ci in ly.each_cell():
    if ci.is_empty():
        ghosts.append(ci.name)
print("GHOST_BEFORE %d" % len(ghosts))

filled = 0
missing = []
for name in ghosts:
    tgt = ly.cell(ly.cell_by_name(name))
    src_id = lib.cell_by_name(name) if lib.has_cell(name) else None
    if src_id is None:
        missing.append(name)
        continue
    tgt.copy_tree(lib.cell(src_id))
    filled += 1
print("FILLED %d" % filled)
print("STILL_MISSING %d" % len(missing))
for m in missing[:20]:
    print("  MISSING %s" % m)

# 复查
still = [ci.name for ci in ly.each_cell() if ci.is_empty()]
print("GHOST_AFTER %d" % len(still))
for s in still[:20]:
    print("  GHOST %s" % s)

ly.write(outp)
print("WROTE %s" % outp)
print("RESULT %s" % ("OK" if len(still) == 0 else "INCOMPLETE"))
