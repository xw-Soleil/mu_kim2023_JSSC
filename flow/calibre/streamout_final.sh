#!/usr/bin/env bash
set -euo pipefail

repo_root=/home/sxw/PDE/pdeMujunjie
calibre_home=/ssd0/mentor/Calibre2023/aoj_cal_2023.2_16.9
lef=/ssd0/PDKs/TSMC65nm/STDCELL/std/STD_Cell/tcbn65lp_200b/Back_End/lef/tcbn65lp_200a/lef/tcbn65lp_6lmT1.lef
cell_gds=/ssd0/PDKs/TSMC65nm/STDCELL/std/STD_Cell/tcbn65lp_200b/Back_End/gds/tcbn65lp_200a/tcbn65lp.gds
map_file=${repo_root}/flow/calibre/lefdef_6lmT1_final.map
routed_def=${1:-${repo_root}/flow/results/openroad/40_route.def}
final_gds=${repo_root}/flow/results/openroad/pde_chip_top_safe.gds
fdi_log=${repo_root}/flow/reports/openroad/50_fdi2gds_final.log

# The launcher otherwise follows the user's default Calibre installation,
# which points at an older release even when an absolute launcher is used.
export CALIBRE_HOME=$calibre_home
export MGC_HOME=$calibre_home
export MGLS_LICENSE_FILE=${MGLS_LICENSE_FILE:-/ssd0/mentor/license/license.dat}
mkdir -p "${repo_root}/flow/results/openroad" "${repo_root}/flow/reports/openroad"

for required in "$routed_def" "$lef" "$cell_gds" "$map_file"; do
  if [[ ! -s "$required" ]]; then
    echo "missing required stream-out input: $required" >&2
    exit 2
  fi
done

"${calibre_home}/bin/fdi2gds" \
  -system LEFDEF \
  -lef "$lef" \
  -def "$routed_def" \
  -cellGDS "$cell_gds" \
  -outFile "$final_gds" \
  -map "$map_file" \
  -logFile "$fdi_log"

test -s "$final_gds"
echo "PDE_CALIBRE_GDS_PASS output=$final_gds stack=SP6M4x1z"
