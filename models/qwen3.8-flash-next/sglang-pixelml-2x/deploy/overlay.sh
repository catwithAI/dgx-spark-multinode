#!/usr/bin/env bash
# PixelML SGLang 配方：每台各自一份 upstream/.env（start-cluster.sh 不同步 env，只 ssh 到各机跑
# start-node.sh，后者从本机 .env 取 MEM_FRACTION_STATIC 传给 --mem-fraction-static）。
# 所以显存占比按角色写本机这份即可。NCCL_IB_GID_INDEX 由 modelhub 每次启动前重写，这里不碰。
set -euo pipefail
up=$1; here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=../../../../scripts/lib-overlay.sh
. "$here/../../../../scripts/lib-overlay.sh"

if [ -n "${MH_GPU_MEM_UTIL:-}" ]; then
  ov_require_fraction "$MH_GPU_MEM_UTIL"
  if [ -f "$up/.env" ]; then
    ov_set_kv "$up/.env" MEM_FRACTION_STATIC "$MH_GPU_MEM_UTIL"
  else
    echo "overlay(qwen38): $up/.env 不存在，显存占比 ${MH_GPU_MEM_UTIL} 未写入" >&2
  fi
fi
true
