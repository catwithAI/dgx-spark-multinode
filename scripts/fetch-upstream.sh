#!/usr/bin/env bash
# fetch-upstream.sh [方案目录...]
# 按每个方案的 upstream.lock 把第三方 kit 拉到 <方案>/upstream/，再套上 deploy/ 覆盖层。
# 新盒子 clone 本仓库后跑一次即可，不再需要手工放配方。不带参数 = 所有带 upstream.lock 的方案。
# REPO 有值：git clone 并 checkout REF；否则从 SEED（已验证的盒子）rsync。
# upstream/ 已存在时跳过（要重拉先手动删）。
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
targets=("$@")
[ ${#targets[@]} -gt 0 ] || mapfile -t targets < <(find "$root/models" -name upstream.lock -exec dirname {} \;)
for scheme in "${targets[@]}"; do
  scheme=$(cd "$scheme" && pwd); up=$scheme/upstream
  # shellcheck source=/dev/null
  REPO= REF= SEED=; . "$scheme/upstream.lock"
  if [ -e "$up" ]; then echo "== $scheme: upstream/ 已存在，跳过"; 
  elif [ -n "$REPO" ]; then
    echo "== $scheme: git clone $REPO @ ${REF:-HEAD}"
    git clone -q "$REPO" "$up"
    [ -z "$REF" ] || git -C "$up" checkout -q "$REF"
  elif [ -n "$SEED" ]; then
    echo "== $scheme: rsync $SEED"
    rsync -a "$SEED" "$up/"
  else
    echo "== $scheme: upstream.lock 没有 REPO 也没有 SEED，跳过" >&2; continue
  fi
  "$root/scripts/apply-overlay.sh" "$scheme"
done
