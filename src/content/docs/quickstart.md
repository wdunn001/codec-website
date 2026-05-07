---
title: Quickstart
description: 90 seconds from "never seen Codec" to a streaming binary completion in your terminal.
section: Start
order: 2
---

This is the fastest path. Pick the language you'd like to write the *client* in &mdash; the *server* (sglang or vLLM) speaks Codec on the same `/v1/completions` endpoint it already serves; no special build.

> **Server prerequisites.** You need an LLM server that speaks Codec on its completions endpoint. As of 2026, [sglang](/docs/sglang/) is the easiest path: any nightly with PR #24483 merged accepts `stream_format: "msgpack"` against any model. vLLM support is in flight ([PR #41765](https://github.com/vllm-project/vllm/pulls)).

## TypeScript / Node

```bash
npm install @codecai/web
```

```ts
import { loadMap, Detokenizer, decodeStream } from "@codecai/web";

const map = await loadMap({
  url:  "https://cdn.jsdelivr.net/gh/wdunn001/codec-maps/maps/qwen/qwen2.json",
  hash: "sha256:c73972f7a580...",
});

const resp = await fetch("http://localhost:8000/v1/completions", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({
    model: "Qwen/Qwen2.5-7B-Instruct",
    prompt: "Explain entropy in one paragraph.",
    stream_format: "msgpack",
    max_tokens: 256,
  }),
});

const detok = new Detokenizer(map);
for await (const frame of decodeStream(resp.body!, "msgpack")) {
  process.stdout.write(detok.render(frame.ids, { partial: !frame.done }));
}
```

Full walkthrough: [TypeScript guide](/docs/typescript/).

## Python

```bash
pip install codecai
```

```python
import asyncio, httpx
from codecai import Detokenizer, decode_msgpack_stream, load_map

async def main():
    m = await load_map(
        url="https://cdn.jsdelivr.net/gh/wdunn001/codec-maps/maps/qwen/qwen2.json",
        hash="sha256:c73972f7a580...",
    )
    detok = Detokenizer(m)
    async with httpx.AsyncClient() as client:
        async with client.stream(
            "POST", "http://localhost:8000/v1/completions",
            json={
                "model": "Qwen/Qwen2.5-7B-Instruct",
                "prompt": "Explain entropy in one paragraph.",
                "stream_format": "msgpack",
                "max_tokens": 256,
            },
        ) as resp:
            async for frame in decode_msgpack_stream(resp.aiter_raw()):
                print(detok.render(frame.ids, partial=not frame.done), end="", flush=True)

asyncio.run(main())
```

Full walkthrough: [Python guide](/docs/python/).

## .NET

```bash
dotnet add package Codec.Net
```

```csharp
using System.Net.Http.Json;
using Codec;

var map = await MapLoader.LoadAsync(new LoadOptions {
    Url  = "https://cdn.jsdelivr.net/gh/wdunn001/codec-maps/maps/qwen/qwen2.json",
    Hash = "sha256:c73972f7a580...",
});

using var http = new HttpClient();
using var req = new HttpRequestMessage(HttpMethod.Post, "http://localhost:8000/v1/completions") {
    Content = JsonContent.Create(new {
        model = "Qwen/Qwen2.5-7B-Instruct",
        prompt = "Explain entropy in one paragraph.",
        stream_format = "msgpack",
        max_tokens = 256,
    }),
};
using var resp = await http.SendAsync(req, HttpCompletionOption.ResponseHeadersRead);

var detok = new Detokenizer(map);
await using var body = await resp.Content.ReadAsStreamAsync();
await foreach (var frame in StreamDecoder.DecodeMsgpackStreamAsync(body)) {
    Console.Write(detok.Render(frame.Ids, new DetokenizeOptions { Partial = !frame.Done }));
}
```

Full walkthrough: [.NET guide](/docs/dotnet/).

## C

```cmake
# CMakeLists.txt
include(FetchContent)
FetchContent_Declare(codec
  GIT_REPOSITORY https://github.com/wdunn001/Codec.git
  GIT_TAG        main
  SOURCE_SUBDIR  packages/c
)
FetchContent_MakeAvailable(codec)
target_link_libraries(your_app PRIVATE codec::codec)
```

```c
#include <codec/codec.h>
/* See packages/c/examples/stream_decode.c for an end-to-end runnable program. */
```

Full walkthrough: [C guide](/docs/c/).

---

## What you just did

In every language, the recipe is the same four steps:

1. **Load a vocab map** &mdash; tells your client which tokenizer the server's IDs belong to. Maps are sha256-content-addressed and cached.
2. **POST a completion request** &mdash; identical to your normal `/v1/completions` call, with one extra field: `stream_format: "msgpack"` (or `"protobuf"`).
3. **Decode the binary stream** &mdash; helper functions yield one `CodecFrame` per `{ids, done, finish_reason}`.
4. **Detokenize at the edge** &mdash; only when a human is going to read it. Internal hops keep the IDs.

That's the whole API. The same four-step shape appears in every binding.
