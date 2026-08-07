#!/bin/bash
# 28nm Design Compiler entry (bring-up line). Modeled on flow/local/run_dc.sh
# but independent of the 65nm env_local.sh. Run inside the synopsys-focal
# container. Requires a fresh PDE28_DC_OUTPUT_ROOT (refuses to overwrite).
set -o pipefail

LOCAL_DIR=$(dirname "$(readlink -f "$0")")
REPO_ROOT=$(readlink -f "$LOCAL_DIR/../..")
export PDE_REPO_ROOT=$REPO_ROOT
SNPS_RUN=$REPO_ROOT/flow/local/snps_no_udev.sh

SNPS_ENV=${PDE_SNPS_ENV:-$HOME/synopsys/env_synopsys_2024.sh}
if [ -f "$SNPS_ENV" ]; then
  # shellcheck disable=SC1090
  source "$SNPS_ENV" >/dev/null 2>&1
fi

OUTPUT_ROOT=${PDE28_DC_OUTPUT_ROOT:?set PDE28_DC_OUTPUT_ROOT to a new run directory}
export PDE28_DC_OUTPUT_ROOT=$OUTPUT_ROOT
LOG=$OUTPUT_ROOT/reports/dc.local.log

if [ -e "$OUTPUT_ROOT" ]; then
  echo "DC28 output tree already exists; refusing to overwrite: $OUTPUT_ROOT"
  exit 1
fi

mkdir -p "$OUTPUT_ROOT/reports"
cd "$REPO_ROOT" || exit 1

echo "=== DC28 synthesis start $(date) ==="
echo "isolated output: $OUTPUT_ROOT"
"$SNPS_RUN" dc_shell -f flow/dc28/synth28.tcl 2>&1 | tee "$LOG"
status=${PIPESTATUS[0]}
echo "=== DC28 synthesis end $(date) ==="

TOP=${PDE_TOP:-pde_chip_top_safe}
RESULT_DIR=$OUTPUT_ROOT/results
if [ "$status" -eq 0 ] \
  && grep -qE '^PDE_DC28_DONE' "$LOG" \
  && [ -s "$RESULT_DIR/$TOP.v" ] \
  && [ -s "$RESULT_DIR/$TOP.sdc" ]; then
  echo "RESULT: OK"
  ls -lh "$RESULT_DIR"
  exit 0
fi

echo "RESULT: FAILED - see $LOG"
exit 1
