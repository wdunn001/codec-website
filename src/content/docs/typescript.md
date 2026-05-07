---
title: TypeScript / Node — @codecai/web
description: The canonical reference implementation. Install, decode a stream, encode a request, watch for tool calls, translate across vocabs.
section: Frameworks
order: 1
---

`@codecai/web` is the reference TypeScript binding. It runs in modern browsers, Node 20+, and Bun without polyfills. The package ships ESM, the public API is fully typed, and the build output is tree-shakable &mdash; if you only use the decoder, you don't pay for the encoder.

## Install

```bash
npm install @codecai/web
# or pnpm / bun / yarn — same thing
```

## The four-step shape

Every Codec client in every language follows the same shape. In TypeScript:

```ts
import {
  loadMap,         // 1. fetch + verify the vocab map
  Detokenizer,     // 2. (and 4.) IDs → text
  decodeStream,    // 3. binary stream → frames
} from "@codecai/web";
```

### 1. Load the vocab map

```ts
const map = await loadMap({
  url:  "https://cdn.jsdelivr.net/gh/wdunn001/codec-maps/maps/qwen/qwen2.json",
  hash: "sha256:887311099cdc09e7022001a01fa1da396750d669b7ed2c242a000b9badd09791",
});
```

`loadMap` does three things:

- Fetches the URL.
- Verifies the bytes against the supplied `hash` (mismatch throws &mdash; this is your supply-chain check).
- Caches the parsed map by hash so subsequent loads are free.

