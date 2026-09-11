#!/usr/bin/env bash
# 把目标机上的旧模型/配方位置对齐到统一约定（fleet.env.example）。
# 只做软链，不搬数据，可重复执行。默认 dry-run，加 --apply 才真正执行。
# 在 head 和 worker 上各跑一次。
set -euo pipefail
APPLY=0; [ "${1:-}" = "--apply" ] && APPLY=1
MODELS_DIR=${MODELS_DIR:-/home/ai/models}
RECIPES_ROOT=${RECIPES_ROOT:-/home/ai/dgx-spark-multinode}
HF_HUB=${HF_HUB:-/home/ai/.cache/huggingface/hub}

link() { # link <目标(已存在)> <新路径(软链)>
  local src=$1 dst=$2
  if [ -e "$dst" ] || [ -L "$dst" ]; then echo "  跳过 $dst（已存在）"; return; fi
  if [ ! -e "$src" ]; then echo "  跳过 $dst（源 $src 不存在）"; return; fi
  echo "  $dst -> $src"
  [ $APPLY = 1 ] && { mkdir -p "$(dirname "$dst")"; ln -s "$src" "$dst"; }
}

echo "== 权重 -> $MODELS_DIR"
link /srv/models/Qwen3.8-Flash-Next-NVFP4 "$MODELS_DIR/Qwen3.8-Flash-Next-NVFP4"
link /home/ai/gguf "$MODELS_DIR/DeepSeek-V4-Flash-GGUF"
snap=$(ls -d "$HF_HUB/models--deepseek-ai--DeepSeek-V4-Flash-0731/snapshots/"* 2>/dev/null | head -1 || true)
[ -n "$snap" ] && link "$snap" "$MODELS_DIR/DeepSeek-V4-Flash-0731" \
  || echo "  跳过 DeepSeek-V4-Flash-0731（HF cache 里没有 snapshot）"

echo "== 上游配方 -> $RECIPES_ROOT/models/<模型>/<方案>/upstream"
link /home/ai/ds4-dspark-2x            "$RECIPES_ROOT/models/deepseek-v4-flash/vllm-dspark-2x-nvfp4/upstream"
link /home/ai/ds4-dspark-2x-vision-src "$RECIPES_ROOT/models/deepseek-v4-flash/vllm-dspark-2x-vision/upstream"
link /opt/qwen38-sglang                "$RECIPES_ROOT/models/qwen3.8-flash-next/sglang-pixelml-2x/upstream"

echo "== GLM-5.3 Entrpi kit -> $RECIPES_ROOT/models/glm-5.3-flash/exl3-2x-entrpi/upstream"
link /home/ai/glm-5.3-flash-exl3-2x-spark "$RECIPES_ROOT/models/glm-5.3-flash/exl3-2x-entrpi/upstream"
link /home/ai/launch-glm53-vllm-tp2.sh "$RECIPES_ROOT/models/glm-5.3-flash/exl3-2x-entrpi/upstream/launch-glm53-vllm-tp2.sh"
link /home/ai/glm53-warmup.sh          "$RECIPES_ROOT/models/glm-5.3-flash/exl3-2x-entrpi/upstream/glm53-warmup.sh"

echo "== deploy/ 覆盖到 upstream/"
for lock in "$RECIPES_ROOT"/models/*/*/upstream.lock; do
  scheme=$(dirname "$lock")
  [ -d "$scheme/upstream" ] || continue
  echo "  apply-overlay $scheme"
  [ $APPLY = 1 ] && "$RECIPES_ROOT/scripts/apply-overlay.sh" "$scheme"
done
[ $APPLY = 1 ] || echo "(dry-run；加 --apply 执行)"
