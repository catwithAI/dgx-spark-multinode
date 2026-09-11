#!/usr/bin/env bash
# 把本目录的配置覆盖到上游 checkout。由 scripts/apply-overlay.sh 调用，$1 = upstream/ 路径。
# modelhub 的 ds4-text/start.sh 每次启动前都会跑，所以改 deploy/ 即生效，不用手动同步。
#
# 显存占比：上游 start 脚本会把 head 的 .env.dspark 原样 scp 到 worker，worker 本机 overlay 写的值
# 会被盖掉。所以 .env.dspark 里放 GPU_MEMORY_UTILIZATION_HEAD / _WORKER 两键，compose 按 NODE_RANK
# 选；本脚本在 head 上要把两键都写对（worker 的值来自 MH_GPU_MEM_UTIL_WORKER，没给就留 deploy/ 默认）。
set -euo pipefail
up=$1; here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=../../../../scripts/lib-overlay.sh
. "$here/../../../../scripts/lib-overlay.sh"

# NCCL_IB_GID_INDEX 由 modelhub 在启动时按本机 GID 表重写，覆盖时保留 upstream 里已有的那行。
gid=$(sed -n 's/^NCCL_IB_GID_INDEX=//p' "$up/.env.dspark" 2>/dev/null | tail -1)
install -m 0644 "$here/.env.dspark" "$up/.env.dspark"
[ -n "$gid" ] && sed -i "s|^NCCL_IB_GID_INDEX=.*|NCCL_IB_GID_INDEX=$gid|" "$up/.env.dspark"
install -m 0644 "$here/docker-compose.dspark.yml" "$up/docker-compose.dspark.yml"

if [ -n "${MH_ROLE:-}${MH_GPU_MEM_UTIL:-}${MH_GPU_MEM_UTIL_MASTER:-}${MH_GPU_MEM_UTIL_WORKER:-}" ]; then
  v=$(ov_gpu_util_for master); [ -z "$v" ] || { ov_require_fraction "$v"; ov_set_kv "$up/.env.dspark" GPU_MEMORY_UTILIZATION_HEAD "$v"; }
  v=$(ov_gpu_util_for worker); [ -z "$v" ] || { ov_require_fraction "$v"; ov_set_kv "$up/.env.dspark" GPU_MEMORY_UTILIZATION_WORKER "$v"; }
  if [ "${MH_ROLE:-}" = master ] && [ -z "${MH_GPU_MEM_UTIL_WORKER:-}" ]; then
    echo "overlay(ds4-text): 未给 MH_GPU_MEM_UTIL_WORKER，worker 用 deploy/.env.dspark 的默认值 $(sed -n 's/^GPU_MEMORY_UTILIZATION_WORKER=//p' "$up/.env.dspark")（head 的这份会 scp 到 worker）" >&2
  fi
fi
