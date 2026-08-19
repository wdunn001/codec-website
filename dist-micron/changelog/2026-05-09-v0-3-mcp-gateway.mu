`F6cf`!Codec-aware MCP gateway`!`f

`F9992026-05-09 - v0.3.0 - feature`f

-

Tool authors can now ship pre-tokenized results that bypass the gateway's back-compat shim. ~4.7× wire-byte reduction on real MCP traffic.

-

The Codec-aware MCP gateway closes the leaf-mode loop end-to-end. Three pieces shipped together:

• `!'@codecai/mcp-leaf'`!, tool-author SDK. Wrap your 'CallToolResult' with 'wrapToolCall(result, meta)' and the gateway sees the pre-tokenized IDs instead of having to re-tokenize on every request.
• `!'codec-time-leaf'`!, reference Codec-aware MCP server. Drop it in any `['codec-metamcp'`:/page/codecai/docs/codec-metamcp.mu] namespace and the gateway log flips from '[Codec][shim]' warns to '[Codec][leaf]' info.
• `!MCP-shaped zstd dictionary`!, pre-trained 16 KB dict that the gateway loads at startup. Cuts wire bytes ~4.7× over JSON+gzip on real MCP traffic.

The leaf-mode path is additive. Non-Codec-aware clients in the same namespace see exactly what they always have. No MCP version bump.

-

>>Links

GitHub release v0.3.0 (https://github.com/wdunn001/Codec/releases/tag/v0.3.0)

codec-metamcp docs (https://codecai.net/docs/codec-metamcp/)

codec-time-leaf reference image (https://hub.docker.com/r/wdunn001/codec-time-leaf)

-

`[<< Full changelog`:/page/codecai/changelog.mu]

`[<< Codec docs index`:/page/codecai/index.mu]

