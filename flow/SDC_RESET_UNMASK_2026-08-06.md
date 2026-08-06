# SDC reset unmask — Stage 4 evidence, 2026-08-06

Scope: dismantle the three-layer SDC reset masking at its source and prove in
DC (65nm) that recovery/removal checks are now live. DC only; no ICC2, no RTL
change, no golden/testbench/tolerance change, no constraint relaxation.

Run: `flow/local_runs/sdc_unmask_20260806/dc/` (fresh directory), launched via
`flow/local/run_dc.sh` in the synopsys-focal container.
Tool: **Design Compiler T-2022.03-SP2** (the container's dc_shell; note this is
older than the VCS W-2024.09 install), target library `tcbn65lpwc_ccs`
(65nm **RVT tcbn65lp, WC corner** — same line as the full_clean_20260804
baseline used for comparison). Runtime 350 s, `PDE_DC_DONE` + `RESULT: OK`,
0 `Error` lines in the log.

## 1. Source of the three masking layers (4.1)

All three originate in one script, `flow/dc/synth.tcl`; none is
DC-auto-generated. Line numbers below are pre-change:

| Layer | Source location | Note |
|---|---|---|
| `set_ideal_network [get_ports rst_n]` | `flow/dc/synth.tcl:108` (`{clk rst_n}` combined) | script-explicit |
| missing `set_input_delay` on rst_n | `flow/dc/synth.tcl:95` — `remove_from_collection [all_inputs] [get_ports {clk rst_n}]` | the omission is deliberate, not an accident |
| `set_false_path -from [get_ports rst_n]` | `flow/dc/synth.tcl:107` | script-explicit |

The final SDC (`…/results/pde_chip_top_safe.sdc`, lines 32/33/41 in the old
run) is the `write_sdc` product of these lines; the fix was applied to the
source only.

**Fourth, DC-specific hidden layer discovered during 4.1:** DC ignores library
recovery/removal arcs unless `enable_recovery_removal_arcs` is set to true
(default false). Even with a perfect SDC, dc_shell would never have reported a
removal check. The variable is now set in `synth.tcl` before compile. Enabling
checks is the opposite of a relaxation; documented here because ICC2/PT do not
share this default, which is one reason the gap survived so long.

## 2. Change diff (4.2) — single file `flow/dc/synth.tcl`

```diff
@@ (library setup section)
 set_app_var link_library [concat "*" $target_library]
+
+# DC ignores library recovery/removal arcs by default (var default: false).
+# Without this, no reset-release check is ever performed regardless of SDC.
+# [28nm-portable] process independent; keep enabled.
+set_app_var enable_recovery_removal_arcs true
+
+# [28nm hook] AOCV derate attach point. The 28nm 1P9M_4X2Y2R libraries ship
+# per-library sbocv tables; load them here (read_aocvm / set_timing_derate
+# -aocvm usage per the 28nm methodology) once that PDK is in place. tcbn65lp
+# has no OCV tables, so no derate is applied in the 65nm flow on purpose.
@@ (constraint section, old lines 105-108)
-# rst_n is an asynchronous functional reset. Ignore its assertion path during
-# synthesis optimization; recovery/removal remains a required post-CTS check.
-set_false_path -from [get_ports rst_n]
-set_ideal_network [get_ports {clk rst_n}]
+# Reset constraints (2026-08-06). The RTL now has a two-stage synchronizer in
+# pde_chip_top_safe (rst_sync_q_reg[0]/[1]): async assertion, sync release.
+# (long rationale comment, see file)
+set_input_delay -max 1.000 -clock $CLOCK_NAME [get_ports rst_n]
+set_input_delay -min 0.200 -clock $CLOCK_NAME [get_ports rst_n]
+set_input_transition 0.100 [get_ports rst_n]
+set_false_path -from [get_ports rst_n]
+set_ideal_network [get_ports clk]
@@ (reports section)
+redirect -file [file join $REPORT_DIR timing_removal.rpt] { … }
+redirect -file [file join $REPORT_DIR timing_recovery.rpt] { … }
```

Full diff: `git diff flow/dc/synth.tcl` (+51/−4 including comments; the
functional changes are exactly the lines above).

