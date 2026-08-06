# PDE RTL simulation restore evidence - 2026-08-06

## Scope and status

This report records Stages 0, 1, and 2. All three stages are complete: the
full VCS regression passes on the current local RTL with zero golden
mismatches, and the pre-sync-baseline outputs are archived.

Changes made in Stages 0-2:

- Created `sim_restored/`.
- Copied seven simulation-control source files from the EDAServer working tree.
- Stage 2: one-line `sim_restored/Makefile` edit (`dsm` target path), two
  library packages reinstalled inside the `synopsys-focal` container, and the
  baseline archive under `local_artifacts/vcs/pre-sync-baseline/2026-08-06/`.
- Created this report.

No RTL, testbench, reference model, backend run, or EDAServer file was changed.
The existing unrelated local `flow/` changes were not modified.

## Executive findings

1. **Confirmed:** the original simulation directory is
   `EDAServer:/home/sxw/PDE/pdeMujunjie/rtl/sim/`, not the obsolete root-level
   `sim/` path.
2. **Confirmed:** all seven tracked source/control files were copied to
   `sim_restored/`; source and destination SHA256 values match 7/7.
3. **Confirmed:** local `src/` and EDAServer `rtl/src/` contain the same 16
   files with identical SHA256 values.
4. **Confirmed:** GitHub commit `5a3fd5dea16cafe26c4596cc163c5e101aec2f14`
   has 13 RTL source files. Twelve are identical across all three copies.
   `pe_top.sv` differs only in one comment. Three chip/core wrapper files exist
   only in the local and EDAServer copies.
5. **Confirmed content direction:** current local `pe_top.sv` is the later
   EDAServer content state. The GitHub content is byte-identical to the earlier
   EDAServer-branch version; commit `4f4d171e` later changed only the comment
   reference from `tb_pe.sv` to `tb_pe_smoke.sv`. The two Git histories are
   disconnected, so GitHub commit `5a3fd5de` is not a direct ancestor.
6. **Confirmed:** `tb_pe_smoke.sv` is a renamed copy of `tb_pe.sv`, not a
   simplified or functionally different test. The only differences are the
   header, module name, and two PASS/FAIL display names.
7. **No confirmed backend/RTL mismatch:** both RVT/DC and HVT/DC logs compile
   the same logical set of 15 RTL files, and those 15 files are currently
   byte-identical between local and EDAServer copies.
8. **Evidence limitation:** neither DC run preserved an input SHA256/MD5
   manifest or source snapshot. Paths, compile success, pre-run mtimes, current
   hashes, and Git history support continuity, but the exact bytes present at
   the instant of synthesis cannot be proven cryptographically.
9. **Confirmed:** ICC2 imported the `full_clean_20260804/dc/results` RVT
   netlist. Innovus imported the HVT bundle `v2_9ns` netlist, whose SHA256 is
   identical to EDAServer's latest `flow/results/dc` HVT netlist.

The requested red mismatch alert is therefore **not triggered**. The missing
run-time RTL hash manifest remains an explicit unresolved provenance gap.

## Stage 0 - restore source

### 0.1 Correct source directory

The initially supplied obsolete path does not exist:

```text
$ LC_ALL=C ssh EDAServer 'ls -laR /home/sxw/PDE/pdeMujunjie/sim/'
ls: cannot access /home/sxw/PDE/pdeMujunjie/sim/: No such file or directory
```

After correction, the complete source directory is:

```text
$ LC_ALL=C ssh EDAServer 'find /home/sxw/PDE/pdeMujunjie/rtl/sim -printf "%y\t%s\t%TY-%Tm-%Td %TH:%TM:%TS\t%p\n"'
d  159   2026-08-05 00:19:26.2292132900  /home/sxw/PDE/pdeMujunjie/rtl/sim
f  8784  2026-08-05 00:19:17.3902134880  /home/sxw/PDE/pdeMujunjie/rtl/sim/Makefile
f  40    2026-08-01 02:16:21.6337938590  /home/sxw/PDE/pdeMujunjie/rtl/sim/chip20.f
f  38    2026-08-01 02:16:21.6337938590  /home/sxw/PDE/pdeMujunjie/rtl/sim/chip8_wave.f
f  34    2026-08-01 02:10:44.9498013970  /home/sxw/PDE/pdeMujunjie/rtl/sim/chip.f
f  76    2026-08-01 02:23:33.9897841790  /home/sxw/PDE/pdeMujunjie/rtl/sim/chip_safe.f
f  384   2026-08-01 02:10:44.9498013970  /home/sxw/PDE/pdeMujunjie/rtl/sim/rtl.f
f  2351  2026-07-26 15:47:48.0000000000  /home/sxw/PDE/pdeMujunjie/rtl/sim/check_golden.py
```

