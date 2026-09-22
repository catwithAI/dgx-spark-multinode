#!/usr/bin/env bash
# MiaAI-Lab kit 读的是 upstream/.env；deploy/.env.miaai 是本集群的填好值。
# 与 exl3-2x-entrpi 不同，这个 kit 只有 head 上的 start.sh 是入口，worker 侧容器
# 完全由 head 用 ssh + docker run 拉起，所以 overlay 只在 head 上有意义（worker 上
# 跑一遍也无害：装出来的 upstream/.env 一样，只是不会被用到）。
set -euo pipefail
up=$1; here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=../../../../scripts/lib-overlay.sh
. "$here/../../../../scripts/lib-overlay.sh"

install -m 0644 "$here/.env.miaai" "$up/.env"

# 显存占比。⚠️ 这个 kit 只有一个 GPU_MEM_UTIL，head 上的 start.sh 把它原样 -e 进
# worker 容器（upstream start.sh 的 launch_worker），没有 per-rank 覆盖，所以
# 本集群 master 0.78 / worker 0.90 的分角色注入在这套栈上做不到：只能取一个值。
# 取 master 那份（较小的一个）——worker 多留的显存浪费掉，但 head 上的 blade
# 全家桶不会被挤爆。GB10 是统一内存，超售不会优雅降级，是直接崩。
# 想吃满 worker 的 0.90，得先把 head 上的业务腾走再手工把两边拉齐。
if [ -n "${MH_GPU_MEM_UTIL:-}" ] || [ -n "${MH_GPU_MEM_UTIL_MASTER:-}" ]; then
  util=$(ov_gpu_util_for master)
  if [ -n "$util" ]; then
    ov_require_fraction "$util"
    ov_set_kv "$up/.env" GPU_MEM_UTIL "$util"
    # 必须写 ${util} 而不是 $util：后面紧跟中文全角括号，bash 会把多字节字符当成变量名的一部分。
    echo "overlay(glm53-miaai): GPU_MEM_UTIL=${util}（两 rank 共用 master 的值，kit 不支持分角色；见本文件注释）"
  fi
fi
true
