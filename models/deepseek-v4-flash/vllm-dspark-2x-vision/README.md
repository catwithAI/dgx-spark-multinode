# DeepSeek-V4-Flash-Vision-Exp · vLLM TP=2 · DSpark · 原生图片输入

双节点 DGX Spark 跑 **DeepSeek-V4-Flash-Vision-Exp**（原生图片输入），TP=2，`nvfp4_ds_mla` KV，1M 上下文，DSpark k=5。
由 [modelhub](https://github.com/blade-hq/modelhub_cli) 的 `ds4-vision` 条目管理生命周期，本目录是它的配方锚点。

## 统一约定（见根目录 `fleet.env.example`）

| 项 | 值 |
|---|---|
| 权重 | `/home/ai/models/DeepSeek-V4-Flash-Vision-Exp`（48 分片 safetensors，两台各一份） |
| 端口 | `8888`，模型名 `deepseek-v4-flash-vision-exp` |
| 上游配方 checkout | 本目录 `upstream/`（gitignore；旧位置 `~/ds4-dspark-2x-vision-src` 用软链过渡） |
| 容器名 | `vllm_ds4_vision` |

## 启动 / 停止

正常情况用 modelhub：

```bash
modelhub switch ds4-vision
modelhub status ds4-vision
```

直接跑上游脚本（modelhub 就是委托给它们）：

```bash
cd ~/dgx-spark-multinode/models/deepseek-v4-flash/vllm-dspark-2x-vision/upstream
./start-vision.sh      # 自带六文件 + 分片预检，先起 rank 1 再起 rank 0，阻塞到真实请求成功
./status-vision.sh
./stop-vision.sh
```

## overlay 做什么（每次 `modelhub start` 前在两台各跑一次）

kit 的每台节点各跑自己的 `ds4-vision-tp2.sh <rank>`，读**本机** `upstream/fleet.env`，head 经 ssh 起 worker、不同步 env，
所以两台的 fleet.env 允许不同。`deploy/overlay.sh` 按 `MH_ROLE` 从 modelhub 的 `fleet.env` 逐键渲染，不再手改 kit：

| kit fleet.env 键 | 来源 |
|---|---|
| `HEAD_IP` / `WORKER_IP` / `WORKER_SSH` | modelhub fleet.env 同名键 |
| `FABRIC_IFNAME` / `NCCL_IB_HCA` | master 用 `FABRIC_IFNAME`/`NCCL_IB_HCA`，worker 用 `WORKER_FABRIC_IFNAME`/`WORKER_NCCL_IB_HCA`（空则同 head）——两台可插不同口 |
| `PORT` | `API_PORT`（默认 8888） |
| `MODELS_HOST` | `MODELS_DIR` |
| `REPO_DIR` | 本目录 `upstream/` 的绝对路径（start-vision.sh 经它 ssh 起 worker 的脚本） |
| `IMAGE` / `NAME` / `SERVED_MODEL_NAME` / `MODEL_DIR` / `MASTER_PORT` | 保留 kit 原值（见 `deploy/fleet.env.reference`） |

显存：kit 把 `--gpu-memory-utilization 0.85` 写死在 `ds4-vision-tp2.sh`，overlay 用 `MH_GPU_MEM_UTIL`（master 0.78 / worker 0.90）改本机副本。
staging：start-vision.sh 要求两台 `/var/tmp` 有六个补丁文件；overlay 发现缺文件且本机有镜像
`vllm-dspark-runtime:dspark-nvfp4-stage-c` 时自动跑 `stage-node.sh`，没镜像则提示先从 `192.168.130.23:5000/bladeai/vllm-dspark-runtime:dspark-nvfp4-stage-c` pull 并 tag。

旧 66/67 上的 `ds4v-*supervisor` 用根目录 `scripts/cutover-modelhub.sh` 禁掉，只留 rail。
