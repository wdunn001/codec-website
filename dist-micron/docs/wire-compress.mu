`F6cf`!HTTP compression picker — @codecai/wire-compress`!`f

`F999Picks the right Content-Encoding for streaming responses based on client support and payload size. Framework-agnostic, zero dependencies, ~5 KB. The companion library every @codecai/* client and Codec-aware gateway uses to negotiate gzip / brotli / dict-zstd / identity.`f

`F999`*Frameworks`*`f

-

'@codecai/wire-compress' is the small, framework-agnostic library that decides which 'Content-Encoding' a streaming response should use. `!~5 KB minified, zero runtime dependencies.`! It ships server-side 'pick()' for choosing the encoding and client-side 'buildAcceptEncoding()' for building the matching request header — both calibrated against the Codec v0.4.1 wire benchmark (https://github.com/wdunn001/Codec/blob/main/packages/bench/RESULTS.md).

The conventional advice is "always brotli for HTTP." That's right for static web assets. It's wrong for `!streaming responses with bursty small frames`! — SSE, Codec, gRPC-Web text, server-streamed JSON. Brotli's per-block overhead doesn't amortise across 10–25 byte frames; gzip and dict-zstd do. This package encodes the measured decision so you don't have to relitigate it per server.

>>>Install

`F999`*code (bash):`*`f
`=
npm install @codecai/wire-compress
`=

Works with any HTTP framework — Express, Fastify, Hono, Node's 'http', Bun, Deno, Cloudflare Workers. Pure functions, no middleware.

>>>Server side — pick the encoding

`F999`*code (ts):`*`f
`=
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
`=

The picker returns '{ encoding, reason }'. 'reason' is a human-readable log string explaining why this encoding was selected — useful when a deployment is debugging "why is the gateway not using zstd?" without having to instrument the decision tree by hand.

>>>Client side — build Accept-Encoding

`F999`*code (ts):`*`f
`=
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
`=

>>>The rule

┌─────────────────────────────────────────────────────┬───────────────┐
│ condition                                           │ encoding      │
├─────────────────────────────────────────────────────┼───────────────┤
│ 'zstdHasDict && zstdEnabled' && client accepts zstd │ `!zstd`!          │
│ client accepts gzip                                 │ `!gzip`!          │
│ client accepts br only                              │ br (fallback) │
│ nothing else                                        │ identity      │
└─────────────────────────────────────────────────────┴───────────────┘

Defaults are calibrated against measured streaming binary frames (Codec on sglang — see 'RESULTS.md' §1c–1g (https://github.com/wdunn001/Codec/blob/main/packages/bench/RESULTS.md) in the parent repo).

>>>>zstd is dict-only

The picker enforces a hard rule: `!'Content-Encoding: zstd' is selected ONLY when both 'zstdHasDict' and 'zstdEnabled' are true.`! Either gate failing → fall through to gzip.

• `!Without a dict`!, no-dict zstd's wire-byte advantage over gzip is essentially zero on Codec streams (both reach ≈3.4 B/token, within noise — 'RESULTS.md' §1f (https://github.com/wdunn001/Codec/blob/main/packages/bench/RESULTS.md)) — and on shipped middleware (sglang, vLLM/llama.cpp PR equivs) zstd buffers the whole response, regressing TTFB by 334× at 2K tokens. No-dict zstd is the worst of both worlds: same bytes as gzip, much worse TTFB.
• `!With a dict + streaming middleware`!, dict-zstd beats gzip by `!16–38%`! on bytes ('RESULTS.md' §1g (https://github.com/wdunn001/Codec/blob/main/packages/bench/RESULTS.md)) at +0.13 ms streaming TTFB — sub-millisecond, dwarfed by network.

The dict isn't an optimisation layered on top of zstd. It's the `!precondition`! for zstd being on the menu at all.

>>>>What about brotli?

Brotli has wider client coverage than zstd — Safari, iOS, older Firefox all ship 'br' but not zstd. So brotli matters as a `!fallback`!, not a primary choice. The picker reflects that:

• If client supports gzip → never use br (gzip wins on this workload at every size we measured).
• If client supports br but not gzip or zstd → use br. Strictly better than identity.
• If client supports nothing compressible → identity.

For the modern web (Chrome 123+, Firefox 126+) the picker lands on zstd; for older browsers and Safari it lands on gzip; br only kicks in for genuinely unusual clients that disabled gzip.

>>>>What about identity?

Identity loses at every size we measured — even at 16 tokens, compressed Codec is ≥2× smaller than raw. The CPU cost of gzip/zstd on a single CodecFrame is sub-microsecond. So identity is `!only`! chosen when the client refuses everything else, or when you explicitly restrict 'serverSupports'.

>>>API

>>>>'pick(input: PickInput): PickOutput'

`F999`*code (ts):`*`f
`=
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
`=

>>>>'parseAcceptEncoding(header): ClientSupport'

RFC 7231 §5.3.4-compliant parser. Sorts entries by q-value descending, drops 'q=0' entries, respects 'identity;q=0' to disable identity, returns 'unspecified=true' when the header is absent.

>>>>'buildAcceptEncoding(opts?): string'

Builds the recommended 'Accept-Encoding' header for clients to send. Default order reflects the measured preference: 'zstd;q=1.0, gzip;q=0.9, br;q=0.5'. Pass '{ zstd: false }' etc. to omit individual encodings.

>>>>'describeRule(t?): string'

Pretty-prints the rule for log lines or '--help' output.

>>>Why a separate package?

This logic is genuinely useful outside Codec. Anywhere you have:

• Streaming responses (SSE, gRPC-Web text, event streams)
• Many small frames rather than one big blob
• Mixed clients (modern browsers, mobile webviews, CLI tools, IoT)

…the right encoding depends on size and client support, and the standard "always-brotli" advice is wrong. Drop this in instead of writing your own switch statement.

The thresholds were measured for streaming token frames specifically. They generalise to other small-frame streaming workloads (chat APIs, log streams, telemetry) but you may want to recalibrate for your data.

>>>Polyglot ports — same picker in C# and C

The picker isn’t just a TypeScript module. The same Pareto-decision tree ships natively in `!Codec.Net`! (C#) and `!libcodec`! (C99), and every release replays the `!12,960-vector cross-language conformance suite`! to assert all three implementations pick the same encoding for the same input.

┌──────────────┬──────────┬─────────────────────────┬──────────────────────────────────────────┐
│ Language     │ Package  │ Public API entry        │ Test target                              │
├──────────────┼──────────┼─────────────────────────┼──────────────────────────────────────────┤
│ TypeScript   │ '@codeca │ 'pick({ ... })'         │ 'npm test' in 'packages/wire-compress/'  │
│              │ i/wire-c │                         │                                          │
│              │ ompress' │                         │                                          │
│              │ (https:/ │                         │                                          │
│              │ /www.npm │                         │                                          │
│              │ js.com/p │                         │                                          │
│              │ ackage/@ │                         │                                          │
│              │ codecai/ │                         │                                          │
│              │ wire-com │                         │                                          │
│              │ press)   │                         │                                          │
│ C# / .NET 8+ │ 'Codec.N │ 'Codec.Wire.Picker.Pick │ 'dotnet test' — 'PickerConformanceTests' │
│              │ et'      │ (new PickInput { ...    │                                          │
│              │ (https:/ │ })'                     │                                          │
│              │ /www.nug │                         │                                          │
│              │ et.org/p │                         │                                          │
│              │ ackages/ │                         │                                          │
│              │ Codec.Ne │                         │                                          │
│              │ t)       │                         │                                          │
│ C99          │ 'libcode │ 'codec_wire_pick(&in,   │ 'ctest -R test_wire_picker'              │
│              │ c' —     │ &out)' from             │                                          │
│              │ CMake    │ 'codec/codec_wire_picke │                                          │
│              │ 'codec:: │ r.h'                    │                                          │
│              │ codec'   │                         │                                          │
│              │ target   │                         │                                          │
└──────────────┴──────────┴─────────────────────────┴──────────────────────────────────────────┘

Same hard rule across all three: `!dictless zstd is never chosen.`! Same 'PickReasonCode' enum ('dict_zstd_default', 'gzip_no_dict', 'per_stack_overrode_zstd', …). Same stack profiles ('default', 'sglang', 'llama.cpp'). The conformance suite walks 12,960 inputs — all 15 standard 'Accept-Encoding' shapes × 9 payload sizes × 4 stack profiles × 4 flag combos × 2 interactivity modes × 3 sample profiles — and asserts byte-for-byte parity on '(encoding, reason_code)' for every vector. CI gates on it.

>>>>C# — 'Codec.Net'

`F999`*code (csharp):`*`f
`=
using Codec.Wire;

var pick = Picker.Pick(new PickInput
{
    AcceptEncoding = request.Headers["Accept-Encoding"],
    EstimatedSize  = 1024,
    ZstdHasDict    = dictResolved is not null,
    ZstdEnabled    = streamingZstdConfirmed,
    StackProfile   = StackProfiles.For("sglang"),
});
if (pick.Encoding != Codec.Wire.Encoding.Identity)
    response.Headers["Content-Encoding"] = Picker.EncodingName(pick.Encoding);
`=

'Codec.Net' targets 'net8.0' and ships the picker alongside the existing tokenizer / detokenizer / dict-zstd helpers. Brotli + gzip are built into the BCL ('System.IO.Compression.BrotliStream' / 'GZipStream'); zstd is left to the caller’s choice of NuGet ('ZstdSharp.Port' is what the test project uses).

>>>>C — 'libcodec'

`F999`*code (c):`*`f
`=
#include "codec/codec_wire_picker.h"

codec_wire_pick_input_t in = {
    .accept_encoding = request_header,
    .estimated_size  = 1024,
    .zstd_has_dict   = dict_resolved,
    .stack_profile   = codec_wire_profile_for("sglang"),
};
codec_wire_pick_result_t r;
codec_wire_pick(&in, &r);
if (r.encoding != CODEC_WIRE_ENC_IDENTITY)
    set_header("Content-Encoding", codec_wire_encoding_name(r.encoding));
`=

No malloc, no thread-locals, no external runtime deps — suitable for ESP32 firmware hot paths and Linux server hot paths alike. Brotli / gzip / zstd link-in is the caller’s choice (libbrotli, zlib, libzstd); 'libcodec' itself just owns the `!decision`!.

>>>Source & links

• npm: '@codecai/wire-compress' (https://www.npmjs.com/package/@codecai/wire-compress)
• NuGet: 'Codec.Net' (https://www.nuget.org/packages/Codec.Net) (picker in 'Codec.Wire.Picker')
• C: 'packages/c/include/codec/codec_wire_picker.h' (https://github.com/wdunn001/Codec/blob/main/packages/c/include/codec/codec_wire_picker.h)
• Source: 'packages/wire-compress' (https://github.com/wdunn001/Codec/tree/main/packages/wire-compress)
• Conformance vectors: 'packages/wire-compress/test/conformance-vectors.json' (https://github.com/wdunn001/Codec/blob/main/packages/wire-compress/test/conformance-vectors.json) (12,960 cases)
• Crossover chart: 'packages/bench/docs/crossover-summary.png' (https://raw.githubusercontent.com/wdunn001/Codec/main/packages/bench/docs/crossover-summary.png)
• Benchmark data: 'packages/bench/RESULTS.md' (https://github.com/wdunn001/Codec/blob/main/packages/bench/RESULTS.md) §1c–1g

>>>See also

• `[Protocol » Compression`:/page/codecai/docs/protocol.mu] — the wire-level negotiation this picker implements.
• `['@codecai/web'`:/page/codecai/docs/typescript.mu] — the canonical TypeScript client; pairs with the picker for end-to-end compressed Codec streams.
• `[codec-metamcp`:/page/codecai/docs/codec-metamcp.mu] — the Codec-aware MCP gateway that uses this picker to negotiate encoding on tool-call results.

-

`[<< Codec docs index`:/page/codecai/index.mu]

