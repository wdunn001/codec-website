---
title: What is Codec?
description: A control-plane primitive for AI inference. Lets gateways, routers, agents, and tool dispatchers operate on raw token IDs end-to-end, with detokenization localized at the edges that need text.
section: Start
order: 1
---

**Codec is a control-plane primitive for AI inference.** It's the substrate that lets gateways, routers, agents, tool dispatchers, and observers operate on raw token IDs end-to-end, no detokenize on the hot path, no JSON-parse per token, no UTF-8 round-trip at every hop. Compression and wire reduction are byproducts of the framing; what you actually buy is the ability to run the inference layer like infrastructure.

It separates three concerns that today's `/v1/chat/completions` mashes together:

1. **Token IDs**, the model layer. The protocol carries `uint32` IDs directly. Routing, sampling, observability, and tool dispatch all reduce to integer compares on the stream.
2. **Framing**, the transport layer. Length-prefixed msgpack or protobuf frames; the same wire on every engine in the matrix.
3. **UTF-8 text**, the presentation layer. Detokenization happens at the *edge*, only at the boundary that has a real reason to need text (a human display, a JSON-RPC tool call, a logging sink). Never per-token, never per-hop.

Three primitives fall out of that layering:

- **Wire-native streaming.** Token IDs flow as length-prefixed binary frames over plain HTTP. Compression layers on top of the same wire. Receipts: a short chat reply ships in 226&nbsp;B (vs 15.2&nbsp;KB JSON-SSE = ~67&times;); a 2 K-token agent stream in 140&nbsp;B-354&nbsp;B (engine-dependent), **1,707&times;** on sglang, **3,868&times;** on llama.cpp fp16 with the full msgpack&nbsp;+ dict-zstd stack. The honest *protocol-only* range across token-distribution profiles is **4.8&times;-391.9&times;** (v0.4.1 synthetic-stream bench, decoupled from engine + model). TTFB is within 1&nbsp;ms of the JSON path on the same server. [v0.4.1 cross-stack matrix](https://github.com/wdunn001/Codec/blob/main/packages/bench/results/2026-05-15T20-00-00Z/MATRIX.md), 24/24 wire AND 24/24 decode unanimous across 6 clients &times; 3 engines.
- **Tool-call dispatch without detokenization.** `ToolWatcher` matches reserved control IDs in the raw token stream, one 32-bit compare per token. v0.4.1 lab microbench on EPYC 8124P + gcc:13: **2.08&nbsp;ms vs 55.42&nbsp;ms** on a 1&nbsp;M-token stream (**26.7&times; faster** than detokenize+regex; the speedup remains in ToolWatcher's favour by ~26-100&times; depending on host). The [MetaMCP gateway](/docs/codec-metamcp/) is the canonical place this primitive lives in production; the same hook works in any inference proxy, agent runtime, or middleware.
- **Cross-vocab agent handoff.** `Translator` pipes a stream from V_A to V_B via one in-process detokenize/retokenize step, UTF-8 never crosses the wire. Llama-3 &rarr; Qwen-2 at 2 K tokens: the bridge produces target-vocab IDs **~30% sooner** (10.9&nbsp;ms &rarr; 7.7&nbsp;ms bridge CPU) on **15.1&times;** fewer wire bytes. Both paths emit byte-identical Qwen-2 output; the bench asserts strict equality.

## Wire format in five sentences

Each Codec frame is **4-byte big-endian length** + **msgpack or protobuf body**. The body carries a packed array of `uint32` token IDs, a `done` boolean, and an optional `finish_reason`. A vocab handshake (a sha256-addressed JSON map, either resolved automatically via `/.well-known/codec/maps/<id>.json` from the server's `Codec-Tokenizer-Map` response header, or fetched directly from [codec-maps](https://github.com/wdunn001/codec-maps) and hash-pinned) tells both ends which tokenizer the IDs belong to. Frames stream over plain HTTP responses; clients advertise `Accept-Encoding: zstd, br, gzip, identity` and the server picks the smallest valid encoding per spec preference (`zstd > br > gzip > identity`). That's the whole spec, nothing else.

## Where Codec earns its keep

Codec is opt-in per request (`stream_format: "msgpack" | "protobuf"`, default `"json"`). Adding it never disturbs existing JSON-SSE traffic on the same endpoint. Pick the format that fits the call.

- **Inference gateways.** Token IDs at the wire and at the dispatch layer. ToolWatcher signals fire on raw IDs in real time; the gateway's text-touching code (JSON-RPC dispatch to MCP servers, human-display sinks) runs once at the seam. The [MetaMCP gateway](/docs/codec-metamcp/) ships this pattern as a docker image; the same primitive is reusable in any proxy, agent runtime, or middleware.
- **Heterogeneous model meshes.** `Translator` carries one model's stream into another's vocabulary without UTF-8 ever crossing the wire. Measured Llama-3 &rarr; Qwen-2 handoff: **15.1&times; smaller wire** with bridge CPU within noise of detokenize+retokenize, byte-identical Qwen-2 output. Source: [`packages/bench/results/2026-05-15T20-00-00Z/translator/`](https://github.com/wdunn001/Codec/tree/main/packages/bench/results/2026-05-15T20-00-00Z/translator).
- **Agent-to-agent traffic.** No human is reading these tokens. Vocab fixed at handshake, dict pre-shared, msgpack frames collapse to a control byte plus a delta. The **1,707&times;** sglang / **3,868&times;** llama.cpp engine-output headlines at 2 K tokens live here.
- **Streaming long outputs at scale.** Wire bytes &asymp; content-length / 4 uncompressed; with dict-zstd the marginal cost per extra token is two compressed bytes. The win compounds with payload size.
- **Human-facing chat UIs.** ~67&times; smaller wire on a short reply, **~1,700&times;** on long ones (sglang), TTFB within 1&nbsp;ms of JSON-SSE. The client decodes once into a string at the edge before render; mobile, edge, and chat-platform-scale traffic all benefit. Bandwidth drops without users seeing anything except faster paint on flaky networks.
- **Observable inference.** Routing, sampling decisions, anomaly detection, SLO checks, everything you'd want a service mesh to do, all reduce to integer comparisons on token streams. No log-scraping a JSON envelope; no detokenize-every-chunk pipeline.

The one constraint: **Codec is a wire-and-dispatch primitive. It is no JSON-to-Codec transformation gateway.** Both client and server need to speak it. If you're calling a third-party JSON-only API you don't control, that's outside Codec's scope. We can't compress bytes a service refuses to emit. Stand up your own and you control both ends.

### Stand up a Codec-speaking server in 30 seconds

Three pre-built Docker images, each `docker run`-ready and OpenAI-compatible. Pick the engine that fits your model + GPU stack:

- **[`codec-sglang`](/docs/codec-sglang/)**, full Codec stack (msgpack/protobuf, gzip + brotli + dict-zstd). The **1,707&times;** headline lane at 2 K tokens.
- **[`codec-vllm`](/docs/codec-vllm/)**, Codec PR over upstream vllm with dicts pre-baked. **137&times;** at 2 K with dict-zstd live (v0.4.1).
- **[`codec-llamacpp`](/docs/codec-llamacpp/)**, llama.cpp built from the fork with the Codec PR + streaming br + zstd middleware (added v0.4.1). **3,868&times;** at 2 K with dict-zstd (fp16); ideal for CPU/edge boxes.

If you'd rather build from source against vanilla upstream, see [sglang vanilla setup](/docs/sglang/) for the DIY path. The wire is bit-identical between the bundled and DIY paths.

## Source-available, BSL 1.1

The protocol and the six reference implementations are published under [BSL 1.1](https://github.com/wdunn001/Codec/blob/main/LICENSE) by Quasarke LLC. Free for non-production use and for production use under US&nbsp;$5M annual revenue. Each release auto-converts to Apache-2.0 four years after publication. For commercial licensing, [licensing@quasarke.com](mailto:licensing@quasarke.com).

Next: pick a runtime in the sidebar, or jump to the [quickstart](/docs/quickstart/).
