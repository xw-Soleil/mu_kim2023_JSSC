# ============================================================================
# sim/Makefile -- regression for the folded red/black PDE accelerator
#
# The simulator is auto-detected at make time ("version judgement"):
#   * VCS + Verdi  (preferred; pulled in via $(SYNOPSYS_ENV) when not in PATH)
#   * Icarus Verilog fallback for hosts without the Synopsys stack
# Force a choice with SIM=vcs or SIM=iverilog.  `make tools` shows what was
# detected and which versions will be used.
#
# All build products (binaries, logs, dumps) go under build/<target>/.
#
#   make all       full regression on the detected simulator
#   make pe        single-PE arithmetic + range detection
#   make top8      8x8   core, positive uniform boundary  (+ golden check)
#   make top8neg   8x8   core, negative uniform boundary  (+ golden check)
#   make top8mixed 8x8   core, mixed-sign boundaries      (+ golden check)
#   make top20     20x20 core, the target configuration   (+ golden check)
#   make chip8     8x8   chip top, serial readout, self-checking
#   make chip20    20x20 chip top, self-checking (6400-bit exact compare)
#   make chipsafe  chip top wrapped in the safe-control layer
#   make spi8      8x8   chip top behind the SPI-lite bridge (+ golden check)
#   make spi20     20x20 chip top behind the SPI-lite bridge (+ golden check)
#   make spi8-sweep   VCS only: SCLK-ratio sweep (16/10/8 pass, 6/4 probe)
#   make chip8-fsdb   VCS only: 8x8 chip top with FSDB dump
#   make verdi-check  VCS only: batch-verify the FSDB/KDB in Verdi
#   make dsm       DSM on/off accuracy sweep (behavioural model)
# ============================================================================

SHELL := /bin/bash
ROOT  := ..
BUILD := build
BND   ?= 4096

SYNOPSYS_ENV ?= /ssd0/synopsys/synopsys_bashrc
ENV_SH := if [ -f $(SYNOPSYS_ENV) ]; then source $(SYNOPSYS_ENV) >/dev/null 2>&1; fi;

VCS_BIN   := $(shell $(ENV_SH) command -v vcs 2>/dev/null)
VERDI_BIN := $(shell $(ENV_SH) command -v verdi 2>/dev/null)
IV_BIN    := $(shell command -v iverilog 2>/dev/null)

ifeq ($(origin SIM), undefined)
  ifneq ($(strip $(VCS_BIN)),)
    SIM := vcs
  else
    SIM := iverilog
  endif
endif

VCS       := $(ENV_SH) vcs
VERDI     := $(ENV_SH) verdi
VCS_FLAGS ?= -full64 -sverilog -timescale=1ns/1ps -debug_access+all -kdb

# FSDB support: Verdi W-2024.09+ uses VERDI_HOME + -debug_access (already in
# VCS_FLAGS).  Older releases need the explicit PLI table and archive.
VERDI_ROOT ?= $(abspath $(dir $(VERDI_BIN))..)
NOVAS_PLI  := $(VERDI_ROOT)/share/PLI/VCS/LINUX64

ifdef VERDI_HOME
  FSDB_PLI :=
else
  FSDB_PLI := -P $(NOVAS_PLI)/novas.tab $(NOVAS_PLI)/pli.a
endif

IV  := iverilog -g2012
VVP := vvp

.PHONY: all tools pe top8 top8neg top8mixed top20 chip8 chip20 chipsafe \
        spi8 spi20 spi8-sweep dsm \
        chip8-fsdb verdi-check need-vcs need-iv clean \
        vcs-all vcs-pe vcs-top8 vcs-top8neg vcs-top8mixed vcs-top20 \
        vcs-chip8 vcs-chip20 vcs-chipsafe vcs-spi8 vcs-spi20 vcs-spi8-sweep \
        iverilog-all iverilog-pe iverilog-top8 iverilog-top8neg \
        iverilog-top8mixed iverilog-top20 iverilog-chip8 iverilog-chip20 \
        iverilog-chipsafe iverilog-spi8 iverilog-spi20

all:       $(SIM)-all
pe:        $(SIM)-pe
top8:      $(SIM)-top8
top8neg:   $(SIM)-top8neg
top8mixed: $(SIM)-top8mixed
top20:     $(SIM)-top20
chip8:     $(SIM)-chip8
chip20:    $(SIM)-chip20
chipsafe:  $(SIM)-chipsafe
spi8:      $(SIM)-spi8
spi20:     $(SIM)-spi20
spi8-sweep: vcs-spi8-sweep

