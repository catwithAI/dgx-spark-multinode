# shellcheck shell=bash
# overlay 公共函数。各方案 deploy/overlay.sh 通过 `. "$(dirname "$0")/../../../../scripts/lib-overlay.sh"` 引入。
#
# 接口（由 modelhub 的 mh_apply_overlay 经 scripts/apply-overlay.sh 传入，全部可选）：
#   MH_ROLE              master | worker —— 本机在双机里的角色
#   MH_GPU_MEM_UTIL      本机的显存占比（master 0.78 / worker 0.90，来源 modelhub fleet.env）
#   MH_GPU_MEM_UTIL_MASTER / MH_GPU_MEM_UTIL_WORKER
#                        两个角色的值都给（可选）。只有"一份 env 同时服务两台"的配方需要
#                        （ds4-text：head 的 .env.dspark 会被 scp 到 worker），其它配方忽略。
# 一个都没设时 overlay 不碰显存键，行为与引入本文件前完全一致。

# ov_set_kv <file> <KEY> <value>
# 把 <file> 里 `KEY=...` 行改成 KEY=<value>（只改第一处，注释行不算）。键不存在则追加一行。
ov_set_kv() {
  local f=$1 key=$2 val=$3
  [ -f "$f" ] || { echo "overlay: $f 不存在，无法写 $key" >&2; return 1; }
  if grep -q "^${key}=" "$f"; then
    sed -i "0,/^${key}=.*/s||${key}=${val}|" "$f"
  else
    printf '%s=%s\n' "$key" "$val" >> "$f"
  fi
  echo "overlay: $f  $key=$val"
}

# ov_gpu_util_for <role>  ->  该角色应得的显存占比，取不到输出空串
# 本机角色用 MH_GPU_MEM_UTIL；另一角色只能用 MH_GPU_MEM_UTIL_<ROLE>。
ov_gpu_util_for() {
  local role=$1
  if [ "$role" = "${MH_ROLE:-}" ] && [ -n "${MH_GPU_MEM_UTIL:-}" ]; then
    echo "$MH_GPU_MEM_UTIL"; return 0
  fi
  case "$role" in
    master) echo "${MH_GPU_MEM_UTIL_MASTER:-}" ;;
    worker) echo "${MH_GPU_MEM_UTIL_WORKER:-}" ;;
    *) echo "" ;;
  esac
}

# ov_require_fraction <value>  ->  校验是 (0,1] 的小数，不是就报错退出
ov_require_fraction() {
  case "$1" in
    0.[0-9]*|1|1.0) return 0 ;;
    *) echo "overlay: 显存占比 '$1' 不合法（应为 0.xx）" >&2; return 1 ;;
  esac
}
