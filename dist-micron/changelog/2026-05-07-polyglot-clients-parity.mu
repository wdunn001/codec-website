`F6cf`!Java, Rust, and .NET clients reach feature parity`!`f

`F9992026-05-07 - feature`f

-

Six client libraries (TypeScript, Python, Java, Rust, .NET, C) are now byte-identical across the cross-stack benchmark matrix. 36 cells × 3 sizes, all green.

-

The Codec polyglot client matrix is feature-complete. Every client (TypeScript via '@codecai/web' (https://www.npmjs.com/package/@codecai/web), Python via 'codecai' (https://pypi.org/project/codecai/), Java (https://github.com/wdunn001/Codec/tree/main/packages/java), Rust (https://crates.io/crates/codec-rs), .NET (https://www.nuget.org/packages/Codec.Net), and C (https://github.com/wdunn001/Codec/tree/main/packages/c)) ships:

• Frame decoder (msgpack + protobuf)
• Detokenizer (byte_level + metaspace + byte_fallback)
• BPETokenizer (deterministic, bit-identical to HuggingFace's reference)
• ToolWatcher (region detection without decoding)
• Translator (cross-vocab agent handoff)
• MapLoader (sha256-verified, well-known discovery)

The cross-stack benchmark matrix runs all six clients against all three text engines (sglang, vLLM, llama.cpp) at three prompt sizes — `!6 × 3 × 3 = 54 cells`!, all byte-identical. A single tokenizer-map registry; one wire shape; six languages.

-

>>Links

GitHub release v0.2.4 (https://github.com/wdunn001/Codec/releases/tag/v0.2.4)

Cross-stack benchmark matrix (https://github.com/wdunn001/Codec/blob/main/RESULTS.md)

-

`[<< Full changelog`:/page/codecai/changelog.mu]

`[<< Codec docs index`:/page/codecai/index.mu]

