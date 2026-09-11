#!/usr/bin/env bash
# apply-overlay.sh <方案目录>   把 <方案目录>/deploy/ 的配置落到 <方案目录>/upstream/。
# 幂等。modelhub 每次 start 前调用；fetch-upstream.sh 拉完也调用。
set -euo pipefail
scheme=$(cd "$1" && pwd)
up=$scheme/upstream
[ -d "$up" ] || { echo "apply-overlay: $up 不存在，先跑 scripts/fetch-upstream.sh" >&2; exit 1; }
if [ -x "$scheme/deploy/overlay.sh" ]; then
  "$scheme/deploy/overlay.sh" "$up"
  echo "overlay: $scheme/deploy -> $up"
fi
