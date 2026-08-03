# ============================================================================
# sim/Makefile -- regression for the folded red/black PDE accelerator
#
#   make pe        single-PE arithmetic + range detection
#   make top8      8x8  positive uniform boundary
#   make top8neg   8x8  negative uniform boundary (signed convergence)
#   make top8mixed 8x8  nonuniform mixed-sign boundaries (routing/indexing)
#   make top20     20x20 grid (the target configuration) -- slow under iverilog
#   make dsm       DSM on/off accuracy sweep in the behavioural model
#   make all       single-PE + all 8x8 regressions + DSM sweep
#
# Tested with Icarus Verilog 12.0 (apt install iverilog).
# For a commercial simulator just pass the same file list to vcs/xrun/vsim.
# ============================================================================

IV      := iverilog -g2012
VVP     := vvp
ROOT    := ..

RTL_COMMON := $(ROOT)/src/common/counter_ce.sv \
              $(ROOT)/src/common/pipeline_delay_bit.sv

RTL_PE  := $(ROOT)/src/pe/pde_q8p7_pkg.sv \
		           $(ROOT)/src/pe/r_alu.sv \
		           $(ROOT)/src/pe/r_reg.sv \
		           $(ROOT)/src/pe/r_dsm.sv \
		           $(ROOT)/src/pe/r_status.sv \
		           $(ROOT)/src/pe/sol_acc.sv \
		           $(ROOT)/src/pe/r_state_ctrl.sv \
		           $(ROOT)/src/pe/pe_top.sv

RTL_ALL := $(RTL_COMMON) \
	           $(RTL_PE) \
	           $(ROOT)/src/pe_array/pde_memcontrol.sv \
	           $(ROOT)/src/pe_array/pde_tcu.sv \
	           $(ROOT)/src/pe_array/pde_top.sv

BND ?= 4096

.PHONY: all pe top8 top8neg top8mixed top20 dsm clean

all: pe top8 top8neg top8mixed dsm

pe:
	$(IV) -o pe.vvp $(RTL_COMMON) $(RTL_PE) $(ROOT)/tb/tb_pe.sv
	$(VVP) pe.vvp

top8:
	$(IV) -DNROW_P=8 -DNCOL_P=8 -DBND_P=$(BND) -DMIXED_P=0 -o top8.vvp \
	      $(RTL_ALL) $(ROOT)/tb/tb_pde_top.sv
	$(VVP) top8.vvp
	python3 check_golden.py u_dyn.txt 8 8 $(BND)
	python3 check_golden.py u_fix.txt 8 8 $(BND)

top8neg:
	$(IV) -DNROW_P=8 -DNCOL_P=8 -DBND_P=-4096 -DMIXED_P=0 -o top8neg.vvp \
	      $(RTL_ALL) $(ROOT)/tb/tb_pde_top.sv
	$(VVP) top8neg.vvp
	python3 check_golden.py u_dyn.txt 8 8 -4096
	python3 check_golden.py u_fix.txt 8 8 -4096

top8mixed:
	$(IV) -DNROW_P=8 -DNCOL_P=8 -DBND_P=0 -DMIXED_P=1 -o top8mixed.vvp \
	      $(RTL_ALL) $(ROOT)/tb/tb_pde_top.sv
	$(VVP) top8mixed.vvp
	python3 check_golden.py u_dyn.txt 8 8 mixed
	python3 check_golden.py u_fix.txt 8 8 mixed

top20:
	$(IV) -DNROW_P=20 -DNCOL_P=20 -DBND_P=$(BND) -DMIXED_P=0 -o top20.vvp \
	      $(RTL_ALL) $(ROOT)/tb/tb_pde_top.sv
	$(VVP) top20.vvp
	python3 check_golden.py u_dyn.txt 20 20 $(BND)

dsm:
	python3 $(ROOT)/reference/dsm_sweep.py

clean:
	rm -f *.vvp *.vcd u_dyn.txt u_fix.txt *.log
