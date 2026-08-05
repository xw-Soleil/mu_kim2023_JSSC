#!/usr/bin/env bash
set -euo pipefail

# Stream out only an OpenROAD final DEF whose exact identity and checksum are
# recorded in a hard-pass manifest.  The tagged GDS is retained; the canonical
# GDS is published atomically only after fdi2gds succeeds.

repo_root=/home/sxw/PDE/pdeMujunjie
result_dir=${repo_root}/flow/results/openroad
report_dir=${repo_root}/flow/reports/openroad
calibre_home=/ssd0/mentor/Calibre2023/aoj_cal_2023.2_16.9
lef=/ssd0/PDKs/TSMC65nm/STDCELL/std/STD_Cell/tcbn65lp_200b/Back_End/lef/tcbn65lp_200a/lef/tcbn65lp_6lmT1.lef
cell_gds=/ssd0/PDKs/TSMC65nm/STDCELL/std/STD_Cell/tcbn65lp_200b/Back_End/gds/tcbn65lp_200a/tcbn65lp.gds
map_file=${repo_root}/flow/calibre/lefdef_6lmT1_final.map
manifest=${1:?usage: streamout_hardpass_manifest_v3.sh FINAL_PASS_MANIFEST}

field() {
  local key=$1
  awk -F= -v key="$key" '$1 == key {sub(/^[^=]*=/, ""); print; found=1} END {if (!found) exit 1}' "$manifest"
}

if [[ ! -s "$manifest" ]] || ! grep -Fxq PDE_OPENROAD_PHYSICAL_HARD_PASS "$manifest"; then
  echo "missing or invalid OpenROAD hard-pass manifest: $manifest" >&2
  exit 2
fi

tag=$(field tag)
final_def=$(field def)
expected_sha=$(field def_sha256)
if [[ ! "$tag" =~ ^drt_buffd2_s[123]_v(27|29)$ ]]; then
  echo "unsupported hard-pass route tag: $tag" >&2
  exit 3
fi
expected_manifest=${result_dir}/45_${tag}_final.pass
expected_def=${result_dir}/45_${tag}_final.def
if [[ "$manifest" != "$expected_manifest" || "$final_def" != "$expected_def" ]]; then
  echo "manifest/DEF identity does not match tag $tag" >&2
  exit 4
fi

for required in "$final_def" "$lef" "$cell_gds" "$map_file"; do
  if [[ ! -s "$required" ]]; then
    echo "missing required stream-out input: $required" >&2
    exit 5
  fi
done
actual_sha=$(sha256sum "$final_def" | awk '{print $1}')
if [[ "$actual_sha" != "$expected_sha" ]]; then
  echo "final DEF checksum differs from hard-pass manifest" >&2
  exit 6
fi
if ! grep -q '^DESIGN pde_chip_top_safe ;' "$final_def"; then
  echo "unexpected or missing DEF top in $final_def" >&2
  exit 7
fi

export CALIBRE_HOME=$calibre_home
export MGC_HOME=$calibre_home
export MGLS_LICENSE_FILE=${MGLS_LICENSE_FILE:-/ssd0/mentor/license/license.dat}
mkdir -p "$result_dir" "$report_dir"

tagged_gds=${result_dir}/50_${tag}.gds
canonical_gds=${result_dir}/pde_chip_top_safe.gds
fdi_log=${report_dir}/50_${tag}_fdi2gds.log
tmp_dir=$(mktemp -d "${result_dir}/.pde_fdi2gds_${tag}.XXXXXX")
tmp_gds=${tmp_dir}/pde_chip_top_safe.gds
tmp_canonical=${result_dir}/.pde_chip_top_safe.gds.publish
trap 'rm -f "$tmp_gds" "$tmp_canonical"; rmdir "$tmp_dir" 2>/dev/null || true' EXIT

"${calibre_home}/bin/fdi2gds" \
  -system LEFDEF \
  -lef "$lef" \
  -def "$final_def" \
  -cellGDS "$cell_gds" \
  -outFile "$tmp_gds" \
  -map "$map_file" \
  -logFile "$fdi_log"

if [[ ! -s "$tmp_gds" ]]; then
  echo "fdi2gds produced no GDS" >&2
  exit 8
fi
mv -f "$tmp_gds" "$tagged_gds"
cp --reflink=auto "$tagged_gds" "$tmp_canonical"
mv -f "$tmp_canonical" "$canonical_gds"
rmdir "$tmp_dir"
trap - EXIT
echo "PDE_GDS_STREAMOUT_PASS tag=$tag tagged=$tagged_gds canonical=$canonical_gds"
