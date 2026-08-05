#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
config_file=${PDE_CALIBRE_CONFIG:-${script_dir}/block_signoff_config.sh}
if [[ ! -r "$config_file" ]]; then
  echo "missing readable Calibre configuration: $config_file" >&2
  exit 2
fi
# shellcheck source=block_signoff_config.sh
source "$config_file"

required_vars=(
  PDE_TOP PDE_GDS PDE_DRC_ARCHIVE PDE_DRC_ARCHIVE_MEMBER
  PDE_ANT_ARCHIVE_MEMBER PDE_DRC_SOURCE_SHA256 PDE_ANT_SOURCE_SHA256
  PDE_CALIBRE_WORK_ROOT PDE_CALIBRE_RESULT_ROOT PDE_CALIBRE_REPORT_ROOT
  PDE_DRC_DECK PDE_ANT_DECK PDE_DECK_MANIFEST
  PDE_DRC_RDB PDE_DRC_SUMMARY PDE_ANT_RDB PDE_ANT_SUMMARY
)
for var_name in "${required_vars[@]}"; do
  if [[ -z ${!var_name:-} ]]; then
    echo "empty required configuration variable: $var_name" >&2
    exit 2
  fi
done
if [[ ! "$PDE_TOP" =~ ^[A-Za-z_][A-Za-z0-9_$]*$ ]]; then
  echo "invalid GDS top-cell name: $PDE_TOP" >&2
  exit 2
