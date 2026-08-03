# Design notes

Chinese version: [design_notes_zh.md](design_notes_zh.md)

Reference: J. Mu and B. Kim, "A Dynamic-Precision Bit-Serial Computing Hardware
Accelerator for Solving Partial Differential Equations Using Finite Difference
Method," *IEEE JSSC*, vol. 58, no. 2, pp. 543-553, Feb. 2023.

This design keeps the paper's residue-based bit-serial FDM and checkerboard
update, and changes three things. Sections 1-3 are the changes, sections 4-7
are the implementation decisions that fall out of them.

---

## 0. RTL control/datapath hierarchy

The RTL follows a PE-first, PE-array-second hierarchy and separates control
from datapath at both levels:

```
pde_top
|-- pde_tcu                 global FSM, precision and convergence control
|-- pde_memcontrol          boundary selection and serialisation
`-- PE lattice (instantiated NROW x NPE times, owned directly by pde_top)
    `-- pe_top          wiring only
        |-- r_state_ctrl    local bank/Mode/write-enable decode
        |-- r_reg x2        residue bank, one per colour
        |-- r_alu           shared bit-serial ALU
        |-- r_dsm           delta-sigma error feedback
        |-- sol_acc         solution accumulators and scan chain
        `-- r_status        precision/convergence flags
