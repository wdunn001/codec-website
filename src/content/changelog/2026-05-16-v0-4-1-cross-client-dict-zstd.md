---
title: v0.4.1 — cross-client dict-zstd, llama.cpp br+zstd, synthetic protocol bench
date: "2026-05-16"
kind: release
version: v0.4.1
summary: A patch release that closes three correctness gaps the v0.4.0 cross-stack matrix had been silently papering over — the §1 headline conflated protocol efficiency with model-output behaviour, only Python actually decoded dict-zstd, and the bench's unanimity check only inspected wire bytes (not whether anything decoded). All fixed AND defended by regression tests. New synthetic-stream bench is the protocol-only headline; 24/24 wire AND 24/24 decode unanimous across all 6 clients × 3 engines for the first time.
links:
  - label: GitHub Release v0.4.1
    url: https://github.com/wdunn001/Codec/releases/tag/v0.4.1
  - label: CHANGELOG entry
    url: https://github.com/wdunn001/Codec/blob/main/CHANGELOG.md#v041--2026-05-16
  - label: New synthetic-stream bench
    url: https://github.com/wdunn001/Codec/blob/main/packages/bench/results/2026-05-15T20-00-00Z/synthetic/wire.json
  - label: MATRIX.md — 2026-05-15T20-00-00Z
    url: https://github.com/wdunn001/Codec/blob/main/packages/bench/results/2026-05-15T20-00-00Z/MATRIX.md
---

v0.4.1 is wire-additive over v0.4 — every v0.4 client decodes a v0.4.1 server byte-for-byte. The shipped changes are all consumer-side fidelity improvements + a wholesale rewrite of how we measure protocol efficiency vs how we report it.

## The three gaps v0.4.0 was silently masking

**§1 headline conflated protocol with model output.** Same prompt at temperature=0, three engines, three different token sequences (floating-point non-associativity in CUDA reductions + sampler/attention divergence), three different compression ratios. The headline number was reading "Codec sglang at 1,707× / vllm at 137× / llama.cpp at 33×" as though it were measuring the *protocol* — but it was measuring "the protocol × what each engine happened to generate." A new synthetic-stream bench (`packages/bench/scripts/synthetic_wire_bench.py`) now runs known token-ID corpora through Codec's encoder + compression libraries locally — no engine, no model — and that's §1. Engine output moves to §1b with a clear "content-dependent" disclaimer.

**Honest protocol-only range:**

| Token distribution (2K msgpack)  | Best ratio over Codec identity |
|----------------------------------|-------------------------------:|
| Uniform random (worst case)      | **4.8×**                       |
| Comma-dominated (50% one ID)     | 6.6×                           |
| Low entropy (50 unique IDs)      | **16.6×**                      |
| Cyclic period 10 (best case)     | **391.9×**                     |

Versus JSON-SSE identity, multiply by ~10× — so the JSON-SSE→Codec range spans ~50× to ~4,000× depending on what the model decides to generate.

**Only Python actually decoded dict-zstd.** The other 5 clients (TS/Web, .NET, Rust, Java, C) either silently returned the compressed bytes (TS, C) or errored loudly with "Dictionary mismatch" (Rust, Java, .NET). The bench's wire-byte unanimity check missed this because it only verified the clients *received* the same bytes, not that they *decoded* the same tokens. Fixed by adding real dict-zstd support to all 5 missing clients (new `compression.{ts,rs,java,cs,c}` modules + 70+ tests across them, all against a shared cross-client interop fixture captured from a real codec-sglang:v0.4.1 zstd response). Result: **24/24 wire AND 24/24 decode unanimous** on every engine — the first cut where the decode side is verifiable.

**llama.cpp was identity + gzip only.** The TODO was literally in the source. v0.4.1 ships `codec_brotli_streamer` + `codec_zstd_streamer` in the llama.cpp fork, plus a new env-loaded `codec_zstd_dict_registry`, plus the missing `/codec/schema` endpoint. Negotiator now honors spec preference order `zstd > br > gzip > identity` with the dict-gate per `spec/versions/v0.4.md`.

## The brotli regression we caught with the synthetic bench

While running the synthetic numbers, brotli started returning the same `cells per size` table:

```
size  identity  gzip    br     zstd
64    975       226     1159   213   ← brotli INFLATED a 975B stream to 1159B
512   7616      853     9013   1286  ← still inflating
2048  29790     4482    21300  5221  ← finally compressing
```

