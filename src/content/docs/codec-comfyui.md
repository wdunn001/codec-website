---
title: codec-comfyui (Docker)
description: ComfyUI image-generation server with the Codec v0.3 latent transport patch. Streams VAE latents on the wire in place of decoded pixels, 48× smaller, decoder runs at the leaf.
section: Server
order: 5
---

`codec-comfyui` is a pre-built Docker image of [ComfyUI](https://github.com/comfyanonymous/ComfyUI) with the Codec v0.3 latent transport patch applied. Stand it up like any image-gen server, point any Codec-aware client at it, and image generations ship as **VAE latents** in place of decoded pixels, same physics as text-token streams in [codec-sglang](/docs/codec-sglang/) / [codec-vllm](/docs/codec-vllm/), but for diffusion.

Why latents and not pixels: a 512×512 RGB frame at fp16 is ~1.5&nbsp;MB; the SD-1 latent that produced it is 4×64×64 fp16 = **32&nbsp;KB**, a 48× reduction. With per-channel int8 quantization on top, the wire weight collapses further. The client does `vae_decode` locally and never re-encodes. Round-trip pixel quality is bounded by the published per-pipeline LPIPS thresholds (see [`spec/PIPELINES.md`](https://github.com/wdunn001/Codec/blob/main/spec/PIPELINES.md)).

This image is built from the [`wdunn001/ComfyUI` fork](https://github.com/wdunn001/ComfyUI/tree/feat/codec-latent-transport) at branch `feat/codec-latent-transport`. The fork is the canonical surface. ComfyUI's plugin/custom-node architecture would let us ship the codec endpoints as a custom node, but the latent-frame emitter and zstd-dict overlay touch enough of the request loop that maintaining a downstream fork is cleaner.

## Quick start

Default boot loads `stabilityai/sd-vae-ft-mse` (SD-1 VAE) and serves it.

```bash
docker run -d --gpus all \
  -p 8080:8080 \
  -v codec-models:/models \
  --shm-size 8g \
  wdunn001/codec-comfyui:latest
```

```bash
# Codec wire format, msgpack frames of LatentStreamHeader + LatentFrame
curl http://localhost:8080/v1/images/generations \
  -H "Content-Type: application/json" \
  -H "Accept: application/x-codec-msgpack" \
  -H "Accept-Encoding: zstd" \
  -d '{
    "model": "sd1.5",
    "prompt": "a wide-angle photograph of a snowy mountain at dusk",
    "stream_format": "msgpack",
    "modality":      "image-latents",
    "latent_space":  "stabilityai/sd-vae-ft-mse",
    "pipeline":      "int8",
    "size": "512x512", "steps": 30, "seed": 42
  }'
```

The response carries:

- `Content-Encoding: zstd` (when a per-pipeline zstd dict is loaded)
- `Codec-Latent-Map: sha256:…`, the [latent-space map](https://github.com/wdunn001/Codec/blob/main/spec/latent-space-map.schema.json) document hash so the client can fail-fast if it doesn't have a matching map loaded
- `Codec-Zstd-Dict: sha256:…`, the active dict identifier

Body is one `LatentStreamHeader` followed by one `LatentFrame` (image) or `N` `LatentFrame`s (video).

## Pipelines

`codec-comfyui` advertises the seven Codec v0.3 pipelines documented in [`spec/PIPELINES.md`](https://github.com/wdunn001/Codec/blob/main/spec/PIPELINES.md):

| Pipeline          | Wire shape                          | Reduction vs `raw`     | Use case                           |
|-------------------|-------------------------------------|------------------------|-------------------------------------|
| `raw`             | Pack tensor in row-major order      | 1×                     | Bit-exact baseline                  |
| `int8`            | Per-channel symmetric int8          | 2× over fp16           | Default for SD-family images        |
| `int4`            | Per-channel symmetric int4 (packed) | 4× over fp16           | Aggressive lossy mode               |
| `int8-adaptive`   | int8 with per-keyframe scales       | ~2×                    | Heterogeneous frames                |
| `int4-adaptive`   | int4 with per-keyframe scales       | ~4×                    | Same use case, more lossy           |
| `delta+int8`      | int8 residual against prior keyframe| 2× + temporal collapse | Video only                          |
| `delta+int4`      | int4 residual against prior keyframe| 4× + temporal collapse | Video, most aggressive              |

Adding a pipeline is an additive v0.3+ point release. The registry is normative. Deployments cannot extend it.

## Pointing a Codec client at it

Any [`@codecai/web`](https://www.npmjs.com/package/@codecai/web) client (v0.4+) speaks the latent wire shape via `LatentStreamDecoder`:

```ts
import {
  decodeLatentHeaderMsgpack,
  decodeLatentFrameMsgpack,
  LatentStreamDecoder,
} from "@codecai/web";

const resp = await fetch("http://localhost:8080/v1/images/generations", {
  method: "POST",
  headers: {
    "Content-Type": "application/json",
    "Accept": "application/x-codec-msgpack",
    "Accept-Encoding": "zstd",
  },
  body: JSON.stringify({ /* …request as above… */ }),
});

// Frames stream length-prefixed; iterate them as Uint8Array chunks
// (see decodeMsgpackStream for the streaming helper).
const [headerBytes, ...frameChunks] = /* …split per the stream protocol… */;
const header = decodeLatentHeaderMsgpack(headerBytes);
const decoder = new LatentStreamDecoder(header);

for (const chunk of frameChunks) {
  const frame = decodeLatentFrameMsgpack(chunk);
  const latent = decoder.decodeFrame(frame); // Float32Array, channel-first
  // Hand `latent` to a browser-side VAE (WebGPU / ONNX-Web / etc.)
}
```

The Python (`codecai`) and the polyglot clients (rust / java / dotnet / c) carry the same parser surface, a single tokenizer-map and latent-space-map registry; one wire shape; six languages.

## When to use this

- **Use `codec-comfyui`** when you want browser- or edge-side VAE decoding, when you're streaming frames into a downstream vision model that accepts latents directly, or when bandwidth is the bottleneck.
- **Use upstream ComfyUI** when you need the full ComfyUI workflow surface (custom nodes, queue management, the visual graph editor) and pixel output is fine.

The Codec patch is fully backwards-compatible per request. JSON-SSE clients see exactly the upstream behaviour.

## Source &amp; links

- Image: [`wdunn001/codec-comfyui:latest`](https://hub.docker.com/r/wdunn001/codec-comfyui) on Docker Hub.
- Codec patch source: [github.com/wdunn001/ComfyUI](https://github.com/wdunn001/ComfyUI/tree/feat/codec-latent-transport).
- Image build recipe: [github.com/wdunn001/codec-supervisor/blob/main/Dockerfile.comfyui](https://github.com/wdunn001/codec-supervisor/blob/main/Dockerfile.comfyui).
- v0.3 spec section: [Codec PROTOCOL.md § Latent Modality](https://github.com/wdunn001/Codec/blob/main/spec/PROTOCOL.md#latent-modality-v03).
- Pipeline math: [Codec PIPELINES.md](https://github.com/wdunn001/Codec/blob/main/spec/PIPELINES.md).

## See also

- [codec-diffusers](/docs/codec-diffusers/), sister image, also a v0.3 latent server. Doubles as the bench/golden perceptual reference.
- [codec-metamcp](/docs/codec-metamcp/), gateway in front of latent servers + tool servers.
- [Protocol overview](/docs/protocol/), the wire format spec the framing in this image speaks.