```

`r_state_ctrl` and `pde_tcu` do not hold wide data or perform arithmetic. State
and arithmetic live in the leaf modules; `pe_top` and `pde_top` are structural.

---

## 1. Red/Black folding

In the paper's 21x21 array each PE holds one grid point. Under a checkerboard
update, Red points read only Black neighbours and vice versa, so in any given
operation cycle **half the bit-serial adders in the array are idle** — the
Black PEs are only serialising their residues out while the Red PEs compute.

Here one physical PE holds two horizontally adjacent logical points, one Red
and one Black:

```
20 x 20 logical points   ->   20 x 10 physical PEs
```

Phase 0 computes Red using Black as the source; phase 1 computes Black using
the Red result produced in the same update (this is what keeps it
Gauss-Seidel, not Jacobi). The shared ALU is busy in both phases.

**What folding actually buys.** Utilisation of the bit-serial adder goes
50% -> 100% and the instance count halves, but the *area* saving is modest.
The paper reports sequential logic at 80.73% of PE area against 19.27%
combinational. Folding shares the four bit-serial carry DFFs, but not the
three bottom shift-register DFFs: source serialization and destination
three-way loading happen simultaneously, so both banks need all 16 residue
DFFs. A first-order estimate is:

| | 2 unfolded PEs | 1 folded PE |
|---|---|---|
| sequential | 2 x 80.7 = 161% | ~152% |
| combinational | 2 x 19.3 = 39% | ~25% |
| **total** | **200%** | **~177%** |

so roughly **11%**, not 50%. Throughput and latency are unchanged. Anyone
presenting this work should quote it as an area/utilisation optimisation, not
a speed-up — the speed-up comes from section 2.

**What must be duplicated.** The rule is: a resource can be shared only if it
is never needed by both banks in the *same cycle*.

| block | same-cycle conflict? | folded |
|---|---|---|
| bit-serial adder + carry | no (phases are sequential) | shared |
| residue shift register | **yes** — one rotates out while the other fills | x2 |
| solution accumulator adder | no (two separate commit cycles) | shared |
| `u_red` / `u_black` | yes (state) | x2 |
| DSM error register | yes (state) | x2 |

The residue register row is the one that catches people out. During the Red
phase `r_black` is shifting out to the neighbours in the very same cycle that
`r_red` is being filled by the ALU, so there is no way to time-share them.

---

## 2. Self-triggered dynamic precision

The paper switches `Ser[1:0]` from a schedule computed offline against a
simulated residue-decay curve. Here every PE emits three range flags,

```
fit12 / fit8 / fit4    both banks' residues still representable in 12 / 8 / 4 bits
```

the array ANDs them, and the controller picks the narrowest width that fits
during the one-cycle `S_CHECK` state. No offline characterisation, and the
schedule adapts automatically to boundary conditions the designer never saw.

Range detection needs **no magnitude comparator**: a two's complement value
fits in *n* bits exactly when its top `17-n` bits are all copies of the sign
bit, which is a wide XNOR. See `fits_n` in `pde_q8p7_pkg.sv`.

Measured on the 8x8 uniform-boundary case (`make top8`):

```
dynamic precision : 53 updates, 1039 cycles
fixed 16-bit      : 53 updates, 1855 cycles
speed-up          : 1.78x
```

Update count is identical in both runs, which is the expected result: dynamic
precision changes the *cost* of an update, not the convergence trajectory.

---

## 3. DSM implemented in RTL, and combined with dynamic precision

In the reference paper the delta-sigma modulator is **not in the chip**. It
appears in Section IV (Discussion), introduced with "we can insert a
first-order delta-sigma modulator"; the introduction lists it among the
"potential improvement scenarios" added over the ISSCC'21 conference version;
Fig. 13 is labelled *simulated* and includes a 24-bit curve the 4-16 bit
silicon cannot produce; and neither the measurement section nor the PE summary
table nor Table I mentions it. It was therefore never combined with dynamic
precision, in silicon or in simulation.

Here it is in the datapath. Cost per PE: **4 flip-flops** (2 error bits per
bank) and **one extra full adder** in the first column of the adder tree. The
four carry DFFs from Fig. 8 do not need widening: the DSM bit is injected into
the first top-row adder, whose sign-extension input remains zero.

The two mechanisms are orthogonal. Dynamic precision removes redundant *high*
sign bits; the DSM recycles the two *low* bits discarded by the divide-by-4.
Measured benefit (`make dsm`, uniform boundary, exact answer known):

| grid | boundary | no DSM | with DSM | error reduction |
|---|---|---|---|---|
| 8x8 | 4096 | 255 | 17 | 15.0x |
| 12x12 | 4096 | 788 | 38 | 20.7x |
| 20x20 | 4096 | 2584 | 107 | 24.1x |

### The -1 fixed point

Divide-by-4 is an arithmetic right shift, i.e. truncation toward -inf. If
every residue in the array equals -1:

```
floor((-1 -1 -1 -1)/4) = -1          interior
floor(( 0 -1 -1 -1)/4) = floor(-0.75) = -1    edge
```

This is self-sustaining. `r == 0` is then never reached, the FSM would hang in
`S_CHECK`, and `u` would drift down by 1 per update. The DSM does **not** fix
it: at `sum = -4` the division is exact, the remainder is 0, and there is
nothing to feed back. Positive residues do not have the problem
(`floor(3/4) = 0`), which is why a Laplace problem with all-positive boundary
values looks fine and a Poisson or mixed-sign problem does not.

The convergence test is therefore the symmetric condition `-1 <= r <= 1`
rather than `r == 0`. It must be written explicitly: `fits_n(v,2)` is **not**
equivalent because the representable 2-bit two's-complement range is
`-2 <= r <= 1`. Accepting that extra `-2` makes negative-boundary problems
stop early. The implementation uses `residue_small` in `pde_q8p7_pkg.sv`, and
`CONV_ON_SMALL` selects it.

---

## 4. Divide-by-4 and the sign extension

The quotient must satisfy, bit for bit,

```
r_new = (rN + rS + rE + rW + e) >>> 2
```

with `>>>` an arithmetic shift. Two things have to be right.

**The two LSBs must leave the residue register.** In compute mode,
the residue register (declared directly in `pe_top`) shifts the Sum stream
through a path of length `B-2`. After
exactly B clocks, `sum[0]` and `sum[1]` have fallen out, while
`sum[B-1:2]` remains. Those two discarded bits are also captured as the DSM
remainder. Getting this wrong is a factor-of-4 error that is easy to miss
because the *shape* of the solution still looks plausible.

**The sum of four B-bit signed numbers needs B+2 bits.** `r_alu`
implements the paper's Fig. 8 structure directly:

* the top row has four bit-serial adders and four carry DFFs;
* the middle and bottom rows combinationally unroll two sign-extension steps;
* on the real MSB clock, the three outputs are `Sum`, `MSB1`, and `MSB0`.

The destination register receives the three streams in parallel. At the end
of the MSB clock its active field is

```
q[15:16-B] = {MSB0, MSB1, sum[B-1:2]}
```

which is the exact signed quotient. No extra sign-extension clocks are used:

```
C_update = 2 * B + 3
  B=16 -> 35    B=12 -> 27    B=8 -> 19    B=4 -> 11