tools:
	@echo "SIM      = $(SIM)   (override with SIM=vcs | SIM=iverilog)"
	@echo "vcs      = $(if $(strip $(VCS_BIN)),$(VCS_BIN),NOT FOUND)"
	@if [ -n "$(strip $(VCS_BIN))" ]; then $(VCS) -ID 2>/dev/null | grep -m1 'vcs script version' || true; fi
	@echo "verdi    = $(if $(strip $(VERDI_BIN)),$(VERDI_BIN),NOT FOUND)"
	@echo "iverilog = $(if $(strip $(IV_BIN)),$(IV_BIN),NOT FOUND)"
	@if [ -n "$(strip $(IV_BIN))" ]; then $(IV_BIN) -V 2>/dev/null | head -1 || true; fi

need-vcs:
	@test -n "$(strip $(VCS_BIN))" || { echo "ERROR: vcs not found in PATH or via $(SYNOPSYS_ENV); use SIM=iverilog or fix SYNOPSYS_ENV"; exit 1; }

need-iv:
	@test -n "$(strip $(IV_BIN))" || { echo "ERROR: iverilog not found; on this server use SIM=vcs"; exit 1; }

# ----------------------------------------------------------------------------
# VCS + Verdi toolchain
# ----------------------------------------------------------------------------

vcs-all: vcs-pe vcs-top8 vcs-top8neg vcs-top8mixed vcs-top20 \
         vcs-chip8 vcs-chip20 vcs-chipsafe vcs-spi8 vcs-spi20 dsm

vcs-pe: need-vcs
	@mkdir -p $(BUILD)/pe
	$(VCS) $(VCS_FLAGS) -top tb_pe_smoke \
	      -Mdir=$(BUILD)/pe/csrc -o $(BUILD)/pe/simv \
	      -f rtl.f $(ROOT)/tb/tb_pe_smoke.sv -l $(BUILD)/pe/compile.log
	cd $(BUILD)/pe && ./simv -l run.log

vcs-top8: need-vcs
	@mkdir -p $(BUILD)/top8
	$(VCS) $(VCS_FLAGS) -top tb_pde_top \
	      +define+NROW_P=8 +define+NCOL_P=8 +define+BND_P=$(BND) +define+MIXED_P=0 \
	      -Mdir=$(BUILD)/top8/csrc -o $(BUILD)/top8/simv \
	      -f rtl.f $(ROOT)/tb/tb_pde_top.sv -l $(BUILD)/top8/compile.log
	cd $(BUILD)/top8 && ./simv -l run.log
	python3 ref/check_golden.py $(BUILD)/top8/u_dyn.txt 8 8 $(BND)
	python3 ref/check_golden.py $(BUILD)/top8/u_fix.txt 8 8 $(BND)

vcs-top8neg: need-vcs
	@mkdir -p $(BUILD)/top8neg
	$(VCS) $(VCS_FLAGS) -top tb_pde_top \
	      +define+NROW_P=8 +define+NCOL_P=8 +define+BND_P=-4096 +define+MIXED_P=0 \
	      -Mdir=$(BUILD)/top8neg/csrc -o $(BUILD)/top8neg/simv \
	      -f rtl.f $(ROOT)/tb/tb_pde_top.sv -l $(BUILD)/top8neg/compile.log
	cd $(BUILD)/top8neg && ./simv -l run.log
	python3 ref/check_golden.py $(BUILD)/top8neg/u_dyn.txt 8 8 -4096
	python3 ref/check_golden.py $(BUILD)/top8neg/u_fix.txt 8 8 -4096

vcs-top8mixed: need-vcs
	@mkdir -p $(BUILD)/top8mixed
	$(VCS) $(VCS_FLAGS) -top tb_pde_top \
	      +define+NROW_P=8 +define+NCOL_P=8 +define+BND_P=0 +define+MIXED_P=1 \
	      -Mdir=$(BUILD)/top8mixed/csrc -o $(BUILD)/top8mixed/simv \
	      -f rtl.f $(ROOT)/tb/tb_pde_top.sv -l $(BUILD)/top8mixed/compile.log
	cd $(BUILD)/top8mixed && ./simv -l run.log
	python3 ref/check_golden.py $(BUILD)/top8mixed/u_dyn.txt 8 8 mixed
	python3 ref/check_golden.py $(BUILD)/top8mixed/u_fix.txt 8 8 mixed

vcs-top20: need-vcs
	@mkdir -p $(BUILD)/top20
	$(VCS) $(VCS_FLAGS) -top tb_pde_top \
	      +define+NROW_P=20 +define+NCOL_P=20 +define+BND_P=$(BND) +define+MIXED_P=0 \
	      -Mdir=$(BUILD)/top20/csrc -o $(BUILD)/top20/simv \
	      -f rtl.f $(ROOT)/tb/tb_pde_top.sv -l $(BUILD)/top20/compile.log
	cd $(BUILD)/top20 && ./simv -l run.log
	python3 ref/check_golden.py $(BUILD)/top20/u_dyn.txt 20 20 $(BND)
	python3 ref/check_golden.py $(BUILD)/top20/u_fix.txt 20 20 $(BND)

