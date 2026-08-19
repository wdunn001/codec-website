---
title: Rust (codec-rs)
description: Native Rust crate. Sync iterators by default, async via the tokio feature. Hand-rolled protobuf, zero-cost token IDs, full sha256 map verification.
section: Frameworks
order: 5
---

`codec-rs` is the Rust binding. The wire-format primitives are sync and runtime-agnostic, an iterator over `std::io::Read`. Async stream variants wrap them behind the `tokio` feature for callers that already speak `AsyncRead`.

It's the natural fit for embedding Codec into inference engines (TGI is Rust; that's where this lives most happily) and for any high-throughput proxy that wants to forward token IDs without ever lifting them through a language runtime.

## Install

```bash
cargo add codec-rs
```

By default the `http` feature is on (pulls `reqwest` for `MapLoader`). For a minimal build (e.g. embedding inside a server that brings its own HTTP client), turn it off:

```toml
[dependencies]
codec-rs = { version = "0.1", default-features = false }
```

For the async stream API, opt in to `tokio`:

```toml
[dependencies]
codec-rs = { version = "0.1", features = ["tokio"] }
```

## The four-step shape

```rust
use codec_rs::{
    LoadOptions, MapLoader,                       // 1. fetch + verify map
    decode_msgpack_stream,                        // 2. stream → frames
    Detokenizer, DetokenizeOptions,               // 3. IDs → text
};
```

### 1. Load the vocab map

```rust
let map = MapLoader::default().load(LoadOptions {
    url:  "https://cdn.jsdelivr.net/gh/wdunn001/codec-maps/maps/qwen/qwen2.json".into(),
    hash: Some("sha256:887311099cdc09e7022001a01fa1da396750d669b7ed2c242a000b9badd09791".into()),
    ..Default::default()
}).await?;
```

`MapLoader` is async; for sync code call `MapLoader::default().load_blocking(opts)`. The hash is verified before parsing. A mismatch returns `LoadError::HashMismatch`.

### 2. Send a request

```rust
use reqwest::Client;
use serde_json::json;

let body = json!({
    "model":         "Qwen/Qwen2.5-7B-Instruct",
    "prompt":        "Explain entropy in one paragraph.",
    "stream_format": "msgpack",
    "max_tokens":    256,
});

let resp = Client::new()
    .post("http://localhost:8000/v1/completions")
    .header("Accept-Encoding", "gzip")
    .json(&body)
    .send()
    .await?;
```

### 3. Decode the binary stream

The sync API takes any `Read`:

```rust
use std::io::Cursor;
use codec_rs::decode_msgpack_stream;

let bytes = resp.bytes().await?;
for frame in decode_msgpack_stream(Cursor::new(&bytes)) {
    let frame = frame?;
    // frame.ids: Vec<u32>
    // frame.done: bool
    // frame.finish_reason: Option<String>
}
```

For true streaming with the `tokio` feature, use the async variant on the body stream directly:

```rust
use codec_rs::stream::decode_msgpack_stream_async;
use futures_util::StreamExt;

let mut frames = decode_msgpack_stream_async(resp.bytes_stream());
while let Some(frame) = frames.next().await {
    let frame = frame?;
    // ...
}
```

`decode_protobuf_stream` / `decode_protobuf_stream_async` cover the protobuf wire mode.

### 4. Detokenize at the edge

```rust
let mut detok = Detokenizer::new(&map);

for frame in decode_msgpack_stream(Cursor::new(&bytes)) {
    let frame = frame?;
    let text = detok.render(&frame.ids, DetokenizeOptions {
        partial: !frame.done,
        render_special: false,
    });
    print!("{text}");
}
```

`Detokenizer` is **stateful**. It persists partial UTF-8 bytes across `render()` calls when `partial: true`. A 4-byte 🚀 split across two frames round-trips identically. Call `detok.reset()` between unrelated streams.

## Encoding (sending IDs, not text)

```rust
use codec_rs::BPETokenizer;

let mut tok = BPETokenizer::new(&map);
let ids: Vec<u32> = tok.encode("System: be concise.\nUser: what's BPE?");

let body = json!({
    "model":         "Qwen/Qwen2.5-7B-Instruct",
    "prompt":        ids,           // Vec<u32> serializes as int[]; servers read as token IDs
    "stream_format": "msgpack",
    "max_tokens":    256,
});
```

`BPETokenizer::encode` is bit-identical to the upstream model's tokenizer (verified against HuggingFace tokenizers reference for Qwen-2 across all reference bindings). Greedy by merge priority, not left-to-right.

## Watching for tool calls

```rust
use codec_rs::{ToolWatcher, WatcherEventKind};

let mut watcher = ToolWatcher::new(&map, "<tool_call>", "</tool_call>")?;

for frame in decode_msgpack_stream(Cursor::new(&bytes)) {
    let frame = frame?;
    for ev in watcher.feed(&frame.ids) {
        match ev.kind {
            WatcherEventKind::Passthrough => forward(&ev.ids),
            WatcherEventKind::Captured    => {
                let text = detok.render(&ev.ids, DetokenizeOptions::default());
                let (tool, args) = parse_tool_call(&text);
                dispatch(&tool, args).await?;
            }
        }
    }
}
```

A single `u32` compare per token, no detokenization on the hot path. The watcher never reads `map.vocab`, only `map.special_tokens` resolution at construction time. See [Tool calling](/docs/tool-calling/).

## Translating across vocabularies

```rust
use codec_rs::Translator;

let qwen  = MapLoader::default().load(LoadOptions {
    url:  "https://cdn.jsdelivr.net/gh/wdunn001/codec-maps/maps/qwen/qwen2.json".into(),
    hash: Some("sha256:887311099cdc09e7022001a01fa1da396750d669b7ed2c242a000b9badd09791".into()),
    ..Default::default()
}).await?;
let llama = MapLoader::default().load(LoadOptions {
    url:  "https://cdn.jsdelivr.net/gh/wdunn001/codec-maps/maps/meta-llama/llama-3.json".into(),
    hash: Some("sha256:79b707aea8c2b41c2883ec7913b0c4a0c880044ac844d89a9a03e779eb92db04".into()),
    ..Default::default()
}).await?;

let mut tr = Translator::new(&qwen, &llama)?;

for frame in decode_msgpack_stream(Cursor::new(&qwen_bytes)) {
    let frame = frame?;
    let llama_ids = tr.translate(&frame.ids, !frame.done);
    forward_to_llama(&llama_ids);
}
```

See [Translator](/docs/translator/).

## Production checklist

- **Pin the map hash.** `LoadOptions { hash: Some(...) }`. `MapLoader` returns `LoadError::HashMismatch` on mismatch, no panic.
- **Reuse `Detokenizer` and `Translator`.** They're stateful by design; new instances mid-stream drop partial-byte buffers. Call `.reset()` at stream boundaries instead.
- **The sync iterator is the canonical API.** Async is a thin wrapper for callers already in a Tokio runtime. Anything calling out to a HTTP body works either way.
- **No unsafe in the crate.** `cargo geiger` reports zero. Safe to embed.

## See also

- [Tool calling](/docs/tool-calling/)
- [Translator](/docs/translator/)
- [packages/rust/ on GitHub](https://github.com/wdunn001/Codec/tree/main/packages/rust)
