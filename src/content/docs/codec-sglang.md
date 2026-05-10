---
title: codec-sglang (Docker)
description: The turnkey path — a pre-built SGLang server with the Codec patches applied and a control plane bolted on, in one GPU container. OpenAI-compatible.
section: Server
order: 1
---

`codec-sglang` is the easy way to stand up a Codec-speaking inference server. It's a pre-built Docker image bundling:

- **SGLang** with the Codec patches already applied &mdash; token-native binary transport on `/v1/completions` and a server-side ToolWatcher that emits tool-call boundaries on the ID stream.
- **codec-supervisor** &mdash; a FastAPI admin sidecar that handles model uploads, Hugging Face pulls, hot-swaps, and reverse-proxies the inference backend.
- All upstream sglang kernels (flash-attn, sgl_kernel, triton) intact &mdash; the patches are applied as an editable overlay.

If you'd rather build sglang yourself from upstream and apply the Codec patches by hand, see [sglang &mdash; vanilla setup](/docs/sglang/).

## Quick start

```bash
docker run -d --gpus all \
  -p 8080:8080 \
  -v codec-models:/models \
  -v codec-hf-cache:/root/.cache/huggingface \
  -e CODEC_INITIAL_MODEL=Qwen/Qwen2.5-0.5B-Instruct \
  --shm-size 8g \
  wdunn001/codec-sglang:latest
```

The container boots the supervisor on `:8080`, which then launches the sglang backend with `Qwen/Qwen2.5-0.5B-Instruct` (or whatever you set in `CODEC_INITIAL_MODEL`). First boot pulls weights from Hugging Face into the persistent cache volume.

> **GPU prereq:** NVIDIA Container Toolkit installed, and `--gpus all` (or a specific device list). See [the NVIDIA install docs](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html). The image targets CUDA 12.

### First request

The same endpoint speaks both formats. The client picks per-request:

```bash
# OpenAI-compatible (JSON-SSE if stream, JSON otherwise)
curl http://localhost:8080/v1/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"x","prompt":"Hello","max_tokens":20}'

# Codec wire format — msgpack frames of token IDs
curl http://localhost:8080/v1/completions \
  -d '{"model":"x","prompt":"Hello","max_tokens":20,"stream":true,"stream_format":"msgpack"}'
```

The `model` field is ignored when only one model is loaded at a time &mdash; the supervisor proxies whichever model is currently loaded. Use `/admin/load` to swap.

## Running your own models

Three ways to point the image at any model you like, progressively more "self-serve":

### 1. Override `CODEC_INITIAL_MODEL` at `docker run` time

Any Hugging Face repo id (or any path inside the container) &mdash; the supervisor downloads + boots on first start and caches in the volume.

```bash
docker run --gpus all -p 8080:8080 \
  -e CODEC_INITIAL_MODEL=meta-llama/Llama-3.1-8B-Instruct \
  -e HF_TOKEN=hf_xxxxx \
  -v hf-cache:/root/.cache/huggingface \
  wdunn001/codec-sglang:latest
```

`HF_TOKEN` is only required for gated models.

### 2. Mount a local model directory

For checkpoints or fine-tunes you don't want to upload to HF &mdash; bind-mount the directory and point `CODEC_INITIAL_MODEL` at the in-container path:

```bash
docker run --gpus all -p 8080:8080 \
  -e CODEC_INITIAL_MODEL=/models/my-finetune \
  -v /path/to/my-finetune:/models/my-finetune:ro \
  wdunn001/codec-sglang:latest
```

The mount is read-only inside the container, so the supervisor can't mutate your weights.

### 3. Hot-swap via the admin API after boot

