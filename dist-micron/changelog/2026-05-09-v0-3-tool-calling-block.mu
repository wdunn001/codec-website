`F6cf`!tool_calling block in tokenizer maps`!`f

`F9992026-05-09 - v0.3.0 - improvement`f

-

Tokenizer maps now carry the model's tool-calling convention. Auto-derived from the chat template — no per-deployment config.

-

Tokenizer maps now carry an optional 'tool_calling' block describing how each model packages tool calls (markers, args format, result format) — no more out-of-band registry of "qwen2.5 uses '<tool_call>' and JSON args; llama3 uses '<|python_tag|>' and python_args."

'@codecai/maps-cli' (https://www.npmjs.com/package/@codecai/maps-cli) auto-derives the block from each model's 'tokenizer_config.json' chat template; the 70 maps in the codec-maps registry (https://github.com/wdunn001/codec-maps) regenerate with the block populated.

Every polyglot client — TypeScript, Python, Rust, Java, .NET, C — now exposes the field, with full validation that marker names exist as keys in the parent map's 'special_tokens' table.

-

>>Links

GitHub release v0.3.0 (https://github.com/wdunn001/Codec/releases/tag/v0.3.0)

PROTOCOL.md § Tool-call calling conventions (https://github.com/wdunn001/Codec/blob/main/spec/PROTOCOL.md)

tokenizer-map.schema.json (https://github.com/wdunn001/Codec/blob/main/spec/tokenizer-map.schema.json)

-

`[<< Full changelog`:/page/codecai/changelog.mu]

`[<< Codec docs index`:/page/codecai/index.mu]

