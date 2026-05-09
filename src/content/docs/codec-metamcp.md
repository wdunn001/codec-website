---
title: codec-metamcp (Docker)
description: MetaMCP gateway with Codec binary transport. The MCP aggregator, but tool-call results ship as length-prefixed msgpack instead of newline-delimited JSON-RPC.
section: Server
order: 4
---

`codec-metamcp` is a pre-built Docker image of [MetaMCP](https://github.com/metatool-ai/metamcp) &mdash; the MCP aggregator/orchestrator/gateway &mdash; with the Codec binary transport patch applied. Stand it up like the upstream image, point any MCP client at it, and tool-heavy sessions ship dramatically smaller wire bytes when the client opts into Codec.

Unlike [codec-sglang](/docs/codec-sglang/) / [codec-vllm](/docs/codec-vllm/) / [codec-llamacpp](/docs/codec-llamacpp/), this image **doesn't bundle a Python control plane**. MetaMCP already ships an admin UI as its frontend (Next.js) for namespace + server management, so there's nothing for `codec-supervisor` to add. The image is just MetaMCP, built from the [`wdunn001/metamcp` fork](https://github.com/wdunn001/metamcp/tree/feat/codec-binary-transport) at the open PR ([metatool-ai/metamcp#287](https://github.com/metatool-ai/metamcp/pull/287)).

## Quick start

```bash
docker run -d \
  -p 12008:12008 \
  -e APP_URL=http://localhost:12008 \
  -e POSTGRES_URL=postgres://user:pass@db:5432/metamcp \
  --name codec-metamcp \
  wdunn001/codec-metamcp:latest
```

Frontend admin UI is on `:12008` &mdash; create a namespace, add a few MCP servers, click through to copy the namespace endpoint URL. That URL works against any standard MCP client (Claude Desktop, Cursor, Cline, etc.) byte-for-byte identically to upstream MetaMCP.

The Codec wire format is **opt-in per request** &mdash; clients that don't negotiate it see exactly the JSON-RPC bytes upstream MetaMCP would emit.

## Negotiation

Three equivalent ways to opt in. Resolution order, first match wins:

```
?stream_format=msgpack     # or protobuf  (URL query param)
Accept: application/x-codec-msgpack    # request header
?stream_format=json        # explicit opt-out (back to JSON-RPC)
```

Add `Accept-Encoding: gzip` for streaming compression on top.

## What you get

For tool-heavy sessions &mdash; long file reads, web fetches, RAG context, model-generated text piped through tools &mdash; the wire weight collapses. Same physics as the [cross-stack benchmark matrix](https://github.com/wdunn001/Codec/blob/main/packages/bench/results/2026-05-08T01-15-02Z/MATRIX.md):

- **Length-prefixed msgpack/protobuf framing** instead of newline-delimited JSON-RPC envelopes
- **Streaming gzip** on top via standard `Accept-Encoding` negotiation
- **TTFB unchanged** &mdash; first-body-byte stays within 1&nbsp;ms of the JSON-RPC path on the same server
- **MCP-shaped zstd dictionary negotiation** &mdash; the gateway loads a pre-trained 16&nbsp;KB dict at startup and emits a `Codec-Zstd-Dict: sha256:…` header so a Codec-aware client can fetch the matching dict and decompress every frame against it. **+78.8&nbsp;% wire-byte reduction over no-dict zstd; ~4.7× over JSON+gzip** on real MCP traffic ([2026-05-08T22-24-23Z bench](https://github.com/wdunn001/Codec/tree/main/packages/bench/results/2026-05-08T22-24-23Z/mcp)).
- **Leaf-mode bypass for Codec-aware tools** &mdash; tools that wrap their results with `_codec_meta` blocks (see [`@codecai/mcp-leaf`](https://www.npmjs.com/package/@codecai/mcp-leaf) and the [`codec-time-leaf`](https://hub.docker.com/r/wdunn001/codec-time-leaf) reference image) tell the gateway "the IDs are already here, don't re-tokenize." `[Codec][leaf]` log fires on bypass; `[Codec][shim]` log fires on legacy fallback.
- **Frame shape compatible with [`@codecai/web`](https://www.npmjs.com/package/@codecai/web), [`codecai`](https://pypi.org/project/codecai/), and the four other client libraries** &mdash; same `decodeStream` decoders that work end-to-end against codec-sglang / codec-vllm / codec-llamacpp work here too.

The follow-up release adds per-token Codec encoding for `text` content blocks beyond the leaf-mode path (the headline wire reduction lives there) plus a [`Translator`](/docs/translator/) middleware for cross-vocab tool handoff. The framing foundation for both is live today.

## Codec-aware tools (leaf mode)

The fast path on a Codec-aware gateway isn't the gateway tokenizing tool results &mdash; it's the **tool itself** doing the tokenization once, against a pinned tokenizer map, and shipping IDs alongside the original text. The gateway recognizes the pre-tokenized output and bypasses its back-compat shim entirely. Three pieces:

- [**`@codecai/mcp-leaf`**](https://www.npmjs.com/package/@codecai/mcp-leaf) &mdash; tool-author-side helper. `wrapToolCall(result, meta)` walks every text content block and adds a sibling `_codec_meta` block carrying the token IDs. Idempotent; non-Codec-aware clients in the same namespace ignore the meta sibling.
- [**`codec-time-leaf`**](https://hub.docker.com/r/wdunn001/codec-time-leaf) &mdash; reference Codec-aware MCP server (the canonical demo of leaf mode). Two trivial tools (`get_current_time`, `convert_time`) chosen for predictability. Drop it in any metamcp namespace; gateway logs flip from `[Codec][shim]` warns to `[Codec][leaf]` info.
- **Reader-side helper** &mdash; `readCodecMeta(result)` / `takeIds(result)` in `@codecai/mcp-leaf` for clients that want to lift the IDs back out symmetrically (no re-tokenization on the receive side).

The contract is additive &mdash; the leaf-mode path is invisible to legacy clients in the same namespace, no MCP version bump.

## Running with the upstream compose

`codec-metamcp` is a drop-in for the upstream image in MetaMCP's own [`docker-compose.yml`](https://github.com/metatool-ai/metamcp/blob/main/docker-compose.yml) &mdash; replace `metatool-ai/metamcp:latest` with `wdunn001/codec-metamcp:latest` and the database / network wiring stays identical:

```yaml
services:
  metamcp:
    image: wdunn001/codec-metamcp:latest
    ports:
      - "12008:12008"
    environment:
      APP_URL: http://localhost:12008
      POSTGRES_URL: postgres://metamcp:metamcp@db:5432/metamcp
    depends_on:
      - db
  db:
    image: postgres:16
    environment:
      POSTGRES_USER: metamcp
      POSTGRES_PASSWORD: metamcp
      POSTGRES_DB: metamcp
    volumes:
      - metamcp-db:/var/lib/postgresql/data

volumes:
  metamcp-db:
```

## Pointing a Codec client at it

Once a namespace is set up and you've copied its endpoint URL (e.g. `http://localhost:12008/metamcp/<namespace-uuid>/mcp`), the same `@codecai/web` decoder you'd use against any Codec server works:

```ts
import { decodeStream } from "@codecai/web";

const resp = await fetch(
  "http://localhost:12008/metamcp/<uuid>/mcp?stream_format=msgpack",
  {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Accept": "application/x-codec-msgpack",
      "Accept-Encoding": "gzip",
    },
    body: JSON.stringify({
      jsonrpc: "2.0",
      id: 1,
      method: "tools/list",
      params: {},
    }),
  },
);

for await (const frame of decodeStream(resp.body!, "msgpack")) {
  console.log(frame); // JSON-RPC message, decoded
}
```

The MCP-over-Codec frames carry plain JSON-RPC bodies inside the msgpack envelope &mdash; same fields, same semantics, same tool-call results. Just smaller on the wire.

## When to use this vs upstream MetaMCP

- **Use `codec-metamcp`** when any of your MCP clients support Codec (today: anything that imports `@codecai/web` / `codecai` / `Codec.Net` / etc.) and you want bandwidth savings on tool-call results without changing how you administer the gateway.
- **Use [upstream MetaMCP](https://github.com/metatool-ai/metamcp)** for everything else &mdash; the Codec patch is fully backwards-compatible per-request, but if no client negotiates it the image just runs the same code as upstream with one extra Express middleware mounted.

The wire is bit-identical between the upstream and codec-metamcp paths when no client opts in. Switching is a no-op until something in the cluster speaks Codec.

## License

The Codec patch is published under [BSL 1.1](https://github.com/wdunn001/Codec/blob/main/LICENSE) by Quasarke LLC; free for non-production use and for production use under US&nbsp;$5M annual gross revenue. The bundled MetaMCP retains its upstream [Apache-2.0](https://github.com/metatool-ai/metamcp/blob/main/LICENSE) license. Commercial licensing for the patch above the threshold: [licensing@quasarke.com](mailto:licensing@quasarke.com).

## Source &amp; links

- Image: [`wdunn001/codec-metamcp:latest`](https://hub.docker.com/r/wdunn001/codec-metamcp) on Docker Hub.
- Codec patch source: [github.com/wdunn001/metamcp](https://github.com/wdunn001/metamcp/tree/feat/codec-binary-transport).
- Upstream PR: [metatool-ai/metamcp#287](https://github.com/metatool-ai/metamcp/pull/287).
- Image build recipe: [github.com/wdunn001/codec-supervisor/blob/main/Dockerfile.metamcp](https://github.com/wdunn001/codec-supervisor/blob/main/Dockerfile.metamcp).

## See also

- [codec-sglang](/docs/codec-sglang/) / [codec-vllm](/docs/codec-vllm/) / [codec-llamacpp](/docs/codec-llamacpp/) &mdash; inference engines on the other side of the gateway.
- [TypeScript](/docs/typescript/) / [Python](/docs/python/) walkthroughs &mdash; client patterns for any Codec endpoint, including this one.
- [Protocol overview](/docs/protocol/) &mdash; the wire format spec the framing in this image speaks.
