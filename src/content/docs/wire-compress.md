---
title: HTTP compression picker — @codecai/wire-compress
description: Picks the right Content-Encoding for streaming responses based on client support and payload size. Framework-agnostic, zero dependencies, ~5 KB. The companion library every @codecai/* client and Codec-aware gateway uses to negotiate gzip / brotli / dict-zstd / identity.
section: Frameworks
order: 7
---

`@codecai/wire-compress` is the small, framework-agnostic library that decides which `Content-Encoding` a streaming response should use. **~5 KB minified, zero runtime dependencies.** It ships server-side `pick()` for choosing the encoding and client-side `buildAcceptEncoding()` for building the matching request header — both calibrated against the Codec [v0.4.1 wire benchmark](https://github.com/wdunn001/Codec/blob/main/packages/bench/RESULTS.md).

The conventional advice is "always brotli for HTTP." That's right for static web assets. It's wrong for **streaming responses with bursty small frames** &mdash; SSE, Codec, gRPC-Web text, server-streamed JSON. Brotli's per-block overhead doesn't amortise across 10&ndash;25 byte frames; gzip and dict-zstd do. This package encodes the measured decision so you don't have to relitigate it per server.

## Install

```bash
npm install @codecai/wire-compress
```

Works with any HTTP framework &mdash; Express, Fastify, Hono, Node's `http`, Bun, Deno, Cloudflare Workers. Pure functions, no middleware.

## Server side — pick the encoding

```ts
import { pick } from '@codecai/wire-compress';

app.get('/stream', (req, res) => {
  const dictForThisRequest = lookupZstdDict(req);
  const choice = pick({
    acceptEncoding: req.headers['accept-encoding'],
    estimatedSize: 1024,
    zstdHasDict: dictForThisRequest !== null,
    zstdEnabled: STREAMING_ZSTD_MIDDLEWARE,
  });
  if (choice.encoding !== 'identity') {
    res.setHeader('Content-Encoding', choice.encoding);
  }
  // ... apply the chosen compressor (with dict if zstd) and stream
});
```

The picker returns `{ encoding, reason }`. `reason` is a human-readable log string explaining why this encoding was selected &mdash; useful when a deployment is debugging "why is the gateway not using zstd?" without having to instrument the decision tree by hand.

## Client side — build Accept-Encoding

```ts
import { buildAcceptEncoding } from '@codecai/wire-compress';

fetch('/stream', {
  headers: { 'Accept-Encoding': buildAcceptEncoding() },
  // → "gzip;q=1.0, br;q=0.5"           (zstd omitted by default)
});

// Opt into zstd only when you've confirmed (a) the server has a dict for
// this tokenizer and (b) the gateway streams (doesn't buffer):
fetch('/stream', {
  headers: { 'Accept-Encoding': buildAcceptEncoding({ zstd: true }) },
  // → "gzip;q=1.0, br;q=0.5, zstd;q=0.3"
});
```

## The rule

| condition | encoding |
|---|---|
| `zstdHasDict && zstdEnabled` && client accepts zstd | **zstd** |
| client accepts gzip | **gzip** |
| client accepts br only | br (fallback) |
| nothing else | identity |

Defaults are calibrated against measured streaming binary frames (Codec on sglang &mdash; see [`RESULTS.md` §1c&ndash;1g](https://github.com/wdunn001/Codec/blob/main/packages/bench/RESULTS.md) in the parent repo).

### zstd is dict-only

The picker enforces a hard rule: **`Content-Encoding: zstd` is selected ONLY when both `zstdHasDict` and `zstdEnabled` are true.** Either gate failing &rarr; fall through to gzip.

- **Without a dict**, no-dict zstd's wire-byte advantage over gzip is essentially zero on Codec streams (both reach &asymp;3.4&nbsp;B/token, within noise &mdash; [`RESULTS.md` §1f](https://github.com/wdunn001/Codec/blob/main/packages/bench/RESULTS.md)) &mdash; and on shipped middleware (sglang, vLLM/llama.cpp PR equivs) zstd buffers the whole response, regressing TTFB by 334&times; at 2K tokens. No-dict zstd is the worst of both worlds: same bytes as gzip, much worse TTFB.
- **With a dict + streaming middleware**, dict-zstd beats gzip by **16&ndash;38%** on bytes ([`RESULTS.md` §1g](https://github.com/wdunn001/Codec/blob/main/packages/bench/RESULTS.md)) at +0.13&nbsp;ms streaming TTFB &mdash; sub-millisecond, dwarfed by network.

The dict isn't an optimisation layered on top of zstd. It's the **precondition** for zstd being on the menu at all.

### What about brotli?

Brotli has wider client coverage than zstd &mdash; Safari, iOS, older Firefox all ship `br` but not zstd. So brotli matters as a **fallback**, not a primary choice. The picker reflects that:

- If client supports gzip &rarr; never use br (gzip wins on this workload at every size we measured).
- If client supports br but not gzip or zstd &rarr; use br. Strictly better than identity.
- If client supports nothing compressible &rarr; identity.

For the modern web (Chrome 123+, Firefox 126+) the picker lands on zstd; for older browsers and Safari it lands on gzip; br only kicks in for genuinely unusual clients that disabled gzip.

### What about identity?

Identity loses at every size we measured &mdash; even at 16 tokens, compressed Codec is &ge;2&times; smaller than raw. The CPU cost of gzip/zstd on a single CodecFrame is sub-microsecond. So identity is **only** chosen when the client refuses everything else, or when you explicitly restrict `serverSupports`.

## API

### `pick(input: PickInput): PickOutput`

```ts
interface PickInput {
  acceptEncoding?: string | null;          // raw header value
  estimatedSize: number;                    // tokens or bytes (your unit)

  // Required for zstd to be a candidate (default false). Set per request:
  // true when the loaded tokenizer map's zstd_dictionaries[] has an entry
  // matching this response's stream_format.
  zstdHasDict?: boolean;

  // Required for zstd to be a candidate (default false). Set globally:
  // true when the gateway uses streaming-zstd-with-flush, not buffered
  // finalisation.
  zstdEnabled?: boolean;

  serverSupports?: Encoding[];              // restrict server-side capabilities
}

interface PickOutput {
  encoding: 'identity' | 'gzip' | 'br' | 'zstd';
  reason: string;                           // human-readable, for logs
}
```

### `parseAcceptEncoding(header): ClientSupport`

RFC 7231 §5.3.4-compliant parser. Sorts entries by q-value descending, drops `q=0` entries, respects `identity;q=0` to disable identity, returns `unspecified=true` when the header is absent.

### `buildAcceptEncoding(opts?): string`

Builds the recommended `Accept-Encoding` header for clients to send. Default order reflects the measured preference: `zstd;q=1.0, gzip;q=0.9, br;q=0.5`. Pass `{ zstd: false }` etc. to omit individual encodings.

### `describeRule(t?): string`

Pretty-prints the rule for log lines or `--help` output.

## Why a separate package?

This logic is genuinely useful outside Codec. Anywhere you have:

- Streaming responses (SSE, gRPC-Web text, event streams)
- Many small frames rather than one big blob
- Mixed clients (modern browsers, mobile webviews, CLI tools, IoT)

&hellip;the right encoding depends on size and client support, and the standard "always-brotli" advice is wrong. Drop this in instead of writing your own switch statement.

The thresholds were measured for streaming token frames specifically. They generalise to other small-frame streaming workloads (chat APIs, log streams, telemetry) but you may want to recalibrate for your data.

## Source &amp; links

- npm: [`@codecai/wire-compress`](https://www.npmjs.com/package/@codecai/wire-compress)
- Source: [`packages/wire-compress`](https://github.com/wdunn001/Codec/tree/main/packages/wire-compress)
- Crossover chart: [`packages/bench/docs/crossover-summary.png`](https://raw.githubusercontent.com/wdunn001/Codec/main/packages/bench/docs/crossover-summary.png)
- Benchmark data: [`packages/bench/RESULTS.md`](https://github.com/wdunn001/Codec/blob/main/packages/bench/RESULTS.md) §1c&ndash;1g

## See also

- [Protocol &raquo; Compression](/docs/protocol/#compression) &mdash; the wire-level negotiation this picker implements.
- [`@codecai/web`](/docs/typescript/) &mdash; the canonical TypeScript client; pairs with the picker for end-to-end compressed Codec streams.
- [codec-metamcp](/docs/codec-metamcp/) &mdash; the Codec-aware MCP gateway that uses this picker to negotiate encoding on tool-call results.
