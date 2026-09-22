# GLM-5.3-Flash · EXL3 4bpw + DFlash2 · 双节点 TP=2（MiaAI-Lab 栈）

上游方案：[MiaAI-Lab/GLM-5.3-Flash-EXL3-2x-DGX-Sparks](https://github.com/MiaAI-Lab/GLM-5.3-Flash-EXL3-2x-DGX-Sparks)
（本仓库记录的是 `c1b7d4c9`，2026-09-22）。

**这是备选栈，当前生产跑的是 [`../exl3-2x-entrpi/`](../exl3-2x-entrpi)。**
2026-09-06 选型时 Entrpi 在结构化 decode 和 TTFT 上明显更快，所以上线的是它。
但从那以后上游这边推了几轮内核工作（E2/E3 fat-expert prefill、adaptive-k、dense FP8），
prefill 数字已经反超，值得作为第二条路线进仓库、择机 A/B。为什么当时没选它见
[`../README.md`](../README.md)，本文只记这一套怎么装、和 Entrpi 那套差在哪。

| | |
|---|---|
| 节点 | `192.168.130.8`（head，API）+ `192.168.130.12`（worker），TP=2 |
| 互联 | 200GbE 直连，`enp1s0f1np1` / HCA `rocep1s0f1`，`10.0.0.2` ↔ `10.0.0.3` |
| 权重 | 同一份 EXL3 4bpw（`Mia-AiLab/GLM-5.3-Flash-EXL3-TR3-4bpw`），但**落盘布局不同**，见下 |
| 投机 | DFlash2 k=7（`incoai/GLM-5.3-Flash-DFlash2`），draft TP=2，FLASH_ATTN |
| 引擎 | MiaAI-Lab 的 vLLM overlay 镜像，sm_121a 原生 cubin，已含 InstantTensor |
| 上下文 | kit 默认 850K；**本地降到 512K**，原因见「本地改了什么」 |
| 端口 | `8888`，模型 id 覆盖成 `glm-5.3-flash`（与 entrpi 那套对齐，客户端不用改） |

## 和 Entrpi 那套的实际差别

两套用的是**同一份量化权重、同一个 drafter**，差的是引擎 overlay：

| | Entrpi（现役） | MiaAI-Lab（本目录） |
|---|---|---|
| 编排 | 两台各有 launcher 脚本，顺序由本仓库 `ops/` 的 supervisor 管 | 只有 head 跑 `./start.sh`，worker 容器由它 ssh 拉起 |
| 权重布局 | `/home/ai/models/<裸目录>` | HF cache 布局（`HF_HOME`） |
| 上游报的 decode | 结构化 72.4 / 散文 27.4 tok/s | 结构化 62.9 / 散文 36.1 tok/s（2026-09-17，开 coop MoE） |
| 上游报的 prefill | 1,490 tok/s @133K | **~1,500–1,600 tok/s** 全程（8K–256K，E3 内核） |
| 分角色显存 | 支持（每台自己的 `~/.glm53-serve.env`） | **不支持**，见下 |
| 多机档位 | TP=2 | TP=2 / TP=3 / TP=4 |
| 视觉 | 支持 | 支持（image + video） |

散文 decode 是这套明显更好的一块（36.1 vs 27.4），而散文恰好是 Entrpi 那套
本地实测掉得最狠的负载（中文散文只有 14.9 tok/s）。**如果要 A/B，第一件事
就是拿中文散文跑**——上游两家都没测过中文。

### ⚠️ 显存占比不能分角色

本仓库的约定是 master `0.78` / worker `0.90`（GB10 统一内存，head 还要养 blade 全家桶）。
这个 kit 只有一个 `GPU_MEM_UTIL`，head 的 `start.sh` 把它原样 `-e` 进 worker 容器，
没有 per-rank 覆盖。所以 `deploy/overlay.sh` 取 **master 那份（较小值）给两 rank 共用**：
worker 多出来的显存浪费掉，但 head 不会被挤爆。要吃满 worker 就得先把 head 上的
业务腾走、再手工把两边拉齐。

### ⚠️ 权重不共用

同一份 4bpw 权重，但 Entrpi 那套要的是 `/home/ai/models/GLM-5.3-Flash-EXL3-TR3-4bpw`
这样的裸目录，这套要的是 HF cache 布局。两套同时装 = **两份 164 GiB**。
本地 `HF_HOME` 指到 `/home/ai/models/hf-cache`（跟着统一权重盘走，别塞 `~/.cache`，
根盘放不下）。A/B 完就把不用的那份删掉。

## 本地改了什么

`deploy/.env.miaai` 只覆盖必须改的项，serving 旋钮一律留空跟随上游验证过的默认。
覆盖的四类：

1. **网络**：`10.0.0.2`/`10.0.0.3`，两台光口都是 f1（kit 默认 head f1 / worker f0）。
2. **权重**：`HF_HOME` 指到统一权重盘；`NFS_SHARE=0` 两台各存一份。
3. **端口与模型 id**：`8888` + `glm-5.3-flash`。
4. **上下文与 KV 池**：kit 默认 850K + 显式 14 GiB KV 池；本地 `GPU_MEM_UTIL` 被压到
   0.78，850K 的池放不下，所以降到 **512K + 10 GiB 池**（≈ 655K token，1.28x）。

> KV 池必须显式给。默认的 `LOAD_FORMAT=instanttensor` 下，profile 出来的池装不下
> 一个满长请求，引擎直接拒绝启动（上游 [#204](https://github.com/MiaAI-Lab/GLM-5.3-Flash-EXL3-2x-DGX-Sparks/issues/204)）。
> 要回 850K：先停 head 上的业务容器，`GPU_MEM_UTIL` 回 0.85，再把 `MAX_MODEL_LEN`
> 和 `EXTRA_ARGS` 还原成 kit 默认（850000 / 15032385536）。

## 部署步骤

### 1. 腾机器

同 [`../exl3-2x-entrpi/README.md`](../exl3-2x-entrpi/README.md#1-腾机器必须先做)：
两台都要退到系统内存占用足够低，至少停掉 DS4 双节点服务和**另一套 glm53**
（两套抢的是同一块统一内存，不可能同时起）。

```bash
ssh ai@192.168.130.8  'docker rm -f vllm_glm53; docker stop ds4-dspark-2x-vllm-dspark-1'
ssh ai@192.168.130.12 'docker rm -f vllm_glm53; docker stop ds4-dspark-2x-vllm-dspark-1'
```

### 2. 落 kit + 套 overlay

```bash
bash scripts/fetch-upstream.sh models/glm-5.3-flash/exl3-2x-miaai
```

按 `upstream.lock` clone 到 `upstream/` 并 checkout `c1b7d4c9`，再把
`deploy/.env.miaai` 装成 `upstream/.env`。改了 `deploy/` 重跑
`scripts/apply-overlay.sh` 即生效（modelhub 每次 start 前也会重跑）。

### 3. 拉镜像

国内直连 ghcr.io 只有 0.1 MB/s，别让 `start.sh` 自己拉：

```bash
bash scripts/pull-image.sh        # 走 ghcr.chenby.cn，拉完 retag 成 ghcr.io/...
```

### 4. 下权重

```bash
cd upstream && ./download.sh      # 只拉到 head 的 HF cache，不碰 worker
```

164 GiB + 2.3 GiB drafter。`start.sh` 启动时会 rsync 给 worker（走光缆，
`SKIP_SYNC=1` 可跳过）。

> 这套默认从 huggingface.co 拉，国内 DNS 污染拉不动。Entrpi 那套的
> [`../exl3-2x-entrpi/scripts/download-model.sh`](../exl3-2x-entrpi/scripts/download-model.sh)
> 走的是 ModelScope（同一份字节一致镜像），但落的是裸目录布局，不能直接喂给这套。
> 要用 ModelScope 就得自己把文件摆成 HF cache 的 `models--Mia-AiLab--…/snapshots/<rev>/` 结构。
> **这条还没在本地实机验证过。**

### 5. 起

```bash
cd upstream
SKIP_PULL=1 ./start.sh            # preflight → 推镜像给 worker → 同步权重 → 起 worker → 起 head → 预热
./start.sh status
./start.sh logs
```

```bash
curl -s http://192.168.130.8:8888/v1/chat/completions \
  -H 'Content-Type: application/json' -d '{
  "model": "glm-5.3-flash",
  "messages": [{"role": "user", "content": "你好"}]
}'
```

停：`./start.sh stop`。重启：`./start.sh restart`（启动顺序 kit 自己管，
不用像 Entrpi 那套手工 head 先停 / worker 先起）。

## 当前进度

- [x] 方案进仓库：`deploy/` + `upstream.lock` + overlay（2026-09-22）
- [ ] 实机装一次（权重要再落一份 164 GiB，得先腾盘）
- [ ] 与 [`../exl3-2x-entrpi/`](../exl3-2x-entrpi) A/B：**中文散文优先**，其次 prefill
- [ ] 进 [`../../../eval/`](../../../eval) 出质量分，与 `eval/reports/glm-5.3-flash/` 对比

> A/B 时注意 `eval/harness.py` 的 `_extract_code` 边界：仓库里 Laguna /
> Qwen3.5-122B / DS4 的历史代码分是旧逻辑跑的，没回填。见
> [`../exl3-2x-entrpi/README.md`](../exl3-2x-entrpi/README.md#质量评测2026-09-06)。

## 上游值得注意的几条

- **E3 grouped MoE prefill**（`EXL3_FAT_GROUPED=1`，2026-09-07 起默认）：
  冷 prefill 比 E2 快 37–45%，8K–256K 全程稳定在 ~1,500 tok/s。
  代价是多占 560 MiB fat-row scratch，**1M 上下文因此装不下了**；要 1M 得
  `EXL3_FAT_GROUPED=0` 退回 E2。
- **adaptive-k / dense FP8**（默认关）：`GLM53_ADAPTIVE_K=ema` 散文 +13–21%，
  温度 0 无损；`GLM53_DENSE_FP8=dense,kda` 再 +12–19%，但**会改目标数值**
  （FP8 舍入，上游自己标 PROVISIONAL，没出完整 KLD 面板）。要跑评测别开第二个。
- **不要传 `--moe-backend marlin`**：这是 EXL3 权重 + fp8 KV，不是 NVFP4。
- **别钉 `TRITON_ATTN` 给 draft**：该镜像上 draft block 内是 causal mask，
  会把靠后位置的接受率打崩（上游实测结构化从 62.9 掉到 ~29）。
- **视觉的每请求图片上限是硬约束**：`LIMIT_MM` 只做校验、不预留显存，
  超了返回 HTTP 500 比把引擎搞死好。无状态客户端每轮重发全部图片，
  会话一长就会撞上限。
- `ABLIT`（去审查）默认关，本仓库不用，别顺手打开。

## 参考

- 上游 README（数据非常全）：<https://github.com/MiaAI-Lab/GLM-5.3-Flash-EXL3-2x-DGX-Sparks>
- KLD 质量面板：4bpw 0.0246 nats ≈ 官方 FP8 0.0246，字节只有 54%
- 论坛横评：<https://forums.developer.nvidia.com/t/deepseek-v4-flash-glm-5-3-flash-qwen3-8-flash-next/381832>
