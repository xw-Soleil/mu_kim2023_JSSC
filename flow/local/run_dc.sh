#!/bin/bash
# Local Design Compiler entry. Results go to an isolated tree by default so
# the migrated golden DC outputs under flow/results/dc are never overwritten.
set -o pipefail

LOCAL_DIR=$(dirname "$(readlink -f "$0")")
source "$LOCAL_DIR/env_local.sh"
SNPS_RUN=$LOCAL_DIR/snps_no_udev.sh

OUTPUT_ROOT=${PDE_DC_OUTPUT_ROOT:-$PDE_REPO_ROOT/flow/local_runs/dc}
export PDE_DC_OUTPUT_ROOT=$OUTPUT_ROOT
LOG=$OUTPUT_ROOT/reports/dc.local.log

if [ -e "$OUTPUT_ROOT" ]; then
  echo "DC output tree already exists; refusing to overwrite: $OUTPUT_ROOT"
  echo "Set PDE_DC_OUTPUT_ROOT to a new path for another run."
  exit 1
fi

mkdir -p "$OUTPUT_ROOT/reports"
cd "$PDE_REPO_ROOT" || exit 1

echo "=== DC synthesis start $(date) ==="
echo "isolated output: $OUTPUT_ROOT"
"$SNPS_RUN" dc_shell -f flow/dc/synth.tcl 2>&1 | tee "$LOG"
status=${PIPESTATUS[0]}
echo "=== DC synthesis end $(date) ==="

RESULT_DIR=$OUTPUT_ROOT/results
if [ "$status" -eq 0 ] \
  && grep -qE '^PDE_DC_DONE' "$LOG" \
  && [ -s "$RESULT_DIR/${PDE_TOP}.v" ] \
  && [ -s "$RESULT_DIR/${PDE_TOP}.sdc" ]; then
  echo "RESULT: OK"
  ls -lh "$RESULT_DIR"
  exit 0
fi

echo "RESULT: FAILED - see $LOG"
exit 1
