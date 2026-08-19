`F6cf`!Quickstart`!`f

`F99990 seconds from "never seen Codec" to a streaming binary completion in your terminal.`f

`F999`*Start`*`f

-

This is the fastest path. Pick the language you'd like to write the `*client`* in. The `*server`* (sglang or vLLM) speaks Codec on the same '/v1/completions' endpoint it already serves; no special build.

`F999┃ `!Server prerequisites.`! You need an LLM server that speaks Codec on its completions endpoint. The fastest path is the pre-built `['codec-sglang' Docker image`:/page/codecai/docs/codec-sglang.mu], 'docker run --gpus all -p 8080:8080 wdunn001/codec-sglang:latest' and you're done. vLLM and llama.cpp ship as `['codec-vllm'`:/page/codecai/docs/codec-vllm.mu] and `['codec-llamacpp'`:/page/codecai/docs/codec-llamacpp.mu] on the same image story.`f

>>>TypeScript / Node

`F999`*code (bash):`*`f
`=
npm install @codecai/web
`=

`F999`*code (ts):`*`f
`=
import { loadMap, Detokenizer, decodeStream } from "@codecai/web";

const map = await loadMap({
  url:  "https://cdn.jsdelivr.net/gh/wdunn001/codec-maps/maps/qwen/qwen2.json",
  hash: "sha256:887311099cdc09e7022001a01fa1da396750d669b7ed2c242a000b9badd09791",
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
`=

Full walkthrough: `[TypeScript guide`:/page/codecai/docs/typescript.mu].

>>>Python

`F999`*code (bash):`*`f
`=
pip install codecai
`=

`F999`*code (python):`*`f
`=
import asyncio, httpx
from codecai import Detokenizer, decode_msgpack_stream, load_map

async def main():
    m = await load_map(
        url="https://cdn.jsdelivr.net/gh/wdunn001/codec-maps/maps/qwen/qwen2.json",
        hash="sha256:887311099cdc09e7022001a01fa1da396750d669b7ed2c242a000b9badd09791",
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
`=

Full walkthrough: `[Python guide`:/page/codecai/docs/python.mu].

>>>.NET

`F999`*code (bash):`*`f
`=
dotnet add package Codec.Net
`=

`F999`*code (csharp):`*`f
`=
using System.Net.Http.Json;
using Codec;

var map = await MapLoader.LoadAsync(new LoadOptions {
    Url  = "https://cdn.jsdelivr.net/gh/wdunn001/codec-maps/maps/qwen/qwen2.json",
    Hash = "sha256:887311099cdc09e7022001a01fa1da396750d669b7ed2c242a000b9badd09791",
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
`=

Full walkthrough: `[.NET guide`:/page/codecai/docs/dotnet.mu].

>>>C

`F999`*code (cmake):`*`f
`=
# CMakeLists.txt
include(FetchContent)
FetchContent_Declare(codec
  GIT_REPOSITORY https://github.com/wdunn001/Codec.git
  GIT_TAG        main
  SOURCE_SUBDIR  packages/c
)
FetchContent_MakeAvailable(codec)
target_link_libraries(your_app PRIVATE codec::codec)
`=

`F999`*code (c):`*`f
`=
#include <codec/codec.h>
/* See packages/c/examples/stream_decode.c for an end-to-end runnable program. */
`=

Full walkthrough: `[C guide`:/page/codecai/docs/c.mu].

-

>>>What you just did

In every language, the recipe is the same four steps:

1. `!Load a vocab map`!, which tells your client which tokenizer the server's IDs belong to. Maps are sha256-content-addressed and cached.
2. `!POST a completion request`!, identical to your normal '/v1/completions' call, with one extra field: 'stream_format: "msgpack"' (or '"protobuf"').
3. `!Decode the binary stream.`! Helper functions yield one 'CodecFrame' per '{ids, done, finish_reason}'.
4. `!Detokenize at the edge`!, only when a human is going to read it. Internal hops keep the IDs.

That's the whole API. The same four-step shape appears in every binding.

-

`[<< Codec docs index`:/page/codecai/index.mu]

