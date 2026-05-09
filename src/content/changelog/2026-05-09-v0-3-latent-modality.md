---
title: v0.3 latent modality — VAE latents on the wire
date: "2026-05-09"
kind: feature
version: v0.3.0
summary: Image and video diffusion models now stream VAE latents instead of decoded pixels. 48× smaller wire weight, decode at the leaf.
links:
  - label: GitHub release v0.3.0
    url: https://github.com/wdunn001/Codec/releases/tag/v0.3.0
  - label: codec-comfyui docs
    url: https://codecai.net/docs/codec-comfyui/
  - label: codec-diffusers docs
    url: https://codecai.net/docs/codec-diffusers/
  - label: PROTOCOL.md § Latent Modality
    url: https://github.com/wdunn001/Codec/blob/main/spec/PROTOCOL.md#latent-modality-v03
---

Codec v0.3 extends the framing surface from text-tokens to **VAE latents**. Two new engine forks ship as pre-built Docker images:

- [`codec-comfyui`](https://codecai.net/docs/codec-comfyui/) — ComfyUI with the v0.3 latent transport patch. Production image-gen with the full ComfyUI workflow surface.
- [`codec-diffusers`](https://codecai.net/docs/codec-diffusers/) — the HuggingFace diffusers reference path. Doubles as the bench/golden perceptual-conformance reference for every Codec latent client.

Same wire shape; same registry; same `LatentStreamDecoder` in [`@codecai/web`](https://www.npmjs.com/package/@codecai/web) handles both.

A 512×512 RGB frame at fp16 is ~1.5 MB; the SD-1 latent that produced it is 4×64×64 fp16 = 32 KB — a **48× reduction**. Per-channel int8 quantization on top, and (for video) delta-coding against keyframes, take it further. The client runs `vae_decode` locally — pixels never touch the wire.
