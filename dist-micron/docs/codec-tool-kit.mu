`F6cf`!codec-tool-kit (Codec-native tool authors)`!`f

`F999SDK for building Codec-native bolt-on tools. Pre-cache the tokenizer at build time, hashtable-lookup at runtime. The gateway stays a pure token router and tools live in their own repos.`f

`F999`*Server`*`f

-

'@codecai/tool-kit' is the SDK for authoring net-new Codec-native tools. `!Tools should be bolt-ons`!: independently versioned, deployed, and hosted by their author, but speak token IDs natively when the model is one they've pre-built a cache for.

The architectural premise: every modern AI tool call pays 'detokenize → JSON → tool → JSON → re-tokenize' on the round-trip. Most of that work is repeated thousands of times for the same response fragments ('"It is currently "', '" UTC."', '"°F"', common error messages). This SDK lets a tool author tokenize those fragments `!once at build time`!, ship the cached IDs, and pay nothing on the hot path.

>>>Why this exists alongside `[codec-leaf`:/page/codecai/docs/codec-leaf.mu]

Two SDKs, two scopes:

┌──────────────┬───────────────────────┬───────────────────────────────────────────────────────┐
│              │ '@codecai/mcp-leaf'   │ '@codecai/tool-kit'                                   │
├──────────────┼───────────────────────┼───────────────────────────────────────────────────────┤
│ `!Use when`!     │ you have an existing  │ you're building a new tool from scratch               │
│              │ MCP server            │                                                       │
│ `!What it does`! │ wraps                 │ full bolt-on contract (manifest + precache + runtime) │
│              │ 'CallToolResult' with │                                                       │
│              │ per-block '_meta'     │                                                       │
│              │ token IDs             │                                                       │
│ `!Tokenization`! │ at MCP-tool runtime   │ at build time, ship the cache file                    │
│              │ against a pinned map  │                                                       │
│ `!Wire`!         │ MCP JSON-RPC +        │ binary bolt-on (gateway ↔ tool over msgpack/protobuf) │
│              │ leaf-meta payload     │                                                       │
│ `!Use case`!     │ upgrade existing MCP  │ author Codec-first tools, host independently          │
│              │ servers in-place      │                                                       │
└──────────────┴───────────────────────┴───────────────────────────────────────────────────────┘

Both are valid; they're complementary. Most real deployments will use both.

>>>Install

`F999`*code (bash):`*`f
`=
npm install @codecai/tool-kit
`=

Zero runtime dependencies. ~6 KB minified. Works in Node, Bun, Deno, and (for the runtime API) browsers.

>>>The three pieces

A bolt-on tool has three artifacts:

>>>>1. 'manifest.json' (the contract)

`F999`*code (json):`*`f
`=
{
  "schema": "1",
  "name": "get_current_time",
  "version": "0.4.1",
  "description": "Return the current UTC time.",
  "argumentsSchema": {
    "type": "object",
    "properties": {
      "format": { "type": "string", "enum": ["iso", "human"] }
    }
  },
  "models": [
    {
      "modelId": "Qwen/Qwen2.5-0.5B-Instruct",
      "tokenizerHash": "sha256:887311099cdc09e7022001a01fa1da396750d669b7ed2c242a000b9badd09791",
      "cacheFile": "cache/qwen25-0.5b-instruct.json"
    }
  ]
}
`=

The gateway reads this once at registration to verify the tool's model bindings match what's loaded.

>>>>2. 'build-cache.ts' (pre-cache at build time)

`F999`*code (ts):`*`f
`=
import { precache } from '@codecai/tool-kit/precache';
import { AutoTokenizer } from '@huggingface/transformers';

const tok = await AutoTokenizer.from_pretrained('Qwen/Qwen2.5-0.5B-Instruct');
const tokenizer = {
  encode: (text: string) => tok.encode(text),
  hash:   () => 'sha256:' + sha256OfTokenizerFile(),
};

const cache = precache({
  fragments: [
    { id: 'human-prefix', kind: 'static',   text: 'It is currently ' },
    { id: 'human-suffix', kind: 'static',   text: ' UTC.' },
    { id: 'iso-line',     kind: 'template', text: '{date}T{time}Z' },
    { id: 'err-bad-fmt',  kind: 'static',   text: 'Error: format must be "iso" or "human".' },
  ],
  tokenizer,
});

writeFileSync('cache/qwen25-0.5b-instruct.json', JSON.stringify(cache));
`=

Runs once at build time, against each model in the manifest. The cache file is the shipped artifact.

>>>>3. 'src/index.ts' (runtime)

