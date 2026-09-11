#!/usr/bin/env bash
# fetch-upstream.sh [方案目录...]
# 按每个方案的 upstream.lock 把第三方 kit 落到 <方案>/upstream/，再套上 deploy/ 覆盖层。
# 新盒子 clone 本仓库后跑一次即可，不再需要手工放配方。不带参数 = 所有带 upstream.lock 的方案。
#
# 来源优先级（高 → 低）：
#   1. upstream/ 已存在        视为已拉取（keeper 的 kit 物料 ds4-vision-kit / qwen38-sglang-kit 就是
#                             直接解到这里的；要重拉先手动删）。
#   2. KIT_DIR=<目录>          环境变量或 lock 键：把该目录 rsync 成 upstream/（包内物料已解开的情形）。
#   3. KIT_TAR=<tar.gz>        环境变量或 lock 键：tar -xzf 到 upstream/（night-build 装机时指向包内物料）。
#   4. REPO / REF              git clone 并 checkout。
#   5. SEED=user@host:/path/   从已验证的盒子 rsync——仅开发机兜底，生产盒子不该依赖别的盒子在线。
# 环境变量 KIT_DIR / KIT_TAR 只对本次调用的所有方案生效，多方案一起跑时请写进各自 lock。
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
targets=("$@")
[ ${#targets[@]} -gt 0 ] || mapfile -t targets < <(find "$root/models" -name upstream.lock -exec dirname {} \;)
ENV_KIT_DIR=${KIT_DIR:-}; ENV_KIT_TAR=${KIT_TAR:-}
for scheme in "${targets[@]}"; do
  scheme=$(cd "$scheme" && pwd); up=$scheme/upstream
  # shellcheck source=/dev/null
  REPO= REF= SEED= KIT_DIR= KIT_TAR=; . "$scheme/upstream.lock"
  KIT_DIR=${ENV_KIT_DIR:-$KIT_DIR}; KIT_TAR=${ENV_KIT_TAR:-$KIT_TAR}
  if [ -e "$up" ]; then
    echo "== $scheme: upstream/ 已存在，视为已拉取（keeper kit 物料或上次拉取），跳过"
  elif [ -n "$KIT_DIR" ]; then
    [ -d "$KIT_DIR" ] || { echo "== $scheme: KIT_DIR=$KIT_DIR 不是目录" >&2; exit 1; }
    echo "== $scheme: rsync KIT_DIR=$KIT_DIR"
    mkdir -p "$up" && rsync -a "${KIT_DIR%/}/" "$up/"
  elif [ -n "$KIT_TAR" ]; then
    [ -f "$KIT_TAR" ] || { echo "== $scheme: KIT_TAR=$KIT_TAR 不存在" >&2; exit 1; }
    echo "== $scheme: tar -xzf KIT_TAR=$KIT_TAR"
    mkdir -p "$up" && tar -xzf "$KIT_TAR" -C "$up" --strip-components="${KIT_TAR_STRIP:-0}"
  elif [ -n "$REPO" ]; then
    echo "== $scheme: git clone $REPO @ ${REF:-HEAD}"
    git clone -q "$REPO" "$up"
    [ -z "$REF" ] || git -C "$up" checkout -q "$REF"
  elif [ -n "$SEED" ]; then
    echo "== $scheme: rsync SEED=$SEED（开发机兜底；生产应走 KIT_TAR/KIT_DIR 或 keeper 物料）"
    rsync -a "$SEED" "$up/"
  else
    echo "== $scheme: upstream.lock 没有 KIT_DIR/KIT_TAR/REPO/SEED，跳过" >&2; continue
  fi
  "$root/scripts/apply-overlay.sh" "$scheme"
done
