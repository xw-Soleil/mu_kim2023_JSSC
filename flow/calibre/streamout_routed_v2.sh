#!/usr/bin/env bash
set -euo pipefail

repo_root=/home/sxw/PDE/pdeMujunjie
calibre_home=/ssd0/mentor/Calibre2023/aoj_cal_2023.2_16.9
lef=/ssd0/PDKs/TSMC65nm/STDCELL/std/STD_Cell/tcbn65lp_200b/Back_End/lef/tcbn65lp_200a/lef/tcbn65lp_6lmT1.lef
cell_gds=/ssd0/PDKs/TSMC65nm/STDCELL/std/STD_Cell/tcbn65lp_200b/Back_End/gds/tcbn65lp_200a/tcbn65lp.gds
map_file=${repo_root}/flow/calibre/lefdef_6lmT1_final.map
routed_def=${1:?usage: streamout_routed_v2.sh ROUTED_DEF [OUTPUT_GDS]}
final_gds=${2:-${repo_root}/flow/results/openroad/pde_chip_top_safe.gds}
result_dir=$(dirname -- "$final_gds")
report_dir=${repo_root}/flow/reports/openroad
fdi_log=${report_dir}/50_fdi2gds_routed_v2.log

export CALIBRE_HOME=$calibre_home
export MGC_HOME=$calibre_home
export MGLS_LICENSE_FILE=${MGLS_LICENSE_FILE:-/ssd0/mentor/license/license.dat}
mkdir -p "$result_dir" "$report_dir"

for required in "$routed_def" "$lef" "$cell_gds" "$map_file"; do
  if [[ ! -s "$required" ]]; then
    echo "missing required stream-out input: $required" >&2
    exit 2
  fi
done
if ! grep -q '^DESIGN pde_chip_top_safe ;' "$routed_def"; then
  echo "unexpected or missing DEF top in $routed_def" >&2
  exit 3
fi

tmp_dir=$(mktemp -d "${result_dir}/.pde_fdi2gds.XXXXXX")
tmp_gds=${tmp_dir}/pde_chip_top_safe.gds
"${calibre_home}/bin/fdi2gds" \
  -system LEFDEF \
  -lef "$lef" \
  -def "$routed_def" \
  -cellGDS "$cell_gds" \
  -outFile "$tmp_gds" \
  -map "$map_file" \
  -logFile "$fdi_log"

test -s "$tmp_gds"
mv -f "$tmp_gds" "$final_gds"
rmdir "$tmp_dir"
echo "PDE_CALIBRE_GDS_PASS output=$final_gds stack=SP6M4x1z"
