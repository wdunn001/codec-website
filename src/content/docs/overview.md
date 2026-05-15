---
title: What is Codec?
description: A control-plane primitive for AI inference. Lets gateways, routers, agents, and tool dispatchers operate on raw token IDs end-to-end, with detokenization localized at the edges that need text.
section: Start
order: 1
---

**Codec is a control-plane primitive for AI inference.** It's the substrate that lets gateways, routers, agents, tool dispatchers, and observers operate on raw token IDs end-to-end &mdash; no detokenize on the hot path, no JSON-parse per token, no UTF-8 round-trip at every hop. Compression and wire reduction are byproducts of the framing; what you actually buy is the ability to run the inference layer like infrastructure.

It separates three concerns that today's `/v1/chat/completions` mashes together:

1. **Token IDs** &mdash; the model layer. The protocol carries `uint32` IDs directly. Routing, sampling, observability, and tool dispatch all reduce to integer compares on the stream.
2. **Framing** &mdash; the transport layer. Length-prefixed msgpack or protobuf frames; the same wire on every engine in the matrix.
3. **UTF-8 text** &mdash; the presentation layer. Detokenization happens at the *edge*, only at the boundary that has a real reason to need text (a human display, a JSON-RPC tool call, a logging sink). Never per-token, never per-hop.

Three primitives fall out of that layering:

- **Wire-native streaming.** Token IDs flow as length-prefixed binary frames over plain HTTP. Compression layers on top of the same wire. Receipts: a short chat reply ships in 226&nbsp;B (vs 15.2&nbsp;KB JSON-SSE = ~67&times;); a 2 K-token agent stream in 354&nbsp;B (1,404&times;) on sglang with the full stack. TTFB is within 1&nbsp;ms of the JSON path on the same server. [Cross-stack matrix](https://github.com/wdunn001/Codec/blob/main/packages/bench/results/2026-05-08T01-15-02Z/MATRIX.md) covers three engines and six client languages.
- **Tool-call dispatch without detokenization.** `ToolWatcher` matches reserved control IDs in the raw token stream &mdash; one 32-bit compare per token. Microbench: **0.61 ms vs 60.4 ms** on a 1 M-token stream (~100&times; faster than detokenize+regex). The [MetaMCP gateway](/docs/codec-metamcp/) is the canonical place this primitive lives in production; the same hook works in any inference proxy, agent runtime, or middleware.
- **Cross-vocab agent handoff.** `Translator` pipes a stream from V_A to V_B via one in-process detokenize/retokenize step &mdash; UTF-8 never crosses the wire. Llama-3 &rarr; Qwen-2 at 2 K tokens: the bridge produces target-vocab IDs **~30% sooner** (10.9&nbsp;ms &rarr; 7.7&nbsp;ms bridge CPU) on **15.1&times;** fewer wire bytes. Both paths emit byte-identical Qwen-2 output; the bench asserts strict equality.

## Wire format in five sentences

Each Codec frame is **4-byte big-endian length** + **msgpack or protobuf body**. The body carries a packed array of `uint32` token IDs, a `done` boolean, and an optional `finish_reason`. A vocab handshake (a sha256-addressed JSON map &mdash; see [codec-maps](https://github.com/wdunn001/codec-maps)) tells both ends which tokenizer the IDs belong to. Frames stream over plain HTTP responses, with `Accept-Encoding: gzip` for streaming-safe compression. That's the whole spec &mdash; nothing else.

## Where Codec earns its keep

Codec is opt-in per request (`stream_format: "msgpack" | "protobuf"`, default `"json"`), so adding it never disturbs existing JSON-SSE traffic on the same endpoint. Pick the format that fits the call.

- **Inference gateways.** Token IDs at the wire and at the dispatch layer. ToolWatcher signals fire on raw IDs in real time; the gateway's text-touching code (JSON-RPC dispatch to MCP servers, human-display sinks) runs once at the seam. The [MetaMCP gateway](/docs/codec-metamcp/) ships this pattern as a docker image; the same primitive is reusable in any proxy, agent runtime, or middleware.
- **Heterogeneous model meshes.** `Translator` carries one model's stream into another's vocabulary without UTF-8 ever crossing the wire. Measured Llama-3 &rarr; Qwen-2 handoff: **~30% less bridge CPU** and **15.1&times; smaller wire**, byte-identical Qwen-2 output. Source: [`packages/bench/results/2026-05-08T01-15-02Z/translator/`](https://github.com/wdunn001/Codec/tree/main/packages/bench/results/2026-05-08T01-15-02Z/translator).
- **Agent-to-agent traffic.** No human is reading these tokens. Vocab fixed at handshake, dict pre-shared, msgpack frames collapse to a control byte plus a delta. The headline **1,404&times;** at 2 K tokens lives here.
- **Streaming long outputs at scale.** Wire bytes &asymp; content-length / 4 uncompressed; with dict-zstd the marginal cost per extra token is two compressed bytes. The win compounds with payload size.
- **Human-facing chat UIs.** ~67&times; smaller wire on a short reply, ~1,400&times; on long ones, TTFB within 1&nbsp;ms of JSON-SSE. The client decodes once into a string at the edge before render; mobile, edge, and chat-platform-scale traffic all benefit. Bandwidth drops without users seeing anything except faster paint on flaky networks.
- **Observable inference.** Routing, sampling decisions, anomaly detection, SLO checks &mdash; everything you'd want a service mesh to do &mdash; reduces to integer comparisons on token streams. No log-scraping a JSON envelope; no detokenize-every-chunk pipeline.

The one constraint: **Codec is a wire-and-dispatch primitive, not a JSON-to-Codec transformation gateway.** Both client and server need to speak it. If you're calling a third-party JSON-only API you don't control, that's outside Codec's scope &mdash; we can't compress bytes a service refuses to emit. Stand up your own and you control both ends.

### Stand up a Codec-speaking server in 30 seconds

Three pre-built Docker images, each `docker run`-ready and OpenAI-compatible. Pick the engine that fits your model + GPU stack:

- **[`codec-sglang`](/docs/codec-sglang/)** &mdash; full Codec stack (msgpack/protobuf, gzip + brotli + dict-zstd). The **1,404&times;** headline lane.
- **[`codec-vllm`](/docs/codec-vllm/)** &mdash; Codec PR over upstream vllm with dicts pre-baked. **126&times;** today via gzip; ~1,400&times; once the lifespan dict-loader hook lands on the wdunn001/vllm fork.
- **[`codec-llamacpp`](/docs/codec-llamacpp/)** &mdash; llama.cpp built from the fork with the Codec PR + streaming gzip middleware. **33&times;** at zero protocol cost; ideal for CPU/edge boxes.

If you'd rather build from source against vanilla upstream, see [sglang &mdash; vanilla setup](/docs/sglang/) for the DIY path. The wire is bit-identical between the bundled and DIY paths.

## Source-available, BSL 1.1

The protocol and the six reference implementations are published under [BSL 1.1](https://github.com/wdunn001/Codec/blob/main/LICENSE) by Quasarke LLC. Free for non-production use and for production use under US&nbsp;$5M annual revenue. Each release auto-converts to Apache-2.0 four years after publication. For commercial licensing, [licensing@quasarke.com](mailto:licensing@quasarke.com).

Next: pick a runtime in the sidebar, or jump to the [quickstart](/docs/quickstart/).
