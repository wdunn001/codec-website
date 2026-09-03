---
title: Python (codecai)
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
    hash="sha256:62c2f94fcbdb9b49d51632314e64aa65894496bc39751cb90866049657a262ad",
)
```

`load_map` is async because it fetches over the network. It verifies the response bytes against `hash` and caches the parsed map.

If the vendor publishes their own map under [`/.well-known/codec/`](/docs/discovery/), skip the URL/hash and resolve from `(origin, id)`:

```python
from codecai import discover_map
map = await discover_map(origin="https://example.com", id="qwen2")
```

### 2. Send a request

A normal `/v1/completions` POST. `stream_format: "msgpack"` lives in the BODY because it piggybacks on OpenAI's request schema; the Codec REQUEST HEADERS are `Accept-Encoding` (compression menu) and `Codec-Client-Version` (v0.4 capability advertisement). See [Protocol &raquo; Request vs response](/docs/protocol/#request-vs-response-where-each-codec-knob-lives) for the full split.

```python
import httpx

async with httpx.AsyncClient() as client:
    async with client.stream(
        "POST", "http://localhost:8000/v1/completions",
        json={
            "model": "Qwen/Qwen2.5-7B-Instruct",
            "prompt": "Explain entropy in one paragraph.",
            "stream": True,
            "stream_format": "msgpack",  # Codec opt-in (body, not header)
            "max_tokens": 256,
        },
        headers={
            "Accept-Encoding": "zstd, br, gzip, identity",  # full v0.4.1 stack
            "Codec-Client-Version": "0.4",                   # v0.4 normative
        },
    ) as resp:
        # see step 3
        ...
```

> **Why `client.stream` over `client.post`?** `stream` doesn't buffer the response body. You want each chunk to flow through the decoder as it arrives.

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

`Detokenizer` is stateful and **stream-safe**. It buffers split UTF-8 sequences across `render` calls. Pass `partial=True` while the stream is open; the final call (or any call where you know the stream is done) should be `partial=False` so the buffer flushes.

## Encoding (text to token IDs)

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

The watcher matches reserved control IDs with a single `uint32` compare per token. It never detokenizes. That's the whole point. See [Tool calling](/docs/tool-calling/) for the agentic-loop pattern.

## Negotiating zstd-with-dict

For deployments with pre-trained zstd dictionaries (see [Protocol &raquo; Compression](/docs/protocol/#zstd-is-dict-only)), `codecai` ships small helpers in `codecai.compression`. The pattern: load the dict bytes once, advertise `zstd` in `Accept-Encoding`, validate the server's `Codec-Zstd-Dict` header before decompressing.

```python
from codecai import (
    CodecZstdDictError,
    hash_zstd_dict,
    select_zstd_dict_for_response,
)

# 1. Load whatever dicts you trust, typically fetched from the
#    tokenizer map's zstd_dictionaries[] entry, hash-verified.
with open("qwen2.5-msgpack-v1.dict", "rb") as f:
    msgpack_dict = f.read()
loaded_dicts = {hash_zstd_dict(msgpack_dict): msgpack_dict}

# 2. Send the request with zstd advertised.
async with httpx.AsyncClient() as http:
    async with http.stream(
        "POST", "http://localhost:8000/v1/completions",
        headers={
            "Accept-Encoding": "zstd, br, gzip, identity",
            "Codec-Client-Version": "0.4",
        },
        json={
            "model": "Qwen/Qwen2.5-7B-Instruct",
            "prompt": "Explain entropy.",
            "stream_format": "msgpack",
            "max_tokens": 256,
        },
    ) as resp:

        # 3. Decide how to read the body based on what the server returned.
        try:
            zdict_bytes = select_zstd_dict_for_response(
                resp.headers, loaded_dicts=loaded_dicts,
            )
        except CodecZstdDictError as e:
            # Server used a dict we don't have, fetch it from the map's
            # zstd_dictionaries[] entry whose hash matches, or retry with
            # Accept-Encoding: gzip. Don't try to decompress a guess.
            raise

        if zdict_bytes is None:
            # Not zstd, httpx auto-decompresses gzip/br. Decode normally.
            async for frame in decode_msgpack_stream(resp.aiter_raw()):
                ...
        else:
            # zstd-with-dict, use a streaming zstd decoder seeded with
            # the right dict bytes, then feed its output to the codec
            # frame decoder.
            ...
```

`select_zstd_dict_for_response` returns the matching dict bytes when the response is `Content-Encoding: zstd` and the server's `Codec-Zstd-Dict` header points at a dict you've loaded. Returns `None` when the response isn't zstd (so your normal gzip / identity path stays untouched). Raises `CodecZstdDictError` on any of: missing header on a zstd response, malformed `sha256:` value, hash unknown to your local registry. Wrong-dict zstd produces garbage bytes. Failing fast is the only safe option.

The matching server-side helper in sglang and vLLM is `set_zstd_dict(stream_format, dict_bytes)`. See [sglang &raquo; zstd, with a dict](/docs/sglang/#zstd-with-a-dict).

## Translating across vocabularies

```python
from codecai import Translator

qwen  = await load_map(
    url="https://cdn.jsdelivr.net/gh/wdunn001/codec-maps/maps/qwen/qwen2.json",
    hash="sha256:62c2f94fcbdb9b49d51632314e64aa65894496bc39751cb90866049657a262ad",
)
llama = await load_map(
    url="https://cdn.jsdelivr.net/gh/wdunn001/codec-maps/maps/meta-llama/llama-3.json",
    hash="sha256:1df0d6a894b844712979207a0521c3887026f3dde427fb75b2984307a57d797f",
)

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
- **Use `client.stream`.** With `client.post` the entire response buffers in memory.
- **Reuse `Detokenizer` and `BPETokenizer`** across requests; both are stateless across-stream (the detokenizer's buffer resets at each new stream).
- **Async ergonomics.** Wrap the decode loop in a `try/finally` if you need to clean up. `aiter_raw()` doesn't auto-close.

## See also

- [Tool calling](/docs/tool-calling/)
- [Translator](/docs/translator/)
- [codecai on PyPI](https://pypi.org/project/codecai/)
- [packages/python/ on GitHub](https://github.com/wdunn001/Codec/tree/main/packages/python)
