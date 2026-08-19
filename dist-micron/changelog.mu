`F6cf`!Codec changelog`!`f

`F999Customer-facing what's-new feed - newest first`f

-

`[v0.5.0 (efficiency, observability, and cohort honesty)`:/page/codecai/changelog/2026-05-18-v0-5-efficiency-observability.mu]  2026-05-18

Wire-additive over v0.4 (v0.4 → v0.5 happy-path bytes identical). Four new opt-in surfaces (delta-varint stream encoding, discoverable Zstandard dictionaries, GPU-side latent quantize, bolt-on tool dispatcher). 11 client artifacts bumped to 0.5.0 across npm, PyPI, NuGet, crates.io, Maven Central. Engine cohort cut to sglang + vLLM + llama.cpp + ComfyUI + diffusers (TGI dropped). 72/72 wire + 72/72 decode unanimous on the cross-stack matrix; numbers byte-identical to v0.4.1, confirming the wire-additive invariant. Upstream PRs filed at sgl-project/sglang#25544 and vllm-project/vllm#42896, both DCO-signed and through bot review.

`[v0.4.1 (cross-client dict-zstd, llama.cpp br+zstd, synthetic protocol bench)`:/page/codecai/changelog/2026-05-16-v0-4-1-cross-client-dict-zstd.mu]  2026-05-16

A patch release that closes three correctness gaps the v0.4.0 cross-stack matrix had been silently papering over. The §1 headline conflated protocol efficiency with model-output behaviour, only Python actually decoded dict-zstd, and the bench's unanimity check only inspected wire bytes (not whether anything decoded). All fixed AND defended by regression tests. New synthetic-stream bench is the protocol-only headline; 24/24 wire AND 24/24 decode unanimous across all 6 clients × 3 engines for the first time.

`[v0.4, safety-policy negotiation as a TLS-style capability axis`:/page/codecai/changelog/2026-05-11-v0-4-safety-policy.mu]  2026-05-11

Codec gains a sixth negotiation axis on the HELLO/READY handshake, a sanitized, hash-anchored \`safety_policy\` descriptor that lets servers advertise enforcement (categories, actions, classifier family) without leaking operator-internal banned-id lists or thresholds. Adds an optional \`@codecai/web-safety\` client package (prefilter + classifier registry), full operator-side enforcement in codec-supervisor (logits processor, multi-token matcher, classifier registry with three v1 implementations), and per-language tokenize/detok benchmarks across all six client libs. Wire numbers unchanged from v0.3.x. v0.4 is wire-additive.


`[Cross-stack bench cleanup, 24/24 unanimous on every engine`:/page/codecai/changelog/2026-05-10-cross-stack-bench-clean-rerun.mu]  2026-05-10

Re-ran the full cross-stack matrix after patching two bench-driver bugs (C/TS token-decode fallback, vllm REPS=1 noise). All three engines × six client languages now produce byte-identical Codec frames per cell, including vllm, which previously read as 0/24 unanimous in the post-mortem.

`[codec-metamcp v0.3.1 (leaf-mode validator fix); Codec-aware tools 4.2× e2e`:/page/codecai/changelog/2026-05-09-v0-3-1-leaf-mode-validator-fix.mu]  2026-05-09

First end-to-end run with codec-time-leaf in a metamcp namespace surfaced (and we fixed) a CallToolResult validator bug that was rejecting all leaf-mode results. Codec-aware tool calls now compress 4.2× through the gateway.

`[v0.3.2, leaf-mode bypass observable end-to-end on real MCP traffic`:/page/codecai/changelog/2026-05-09-v0-3-2-leaf-mode-loop-closed.mu]  2026-05-09

The Codec leaf-mode bypass (the architectural target the entire v0.3 contract was designed for) fires end-to-end. \`[Codec][leaf]\` log line confirms the gateway is a transparent ID pipe; the tokenizer sits at the leaf where it belongs.

`[v0.3 bench numbers from the lab (3.6× on tools/list, 18× on text streams)`:/page/codecai/changelog/2026-05-09-v0-3-bench-numbers-live.mu]  2026-05-09

First end-to-end run of the v0.3 stack against codec-metamcp:v0.3.0 on a real lab box. tools/list collapses to 3.6× over JSON-RPC; text streams hit 18× over JSON-SSE on protobuf framing.

`[v0.3 latent bench, pipeline math validates byte-for-byte`:/page/codecai/changelog/2026-05-09-v0-3-latent-bench-real-numbers.mu]  2026-05-09

First end-to-end latent run against codec-diffusers with real SD-1.5 latents on the wire. The seven-pipeline registry collapses bytes exactly as the spec promises (int4 packs 3.9× over raw, ~5-10× smaller than JPEG).

`[v0.3 latent modality (VAE latents on the wire)`:/page/codecai/changelog/2026-05-09-v0-3-latent-modality.mu]  2026-05-09

Image and video diffusion models now stream VAE latents instead of decoded pixels. 48× smaller wire weight, decode at the leaf.

`[Codec-aware MCP gateway`:/page/codecai/changelog/2026-05-09-v0-3-mcp-gateway.mu]  2026-05-09

Tool authors can now ship pre-tokenized results that bypass the gateway's back-compat shim. ~4.7× wire-byte reduction on real MCP traffic.

`[tool_calling block in tokenizer maps`:/page/codecai/changelog/2026-05-09-v0-3-tool-calling-block.mu]  2026-05-09

Tokenizer maps now carry the model's tool-calling convention. Auto-derived from the chat template, no per-deployment config.

`[Java, Rust, and .NET clients reach feature parity`:/page/codecai/changelog/2026-05-07-polyglot-clients-parity.mu]  2026-05-07

Six client libraries (TypeScript, Python, Java, Rust, .NET, C) are now byte-identical across the cross-stack benchmark matrix. 36 cells × 3 sizes, all green.

`[zstd dictionary negotiation via Codec-Zstd-Dict header`:/page/codecai/changelog/2026-05-07-zstd-dict-negotiation.mu]  2026-05-07

Servers advertise the active zstd dict on the wire; clients fetch it once and decompress every frame against it. Identification by sha256, not URL.

-

`[<< Codec docs index`:/page/codecai/index.mu]

