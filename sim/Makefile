# ============================================================================
# rtl/sim/Makefile -- regression for the folded red/black PDE accelerator
#
# The simulator is auto-detected at make time ("version judgement"):
#   * VCS + Verdi  (preferred; pulled in via $(SYNOPSYS_ENV) when not in PATH)
#   * Icarus Verilog fallback for hosts without the Synopsys stack
# Force a choice with SIM=vcs or SIM=iverilog.  `make tools` shows what was
# detected and which versions will be used.
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
#   make chip8-fsdb   VCS only: 8x8 chip top with FSDB dump (Verdi PLI)
#   make verdi-check  VCS only: batch-verify the FSDB/KDB in Verdi
#   make dsm       DSM on/off accuracy sweep (behavioural model)
# ============================================================================

SHELL := /bin/bash
ROOT  := ..
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
# Verdi install root is derived from the detected binary (bin/verdi -> root)
VERDI_ROOT ?= $(abspath $(dir $(VERDI_BIN))..)
NOVAS_PLI  := $(VERDI_ROOT)/share/PLI/VCS/LINUX64

IV  := iverilog -g2012
VVP := vvp

.PHONY: all tools pe top8 top8neg top8mixed top20 chip8 chip20 chipsafe dsm \
        chip8-fsdb verdi-check need-vcs need-iv clean \
        vcs-all vcs-pe vcs-top8 vcs-top8neg vcs-top8mixed vcs-top20 \
        vcs-chip8 vcs-chip20 vcs-chipsafe \
        iverilog-all iverilog-pe iverilog-top8 iverilog-top8neg \
        iverilog-top8mixed iverilog-top20 iverilog-chip8 iverilog-chip20 \
        iverilog-chipsafe

all:       $(SIM)-all
pe:        $(SIM)-pe
top8:      $(SIM)-top8
top8neg:   $(SIM)-top8neg
top8mixed: $(SIM)-top8mixed
top20:     $(SIM)-top20
chip8:     $(SIM)-chip8
chip20:    $(SIM)-chip20
chipsafe:  $(SIM)-chipsafe

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
         vcs-chip8 vcs-chip20 vcs-chipsafe dsm

vcs-pe: need-vcs
	$(VCS) $(VCS_FLAGS) -top tb_pe_smoke \
	      -Mdir=csrc_vcs_pe -o simv_vcs_pe \
	      -f rtl.f $(ROOT)/tb/tb_pe_smoke.sv -l vcs_pe_compile.log
	./simv_vcs_pe -l vcs_pe_run.log

vcs-top8: need-vcs
	$(VCS) $(VCS_FLAGS) -top tb_pde_top \
	      +define+NROW_P=8 +define+NCOL_P=8 +define+BND_P=$(BND) +define+MIXED_P=0 \
	      -Mdir=csrc_vcs_top8 -o simv_vcs_top8 \
	      -f rtl.f $(ROOT)/tb/tb_pde_top.sv -l vcs_top8_compile.log
	./simv_vcs_top8 -l vcs_top8_run.log
	python3 check_golden.py u_dyn.txt 8 8 $(BND)
	python3 check_golden.py u_fix.txt 8 8 $(BND)

vcs-top8neg: need-vcs
	$(VCS) $(VCS_FLAGS) -top tb_pde_top \
	      +define+NROW_P=8 +define+NCOL_P=8 +define+BND_P=-4096 +define+MIXED_P=0 \
	      -Mdir=csrc_vcs_top8neg -o simv_vcs_top8neg \
	      -f rtl.f $(ROOT)/tb/tb_pde_top.sv -l vcs_top8neg_compile.log
	./simv_vcs_top8neg -l vcs_top8neg_run.log
	python3 check_golden.py u_dyn.txt 8 8 -4096
	python3 check_golden.py u_fix.txt 8 8 -4096

vcs-top8mixed: need-vcs
	$(VCS) $(VCS_FLAGS) -top tb_pde_top \
	      +define+NROW_P=8 +define+NCOL_P=8 +define+BND_P=0 +define+MIXED_P=1 \
	      -Mdir=csrc_vcs_top8mixed -o simv_vcs_top8mixed \
	      -f rtl.f $(ROOT)/tb/tb_pde_top.sv -l vcs_top8mixed_compile.log
	./simv_vcs_top8mixed -l vcs_top8mixed_run.log
	python3 check_golden.py u_dyn.txt 8 8 mixed
	python3 check_golden.py u_fix.txt 8 8 mixed

vcs-top20: need-vcs
	$(VCS) $(VCS_FLAGS) -top tb_pde_top \
	      +define+NROW_P=20 +define+NCOL_P=20 +define+BND_P=$(BND) +define+MIXED_P=0 \
	      -Mdir=csrc_vcs_top20 -o simv_vcs_top20 \
	      -f rtl.f $(ROOT)/tb/tb_pde_top.sv -l vcs_top20_compile.log
	./simv_vcs_top20 -l vcs_top20_run.log
	python3 check_golden.py u_dyn.txt 20 20 $(BND)
	python3 check_golden.py u_fix.txt 20 20 $(BND)

