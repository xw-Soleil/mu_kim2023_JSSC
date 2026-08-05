#!/bin/bash
# ECO10 stage 2：正确约束下的 route_opt 收敛（fillers out -> route_opt -> route_eco -> fillers in -> 全套检查）。
# 详见 eco10_stage2v_transfix.tcl 头部注释。
#
#   distrobox enter synopsys-focal -- flow/local/run_eco10_stage2.sh
#
# snps_no_udev.sh 绕开已知的 SCL udev 崩溃；启动重试继续作为保护，
# 判据是 '^PDE_ECO10_S2V_BEGIN'。
set -o pipefail
LOCAL_DIR=$(dirname "$(readlink -f "$0")")
source "$LOCAL_DIR/env_local.sh"
SNPS_RUN=$LOCAL_DIR/snps_no_udev.sh

ECO10_ROOT=$PDE_REPO_ROOT/flow/local_runs/icc2_signoff_eco10
export PDE_ECO10_DESIGN_LIB=${PDE_ECO10_DESIGN_LIB:-$ECO10_ROOT/work/icc2/pde_chip_top_safe.dlib}
export PDE_ECO10_REPORT_DIR=${PDE_ECO10_REPORT_DIR:-$ECO10_ROOT/reports/icc2/closure6}

# console log 跟随报告目录命名，避免多轮互相覆盖
LOG=$ECO10_ROOT/reports/icc2/$(basename "$PDE_ECO10_REPORT_DIR").console.log
MAX_ATTEMPTS=25
mkdir -p "$(dirname "$LOG")"

if [ ! -e "$PDE_ECO10_DESIGN_LIB" ]; then
  echo "design lib 不存在：$PDE_ECO10_DESIGN_LIB"
  exit 1
fi

cd "$PDE_REPO_ROOT" || exit 1

for attempt in $(seq 1 $MAX_ATTEMPTS); do
  echo "=== eco10 stage2v 尝试 $attempt/$MAX_ATTEMPTS 开始 $(date) ==="
  "$SNPS_RUN" icc2_shell -f flow/local/eco10_stage2v_transfix.tcl 2>&1 | tee "$LOG"
  echo "=== eco10 stage2v 尝试 $attempt 结束 $(date) ==="

  if grep -qE "^PDE_ECO10_S2V_DONE" "$LOG"; then
    echo "RESULT: OK"
    exit 0
  fi

  if grep -qE "^PDE_ECO10_S2V_BEGIN" "$LOG"; then
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
