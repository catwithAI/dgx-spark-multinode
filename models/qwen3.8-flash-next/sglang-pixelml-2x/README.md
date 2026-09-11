# Qwen3.8-Flash-Next-NVFP4 · SGLang TP=2 · PixelML 配方

双节点 DGX Spark 跑 **Qwen3.8-Flash-Next-NVFP4**（与 [`../../qwen3.8-27b`](../../qwen3.8-27b) 不是同一个模型），SGLang，TP=2，262K 上下文，NEXTN/MTP k=3。
由 [modelhub](https://github.com/blade-hq/modelhub_cli) 的 `qwen38` 条目管理生命周期，本目录是它的配方锚点。

## 统一约定（见根目录 `fleet.env.example`）

| 项 | 值 |
|---|---|
| 权重 | `/home/ai/models/Qwen3.8-Flash-Next-NVFP4`（旧位置 `/srv/models/...` 用软链过渡） |
| 端口 | `8888`，模型名 `qwen3.8-flash-next`，带 bearer token |
| 上游配方 checkout | 本目录 `upstream/`（gitignore；旧位置 `/opt/qwen38-sglang` 用软链过渡） |
| API key 文件 | `upstream/.sglang-api-key`（只记路径，密钥不进仓库） |
| 容器名 | `qwen38-flash-next-sglang` |

## 必须的补丁

SM121 QSA 补丁不是可选项：不打的话长上下文会静默吐 token id 0（`!`）填满输出预算。
modelhub 每次启动都会跑 `upstream/scripts/apply-sm121-qsa-patch.sh` 校验。

## 启动 / 停止

```bash
modelhub switch qwen38
modelhub logs qwen38 -f
```

直接跑上游脚本：

```bash
cd ~/dgx-spark-multinode/models/qwen3.8-flash-next/sglang-pixelml-2x/upstream
./scripts/start-cluster.sh
./scripts/status-node.sh
./scripts/stop-cluster.sh
```

`NCCL_IB_GID_INDEX` 每台不同且重启会变，上游 `.env` 里的值由 modelhub 每次启动前重写，不要手填。
