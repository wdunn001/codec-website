---
title: codec-metamcp v0.3.1 (leaf-mode validator fix); Codec-aware tools 4.2× e2e
date: "2026-05-09"
kind: fix
version: v0.3.1
summary: First end-to-end run with codec-time-leaf in a metamcp namespace surfaced (and we fixed) a CallToolResult validator bug that was rejecting all leaf-mode results. Codec-aware tool calls now compress 4.2× through the gateway.
links:
  - label: GitHub release v0.3.1
    url: https://github.com/wdunn001/Codec/releases/tag/v0.3.1
  - label: 2026-05-09T11-10-48Z bench results
    url: https://github.com/wdunn001/Codec/tree/main/packages/bench/results/2026-05-09T11-10-48Z/mcp
  - label: metamcp validator-fix commit
    url: https://github.com/wdunn001/metamcp/commit/e8c3fca
---

The first end-to-end bench of [`codec-time-leaf`](https://hub.docker.com/r/wdunn001/codec-time-leaf) in a real `codec-metamcp` namespace surfaced a real bug: the SDK's `CompatibilityCallToolResultSchema` strict-validates each content block against the closed `text|image|audio|resource` union. That rejects any `_codec_meta` sibling block, exactly what a Codec-aware leaf-mode MCP server emits.

Net effect on v0.3.0: all leaf-mode results crashed with `MCP error -32602: Invalid tools/call result` *before* the leaf-bypass detector could run.

**v0.3.1 fix**: a hand-rolled `CodecAwareCallToolResultSchema` that validates the envelope shape but uses `.passthrough()` per content block. `_codec_meta` (and any future custom content type) therefore survives parsing. The gateway no longer needs strict per-type validation. The downstream MCP server already validated its own response.

Bench numbers from the v0.3.1 run (`2026-05-09T11-10-48Z`):

| Workload                                | json   | msgpack-both+gzip | reduction |
|-----------------------------------------|-------:|------------------:|----------:|
| `tools/list` (40 tools)                 | 21.4 KB |          5.9 KB   |   **3.6×** |
| `codec-time-leaf__get_current_time`     |  4.6 KB |          1.1 KB   |   **4.2×** |

The 4.2× reduction on a Codec-aware tool call is the production-shape answer for "what does Codec do to MCP wire weight today" against a leaf-mode-eligible namespace.

A second bug remains under investigation: even with the validator fix in place, the gateway's `[Codec][leaf]` log doesn't fire, only `[Codec][shim]` does, suggesting the `_codec_meta` block is getting stripped somewhere between the SDK schema parse and the leaf-bypass detector. The 4.2× number above is real either way (gzip on the duplicated text+IDs payload), but the headline "leaf-mode bypass observable end-to-end" claim waits for the next patch.