vcs-chip8: need-vcs
	@mkdir -p $(BUILD)/chip8
	$(VCS) $(VCS_FLAGS) -top tb_pde_chip_top \
	      -Mdir=$(BUILD)/chip8/csrc -o $(BUILD)/chip8/simv \
	      -f chip.f -l $(BUILD)/chip8/compile.log
	cd $(BUILD)/chip8 && ./simv -l run.log

vcs-chip20: need-vcs
	@mkdir -p $(BUILD)/chip20
	$(VCS) $(VCS_FLAGS) -top tb_pde_chip_top_param \
	      -Mdir=$(BUILD)/chip20/csrc -o $(BUILD)/chip20/simv \
	      -f chip20.f -l $(BUILD)/chip20/compile.log
	cd $(BUILD)/chip20 && ./simv -l run.log

vcs-chipsafe: need-vcs
	@mkdir -p $(BUILD)/chipsafe
	$(VCS) $(VCS_FLAGS) -top tb_pde_chip_top_safe \
	      -Mdir=$(BUILD)/chipsafe/csrc -o $(BUILD)/chipsafe/simv \
	      -f chip_safe.f -l $(BUILD)/chipsafe/compile.log
	cd $(BUILD)/chipsafe && ./simv -l run.log

vcs-spi8: need-vcs
	@mkdir -p $(BUILD)/spi8
	$(VCS) $(VCS_FLAGS) -top tb_pde_chip_top_spi \
	      +define+NROW_P=8 +define+NCOL_P=8 \
	      -Mdir=$(BUILD)/spi8/csrc -o $(BUILD)/spi8/simv \
	      -f chip_spi.f -l $(BUILD)/spi8/compile.log
	cd $(BUILD)/spi8 && ./simv -l run.log
	python3 ref/check_golden.py $(BUILD)/spi8/u_dyn.txt 8 8 4096

vcs-spi20: need-vcs
	@mkdir -p $(BUILD)/spi20
	$(VCS) $(VCS_FLAGS) -top tb_pde_chip_top_spi \
	      -Mdir=$(BUILD)/spi20/csrc -o $(BUILD)/spi20/simv \
	      -f chip_spi.f -l $(BUILD)/spi20/compile.log
	cd $(BUILD)/spi20 && ./simv -l run.log
	python3 ref/check_golden.py $(BUILD)/spi20/u_dyn.txt 20 20 4096

# SCLK-frequency sweep on the 8x8 build: ratios 16/10/8 must pass (spec floor
# is f_core/8); 6 and 4 probe the real break point and are informational only.
vcs-spi8-sweep: vcs-spi8
	cd $(BUILD)/spi8 && for r in 16 10 8; do \
	  ./simv +SCLK_RATIO=$$r -l run_r$$r.log || exit 1; done
	-cd $(BUILD)/spi8 && for r in 6 4; do \
	  ./simv +SCLK_RATIO=$$r -l run_r$$r.log; done
	@echo "sweep done: ratios 16/10/8 passed; see run_r6/run_r4 logs for the probe"

chip8-fsdb: need-vcs
ifndef VERDI_HOME
	@test -d "$(NOVAS_PLI)" || { echo "ERROR: set VERDI_HOME or VERDI_ROOT for FSDB support"; exit 1; }
endif
	@mkdir -p $(BUILD)/chip8-fsdb
	$(VCS) $(VCS_FLAGS) -top tb_pde_chip_top \
	      $(FSDB_PLI) \
	      -Mdir=$(BUILD)/chip8-fsdb/csrc -o $(BUILD)/chip8-fsdb/simv \
	      -f chip8_wave.f -l $(BUILD)/chip8-fsdb/compile.log
	cd $(BUILD)/chip8-fsdb && ./simv -l run.log

verdi-check: need-vcs
	$(VERDI) -batch -nologo -top tb_pde_chip_top \
	         -f chip8_wave.f \
	         -ssf $(BUILD)/chip8-fsdb/pde_chip_top8.fsdb \
	         -dbdir $(BUILD)/chip8-fsdb/simv.daidir \
	         -logdir $(BUILD)/chip8-fsdb/verdi_check

# ----------------------------------------------------------------------------
# Icarus Verilog fallback (top20/chip20 excluded from `all`: very slow)
# ----------------------------------------------------------------------------

iverilog-all: iverilog-pe iverilog-top8 iverilog-top8neg iverilog-top8mixed dsm

