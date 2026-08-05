#!/usr/bin/env bash
set -euo pipefail

# Convert a completed v27 OpenROAD hard-pass log into an atomic, checksummed
# manifest.  This deliberately refuses diagnostic/intermediate DEF files.

repo_root=/home/sxw/PDE/pdeMujunjie
result_dir=${repo_root}/flow/results/openroad
work_dir=${repo_root}/flow/work/openroad
report_dir=${repo_root}/flow/reports/openroad
tag=${1:?usage: publish_v27_hardpass_manifest_v1.sh drt_buffd2_sN_v27}

if [[ ! "$tag" =~ ^drt_buffd2_s[123]_v27$ ]]; then
  echo "unsupported v27 route tag: $tag" >&2
  exit 2
fi

log=${report_dir}/40_${tag}.log
final_def=${result_dir}/45_${tag}_final.def
final_odb=${work_dir}/45_${tag}_final.odb
final_lvs=${result_dir}/45_${tag}_final_lvs.v
final_nofill=${result_dir}/45_${tag}_final_nofill.v
final_sdc=${result_dir}/45_${tag}_final.sdc
manifest=${result_dir}/45_${tag}_final.pass

for required in "$log" "$final_def" "$final_odb" "$final_lvs" "$final_nofill" "$final_sdc"; do
  if [[ ! -s "$required" ]]; then
    echo "missing hard-pass artifact: $required" >&2
    exit 3
  fi
done

if ! grep -Fxq "PDE_OPENROAD_PHYSICAL_HARD_PASS tag=$tag" "$log"; then
  echo "OpenROAD hard-pass marker is absent from $log" >&2
  exit 4
fi
if [[ ! "$log" -nt "$final_sdc" ]]; then
  echo "OpenROAD log is not newer than the last final artifact: $log" >&2
  exit 5
fi
if ! grep -q '^DESIGN pde_chip_top_safe ;' "$final_def"; then
  echo "unexpected or missing final DEF top: $final_def" >&2
  exit 6
fi

tmp_manifest=$(mktemp "${result_dir}/.45_${tag}_final.pass.XXXXXX")
trap 'rm -f "$tmp_manifest"' EXIT
{
  echo PDE_OPENROAD_PHYSICAL_HARD_PASS
  echo "tag=$tag"
  echo "def=$final_def"
  echo "def_sha256=$(sha256sum "$final_def" | awk '{print $1}')"
  echo "odb=$final_odb"
  echo "odb_sha256=$(sha256sum "$final_odb" | awk '{print $1}')"
  echo "lvs=$final_lvs"
  echo "lvs_sha256=$(sha256sum "$final_lvs" | awk '{print $1}')"
  echo "nofill=$final_nofill"
  echo "nofill_sha256=$(sha256sum "$final_nofill" | awk '{print $1}')"
  echo "sdc=$final_sdc"
  echo "sdc_sha256=$(sha256sum "$final_sdc" | awk '{print $1}')"
  echo "log=$log"
  echo "log_sha256=$(sha256sum "$log" | awk '{print $1}')"
} >"$tmp_manifest"
mv -f "$tmp_manifest" "$manifest"
trap - EXIT
echo "PDE_OPENROAD_PASS_MANIFEST_PUBLISHED tag=$tag manifest=$manifest"
