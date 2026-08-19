`F6cf`!TypeScript / Node (@codecai/web)`!`f

`F999The canonical reference implementation. Install, decode a stream, encode a request, watch for tool calls, translate across vocabs.`f

`F999`*Frameworks`*`f

-

'@codecai/web' is the reference TypeScript binding. It runs in modern browsers, Node 20+, and Bun without polyfills. The package ships ESM, the public API is fully typed, and the build output is tree-shakable. If you only use the decoder, you don't pay for the encoder.

>>>Install

`F999`*code (bash):`*`f
`=
npm install @codecai/web
# or pnpm / bun / yarn, same thing
`=

>>>The four-step shape

Every Codec client in every language follows the same shape. In TypeScript:

`F999`*code (ts):`*`f
`=
import {
  loadMap,         // 1. fetch + verify the vocab map
  Detokenizer,     // 2. (and 4.) IDs → text
  decodeStream,    // 3. binary stream → frames
} from "@codecai/web";
`=

>>>>1. Load the vocab map

`F999`*code (ts):`*`f
`=
const map = await loadMap({
  url:  "https://cdn.jsdelivr.net/gh/wdunn001/codec-maps/maps/qwen/qwen2.json",
  hash: "sha256:887311099cdc09e7022001a01fa1da396750d669b7ed2c242a000b9badd09791",
});
`=

'loadMap' does three things:

• Fetches the URL.
• Verifies the bytes against the supplied 'hash' (mismatch throws; this is your supply-chain check).
• Caches the parsed map by hash so subsequent loads are free.

codec-maps (https://github.com/wdunn001/codec-maps) ships pre-generated maps for a starter set (Llama, Qwen, Mistral, Phi, Gemma, DeepSeek, etc.) with hashes pinned in its README. For anything not in that list (a fine-tune, a private model, a brand-new release), install '@codecai/maps-cli' (https://www.npmjs.com/package/@codecai/maps-cli) and run 'codec-maps generate <tokenizer.json>' to produce your own map locally. Same format, same 'loadMap' call.

If the vendor publishes their own map under `['/.well-known/codec/'`:/page/codecai/docs/discovery.mu], you can skip the URL/hash entirely and resolve from '(origin, id)':

`F999`*code (ts):`*`f
`=
import { discoverMap } from "@codecai/web/discover";
const map = await discoverMap({ origin: "https://example.com", id: "qwen2" });
`=

>>>>2. Send a request

