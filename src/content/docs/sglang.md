---
title: sglang (vanilla)
description: Run upstream sglang with the Codec patches applied yourself. Use this when you need a custom build; otherwise prefer the pre-built codec-sglang Docker image.
section: Server
order: 2
---

> **If you just want a working server**, use the pre-built [codec-sglang Docker image](/docs/codec-sglang/) &mdash; one container, GPU-ready, supervisor and patches already applied. This page is for the DIY path: vanilla upstream sglang plus the two Codec PRs.

[sglang](https://github.com/sgl-project/sglang) is the easiest path to a Codec-speaking server. As of [PR #24483](https://github.com/sgl-project/sglang/pulls) (merged) the standard sglang `/v1/completions` endpoint accepts `stream_format: "msgpack" | "protobuf"` against any model it can serve.

## Run a Codec-capable sglang server

You don't need a fork. Any nightly with PR #24483 and (for tool-call detection) [PR #24557](https://github.com/sgl-project/sglang/pulls) merged works:

```bash
docker run --gpus all -p 30000:30000 --ipc host \
  lmsysorg/sglang:latest \
  python3 -m sglang.launch_server \
    --model Qwen/Qwen2.5-7B-Instruct \
    --port 30000
```

That's it &mdash; the server now speaks both JSON-SSE and Codec on the same endpoint. Clients pick which one they want via the request body.

> **Server prerequisites in version terms:** sglang nightly tag `nightly-dev-cu12-20260506-22cf7d2b` or later. Check the [release notes](https://github.com/sgl-project/sglang/releases) for the exact build that lands on your platform.

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

## Server-side ToolWatcher (PR #24557)

PR #24557 adds an in-server tool-call detector that runs on the token-ID stream *before* the stream leaves the server. When the model emits a tool-call region, sglang surfaces it as a discrete event in the Codec stream &mdash; with a reserved control-ID frame the client picks up via `ToolWatcher.feed()`.

This is the source of the **~100&times; tool-call detection speedup** in [RESULTS.md §3](https://github.com/wdunn001/Codec/blob/main/RESULTS.md). The server skips its usual "detokenize and regex-match against tool delimiters" step entirely; the client gets pre-segmented frames and can dispatch with no further parsing.

```python
from codecai import Detokenizer, ToolWatcher, decode_msgpack_stream, load_map

watcher = ToolWatcher(map, start="<tool_call>", end="</tool_call>")

async for frame in decode_msgpack_stream(resp.aiter_raw()):
    for ev in watcher.feed(frame.ids):
        if ev.kind == "captured":
            await dispatch(detok.render(ev.ids))
```

The same client-side code works whether or not the server has PR #24557 merged &mdash; if the server doesn't pre-segment, the watcher segments client-side. PR #24557 just moves the work earlier in the pipeline.

## End-to-end agentic example numbers

Live runs from [RESULTS.md](https://github.com/wdunn001/Codec/blob/main/RESULTS.md) on a real sglang server with two-turn tool dispatch:

| Path | Wire (2 turns) | TTFB | Total |
|---|---:|---:|---:|
| JSON-SSE + client regex | 61.9 KB | 52 ms | 2,426 ms |
| Codec + ToolWatcher     | 3.4 KB  | 16 ms | 1,954 ms |

18&times; less wire, 20% faster end-to-end on a real-world agent loop with a real-world tool (SearXNG search).

## Configuration knobs

`stream_format` is the only Codec-specific request knob. The compression negotiation is the standard HTTP `Accept-Encoding`. **Use `gzip, identity` for streaming**; never request `zstd` on a streaming response &mdash; it buffers the whole stream before flushing (3.7 s TTFT regression at 2K tokens; see [RESULTS.md §1d](https://github.com/wdunn001/Codec/blob/main/RESULTS.md)).

## vLLM

vLLM support is in flight in [PR #41765](https://github.com/vllm-project/vllm/pulls). The shape will match sglang's: `stream_format` request field, no other changes. Watch that PR for status.

## See also

- [TypeScript](/docs/typescript/), [Python](/docs/python/), [.NET](/docs/dotnet/) &mdash; client walkthroughs.
- [Tool calling](/docs/tool-calling/) &mdash; detail on `ToolWatcher` events and dispatch.
- [PROTOCOL.md](https://github.com/wdunn001/Codec/blob/main/spec/PROTOCOL.md) &mdash; the wire spec.
