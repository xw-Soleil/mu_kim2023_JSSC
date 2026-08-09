#!/usr/bin/env python3
"""
check_golden.py -- point-by-point comparison of the RTL dump against the
behavioural model.

    python3 sim/check_golden.py sim/u_dyn.txt <nrow> <ncol> <boundary|mixed>

Exits non-zero on any mismatch.  This is the check that actually pins the
design down: matching a floating-point reference to within a tolerance would
hide truncation-direction and DSM-ordering bugs, whereas the model in
matlab/golden_model.py reproduces the exact integer arithmetic, so the two
must agree on every single grid point.
"""

import sys, os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from golden_model import solve


def main():
    path = sys.argv[1]
    nrow = int(sys.argv[2])
    ncol = int(sys.argv[3])
    bnd_spec = sys.argv[4]

    with open(path) as f:
        rtl = [[int(x) for x in line.split()] for line in f if line.strip()]

    if len(rtl) != nrow or any(len(row) != ncol for row in rtl):
        print(f"  dump dimensions           : {len(rtl)} rows")
        print(f"  expected dimensions       : {nrow} x {ncol}")
        print("check_golden : FAIL  (malformed or stale dump)")
        return 1

    if bnd_spec == "mixed":
        bnd_n = [100 + 11*j for j in range(ncol)]
        bnd_s = [-200 - 7*j for j in range(ncol)]
        bnd_w = [300 + 13*i for i in range(nrow)]
        bnd_e = [-400 + 17*i for i in range(nrow)]
    else:
        bnd = int(bnd_spec)
        bnd_n = [bnd] * ncol
        bnd_s = [bnd] * ncol
        bnd_w = [bnd] * nrow
        bnd_e = [bnd] * nrow

    gold, upd = solve(nrow, ncol, bnd_n, bnd_s, bnd_w, bnd_e)

    bad = 0
    worst = 0
    for i in range(nrow):
        for j in range(ncol):
            d = rtl[i][j] - gold[i][j]
            if d:
                bad += 1
                worst = max(worst, abs(d))
                if bad <= 5:
                    print(f"  mismatch [{i}][{j}] rtl={rtl[i][j]} golden={gold[i][j]}")

    print(f"  golden model converged in {upd} updates")
    print(f"  grid points compared      : {nrow*ncol}")
    print(f"  mismatches                : {bad}")
    if bad:
        print(f"  worst difference          : {worst}")
        print("check_golden : FAIL")
        return 1
    print("check_golden : PASS  (RTL is bit-exact against the model)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
