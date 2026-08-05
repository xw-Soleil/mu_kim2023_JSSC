#!/bin/bash
# 用本地 icc2_lm_shell(W-2024.09) 从 TSMC65LP PDK 源文件重建参考 NDM。
# 在容器里跑：distrobox enter synopsys-focal -- flow/local/run_create_ndm.sh
set -o pipefail
LOCAL_DIR=$(dirname "$(readlink -f "$0")")
source "$LOCAL_DIR/env_local.sh"
SNPS_RUN=$LOCAL_DIR/snps_no_udev.sh

LOG=$PDE_REPO_ROOT/flow/reports/icc2/create_ndm.local.log
ACTIVE_REF_NDM=$PDE_REF_NDM
BUILD_REF_NDM=${PDE_NDM_BUILD_OUTPUT:-$PDE_REPO_ROOT/flow/work/icc2/ref_candidate/tcbn65lp_6lmT1.ndm}

# 默认写入 ref_candidate，绝不覆盖当前 P&R 正在使用的 active NDM。
if [ "$BUILD_REF_NDM" = "$ACTIVE_REF_NDM" ] && [ "${PDE_NDM_ALLOW_ACTIVE_OUTPUT:-0}" != 1 ]; then
  echo "拒绝覆盖当前参考 NDM：$ACTIVE_REF_NDM"
  echo "确需写入该路径时显式设置 PDE_NDM_ALLOW_ACTIVE_OUTPUT=1。"
  exit 1
fi
if [ -e "$BUILD_REF_NDM" ]; then
  echo "构建输出已存在，拒绝覆盖：$BUILD_REF_NDM"
  echo "请设置新的 PDE_NDM_BUILD_OUTPUT，或先人工归档现有测试输出。"
  exit 1
fi

export PDE_REF_NDM=$BUILD_REF_NDM
mkdir -p "$(dirname "$LOG")" "$(dirname "$PDE_REF_NDM")"

cd "$PDE_REPO_ROOT" || exit 1
echo "=== create_ndm 开始 $(date) ==="
echo "现用参考库保持不动：$ACTIVE_REF_NDM"
echo "隔离构建输出：$PDE_REF_NDM"
"$SNPS_RUN" icc2_lm_shell -f flow/icc2/create_ndm.tcl 2>&1 | tee "$LOG"
status=${PIPESTATUS[0]}
echo "=== create_ndm 结束 $(date) ==="

if [ "$status" -eq 0 ] \
  && grep -qE '^PDE_NDM_DONE' "$LOG" \
  && [ -s "$PDE_REF_NDM/reflib.ndm" ]; then
  echo "RESULT: OK"
  du -sh "$PDE_REF_NDM"
else
  echo "RESULT: FAILED — 看 $LOG"
  exit 1
fi
