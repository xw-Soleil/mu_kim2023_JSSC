# Folded Red/Black Bit-Serial PDE Accelerator (RTL)

> **Disclaimer:** This project is for academic learning and demonstration purposes only. Library files and Synopsys tool scripts cannot be distributed publicly.

20x20 logical grid on 20x10 physical PEs. Residue-based FDM, checkerboard
update, 4/8/12/16-bit dynamic precision, first-order DSM.

Deltas vs Mu & Kim, JSSC'23:
1. Red/Black folded into one PE sharing a bit-serial ALU (utilisation 50%->100%)
2. Precision switching self-triggered by per-PE range flags (no offline schedule)
3. DSM implemented in RTL and combined with dynamic precision (paper: proposal only)

The core arithmetic follows Fig. 8: N clocks at N-bit precision, four carry
DFFs, and parallel `Sum/MSB1/MSB0` outputs into the residue shift register.

## Run
    cd sim
    make pe         # single-PE arithmetic, reproduces Fig.10
    make top8       # 8x8, positive uniform boundary
    make top8neg    # 8x8, negative uniform boundary
    make top8mixed  # 8x8, nonuniform mixed-sign boundaries
    make top20      # 20x20 (slow under iverilog)
    make dsm        # DSM accuracy sweep

## Verified results (8x8, uniform boundary 4096)
    converged, max|u-exact| = 17 (0.4%)
    dynamic precision : 53 updates, 1039 cycles
    fixed 16-bit      : 53 updates, 1855 cycles   -> 1.78x
    golden comparison : 64/64 points bit-exact
    scan-chain check  : 64/64 words exact

Additional signed regressions:
    boundary -4096    : 53 updates, max error 2, 64/64 bit-exact
    mixed boundaries  : 17 updates, 64/64 bit-exact

## Files
    src/common/    counter_ce pipeline_delay_bit
    src/pe/        pde_q8p7_pkg r_alu r_reg r_dsm r_status sol_acc
                   r_state_ctrl pe_top
    src/pe_array/  pde_memcontrol pde_tcu pde_top
    tb/            tb_pe_smoke tb_pde_top
    sim/           Makefile + filelists
    sim/ref/       golden_model.py dsm_sweep.py check_golden.py
    docs/           design_notes.md / design_notes_zh.md   <-- read this first

## Key parameters
    USE_DSM        delta-sigma on/off
    DYN_PREC       dynamic vs pinned 16-bit (A/B baseline)
    CONV_ON_SMALL  |r|<=1 vs r==0 convergence test

Control/datapath split:

    pde_tcu        global FSM, precision and convergence control
    r_state_ctrl   local bank/Mode/write-enable decode, one per PE
    pe_top         wires up the PE leaves (r_reg x2, r_alu, r_dsm, sol_acc,
                   r_status)
    pde_top        owns the PE lattice directly (neighbour routing, scan chain)

The folded PE keeps two residue-register banks because source serialization and
destination loading happen on the same CK_A.  One shared full-width precision
MUX sits after the Red/Black bank select.

`start` launches one solve after reset. Assert `rst_n` before loading and
starting another independent problem; solution, residue and DSM state are all
stateful and are intentionally not silently cleared from `S_DONE`.

## Implementation status (TSMC 28nm HPC+)

Three implementation rounds, records under `flow/`:

- R1 (tag `signoff28-full-clean`): core-only top through DC/ICC2 with the first independent PT + Calibre signoff (`flow/SIGNOFF_28NM_2026-08-07.md`).
- R2: PPA tightening (clock 10 -> 6 ns, utilization 0.55 -> 0.70) plus root-cause fixes (`flow/PPA_28NM_R2_2026-08-08.md`).
- R3 (tag `fullchip28-signoff`): tapeout-shaped chip -- SPI-style config interface, 21-pad GPIO ring with CUP bond pads on a 685x685 um die, all six ICC2 hard gates zero, and PT/Calibre signoff with every remaining discrepancy root-caused (`flow/R3_FULLCHIP_2026-08-15.md` and the records it links). Dummy fill is intentionally out of scope.

A per-script walkthrough and glossary for the whole line: `docs/flow_primer_zh.md`.

## Local Git safety

This working repository is local-only and its existing history is not a publication-ready export. Source-management rules are in `AGENTS.md`; Claude Code imports the same rules through `CLAUDE.md`.

Enable the tracked pre-commit policy after cloning or recreating `.git`:

```bash
git config core.hooksPath .githooks
git config --get core.hooksPath
```

The hook rejects files over 50 MiB, common PDK/vendor/implementation file types, and obvious credential patterns. Disclosure-class findings (machine/license/internal-host strings) and the per-commit inventory of staged `flow/` paths with candidate cell/layer/corner tokens are printed as non-blocking notices since 2026-08-07 -- review them at commit time; they do not constitute sanitization for any future public release.

Do not use `--no-verify` without explicit approval for the exact commit. `gitleaks` is additionally required before any remote or public-release work; the hook reports when it is unavailable.
