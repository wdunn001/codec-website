---
title: .NET (Codec.Net)
description: ASP.NET / console-friendly binding. .NET 8+, IAsyncEnumerable streams, full nullability, AOT-friendly.
section: Frameworks
order: 3
---

`Codec.Net` is the .NET binding. It targets .NET 8 and newer, ships full nullable annotations, and the streaming API is `IAsyncEnumerable<CodecFrame>`. Everything is `await foreach`-shaped.

## Install

```bash
dotnet add package Codec.Net
```

## The four-step shape

```csharp
using Codec;

// 1. fetch + verify the vocab map
// 2. (and 4.) IDs → text via Detokenizer
// 3. Stream → IAsyncEnumerable<CodecFrame> via StreamDecoder
```

### 1. Load the vocab map

```csharp
var map = await MapLoader.LoadAsync(new LoadOptions {
    Url  = "https://cdn.jsdelivr.net/gh/wdunn001/codec-maps/maps/qwen/qwen2.json",
    Hash = "sha256:62c2f94fcbdb9b49d51632314e64aa65894496bc39751cb90866049657a262ad",
});
```

`MapLoader.LoadAsync` fetches, verifies the hash, and caches by hash for future calls.

### 2. Send a request

```csharp
using System.Net.Http;
using System.Net.Http.Json;

// stream_format lives in the BODY (piggybacks on OpenAI's request schema);
// Accept-Encoding + Codec-Client-Version are the v0.4.1 Codec REQUEST HEADERS.
// See /docs/protocol/#request-vs-response-where-each-codec-knob-lives.
using var http = new HttpClient {
    DefaultRequestHeaders = {
        { "Accept-Encoding",       "zstd, br, gzip, identity" },
        { "Codec-Client-Version",  "0.4" },
    },
};

using var req = new HttpRequestMessage(HttpMethod.Post, "http://localhost:8000/v1/completions") {
    Content = JsonContent.Create(new {
        model = "Qwen/Qwen2.5-7B-Instruct",
        prompt = "Explain entropy in one paragraph.",
        stream = true,
        stream_format = "msgpack",  // Codec opt-in (body, not header)
        max_tokens = 256,
    }),
};

using var resp = await http.SendAsync(req, HttpCompletionOption.ResponseHeadersRead);
resp.EnsureSuccessStatusCode();
```

`HttpCompletionOption.ResponseHeadersRead` is the .NET equivalent of "don't buffer the body". Without it, `HttpClient` will read the entire response into memory before handing it to you.

### 3. Decode the binary stream

```csharp
await using var body = await resp.Content.ReadAsStreamAsync();

await foreach (var frame in StreamDecoder.DecodeMsgpackStreamAsync(body)) {
    // frame.Ids: ReadOnlyMemory<uint>
    // frame.Done: bool
    // frame.FinishReason: string?
}
```

Use `DecodeProtobufStreamAsync` if your server is configured for protobuf.

### 4. Detokenize at the edge

```csharp
var detok = new Detokenizer(map);

await foreach (var frame in StreamDecoder.DecodeMsgpackStreamAsync(body)) {
    var text = detok.Render(frame.Ids, new DetokenizeOptions { Partial = !frame.Done });
    Console.Write(text);
}
```

`Detokenizer` is **stateful**. The same instance persists UTF-8 buffer state across calls so split sequences render correctly. Set `Partial = true` while the stream is open.

## Encoding (text to token IDs)

```csharp
var tok = new BPETokenizer(map);
int[] ids = tok.Encode("System: be concise.\nUser: what's BPE?");

using var req = new HttpRequestMessage(HttpMethod.Post, "http://localhost:8000/v1/completions") {
    Content = JsonContent.Create(new {
        model = "Qwen/Qwen2.5-7B-Instruct",
        prompt = ids,            // int[], server reads as token IDs
        stream_format = "msgpack",
        max_tokens = 256,
    }),
};
```

