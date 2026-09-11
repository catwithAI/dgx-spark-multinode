#!/usr/bin/env bash
# 把本目录的配置覆盖到上游 checkout。由 scripts/apply-overlay.sh 调用，$1 = upstream/ 路径。
# modelhub 的 ds4-text/start.sh 每次启动前都会跑，所以改 deploy/ 即生效，不用手动同步。
set -euo pipefail
up=$1; here=$(cd "$(dirname "$0")" && pwd)
# NCCL_IB_GID_INDEX 由 modelhub 在启动时按本机 GID 表重写，覆盖时保留 upstream 里已有的那行。
gid=$(sed -n 's/^NCCL_IB_GID_INDEX=//p' "$up/.env.dspark" 2>/dev/null | tail -1)
install -m 0644 "$here/.env.dspark" "$up/.env.dspark"
[ -n "$gid" ] && sed -i "s|^NCCL_IB_GID_INDEX=.*|NCCL_IB_GID_INDEX=$gid|" "$up/.env.dspark"
install -m 0644 "$here/docker-compose.dspark.yml" "$up/docker-compose.dspark.yml"
