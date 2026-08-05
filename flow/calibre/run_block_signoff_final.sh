#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
config_file=${PDE_CALIBRE_CONFIG:-${script_dir}/block_signoff_config.sh}
mode=${1:-all}

case "$mode" in
  drc|antenna|all) ;;
  *)
    echo "usage: $0 {drc|antenna|all}" >&2
    exit 2
    ;;
esac

export PDE_CALIBRE_CONFIG=$config_file
"${script_dir}/prepare_block_signoff_decks.sh"
# shellcheck source=block_signoff_config.sh
source "$config_file"

calibre_bin=${PDE_CALIBRE_HOME}/bin/calibre
if [[ ! -x "$calibre_bin" ]]; then
  echo "missing Calibre executable: $calibre_bin" >&2
  exit 2
fi
if [[ ! -s "$PDE_GDS" ]]; then
  echo "missing final routed GDS: $PDE_GDS" >&2
  exit 2
fi
if [[ ! "$PDE_CALIBRE_TURBO" =~ ^[1-9][0-9]*$ ]]; then
  echo "PDE_CALIBRE_TURBO must be a positive integer" >&2
  exit 2
fi

export CALIBRE_HOME=$PDE_CALIBRE_HOME
export MGC_HOME=$PDE_CALIBRE_HOME
export MGLS_LICENSE_FILE=$PDE_LICENSE_FILE

run_deck() {
  local kind=$1
  local deck=$2
  local log=$3
  local summary=$4
  echo "PDE_CALIBRE_RUN_START kind=$kind deck=$deck gds=$PDE_GDS top=$PDE_TOP"
  "$calibre_bin" -drc -hier -turbo "$PDE_CALIBRE_TURBO" "$deck" 2>&1 | tee "$log"
  if [[ ! -s "$summary" ]]; then
    echo "Calibre completed without the expected $kind summary: $summary" >&2
    exit 4
  fi
  echo "PDE_CALIBRE_RUN_COMPLETE kind=$kind summary=$summary log=$log"
  echo "PDE_CALIBRE_REVIEW_REQUIRED kind=$kind (process exit alone does not mean zero violations)"
}

if [[ "$mode" == drc || "$mode" == all ]]; then
  run_deck drc "$PDE_DRC_DECK" "$PDE_DRC_LOG" "$PDE_DRC_SUMMARY"
fi
if [[ "$mode" == antenna || "$mode" == all ]]; then
  run_deck antenna "$PDE_ANT_DECK" "$PDE_ANT_LOG" "$PDE_ANT_SUMMARY"
fi

