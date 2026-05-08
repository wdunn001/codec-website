---
title: codec-llamacpp (Docker)
description: Pre-built llama.cpp server with the Codec patches applied and a control plane bolted on, in one GPU container. OpenAI-compatible. Smallest of the three.
section: Server
order: 3
---

`codec-llamacpp` is the easy way to stand up a Codec-speaking inference server on top of llama.cpp. It's a pre-built Docker image bundling:

- **`llama-server`** &mdash; statically-linked CUDA binary built from the Codec fork ([ggml-org/llama.cpp#22757](https://github.com/ggml-org/llama.cpp/pull/22757) for token-native binary transport on the OpenAI-compatible server, plus the stacked `feat/codec-compression` follow-ups: server-side ToolWatcher, streaming gzip, zstd-dict-header docs).
- **codec-supervisor** &mdash; the same FastAPI admin sidecar as [codec-sglang](/docs/codec-sglang/), handling model uploads, Hugging Face pulls, hot-swaps, and reverse-proxying the llama-server backend.
- **Static linking** (`GGML_BACKEND_DL=OFF`, `BUILD_SHARED_LIBS=OFF`) &mdash; the CUDA backend is compiled into the binary, no `.so` plugins to load at runtime, no `LD_LIBRARY_PATH` config.

This image is **~3.6 GB** &mdash; an order of magnitude smaller than codec-sglang or codec-vllm because llama.cpp doesn't ship a heavy ML Python stack.

## Quick start

Default boot downloads `Qwen/Qwen2.5-0.5B-Instruct-GGUF:Q4_K_M` (~400 MB) and serves it.

```bash
docker run -d --gpus all \
  -p 8080:8080 \
  -v codec-models:/models \
  -v llamacpp-cache:/root/.cache/llama.cpp \
  --shm-size 8g \
  wdunn001/codec-llamacpp:latest
```

```bash
# OpenAI-compatible (JSON-SSE)
curl http://localhost:8080/v1/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"x","prompt":"Hello","max_tokens":20}'

# Codec wire format - msgpack frames of token IDs
curl http://localhost:8080/v1/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"x","prompt":"Hello","max_tokens":20,"stream":true,"stream_format":"msgpack"}'
```

llama-server ignores the `model` field for routing (single-model-per-process), so `"x"` is fine.

> **GPU prereq:** NVIDIA Container Toolkit + `--gpus all`. The image is built for compute capability `sm_86` (RTX 3090); use `--build-arg CUDA_DOCKER_ARCH=<arch>` if you rebuild for a different GPU.

## Model spec: HF id or local file

`CODEC_INITIAL_MODEL` accepts two forms; the supervisor's `LlamaCppBackend` picks `--model` vs `-hf` automatically:

| Spec | What llama-server gets | Use case |
|---|---|---|
| `Owner/Repo-GGUF:filename-glob` | `-hf Owner/Repo-GGUF:filename-glob` | Pull a quantized GGUF from Hugging Face directly. The default. |
| `/absolute/path/to/file.gguf` | `--model /absolute/path/to/file.gguf` | Bind-mounted local model file. |

### Examples

**HF GGUF id:**

```bash
docker run --gpus all -p 8080:8080 \
  -e CODEC_INITIAL_MODEL='Qwen/Qwen2.5-7B-Instruct-GGUF:Q4_K_M' \
  -v llamacpp-cache:/root/.cache/llama.cpp \
  wdunn001/codec-llamacpp:latest
```

**Local .gguf file:**

```bash
docker run --gpus all -p 8080:8080 \
  -e CODEC_INITIAL_MODEL=/models/my-model.gguf \
  -v /path/to/my-model.gguf:/models/my-model.gguf:ro \
  wdunn001/codec-llamacpp:latest
```

**Hot-swap via admin API:**

```bash
curl -X POST http://localhost:8080/admin/load \
  -H "Content-Type: application/json" \
  -d '{"name":"Qwen/Qwen2.5-7B-Instruct-GGUF:Q4_K_M","allow_remote":true}'
```

## Configuration

| Variable | Default | Effect |
|---|---|---|
| `CODEC_INITIAL_MODEL` | `Qwen/Qwen2.5-0.5B-Instruct-GGUF:Q4_K_M` | Model spec (HF id `:filename-glob` or absolute `.gguf` path). |
| `CODEC_BACKEND_ARGS` | `--ctx-size 4096 --gpu-layers 999` | Verbatim arguments to `llama-server`. `--gpu-layers 999` offloads everything to GPU. |
| `CODEC_PORT` | `8080` | Supervisor port. |
| `HF_TOKEN` | _(unset)_ | Required only for gated GGUF repos. |

## Admin API

Identical to [codec-sglang](/docs/codec-sglang/#admin-endpoints).

## Source &amp; links

- Image: [`wdunn001/codec-llamacpp:latest`](https://hub.docker.com/r/wdunn001/codec-llamacpp) on Docker Hub.
- Source: [github.com/wdunn001/codec-supervisor](https://github.com/wdunn001/codec-supervisor) (see `Dockerfile.llamacpp`).
- Upstream PR: [ggml-org/llama.cpp#22757](https://github.com/ggml-org/llama.cpp/pull/22757).

## See also

- [codec-sglang](/docs/codec-sglang/) &mdash; same image story, sglang backend (best throughput on supported models).
- [codec-vllm](/docs/codec-vllm/) &mdash; same image story, vLLM backend.
