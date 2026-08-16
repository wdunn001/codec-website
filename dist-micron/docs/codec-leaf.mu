`F6cf`!codec-leaf (MCP tool authors)`!`f

`F999The Codec leaf-mode contract for MCP tool authors. Wrap tool results with token IDs against a pinned tokenizer map, and a Codec-aware gateway forwards them verbatim — no re-tokenization, no KV-cache risk.`f

`F999`*Server`*`f

-

'@codecai/mcp-leaf' is the tool-author surface for the Codec leaf-mode contract. The principle is simple:

• The MCP `!gateway`! (`['codec-metamcp'`:/page/codecai/docs/codec-metamcp.mu]) tokenizes tool results by default — necessary back-compat for legacy MCP servers, but every gateway hop pays the tokenizer cost.
• The MCP `!tool`! knows the tokenizer the receiving model expects. If it does the work once and ships the IDs alongside the original text, the gateway becomes a transparent ID pipe — the cheapest possible hop on the wire.

'codec-leaf' is the smallest change that graduates a tool to that path. Two function calls.

>>>Install

`F999`*code (bash):`*`f
`=
npm install @codecai/mcp-leaf
`=

The package ships TypeScript types and runs in Node, Bun, or Deno. The reference Codec-aware MCP server ('codec-time-leaf' (https://hub.docker.com/r/wdunn001/codec-time-leaf)) is built on top of it.

>>>Quick start (writer side)

`F999`*code (ts):`*`f
`=
import { makeMetaTokenizer, wrapToolCall } from '@codecai/mcp-leaf';

// Once at server startup. Pinned to the tokenizer map your receiving model uses.
const meta = await makeMetaTokenizer({
  mapUrl:  'https://cdn.jsdelivr.net/gh/wdunn001/codec-maps@main/maps/qwen/qwen2.json',
  mapHash: 'sha256:887311099cdc09e7022001a01fa1da396750d669b7ed2c242a000b9badd09791',
});

// In your existing tool handler — whatever you used to return:
const result = {
  content: [{ type: 'text', text: 'It is currently 14:30 UTC.' }],
};

// Wrap it.
return wrapToolCall(result, meta);
`=

The wrapped result keeps every original 'text' block intact and attaches a per-block '_meta['ai.codec/leaf-tokenization']' payload carrying the token IDs:

`F999`*code (jsonc):`*`f
`=
{
  "content": [
    {
      "type": "text",
      "text": "It is currently 14:30 UTC.",
      "_meta": {
        "ai.codec/leaf-tokenization": {
          "map_id": "sha256:887311099cdc…",
          "ids": [2132, 374, 5023, 220, 16, 19, 25, 18, 15, 27269, 13]
        }
      }
    }
  ]
}
`=

Non-Codec-aware clients in the same MCP namespace ignore the '_meta' field per the MCP spec and see the original text exactly as before. No protocol change, no MCP version bump.

>>>>Wire trade-off, measured

Leaf is `!purely additive`! — the IDs ride alongside the text, not in place of it. That means the '_meta' envelope ('map_id' sha256 hex + ids array in JSON) is a fixed ~210-byte cost per text block. On a ~30-character timestamp result it's a wire-loss ('105 B → 316 B', leaf 3× larger); on a 1 KB search result it's a wire-win. The crossover where leaf wire ≤ plain wire sits at `!~300+ characters per text block`!. The consumer-CPU win is unconditional: re-tokenize is O(chars), 'readCodecMeta()' is O(blocks).

Measured against the reference 'codec-time-leaf' (https://hub.docker.com/r/wdunn001/codec-time-leaf) server (20 warm 'get_current_time' calls, qwen/qwen2 map, MCP stdio):

┌────────────────────────────────────────────┬──────────────┬───────────────────┬────────┐
│ Path                                       │ wire (bytes) │ consumer tokenize │ total  │
├────────────────────────────────────────────┼──────────────┼───────────────────┼────────┤
│ plain MCP (consumer re-tokenizes text)     │          105 │          0.052 ms │ 0.5 ms │
│ mcp-leaf (consumer reads ids from '_meta') │          316 │          0.004 ms │ 0.4 ms │
│ `!delta`!                                      │   `!+211 bytes`! │      `!12.4× faster`! │      — │
└────────────────────────────────────────────┴──────────────┴───────────────────┴────────┘

Driver: 'packages/bench/src/leaf-live.ts' (https://github.com/wdunn001/Codec/blob/main/packages/bench/src/leaf-live.ts). Captured to 'packages/bench/results/2026-05-15T20-00-00Z/agent-loop/leaf.txt' (https://github.com/wdunn001/Codec/blob/main/packages/bench/results/2026-05-15T20-00-00Z/agent-loop/leaf.txt). 20/20 integrity: every leaf sample's 'ids' equal 'tokenizer.encode(text)' under the declared 'map_id'.

>>>Reader side

For client code that wants to lift the IDs out symmetrically (and skip `*its`* re-tokenization step):

`F999`*code (ts):`*`f
`=
import { hasCodecMeta, takeIds, readCodecMeta, stripCodecMeta } from '@codecai/mcp-leaf';

if (hasCodecMeta(callToolResult)) {
  const ids = takeIds(callToolResult);
  // Feed `ids` straight into the model — no tokenizer call.
}
`=

'readCodecMeta()' returns the full payload ('{ map_id, ids }'); 'takeIds()' is a shortcut. 'stripCodecMeta()' returns a plain 'CallToolResult' for forwarding to non-Codec-aware downstream clients.

The reader helpers validate that the leaf-tokenization 'map_id' matches your active tokenizer map and throw 'CodecMetaMapMismatchError' on divergence. KV-cache poisoning is a fail-fast condition; never silently accept a mismatched vocab.

>>>What the gateway sees

A Codec-aware gateway like `[codec-metamcp`:/page/codecai/docs/codec-metamcp.mu] detects the leaf-mode result and bypasses its back-compat shim:

`=
[Codec][leaf] downstream tool returned pre-tokenized result for vocab
  887311099cdc… — gateway shim bypassed.
`=

Versus the legacy path:

`=
[Codec][shim] tokenizing tool result for vocab 887311099cdc… —
  leaf-mode MCP server would skip this.
`=

Both log lines fire on the lab today; the bypass counter is exposed for dashboards via 'getShimMetrics()'.

>>>The reference server: 'codec-time-leaf'

'@codecai/codec-time-leaf' (https://www.npmjs.com/package/@codecai/codec-time-leaf) is the canonical Codec-aware MCP server, built on '@codecai/mcp-leaf'. Two trivially-implementable tools ('get_current_time', 'convert_time') chosen so the wire shape is the only variable.

Run it as a stdio MCP server (Claude Desktop / Continue):

`F999`*code (bash):`*`f
`=
npx @codecai/codec-time-leaf
`=

Or the Docker image, dropped into a `[codec-metamcp`:/page/codecai/docs/codec-metamcp.mu] namespace:

`F999`*code (bash):`*`f
`=
docker run --rm -i wdunn001/codec-time-leaf:latest
`=

Wire it into an MCP client config:

`F999`*code (jsonc):`*`f
`=
{
  "mcpServers": {
    "time-leaf": {
      "command": "npx",
      "args": ["-y", "@codecai/codec-time-leaf"],
      "env": {
        "CODEC_MAP_URL":  "https://cdn.jsdelivr.net/gh/wdunn001/codec-maps@main/maps/qwen/qwen2.json",
        "CODEC_MAP_HASH": "sha256:887311099cdc09e7022001a01fa1da396750d669b7ed2c242a000b9badd09791"
      }
    }
  }
}
`=

Without 'CODEC_MAP_URL' the server runs as a plain MCP server and the gateway shim handles tokenization. With it set, the gateway logs flip to '[Codec][leaf]' on every result.

>>>Picking the right map

Your tool's 'mapUrl' + 'mapHash' MUST match the tokenizer the receiving model expects. Three sources:

• `!CDN-hosted reference maps`! at 'wdunn001/codec-maps' (https://github.com/wdunn001/codec-maps) — pre-built for Qwen, Llama, Mistral, etc. Pin the 'sha256' for integrity.
• `!Self-hosted`! — build with 'maps-cli' (https://github.com/wdunn001/Codec/tree/main/packages/maps-cli) from any Hugging Face repo and serve it from your own CDN.
• `!'Codec-Tokenizer-Map' response header`! — if your tool calls upstream Codec-aware engines, lift the negotiated map URL straight from the header.

Mismatched vocab between leaf-tokenized output and the receiving model corrupts the KV cache. The reader-side 'readCodecMeta()' validates this; on the writer side, prefer pinning a single map and refusing to start the server if 'mapHash' doesn't match the fetched bytes.

>>>When NOT to graduate to leaf mode

• `!Tool returns a non-text resource`! (image, audio, binary) — '_meta['ai.codec/leaf-tokenization']' only applies to text content blocks. The gateway shim handles the binary side.
• `!Receiving model's tokenizer is unstable`! — if you don't know the vocab the model will use at call time, leave the gateway to tokenize against its negotiated map.
• `!Tool result is multi-recipient`! — leaf mode is per-vocab. Multi-fanout to different models with different vocabs needs the gateway to re-tokenize per recipient anyway.

In all three cases the legacy path keeps working. Leaf mode is purely additive.

>>>Source & links

• npm: '@codecai/mcp-leaf' (https://www.npmjs.com/package/@codecai/mcp-leaf), '@codecai/codec-time-leaf' (https://www.npmjs.com/package/@codecai/codec-time-leaf).
• Docker: 'wdunn001/codec-time-leaf' (https://hub.docker.com/r/wdunn001/codec-time-leaf).
• Source: 'packages/mcp-leaf' (https://github.com/wdunn001/Codec/tree/main/packages/mcp-leaf) and the reference 'examples/time-server' (https://github.com/wdunn001/Codec/tree/main/packages/mcp-leaf/examples/time-server).
• Spec: PROTOCOL.md § "Tool-call calling conventions in the map" (https://github.com/wdunn001/Codec/blob/main/spec/PROTOCOL.md).

>>>See also

• `[codec-metamcp`:/page/codecai/docs/codec-metamcp.mu] — the Codec-aware MCP gateway that detects the leaf-mode payload and bypasses its shim.
• `[Tool calling`:/page/codecai/docs/tool-calling.mu] — the in-stream 'ToolWatcher' for engine-side tool-call detection (the parallel mechanism on the engine side of the same problem).
• Protocol map (https://codecai.net/protocol-map/) — where leaf-mode sits in the three-pathway picture.

-

`[<< Codec docs index`:/page/codecai/index.mu]