There are seven regular files, no subdirectories, and no symbolic links.
`git status --short -- rtl/sim` returned no output, and `git ls-files -s --
rtl/sim` listed all seven files. The EDAServer working tree version is therefore
tracked and clean at:

```text
14591f959dcdbf7af60c02b1c1e48996587f1fe1  2026-08-05T16:59:08+08:00
flow+docs: Innovus 20.10 P&R on HVT closes clean -- final GDS delivered
```

### 0.2 File classification and golden reference

The five `.f` files are plain-text simulator file lists. For example:

```text
$ LC_ALL=C ssh EDAServer 'sed -n "1,260p" /home/sxw/PDE/pdeMujunjie/rtl/sim/rtl.f'
../src/common/counter_ce.sv
../src/common/pipeline_delay_bit.sv
../src/pe/pde_q8p7_pkg.sv
../src/pe/r_alu.sv
../src/pe/r_reg.sv
../src/pe/r_dsm.sv
../src/pe/r_status.sv
../src/pe/sol_acc.sv
../src/pe/r_state_ctrl.sv
../src/pe/pe_top.sv
../src/pe_array/pde_memcontrol.sv
../src/pe_array/pde_tcu.sv
../src/pe_array/pde_core.sv
../src/pe_array/pde_top.sv
../src/pe_array/pde_chip_top.sv
```

No `simv`, `csrc`, `*.daidir`, `*.vpd`, `AN.DB`, waveform, or log exists in
the complete directory listing. All seven files are source/control collateral;
none is a compile product.

There is no static golden-data file. `check_golden.py` computes the reference
grid dynamically and compares it with simulation-generated `u_dyn.txt` and
`u_fix.txt`:

```python
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'matlab'))
from golden_model import solve
...
gold, upd = solve(nrow, ncol, bnd_n, bnd_s, bnd_w, bnd_e)
```

On EDAServer, the script's literal `../matlab` path from `rtl/sim/` does not
exist. The actual server model is `rtl/reference/golden_model.py`. When the
unmodified script is placed in local root-level `sim_restored/`, `../matlab`
resolves to local `matlab/`. The model bytes match:

```text
$ LC_ALL=C ssh EDAServer 'sha256sum /home/sxw/PDE/pdeMujunjie/rtl/reference/golden_model.py /home/sxw/PDE/pdeMujunjie/rtl/reference/dsm_sweep.py'
128c61691d9721bb02cda7b680fc577c5901c6346963fe46bb8a487726837a8a  .../golden_model.py
1e56ec5a7ca6b5cc84762e5f80329a433e08da526ec1c41718c17b224c8c3107  .../dsm_sweep.py

$ sha256sum matlab/golden_model.py matlab/dsm_sweep.py
128c61691d9721bb02cda7b680fc577c5901c6346963fe46bb8a487726837a8a  matlab/golden_model.py
1e56ec5a7ca6b5cc84762e5f80329a433e08da526ec1c41718c17b224c8c3107  matlab/dsm_sweep.py
```

No testbench is stored in `rtl/sim/`. File lists and Makefile targets reference
files under `rtl/tb/`.

### 0.3 Transfer and verification

Executed transfer:

```text
$ mkdir sim_restored
$ LC_ALL=C scp -p \
    EDAServer:/home/sxw/PDE/pdeMujunjie/rtl/sim/Makefile \
    EDAServer:/home/sxw/PDE/pdeMujunjie/rtl/sim/check_golden.py \
    EDAServer:/home/sxw/PDE/pdeMujunjie/rtl/sim/rtl.f \
    EDAServer:/home/sxw/PDE/pdeMujunjie/rtl/sim/chip.f \
    EDAServer:/home/sxw/PDE/pdeMujunjie/rtl/sim/chip20.f \
    EDAServer:/home/sxw/PDE/pdeMujunjie/rtl/sim/chip8_wave.f \
    EDAServer:/home/sxw/PDE/pdeMujunjie/rtl/sim/chip_safe.f \
    sim_restored/
```

