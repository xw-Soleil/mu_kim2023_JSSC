# Mu & Kim 2023 PDE Accelerator

This repository contains two active implementations of the folded red/black
dynamic-precision PDE accelerator:

- `model/demo_golden_model.m`: standalone MATLAB algorithm and fixed-point model.
- `rtl/`: SystemVerilog implementation, testbenches, and Python reference checks.

## Project Layout

```text
model/      MATLAB golden model, paper reproduction, and explorations
rtl/        synthesizable RTL, testbenches, simulation, and Python references
docs/       paper and datapath documentation
```

## Run the MATLAB Model

```matlab
run('model/demo_golden_model.m')
```

## Run RTL Regressions

```sh
make -C rtl/sim pe
make -C rtl/sim top8
make -C rtl/sim top8neg
make -C rtl/sim top8mixed
```

Run `make -C rtl/sim top20` for the target 20x20 configuration. It is slower
under Icarus Verilog.

The active golden model is `model/demo_golden_model.m`. Supporting reproduction
experiments and design explorations live under `model/reproduction/` and
`model/explorations/`.