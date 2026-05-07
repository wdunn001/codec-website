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

- **Wire bytes collapse** &mdash; up to 470&times; smaller than JSON-SSE at 2,048-token streams (live numbers in [RESULTS.md](https://github.com/wdunn001/Codec/blob/main/RESULTS.md)).
- **Tool-call detection without detokenizing** &mdash; servers and middleboxes can dispatch on reserved control IDs with a single 32-bit compare per token (~100&times; faster than the text path).
- **Cross-vocab agent handoff** &mdash; the `Translator` re-tokenizes a stream from one model's vocab to another's mid-flight, no UTF-8 round-trip.

## Wire format in five sentences

Each Codec frame is **4-byte big-endian length** + **msgpack or protobuf body**. The body carries a packed array of `uint32` token IDs, a `done` boolean, and an optional `finish_reason`. A vocab handshake (a sha256-addressed JSON map &mdash; see [codec-maps](https://github.com/wdunn001/codec-maps)) tells both ends which tokenizer the IDs belong to. Frames stream over plain HTTP responses, with `Accept-Encoding: gzip` for streaming-safe compression. That's the whole spec &mdash; nothing else.

## When NOT to use Codec

- **You're building a chat UI for humans.** Just use SSE; the wire savings get eaten by every other thing on a typical webpage.
- **You don't control both ends.** Codec wins when both client and server speak it. If you're calling a JSON-only API, this protocol is not your bottleneck.

## When Codec earns its keep

- **Agent-to-agent traffic.** No human is reading these tokens; UTF-8 is dead weight.
- **Streaming long outputs at scale.** The wire bytes are roughly content-length divided by 4; the marginal cost per extra token is two compressed bytes.
- **Server-side tool dispatch.** Watching token IDs for control markers is essentially free; watching text for `<tool_call>` requires detokenizing every chunk.
- **Heterogeneous model meshes.** `Translator` lets a Llama-vocab agent emit a stream that a Qwen-vocab agent consumes without going through English in between.

## Source-available, BSL 1.1

The protocol and the four reference implementations are published under [BSL 1.1](https://github.com/wdunn001/Codec/blob/main/LICENSE) by Quasarke LLC. Free for non-production use and for production use under US&nbsp;$5M annual revenue. Each release auto-converts to Apache-2.0 four years after publication. For commercial licensing, [licensing@quasarke.com](mailto:licensing@quasarke.com).

Next: pick a runtime in the sidebar, or jump to the [quickstart](/docs/quickstart/).
