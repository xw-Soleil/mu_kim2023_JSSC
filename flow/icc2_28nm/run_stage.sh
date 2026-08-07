#!/bin/bash
# Run one stage of the 28nm ICC2 flow inside the synopsys-focal container:
#   flow/icc2_28nm/run_stage.sh s01_setup
# Judged by artifacts, not exit codes: each stage prints PDE28_STAGE_DONE
# and the caller checks the stage's expected products.
set -o pipefail
STAGE=${1:?usage: run_stage.sh <sNN_name>}
LOCAL_DIR=$(dirname "$(readlink -f "$0")")
REPO_ROOT=$(readlink -f "$LOCAL_DIR/../..")
export PDE_REPO_ROOT=$REPO_ROOT
SNPS_RUN=$REPO_ROOT/flow/local/snps_no_udev.sh

SNPS_ENV=${PDE_SNPS_ENV:-$HOME/synopsys/env_synopsys_2024.sh}
if [ -f "$SNPS_ENV" ]; then
  # shellcheck disable=SC1090
  source "$SNPS_ENV" >/dev/null 2>&1
fi

OUTPUT_ROOT=${PDE28_ICC2_OUTPUT_ROOT:-$REPO_ROOT/flow/local_runs/icc2_28nm_20260807}
export PDE28_ICC2_OUTPUT_ROOT=$OUTPUT_ROOT
mkdir -p "$OUTPUT_ROOT/reports"
LOG=$OUTPUT_ROOT/reports/$STAGE.log

cd "$REPO_ROOT" || exit 1
echo "=== $STAGE start $(date) ==="
"$SNPS_RUN" icc2_shell -batch -file "$LOCAL_DIR/$STAGE.tcl" 2>&1 | tee "$LOG"
status=${PIPESTATUS[0]}
echo "=== $STAGE end $(date) status=$status ==="
grep -q "PDE28_STAGE_DONE $STAGE" "$LOG" && echo "STAGE_MARKER: OK" || echo "STAGE_MARKER: MISSING"
exit $status