Source and destination SHA256 values:

| File | SHA256 before and after |
|---|---|
| `Makefile` | `49ecb90aeb928a32c0afc830770d1ae9986db5334c928f6145056919bc599e79` |
| `check_golden.py` | `b6c8a0b7e1cb8cf8960d3d5244488247360a02f884ca0b1bfe370bf02c0ee7fa` |
| `rtl.f` | `2fb36268c287b6407453e8eda142ac12cca230d9c0ad9864f0147b9b16c5f2e8` |
| `chip.f` | `6b491ca77f43ed02227a73019000d4a3ad3768177b4315b9f1b468cc2684b254` |
| `chip20.f` | `e31f9ce7b3ccec6f312b55c381a7814226836fe8ad67d8b36211b4da598c021f` |
| `chip8_wave.f` | `96ed55fc7183202864dd29dd719f8644d40f91bf2b8a9527ea0112810d5b4bb2` |
| `chip_safe.f` | `e45f743ba2837c38553446af4ff7395b835eb9685eb24f2a349c4296f4cc899f` |

The post-transfer command was:

```text
$ sha256sum sim_restored/Makefile sim_restored/check_golden.py \
    sim_restored/rtl.f sim_restored/chip.f sim_restored/chip20.f \
    sim_restored/chip8_wave.f sim_restored/chip_safe.f
```

`diff -qr sim_restored /tmp/pde_sim_restore_stage1.YLchuvNh/edaserver/rtl/sim`
returned no output and exit status 0.

## Stage 1 - three-way version relationship

### 1.1 Source manifests

Logical path mapping:

- Local: `src/<path>`
- EDAServer: `rtl/src/<path>`
- GitHub: `rtl/src/<path>` at commit
  `5a3fd5dea16cafe26c4596cc163c5e101aec2f14`

Commands:

```text
$ find src -type f -exec sha256sum {} +
$ LC_ALL=C ssh EDAServer 'find /home/sxw/PDE/pdeMujunjie/rtl/src -type f -exec sha256sum {} +'
$ find /tmp/pde_sim_restore_stage1.YLchuvNh/github/tree/rtl/src -type f -exec sha256sum {} +
```

### 1.2 Three-way classification

Complete normalized manifest and classification:

| RTL path | Local SHA256 | EDAServer SHA256 | GitHub SHA256 | Class |
|---|---|---|---|---|
| `common/counter_ce.sv` | `ecbd942a547f30ea87e6b08cb9291a27428a6ff75c551bbebfb61c19f6d446d9` | same | same | three-way same |
| `common/pipeline_delay_bit.sv` | `b959a9589092c0abb21df9d4487d131557d146b2cc14c3e4bf9071237cce8544` | same | same | three-way same |
| `pe/pde_q8p7_pkg.sv` | `3ab3fe818fd29a45856068baecb96e7ef0c54b1e9e4e4e5c19eafa9e09051a6a` | same | same | three-way same |
| `pe/r_alu.sv` | `9910ef8f257431b1826bd751eb02feefda88293cc4bf297b5f57a77c069dca38` | same | same | three-way same |
| `pe/r_reg.sv` | `e43b79c675f0593ef3238b88eab15c5b3b8d1d34ec71e8368341d5b186697e57` | same | same | three-way same |
| `pe/r_dsm.sv` | `f127249c8db121cabb11467038ac44733b415885f7e7a7a33dfeb0901762494d` | same | same | three-way same |
| `pe/r_status.sv` | `8cf9167b3e915bc042d7dcc550173c6594a78dd75d29df13600fa7026719466f` | same | same | three-way same |
| `pe/sol_acc.sv` | `e6e9b4063393dd82a55981f3cec63986eee935e293f2d0940db89d46cd2457a7` | same | same | three-way same |
| `pe/r_state_ctrl.sv` | `a529424787a644650af75c5b28d7d563aa3703f1366644229441307ea73b426a` | same | same | three-way same |
| `pe/pe_top.sv` | `3bd4cbca6da296f5dd483f81d0e8cd16e07bceab92ad484bc8f12c7c3deb196e` | same | `5e9f11ce0c77aaacd6e3acaa9386496b6efd84a2c75e25d7104b74b98a35dab7` | local + EDAServer same; GitHub differs |
| `pe_array/pde_memcontrol.sv` | `4e16b38d6dac06f1696fc94a8af44d4d03093ce5daebc5f7f3ab255f63773d43` | same | same | three-way same |
| `pe_array/pde_tcu.sv` | `dbd8ec05f2822e972c42619e12e4f01f9e0737afc65ad67008c01438447d1be8` | same | same | three-way same |
| `pe_array/pde_top.sv` | `0ed600fec2fb5b062e66ae1ab7c21eec38b19f49a668a7b806d2b1b92e322b10` | same | same | three-way same |
| `pe_array/pde_core.sv` | `0a1545861e8494a3bf4aeea427a4f0b2bc1782ddb0914d7e98172665bdd738fd` | same | absent | local + EDAServer only |
| `pe_array/pde_chip_top.sv` | `3e5494b3d345deb168f9f4137c1cade76d0d45a2cddb18b4fa3efd1dcf2bafa5` | same | absent | local + EDAServer only |
| `pe_array/pde_chip_top_safe.sv` | `60f1f9317154b068ba33b0d1ff01eeb7308375acf68cd14afd78b8ec2eceb1ad` | same | absent | local + EDAServer only |