vcs-chip8: need-vcs
	$(VCS) $(VCS_FLAGS) -top tb_pde_chip_top \
	      -Mdir=csrc_vcs_chip8 -o simv_vcs_chip8 \
	      -f chip.f -l vcs_chip8_compile.log
	./simv_vcs_chip8 -l vcs_chip8_run.log

vcs-chip20: need-vcs
	$(VCS) $(VCS_FLAGS) -top tb_pde_chip_top_param \
	      -Mdir=csrc_vcs_chip20 -o simv_vcs_chip20 \
	      -f chip20.f -l vcs_chip20_compile.log
	./simv_vcs_chip20 -l vcs_chip20_run.log

vcs-chipsafe: need-vcs
	$(VCS) $(VCS_FLAGS) -top tb_pde_chip_top_safe \
	      -Mdir=csrc_vcs_chipsafe -o simv_vcs_chipsafe \
	      -f chip_safe.f -l vcs_chipsafe_compile.log
	./simv_vcs_chipsafe -l vcs_chipsafe_run.log

chip8-fsdb: need-vcs
	@test -d "$(NOVAS_PLI)" || { echo "ERROR: Verdi PLI not found at $(NOVAS_PLI); set VERDI_ROOT"; exit 1; }
	$(VCS) $(VCS_FLAGS) -top tb_pde_chip_top \
	      -P $(NOVAS_PLI)/novas.tab $(NOVAS_PLI)/pli.a \
	      -Mdir=csrc_vcs_chip8_fsdb -o simv_vcs_chip8_fsdb \
	      -f chip8_wave.f -l vcs_chip8_fsdb_compile.log
	./simv_vcs_chip8_fsdb -l vcs_chip8_fsdb_run.log

verdi-check: need-vcs
	$(VERDI) -batch -nologo -top tb_pde_chip_top \
	         -f chip8_wave.f -ssf pde_chip_top8.fsdb \
	         -dbdir simv_vcs_chip8_fsdb.daidir \
	         -logdir verdi_chip8_check

# ----------------------------------------------------------------------------
# Icarus Verilog fallback (top20/chip20 excluded from `all`: very slow)
# ----------------------------------------------------------------------------

iverilog-all: iverilog-pe iverilog-top8 iverilog-top8neg iverilog-top8mixed dsm

iverilog-pe: need-iv
	$(IV) -o pe_smoke.vvp -f rtl.f $(ROOT)/tb/tb_pe_smoke.sv
	$(VVP) pe_smoke.vvp

iverilog-top8: need-iv
	$(IV) -DNROW_P=8 -DNCOL_P=8 -DBND_P=$(BND) -DMIXED_P=0 -o top8.vvp \
	      -f rtl.f $(ROOT)/tb/tb_pde_top.sv
	$(VVP) top8.vvp
	python3 check_golden.py u_dyn.txt 8 8 $(BND)
	python3 check_golden.py u_fix.txt 8 8 $(BND)

iverilog-top8neg: need-iv
	$(IV) -DNROW_P=8 -DNCOL_P=8 -DBND_P=-4096 -DMIXED_P=0 -o top8neg.vvp \
	      -f rtl.f $(ROOT)/tb/tb_pde_top.sv
	$(VVP) top8neg.vvp
	python3 check_golden.py u_dyn.txt 8 8 -4096
	python3 check_golden.py u_fix.txt 8 8 -4096

iverilog-top8mixed: need-iv
	$(IV) -DNROW_P=8 -DNCOL_P=8 -DBND_P=0 -DMIXED_P=1 -o top8mixed.vvp \
	      -f rtl.f $(ROOT)/tb/tb_pde_top.sv
	$(VVP) top8mixed.vvp
	python3 check_golden.py u_dyn.txt 8 8 mixed
	python3 check_golden.py u_fix.txt 8 8 mixed

iverilog-top20: need-iv
	$(IV) -DNROW_P=20 -DNCOL_P=20 -DBND_P=$(BND) -DMIXED_P=0 -o top20.vvp \
	      -f rtl.f $(ROOT)/tb/tb_pde_top.sv
	$(VVP) top20.vvp
	python3 check_golden.py u_dyn.txt 20 20 $(BND)
	python3 check_golden.py u_fix.txt 20 20 $(BND)

iverilog-chip8: need-iv
	$(IV) -s tb_pde_chip_top -o chip8.vvp -f chip.f
	$(VVP) chip8.vvp

iverilog-chip20: need-iv
	$(IV) -s tb_pde_chip_top_param -o chip20.vvp -f chip20.f
	$(VVP) chip20.vvp

iverilog-chipsafe: need-iv
	$(IV) -s tb_pde_chip_top_safe -o chipsafe.vvp -f chip_safe.f
	$(VVP) chipsafe.vvp

dsm:
	python3 $(ROOT)/matlab/dsm_sweep.py

clean:
	rm -f *.vvp *.vcd *.fsdb *.log u_dyn.txt u_fix.txt ucli.key novas.conf novas.rc
	rm -rf csrc_* simv_* *.daidir verdi_chip8_check verdiLog
