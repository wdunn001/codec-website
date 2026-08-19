---
title: v0.5.0 (efficiency, observability, and cohort honesty)
date: "2026-05-18"
kind: feature
version: v0.5.0
summary: Wire-additive over v0.4 (v0.4 → v0.5 happy-path bytes identical). Four new opt-in surfaces (delta-varint stream encoding, discoverable Zstandard dictionaries, GPU-side latent quantize, bolt-on tool dispatcher). 11 client artifacts bumped to 0.5.0 across npm, PyPI, NuGet, crates.io, Maven Central. Engine cohort cut to sglang + vLLM + llama.cpp + ComfyUI + diffusers (TGI dropped). 72/72 wire + 72/72 decode unanimous on the cross-stack matrix; numbers byte-identical to v0.4.1, confirming the wire-additive invariant. Upstream PRs filed at sgl-project/sglang#25544 and vllm-project/vllm#42896, both DCO-signed and through bot review.
links:
  - label: GitHub Release v0.5.0
    url: https://github.com/wdunn001/Codec/releases/tag/v0.5.0
  - label: CHANGELOG entry
    url: https://github.com/wdunn001/Codec/blob/main/CHANGELOG.md#v050--2026-05-18
  - label: Cross-stack matrix
    url: https://github.com/wdunn001/Codec/blob/main/packages/bench/results/2026-05-17T23-06-45Z/MATRIX.md
  - label: IETF Internet-Draft (draft-dunn-codec-00)
    url: https://github.com/wdunn001/Codec/blob/main/docs/submissions/draft-dunn-codec-00.md
  - label: sglang upstream PR
    url: https://github.com/sgl-project/sglang/pull/25544
  - label: vLLM upstream PR
    url: https://github.com/vllm-project/vllm/pull/42896
---

v0.5.0 ships four new wire surfaces, all opt-in, without changing the v0.4 happy path. Every existing v0.4 client decodes a v0.5 server byte-for-byte unless it explicitly negotiates a new surface via `stream_format`, `Accept-Encoding`, or a new env var.

## Four new opt-in wire surfaces

**Delta-varint stream encoding.** New `stream_format` values `"msgpack-delta"` and `"protobuf-delta"`. Frames carry `base_id` plus zigzag-encoded deltas against the prior frame's last identifier; stateless framing preserved. ~10-15% wire reduction pre-zstd, ~3-5% post-zstd. Python reference impl; engine-side emit pending in v0.5.x.

**Discoverable Zstandard dictionaries.** Engines now publish their pre-trained dicts at `<origin>/.well-known/codec/dicts/<sha256>.zstd`. Hash-pinned: the client MUST verify the bytes hash to the URL component. Closes the v0.4.1 silent-COPY-dicts-drop regression class. Dictionary drift now fails loudly (404 or hash-mismatch) instead of falling back silently to identity bytes. Release-checklist §1.7 codifies a four-sub-gate audit; the v0.5 cut actually caught a llama.cpp regression where `master` was vanilla upstream without the codec patches and the engine was silently serving identity-encoded msgpack.

**GPU-side latent quantize fast path.** `LatentStreamEncoderOptions.gpu_quantize=True` accepts a CUDA `torch.Tensor`, quantizes on-device, and transfers the int4/int8 result instead of the fp16 latent. ~75% PCIe reduction on int4 SDXL; smaller wins at SD-1.5.

**Bolt-on tool dispatcher.** The engine can dispatch directly to tools published via the `@codecai/tool-kit` manifest, without ever detokenizing the model's `<tool_call>` region. Manifest schema + `_codec_meta` envelope let a tool author publish pre-tokenized IDs that flow into and out of the engine's generation context.

## 11 packages at 0.5.0

- **npm**: `@codecai/{web, web-safety, web-llm, maps-cli, mcp-leaf, tool-kit, wire-compress}`
- **PyPI**: `codecai`
- **NuGet**: `Codec.Net`
- **crates.io**: `codec-rs`
- **Maven Central**: `ai.codec:codec`

New cross-cohort surfaces: content-aware + per-stack-aware compression picker rewrite with a typed `PickReasonCode` enum, `policies-enumerate` subcommand on `@codecai/maps-cli` (resolves v0.4-OQ4), `@codecai/tool-kit` promoted to first-class family member with a runnable reference tool (`@codecai/codec-time-tool`).

## Engine cohort

`wdunn001/codec-{sglang,vllm,llamacpp,comfyui,diffusers}:v0.5.0` and `:latest` live on Docker Hub. Each image bakes the canonical zstd dicts at `/opt/codec/dicts/`, ships the `/opt/codec/check-dict-availability.sh` probe, and is dep-verified for `import brotli, zstandard, msgpack` before push.

Upstream PRs filed at [sgl-project/sglang#25544](https://github.com/sgl-project/sglang/pull/25544) and [vllm-project/vllm#42896](https://github.com/vllm-project/vllm/pull/42896). Both DCO-signed; both through five gemini-code-assist bot review-fix iterations (struct.unpack bytes path, hardened `_decode_varint` shift-cap, async dispatch, cached registry, manifest dict-shape guard).

`wdunn001/codec-tgi` is **dropped**, TGI treated as a dead project; the cohort is now five engines.

## Bench: byte-identical to v0.4.1

The §1 + §1b numbers are unchanged from v0.4.1, which is exactly what wire-additive is supposed to mean. The §1.7 and §1.9 gates added in this release exist to guarantee that, not change it.

**§1b engine-output @ 2K tokens, Codec msgpack + dict-zstd:**

| Engine     | JSON-SSE  | Best Codec | Reduction  |
|------------|----------:|-----------:|-----------:|
| llama.cpp  | 528.8 KB  | 140 B      | **3,868×** |
| sglang     | 485.2 KB  | 291 B      | **1,707×** |
| vllm       | 517.8 KB  | 3.9 KB     | **137×**   |

**§2 cross-language interop:** **72/72 wire-unanimous + 72/72 decode-unanimous** across three engines and six client languages. vllm required `REPS=4` to median out its documented ~10-20% scheduler variance at T=0; ran clean on the second pass.

## IETF Internet-Draft

`draft-dunn-codec-00` rewritten to RFC 2026 compliance. Required sections present, kramdown-rfc compatible frontmatter, threat model expanded with five inline Codec-specific threats (binary-WAF blindness, capability-trust, discovery cache poisoning, frame-size + varint exhaustion, sentinel-identifier integrity), explicit out-of-specification behaviour table, liberal/conservative acceptance rules, implementation-experience section. Companion `SUBMITTING.md` walkthrough covers the `kdrfc` → datatracker submission flow.

## Migration

v0.4.1 → v0.5.0 is non-breaking. Bump the package version; nothing else changes for existing v0.4 consumers. To opt into new surfaces, set the appropriate env var or request field. See the [CHANGELOG entry](https://github.com/wdunn001/Codec/blob/main/CHANGELOG.md#v050--2026-05-18) for the per-surface opt-in matrix.
