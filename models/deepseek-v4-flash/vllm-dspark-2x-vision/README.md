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

`upstream.lock` 指向种子机（66）的 `~/ds4-dspark-2x-vision-src`；`deploy/overlay.sh` 每次 start 前把上游里的 `:8899` 改成 `:8888`。66/67 上原来的 `ds4v-*supervisor` 用根目录 `scripts/cutover-modelhub.sh` 禁掉，只留 rail。
