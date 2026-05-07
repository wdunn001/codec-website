---
title: Python — codecai
description: Async-first binding for Python 3.10+. Decode streams, encode IDs, watch tool calls, translate across vocabs.
section: Frameworks
order: 2
---

`codecai` is the Python binding. It's async-first (built on `httpx`-style streams), pure-Python, no compiled extension. Python 3.10+ is required for the type annotations.

## Install

```bash
pip install codecai
```

## The four-step shape

Every Codec client follows the same four steps. In Python:

```python
from codecai import (
    load_map,                # 1. fetch + verify the vocab map
    Detokenizer,             # 2. (and 4.) IDs → text
    decode_msgpack_stream,   # 3. binary stream → frames
)
```

### 1. Load the vocab map

```python
map = await load_map(
    url="https://cdn.jsdelivr.net/gh/wdunn001/codec-maps/maps/qwen/qwen2.json",
    hash="sha256:c73972f7a580...",
)
```

`load_map` is async because it fetches over the network. It verifies the response bytes against `hash` and caches the parsed map.

### 2. Send a request

A normal `/v1/completions` POST with `stream_format` added:

```python
import httpx

async with httpx.AsyncClient() as client:
    async with client.stream(
        "POST", "http://localhost:8000/v1/completions",
        json={
            "model": "Qwen/Qwen2.5-7B-Instruct",
            "prompt": "Explain entropy in one paragraph.",
            "stream_format": "msgpack",
            "max_tokens": 256,
        },
        headers={"Accept-Encoding": "gzip"},
    ) as resp:
        # see step 3
        ...
```

> **Why `client.stream` over `client.post`?** `stream` doesn't buffer the response body &mdash; you want each chunk to flow through the decoder as it arrives.

### 3. Decode the binary stream

```python
async for frame in decode_msgpack_stream(resp.aiter_raw()):
    # frame.ids: list[int]
    # frame.done: bool
    # frame.finish_reason: str | None
    ...
```

`decode_msgpack_stream` consumes an async byte iterator and yields `CodecFrame` objects. Use `decode_protobuf_stream` if your server is configured for protobuf instead.

### 4. Detokenize at the edge

```python
detok = Detokenizer(map)

async for frame in decode_msgpack_stream(resp.aiter_raw()):
    text = detok.render(frame.ids, partial=not frame.done)
    print(text, end="", flush=True)
```

`Detokenizer` is stateful and **stream-safe** &mdash; it buffers split UTF-8 sequences across `render` calls. Pass `partial=True` while the stream is open; the final call (or any call where you know the stream is done) should be `partial=False` so the buffer flushes.

## Encoding (sending IDs, not text)

If you already have token IDs:

```python
from codecai import BPETokenizer

tok = BPETokenizer(map)
ids = tok.encode("System: be concise.\nUser: what's BPE?")

async with client.stream(
    "POST", "http://localhost:8000/v1/completions",
    json={
        "model": "Qwen/Qwen2.5-7B-Instruct",
        "prompt": ids,           # list[int]
        "stream_format": "msgpack",
        "max_tokens": 256,
    },
) as resp:
    ...
```

`BPETokenizer.encode()` produces bit-identical IDs to the upstream model's tokenizer.

## Watching for tool calls

```python
from codecai import ToolWatcher

watcher = ToolWatcher(map, start="<tool_call>", end="</tool_call>")

async for frame in decode_msgpack_stream(resp.aiter_raw()):
    for ev in watcher.feed(frame.ids):
        if ev.kind == "passthrough":
            forward(ev.ids)
        else:  # ev.kind == "captured"
            text = detok.render(ev.ids)
            tool, args = parse_tool_call(text)
            await dispatch(tool, args)
```

The watcher matches reserved control IDs with a single `uint32` compare per token. It never detokenizes &mdash; that's the whole point. See [Tool calling](/docs/tool-calling/) for the agentic-loop pattern.

## Translating across vocabularies

```python
from codecai import Translator

qwen  = await load_map(url="...", hash="...")
llama = await load_map(url="...", hash="...")

tr = Translator(qwen, llama)

async for frame in decode_msgpack_stream(qwen_resp.aiter_raw()):
    llama_ids = tr.translate(frame.ids, partial=not frame.done)
    forward_to_llama_agent(llama_ids)
```

Cross-vocab handoff that never goes through UTF-8. See [Translator](/docs/translator/).

## A complete agent loop

The `packages/demo-python/` directory in the main repo has a runnable agent example with real tool dispatch. Highlights:

```python
import asyncio, httpx
from codecai import Detokenizer, ToolWatcher, decode_msgpack_stream, load_map

async def run_turn(prompt_ids, map, http):
    detok   = Detokenizer(map)
    watcher = ToolWatcher(map, start="<tool_call>", end="</tool_call>")

    async with http.stream("POST", SERVER + "/v1/completions", json={
        "model": MODEL, "prompt": prompt_ids,
        "stream_format": "msgpack", "max_tokens": 512,
    }) as resp:
        async for frame in decode_msgpack_stream(resp.aiter_raw()):
            for ev in watcher.feed(frame.ids):
                if ev.kind == "passthrough":
                    yield ("text", detok.render(ev.ids, partial=not frame.done))
                else:
                    yield ("tool", detok.render(ev.ids))
            if frame.done:
                return frame.finish_reason
```

Yields `("text", str)` for normal output and `("tool", str)` when the model emits a tool-call region.

## Production checklist

- **Pin the map hash.** Mismatch = supply-chain alarm.
- **Use `client.stream`, not `client.post`.** Otherwise the entire response buffers in memory.
- **Reuse `Detokenizer` and `BPETokenizer`** across requests; both are stateless across-stream (the detokenizer's buffer resets at each new stream).
- **Async ergonomics.** Wrap the decode loop in a `try/finally` if you need to clean up &mdash; `aiter_raw()` doesn't auto-close.

## See also

- [Tool calling](/docs/tool-calling/)
- [Translator](/docs/translator/)
- [codecai on PyPI](https://pypi.org/project/codecai/)
- [packages/python/ on GitHub](https://github.com/wdunn001/Codec/tree/main/packages/python)
