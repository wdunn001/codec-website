---
title: What is Codec?
description: A token-native binary transport protocol for AI APIs. Replaces JSON-SSE with msgpack or protobuf frames carrying raw token IDs.
section: Start
order: 1
---

Codec is a wire format for **computer-to-computer** AI traffic. Where JSON-SSE wraps every character of every model output in syntax the LLM never reads, Codec ships **token IDs** &mdash; the integers a model already speaks &mdash; in compact length-prefixed frames.

It separates three concerns that today's `/v1/chat/completions` mashes together:

1. **Token IDs** &mdash; the model layer. The protocol carries `uint32` IDs directly.
2. **Framing** &mdash; the transport layer. Length-prefixed msgpack or protobuf frames.
3. **UTF-8 text** &mdash; the presentation layer. Detokenization happens at the *edge*, only when a human is going to read the output.

The wins:

- **Wire bytes collapse** &mdash; up to **1,404&times;** smaller than JSON-SSE at 2,048-token streams on sglang with the full Codec stack (msgpack + dict-zstd). 126&times; on vllm and 33&times; on llama.cpp with gzip alone. Live cross-stack numbers in [RESULTS.md](https://github.com/wdunn001/Codec/blob/main/RESULTS.md).
- **No latency tax** &mdash; TTFB at 2 K tokens is 40.7 ms (llama.cpp) / 45.6 ms (sglang) / 67.3 ms (vllm) on the Codec path, within 1 ms of JSON-SSE on the same engines. Wire reduction is essentially free in time.
- **Tool-call detection without detokenizing** &mdash; servers and middleboxes dispatch on reserved control IDs with a single 32-bit compare per token: 0.61 ms vs 60.4 ms on a 1 M-token stream (~100&times; faster than the text path).
- **Cross-vocab agent handoff** &mdash; the `Translator` re-tokenizes a stream from one model's vocab to another's mid-flight, no UTF-8 on the wire. Measured on a Llama-3 &rarr; Qwen-2 handoff at 2,048 tokens: **709 B vs 10.7 KB** on the wire (15.1&times; smaller, gzip both paths) and **7.6 ms vs 10.9 ms** of bridge CPU (~30% less work). Both paths emit byte-identical Qwen-2 IDs &mdash; the bench asserts strict equality.

## Wire format in five sentences

Each Codec frame is **4-byte big-endian length** + **msgpack or protobuf body**. The body carries a packed array of `uint32` token IDs, a `done` boolean, and an optional `finish_reason`. A vocab handshake (a sha256-addressed JSON map &mdash; see [codec-maps](https://github.com/wdunn001/codec-maps)) tells both ends which tokenizer the IDs belong to. Frames stream over plain HTTP responses, with `Accept-Encoding: gzip` for streaming-safe compression. That's the whole spec &mdash; nothing else.

## Where Codec wins

Codec is opt-in per request (`stream_format: "msgpack" | "protobuf"`, default `"json"`), so adding it never disturbs existing JSON-SSE traffic on the same endpoint. Pick the format that fits the call.

- **Human-facing chat UIs.** The wire is still ~1,400&times; smaller at 2 K tokens (sglang dict-zstd), TTFB is within 1 ms of JSON-SSE on the same server, and the client decodes once into a string before render. Mobile, edge, and chat-platform-scale traffic all benefit; the bandwidth bill drops without the user noticing anything except faster paint on flaky networks. See [the cross-stack benchmark matrix](https://github.com/wdunn001/Codec/blob/main/packages/bench/results/2026-05-08T01-15-02Z/MATRIX.md).
- **Agent-to-agent traffic.** No human is reading these tokens. The vocab is fixed at handshake, the dict is pre-shared, and msgpack frames collapse to a control byte and a delta. This is the lane Codec was built for &mdash; the headline 1,404&times; lives here.
- **Streaming long outputs at scale.** The wire bytes are roughly content-length divided by 4 uncompressed; with dict-zstd the marginal cost per extra token is two compressed bytes. Codec's win compounds with payload size.
- **Server-side tool dispatch.** Watching token IDs for control markers is essentially free &mdash; a single 32-bit compare per token. Watching text for `<tool_call>` requires detokenizing every chunk: 0.61 ms vs 60.4 ms on a 1 M-token stream.
- **Heterogeneous model meshes.** `Translator` lets a Llama-vocab agent emit a stream that a Qwen-vocab agent consumes without going through English on the wire &mdash; the actual measurement is **15.1&times; smaller wire and ~30% less bridge CPU** at 2 K tokens, both paths producing byte-identical Qwen-2 output. Source: [`packages/bench/results/2026-05-08T01-15-02Z/translator/`](https://github.com/wdunn001/Codec/tree/main/packages/bench/results/2026-05-08T01-15-02Z/translator).

The one constraint: **Codec is a wire format, not a transformation gateway.** Both client and server need to speak it. If you're calling a third-party JSON-only API you don't control, that's outside Codec's scope &mdash; the protocol can't reduce bytes a service refuses to emit. Stand up your own and you control both ends.

### Stand up a Codec-speaking server in 30 seconds

Three pre-built Docker images, each `docker run`-ready and OpenAI-compatible. Pick the engine that fits your model + GPU stack:

- **[`codec-sglang`](/docs/codec-sglang/)** &mdash; full Codec stack (msgpack/protobuf, gzip + brotli + dict-zstd). The **1,404&times;** headline lane.
- **[`codec-vllm`](/docs/codec-vllm/)** &mdash; Codec PR over upstream vllm with dicts pre-baked. **126&times;** today via gzip; ~1,400&times; once the lifespan dict-loader hook lands on the wdunn001/vllm fork.
- **[`codec-llamacpp`](/docs/codec-llamacpp/)** &mdash; llama.cpp built from the fork with the Codec PR + streaming gzip middleware. **33&times;** at zero protocol cost; ideal for CPU/edge boxes.

If you'd rather build from source against vanilla upstream, see [sglang &mdash; vanilla setup](/docs/sglang/) for the DIY path. The wire is bit-identical between the bundled and DIY paths.

## Source-available, BSL 1.1

The protocol and the six reference implementations are published under [BSL 1.1](https://github.com/wdunn001/Codec/blob/main/LICENSE) by Quasarke LLC. Free for non-production use and for production use under US&nbsp;$5M annual revenue. Each release auto-converts to Apache-2.0 four years after publication. For commercial licensing, [licensing@quasarke.com](mailto:licensing@quasarke.com).

Next: pick a runtime in the sidebar, or jump to the [quickstart](/docs/quickstart/).