This is what the supervisor adds on top of stock sglang &mdash; the container stays up, only the model process swaps. See the [Admin endpoints](#admin-endpoints) section below for the full surface; the short version:

```bash
# Pull from HF into the persistent registry
curl -X POST http://localhost:8080/admin/models/pull \
  -H "Content-Type: application/json" \
  -d '{"repo_id": "Qwen/Qwen2.5-7B-Instruct"}'

# Or upload a tarball of a local fine-tune (multipart, name as query param)
tar -cf my-finetune.tar -C ./checkpoints/my-finetune .
curl -X POST "http://localhost:8080/admin/models/upload?name=my-finetune" \
  -F "file=@my-finetune.tar"

# Hot-swap to it
curl -X POST http://localhost:8080/admin/load \
  -H "Content-Type: application/json" \
  -d '{"name": "my-finetune"}'

# Or load an HF id directly without staging it first
curl -X POST http://localhost:8080/admin/load \
  -H "Content-Type: application/json" \
  -d '{"name": "Qwen/Qwen2.5-7B-Instruct", "allow_remote": true}'
```

Pass `CODEC_BACKEND_ARGS` to tune sglang per-model (`--tp 2 --quantization fp8 --mem-fraction-static 0.9`, etc.); for per-load tuning, add `extra_args` to the `/admin/load` body to override the supervisor's default for that single load.

> **Hot-swap caveat**: there's a few-second gap during the swap (terminate child &rarr; fork new &rarr; poll `/health`). For zero-downtime multi-model serving, run multiple containers behind a router &mdash; the supervisor is single-model-per-container by design.

## Volumes and persistence

| Mount | Purpose |
|---|---|
| `/models` | Local model store. Models pulled or uploaded here survive container restarts. |
| `/root/.cache/huggingface` | HF download cache. Subsequent pulls of the same revision skip the network. |

In the quick-start above, both are named Docker volumes. For production, mount a host directory or a shared filesystem so the cache survives image upgrades.

## Environment

| Variable | Default | Effect |
|---|---|---|
| `CODEC_PORT` | `8080` | Port the supervisor listens on (host-side via `-p`). |
| `CODEC_INITIAL_MODEL` | _(unset)_ | Model to load on first boot. HF repo id, local name in `/models`, or absolute path. If unset, the supervisor starts but no backend is running until you call `/admin/load`. |
| `CODEC_BACKEND_ARGS` | `--mem-fraction-static 0.85 --attention-backend triton` | Verbatim arguments appended to `python3 -m sglang.launch_server`. Use this for `--tp`, `--quantization`, mem fractions, etc. |
| `CODEC_BACKEND_PORT` | `30000` | Internal-only sglang port; rarely needs changing. |
| `CODEC_MODELS_DIR` | `/models` | Where uploaded / HF-pulled models land. Volume-mounted in the quick-start. |
| `CODEC_STARTUP_TIMEOUT_S` | `1800` | How long to wait for sglang's `/health` after launch (large models take a while). |
| `HF_TOKEN` | _(unset)_ | Required only for gated HF models. |

## Admin endpoints

The supervisor on `:8080` mixes admin routes with a transparent proxy:

| Method | Path | What |
|---|---|---|
| `GET` | `/health` | supervisor liveness |
| `GET` | `/admin/status` | current model + uptime |
| `GET` | `/admin/models` | list models in `/models` |
| `POST` | `/admin/models/pull` | `snapshot_download` from Hugging Face |
| `POST` | `/admin/models/upload` | multipart tarball upload |
| `DELETE` | `/admin/models/{name}` | remove from `/models` |
| `POST` | `/admin/load` | hot-swap to a different model |
| `POST` | `/admin/stop` | stop backend (supervisor stays up) |
| `*` | `/v1/*` | proxied to the sglang backend |

### Pull a model from Hugging Face

```bash
curl -X POST http://localhost:8080/admin/models/pull \
  -H "Content-Type: application/json" \
  -d '{"repo_id":"Qwen/Qwen2.5-7B-Instruct"}'
```

Optional fields: `revision` (branch / tag / commit) and `token` (per-request HF token; otherwise falls back to the `HF_TOKEN` env var).

### Hot-swap to a different model

```bash
curl -X POST http://localhost:8080/admin/load \
  -H "Content-Type: application/json" \
  -d '{"name":"qwen2.5-7b"}'
```

`name` resolves first against the local `/models` registry. To load a fresh HF id without staging it first, set `allow_remote: true`:

```bash
curl -X POST http://localhost:8080/admin/load \
  -H "Content-Type: application/json" \
  -d '{"name":"Qwen/Qwen2.5-7B-Instruct","allow_remote":true}'
```

The supervisor stops the running backend, releases the GPU, and starts a new one with the requested model. Inflight requests against `/v1/*` see a brief unavailable window during the swap.

To override sglang flags for just this load (`--tp`, `--quantization`, etc.), pass `extra_args`:

```bash
curl -X POST http://localhost:8080/admin/load \
  -H "Content-Type: application/json" \
  -d '{"name":"Qwen/Qwen2.5-7B-Instruct","allow_remote":true,
       "extra_args":["--tp","2","--quantization","fp8"]}'
```

### Upload a model tarball

For air-gapped setups or pre-baked models. `name` is a query parameter; the tarball is the multipart `file` field:

```bash
tar -cf my-fine-tune.tar -C ./checkpoints/my-fine-tune .
curl -X POST "http://localhost:8080/admin/models/upload?name=my-fine-tune" \
  -F "file=@./my-fine-tune.tar"
```

The tarball is extracted into `/models/<name>/` (path-traversal-safe; symlinks are rejected). Afterwards it's loadable via `/admin/load`.

## Pointing a Codec client at it

Once running, point any of the language bindings at `http://your-host:8080/v1/completions` &mdash; that's the same endpoint pattern the language walkthroughs already document. The Codec client decides per-request whether to ask for `stream_format: "msgpack"` (binary frames) or omit the field (JSON-SSE).

```ts
// TypeScript example — same as the sglang walkthrough, just a different host
import { loadMap, Detokenizer, decodeStream } from "@codecai/web";

const map = await loadMap({
  url:  "https://cdn.jsdelivr.net/gh/wdunn001/codec-maps/maps/qwen/qwen2.json",
  hash: "sha256:887311099cdc09e7022001a01fa1da396750d669b7ed2c242a000b9badd09791",
});

const resp = await fetch("http://localhost:8080/v1/completions", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({
    model: "Qwen/Qwen2.5-0.5B-Instruct",
    prompt: "Explain entropy in one paragraph.",
    stream_format: "msgpack",
    max_tokens: 256,
  }),
});

const detok = new Detokenizer(map);
for await (const frame of decodeStream(resp.body!, "msgpack")) {
  process.stdout.write(detok.render(frame.ids, { partial: !frame.done }));
}
```

The same code works against vanilla sglang too &mdash; codec-sglang's wire format is bit-identical to upstream-sglang-with-the-PRs.

## When to use this vs vanilla sglang

- **Use `codec-sglang`** when you want the protocol working in 30 seconds with no toolchain to babysit. The image bakes the right CUDA, the right sglang build, and the supervisor.
- **Use [vanilla sglang](/docs/sglang/)** when you have a bespoke build (custom kernels, weird CUDA version, internal mirror) or a deploy story that already pulls upstream sglang directly. Apply the Codec patches and you're equivalent.

## License

The `codec-supervisor` wrapper is published under [Business Source License 1.1](https://github.com/wdunn001/codec-supervisor/blob/main/LICENSE) by Quasarke LLC. Free for non-production use and for production use under US&nbsp;$5M annual gross revenue (combined with affiliates). Each release auto-converts to Apache-2.0 four years after publication.

The bundled SGLang itself is unchanged from upstream and remains under Apache-2.0. Commercial licensing for the wrapper above the threshold: [licensing@quasarke.com](mailto:licensing@quasarke.com).

## Source &amp; links

- Image: [`wdunn001/codec-sglang:latest`](https://hub.docker.com/r/wdunn001/codec-sglang) on Docker Hub.
- Source: [github.com/wdunn001/codec-supervisor](https://github.com/wdunn001/codec-supervisor).

## See also

- [sglang &mdash; vanilla setup](/docs/sglang/) for the DIY path.
- [TypeScript](/docs/typescript/), [Python](/docs/python/), [.NET](/docs/dotnet/), [C](/docs/c/), [Rust](/docs/rust/), [Java](/docs/java/) walkthroughs &mdash; client-side patterns.
- [Tool calling](/docs/tool-calling/) &mdash; ToolWatcher events from the server-side detector.