The `_compress_brotli` helper in both sglang and vllm forks was calling `compressor.flush()` inside the chunk loop. Each flush emits a complete brotli block + header, forfeiting brotli's between-chunk dictionary sharing. Removed the per-chunk flush; brotli now compresses correctly across all stream sizes. The fix landed in lockstep across both forks; new `test_codec_compression.py` (7 tests) guards the regression.

Re-running the post-fix synthetic bench, brotli is now Pareto-front for 32-256 token msgpack streams — beating both gzip and dict-zstd. The README's "Brotli isn't compressing" warning (true for v0.4.0) is gone.

## Bench gate hardening

The release process now refuses to ship a bench with errored cells. `aggregate.py` exits non-zero if any row has a non-empty `error` field, and §2 reports both **wire-unanimous** AND **decode-unanimous** counts (the wire-only check was the loophole that hid the 5/6 dict-zstd silent failures). An `engine-acceptance` pytest (`packages/bench/tests/test_engine_acceptance.py`) runs 9 protocol probes against any candidate engine image — `/codec/schema`, spec-preference-order compression negotiation, `Codec-Zstd-Dict` header presence, detokenize-bypass — *before* the cross-stack bench is invoked. Catches "image was built from a stale Dockerfile" regressions in ~15s instead of via the bench's headline aggregator.

## What's verified end-to-end at v0.4.1

| Bench surface                              | Result                                                    |
|--------------------------------------------|-----------------------------------------------------------|
| Cross-stack matrix (24 cells × 6 clients × 3 engines) | 24/24 wire + 24/24 decode unanimous on every engine |
| §1 synthetic protocol-only                 | 4.8× – 391.9× depending on content compressibility       |
| §1b engine-output (content-dependent)      | sglang 1,707× / vllm 137× / llama.cpp fp16 3,868× @ 2K   |
| Cross-vocab translator (Llama-3 → Qwen-2)  | 15.1× wire @ 2K, bridge CPU within noise                 |
| Agent loop — mock get_weather              | 16.9× wire / 8.8× total latency speedup                  |
| Agent loop — SearXNG (live web)            | 18.0× wire / 1.65× speedup                                |
| Agent loop — MetaMCP (Time MCP)            | 17.0× wire / ~neutral                                     |
| ToolWatcher microbench                     | 481 Mtok/s vs detokenize 18 Mtok/s → 26.7× speedup       |

## What didn't change

- **Wire spec** — v0.4.1 is wire-additive over v0.4. A v0.4 client speaking to a v0.4.1 server sees byte-identical frames. The dict-zstd interop fixes are all on the consumer side.
- **Engine output bytes for the same model** — by construction, v0.4.1 sglang produces the same frames as v0.4.0 sglang for the same prompt; only the v0.4.1 fixes are in the encoder paths.
- **Public API surface** for the 4 already-published clients (npm @codecai/web, web-safety, maps-cli; PyPI codecai; NuGet Codec.Net; crates.io codec-rs) — additive only.

## Publishes

All shipped at 0.4.1 on their respective registries:

- npm: `@codecai/web`, `@codecai/web-safety`, `@codecai/maps-cli`, `@codecai/web-llm`, `@codecai/mcp-leaf`
- PyPI: `codecai`
- crates.io: `codec-rs`
- NuGet: `Codec.Net`
- Docker Hub: all 7 `wdunn001/codec-*` images at `:v0.4.1`

Maven Central publish for `ai.codec:codec` 0.4.1 is deferred — JAR is built + tested locally; revisits at the v0.4.2 cut.

## Filed for v0.5

Two design docs added under `spec/proposals/` while writing v0.4.1:

- **Prompt dialects** — per-concept opportunistic substitution dictionaries (emoji / CJK chars / math symbols / abbreviations) measured per (model, corpus). A third stackable compression layer alongside Codec's framing and dict-zstd wire layers. Token reduction without quality loss because every substitution is individually measured.
- **Content-aware compression selector** — the current `wire-compress` picker uses a size-only heuristic; the v0.4.1 synthetic bench surfaces that the optimal compressor depends on content profile (br wins 32-256 tokens, gzip wins 512, dict-zstd wins 1024+ when content cooperates). Filed as a v0.5 candidate.
