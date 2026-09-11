#!/usr/bin/env bash
# Vision 上游在 66/67 上是按 :8899 起的；统一约定是 :8888。
# 这里不替换整份 env（上游文件格式未入库），只把端口和权重目录改到约定值。
set -euo pipefail
up=$1
for f in "$up"/.env* "$up"/*.env; do
  [ -f "$f" ] || continue
  sed -i 's/^\(VLLM_PORT\|PORT\)=8899$/\1=8888/' "$f"
done
grep -rl ':8899\|port 8899\|PORT=8899' "$up" --include='*.sh' 2>/dev/null | while read -r f; do
  sed -i 's/:8899/:8888/g; s/port 8899/port 8888/g; s/PORT=8899/PORT=8888/g' "$f"
done
if ! grep -rq '8888' "$up"/.env* "$up"/*.sh 2>/dev/null; then
  echo "overlay(vision): 上游里没找到端口设置，请人工确认 $up 监听 8888" >&2
fi
