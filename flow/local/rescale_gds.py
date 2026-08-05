# 把 ICC2 写出的 GDS 从 0.1nm 栅格(10000 dbu/um)转成 1nm 栅格(1000 dbu/um)。
#
# 为什么要转：TSMC 的 Calibre 天线 deck 里写死 PRECISION 1000，layout 比它细就报
#   "Rule file precision 1000 is not consistent with database precision 10000"
# 改 deck 的 PRECISION 也能解，但那样必须连 RESOLUTION 一起等比例改，
# 而且会让经过 SHA-256 校验的 foundry 签核 deck 不再是原始文件。转 GDS 更干净。
#
# 转换只有在所有坐标都是 10 的倍数时才是无损的（工艺 gridResolution=5，
# 即 5nm，在 0.1nm 单位下是 50 的倍数，理论上安全）——但这里实测验证，不假设。
#
#   klayout -b -r rescale_gds.py -rd inp=<in.gds> -rd outp=<out.gds>

import pya

inp = globals()["inp"]
outp = globals()["outp"]

ly = pya.Layout()
ly.read(inp)
print("SRC dbu = %.6g um" % ly.dbu)
print("SRC cells = %d" % ly.cells())

# ---- 先验证：有没有不是 10 的倍数的坐标 ----
offgrid = 0
checked = 0
for li in ly.layer_indexes():
    for ci in ly.each_cell():
        for sh in ci.shapes(li).each():
            checked += 1
            box = sh.bbox()
            for v in (box.left, box.right, box.bottom, box.top):
                if v % 10 != 0:
                    offgrid += 1
                    break
print("CHECK shapes=%d offgrid_bbox=%d" % (checked, offgrid))

# 每层的图形数与面积，转换前后对比
def stats(layout):
    out = {}
    for li in layout.layer_indexes():
        info = layout.get_info(li)
        n = 0
        area = 0
        for ci in layout.each_cell():
            for sh in ci.shapes(li).each():
                n += 1
                area += sh.area()
        out[str(info)] = (n, area)
    return out

before = stats(ly)

# ---- 转换：坐标缩小 10 倍，dbu 放大 10 倍，物理尺寸不变 ----
ly.transform(pya.ICplxTrans(0.1))
ly.dbu = ly.dbu * 10.0
print("DST dbu = %.6g um" % ly.dbu)

after = stats(ly)

# 面积以 dbu^2 计，缩放后应为原来的 1/100
bad = 0
for k in sorted(before):
    n0, a0 = before[k]
    n1, a1 = after.get(k, (0, 0))
    exp = a0 / 100.0
    if n0 != n1:
        print("MISMATCH layer=%s count %d -> %d" % (k, n0, n1))
        bad += 1
    elif exp > 0 and abs(a1 - exp) / exp > 1e-9:
        print("MISMATCH layer=%s area %.6g -> %.6g (expected %.6g)" % (k, a0, a1, exp))
        bad += 1
print("LAYER_CHECK layers=%d mismatches=%d" % (len(before), bad))

ly.write(outp)
print("WROTE %s" % outp)
print("RESULT %s" % ("OK" if (offgrid == 0 and bad == 0) else "LOSSY"))
