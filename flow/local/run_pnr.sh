#!/bin/bash
# ICC2 布局布线：initialize_floorplan → place_opt → clock_opt → route_auto/route_opt
# → filler → 签核报告 → 写 DEF/GDS/后仿网表/SPEF。
# 在容器里跑：distrobox enter synopsys-focal -- flow/local/run_pnr.sh
#
# snps_no_udev.sh 会绕开 SCL 中不稳定的 udev 枚举路径（原因和回归数据见 README.md）。
# 仍保留启动重试作为保护，但只对脚本输出前的 Internal system error 重试；
# 确定性错误（比如 API 不兼容）直接退出。
#
# 判据全部用 '^' 锚定行首：icc2_shell 会回显脚本源码，源码里的
#   puts "PDE_ICC2_DONE ..."
# 不加锚点会被误判成流程真的跑完了。
set -o pipefail
LOCAL_DIR=$(dirname "$(readlink -f "$0")")
source "$LOCAL_DIR/env_local.sh"
SNPS_RUN=$LOCAL_DIR/snps_no_udev.sh

OUTPUT_ROOT=${PDE_ICC2_OUTPUT_ROOT:-$PDE_REPO_ROOT/flow}
LOG=$OUTPUT_ROOT/reports/icc2/pnr.local.log
RESULT_DIR=$OUTPUT_ROOT/results/icc2
MAX_ATTEMPTS=25
mkdir -p "$(dirname "$LOG")" "$RESULT_DIR"

if [ ! -e "$PDE_REF_NDM" ]; then
  echo "参考 NDM 不存在：$PDE_REF_NDM"
  exit 1
fi

cd "$PDE_REPO_ROOT" || exit 1

for attempt in $(seq 1 $MAX_ATTEMPTS); do
  # pnr.tcl 拒绝覆盖已存在的 design library，每次尝试前清掉上一次的残留。
  [ -e "$PDE_ICC2_DESIGN_LIB" ] && rm -rf "$PDE_ICC2_DESIGN_LIB"

  echo "=== P&R 尝试 $attempt/$MAX_ATTEMPTS 开始 $(date) ==="
  "$SNPS_RUN" icc2_shell -f flow/local/pnr_local.tcl 2>&1 | tee "$LOG"
  status=${PIPESTATUS[0]}
  echo "=== P&R 尝试 $attempt 结束 $(date) ==="

  if [ "$status" -eq 0 ] \
    && grep -qE '^PDE_ICC2_DONE' "$LOG" \
    && [ -s "$RESULT_DIR/${PDE_TOP}.gds" ] \
    && [ -s "$RESULT_DIR/${PDE_TOP}.def" ] \
    && [ -s "$RESULT_DIR/${PDE_TOP}.postroute.v" ]; then
    echo "RESULT: OK"
    ls -la "$RESULT_DIR/"
    exit 0
  fi

  if grep -qE "^PDE_ICC2: top=" "$LOG"; then
    echo "RESULT: FAILED — 已经进入流程后失败，不是启动崩溃。看 $LOG"
    exit 1
  fi

  if ! grep -q "Internal system error, cannot recover" "$LOG"; then
    echo "RESULT: FAILED — 启动阶段的确定性错误，重试没有意义。看 $LOG"
    exit 1
  fi

  echo "[retry] SCL 签 license 时段错误，重来…"
  cp "$LOG" "$LOG.startup-crash.$attempt"
done

echo "RESULT: FAILED — 连续 $MAX_ATTEMPTS 次都在启动阶段崩溃"
exit 1
