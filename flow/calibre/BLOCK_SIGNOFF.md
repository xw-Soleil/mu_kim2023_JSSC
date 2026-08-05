# TSMC65LP block-level Calibre setup

This directory contains a reproducible setup for the routed block
`pde_chip_top_safe` on the SP6M4x1z stack. The configuration default still
points to `flow/results/openroad/pde_chip_top_safe.gds` for compatibility; it
is not the current canonical signoff input.

> **2026-08-03 status:** the latest verified antenna input is the rebuilt-NDM
> ICC2 layout on EDAServer:
> `flow/results/icc2_from_ubuntu/pde_chip_top_safe.rebuilt_20260803.dbu1000.gds`.
> It produced 26 checks and 0 results, with 1,228,347 expanded VIA1-VIA5
> geometries and no summary runtime warnings. See
> `flow/reports/calibre/READ_ME_FIRST.md` and
> `pde_chip_top_safe_rebuilt_20260803_antenna.summary`.
>
> This is an antenna-only result. ICC2 still reports one open net and two M5
> shorts. Full Calibre DRC/LVS has not passed. The available DRC deck is 4X1Z
> while ICC2 stream-out uses the 3X1Z map; that mismatch must be resolved before
> treating a DRC run as signoff.

The preparation script extracts the audited 23a DRC and antenna decks from
the persistent local archive.  It verifies their SHA-256 values, copies them
under `flow/work/calibre/block_signoff`, patches only run I/O and the DRC
option block, and writes a manifest.  The foundry archive is never modified.

For the block-level LP DRC copy, the exact switch policy is:

- keep `FRONT_END` and `BACK_END` enabled;
- enable `LP`;
- disable `FULL_CHIP`;
- disable `WLCSP_SEALRING`;
- disable both active `CHECK_LOW_DENSITY` definitions;
- keep `GP` and `LPG` disabled.

The antenna deck has no corresponding LP/block option switch.  Its layout,
top-cell, results database and summary paths are replaced, while its antenna
rules remain unchanged.

Prepare decks without invoking Calibre:

```bash
flow/calibre/prepare_block_signoff_decks.sh
```

After the final GDS exists, run DRC, antenna, or both:

```bash
flow/calibre/run_block_signoff.sh drc
flow/calibre/run_block_signoff.sh antenna
flow/calibre/run_block_signoff.sh all
```

Always override `PDE_GDS` for an ICC2 result. The 2026-08-03 run used
`run_block_signoff_final.sh antenna` plus unique `PDE_ANT_RDB`,
`PDE_ANT_SUMMARY`, and `PDE_ANT_LOG` paths so historical reports were not
overwritten.

All defaults are in `block_signoff_config.sh` and can be overridden through
environment variables or by setting `PDE_CALIBRE_CONFIG` to another sourced
configuration file.  A successful Calibre process exit is not treated as a
zero-violation result; the generated summaries and RDBs must be reviewed.

No local foundry LVS deck was identified by this setup, so these scripts make
no LVS claim and do not substitute a fabricated rule deck.
