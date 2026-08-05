#!/bin/bash
# Isolated local Synopsys flow: RTL -> DC netlist/SDC -> ICC2 DEF/GDS/netlist/SPEF.
# Run inside the synopsys-focal container through distrobox.
set -euo pipefail

LOCAL_DIR=$(dirname "$(readlink -f "$0")")
source "$LOCAL_DIR/env_local.sh"

RUN_TAG=${PDE_FULL_RUN_TAG:-$(date +%Y%m%d_%H%M%S)}
FULL_ROOT=${PDE_FULL_OUTPUT_ROOT:-$PDE_REPO_ROOT/flow/local_runs/full_$RUN_TAG}
DC_ROOT=$FULL_ROOT/dc
ICC2_ROOT=$FULL_ROOT/icc2

if [ -e "$FULL_ROOT" ]; then
  echo "Full-flow output already exists; refusing to overwrite: $FULL_ROOT"
  exit 1
fi

export PDE_DC_OUTPUT_ROOT=$DC_ROOT
"$LOCAL_DIR/run_dc.sh"

export PDE_DC_NETLIST=$DC_ROOT/results/${PDE_TOP}.v
export PDE_DC_SDC=$DC_ROOT/results/${PDE_TOP}.sdc
export PDE_ICC2_OUTPUT_ROOT=$ICC2_ROOT
export PDE_ICC2_DESIGN_LIB=$ICC2_ROOT/work/icc2/${PDE_TOP}.dlib
"$LOCAL_DIR/run_pnr.sh"

echo "PDE_FULL_FLOW_DONE root=$FULL_ROOT"
echo "DC results: $DC_ROOT/results"
echo "ICC2 results: $ICC2_ROOT/results/icc2"
