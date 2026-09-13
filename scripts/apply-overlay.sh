#!/usr/bin/env bash
# apply-overlay.sh <方案目录>   把 <方案目录>/deploy/ 的配置落到 <方案目录>/upstream/。
# 幂等。modelhub 每次 start 前在 head 与 worker 上各调一次；fetch-upstream.sh 拉完也调用。
#
# 调用方可通过环境变量传入本机角色与显存占比，本脚本原样透传给 deploy/overlay.sh：
#   MH_ROLE=master|worker  MH_GPU_MEM_UTIL=0.78
#   MH_GPU_MEM_UTIL_MASTER=0.78 MH_GPU_MEM_UTIL_WORKER=0.90   （可选，见 scripts/lib-overlay.sh）
# 不传时各 overlay 不碰显存键。
set -euo pipefail
scheme=$(cd "$1" && pwd)
up=$scheme/upstream
[ -d "$up" ] || { echo "apply-overlay: $up 不存在，先跑 scripts/fetch-upstream.sh" >&2; exit 1; }
export MH_ROLE="${MH_ROLE:-}" MH_GPU_MEM_UTIL="${MH_GPU_MEM_UTIL:-}" \
       MH_GPU_MEM_UTIL_MASTER="${MH_GPU_MEM_UTIL_MASTER:-}" MH_GPU_MEM_UTIL_WORKER="${MH_GPU_MEM_UTIL_WORKER:-}"
if [ -x "$scheme/deploy/overlay.sh" ]; then
  "$scheme/deploy/overlay.sh" "$up"
  echo "overlay: $scheme/deploy -> $up${MH_ROLE:+ (role=$MH_ROLE gpu_mem_util=${MH_GPU_MEM_UTIL:-unset})}"
fi
