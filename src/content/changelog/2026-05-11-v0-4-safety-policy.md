---
title: v0.4, safety-policy negotiation as a TLS-style capability axis
date: "2026-05-11"
kind: feature
version: v0.4
summary: |
  Codec gains a sixth negotiation axis on the HELLO/READY handshake, a sanitized, hash-anchored `safety_policy` descriptor that lets servers advertise enforcement (categories, actions, classifier family) without leaking operator-internal banned-id lists or thresholds. Adds an optional `@codecai/web-safety` client package (prefilter + classifier registry), full operator-side enforcement in codec-supervisor (logits processor, multi-token matcher, classifier registry with three v1 implementations), and per-language tokenize/detok benchmarks across all six client libs. Wire numbers unchanged from v0.3.x. v0.4 is wire-additive.
links:
  - label: CHANGELOG.md
    url: https://github.com/wdunn001/Codec/blob/main/CHANGELOG.md
  - label: spec/versions/v0.4.md
    url: https://github.com/wdunn001/Codec/blob/main/spec/versions/v0.4.md
  - label: 2026-05-11T00-12-00Z bench matrix
    url: https://github.com/wdunn001/Codec/blob/main/packages/bench/results/2026-05-11T00-12-00Z/MATRIX.md
  - label: docs/RELEASE_CHECKLIST.md
    url: https://github.com/wdunn001/Codec/blob/main/docs/RELEASE_CHECKLIST.md
---

## The wire additions

Three new fields on the existing handshake, all optional / additive:

- **`HELLO.accept_safety_policies`.** Clients declare which policy
  IDs (or `"*"`) they're willing to talk to.
- **`READY.safety_policy_id`** + **`READY.safety_policy_hash`**,
  server declares the sanitized policy it's enforcing, hash-anchored
  so the client can fetch `.well-known/codec/policies/<id>.json`
  out-of-band and verify the bytes against what the server reports.
- **`finish_reason: "policy_violation"`**, a new enum value on the
  streaming completion frame, surfacing when a server-side action
  fires.

A v0.3 client sees an extra string on a known enum, ignores the new
optional fields, and continues working. A v0.4 client talking to a
v0.3 server sees no policy advertised and falls back to "unknown
enforcement". That is exactly the same posture v0.3 had.

## The "publishable descriptor" boundary

The big design call: operators publish a **sanitized** policy
descriptor at `.well-known/codec/policies/<id>.json`, categories,
action types per category, classifier family, but **never**
banned-token-ID lists, classifier thresholds, or model weights.
Disclosing the *shape* of enforcement is fine; disclosing
`["banned_token_id": 81727]` is an enumeration map for attackers.

Hash interop across the six client libs (TS, Python, Rust, .NET,
Java, C) is bit-identical because canonical-bytes JSON uses the
same encoding rule on every stack, 2-space indent, trailing
newline, null-omitted, verified by spot-checks on a canonical
descriptor.

## The optional `@codecai/web-safety` client

- Always-on **prefilter** (vendor regexes for AWS/GCP/GH/OpenAI
  keys, PII with Luhn-gated card numbers, Shannon-entropy catch-all),
  framework-free `SafetyGate` state machine. Catches doomed prompts
  in the browser before they hit the wire.
- **Classifier registry** with two opt-in classifiers: Prompt Guard
  86M (Transformers.js, ~80 MB CPU default tier) and Llama Guard 3
  1B (codec-web-llm, ~1 GB WebGPU opt-in tier). Same 14-category
  Llama Guard taxonomy as the server-side classifier. Policy
  decisions stay symmetric across hosts.

62 tests, no host-framework dependency. Hosts (leet, codec-website,
future clients) implement their own dialog UI on top of the
framework-free `SafetyGate`.

## The operator side, in codec-supervisor

- **Layered enforcement**: prefilter (client) → logits processor
  (server, token-space) → streaming classifier (server, embedding
  or text-space) → per-category action policy
  (`stop` / `redact` / `regenerate` / `flag`).
- `BannedTokenLogitsProcessor`, vLLM-compatible.
- Multi-token banned-pattern matcher: Aho-Corasick over int
  alphabets so multi-token banned strings (slurs, secret-shaped
  patterns) match during generation without per-step regex.
- Delay-k streaming decisioning (Streaming Content Monitor /
  arxiv 2506.09996 pattern).
- Pluggable classifier registry: three v1 implementations
  (Llama Guard 3 1B / ShieldGemma 2B / embedding-space). Each
  classifier has a generator-DI constructor so tests run without
  weights.