Counts and raw recursive comparison:

```text
$ find src -type f | wc -l
16
$ find .../edaserver/rtl/src -type f | wc -l
16
$ find .../github/tree/rtl/src -type f | wc -l
13

$ diff -qr src .../edaserver/rtl/src
# no output; exit 0

$ diff -qr src .../github/tree/rtl/src
Files src/pe/pe_top.sv and .../github/tree/rtl/src/pe/pe_top.sv differ
Only in src/pe_array: pde_chip_top.sv
Only in src/pe_array: pde_chip_top_safe.sv
Only in src/pe_array: pde_core.sv
```

Summary: 12 files are three-way identical; one file is present in all three
but local/EDAServer match each other; three files exist only in local and
EDAServer. There are no three-way-all-different files and no GitHub-only RTL
source files.

### 1.3 `pe_top.sv` direction

The GitHub commit object exists in the EDAServer object database, but it is not
an ancestor of EDAServer HEAD and `git merge-base` finds no common ancestor:

```text
$ LC_ALL=C ssh EDAServer 'git -C /home/sxw/PDE/pdeMujunjie cat-file -t 5a3fd5dea16cafe26c4596cc163c5e101aec2f14'
commit

$ LC_ALL=C ssh EDAServer 'git -C /home/sxw/PDE/pdeMujunjie merge-base --is-ancestor 5a3fd5dea16cafe26c4596cc163c5e101aec2f14 HEAD'
# no output; exit 1

$ LC_ALL=C ssh EDAServer 'git -C /home/sxw/PDE/pdeMujunjie merge-base 5a3fd5dea16cafe26c4596cc163c5e101aec2f14 HEAD'
# no output; exit 1
```

Content history does establish direction. GitHub `5a3fd5de` and the earlier
EDAServer-branch commit `c8ec59bb` contain identical `pe_top.sv` bytes; the
later EDAServer commit `4f4d171e` contains the current local bytes:

```text
$ LC_ALL=C ssh EDAServer 'git -C /home/sxw/PDE/pdeMujunjie show 5a3fd5de:rtl/src/pe/pe_top.sv | sha256sum'
5e9f11ce0c77aaacd6e3acaa9386496b6efd84a2c75e25d7104b74b98a35dab7  -
$ LC_ALL=C ssh EDAServer 'git -C /home/sxw/PDE/pdeMujunjie show c8ec59bb:rtl/src/pe/pe_top.sv | sha256sum'
5e9f11ce0c77aaacd6e3acaa9386496b6efd84a2c75e25d7104b74b98a35dab7  -
$ LC_ALL=C ssh EDAServer 'git -C /home/sxw/PDE/pdeMujunjie show 4f4d171e:rtl/src/pe/pe_top.sv | sha256sum'
3bd4cbca6da296f5dd483f81d0e8cd16e07bceab92ad484bc8f12c7c3deb196e  -
```

The complete semantic change is:

```diff
-  //    a non-16-bit precision (see tb/tb_pe.sv).
+  //    a non-16-bit precision (see tb/tb_pe_smoke.sv).
```