A Codec request is `!a normal '/v1/completions' POST with one extra body field`! ('stream_format') `!and two Codec request HEADERS`!: 'Accept-Encoding' (compression menu) + 'Codec-Client-Version' (capability advertisement, v0.4 normative). The server reads 'stream_format' from the body and switches its response from JSON-SSE to binary frames; it reads 'Accept-Encoding' to pick the smallest valid encoding per spec preference 'zstd > br > gzip > identity'. See `[Protocol » Request vs response`:/page/codecai/docs/protocol.mu] for why 'stream_format' lives in the body rather than as a 'Codec-Stream-Format' header (short answer: piggybacks on OpenAI's request schema so the patch slots into upstream engines without forking the request validator).

`F999`*code (ts):`*`f
`=
const resp = await fetch("http://localhost:8000/v1/completions", {
  method: "POST",
  headers: {
    "Content-Type":         "application/json",
    "Accept-Encoding":      "zstd, br, gzip, identity", // full v0.4.1 stack
    "Codec-Client-Version": "0.4",                       // v0.4 normative
  },
  body: JSON.stringify({
    model:         "Qwen/Qwen2.5-7B-Instruct",
    prompt:        "Explain entropy in one paragraph.",
    stream:        true,
    stream_format: "msgpack",   // Codec opt-in (body, not header)
    max_tokens:    256,
  }),
});
`=

The server's response will carry 'Codec-Tokenizer-Map', 'Codec-Zstd-Dict' (when 'Content-Encoding: zstd'), and v0.4 'Codec-Safety-Policy-{Id,Hash}' headers. Read those to verify the wire before decoding ('Codec-Tokenizer-Map' hash MUST match your loaded map; mismatch is a fail-fast condition).

`F999┃ `!Why msgpack over protobuf?`! Both work and produce identical semantics. Pick `!msgpack`! if you want zero schema toolchain. Pick `!protobuf`! if you already have 'protoc' set up or you need stricter typing across polyglot teams. Performance is within noise; the wire bytes match within 1%.`f

>>>>3. Decode the binary stream

`F999`*code (ts):`*`f
`=
import { decodeStream } from "@codecai/web";

if (!resp.ok || !resp.body) throw new Error(`HTTP ${resp.status}`);

for await (const frame of decodeStream(resp.body, "msgpack")) {
  // frame.ids: Uint32Array
  // frame.done: boolean
  // frame.finish_reason?: "stop" | "length" | ...
}
`=

'decodeStream' returns an 'AsyncIterable<CodecFrame>'. It owns the 'ReadableStream' lock; let it run to completion or call '.return()' on the iterator if you bail early.

>>>>4. Detokenize at the edge

`F999`*code (ts):`*`f
`=
const detok = new Detokenizer(map);

for await (const frame of decodeStream(resp.body!, "msgpack")) {
  const text = detok.render(frame.ids, { partial: !frame.done });
  process.stdout.write(text);
}
`=

'Detokenizer' is `!stateful`!. It buffers UTF-8 fragments across calls so a multi-byte character split across two frames renders correctly. Pass '{ partial: true }' while the stream is open and '{ partial: false }' (or omit) on the final flush; the partial flag tells the detokenizer to hold incomplete bytes back until the next call.

>>>Encoding (sending IDs, not text)

If you already have token IDs (for example, the `*previous`* response in an agent loop), skip the server's tokenizer:

`F999`*code (ts):`*`f
`=
import { BPETokenizer } from "@codecai/web";

const tokenizer = new BPETokenizer(map);
const ids = tokenizer.encode("System: be concise.\nUser: what's BPE?");

const resp = await fetch("http://localhost:8000/v1/completions", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({
    model: "Qwen/Qwen2.5-7B-Instruct",
    prompt: Array.from(ids),  // uint32[], the prompt is now token IDs
    stream_format: "msgpack",
    max_tokens: 256,
  }),
});
`=

'BPETokenizer.encode()' is bit-identical to the upstream model's tokenizer (verified across all reference bindings). If the server's BPE produces different IDs from yours, open an issue (https://github.com/wdunn001/Codec/issues). The map is wrong.

>>>Watching for tool calls

`F999`*code (ts):`*`f
`=
import { ToolWatcher } from "@codecai/web";

const watcher = new ToolWatcher(map, "<tool_call>", "</tool_call>");

for await (const frame of decodeStream(resp.body!, "msgpack")) {
  for (const ev of watcher.feed(frame.ids)) {
    if (ev.kind === "passthrough") {
      // Stream these IDs to the user / next agent
      forward(ev.ids);
    } else {
      // ev.kind === "captured", these are the tool-call body
      const text = detok.render(ev.ids);
      const { tool, args } = parseToolCall(text);
      dispatch(tool, args);
    }
  }
}
`=

ToolWatcher does its work with a single 'uint32' compare per token. It does `!not`! detokenize. On a 1 M-token stream the v0.4.1 lab measurement on EPYC 8124P + gcc:13 is `!2.08 ms`! (481 Mtok/s) vs `!55.42 ms`! (18 Mtok/s) for detokenize+regex, `!26.7× faster`! on that host. The speedup ratio stays in ToolWatcher's favour by ~26-100× depending on host; see `[Benchmarks`:/page/codecai/index.mu].

Full reference: `[Tool calling`:/page/codecai/docs/tool-calling.mu].

>>>Translating across vocabularies

`F999`*code (ts):`*`f
`=
import { Translator } from "@codecai/web";

const qwen = await loadMap({
  url:  "https://cdn.jsdelivr.net/gh/wdunn001/codec-maps/maps/qwen/qwen2.json",
  hash: "sha256:887311099cdc09e7022001a01fa1da396750d669b7ed2c242a000b9badd09791",
});
const llama = await loadMap({
  url:  "https://cdn.jsdelivr.net/gh/wdunn001/codec-maps/maps/meta-llama/llama-3.json",
  hash: "sha256:79b707aea8c2b41c2883ec7913b0c4a0c880044ac844d89a9a03e779eb92db04",
});

const tr = new Translator(qwen, llama);

for await (const frame of decodeStream(qwenResp.body!, "msgpack")) {
  const llamaIds = tr.translate(frame.ids, { partial: !frame.done });
  forwardToLlamaAgent(llamaIds);
}
`=

The translator goes IDs → IDs without ever materializing UTF-8. It handles byte-level boundaries the same way 'Detokenizer' does, so you can stream it.

Full reference: `[Translator`:/page/codecai/docs/translator.mu].

>>>Production checklist

• `!Pin the map hash.`! Never call 'loadMap({ url, hash: undefined })'. The hash is the supply-chain seal.
• `!Set 'Accept-Encoding: gzip, identity'.`! Streaming-safe and ~5× smaller than identity. zstd is supported but only when the server has a pre-trained dictionary loaded for the request. See `[Protocol » Compression`:/page/codecai/docs/protocol.mu]. Without a dict, advertising 'zstd' is a no-op (server falls through to gzip).
• `!Reuse 'Detokenizer' and 'Tokenizer' instances`! across requests. Both are reusable; only 'decodeStream' is per-response.
• `!Detokenize at the edge.`! If you're forwarding the stream to another agent or to a server-side tool dispatcher, leave the IDs as IDs.

>>>See also

• `[Browser safety`:/page/codecai/docs/web-safety.mu], the optional '@codecai/web-safety' sibling. Catches secrets, PII, jailbreak templates, destructive commands, and host-blocked patterns before the prompt reaches the wire. New in v0.4.
• `[Tool calling`:/page/codecai/docs/tool-calling.mu], deeper dive on 'ToolWatcher'.
• `[Translator`:/page/codecai/docs/translator.mu], cross-vocab handoff details.
• @codecai/web on npm (https://www.npmjs.com/package/@codecai/web), the package readme has additional examples.
• packages/web/ on GitHub (https://github.com/wdunn001/Codec/tree/main/packages/web), source.

-

`[<< Codec docs index`:/page/codecai/index.mu]

