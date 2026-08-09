#!/usr/bin/env python3
"""
dsm_sweep.py -- quantify what the delta-sigma feedback buys.

The reference paper presents the DSM only as a proposal in its discussion
section, evaluated behaviourally at fixed 16/24-bit precision; it is not part
of the fabricated PE and was never combined with dynamic precision.  This
sweep is the measurement that gap leaves open.

Reported for a uniform Dirichlet boundary, whose exact steady state is a
constant, so `max |u - exact|` is a true error and not an estimate.
"""

import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from golden_model import solve


def run(n, bnd, dsm):
    u, k = solve(n, n, [bnd]*n, [bnd]*n, [bnd]*n, [bnd]*n, use_dsm=dsm)
    err = max(abs(v - bnd) for row in u for v in row)
    return k, err


def main():
    print()
    print("  grid   boundary |      no DSM      |      with DSM     | error")
    print("                  | updates    error | updates     error | reduction")
    print("  " + "-" * 66)
    for n in (8, 12, 20):
        for bnd in (1024, 4096):
            k0, e0 = run(n, bnd, False)
            k1, e1 = run(n, bnd, True)
            print(f"  {n:2d}x{n:<2d}  {bnd:7d} | {k0:7d} {e0:8d} |"
                  f" {k1:7d} {e1:9d} | {e0/max(e1,1):6.1f}x")
    print()
    print("  The DSM costs 4 flip-flops and one full adder per PE.")
    print("  It does not remove the -1 fixed point: with every residue at -1")
    print("  the sum is exactly -4, the remainder is 0 and there is nothing to")
    print("  feed back -- which is why the convergence test is |r| <= 1 rather")
    print("  than r == 0.")
    print()


if __name__ == "__main__":
    main()