`4f4d171ee9c31a8c2793ee1dc08b72cbf1e45661` was committed at
`2026-08-05T01:33:21+08:00` with subject `rtl+sim: VCS/Verdi-first sim flow,
20x20 chip targets, restructure leftovers`. It added `tb_pe_smoke.sv`, the
five simulation file lists, `pde_core.sv`, `pde_chip_top.sv`, and
`pde_chip_top_safe.sv` in the same commit.

**Conclusion:** local is the later content state relative to the GitHub file,
but the only `pe_top.sv` change is a comment; synthesized behavior is identical.
This is content evolution through the EDAServer branch, not a direct descendant
relationship between the disconnected Git commit graphs.

### 1.4 Backend netlist RTL provenance

#### RVT / ICC2 line

The original DC log defines and compiles these 15 source files:

```text
$ rg -n -C 3 'analyze|Compiling source file|Presto compilation completed' \
    flow/local_runs/full_clean_20260804/dc/reports/dc.local.log
114:analyze -format sverilog -library WORK $RTL_FILES
116:Compiling source file .../src/common/counter_ce.sv
117:Compiling source file .../src/common/pipeline_delay_bit.sv
118:Compiling source file .../src/pe/pde_q8p7_pkg.sv
119:Compiling source file .../src/pe/r_alu.sv
122:Compiling source file .../src/pe/r_reg.sv
123:Compiling source file .../src/pe/r_dsm.sv
124:Compiling source file .../src/pe/r_status.sv
125:Compiling source file .../src/pe/sol_acc.sv
126:Compiling source file .../src/pe/r_state_ctrl.sv
127:Compiling source file .../src/pe/pe_top.sv
128:Compiling source file .../src/pe_array/pde_memcontrol.sv
129:Compiling source file .../src/pe_array/pde_tcu.sv
130:Compiling source file .../src/pe_array/pde_core.sv
131:Compiling source file .../src/pe_array/pde_chip_top.sv
132:Compiling source file .../src/pe_array/pde_chip_top_safe.sv
133:Presto compilation completed successfully.
```

`pde_top.sv` is present in the source tree but was not an input to this chip-top
synthesis. The resulting netlist is:

```text
$ sha256sum flow/local_runs/full_clean_20260804/dc/results/pde_chip_top_safe.v
0b2ee4fa9eacd5015d83cfb7f5da8fac5806b53e09b0aec0b1ac257283632daa  flow/local_runs/full_clean_20260804/dc/results/pde_chip_top_safe.v
```

ICC2 imported that exact path:

```text
$ rg -n -C 3 'PDE_ICC2: netlist|Loading verilog file' \
    flow/local_runs/full_clean_20260804/icc2/reports/icc2/pnr.local.log
465:PDE_ICC2: netlist=/home/soleil/code/DigitalIC/PDE/pdeMujunjie/flow/local_runs/full_clean_20260804/dc/results/pde_chip_top_safe.v
468:Information: Reading Verilog into new design 'pde_chip_top_safe' in library 'pde_chip_top_safe.dlib'. (VR-012)
469:Loading verilog file '/home/soleil/code/DigitalIC/PDE/pdeMujunjie/flow/local_runs/full_clean_20260804/dc/results/pde_chip_top_safe.v'
470:Number of modules read: 1606
```

Time order is also consistent:

```text
2026-08-04 15:42:02 +0800  DC netlist
2026-08-04 16:40:15 +0800  ICC2 import log
```

All 15 current local source hashes equal the corresponding current EDAServer
hashes. Their local mtimes are between `2026-08-01 01:30` and
`2026-08-01 02:20`, before the DC run. However, no input checksum manifest or
source snapshot exists in the run. `find` found no manifest/checksum file, and
the WORK `.pvl`/`.syn` plus SVF are opaque binary tool products. Therefore:

- input paths and compile success: **confirmed**;
- current local versus current EDAServer bytes: **confirmed 15/15**;
- synthesis-time bytes versus current bytes: **cannot be cryptographically
  verified**;
- evidence of a content mismatch: **none found**.

#### HVT / Innovus line

EDAServer's latest HVT DC log compiles the same logical 15-file set from
`rtl/src/` and reports `Presto compilation completed successfully`:

```text
$ LC_ALL=C ssh EDAServer 'grep -n -E "RTL_FILES|analyze|Compiling source file|Presto compilation completed" /home/sxw/PDE/pdeMujunjie/flow/reports/dc_shell.log'
67:set RTL_FILES [list ...]
88:analyze -format sverilog -library WORK $RTL_FILES
90:Compiling source file .../rtl/src/common/counter_ce.sv
...
107:Compiling source file .../rtl/src/pe_array/pde_chip_top_safe.sv
108:Presto compilation completed successfully.
```