- Adversarial defenses: TokenBreak / EchoGram / glitch-token
  helpers.
- Admin REST surface at `/admin/policies/*` + a Vite/React admin
  app for authoring + revision history.
- 159 tests, all classifiers test-without-weights via generator
  injection.

## Tokenizer + BPE corrections (collateral wins this cut)

- **BPE special-token pre-scan** in every encoder
  (`@codecai/web`, `codecai`, `codec-rs`, `Codec.Net`,
  `ai.codec:codec`). Before this fix, `BPETokenizer.encode("<|im_start|>...<|im_end|>")`
  on Qwen-2.5 split chat-template delimiters into 6 byte-level
  tokens each (`<`, `|`, `im`, `_start`, `|`, `>`) in place of
  emitting the single atomic vocab ID. Visible because Qwen-2.5-0.5B
  is small enough that wrong tokenization produces incoherent
  replies.
- **`(?i:...)` desugar** in `@codecai/web/bpe.ts`, GPT-2-family
  pre-tokenizer patterns use the ES2025 RegExp Pattern Modifiers
  inline-flag group that throws on Chrome <125, iOS Safari <18,
  Firefox <132, Node <23. The encoder now rewrites
  `(?i:abc)` → `(?:[aA][bB][cC])` as the third fallback. BPE
  encoding works on every shipped mobile-leaning runtime.
- **`pre_tokenizer_program` runtime port to Rust**, `codec-rs`
  BPE now works against Qwen-2 / Llama-3 / Phi-4 / cl100k_base
  maps for the first time (the `regex` crate doesn't support
  `(?i:...)` or `\s+(?!\S)`).
- **convert-tiktoken merge derivation fix**, the previous
  `max(rank(left), rank(right))` heuristic picked splits that
  aren't reachable via greedy BPE from initial bytes. Vocab tokens
  like `Hello` on o200k_base encoded as `["H", "ello"]` in place of
  `[13225]`. Replaced with Karpathy-style greedy-BPE simulation
  that emits reachable splits. Affected every shipped OpenAI
  tokenizer in codec-maps; now HF-byte-identical.

## Documentation infrastructure

- `spec/PROTOCOL.md` restructured from a 1555-line monolith into a
  95-line navigation index. Per-version snapshots live at
  `spec/versions/v0.{2,3,4}.md` with frozen wire-text blocks plus
  LIVING `## Open questions (v0.X)` sections that evolve across
  releases.
- `docs/RELEASE_CHECKLIST.md` (12 phases), formalises the gate
  between feature work and a published cut. Binding from v0.4
  forward.
- **Versioning policy codified** in `spec/versions/v0.4.md`:
  minor versions are wire-additive only; breaking changes require
  a major bump. This v0.4 cut is the first one audited against
  that rule.
- `CHANGELOG.md` lands at the top level (this entry, basically).

## Bench surface additions

- New per-language tokenize/detokenize micro-bench:
  `packages/demo-*/token_bench.{py,ts,rs,cs,java,c}` +
  `packages/bench/scripts/run-all-token-benches.sh`. Measures
  encode + decode time over a fixed golden corpus per language.
  Output aggregated into `MATRIX.md` §X.
- `aggregate.py.fmt_bytes` now emits explicit `b` (byte) suffix on
  bare numeric values, reviewer feedback after the
  2026-05-09T17-09-35Z run flagged unsuffixed integers as
  confusing.
- Coverage tooling wired across all 9 stacks (first time): c8 for
  npm packages, pytest-cov for Python, cargo-llvm-cov for Rust,
  coverlet for .NET, JaCoCo for Java, gcovr for libcodec.
  Baselines in each `packages/*/COVERAGE.md`.

## Numbers (unchanged, v0.4 is wire-additive)

|  Engine   |   JSON-SSE  | Best Codec   | Reduction  |
|-----------|------------:|-------------:|-----------:|
| llama.cpp |  529.2 KB   | 16.1 KB gzip |     32.8×  |
| sglang    |  485.2 KB   | 291 b zstd   | **1,707×** |
| vllm      |  517.8 KB   | 3,874 b gzip |       137× |

24/24 unanimous on every engine across 6 client languages.
Per-language tokenize/detok throughput (new this release) ranges
from 1.3M tok/s (Java encode) up to 17.3M tok/s (C decode).
[Full matrix](https://github.com/wdunn001/Codec/blob/main/packages/bench/results/2026-05-11T00-12-00Z/MATRIX.md).
