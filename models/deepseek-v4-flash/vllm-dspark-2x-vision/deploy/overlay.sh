#!/usr/bin/env bash
# Vision 上游在 66/67 上是按 :8899 起的；统一约定是 :8888。
# 这里不替换整份 env（上游文件格式未入库），只把端口和权重目录改到约定值。
set -euo pipefail
up=$1; here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=../../../../scripts/lib-overlay.sh
. "$here/../../../../scripts/lib-overlay.sh"

for f in "$up"/.env* "$up"/*.env; do
  [ -f "$f" ] || continue
  sed -i 's/^\(VLLM_PORT\|PORT\)=8899$/\1=8888/' "$f"
done
# grep 没匹配返回 1，配合 pipefail 会让整个 overlay 静默退出（apply-overlay 也跟着失败），必须兜住。
grep -rl ':8899\|port 8899\|PORT=8899' "$up" --include='*.sh' 2>/dev/null | while read -r f; do
  sed -i 's/:8899/:8888/g; s/port 8899/port 8888/g; s/PORT=8899/PORT=8888/g' "$f"
done || true
if ! grep -rq '8888' "$up"/.env* "$up"/*.sh 2>/dev/null; then
  echo "overlay(vision): 上游里没找到端口设置，请人工确认 $up 监听 8888" >&2
fi

# 显存占比（TODO：2026-09-11 66 的 ssh 密钥已换、未能只读核对 vision kit 的显存键名；
# 按 vLLM 常规假设 env 文件里有 GPU_MEMORY_UTILIZATION 或 GPU_MEM_UTIL 键，写不进就报警不静默。
# 若 start-vision.sh 是把两台的值硬编码在同一脚本里，需要改成读 env 后再来这里对接。）
if [ -n "${MH_GPU_MEM_UTIL:-}" ]; then
  ov_require_fraction "$MH_GPU_MEM_UTIL"
  hit=0
  for f in "$up"/.env* "$up"/*.env; do
    [ -f "$f" ] || continue
    for key in GPU_MEMORY_UTILIZATION GPU_MEM_UTIL; do
      grep -q "^${key}=" "$f" || continue
      ov_set_kv "$f" "$key" "$MH_GPU_MEM_UTIL"; hit=1
    done
  done
  [ "$hit" = 1 ] || echo "overlay(vision): 上游 env 里没有 GPU_MEMORY_UTILIZATION/GPU_MEM_UTIL 键，显存占比 ${MH_GPU_MEM_UTIL}（${MH_ROLE:-?}）未写入，请人工核对 $up" >&2
fi
