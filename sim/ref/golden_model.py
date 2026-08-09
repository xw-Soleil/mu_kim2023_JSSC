#!/usr/bin/env python3
"""
golden_model.py -- bit-accurate behavioural model of the accelerator.

Models exactly what the RTL does, including the parts that are easy to get
wrong and that a floating-point reference would hide:

  * floor (toward -inf) division by 4, not round-to-nearest
  * the first-order delta-sigma feedback of the discarded remainder
  * red/black (checkerboard) ordering: the Black sweep sees the Red residues
    that were produced in the same grid update
  * boundary residues injected during update #0 only

Run standalone to print a grid, or import `solve` from the checker script.
"""

import sys


def solve(nrow, ncol, bnd_n, bnd_s, bnd_w, bnd_e,
          use_dsm=True, conv_small=True, max_upd=4096, verbose=False):
    """Returns (u, updates). Colour convention: Red = ((i + j) even)."""
    r = [[0] * ncol for _ in range(nrow)]
    u = [[0] * ncol for _ in range(nrow)]
    e = [[0] * ncol for _ in range(nrow)]

    def nb(i, j, first):
        """Sum of the four neighbour residues, boundary applied on update 0."""
        s = 0
        s += r[i - 1][j] if i > 0        else (bnd_n[j] if first else 0)
        s += r[i + 1][j] if i < nrow - 1 else (bnd_s[j] if first else 0)
        s += r[i][j - 1] if j > 0        else (bnd_w[i] if first else 0)
        s += r[i][j + 1] if j < ncol - 1 else (bnd_e[i] if first else 0)
        return s

    for upd in range(max_upd):
        first = (upd == 0)
        for colour in (0, 1):                     # 0 = Red, 1 = Black
            for i in range(nrow):
                for j in range(ncol):
                    if ((i + j) % 2) != colour:
                        continue
                    s = nb(i, j, first) + (e[i][j] if use_dsm else 0)
                    q = s >> 2                    # arithmetic shift = floor
                    e[i][j] = s - 4 * q           # remainder in 0..3
                    r[i][j] = q
                    u[i][j] += q

        # Symmetric small-residue convergence.  Using "fits in 2-bit signed"
        # here would also accept -2 and would stop negative problems early.
        hit = all((-1 <= r[i][j] <= 1) if conv_small else (r[i][j] == 0)
                  for i in range(nrow) for j in range(ncol))
        if verbose and upd < 8:
            print(f"  update {upd:3d}  max|r| = "
                  f"{max(abs(r[i][j]) for i in range(nrow) for j in range(ncol))}")
        if hit:
            return u, upd + 1
    return u, max_upd


if __name__ == "__main__":
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 8
    c = int(sys.argv[2]) if len(sys.argv) > 2 else 256
    u, k = solve(n, n, [c] * n, [c] * n, [c] * n, [c] * n, verbose=True)
    print(f"\n{n}x{n} grid, uniform boundary {c}, converged in {k} updates")
    for row in u:
        print(" ".join(f"{v:6d}" for v in row))
