---
title: codec-vllm (Docker)
description: Pre-built vLLM server with the Codec patches applied and a control plane bolted on, in one GPU container. OpenAI-compatible.
section: Server
order: 2
---

`codec-vllm` is the easy way to stand up a Codec-speaking inference server on top of vLLM. It's a pre-built Docker image bundling:

- **vLLM nightly** with the Codec patches already applied ([vllm-project/vllm#41765](https://github.com/vllm-project/vllm/pull/41765) for token-native binary transport on `/v1/completions` and `/v1/chat/completions`).
- **codec-supervisor** &mdash; the same FastAPI admin sidecar as [codec-sglang](/docs/codec-sglang/), handling model uploads, Hugging Face pulls, hot-swaps, and reverse-proxying the vLLM backend.
- All upstream vLLM kernels (compiled `_C.abi3.so`, `_flashmla_C.abi3.so`, `_moe_C.abi3.so`, etc.) intact &mdash; the codec patches are a surgical file overlay (9 changed `.py` files), not a recompile.

> **Why nightly, not `:latest`?** The Codec PR sits on the upstream dev branch *after* the route refactor that splits `/v1/completions` and `/v1/chat/completions` out of `api_server.py` into per-endpoint modules. The v0.10.x release in `vllm/vllm-openai:latest` still has the monolithic structure, so the codec routes wouldn't fire there. The image therefore builds on top of `vllm/vllm-openai:nightly`.

## Quick start

```bash
docker run -d --gpus all \
  -p 8080:8080 \
  -v codec-models:/models \
  -v codec-hf-cache:/root/.cache/huggingface \
  -e CODEC_INITIAL_MODEL=Qwen/Qwen2.5-0.5B-Instruct \
  --shm-size 8g --ipc host \
  wdunn001/codec-vllm:latest
```

The container boots the supervisor on `:8080`, which then launches the vLLM backend with `Qwen/Qwen2.5-0.5B-Instruct` (or whatever you set in `CODEC_INITIAL_MODEL`). First boot pulls weights from Hugging Face into the persistent cache volume.

> **GPU prereq:** NVIDIA Container Toolkit installed, and `--gpus all` (or a specific device list). The image targets recent CUDA. The `--ipc host` flag is required for vLLM's shared-memory CUDA IPC.

### First request

```bash
# OpenAI-compatible (JSON-SSE)
curl http://localhost:8080/v1/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"Qwen/Qwen2.5-0.5B-Instruct","prompt":"Hello","max_tokens":20}'

# Codec wire format - msgpack frames of token IDs (gzip-wrapped)
curl http://localhost:8080/v1/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"Qwen/Qwen2.5-0.5B-Instruct","prompt":"Hello","max_tokens":20,"stream":true,"stream_format":"msgpack"}'
```

Unlike sglang, vLLM **strictly validates the `model` field** &mdash; pass the loaded model id, not a placeholder. Use `/admin/status` to check the current model.

The codec PR on vLLM also auto-applies **gzip compression** on the binary path (the response starts with the gzip magic `1f 8b 08 ...`). The Codec clients in [`@codecai/web`](https://www.npmjs.com/package/@codecai/web) and the Python/Rust/.NET equivalents handle decompression transparently.

## Run your own model

Three ways, same surface as codec-sglang:

### 1. Override `CODEC_INITIAL_MODEL` at `docker run` time

Any HF repo id:

```bash
docker run --gpus all -p 8080:8080 \
  -e CODEC_INITIAL_MODEL=meta-llama/Llama-3.1-8B-Instruct \
  -e HF_TOKEN=hf_xxxxx \
  -v hf-cache:/root/.cache/huggingface \
  --shm-size 8g --ipc host \
  wdunn001/codec-vllm:latest
```

### 2. Bind-mount a local checkpoint

```bash
docker run --gpus all -p 8080:8080 \
  -e CODEC_INITIAL_MODEL=/models/my-finetune \
  -v /path/to/my-finetune:/models/my-finetune:ro \
  --shm-size 8g --ipc host \
  wdunn001/codec-vllm:latest
```

### 3. Hot-swap via the admin API

```bash
curl -X POST http://localhost:8080/admin/load \
  -H "Content-Type: application/json" \
  -d '{"name":"Qwen/Qwen2.5-7B-Instruct","allow_remote":true}'
```

Pass `CODEC_BACKEND_ARGS` to tune vLLM (`--gpu-memory-utilization 0.9 --max-model-len 4096 --tensor-parallel-size 2 ...`). Defaults are vLLM-shaped (not sglang-shaped):

| Variable | Default | Effect |
|---|---|---|
| `CODEC_INITIAL_MODEL` | `Qwen/Qwen2.5-0.5B-Instruct` | Model to load on first boot. HF id, local name, or absolute path. |
| `CODEC_BACKEND_ARGS` | `--gpu-memory-utilization 0.85 --max-model-len 2048 --dtype auto` | Verbatim arguments to `python3 -m vllm.entrypoints.openai.api_server`. |
| `CODEC_PORT` | `8080` | Supervisor port. |
| `HF_TOKEN` | _(unset)_ | Required only for gated HF models. |

## Admin API

Identical to [codec-sglang](/docs/codec-sglang/#admin-endpoints) &mdash; the supervisor is backend-agnostic. `/health`, `/admin/status`, `/admin/models`, `/admin/models/pull`, `/admin/models/upload`, `/admin/load`, `/admin/stop`. Anything not under `/admin` proxies to vLLM.

## Source &amp; links

- Image: [`wdunn001/codec-vllm:latest`](https://hub.docker.com/r/wdunn001/codec-vllm) on Docker Hub.
- Source: [github.com/wdunn001/codec-supervisor](https://github.com/wdunn001/codec-supervisor) (see `Dockerfile.vllm`).
- Upstream PR: [vllm-project/vllm#41765](https://github.com/vllm-project/vllm/pull/41765).

## See also

- [codec-sglang](/docs/codec-sglang/) &mdash; same image story, sglang backend.
- [codec-llamacpp](/docs/codec-llamacpp/) &mdash; same image story, llama.cpp backend.
- [TypeScript](/docs/typescript/), [Python](/docs/python/), [.NET](/docs/dotnet/), [C](/docs/c/), [Rust](/docs/rust/), [Java](/docs/java/) walkthroughs &mdash; client-side patterns.