fi
for path_value in \
  "$PDE_GDS" "$PDE_DRC_RDB" "$PDE_DRC_SUMMARY" \
  "$PDE_ANT_RDB" "$PDE_ANT_SUMMARY"; do
  if [[ "$path_value" != /* ]]; then
    echo "Calibre deck paths must be absolute: $path_value" >&2
    exit 2
  fi
  case "$path_value" in
    *'@'*|*'&'*|*'"'*)
      echo "unsupported character in Calibre deck path: $path_value" >&2
      exit 2
      ;;
  esac
done
if [[ ! -s "$PDE_DRC_ARCHIVE" ]]; then
  echo "missing TSMC65 Calibre rule archive: $PDE_DRC_ARCHIVE" >&2
  exit 2
fi

vendor_root=${PDE_CALIBRE_WORK_ROOT}/vendor_23a
mkdir -p \
  "$vendor_root" "$(dirname -- "$PDE_DRC_DECK")" \
  "$PDE_CALIBRE_RESULT_ROOT" "$PDE_CALIBRE_REPORT_ROOT"
tar -xzf "$PDE_DRC_ARCHIVE" -C "$vendor_root" \
  "$PDE_DRC_ARCHIVE_MEMBER" "$PDE_ANT_ARCHIVE_MEMBER"
drc_source=${vendor_root}/${PDE_DRC_ARCHIVE_MEMBER}
ant_source=${vendor_root}/${PDE_ANT_ARCHIVE_MEMBER}

check_sha256() {
  local file=$1 expected=$2 label=$3 actual
  actual=$(sha256sum "$file" | awk '{print $1}')
  if [[ "$actual" != "$expected" ]]; then
    echo "$label SHA-256 mismatch: expected=$expected actual=$actual file=$file" >&2
    exit 3
  fi
}
check_sha256 "$drc_source" "$PDE_DRC_SOURCE_SHA256" "DRC source deck"
check_sha256 "$ant_source" "$PDE_ANT_SOURCE_SHA256" "antenna source deck"

cp -- "$drc_source" "$PDE_DRC_DECK"
cp -- "$ant_source" "$PDE_ANT_DECK"

assert_count() {
  local expected=$1 expression=$2 file=$3 label=$4 actual
  actual=$(grep -Ec "$expression" "$file" || true)
  if [[ "$actual" != "$expected" ]]; then
    echo "$label count mismatch: expected=$expected actual=$actual file=$file" >&2
    exit 3
  fi
}

# Audit the pristine 23a option block first.  CHECK_LOW_DENSITY appears twice:
# once in the option block and once inside a FULL_CHIP conditional.
assert_count 2 '^#DEFINE[[:space:]]+CHECK_LOW_DENSITY([[:space:]]|$)' "$PDE_DRC_DECK" "source CHECK_LOW_DENSITY"
assert_count 1 '^#DEFINE[[:space:]]+FULL_CHIP([[:space:]]|$)' "$PDE_DRC_DECK" "source FULL_CHIP"
assert_count 1 '^#DEFINE[[:space:]]+WLCSP_SEALRING([[:space:]]|$)' "$PDE_DRC_DECK" "source WLCSP_SEALRING"
assert_count 1 '^//#DEFINE[[:space:]]+LP([[:space:]]|$)' "$PDE_DRC_DECK" "source commented LP"
assert_count 0 '^#DEFINE[[:space:]]+(GP|LPG)([[:space:]]|$)' "$PDE_DRC_DECK" "source GP/LPG"
assert_count 1 '^#DEFINE[[:space:]]+FRONT_END([[:space:]]|$)' "$PDE_DRC_DECK" "source FRONT_END"
assert_count 1 '^#DEFINE[[:space:]]+BACK_END([[:space:]]|$)' "$PDE_DRC_DECK" "source BACK_END"

# Use '@' as the sed delimiter so the ERE alternation in the LP macro boundary
# is not confused with the substitution delimiter.
sed -E -i \
  -e 's@^#DEFINE CHECK_LOW_DENSITY@//#DEFINE CHECK_LOW_DENSITY@' \
  -e 's@^#DEFINE FULL_CHIP@//#DEFINE FULL_CHIP@' \
  -e 's@^#DEFINE WLCSP_SEALRING@//#DEFINE WLCSP_SEALRING@' \
  -e 's@^//#DEFINE LP([[:space:]]|$)@#DEFINE LP\1@' \
  "$PDE_DRC_DECK"

patch_run_io() {
  local deck=$1 rdb=$2 summary=$3
  assert_count 1 '^LAYOUT PATH[[:space:]]+' "$deck" "LAYOUT PATH"
  assert_count 1 '^LAYOUT PRIMARY[[:space:]]+' "$deck" "LAYOUT PRIMARY"
  assert_count 1 '^DRC RESULTS DATABASE[[:space:]]+' "$deck" "DRC RESULTS DATABASE"
  assert_count 1 '^DRC SUMMARY REPORT[[:space:]]+' "$deck" "DRC SUMMARY REPORT"
  sed -E -i \
    -e "s@^LAYOUT PATH[[:space:]].*@LAYOUT PATH \"${PDE_GDS}\"@" \
    -e "s@^LAYOUT PRIMARY[[:space:]].*@LAYOUT PRIMARY \"${PDE_TOP}\"@" \
    -e "s@^DRC RESULTS DATABASE[[:space:]].*@DRC RESULTS DATABASE \"${rdb}\"@" \
    -e "s@^DRC SUMMARY REPORT[[:space:]].*@DRC SUMMARY REPORT \"${summary}\"@" \
    "$deck"
}
patch_run_io "$PDE_DRC_DECK" "$PDE_DRC_RDB" "$PDE_DRC_SUMMARY"
patch_run_io "$PDE_ANT_DECK" "$PDE_ANT_RDB" "$PDE_ANT_SUMMARY"

# Enforce the exact generated block-level LP policy.
assert_count 0 '^#DEFINE[[:space:]]+CHECK_LOW_DENSITY([[:space:]]|$)' "$PDE_DRC_DECK" "generated CHECK_LOW_DENSITY"
assert_count 0 '^#DEFINE[[:space:]]+FULL_CHIP([[:space:]]|$)' "$PDE_DRC_DECK" "generated FULL_CHIP"
assert_count 0 '^#DEFINE[[:space:]]+WLCSP_SEALRING([[:space:]]|$)' "$PDE_DRC_DECK" "generated WLCSP_SEALRING"
assert_count 1 '^#DEFINE[[:space:]]+LP([[:space:]]|$)' "$PDE_DRC_DECK" "generated LP"
assert_count 0 '^#DEFINE[[:space:]]+(GP|LPG)([[:space:]]|$)' "$PDE_DRC_DECK" "generated GP/LPG"
assert_count 1 '^#DEFINE[[:space:]]+FRONT_END([[:space:]]|$)' "$PDE_DRC_DECK" "generated FRONT_END"
assert_count 1 '^#DEFINE[[:space:]]+BACK_END([[:space:]]|$)' "$PDE_DRC_DECK" "generated BACK_END"

{
  echo "source_archive=$PDE_DRC_ARCHIVE"
  echo "source_drc_member=$PDE_DRC_ARCHIVE_MEMBER"
  echo "source_drc_sha256=$PDE_DRC_SOURCE_SHA256"
  echo "source_ant_member=$PDE_ANT_ARCHIVE_MEMBER"
  echo "source_ant_sha256=$PDE_ANT_SOURCE_SHA256"
  echo "layout_path=$PDE_GDS"
  echo "layout_primary=$PDE_TOP"
  echo "drc_switches=FRONT_END,BACK_END,LP"
  echo "drc_disabled=FULL_CHIP,WLCSP_SEALRING,CHECK_LOW_DENSITY,GP,LPG"
  sha256sum "$PDE_DRC_DECK" "$PDE_ANT_DECK"
} > "$PDE_DECK_MANIFEST"

echo "PDE_CALIBRE_DECKS_PREPARED drc=$PDE_DRC_DECK antenna=$PDE_ANT_DECK"
echo "PDE_CALIBRE_DECK_MANIFEST path=$PDE_DECK_MANIFEST"
if [[ ! -s "$PDE_GDS" ]]; then
  echo "PDE_CALIBRE_GDS_PENDING path=$PDE_GDS" >&2
fi


