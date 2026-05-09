---
title: codec-diffusers (Docker)
description: HuggingFace diffusers reference server with the Codec v0.3 latent transport patch. Doubles as the bench/golden perceptual-conformance reference for every Codec latent client.
section: Server
order: 6
---

`codec-diffusers` is a pre-built Docker image of the [HuggingFace diffusers](https://github.com/huggingface/diffusers) reference path with the Codec v0.3 latent transport patch applied. It exposes the same `/v1/images/generations` and `/v1/videos/generations` endpoints as [codec-comfyui](/docs/codec-comfyui/) — the wire shape is byte-identical — but on top of `diffusers` instead of ComfyUI's workflow engine.

This image **doubles as the bench/golden perceptual-conformance reference**. The `torch` + `diffusers` + `transformers` versions pinned in this image define the SSIM / PSNR / LPIPS contract every latent bench cell resolves against. Bumping any of them re-pins the perceptual contract — operators tracking conformance across runs MUST pin to a specific image digest, not `:latest`.

The patch is built from the [`wdunn001/diffusers` fork](https://github.com/wdunn001/diffusers/tree/feat/codec-latent-transport) at branch `feat/codec-latent-transport`. `diffusers` is a *library*, not a server, so the fork adds an `examples/codec_server/` FastAPI wrapper that loads any `StableDiffusionPipeline` / `StableVideoDiffusionPipeline` / etc. and serves Codec latent streams.

## Quick start

```bash
docker run -d --gpus all \
  -p 8080:8080 \
  -v codec-models:/models \
  --shm-size 8g \
  -e CODEC_MODEL=stabilityai/stable-diffusion-2-1 \
  wdunn001/codec-diffusers:latest
```

Same request shape as codec-comfyui:

```bash
curl http://localhost:8080/v1/images/generations \
  -H "Content-Type: application/json" \
  -H "Accept: application/x-codec-msgpack" \
  -H "Accept-Encoding: zstd" \
  -d '{
    "model": "sd2.1",
    "prompt": "a wide-angle photograph of a snowy mountain at dusk",
    "stream_format": "msgpack",
    "modality":      "image-latents",
    "latent_space":  "stabilityai/sd-vae-ft-mse",
    "pipeline":      "int8-adaptive",
    "size": "768x768", "steps": 30, "seed": 42
  }'
```

Response carries the same headers as codec-comfyui: `Codec-Latent-Map`, `Codec-Zstd-Dict`, and `Content-Encoding: zstd` when a per-pipeline dict is loaded.

## Why two latent servers

`codec-comfyui` and `codec-diffusers` are siblings — same wire, same pipelines, same registry. Pick by use case:

| Need                                                  | Image            |
|-------------------------------------------------------|------------------|
| Production image-gen with rich workflow primitives    | `codec-comfyui`  |
| Reference / bench / "what does the canonical decoder produce" | `codec-diffusers` |
| Custom pipeline (e.g. ControlNet variants, LoRA stacks) easier to script | `codec-diffusers` |
| Pre-built node graph + queue + visual editor          | `codec-comfyui`  |

The wire format is **identical** between the two — a Codec client can switch upstream without code changes.

## Bench / golden role

When the [Codec bench harness](https://github.com/wdunn001/Codec/tree/main/packages/bench) computes perceptual quality (SSIM / PSNR / LPIPS) for a given `(latent_space_id, pipeline)` cell, the reference pixels come from this image, executed against a pinned image digest (the `decoder.canonical_image` field in the [latent-space-map schema](https://github.com/wdunn001/Codec/blob/main/spec/latent-space-map.schema.json)).

Operators reporting bench results MUST pin to the same digest — `wdunn001/codec-diffusers@sha256:…` — that the published latent map references. `:latest` drift is the difference between "we beat last quarter's SSIM" and "we measured a noisier reference."

The `golden-builder` Dockerfile in the Codec repo bumps in lockstep with this image; bumping `torch` or `diffusers` here without bumping `packages/bench/golden-builder/Dockerfile` breaks the conformance gate.

## Pointing a Codec client at it

Same code as [codec-comfyui's section](/docs/codec-comfyui/#pointing-a-codec-client-at-it) — a single `LatentStreamDecoder` works against either server.

## Source &amp; links

- Image: [`wdunn001/codec-diffusers:latest`](https://hub.docker.com/r/wdunn001/codec-diffusers) on Docker Hub.
- Codec patch source: [github.com/wdunn001/diffusers](https://github.com/wdunn001/diffusers/tree/feat/codec-latent-transport).
- Image build recipe: [github.com/wdunn001/codec-supervisor/blob/main/Dockerfile.diffusers](https://github.com/wdunn001/codec-supervisor/blob/main/Dockerfile.diffusers).
- v0.3 spec section: [Codec PROTOCOL.md § Latent Modality](https://github.com/wdunn001/Codec/blob/main/spec/PROTOCOL.md#latent-modality-v03).

## See also

- [codec-comfyui](/docs/codec-comfyui/) — workflow-oriented sibling.
- [codec-metamcp](/docs/codec-metamcp/) — gateway in front of latent + text + tool servers.
- [Protocol overview](/docs/protocol/) — the wire format spec.