The latest committed change under `rtl/src` is the pre-synthesis commit:

```text
$ LC_ALL=C ssh EDAServer 'git -C /home/sxw/PDE/pdeMujunjie log -1 --format="%H%x09%cI%x09%s" -- rtl/src'
4f4d171ee9c31a8c2793ee1dc08b72cbf1e45661  2026-08-05T01:33:21+08:00  rtl+sim: VCS/Verdi-first sim flow, 20x20 chip targets, restructure leftovers

$ LC_ALL=C ssh EDAServer 'git -C /home/sxw/PDE/pdeMujunjie diff --name-status 4f4d171e HEAD -- rtl/src'
# no output; exit 0
```

HVT DC produced `flow/results/dc/pde_chip_top_safe.v`. The Innovus environment
selected the copied bundle file `pde_chip_top_safe_v2_9ns.v`, and the Innovus
run log proves it was read:

```text
$ rg -n 'Reading verilog netlist' ../pde_hvt_innovus/run_flow.out
94:Reading verilog netlist '/home/soleil/code/DigitalIC/PDE/pde_hvt_innovus/hvt_innovus_bundle/design/pde_chip_top_safe_v2_9ns.v'
```

The netlists are byte-identical:

```text
$ sha256sum ../pde_hvt_innovus/hvt_innovus_bundle/design/pde_chip_top_safe_v2_9ns.v
1d4bff781ebdd16ed8d177f7da8653a73853f69192bb3222397654511cf9fc0c  .../pde_chip_top_safe_v2_9ns.v

$ LC_ALL=C ssh EDAServer 'sha256sum /home/sxw/PDE/pdeMujunjie/flow/results/dc/pde_chip_top_safe.v'
1d4bff781ebdd16ed8d177f7da8653a73853f69192bb3222397654511cf9fc0c  .../pde_chip_top_safe.v
```

The earlier `dc_10ns` and `dc_run1` netlists have different hashes, so they
were not the final Innovus input.

As with the RVT run, HVT DC did not record an input-source checksum manifest.
Git history supplies stronger continuity evidence than the pre-Git local run,
but cannot rule out a hypothetical uncommitted edit-and-revert during the run.

### 1.5 `tb_pe.sv` versus `tb_pe_smoke.sv`

Complete testbench manifests:

| File | Local | EDAServer | GitHub `5a3fd5de` |
|---|---|---|---|
| `tb_pde_top.sv` | `018e64dbac4766bc4a3684bcfd74f51d52ab3241e7beccce26ac86c559eec3e6` | same | same |
| `tb_pe.sv` | absent | `e0456e05e13ee39106c65e476660f7455d384e6ee4af72f5b521a7dfa155e2ec` | same |
| `tb_pe_smoke.sv` | `7d0d7fbc457828cddd893b70bbc0988b4cdb759834ae9f06547e41cd0bfab604` | same | absent |
| `tb_pde_chip_top.sv` | `fefb04f855a2962baf7a913becf2e5eb02ee6916e0c06a153623f5812d15066f` | same | absent |
| `tb_pde_chip_top_param.sv` | `93cd362f49f9413456a41a9a63be0af3ba63c837055051827877bf2e990db48f` | same | absent |
| `tb_pde_chip_top_safe.sv` | `71869a5937cba79a2a5f1517b07f146b228c405dc69894322f671f3efc24659b` | same | absent |
| `pde_chip_wave_dump.sv` | `72368e28edc8e40956da4a8ec49953db7364d4c070cc05493dab2727d4f08339` | same | absent |

Commands:

```text
$ find tb -maxdepth 1 -type f -exec sha256sum {} +
$ find /tmp/pde_sim_restore_stage1.YLchuvNh/edaserver/rtl/tb -maxdepth 1 -type f -exec sha256sum {} +
$ find /tmp/pde_sim_restore_stage1.YLchuvNh/github/tree/rtl/tb -maxdepth 1 -type f -exec sha256sum {} +
```

The complete diff between the two PE tests contains only four renames:

