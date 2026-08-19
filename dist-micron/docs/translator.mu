`F6cf`!Cross-vocab (Translator)`!`f

`F999Re-tokenize a stream from one model's vocab to another's, mid-flight, without ever materializing UTF-8.`f

`F999`*Reference`*`f

-

'Translator' is for the case where two models in your pipeline use different vocabs (say, a Qwen-vocab planner upstream and a Llama-vocab executor downstream) and you want them to talk to each other without going through English.

Without Codec, the handoff goes:

`=
Qwen IDs → detokenize → UTF-8 → tokenize as Llama → Llama IDs
`=

That's two extra string round-trips per token, plus all the bytes those strings cost on the wire. With 'Translator':

`=
Qwen IDs → Translator → Llama IDs
`=

One pass. No UTF-8.

>>>How it works

The translator pre-computes a `!byte-level translation table`! between the two vocabs at construction. For each token in the source vocab, it knows the corresponding sequence of one or more tokens in the target vocab. Translation at runtime is a flat lookup, plus a small amount of state for handling tokens that split UTF-8 sequences across boundaries (the same problem 'Detokenizer' solves).

The table only depends on the two maps, so two long-running agents talking back and forth share one translator instance.

>>>Pattern: pipe between two agents

`F999`*code (ts):`*`f
`=
import { Translator, decodeStream, loadMap } from "@codecai/web";

const qwen = await loadMap({
  url:  "https://cdn.jsdelivr.net/gh/wdunn001/codec-maps/maps/qwen/qwen2.json",
  hash: "sha256:887311099cdc09e7022001a01fa1da396750d669b7ed2c242a000b9badd09791",
});
const llama = await loadMap({
  url:  "https://cdn.jsdelivr.net/gh/wdunn001/codec-maps/maps/meta-llama/llama-3.json",
  hash: "sha256:79b707aea8c2b41c2883ec7913b0c4a0c880044ac844d89a9a03e779eb92db04",
});

const tr = new Translator(qwen, llama);

// Upstream agent (Qwen vocab) is producing a Codec stream.
const qwenResp = await fetch(QWEN_SERVER + "/v1/completions", { ... });

for await (const frame of decodeStream(qwenResp.body!, "msgpack")) {
  const llamaIds = tr.translate(frame.ids, { partial: !frame.done });

  // Forward to downstream Llama agent as its prompt or as a streamed tool result.
  await sendToLlama(llamaIds);
}
`=

The same shape in Python ('tr.translate(frame.ids, partial=not frame.done)'), .NET ('tr.Translate(frame.Ids, partial: !frame.Done)'), and via the analogous C API.

>>>What "partial" means

'Translator' is `!stream-safe`!: a UTF-8 sequence that spans two source frames will not produce a malformed target ID. While 'partial = true', the translator buffers any token whose translation depends on the next token. On the final frame ('partial = false' or omitted), the buffer flushes.

This means: in real streaming use, 'tr.translate(frame.ids, partial: !frame.done)' may return `*fewer`* IDs than the input frame (some held back) or `*more`* (some buffered IDs flushed); over the whole stream, the counts work out.

>>>Static translation table

If you don't need streaming (e.g., you're translating a fixed prompt before sending it), you can precompute the table directly:

`F999`*code (ts):`*`f
`=
import { staticTranslationTable } from "@codecai/web";

const table = staticTranslationTable(qwen, llama);
// table is a Map<sourceId, targetId[]>

const qwenIds = qwenTokenizer.encode(prompt);
const llamaIds = qwenIds.flatMap((id) => table.get(id) ?? []);
`=

Faster setup, but you lose stream safety. Use the stateful 'Translator' whenever you're consuming a real model's output stream.

>>>When to reach for it

• `!Multi-vocab agent meshes.`! A planning model produces structured output; a smaller fast executor model consumes it. They have different tokenizers because they're different families. Don't go through UTF-8.
• `!Tool-result splicing.`! A tool returns text; you want it as the next prompt for an agent on a different vocab. Translate once, splice into the prompt IDs.
• `!Vocab migration.`! You're rolling forward from 'qwen2' to 'qwen2.5' and need to bridge requests/responses during the transition window.

>>>When NOT to reach for it

• `!Single-model pipelines.`! If everything speaks the same vocab, you already don't need translation.
• `!Human-readable output.`! If the next consumer is a human, just detokenize.

>>>See also

• `[TypeScript`:/page/codecai/docs/typescript.mu] / `[Python`:/page/codecai/docs/python.mu] / `[.NET`:/page/codecai/docs/dotnet.mu] / `[Rust`:/page/codecai/docs/rust.mu] / `[Java`:/page/codecai/docs/java.mu] walkthroughs, each ends with a Translator section.
• PROTOCOL.md (https://github.com/wdunn001/Codec/blob/main/spec/PROTOCOL.md), the wire spec.

-

`[<< Codec docs index`:/page/codecai/index.mu]

