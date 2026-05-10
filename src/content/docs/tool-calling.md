---
title: Tool calling — ToolWatcher
description: Detect tool-call regions in token-ID streams without detokenizing. ~100× faster than the text path.
section: Reference
order: 1
---

The standard "regex-match `<tool_call>...</tool_call>` in the streaming text" approach has a problem: every chunk that arrives over the wire has to be detokenized to UTF-8 first, which means decoding bytes the model just produced as integers, just to scan them as text, just to dispatch on the result.

`ToolWatcher` skips the detokenization. It matches on the **token IDs** of the delimiters &mdash; a single `uint32` compare per token &mdash; and yields events directly from the binary stream.

## How it works

A tokenizer's special tokens (`<tool_call>`, `</tool_call>`, `<|im_start|>`, etc.) have **reserved IDs** that don't appear in any normal text. When the model emits the start delimiter, exactly one ID flows by; ditto the end delimiter. Watching for those IDs is O(1) per token with an integer comparison.

The text-path equivalent has to: pull bytes off the wire, msgpack-decode the IDs, look up each ID in the vocab, concatenate the bytes, parse them as UTF-8, run a regex against the cumulative text, and only then dispatch. That's a lot of work for every chunk that *isn't* a tool call &mdash; which is most of them.

## The events ToolWatcher yields

```ts
type WatcherEvent =
  | { kind: "passthrough"; ids: Uint32Array }   // normal model output
  | { kind: "captured";    ids: Uint32Array };  // contents of a tool-call region
```

`passthrough` events are the IDs you forward to the user (or to the next agent). `captured` events are the body of a `<tool_call>...</tool_call>` region with the delimiters stripped &mdash; that's what you detokenize and parse.

A region that spans multiple frames produces one `captured` event when the closing delimiter arrives, with all the body IDs concatenated.

## Pattern: stream + dispatch loop

The same shape in every binding. TypeScript:

```ts
import { Detokenizer, ToolWatcher, decodeStream, loadMap } from "@codecai/web";

const map = await loadMap({
  url:  "https://cdn.jsdelivr.net/gh/wdunn001/codec-maps/maps/qwen/qwen2.json",
  hash: "sha256:887311099cdc09e7022001a01fa1da396750d669b7ed2c242a000b9badd09791",
});
const detok = new Detokenizer(map);
const watcher = new ToolWatcher(map, "<tool_call>", "</tool_call>");

const resp = await fetch("http://localhost:8000/v1/completions", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({
    model: "Qwen/Qwen2.5-7B-Instruct",
    prompt: agentPrompt,
    stream_format: "msgpack",
    max_tokens: 1024,
  }),
});

for await (const frame of decodeStream(resp.body!, "msgpack")) {
  for (const ev of watcher.feed(frame.ids)) {
    if (ev.kind === "passthrough") {
      // Forward IDs to the next hop (or detokenize for a human).
      forward(ev.ids);
    } else {
      // ev.kind === "captured" — the tool body.
      const body = detok.render(ev.ids);
      const { tool, args } = JSON.parse(body);   // or your tool-format of choice
      const result = await dispatch(tool, args);
      // Splice result back into the next request.
    }
  }
}
```

Python looks the same with `watcher.feed(frame.ids)` returning a list of events; .NET uses `foreach (var ev in watcher.Feed(...))`; C uses `codec_tool_watcher_feed(...)` writing to a heap-allocated event array.

## When the server pre-segments

If your server runs the [in-server ToolWatcher](/docs/sglang/#server-side-toolwatcher), the server emits Codec frames where tool-call regions are already marked with reserved control IDs. Client-side `ToolWatcher.feed()` still works the same way &mdash; it picks up the server's markers instead of doing the matching itself. Strictly faster, but you don't write different client code.

## Performance

From [RESULTS.md §7](https://github.com/wdunn001/Codec/blob/main/RESULTS.md), `libcodec` C99 on a 1M-token synthetic stream with 5% of tokens inside tool-call regions, 1,024-token chunks:

| Operation | ns / token | Mtok / s |
|---|---:|---:|
| ToolWatcher (uint32 compare)    | **0.61** | 1,648 |
| Detokenize + regex (text path)  |   60.4   |  16.6 |

About **100&times; faster on the hot path**. End-to-end agent benchmarks in [§3–§6 of RESULTS.md](https://github.com/wdunn001/Codec/blob/main/RESULTS.md) show 17–18&times; wire-byte reduction and 20% wall-clock improvement on real two-turn dispatch loops.

## Custom delimiters

`ToolWatcher` takes the delimiter strings; the binding looks up their IDs against the loaded map. You can use any pair of special tokens in your model's vocab, including custom ones in fine-tuned models:

```ts
const watcher = new ToolWatcher(map, "<json_args>", "</json_args>");
```

If the strings don't tokenize to single IDs in your map, the constructor throws &mdash; multi-token delimiters aren't supported (and don't really make sense, since the whole point is one comparison per token).

## See also

- [Server — sglang](/docs/sglang/) &mdash; server-side pre-segmentation.
- [TypeScript](/docs/typescript/) / [Python](/docs/python/) / [.NET](/docs/dotnet/) / [C](/docs/c/) &mdash; ToolWatcher in each binding.
- [bench_watcher.c](https://github.com/wdunn001/Codec/blob/main/packages/c/examples/bench_watcher.c) &mdash; the microbench harness.