Input-delay value rationale: max 1.0 ns equals the block-level budget used by
every data input (synth.tcl line 97); min 0.2 ns is the project
earliest-arrival convention, giving removal a non-zero early bound. Neither
the clock, uncertainty, nor any exception was relaxed; no new false paths and
no set_disable_timing were added.

`set_false_path -from [get_ports rst_n]` was **kept unchanged** — 4.2.3
empirical confirmation below shows it now reaches only the truly-async
port→synchronizer segment.

## 3. Generated-SDC confirmation

New `results/pde_chip_top_safe.sdc`:

```text
32:set_ideal_network [get_ports clk]
40:set_false_path   -from [get_ports rst_n]
41:set_input_delay -clock core_clk  -max 1  [get_ports rst_n]
42:set_input_delay -clock core_clk  -min 0.2  [get_ports rst_n]
```

`set_ideal_network [get_ports rst_n]` no longer exists in the product.
Old-run `check_timing` flagged `rst_n` under `no_input_delay` (TIM-216); the
new `check_timing.rpt` lists no port there.

## 4. Recovery/removal now live (4.3b — core criterion)

The user-specified commands are not supported by this DC build:

```text
dc_shell> report_timing -delay_type min -check_type removal
Error: unknown option '-check_type' (CMD-010)
Error: extra positional option 'removal' (CMD-012)
```

The scripted fallback (same path set, addressed via the async clear pins)
executed automatically:

```tcl
report_timing -delay_type min -max_paths 20 -nworst 1 -input_pins \
  -to [get_pins -hierarchical */CDN]     ;# removal
report_timing -delay_type max -max_paths 20 -nworst 1 -input_pins \
  -to [get_pins -hierarchical */CDN]     ;# recovery
```

Results (`reports/timing_removal.rpt`, `reports/timing_recovery.rpt`):

- **Real paths returned.** Zero "No paths", zero TIM-010 in both reports and
  in the log.
- All 20/20 reported paths in each report start at
  `rst_sync_q_reg_1_` (the second synchronizer stage, clocked by core_clk).
  Zero paths start at the port `rst_n`.
- Endpoint population: 16,226 CDN pins total in the netlist; 2 belong to the
  synchronizer (exempt by design), leaving **16,224 live check endpoints**.
  `report_constraint -all_violators` contains **zero** removal/recovery/
  min_delay entries → every live check is MET.

| Check | Worst slack | Worst path | TNS |
|---|---|---|---|
| removal (min) | **+0.10** (MET) | `rst_sync_q_reg_1_` → `status_read_q_reg` (CDN) | 0 |
| recovery (max) | **+6.43** (MET) | `rst_sync_q_reg_1_` → `u_impl/u_core/g_row_0__g_col_2__u_pe/u_r_red/q_reg_0_` | 0 |

Worst removal arithmetic (raw report excerpt):

```text
  clock core_clk (rise edge)               0.00       0.00
  clock network delay (ideal)              0.00       0.00
  rst_sync_q_reg_1_/CP (DFCNQD1)           0.00 #     0.00 r
  rst_sync_q_reg_1_/Q (DFCNQD1)            0.49       0.49 r
  data arrival time                                   0.49
  data required time                                  0.38
  slack (MET)                                         0.10
```

Removal slack is positive here because clocks are still ideal and the wire
load model is Zero/segmented — there is no reset-vs-clock network skew yet.
The +0.10 margin is thin; after real clock-tree and reset distribution
insertion delays in P&R this is exactly the check expected to go negative
until a reset tree is built. That is a P&R task (28nm), not a constraint
problem.

**4.2.3 empirical confirmation** that the blanket `-from [get_ports rst_n]`
false path self-confines after the synchronizer:

1. Netlist connectivity: in the `pde_chip_top_safe` top scope the raw port
   `rst_n` drives exactly **2** pins — `rst_sync_q_reg_0_/CDN` and
   `rst_sync_q_reg_1_/CDN`. The wrapper's own three registers and `u_impl`
   take `rst_sync_q[1]`.
2. Timing: with the report explicitly targeting **all** hierarchical CDN
   pins, zero returned paths originate at the port; downstream checks
   launch from `rst_sync_q_reg_1_/CP` and are therefore outside the
   exception's reach.

