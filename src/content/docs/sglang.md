---
title: sglang (vanilla)
description: Run upstream sglang with the Codec patches applied yourself. Use this when you need a custom build; otherwise prefer the pre-built codec-sglang Docker image.
section: Server
order: 2
---

> **If you just want a working server**, use the pre-built [codec-sglang Docker image](/docs/codec-sglang/) &mdash; one container, GPU-ready, supervisor and patches already applied. This page is for the DIY path: vanilla upstream sglang plus the Codec patches.

[sglang](https://github.com/sgl-project/sglang) is the easiest path to a Codec-speaking server. With the Codec patches applied, the standard `/v1/completions` endpoint accepts `stream_format: "msgpack" | "protobuf"` against any model it can serve.

## Run a Codec-capable sglang server

The pre-built `codec-sglang` image (or `wdunn001/sglang` source build with the codec patches applied) is the simplest:

```bash
docker run --gpus all -p 30000:30000 --ipc host \
  wdunn001/codec-sglang:latest
```

That's it &mdash; the server now speaks both JSON-SSE and Codec on the same endpoint. Clients pick which one they want via the request body.

> **Why a fork?** sglang upstream merges new transports through formal proposals; while the Codec patches stabilise we ship them in `wdunn001/sglang` (CUDA 12 builds in [`wdunn001/codec-supervisor`](https://github.com/wdunn001/codec-supervisor)). The patch is a thin overlay &mdash; cherry-pickable on any recent upstream nightly.

## Request shape

The client picks the wire format on a per-request basis by adding `stream_format`:

```http
POST /v1/completions HTTP/1.1
Host: localhost:30000
Content-Type: application/json
Accept-Encoding: gzip

{
  "model": "Qwen/Qwen2.5-7B-Instruct",
  "prompt": "Explain entropy.",
  "stream_format": "msgpack",
  "max_tokens": 256
}
```

Server responds with `Content-Type: application/codec+msgpack` and a sequence of length-prefixed msgpack frames. Every other knob (temperature, top-p, max_tokens, stop sequences) works exactly as before.

If the client omits `stream_format` (or sets `stream: true`), sglang behaves exactly as upstream &mdash; you get JSON-SSE. So one server can simultaneously serve a JSON SaaS chat UI and a Codec-native agent fleet.

## Server-side ToolWatcher

The Codec patches add an in-server tool-call detector that runs on the token-ID stream *before* the stream leaves the server. When the model emits a tool-call region, sglang surfaces it as a discrete event in the Codec stream &mdash; with a reserved control-ID frame the client picks up via `ToolWatcher.feed()`.

This is the source of the **~100&times; tool-call detection speedup** in [RESULTS.md §3](https://github.com/wdunn001/Codec/blob/main/RESULTS.md). The server skips its usual "detokenize and regex-match against tool delimiters" step entirely; the client gets pre-segmented frames and can dispatch with no further parsing.

```python
from codecai import Detokenizer, ToolWatcher, decode_msgpack_stream, load_map

watcher = ToolWatcher(map, start="<tool_call>", end="</tool_call>")

async for frame in decode_msgpack_stream(resp.aiter_raw()):
    for ev in watcher.feed(frame.ids):
        if ev.kind == "captured":
            await dispatch(detok.render(ev.ids))
```

The same client-side code works whether or not the server runs the in-server detector &mdash; if the server doesn't pre-segment, the watcher segments client-side. The server-side detector just moves the work earlier in the pipeline.

## End-to-end agentic example numbers

Live runs from [RESULTS.md](https://github.com/wdunn001/Codec/blob/main/RESULTS.md) on a real sglang server with two-turn tool dispatch:

| Path | Wire (2 turns) | TTFB | Total |
|---|---:|---:|---:|
| JSON-SSE + client regex | 61.9 KB | 52 ms | 2,426 ms |
| Codec + ToolWatcher     | 3.4 KB  | 16 ms | 1,954 ms |

18&times; less wire, 20% faster end-to-end on a real-world agent loop with a real-world tool (SearXNG search).

## Configuration knobs

`stream_format` is the only Codec-specific request knob. The compression negotiation is the standard HTTP `Accept-Encoding`. `gzip, identity` is the safe default for any streaming workload &mdash; gzip preserves TTFT and gives 30&ndash;40&times; wire savings on Codec frames.

### zstd, with a dict

`zstd` is supported but **only when the server has a pre-trained dictionary loaded for the request's `stream_format`** &mdash; see [Protocol &raquo; Compression](/docs/protocol/#zstd-is-dict-only) for the rule and the rationale. Without a dict, sglang's compression module falls through to gzip even if the client advertised `zstd` &mdash; no-dict zstd's bytes match gzip but the buffered middleware adds a 334&times; TTFB cliff at 2K tokens.

The reference dicts in the main repo's [`dictionaries/`](https://github.com/wdunn001/Codec/tree/main/dictionaries) are trained for Qwen-2.5 / msgpack and Qwen-2.5 / protobuf. Load them at server startup:

```python
from sglang.srt.entrypoints.codec_compression import set_zstd_dict

with open("qwen2.5-msgpack-v1.dict", "rb") as f:
    set_zstd_dict("msgpack", f.read())
with open("qwen2.5-protobuf-v1.dict", "rb") as f:
    set_zstd_dict("protobuf", f.read())
```

After this, requests with `Accept-Encoding: zstd, gzip` come back with:

```http
Content-Encoding: zstd
Codec-Zstd-Dict:  sha256:<hex of the dict bytes>
Vary:             Accept-Encoding
```

Clients use the `Codec-Zstd-Dict` header to pick the right local dict before decompressing. With dict-zstd the wire is **16&ndash;38% smaller** than gzip ([RESULTS.md §1g](https://github.com/wdunn001/Codec/blob/main/packages/bench/RESULTS.md)) at +0.13&nbsp;ms TTFB &mdash; sub-millisecond, dwarfed by network. For deployments that ship a dict alongside the model, zstd is the right pick for both interactive and agent traffic.

Deployments that don't load a dict keep getting gzip on every request &mdash; backward-compatible by default. Empty registry &rarr; zstd never picked.

## vLLM and llama.cpp

The same surface area &mdash; `stream_format` request field, server-side `ToolWatcher`, dict-gated zstd, and the `Codec-Zstd-Dict` response header &mdash; is shipped in pre-built form as [`codec-vllm`](/docs/codec-vllm/) and [`codec-llamacpp`](/docs/codec-llamacpp/).

## See also

- [TypeScript](/docs/typescript/), [Python](/docs/python/), [.NET](/docs/dotnet/) &mdash; client walkthroughs.
- [Tool calling](/docs/tool-calling/) &mdash; detail on `ToolWatcher` events and dispatch.
- [PROTOCOL.md](https://github.com/wdunn001/Codec/blob/main/spec/PROTOCOL.md) &mdash; the wire spec.