```

As in Fig. 9, the default implementation physically places the active word in
`q[15:16-B]`.  Sum, MSB1 and MSB0 always enter fixed positions `q[13]`,
`q[14]` and `q[15]`; precision does not change the shift connection.

This project's self-triggered precision may narrow while a residue written at
the old precision is still live. Rather than storing a per-bank "what
precision is this physically laid out in" tag and realigning the whole word
before its first shift at the new precision, the current design exploits the
fixed Red/Black commit order within one full update to let the layout migrate
by itself over one update cycle.

`pde_tcu` keeps a single global `prec_prev_q` register (the precision used by
the *previous* full update) and decodes `src_prec` there once for the whole
array -- the decision is identical in every PE, so there is no reason to
replicate it 200 times, and it keeps the PEs from having to know how `phase`
is encoded:

```systemverilog
// pde_tcu.sv
assign src_prec = (run_en && !phase) ? prec_prev_q : prec_q;
```

Only the Red-phase run reads Black, which was written by the *previous*
update and has not been rewritten yet this update, so it may still sit at the
old precision. Everything else (the Black-phase run reading Red, written
earlier in this same update; and every commit cycle, which reads the
just-computed destination bank) is at the current precision.

Worked example, P8 narrowing to P4 with Black holding −3:

| stage | source bank | tap | result |
|---|---|---|---|
| transition Red phase | Black (old layout) | `q[8]` (old) | emits old bits 0..3 = `1101` = −3, correct; Red is written in the new layout `q[15:12]` |
| transition Black phase | Red (**already new layout**) | `q[12]` (new) | normal; Black is fully overwritten by the new result |
| every later update | both new layout | `q[12]` | steady state |

Three things make this work: **(1)** the tap sits at `q[16-B]` and each clock
shifts the whole word right by one and feeds the tap back into `q[15]`, which
is exactly a circular right-rotate of the active window, restored after B
shifts. **(2)** Emitting only `B_new` bits during the transition is legal --
the precondition for narrowing is precisely "the value already fits in the
narrower field," so the old value's low 4 bits *are* the complete value and
bit 3 is its sign bit, which is what `r_alu`'s final-cycle correction
rows need. **(3)** Black is left mid-rotation and scrambled by the transition
phase, but it is the destination bank in the very next phase and gets fully
overwritten; the write connection `{calc_bits, q[13:1]}` carries no precision
information of its own, so the new value naturally lands in the new layout.

**This scheme has a hard precondition: precision may only narrow, never
widen.** Going the other way (say P4 to P8) breaks it, because `q[11:8]` of
the wider window holds leftover garbage from rotation and shifting. The
convergence algorithm already guarantees residues only decay (the average of
four values that fit in B bits still fits in B bits, and adding the DSM
`err<=3` does not overflow it), but that is a property of the algorithm, not
of the circuit, so `pde_tcu` turns it into a hardware guarantee with one
2-bit comparator:

```systemverilog
// P16(00) < P12(01) < P8(10) < P4(11): larger code = narrower word,
// so taking the max is exactly "narrow only"
assign prec_next = (prec_d > prec_q) ? prec_d : prec_q;
```

A simulation-only warning fires if the clamp ever actually engages. No
regression case triggers it -- i.e. the clamp is currently pure insurance and
changes no behaviour (the bit-identical regression numbers confirm this) --
but if a future equation or boundary condition does trigger it, the whole
transition scheme has to be re-examined.

Cost comparison: a per-bank precision tag (4 flops per PE, 800 across a 20x10
array) plus a full 16-bit repack network, replaced by **one global 2-bit
register, one 2-bit comparator, and a 1-bit-wide 4:1 tap mux per PE**.

---

## 5. Residue representation

The residue-bank logic (declared directly in `pe_top.sv`, one `always_ff`
per colour) follows the paper's **high-aligned** physical layout:

| precision | physical active field | canonical (unpacked) value |
|---|---|---|
| 16 bit | `q[15:0]` | `q[15:0]` |
| 12 bit | `q[15:4]` | sign-extended to 16 bit |
| 8 bit | `q[15:8]` | sign-extended to 16 bit |
| 4 bit | `q[15:12]` | sign-extended to 16 bit |

The Red/Black bank select happens first, so only **one** shared precision MUX
(`unpack_high`) exists in the whole PE, feeding both the shared accumulator
and range detection. Because that single read path can only expose one bank
at a time, `fit12_o/fit8_o/fit4_o/small_o/nonzero_o` can no longer be pure
combinational functions of both banks at once (as they would need to be to
serve `pde_tcu`'s array-wide reduction at `S_CHECK`). Instead each PE latches
its own Red result at `S_RED_CMT` and folds in the live Black result at
`S_BLACK_CMT` (AND for fit12/fit8/fit4/small, OR for nonzero); the combined
value then holds stable through `S_CHECK`, which is the only point `pde_tcu`
actually samples it. This trades two always-on 16-bit unpack networks
(one per bank) for five latched status bits per PE.

The load path is controlled by the `LOAD_ANY_PREC` parameter, default `0`:
incoming values are packed at a fixed P16, and `pack_high(v, P16)` is just
`v`, so the synthesiser folds both packing networks away into plain wires. In
normal whole-chip operation the initial load necessarily happens during the
first update, where precision is necessarily 16-bit, so that network is never
exercised at runtime and there is no reason to synthesise it.

With `LOAD_ANY_PREC=1` the load is packed at the current broadcast `prec`,
for when `pe_top` is exercised directly as a standalone unit --
`tb/tb_pe.sv` deliberately loads at 8-bit and 4-bit precision to test
the pack/unpack path in isolation, so it instantiates with `1`. The two needs
do not have to fight each other.

**Serialisation is non-destructive.** The selected active LSB leaves the PE
and is fed back into `q[15]`. After B shifts the active B-bit word is restored.
The DFF chain is fixed; only the active LSB tap position depends on precision.

---

## 6. Neighbour interconnect

**Transmit needs no direction decoding.** Each PE drives one serial bit onto
all four ports. A neighbour that does not need it this phase ignores it.

**Receive needs exactly one 2:1 MUX**, and only on the horizontal axis:

* *north / south*: no selection. Row parity alternates the left/right colour
  layout, so the vertical neighbour's active bank is always in the same
  logical column as ours. This alignment is automatic and is the nicest
  property of the folding.
* *horizontal*: one of the two horizontal neighbours is the other bank of this
  very PE — it is the transmit bit itself, costing zero routing. The remote
  one is east or west according to `ROW_ODD ^ phase`.

With the convention `Red = ((i+j) even)` and PE(i,k) holding logical columns
`(2k, 2k+1)`:

| row | Red at | Black at | Red-phase remote | Black-phase remote |
|---|---|---|---|---|
| even | left (2k) | right (2k+1) | **west** | **east** |
| odd | right (2k+1) | left (2k) | **east** | **west** |

```systemverilog
assign remote_east_sel = ROW_ODD ^ phase;    // phase 0 = update Red
```

Defining Red as `(i+j)` *odd* inverts this. Either convention works, but it
must match the `ROW_ODD` passed at instantiation and the boundary injection in
`pde_memcontrol.sv`, all three. A mismatch does not produce an error — it
silently solves the wrong stencil. `tb_pde_top.sv` pins it down by comparing
every grid point against `golden_model.py`.

---

## 7. Accumulator: fan-out forward, MUX on the return

The two paths are asymmetric and this is worth stating explicitly, because it
is where a shared adder is easy to get wrong.

* **adder -> banks** is a 1-to-2 **fan-out**. No demux. The unselected bank has
  wrong data on its D input and simply does not enable.
* **banks -> adder** is 2-to-1 and therefore needs a real 16-bit 2:1 MUX. An
  adder has one B-operand port; wired-OR and tri-state are not options in a
  standard-cell flow.

Sharing saves ~16 full adders (~88 GE) and costs ~16 muxes (~37 GE), so about
50 GE net — real but small, and the return routing gets longer. `sol_acc` takes
the shared adder unconditionally. The "shared ALU" claim of this project rests
on the *bit-serial* adder in the residue path, not on this one.

**Readout reuses the same flip-flops.** With `read_en` asserted the 32 accumulator
flops of a PE re-chain into a shift register, `scan_in -> head bank -> tail
bank -> scan_out`, and the PEs chain across the array. One wire in, one wire
out per PE instead of 32. A parallel readout port would be 3200 wires to the
top level on a 20x10 array. Chain order follows logical column order and
therefore flips with row parity — hence `HEAD_IS_RED = ~ROW_ODD`.

---

## 8. Known limitations / next steps

1. **Poisson initial conditions** are supported by the `load_*` ports on the
   PE and array but are not exercised by a testbench. The initial residue is
   `-(delta^2 f(x,y))/4`.
2. **No multigrid.** Restriction/prolongation and the V-cycle schedule are not
   implemented; the accelerator is a single-grid red/black solver. Do not
   describe it as a multigrid design.
3. **Array reconfiguration** — adding 1-2 configuration bits per PE to force
   selected neighbour inputs to the boundary value would let one array be
   partitioned into several independent sub-problems, or solve non-rectangular
   domains. The boundary MUX needed for it already exists.
4. **Two clock domains not implemented.** The paper uses separate `CK_A` /
   `CK_B`; this design is single-clock with `run_en` / `commit` enables and
   lets the synthesis tool insert clock gating. Same power result, far less
   CDC and DFT trouble.
5. **One solve per reset.** `start` is accepted in `S_IDLE`; starting an
   independent problem after `S_DONE` requires reset because residue,
   accumulator and DSM registers are all persistent architectural state.