```diff
-// tb_pe.sv : single-PE arithmetic and range detection
+// tb_pe_smoke.sv : single-PE arithmetic and range detection
-module tb_pe;
+module tb_pe_smoke;
-      $display("tb_pe : PASS");
+      $display("tb_pe_smoke : PASS");
-      $fatal(1, "tb_pe : FAIL (%0d errors)", errors);
+      $fatal(1, "tb_pe_smoke : FAIL (%0d errors)", errors);
```

**Conclusion:** `tb_pe_smoke.sv` is a renamed copy with identical test logic.
It is not a reduced smoke subset despite its name. EDAServer keeps both names;
the local copy keeps only `tb_pe_smoke.sv`; GitHub `5a3fd5de` keeps only
`tb_pe.sv`.

### 1.6 EDAServer/local divergence within RTL and simulation scope

Normalized mappings used for this comparison:

| EDAServer | Local |
|---|---|
| `rtl/src/` | `src/` |
| `rtl/tb/` | `tb/` |
| `rtl/reference/` | `matlab/` |
| `rtl/sim/` | `sim_restored/` |
| `rtl/docs/` | `doc/` design-note files only |
| `rtl/README.md` | `README.md` |

Results:

- `src/`: no file-set or content differences (`diff -qr` exit 0).
- `matlab/` versus `rtl/reference/`: both files have matching SHA256.
- `sim_restored/` versus `rtl/sim/`: all seven files match (`diff -qr` exit 0).
- design notes: both Markdown files match by SHA256.
- `tb/`: EDAServer-only `tb_pe.sv`; all six shared files match by SHA256.
- README exists on both sides but differs. EDAServer documents the new
  `rtl/{src,tb,sim,reference,docs}` layout and `tb_pe.sv`; local README still
  documents the old root layout and contains local Git safety text.
- Within the normalized RTL/simulation scope, there are no local-only source,
  testbench, reference, simulation-control, or design-note files.

Evidence:

```text
$ diff -qr src /tmp/pde_sim_restore_stage1.YLchuvNh/edaserver/rtl/src
# no output; exit 0
$ diff -qr tb /tmp/pde_sim_restore_stage1.YLchuvNh/edaserver/rtl/tb
Only in /tmp/pde_sim_restore_stage1.YLchuvNh/edaserver/rtl/tb: tb_pe.sv
$ diff -qr sim_restored /tmp/pde_sim_restore_stage1.YLchuvNh/edaserver/rtl/sim
# no output; exit 0
```

The local and EDAServer Git repositories do not contain one another's baseline
objects:

```text
$ git cat-file -t 14591f959dcdbf7af60c02b1c1e48996587f1fe1
fatal: git cat-file: could not get object info

$ LC_ALL=C ssh EDAServer 'git -C /home/sxw/PDE/pdeMujunjie cat-file -t 2d18730f7af127e61ba6cd436eedf2b58683c72b'
fatal: git cat-file: could not get object info
```

This confirms separate Git histories. It does not imply different RTL bytes;
the file hashes above prove the current RTL source bytes are identical.

## Stage 2 - regression executed and passing (2026-08-06)

### 2.1 VCS availability

Initial state (recorded in the prior session): `vcs -ID` inside the
`synopsys-focal` container failed with
`vcs1: error while loading shared libraries: libelf.so.1`.

Root cause, established from raw evidence:

- `/lib/x86_64-linux-gnu/libelf.so.1 -> libelf-0.176.so` was a dangling
  symlink (the target file was missing from the container).
- `vcs1` is a **32-bit** ELF (`file` output: `ELF 32-bit LSB executable,
  Intel 80386`), so it additionally needs the i386 library, which was also
  missing. The host's `libelf-0.190.so` requires `GLIBC_2.38` and cannot be
  used in the focal (glibc 2.31) container.

Fix (container-internal package operations only; no repository file touched):

```bash
distrobox enter synopsys-focal -- sudo apt-get install --reinstall -y libelf1
distrobox enter synopsys-focal -- sudo apt-get install -y libelf1:i386
```

After the fix `vcs -ID` reports `Compiler version = VCS W-2024.09-SP1` and
`make tools` detects:

```text
SIM      = vcs
vcs      = /home/soleil/synopsys/vcs/W-2024.09-SP1/bin/vcs
verdi    = /home/soleil/synopsys/verdi/W-2024.09-SP1/bin/verdi
iverilog = NOT FOUND
```

License checkout is proven working by the successful compiles below (each VCS
compile performs a real checkout).

### 2.2 Adaptations

Exactly one file edit was required:

