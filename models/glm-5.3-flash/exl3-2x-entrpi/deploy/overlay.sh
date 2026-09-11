#!/usr/bin/env bash
# Entrpi kit 读的是 upstream/.env；deploy/.env.entrpi 是本集群的填好值。
# 同时把 kit install.sh 装到 ~/ 的启动/预热脚本链进 upstream/，供 modelhub 的 LAUNCH/WARMUP 使用。
set -euo pipefail
up=$1; here=$(cd "$(dirname "$0")" && pwd)
install -m 0644 "$here/.env.entrpi" "$up/.env"
for s in launch-glm53-vllm-tp2.sh glm53-warmup.sh; do
  [ -e "$up/$s" ] && continue
  [ -x "$HOME/$s" ] && ln -s "$HOME/$s" "$up/$s"
done
true
