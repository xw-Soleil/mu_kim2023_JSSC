#!/bin/bash
# 续跑 P&R 的尾部：填充单元 → 签核报告 → 写 DEF/GDS/后仿网表/SPEF。
# 用在 route_opt 已经跑完存盘、但后面某一步失败的情况下，避免重做 place/CTS/route。
#
#   flow/local/run_finish.sh              # 正常跑（含填充单元）
#   PDE_SKIP_FILLERS=1 flow/local/run_finish.sh   # 跳过填充单元
#
# snps_no_udev.sh 绕开已知的 SCL udev 崩溃；启动重试继续作为保护，
# 判据是 '^PDE_FINISH: block='。
set -o pipefail
LOCAL_DIR=$(dirname "$(readlink -f "$0")")
source "$LOCAL_DIR/env_local.sh"
SNPS_RUN=$LOCAL_DIR/snps_no_udev.sh

LOG=$PDE_REPO_ROOT/flow/reports/icc2/finish.local.log
MAX_ATTEMPTS=25
mkdir -p "$(dirname "$LOG")" "$PDE_REPO_ROOT/flow/results/icc2"

if [ ! -e "$PDE_ICC2_DESIGN_LIB" ]; then
  echo "design lib 不存在，没有可续跑的数据：$PDE_ICC2_DESIGN_LIB"
  exit 1
fi

cd "$PDE_REPO_ROOT" || exit 1

for attempt in $(seq 1 $MAX_ATTEMPTS); do
  echo "=== 续跑尝试 $attempt/$MAX_ATTEMPTS 开始 $(date) ==="
  "$SNPS_RUN" icc2_shell -f flow/local/finish.tcl 2>&1 | tee "$LOG"
  echo "=== 续跑尝试 $attempt 结束 $(date) ==="

  if grep -qE "^PDE_ICC2_DONE" "$LOG"; then
    echo "RESULT: OK"
    ls -la "$PDE_REPO_ROOT/flow/results/icc2/"
    exit 0
  fi

  if grep -qE "^PDE_FINISH: block=" "$LOG"; then
    echo "RESULT: FAILED — 已经打开设计后失败，不是启动崩溃。看 $LOG"
    exit 1
  fi

  if ! grep -q "Internal system error, cannot recover" "$LOG"; then
    echo "RESULT: FAILED — 启动阶段的确定性错误，重试没有意义。看 $LOG"
    exit 1
  fi

  echo "[retry] SCL 签 license 时段错误，重来…"
done

echo "RESULT: FAILED — 连续 $MAX_ATTEMPTS 次都在启动阶段崩溃"
exit 1