| File | Original | New | Reason |
|---|---|---|---|
| `sim_restored/Makefile`, `dsm` target | `python3 $(ROOT)/reference/dsm_sweep.py` | `python3 $(ROOT)/matlab/dsm_sweep.py` | EDAServer layout keeps the model in `rtl/reference/`; the local layout keeps the byte-identical file (sha256 `1e56ec5a…`) in `matlab/`. `$(ROOT)` is `..` = repo root here. |

Non-edit adaptations:

- `SYNOPSYS_ENV=/home/soleil/synopsys/env_synopsys_2024.sh` is passed as a
  make variable (the Makefile default `/ssd0/synopsys/synopsys_bashrc` is the
  EDAServer path). No file change needed.
- `check_golden.py` was **not** modified: its `../matlab` import resolves
  correctly from `sim_restored/` and was validated by execution.
- No RTL, testbench, golden-model, or tolerance change of any kind. The
  comparison remains exact integer equality per grid point.

### 2.3 / 2.4 Results

All targets pass on the current local RTL. `check_golden.py` reports **0
mismatches** in all 8 comparisons (bit-exact against
`golden_model.solve()`):

| Target | Top | Result | Golden check | Wall time |
|---|---|---|---|---|
| `chipsafe` | tb_pde_chip_top_safe (backend top) | PASS (20 updates / 420 cycles, 256-bit scan) | self-checking | 13.7 s |
| `top8` | tb_pde_top 8x8 +4096 | PASS | u_dyn + u_fix: 64 pts, 0 mismatch | 13.9 s |
| `top8neg` | tb_pde_top 8x8 -4096 | PASS | 64 pts, 0 mismatch | 16.8 s |
| `top8mixed` | tb_pde_top 8x8 mixed | PASS | 64 pts, 0 mismatch | 15.8 s |
| `top20` | tb_pde_top 20x20 +4096 (target config) | PASS | 400 pts, 0 mismatch | 14.0 s |
| `pe` | tb_pe_smoke | PASS | self-checking | 10.5 s |
| `chip8` | tb_pde_chip_top | PASS | self-checking | 15.8 s |
| `chip20` | tb_pde_chip_top_param | PASS (6400-bit exact compare) | self-checking | 21.1 s |
| `dsm` | dsm_sweep.py (behavioural) | completed | — | <1 s |

A subsequent single-command `make all` run reproduced every PASS
(8 testbench PASS + 8 `check_golden : PASS`, exit 0) in **88.45 s** total.

### 2.5 Reproducible run method

```bash
# enter the tool container
distrobox enter synopsys-focal
cd /home/soleil/code/DigitalIC/PDE/pdeMujunjie/sim_restored

# full regression (~90 s)
make SYNOPSYS_ENV=/home/soleil/synopsys/env_synopsys_2024.sh all

# clean state for the next run
make SYNOPSYS_ENV=/home/soleil/synopsys/env_synopsys_2024.sh clean
```

Success criterion: exit 0 and eight `check_golden : PASS` lines plus eight
testbench PASS lines; any `mismatches : N` with N > 0 is a failure.

### 2.6 Pre-sync baseline archive

`u_dyn.txt` / `u_fix.txt` from each golden-checked target are preserved as
the **pre-sync-baseline** (the reference for the upcoming reset-synchronizer
RTL change) under:

```text
local_artifacts/vcs/pre-sync-baseline/2026-08-06/
```

with a `MANIFEST.md` recording per-file SHA256, tool version
(VCS W-2024.09-SP1_Full64), configuration, repo HEAD
(`f86c4cf`, `src/` clean), and golden-model hash. Notable property:
`u_dyn` and `u_fix` are hash-identical per configuration (both readout paths
converge to the same grid).

## Unresolved issues

1. Neither backend DC run has a synthesis-time input hash manifest. Exact
   run-time source bytes remain unprovable despite consistent paths, mtimes,
   current hashes, and Git evidence.
2. The `libelf` loss inside the `synopsys-focal` container had an unknown
   cause (both the x86-64 file and the i386 package were absent while the
   symlink survived). If it recurs, rerun the two `apt-get` commands in 2.1.
3. VCS license checkout is proven for compile/simulate; Verdi interactive
   flows (`chip8-fsdb`, `verdi-check`) were not exercised in this stage.
4. No RTL or golden-data change is authorized; this stage made none.
