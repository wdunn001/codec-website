`F6cf`!v0.3.2, leaf-mode bypass observable end-to-end on real MCP traffic`!`f

`F9992026-05-09 - v0.3.2 - feature`f

-

The Codec leaf-mode bypass (the architectural target the entire v0.3 contract was designed for) fires end-to-end. \`[Codec][leaf]\` log line confirms the gateway is a transparent ID pipe; the tokenizer sits at the leaf where it belongs.

-

The Codec v0.3 leaf-mode contract (the architectural target where `!the tool tokenizes once, the gateway forwards IDs verbatim`!) landed on real lab traffic for the first time today. The proof is one log line:

`=
[INFO] [Codec][leaf] downstream tool returned pre-tokenized result
for vocab sha256:9db56ff6… gateway shim bypassed.
`=

Two coordinated fixes shipped in v0.3.2:

`!1. Wire shape change.`! '@codecai/mcp-leaf' now annotates each text content block with a per-block '_meta['ai.codec/leaf-tokenization']' payload instead of pushing a sibling '_codec_meta' content block. The sibling form crashed the MCP SDK's validator on the `!server`! side ('-32602 Invalid tools/call result') before the result ever left the leaf process, '_codec_meta' isn't in the SDK's discriminated content-block union. The per-block '_meta' slot is a first-class MCP spec field that the SDK passes through unchanged. Bonus side-effect: the per-block representation is `!~4.6× more compact`! than the sibling form (a 4.6 KB JSON baseline collapsed to 990 B).

`!2. Gateway detector.`! 'codec-metamcp''s 'hasExistingCodecMeta' now checks both shapes (per-block '_meta' first, legacy sibling-block as back-compat). When it finds either, the shim bypasses, the '[Codec][leaf]' log fires, and the gateway acts as a transparent ID pipe for that hop.

Bench numbers from the v0.3.2 run ('2026-05-09T12-17-48Z'):

┌─────────────────────────────────────┬─────────┬──────────────────────────────┐
│ Workload                            │ json    │ msgpack-both+gzip+map (leaf) │
├─────────────────────────────────────┼─────────┼──────────────────────────────┤
│ 'codec-time-leaf__get_current_time' │   990 B │                        931 B │
│ 'codec-time-leaf__convert_time'     │  1.0 KB │                        972 B │
│ 'tools/list' (40 tools)             │ 21.4 KB │                       5.9 KB │
└─────────────────────────────────────┴─────────┴──────────────────────────────┘

Wire bytes between variant 4 (gzip with shim) and variant 5 (gzip with leaf-bypass) are now identical because gzip already collapses redundant content. The leaf-bypass benefit on this hop is `!CPU on the gateway`! (no tokenizer runs) and `!KV-cache safety`! (the engine receives the exact IDs the leaf produced). The '[Codec][leaf]' log is the right observability target, not a smaller number.

'tools/list' holds at `!3.6×`! wire reduction across the 40-tool namespace.

Status of the v0.3 release: spec, polyglot clients, MCP integration, website + RSS, bench methodology, and now the leaf-mode end-to-end demo all live.

-

>>Links

GitHub release v0.3.2 (https://github.com/wdunn001/Codec/releases/tag/v0.3.2)

2026-05-09T12-17-48Z bench results (https://github.com/wdunn001/Codec/tree/main/packages/bench/results/2026-05-09T12-17-48Z/mcp)

PROTOCOL.md § Tool-call calling conventions in the map (https://github.com/wdunn001/Codec/blob/main/spec/PROTOCOL.md)

-

`[<< Full changelog`:/page/codecai/changelog.mu]

`[<< Codec docs index`:/page/codecai/index.mu]