`F999`*code (ts):`*`f
`=
import { findBinding, validateManifest } from '@codecai/tool-kit';
import { renderTemplate, verifyCache } from '@codecai/tool-kit/precache';
import manifest from '../manifest.json' assert { type: 'json' };
import cache from '../cache/qwen25-0.5b-instruct.json' assert { type: 'json' };

validateManifest(manifest);
const binding = findBinding(manifest, process.env.CODEC_MODEL_ID!);
if (!verifyCache(cache, binding.tokenizerHash)) {
  throw new Error('cache stale; rebuild');
}

export function handleCall(args: { format?: 'iso' | 'human' }) {
  const now = new Date();
  const iso = now.toISOString();

  if (args.format === 'human') {
    return renderTemplate(cache.fragments['human-line'], {
      time: iso.slice(11, 19),
    }, slotTokenizer);
  }

  return renderTemplate(cache.fragments['iso-line'], {
    date: iso.slice(0, 10),
    time: iso.slice(11, 19),
  }, slotTokenizer);
}
`=

The hot path is a hashtable lookup + slot-only tokenization (the only runtime tokenizer cost, and it only sees ~15-char slot values). Static fragments are pure memcpy.

>>>What's happening on a call, end-to-end

1. The model emits '<tool_call>{"name":"get_current_time","arguments":{"format":"iso"}}</tool_call>' between its control tokens.
2. The gateway's `['ToolWatcher'`:/page/codecai/docs/tool-calling.mu] matches the control tokens (one 32-bit compare per token, `!no detokenize`!) and routes the argument IDs to your tool.
3. Your tool reads its cache, picks the right template entry, fills the slots, returns response token IDs.
4. The gateway memcpys those IDs back into the model's generation context. The model continues.

`!No JSON envelope serialized, parsed, detokenized, or re-tokenized anywhere in this loop.`! That's the whole point of the bolt-on architecture.

>>>Reference: 'codec-time-tool'

The canonical demo lives at 'packages/codec-tool-kit/examples/time-tool/' (https://github.com/wdunn001/Codec/tree/main/packages/codec-tool-kit/examples/time-tool) and ships on npm as '@codecai/codec-time-tool' (https://www.npmjs.com/package/@codecai/codec-time-tool). Build cache + runtime + tests + manifest, all runnable end-to-end:

`F999`*code (bash):`*`f
`=
cd packages/codec-tool-kit/examples/time-tool
npm run build:cache    # pre-build the token cache
npm run build          # compile the runtime
node dist/index.js iso
# → model:       Qwen/Qwen2.5-0.5B-Instruct
# → format:      iso
# → response IDs (5): [12345, 67890, ...]
`=

>>>Why bolt-ons (and not in-process)

An earlier sketch had the gateway dispatch tools in-process. Three reasons that didn't survive:

1. `!Modularity.`! Tools want their own release cadence, security review, dependencies, and deploy surface. Locking them into the inference server forces every tool change into a server release.
2. `!Independent hosting.`! A team that builds a Codec-native search tool wants to host it in their own repo, on their own infra, with their own SLOs. The gateway only needs the manifest URL.
3. `!Pre-cached tokenization belongs at the tool, not the gateway.`! Every tool knows its own response shape better than any gateway can. Putting the cache in the tool means each tool ships `*exactly the fragments it emits`*, no central dictionary to maintain, no cross-tool coupling.

The wire savings are the same as in-process dispatch. The latency win is one extra hop (tool ↔ gateway, typically a unix socket or LAN RTT of single-digit ms), worth it for the operational decoupling.

>>>Source & links

• npm: '@codecai/tool-kit' (https://www.npmjs.com/package/@codecai/tool-kit), '@codecai/codec-time-tool' (https://www.npmjs.com/package/@codecai/codec-time-tool) (reference)
• Source: 'packages/codec-tool-kit' (https://github.com/wdunn001/Codec/tree/main/packages/codec-tool-kit) (SDK), 'examples/time-tool' (https://github.com/wdunn001/Codec/tree/main/packages/codec-tool-kit/examples/time-tool) (reference)
• Spec: PROTOCOL.md § "Tool-call calling conventions in the map" (https://github.com/wdunn001/Codec/blob/main/spec/PROTOCOL.md)

>>>See also

• `[codec-leaf`:/page/codecai/docs/codec-leaf.mu], companion SDK for `*existing`* MCP servers
• `[codec-metamcp`:/page/codecai/docs/codec-metamcp.mu], Codec-aware MCP gateway that dispatches both leaf-mode results and bolt-on tools
• `[Tool calling`:/page/codecai/docs/tool-calling.mu], in-stream 'ToolWatcher' for engine-side tool-call detection
• Protocol map (https://codecai.net/protocol-map/), where tool-kit sits in the three-pathway picture

-

`[<< Codec docs index`:/page/codecai/index.mu]