## Watching for tool calls

```csharp
var watcher = new ToolWatcher(map, "<tool_call>", "</tool_call>");

await foreach (var frame in StreamDecoder.DecodeMsgpackStreamAsync(body)) {
    foreach (var ev in watcher.Feed(frame.Ids)) {
        switch (ev.Kind) {
            case WatcherEventKind.Passthrough:
                Forward(ev.Ids);
                break;
            case WatcherEventKind.Captured:
                var text = detok.Render(ev.Ids);
                var (tool, args) = ParseToolCall(text);
                await Dispatch(tool, args);
                break;
        }
    }
}
```

Single `uint` compare per token, no detokenization on the hot path. See [Tool calling](/docs/tool-calling/).

## Translating across vocabularies

```csharp
var qwen  = await MapLoader.LoadAsync(new LoadOptions {
    Url  = "https://cdn.jsdelivr.net/gh/wdunn001/codec-maps/maps/qwen/qwen2.json",
    Hash = "sha256:62c2f94fcbdb9b49d51632314e64aa65894496bc39751cb90866049657a262ad",
});
var llama = await MapLoader.LoadAsync(new LoadOptions {
    Url  = "https://cdn.jsdelivr.net/gh/wdunn001/codec-maps/maps/meta-llama/llama-3.json",
    Hash = "sha256:1df0d6a894b844712979207a0521c3887026f3dde427fb75b2984307a57d797f",
});

var tr = new Translator(qwen, llama);

await foreach (var frame in StreamDecoder.DecodeMsgpackStreamAsync(qwenBody)) {
    var llamaIds = tr.Translate(frame.Ids, partial: !frame.Done);
    ForwardToLlamaAgent(llamaIds);
}
```

See [Translator](/docs/translator/).

## ASP.NET integration

A typical pattern: an ASP.NET endpoint proxies a Codec stream from an internal model server out to a browser as SSE for a chat UI, doing the detokenization at the edge.

```csharp
app.MapPost("/chat", async (HttpContext ctx, ChatRequest req, IHttpClientFactory http) => {
    ctx.Response.ContentType = "text/event-stream";
    var detok = new Detokenizer(_map);

    using var inner = http.CreateClient();
    using var inboundReq = new HttpRequestMessage(HttpMethod.Post, _modelServer + "/v1/completions") {
        Content = JsonContent.Create(new {
            model = req.Model, prompt = req.Prompt,
            stream_format = "msgpack", max_tokens = req.MaxTokens,
        }),
    };
    using var inbound = await inner.SendAsync(inboundReq, HttpCompletionOption.ResponseHeadersRead);
    await using var inBody = await inbound.Content.ReadAsStreamAsync();

    await foreach (var frame in StreamDecoder.DecodeMsgpackStreamAsync(inBody)) {
        var text = detok.Render(frame.Ids, new DetokenizeOptions { Partial = !frame.Done });
        await ctx.Response.WriteAsync($"data: {JsonSerializer.Serialize(new { text, done = frame.Done })}\n\n");
        await ctx.Response.Body.FlushAsync();
    }
});
```

## Production checklist

- **Pin the map hash.**
- **`HttpCompletionOption.ResponseHeadersRead`**. Without it, `HttpClient` buffers the whole response. Bypasses streaming entirely.
- **Reuse `HttpClient` and `Detokenizer`**. Both are designed for reuse. New `Detokenizer` per stream isn't required, but its buffer should be reset at stream boundaries (call `Reset()` between streams when reusing).
- **Cancellation tokens.** All async APIs accept `CancellationToken`; pass yours through so timeouts and disposal propagate cleanly.

## See also

- [Tool calling](/docs/tool-calling/)
- [Translator](/docs/translator/)
- [Codec.Net on NuGet](https://www.nuget.org/packages/Codec.Net)
- [packages/dotnet/ on GitHub](https://github.com/wdunn001/Codec/tree/main/packages/dotnet)
