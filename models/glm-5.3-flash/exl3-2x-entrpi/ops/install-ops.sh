#!/usr/bin/env bash
# 把运维层装到两台上：光口自适应（rail）+ 开机自启。
# 在 head 上跑一次即可，它会把 worker 侧也装好。幂等，可重复执行。
#
# 看门狗默认不装：生命周期由 modelhub 编排，两个看门狗会抢 GPU。
# 只有不用 modelhub 的独立部署才加 --with-supervisor。
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
CFG=$here/glm53-ops.env
. "$CFG"
WORKER_HOST=${WORKER_HOST:-glm53-worker.local}
peer(){ ssh -o StrictHostKeyChecking=no "$SSH_USER@$WORKER_HOST" "$@"; }
WITH_SUPERVISOR=0; [ "${1:-}" = "--with-supervisor" ] && WITH_SUPERVISOR=1

# 启动/预热脚本按统一约定放在本仓库 checkout 的 upstream/ 顶层（deploy/ 固化副本，由
# scripts/apply-overlay.sh 安装）。这里先在 head 套一次 overlay 再检查，worker 侧要求已由
# fetch-upstream/apply-overlay 铺好（modelhub 每次 start 也会在两台重套）。
ROOT=${RECIPES_ROOT:-/home/ai/dgx-spark-multinode}
SCHEME=$ROOT/models/glm-5.3-flash/exl3-2x-entrpi
UP=$SCHEME/upstream
[ -d "$UP" ] || { echo "缺少 $UP：先跑 $ROOT/scripts/fetch-upstream.sh $SCHEME" >&2; exit 1; }
"$ROOT/scripts/apply-overlay.sh" "$SCHEME" >/dev/null
for s in launch-glm53-vllm-tp2.sh glm53-warmup.sh; do
  [ -x "$UP/$s" ] || { echo "缺少可执行依赖: $UP/$s（overlay 应已安装，检查 deploy/ 是否完整）" >&2; exit 1; }
done
peer "test -x '$UP/launch-glm53-vllm-tp2.sh'" \
  || { echo "worker 缺少 $UP/launch-glm53-vllm-tp2.sh：先在 worker 跑 fetch-upstream.sh + apply-overlay.sh" >&2; exit 1; }

echo "== head: 装脚本和配置 =="
sudo install -m 0644 "$CFG"                 /etc/glm53-ops.env
sudo install -m 0755 "$here/glm53-rail.sh"      /usr/local/sbin/glm53-rail.sh
sudo install -m 0644 "$here/systemd/glm53-rail.service"       /etc/systemd/system/
sudo install -m 0644 "$here/systemd/glm53-rail.timer"         /etc/systemd/system/
if [ $WITH_SUPERVISOR = 1 ]; then
  sudo install -m 0755 "$here/glm53-supervise.sh" /usr/local/bin/glm53-supervise.sh
  sudo install -m 0644 "$here/systemd/glm53-supervisor.service" /etc/systemd/system/
fi
# supervisor 要能免密调 rail 脚本重新探测光口
echo "$SSH_USER ALL=(root) NOPASSWD: /usr/local/sbin/glm53-rail.sh" \
  | sudo tee /etc/sudoers.d/glm53-rail >/dev/null
sudo chmod 0440 /etc/sudoers.d/glm53-rail
sudo touch /var/log/glm53-supervisor.log && sudo chown "$SSH_USER" /var/log/glm53-supervisor.log
sudo systemctl daemon-reload
sudo systemctl enable --now glm53-rail.service
sudo systemctl enable --now glm53-rail.timer

echo "== worker: 装脚本和配置 =="
tar -C "$here" -cf - glm53-ops.env glm53-rail.sh systemd/glm53-rail.service systemd/glm53-rail.timer systemd/glm53-worker-boot.service \
  | peer 'mkdir -p ~/glm53-ops && tar -C ~/glm53-ops -xf - && sed -i "s/^NODE_ROLE=.*/NODE_ROLE=slave/" ~/glm53-ops/glm53-ops.env'
peer 'sudo install -m 0644 ~/glm53-ops/glm53-ops.env /etc/glm53-ops.env
      sudo install -m 0755 ~/glm53-ops/glm53-rail.sh /usr/local/sbin/glm53-rail.sh
      sudo install -m 0644 ~/glm53-ops/systemd/glm53-rail.service        /etc/systemd/system/
      sudo install -m 0644 ~/glm53-ops/systemd/glm53-rail.timer          /etc/systemd/system/
      sudo install -m 0644 ~/glm53-ops/systemd/glm53-worker-boot.service /etc/systemd/system/
      sudo systemctl daemon-reload
      sudo systemctl enable --now glm53-rail.service
      sudo systemctl enable --now glm53-rail.timer
      sudo systemctl enable glm53-worker-boot.service'

if [ $WITH_SUPERVISOR = 1 ]; then
  echo "== head: 启用看门狗 =="
  sudo systemctl enable --now glm53-supervisor.service
else
  echo "== head: 看门狗交给 modelhub，确保旧的 glm53-supervisor 关掉 =="
  sudo systemctl disable --now glm53-supervisor.service 2>/dev/null || true
fi

echo
echo "装好了。查看:"
echo "  systemctl status glm53-supervisor --no-pager"
echo "  tail -f /var/log/glm53-supervisor.log"
echo "  cat /run/glm53-rail.env        # 探测到的光口"
