#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
exec "${script_dir}/prepare_block_signoff_decks_final_v3.sh" "$@"
