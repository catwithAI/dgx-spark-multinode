#!/usr/bin/env bash
# Entrpi kit 读的是 upstream/.env；deploy/.env.entrpi 是本集群的填好值。
# 同时把 kit install.sh 装到 ~/ 的启动/预热脚本链进 upstream/，供 modelhub 的 LAUNCH/WARMUP 使用。
set -euo pipefail
up=$1; here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=../../../../scripts/lib-overlay.sh
. "$here/../../../../scripts/lib-overlay.sh"

install -m 0644 "$here/.env.entrpi" "$up/.env"
for s in launch-glm53-vllm-tp2.sh glm53-warmup.sh; do
  [ -e "$up/$s" ] && continue
  [ -x "$HOME/$s" ] && ln -s "$HOME/$s" "$up/$s"
done

# 显存占比：launch-glm53-vllm-tp2.sh 读 GMU（--gpu-memory-utilization，kit 默认 0.85），
# 来源是每台各自的 ~/.glm53-serve.env（`: "${GMU:=x}"` 写法，命令行 env 优先）。
# 两台值不同，所以写本机这份，不写 upstream/.env（launch 不读它）。
# 注意 modelhub 的 glm53/start.sh knobs() 不能再传 GMU，否则两台被同一个值盖掉。
if [ -n "${MH_GPU_MEM_UTIL:-}" ]; then
  ov_require_fraction "$MH_GPU_MEM_UTIL"
  serve_env=${GLM53_ENV:-$HOME/.glm53-serve.env}
  if [ -f "$serve_env" ]; then
    if grep -q '^: "${GMU' "$serve_env"; then
      sed -i "s|^: \"\${GMU[:]*=.*|: \"\${GMU:=${MH_GPU_MEM_UTIL}}\"|" "$serve_env"
    else
      printf ': "${GMU:=%s}"\n' "$MH_GPU_MEM_UTIL" >> "$serve_env"
    fi
    echo "overlay(glm53): $serve_env  GMU=${MH_GPU_MEM_UTIL} (${MH_ROLE:-?})"
  else
    echo "overlay(glm53): $serve_env 不存在（kit install.sh 还没跑？），显存占比 ${MH_GPU_MEM_UTIL} 未写入" >&2
  fi
fi
true
