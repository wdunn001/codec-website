---
title: Codec-aware MCP gateway
date: "2026-05-09"
kind: feature
version: v0.3.0
summary: Tool authors can now ship pre-tokenized results that bypass the gateway's back-compat shim. ~4.7× wire-byte reduction on real MCP traffic.
links:
  - label: GitHub release v0.3.0
    url: https://github.com/wdunn001/Codec/releases/tag/v0.3.0
  - label: codec-metamcp docs
    url: https://codecai.net/docs/codec-metamcp/
  - label: codec-time-leaf reference image
    url: https://hub.docker.com/r/wdunn001/codec-time-leaf
---

The Codec-aware MCP gateway closes the leaf-mode loop end-to-end. Three pieces shipped together:

- **`@codecai/mcp-leaf`**, tool-author SDK. Wrap your `CallToolResult` with `wrapToolCall(result, meta)` and the gateway sees the pre-tokenized IDs instead of having to re-tokenize on every request.
- **`codec-time-leaf`**, reference Codec-aware MCP server. Drop it in any [`codec-metamcp`](https://codecai.net/docs/codec-metamcp/) namespace and the gateway log flips from `[Codec][shim]` warns to `[Codec][leaf]` info.
- **MCP-shaped zstd dictionary**, pre-trained 16 KB dict that the gateway loads at startup. Cuts wire bytes ~4.7× over JSON+gzip on real MCP traffic.

The leaf-mode path is additive. Non-Codec-aware clients in the same namespace see exactly what they always have. No MCP version bump.