iverilog-pe: need-iv
	@mkdir -p $(BUILD)/pe
	$(IV) -o $(BUILD)/pe/pe_smoke.vvp -f rtl.f $(ROOT)/tb/tb_pe_smoke.sv
	cd $(BUILD)/pe && $(VVP) pe_smoke.vvp

iverilog-top8: need-iv
	@mkdir -p $(BUILD)/top8
	$(IV) -DNROW_P=8 -DNCOL_P=8 -DBND_P=$(BND) -DMIXED_P=0 \
	      -o $(BUILD)/top8/top8.vvp -f rtl.f $(ROOT)/tb/tb_pde_top.sv
	cd $(BUILD)/top8 && $(VVP) top8.vvp
	python3 ref/check_golden.py $(BUILD)/top8/u_dyn.txt 8 8 $(BND)
	python3 ref/check_golden.py $(BUILD)/top8/u_fix.txt 8 8 $(BND)

iverilog-top8neg: need-iv
	@mkdir -p $(BUILD)/top8neg
	$(IV) -DNROW_P=8 -DNCOL_P=8 -DBND_P=-4096 -DMIXED_P=0 \
	      -o $(BUILD)/top8neg/top8neg.vvp -f rtl.f $(ROOT)/tb/tb_pde_top.sv
	cd $(BUILD)/top8neg && $(VVP) top8neg.vvp
	python3 ref/check_golden.py $(BUILD)/top8neg/u_dyn.txt 8 8 -4096
	python3 ref/check_golden.py $(BUILD)/top8neg/u_fix.txt 8 8 -4096

iverilog-top8mixed: need-iv
	@mkdir -p $(BUILD)/top8mixed
	$(IV) -DNROW_P=8 -DNCOL_P=8 -DBND_P=0 -DMIXED_P=1 \
	      -o $(BUILD)/top8mixed/top8mixed.vvp -f rtl.f $(ROOT)/tb/tb_pde_top.sv
	cd $(BUILD)/top8mixed && $(VVP) top8mixed.vvp
	python3 ref/check_golden.py $(BUILD)/top8mixed/u_dyn.txt 8 8 mixed
	python3 ref/check_golden.py $(BUILD)/top8mixed/u_fix.txt 8 8 mixed

iverilog-top20: need-iv
	@mkdir -p $(BUILD)/top20
	$(IV) -DNROW_P=20 -DNCOL_P=20 -DBND_P=$(BND) -DMIXED_P=0 \
	      -o $(BUILD)/top20/top20.vvp -f rtl.f $(ROOT)/tb/tb_pde_top.sv
	cd $(BUILD)/top20 && $(VVP) top20.vvp
	python3 ref/check_golden.py $(BUILD)/top20/u_dyn.txt 20 20 $(BND)
	python3 ref/check_golden.py $(BUILD)/top20/u_fix.txt 20 20 $(BND)

iverilog-chip8: need-iv
	@mkdir -p $(BUILD)/chip8
	$(IV) -s tb_pde_chip_top -o $(BUILD)/chip8/chip8.vvp -f chip.f
	cd $(BUILD)/chip8 && $(VVP) chip8.vvp

iverilog-chip20: need-iv
	@mkdir -p $(BUILD)/chip20
	$(IV) -s tb_pde_chip_top_param -o $(BUILD)/chip20/chip20.vvp -f chip20.f
	cd $(BUILD)/chip20 && $(VVP) chip20.vvp

iverilog-chipsafe: need-iv
	@mkdir -p $(BUILD)/chipsafe
	$(IV) -s tb_pde_chip_top_safe -o $(BUILD)/chipsafe/chipsafe.vvp -f chip_safe.f
	cd $(BUILD)/chipsafe && $(VVP) chipsafe.vvp

iverilog-spi8: need-iv
	@mkdir -p $(BUILD)/spi8
	$(IV) -DNROW_P=8 -DNCOL_P=8 -s tb_pde_chip_top_spi \
	      -o $(BUILD)/spi8/spi8.vvp -f chip_spi.f
	cd $(BUILD)/spi8 && $(VVP) spi8.vvp
	python3 ref/check_golden.py $(BUILD)/spi8/u_dyn.txt 8 8 4096

iverilog-spi20: need-iv
	@mkdir -p $(BUILD)/spi20
	$(IV) -s tb_pde_chip_top_spi -o $(BUILD)/spi20/spi20.vvp -f chip_spi.f
	cd $(BUILD)/spi20 && $(VVP) spi20.vvp
	python3 ref/check_golden.py $(BUILD)/spi20/u_dyn.txt 20 20 4096

dsm:
	python3 ref/dsm_sweep.py

clean:
	rm -rf $(BUILD)
