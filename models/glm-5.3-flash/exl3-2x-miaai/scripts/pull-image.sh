#!/usr/bin/env bash
# 拉 MiaAI-Lab 服务镜像（arm64 / CUDA 13.0，含 InstantTensor）。
#
# 和 exl3-2x-entrpi/scripts/pull-image.sh 是同一套路：这两台 Spark 到 ghcr.io
# 实测只有 0.1 MB/s，直接让 start.sh 拉会卡死在 pull 阶段。ghcr.chenby.cn 是
# 目前实测唯一快的代理（多层并行约 10 MiB/s）。
#
# 拉完 retag 成 ghcr.io/... 让 start.sh 的默认镜像名本地命中，不用改 .env；
# 之后 SKIP_PULL=1 ./start.sh，并让 start.sh 自己走 docker save | ssh docker load
# 把镜像推给 worker（比让 worker 去外网拉快得多），或 SKIP_SHIP=1 手工推。
#
# ⚠️ 测代理源速度别只看 HTTP 码：代理站会秒返 26 字节的 UNAUTHORIZED，
# %{http_code} 是 200、算出来的速度是假的。必须真下几十 MB 再 file 确认是 gzip。
set -u
TAG=${TAG:-exl3-instanttensor}
SRC=${SRC:-ghcr.chenby.cn/miaai-lab/glm-5.3-flash-2x-dgx-sparks:$TAG}
DST=${DST:-ghcr.io/miaai-lab/glm-5.3-flash-2x-dgx-sparks:$TAG}
log=${LOG:-$HOME/glm53-miaai-img.log}
: > "$log"
# 外层重试：单次 unexpected EOF 会把 docker pull 整个带走，重进时已完成的层会复用
for i in $(seq 1 200); do
  echo "=== attempt $i $(date -Is) ===" >> "$log"
  if docker pull "$SRC" >> "$log" 2>&1; then
    docker tag "$SRC" "$DST" && echo "=== TAGGED $(date -Is) ===" >> "$log"
    # 本机若是 x86_64 中转，务必确认这行是 arm64，否则拉到的是废件
    docker image inspect "$DST" --format '=== ARCH={{.Architecture}} OS={{.Os}} SIZE={{.Size}} ===' | tee -a "$log"
    echo "=== COMPLETE ===" >> "$log"; exit 0
  fi
  sleep 10
done
echo "=== GAVE UP ===" >> "$log"; exit 1
