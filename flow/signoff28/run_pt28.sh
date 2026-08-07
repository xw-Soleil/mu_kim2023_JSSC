#!/bin/bash
# Post-route PT signoff runner (one corner per invocation).
# Usage: run_pt28.sh <signoff_root> <WC|BC>
# Prereq: pt_shell in PATH with a reachable license (source the host's
# Synopsys environment first). Machine-specific paths stay out of this script.
set -euo pipefail

ROOT=${1:?usage: run_pt28.sh <signoff_root> <WC|BC>}
CORNER=${2:?usage: run_pt28.sh <signoff_root> <WC|BC>}
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

export PDE28_SIGNOFF_ROOT=$ROOT
export PDE28_PT_CORNER=$CORNER
mkdir -p "$ROOT/pt"
cd "$ROOT/pt"
pt_shell -file "$SCRIPT_DIR/pt_sta28.tcl" 2>&1 | tee "pt_${CORNER}.log"
