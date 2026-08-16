`c`F38f░████░░███░░████░░█████░░████`f
`c`F38f█░░░░░█░░░█░█░░░█░█░░░░░█░░░░`f
`c`F38f█░░░░░█░░░█░█░░░█░████░░█░░░░`f
`c`F38f█░░░░░█░░░█░█░░░█░█░░░░░█░░░░`f
`c`F38f░████░░███░░████░░█████░░████`f

`c`F999The control plane for AI inference.`f

`a

-

AI inference is burning megawatts of GPU power and datacenter buildout is racing to keep up -- meanwhile your inference stack is paying again at every hop on top of the GPU bill. Models think in tokens, but the rest of the stack speaks text. Every gateway, router, tool dispatcher, and middleware in the path does the same ritual: detokenize the model's IDs to text, encode as UTF-8, wrap in JSON, ship it, parse it, decode UTF-8, re-tokenize back to IDs -- burning CPU, memory, and latency on lossy conversions the AI never asked for, and risking KV-cache corruption when the re-tokenize doesn't round-trip cleanly. Codec is a drop-in upgrade that keeps token IDs as the wire format end-to-end: gateways forward IDs verbatim, tool dispatchers match on raw IDs, cross-model handoffs translate vocabularies in-process. Same model, same prompts, same answers; typically 16x less data on the wire on real agent traffic, up to ~1,700x when the content compresses well -- how big the win is depends on what your AI generates. Plug-in libraries for TypeScript, Python, Rust, Java, .NET, and C work with the AI servers you already use (sglang, vllm, llama.cpp). Your code doesn't change.

-

>>Docs

Codec is a token-native binary transport protocol for AI APIs. Reference implementations, engine integrations, and protocol references, grouped the same way as the live docs sidebar.

>>>Start

`[What is Codec?`:/page/codecai/docs/overview.mu]

`[Quickstart`:/page/codecai/docs/quickstart.mu]

`[Protocol overview`:/page/codecai/docs/protocol.mu]

>>>Frameworks

`[TypeScript / Node — @codecai/web`:/page/codecai/docs/typescript.mu]

`[Python — codecai`:/page/codecai/docs/python.mu]

`[.NET — Codec.Net`:/page/codecai/docs/dotnet.mu]

`[C — libcodec`:/page/codecai/docs/c.mu]

`[Rust — codec-rs`:/page/codecai/docs/rust.mu]

`[Browser safety — @codecai/web-safety`:/page/codecai/docs/web-safety.mu]

`[Java — codec`:/page/codecai/docs/java.mu]

`[HTTP compression picker — @codecai/wire-compress`:/page/codecai/docs/wire-compress.mu]

>>>Server

`[codec-sglang (Docker)`:/page/codecai/docs/codec-sglang.mu]

`[codec-vllm (Docker)`:/page/codecai/docs/codec-vllm.mu]

`[sglang (vanilla)`:/page/codecai/docs/sglang.mu]

`[codec-llamacpp (Docker)`:/page/codecai/docs/codec-llamacpp.mu]

`[codec-metamcp (Docker)`:/page/codecai/docs/codec-metamcp.mu]

`[codec-comfyui (Docker)`:/page/codecai/docs/codec-comfyui.mu]

`[codec-diffusers (Docker)`:/page/codecai/docs/codec-diffusers.mu]

`[codec-leaf (MCP tool authors)`:/page/codecai/docs/codec-leaf.mu]

`[codec-tool-kit (Codec-native tool authors)`:/page/codecai/docs/codec-tool-kit.mu]

>>>Reference

`[Tool calling — ToolWatcher`:/page/codecai/docs/tool-calling.mu]

`[Cross-vocab — Translator`:/page/codecai/docs/translator.mu]

`[Self-hosted discovery — .well-known/codec/`:/page/codecai/docs/discovery.mu]

-

>>Changelog

What's new, newest first.

`[Full changelog (overview)`:/page/codecai/changelog.mu]

`[v0.5.0 — efficiency, observability, and cohort honesty`:/page/codecai/changelog/2026-05-18-v0-5-efficiency-observability.mu]  2026-05-18

`[v0.4.1 — cross-client dict-zstd, llama.cpp br+zstd, synthetic protocol bench`:/page/codecai/changelog/2026-05-16-v0-4-1-cross-client-dict-zstd.mu]  2026-05-16

`[v0.4 — safety-policy negotiation as a TLS-style capability axis`:/page/codecai/changelog/2026-05-11-v0-4-safety-policy.mu]  2026-05-11

`[Cross-stack bench cleanup — 24/24 unanimous on every engine`:/page/codecai/changelog/2026-05-10-cross-stack-bench-clean-rerun.mu]  2026-05-10

`[codec-metamcp v0.3.1 — leaf-mode validator fix; Codec-aware tools 4.2× e2e`:/page/codecai/changelog/2026-05-09-v0-3-1-leaf-mode-validator-fix.mu]  2026-05-09

`[v0.3.2 — leaf-mode bypass observable end-to-end on real MCP traffic`:/page/codecai/changelog/2026-05-09-v0-3-2-leaf-mode-loop-closed.mu]  2026-05-09

`[v0.3 bench numbers from the lab — 3.6× on tools/list, 18× on text streams`:/page/codecai/changelog/2026-05-09-v0-3-bench-numbers-live.mu]  2026-05-09

`[v0.3 latent bench — pipeline math validates byte-for-byte`:/page/codecai/changelog/2026-05-09-v0-3-latent-bench-real-numbers.mu]  2026-05-09

`[v0.3 latent modality — VAE latents on the wire`:/page/codecai/changelog/2026-05-09-v0-3-latent-modality.mu]  2026-05-09

`[Codec-aware MCP gateway`:/page/codecai/changelog/2026-05-09-v0-3-mcp-gateway.mu]  2026-05-09

`[tool_calling block in tokenizer maps`:/page/codecai/changelog/2026-05-09-v0-3-tool-calling-block.mu]  2026-05-09

`[Java, Rust, and .NET clients reach feature parity`:/page/codecai/changelog/2026-05-07-polyglot-clients-parity.mu]  2026-05-07

`[zstd dictionary negotiation via Codec-Zstd-Dict header`:/page/codecai/changelog/2026-05-07-zstd-dict-negotiation.mu]  2026-05-07

-

>>Protocol map

Codec runs on one client/gateway/engine triangle. The wire frame, the per-modality map, and the response headers shift per pathway -- the triangle does not. Four negotiation pathways: text-tokens (v0.2, uint32 token-ID frames), MCP tool-calls with leaf-mode bypass (pre-tokenized results via a pinned tokenizer map), latents (v0.3, VAE latents instead of decoded pixels for image/video diffusion), and safety policies (v0.4, a TLS-style capability axis with hash-anchored policy descriptors). Full diagram and normative spec:

Protocol map (https://codecai.net/protocol-map/)

-

`F999About this mirror: pre-rendered from codecai.net for the quasarke NomadNet node. Prose is unedited, only the markup changed. Images and diagrams are described in text with a citation back to the live site (no image transport over Reticulum).`f

`[<< Node index (The Mild Take)`:/page/index.mu]