No `-to`-qualified rewrite was needed; the original line stays.

## 5. Setup/hold comparison vs pre-change baseline (4.3a)

Baseline: `full_clean_20260804/dc` (old RTL, masked SDC). Note the comparison
includes the Stage 3 RTL change by necessity.

| Metric | Baseline | This run |
|---|---|---|
| Critical path slack (setup, 10 ns clock) | +3.60 | **+3.59** |
| Setup TNS / violating paths | 0 / 0 | 0 / 0 |
| Hold WNS / TNS / violations | 0 / 0 / 0 | 0 / 0 / 0 |
| Cell count | 110,030 | 110,972 (+942) |
| Total cell area (µm²) | 402,140 | 403,699 (+1,559, +0.39%) |
| High-fanout nets (TIM-134, >1000) | 2 (clk, rst_n) | **1 (clk only)** |

Setup converged; no setup/hold violations. The +942 cells / +0.39% area are
the two synchronizer flops plus the reset buffer tree DC now builds, because
removing `set_ideal_network` exposes the reset net to the existing
`set_max_fanout 32` rule.

One honest observation outside the pass criteria: `max_transition` violating
nets grew from 6 to 66 (worst −0.02 ns on a 0.50 ns limit, same severity
class as the baseline's own violations; drivers are ordinary combinational
gates and one CKBD0 buffer). These are wire-load-model marginals of the class
routinely cleaned by P&R optimization; per the no-relaxation rule nothing was
tuned to hide them. `max_leakage_power` remains violated by construction in
both runs (leakage budget 0).

## 6. NEX-020 status (4.4)

- NEX-020 is an ICC2 RC-extraction message; it appears in the old ICC2 logs
  (`Net 'rst_n' is exceeding threshold (over 1000 pins) and will be skipped`,
  e.g. `full_clean_20260804/icc2/reports/icc2/final_qor.rpt:9`). This stage
  runs DC only → **0 occurrences in the new DC log**, as expected.
- Current fanout facts: raw port `rst_n` now has 2 loads. The synchronized
  reset fans out to **16,224 CDN pins logically**, but at DC netlist level it
  is distributed through a buffer tree (max_fanout 32), so no reset net
  exceeds the 1000-pin threshold; DC's analogous high-fanout list (TIM-134)
  dropped from {clk, rst_n} to {clk}.
- If the 28nm P&R strips or rebuilds DC's buffer tree (typical), the >1000-pin
  situation reappears on `rst_n_sync` at placement until a reset tree exists.
  Handling directions, **no choice made here** (28nm P&R decision):
  1. raise the extraction pin-count threshold so the net is extracted;
  2. build the reset distribution as a proper tree (CTS-managed or
     synthesis-preserved) so no single net exceeds the threshold.

## 7. 28nm migration annotations (4.5)

Marked in `flow/dc/synth.tcl` comments:

- **Process-independent, migrate as-is**: `enable_recovery_removal_arcs true`;
  the three-layer unmasking structure (no ideal reset, real min/max arrival
  window, false path confined to port→synchronizer); the removal/recovery
  report blocks.
- **Re-derive on 28nm**: the numeric input-delay budget (1.0/0.2 ns) from the
  28nm IO timing plan; clock period/uncertainty; max_fanout/max_transition
  targets.
- **28nm-only addition, hook left in place**: AOCV/sbocv derate attach point
  right after library setup (marked `[28nm hook]`); intentionally inactive at
  65nm because tcbn65lp ships no OCV tables.

## 8. Leftovers

1. `flow/dc/synth.tcl` change is uncommitted (as is the Stage 3 RTL edit);
   commit timing is the user's call.
2. `-check_type` unavailable in DC T-2022.03-SP2; if the flow moves to a
   newer dc_shell or PT, the two exact commands should be retried there.
3. The 6→66 max_transition marginals (worst −0.02 ns) are left for P&R
   optimization; re-check after the 28nm library swap.
4. `flow/OVERNIGHT_RECON_2026-08-06.md` carries an unrelated uncommitted
   appendix (HVT library completeness survey) added outside this stage; left
   untouched.
