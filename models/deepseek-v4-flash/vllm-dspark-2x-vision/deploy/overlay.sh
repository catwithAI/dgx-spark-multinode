#!/usr/bin/env bash
# ds4-vision 配方 overlay：由 scripts/apply-overlay.sh 调用，$1 = upstream/（kit 落地目录）。
# modelhub 每次 start 前在 head 与 worker 上各跑一次（MH_ROLE=master|worker、MH_GPU_MEM_UTIL）。
#
# kit 事实（tonyd2wild DSpark vision 配方，入库 keeper 物料 ds4-vision-kit-20260911）：
#   * 每台各跑自己的 ds4-vision-tp2.sh <rank>，它 source 本目录（kit 自己）的 fleet.env；
#     start-vision.sh 在 head 上经 ssh 起 worker，不 scp env —— 所以每台 fleet.env 可以不同，
#     这里按 MH_ROLE 用 modelhub fleet.env 的值逐键渲染（口名/HCA 两台允许不同）。
#   * 显存写死在 ds4-vision-tp2.sh 的 `--gpu-memory-utilization 0.85`，没有变量，直接改本机副本。
#   * start-vision.sh 要求两台 /var/tmp 已有六个补丁文件，由各台 stage-node.sh 生成（需要镜像在本机）。
set -euo pipefail
up=$1; here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=../../../../scripts/lib-overlay.sh
. "$here/../../../../scripts/lib-overlay.sh"

kit_env="$up/fleet.env"
[ -f "$kit_env" ] || { echo "overlay(vision): $kit_env 不存在（kit 未解到 upstream/？先装物料 ds4-vision-kit）" >&2; exit 1; }
up_abs=$(cd "$up" && pwd)

# ---- 1) kit fleet.env <- modelhub fleet.env（按角色）----
mh_env="${MODELHUB_ROOT:-/home/ai/modelhub}/fleet.env"
mh_get() { sed -n "s/^[[:space:]]*$1=//p" "$mh_env" 2>/dev/null | tail -1 | sed 's/[[:space:]]*#.*//' | tr -d '"'"'"; }
ov_set_kv "$kit_env" REPO_DIR "$up_abs"
if [ -f "$mh_env" ]; then
  head_ip=$(mh_get HEAD_IP); worker_ip=$(mh_get WORKER_IP); worker_ssh=$(mh_get WORKER_SSH)
  h_if=$(mh_get FABRIC_IFNAME); h_hca=$(mh_get NCCL_IB_HCA)
  w_if=$(mh_get WORKER_FABRIC_IFNAME); w_hca=$(mh_get WORKER_NCCL_IB_HCA)
  [ -n "$w_if" ]  || w_if=$h_if
  [ -n "$w_hca" ] || w_hca=$h_hca
  port=$(mh_get API_PORT); models_dir=$(mh_get MODELS_DIR)
  [ -n "$head_ip" ]   && ov_set_kv "$kit_env" HEAD_IP "$head_ip"
  [ -n "$worker_ip" ] && ov_set_kv "$kit_env" WORKER_IP "$worker_ip"
  [ -n "$worker_ssh" ] && ov_set_kv "$kit_env" WORKER_SSH "$worker_ssh"
  case "${MH_ROLE:-master}" in
    worker) [ -n "$w_if" ] && ov_set_kv "$kit_env" FABRIC_IFNAME "$w_if"; [ -n "$w_hca" ] && ov_set_kv "$kit_env" NCCL_IB_HCA "$w_hca" ;;
    *)      [ -n "$h_if" ] && ov_set_kv "$kit_env" FABRIC_IFNAME "$h_if"; [ -n "$h_hca" ] && ov_set_kv "$kit_env" NCCL_IB_HCA "$h_hca" ;;
  esac
  ov_set_kv "$kit_env" PORT "${port:-8888}"
  [ -n "$models_dir" ] && ov_set_kv "$kit_env" MODELS_HOST "$models_dir"
else
  echo "overlay(vision): 没有 $mh_env，只改 REPO_DIR 与 PORT；口名/HCA/IP 沿用 kit 原值（${MH_ROLE:-?}）" >&2
  ov_set_kv "$kit_env" PORT 8888
fi

# ---- 2) 显存：改本机副本的 ds4-vision-tp2.sh ----
if [ -n "${MH_GPU_MEM_UTIL:-}" ]; then
  ov_require_fraction "$MH_GPU_MEM_UTIL"
  tp2="$up/ds4-vision-tp2.sh"
  if [ -f "$tp2" ] && grep -q -- '--gpu-memory-utilization [0-9.]*' "$tp2"; then
    sed -i "s|--gpu-memory-utilization [0-9.]*|--gpu-memory-utilization ${MH_GPU_MEM_UTIL}|" "$tp2"
    echo "overlay(vision): $tp2  --gpu-memory-utilization ${MH_GPU_MEM_UTIL} (${MH_ROLE:-?})"
  else
    echo "overlay(vision): $tp2 里找不到 --gpu-memory-utilization，显存占比 ${MH_GPU_MEM_UTIL} 未写入" >&2
  fi
fi

# ---- 3) staging：六个补丁文件缺任一且镜像在本机时跑 stage-node.sh（幂等；它会清 ~/.cache/vllm-dspark/modelinfos，所以只在缺文件时跑）----
image=$(sed -n 's/^IMAGE=//p' "$kit_env" | tail -1 | sed 's/[[:space:]]*#.*//')
missing=""
for f in patch3-scheduler.py spec-dspark.py ds4v_model.py ds4v_vision.py ds4v_mm.py ds4v_registry.py; do
  [ -f "/var/tmp/$f" ] || missing="$missing $f"
done
if [ -n "$missing" ]; then
  if [ -n "$image" ] && docker image inspect "$image" >/dev/null 2>&1; then
    echo "overlay(vision): /var/tmp 缺$missing，跑 stage-node.sh（镜像 $image）"
    "$up/stage-node.sh" || echo "overlay(vision): stage-node.sh 失败，start 时 kit 会再报" >&2
  else
    echo "overlay(vision): /var/tmp 缺$missing，且本机没有镜像 ${image:-?}——先 docker pull 192.168.130.23:5000/bladeai/vllm-dspark-runtime:dspark-nvfp4-stage-c 并 docker tag 成 ${image:-vllm-dspark-runtime:dspark-nvfp4-stage-c}，再跑 upstream/stage-node.sh" >&2
  fi
fi
true
