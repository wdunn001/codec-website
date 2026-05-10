---
title: v0.3 bench numbers from the lab — 3.6× on tools/list, 18× on text streams
date: "2026-05-09"
kind: improvement
version: v0.3.0
summary: First end-to-end run of the v0.3 stack against codec-metamcp:v0.3.0 on a real lab box. tools/list collapses to 3.6× over JSON-RPC; text streams hit 18× over JSON-SSE on protobuf framing.
links:
  - label: GitHub release v0.3.0
    url: https://github.com/wdunn001/codec-supervisor/releases/tag/v0.3.0
  - label: MCP-live results — 2026-05-09T09-26-54Z
    url: https://github.com/wdunn001/Codec/tree/main/packages/bench/results/2026-05-09T09-26-54Z/mcp
  - label: Bench methodology — SCHEMA.md
    url: https://github.com/wdunn001/Codec/blob/main/packages/bench/methodology/SCHEMA.md
---

The v0.3 release shipped to a real lab today (vinez@192.168.1.88, 2× RTX 3090) and the bench numbers landed.

**MCP gateway** — `codec-metamcp:v0.3.0` against a 38-tool namespace (Playwright, Calculator, Sequential-Thinking, Time, YouTube-Transcripts, Memory). The headline `tools/list` call:

| Variant                   | Wire bytes | vs JSON-RPC |
|---------------------------|-----------:|------------:|
| `json` (baseline)         |    20.7 KB |        1.0× |
| `msgpack-both+gzip`       |     5.7 KB |    **3.6×** |

**Text streams** — `codec-sglang` running Qwen2.5-0.5B at 274 tokens:

| Encoder    | Wire bytes | B/token | vs JSON-SSE |
|------------|-----------:|--------:|------------:|
| JSON-SSE   |    53.1 KB |     198 |        1.0× |
| Codec msgpack |  4.0 KB |    15.1 |   **13.2×** |
| Codec protobuf | 2.9 KB |    11.0 |   **18.0×** |

The leaf-mode bypass (variant 5 of the MCP-live matrix — `msgpack-both+gzip+map` with [`codec-time-leaf`](https://hub.docker.com/r/wdunn001/codec-time-leaf) in-namespace) is wired end-to-end, with the gateway emitting the `[Codec][leaf]` log line on every Codec-aware tool call.
