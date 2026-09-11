#!/usr/bin/env bash
# 把一台盒子从"各模型自带看门狗 + 各自端口"切到"modelhub 统一编排 + :8888"。
# 在 head 和 worker 上各跑一次。默认 dry-run，--apply 执行。幂等。
set -uo pipefail
APPLY=0; [ "${1:-}" = "--apply" ] && APPLY=1
run() { echo "  + $*"; [ $APPLY = 1 ] && "$@"; }

echo "== 1) 禁掉会跟 modelhub 抢 GPU 的看门狗"
for u in $(systemctl list-unit-files --no-legend 2>/dev/null | awk '{print $1}' | grep -E '^(glm53-supervisor|ds4v-supervisor|ds4v-.*supervis)' ); do
  run sudo systemctl disable --now "$u"
done
echo "   保留 glm53-rail / ds4v-rail：它们只配光口地址，不起容器。"

echo "== 2) 清掉旧 compose project 起的 DeepSeek 容器（新 project 从 upstream/ 起，名字显式固定）"
for c in $(docker ps -aq --filter name=ds4-dspark-2x-vllm-dspark-1 --filter label=com.docker.compose.project=ds4-dspark-2x 2>/dev/null); do
  run docker rm -f "$c"
done

echo "== 3) 各方案的 deploy/ 覆盖到 upstream/（端口 8899/8000 -> 8888、权重 -> /home/ai/models）"
root=$(cd "$(dirname "$0")/.." && pwd)
for lock in "$root"/models/*/*/upstream.lock; do
  scheme=$(dirname "$lock")
  [ -d "$scheme/upstream" ] || { echo "   跳过 $scheme（无 upstream/，先跑 migrate-layout.sh 或 fetch-upstream.sh）"; continue; }
  run "$root/scripts/apply-overlay.sh" "$scheme"
done

[ $APPLY = 1 ] || echo "(dry-run；加 --apply 执行)"
