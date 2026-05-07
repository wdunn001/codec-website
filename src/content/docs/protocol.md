---
title: Protocol overview
description: The wire format in detail — frames, vocab handshake, transports, compression. Everything you need to write a fifth implementation.
section: Start
order: 3
---

This is a tour of [PROTOCOL.md](https://github.com/wdunn001/Codec/blob/main/spec/PROTOCOL.md), the canonical spec. If you're using one of the six reference implementations you don't need to read it &mdash; the bindings already speak the protocol for you.

## Layers

Codec is deliberately three thin layers on top of HTTP, not one fat envelope:

| Layer | What it carries | What it does NOT carry |
|---|---|---|
| **Token IDs** | `uint32[]` | Text, role markers, tool framing |
| **Frames** | `{ids, done, finish_reason?}` | Token semantics |
| **Vocab handshake** | sha256-addressed JSON map | Frames |

The handshake binds an ID space to a tokenizer; frames carry IDs in that space; the IDs map back to tokens *only* when a human edge needs them.

## Frame format

Every frame on the wire is:

```
+---------------------+----------------------------+
| 4-byte BE length    | msgpack OR protobuf body   |
+---------------------+----------------------------+
```

The body is one of:

**msgpack** &mdash; a map with three optional keys:

```
{ "ids": [uint32, uint32, ...], "done": bool, "finish_reason": str (optional) }
```

**protobuf** &mdash; a `CodecFrame` message:

```proto
message CodecFrame {
  repeated uint32 ids = 1 [packed = true];
  bool done = 2;
  optional string finish_reason = 3;
}
```

Both bind to identical semantics. Pick msgpack if you want zero schema dependencies; pick protobuf if you want stricter typing or already have a `protoc` toolchain.

## Vocab handshake

A *dialect map* is a JSON document that fully describes a tokenizer:

- `vocab` &mdash; the token-string-to-ID map
- `merges` &mdash; BPE merge rules
- `special_tokens` &mdash; reserved control IDs (`<|im_start|>`, `<tool_call>`, etc.)
- `encoder_type` &mdash; `byte_level`, `metaspace`, or omitted
- `pre_tokenizer_program` (optional) &mdash; a small instruction list that replaces the legacy GPT-2 regex; deterministic across languages

Maps are addressed by **sha256 of the canonical JSON bytes**. `loadMap({url, hash})` is `fetch + verify + cache`. A given `(url, hash)` pair always resolves to byte-identical bytes &mdash; or `loadMap` raises.

The community-curated set of pre-built maps for major model families (Llama, Qwen, Mistral, GPT-OSS, etc.) lives at [github.com/wdunn001/codec-maps](https://github.com/wdunn001/codec-maps).

### Discovery

If you don't want to track URLs and hashes out of band, model maintainers can publish maps at a stable `/.well-known/codec/` path on a domain they control. Clients then resolve a map from `(origin, id)` alone:

```ts
import { discoverMap } from "@codecai/web/discover";
const map = await discoverMap({ origin: "https://example.com", id: "qwen2" });
```

This is the resolution to PROTOCOL.md's old Open Question #3 (decentralised first; a registry remains an option for cross-org and air-gapped use). Full convention: [Self-hosted discovery](/docs/discovery/).

## HTTP transports

The spec defines three patterns over plain HTTP, in increasing weirdness:

### A. Text prompt in, binary stream out

The drop-in upgrade. Same JSON request body as today's `/v1/completions`, plus `stream_format`:

```http
POST /v1/completions HTTP/1.1
Content-Type: application/json
Accept-Encoding: gzip

{
  "model": "Qwen/Qwen2.5-7B-Instruct",
  "prompt": "Explain entropy.",
  "stream_format": "msgpack",
  "max_tokens": 256
}
```

Response body is a sequence of length-prefixed msgpack frames. `Content-Type: application/codec+msgpack` (or `+protobuf`).

### B. Token-ID prompt, binary in, binary out

Skip the server's tokenizer call entirely:

```json
{
  "model": "Qwen/Qwen2.5-7B-Instruct",
  "prompt": [4954, 198, 11, 5234, ...],
  "stream_format": "msgpack",
  "max_tokens": 256
}
```

Useful when the client already has the IDs (e.g., during multi-hop agent flows where a previous Codec response *is* the next prompt).

### C. Binary in, binary out: `/v1/completions/codec`

For very large prompts where even the JSON envelope is too big. The whole request body is a Codec frame; the response is a Codec stream. Documented in [PROTOCOL.md §3.3](https://github.com/wdunn001/Codec/blob/main/spec/PROTOCOL.md).

## Compression

Codec is **streaming-safe with gzip**. Set `Accept-Encoding: gzip, identity` on the request; the server compresses if it's worth it. Identity is always a valid response. Brotli underperforms gzip at every payload size measured (per-block overhead doesn't amortize on small frames).

### zstd is dict-only

zstd without a pre-trained dictionary is a trap on Codec streams: its wire-byte advantage over gzip is essentially zero (both reach &asymp;3.4&nbsp;B/token, within noise &mdash; [RESULTS.md §1f](https://github.com/wdunn001/Codec/blob/main/packages/bench/RESULTS.md)) but the shipped buffered middleware in every gateway eats a **334&times; TTFB cliff** at 2K tokens (11&nbsp;ms &rarr; 3,684&nbsp;ms). Same bytes as gzip, much worse first-token latency.

**The pre-trained dictionary is the precondition for using zstd at all** &mdash; not an optimization layered on top. Tokenizer maps now declare zstd dictionaries inline:

```json
{
  "id": "qwen/qwen2",
  "vocab": { ... },
  "merges": [ ... ],
  "zstd_dictionaries": [
    {
      "format":     "msgpack",
      "url":        "https://raw.githubusercontent.com/wdunn001/Codec/main/dictionaries/qwen2.5-msgpack-v1.dict",
      "hash":       "sha256:...",
      "size_bytes": 16384
    },
    {
      "format":     "protobuf",
      "url":        "https://raw.githubusercontent.com/wdunn001/Codec/main/dictionaries/qwen2.5-protobuf-v1.dict",
      "hash":       "sha256:...",
      "size_bytes": 16384
    }
  ]
}
```

A server with a matching dict loaded compresses against it; a client decompresses against the same one (matched by hash). The two formats train against different byte distributions, so dicts are not interchangeable across `msgpack` / `protobuf`. Without a loaded dict, servers MUST fall through to gzip &mdash; the picker enforces this and the wire-compress library refuses to advertise zstd unless a matching dict is in place.

With a dict, dict-zstd beats gzip by **16&ndash;38%** on bytes ([RESULTS.md §1g](https://github.com/wdunn001/Codec/blob/main/packages/bench/RESULTS.md)) at +0.13&nbsp;ms streaming TTFB &mdash; sub-millisecond, dwarfed by network. So for a deployment with a dict shipped alongside the model, zstd is the right pick for both interactive and agent traffic.

### `Codec-Zstd-Dict` response header

When a server responds with `Content-Encoding: zstd`, it MUST emit the hash of the dictionary it used as a `Codec-Zstd-Dict` header:

```http
Content-Encoding: zstd
Codec-Zstd-Dict:  sha256:79b707aea8c2b41c2883ec7913b0c4a0c880044ac844d89a9a03e779eb92db04
Vary:             Accept-Encoding
```

The header value is `sha256:` followed by the lowercase hex digest of the raw dictionary bytes &mdash; same shape as the `hash` field in `zstd_dictionaries[]` entries.

Clients check the hash against a dict they have loaded. Hash mismatch is a fatal stream error (wrong-dict zstd decompression yields garbage); a missing header on a zstd response is a server protocol error. Why a header rather than inferring from `tokenizer_id`: a single tokenizer can have multiple dict versions over time (re-trained on fresher corpora, specialised per workload). The header lets a deployment upgrade its dict without bumping the tokenizer-map version, and lets intermediaries identify the active dict by reading headers alone.

Reference dicts ship at [`dictionaries/`](https://github.com/wdunn001/Codec/tree/main/dictionaries) in the main repo; the training pipeline is [`packages/bench/scripts/train-zstd-dict.py`](https://github.com/wdunn001/Codec/blob/main/packages/bench/scripts/train-zstd-dict.py).

## Polyglot bit-identical

The six reference implementations (TypeScript, Python, .NET, C, Rust, Java) all produce **byte-identical** wire output for the same inputs. The CI matrix encodes the same prompt with each binding and asserts a SHA match. If your seventh implementation matches the bytes from any one of those, you're correct.