Maps for the major model families are pre-built in [codec-maps](https://github.com/wdunn001/codec-maps); their hashes are pinned in that repo's README.

If the vendor publishes their own map under [`/.well-known/codec/`](/docs/discovery/), you can skip the URL/hash entirely and resolve from `(origin, id)`:

```ts
import { discoverMap } from "@codecai/web/discover";
const map = await discoverMap({ origin: "https://example.com", id: "qwen2" });
```

### 2. Send a request

A Codec request is **a normal `/v1/completions` POST with one extra field**: `stream_format`. The server reads the field and switches its response body from JSON-SSE to the matching binary frame format.

```ts
const resp = await fetch("http://localhost:8000/v1/completions", {
  method: "POST",
  headers: {
    "Content-Type": "application/json",
    "Accept-Encoding": "gzip",
  },
  body: JSON.stringify({
    model: "Qwen/Qwen2.5-7B-Instruct",
    prompt: "Explain entropy in one paragraph.",
    stream_format: "msgpack",
    max_tokens: 256,
  }),
});
```

> **Why msgpack over protobuf?** Both work and produce identical semantics. Pick **msgpack** if you want zero schema toolchain. Pick **protobuf** if you already have `protoc` set up or you need stricter typing across polyglot teams. Performance is within noise; the wire bytes match within 1%.

### 3. Decode the binary stream

```ts
import { decodeStream } from "@codecai/web";

if (!resp.ok || !resp.body) throw new Error(`HTTP ${resp.status}`);

for await (const frame of decodeStream(resp.body, "msgpack")) {
  // frame.ids: Uint32Array
  // frame.done: boolean
  // frame.finish_reason?: "stop" | "length" | ...
}
```

`decodeStream` returns an `AsyncIterable<CodecFrame>`. It owns the `ReadableStream` lock; let it run to completion or call `.return()` on the iterator if you bail early.

### 4. Detokenize at the edge

```ts
const detok = new Detokenizer(map);

for await (const frame of decodeStream(resp.body!, "msgpack")) {
  const text = detok.render(frame.ids, { partial: !frame.done });
  process.stdout.write(text);
}
```

`Detokenizer` is **stateful**. It buffers UTF-8 fragments across calls so a multi-byte character split across two frames renders correctly. Pass `{ partial: true }` while the stream is open and `{ partial: false }` (or omit) on the final flush; the partial flag tells the detokenizer to hold incomplete bytes back until the next call.

## Encoding (sending IDs, not text)

If you already have token IDs &mdash; for example, the *previous* response in an agent loop &mdash; skip the server's tokenizer:

```ts
import { BPETokenizer } from "@codecai/web";

const tokenizer = new BPETokenizer(map);
const ids = tokenizer.encode("System: be concise.\nUser: what's BPE?");

const resp = await fetch("http://localhost:8000/v1/completions", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({
    model: "Qwen/Qwen2.5-7B-Instruct",
    prompt: Array.from(ids),  // uint32[] — the prompt is now token IDs
    stream_format: "msgpack",
    max_tokens: 256,
  }),
});
```

`BPETokenizer.encode()` is bit-identical to the upstream model's tokenizer (verified across all four reference bindings). If the server's BPE produces different IDs from yours, [open an issue](https://github.com/wdunn001/Codec/issues) &mdash; the map is wrong.

## Watching for tool calls

```ts
import { ToolWatcher } from "@codecai/web";

const watcher = new ToolWatcher(map, "<tool_call>", "</tool_call>");

for await (const frame of decodeStream(resp.body!, "msgpack")) {
  for (const ev of watcher.feed(frame.ids)) {
    if (ev.kind === "passthrough") {
      // Stream these IDs to the user / next agent
      forward(ev.ids);
    } else {
      // ev.kind === "captured" — these are the tool-call body
      const text = detok.render(ev.ids);
      const { tool, args } = parseToolCall(text);
      dispatch(tool, args);
    }
  }
}
```

ToolWatcher does its work with a single `uint32` compare per token. It does **not** detokenize. On a 1M-token stream, it runs in **0.61 ms** vs **60.4 ms** for the text path &mdash; about 100&times; faster (see [Benchmarks](/#benchmarks)).

Full reference: [Tool calling](/docs/tool-calling/).

## Translating across vocabularies

```ts
import { Translator } from "@codecai/web";

const qwen = await loadMap({
  url:  "https://cdn.jsdelivr.net/gh/wdunn001/codec-maps/maps/qwen/qwen2.json",
  hash: "sha256:887311099cdc09e7022001a01fa1da396750d669b7ed2c242a000b9badd09791",
});
const llama = await loadMap({
  url:  "https://cdn.jsdelivr.net/gh/wdunn001/codec-maps/maps/meta-llama/llama-3.json",
  hash: "sha256:79b707aea8c2b41c2883ec7913b0c4a0c880044ac844d89a9a03e779eb92db04",
});

const tr = new Translator(qwen, llama);

for await (const frame of decodeStream(qwenResp.body!, "msgpack")) {
  const llamaIds = tr.translate(frame.ids, { partial: !frame.done });
  forwardToLlamaAgent(llamaIds);
}
```

The translator goes IDs → IDs without ever materializing UTF-8. It handles byte-level boundaries the same way `Detokenizer` does, so you can stream it.

Full reference: [Translator](/docs/translator/).

## Production checklist

- **Pin the map hash.** Never call `loadMap({ url, hash: undefined })` &mdash; the hash is the supply-chain seal.
- **Set `Accept-Encoding: gzip, identity`.** Streaming-safe and ~5&times; smaller than identity. Don't request zstd on streams &mdash; it buffers the whole response.
- **Reuse `Detokenizer` and `Tokenizer` instances** across requests. Both are reusable; only `decodeStream` is per-response.
- **Detokenize at the edge.** If you're forwarding the stream to another agent or to a server-side tool dispatcher, leave the IDs as IDs.

## See also

- [Tool calling](/docs/tool-calling/) &mdash; deeper dive on `ToolWatcher`.
- [Translator](/docs/translator/) &mdash; cross-vocab handoff details.
- [@codecai/web on npm](https://www.npmjs.com/package/@codecai/web) &mdash; the package readme has additional examples.
- [packages/web/ on GitHub](https://github.com/wdunn001/Codec/tree/main/packages/web) &mdash; source.
