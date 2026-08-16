`F6cf`!Protocol overview`!`f

`F999The wire format in detail — frames, vocab handshake, transports, compression. Everything you need to write a fifth implementation.`f

`F999`*Start`*`f

-

This is a tour of PROTOCOL.md (https://github.com/wdunn001/Codec/blob/main/spec/PROTOCOL.md), the canonical spec. If you're using one of the six reference implementations you don't need to read it — the bindings already speak the protocol for you.

>>>Layers

Codec is deliberately three thin layers on top of HTTP, not one fat envelope:

┌─────────────────┬───────────────────────────────┬──────────────────────────────────┐
│ Layer           │ What it carries               │ What it does NOT carry           │
├─────────────────┼───────────────────────────────┼──────────────────────────────────┤
│ `!Token IDs`!       │ 'uint32[]'                    │ Text, role markers, tool framing │
│ `!Frames`!          │ '{ids, done, finish_reason?}' │ Token semantics                  │
│ `!Vocab handshake`! │ sha256-addressed JSON map     │ Frames                           │
└─────────────────┴───────────────────────────────┴──────────────────────────────────┘

The handshake binds an ID space to a tokenizer; frames carry IDs in that space; the IDs map back to tokens `*only`* when a human edge needs them.

>>>Frame format

Every frame on the wire is:

`=
+---------------------+----------------------------+
| 4-byte BE length    | msgpack OR protobuf body   |
+---------------------+----------------------------+
`=

The body is one of:

`!msgpack`! — a map with three optional keys:

`=
{ "ids": [uint32, uint32, ...], "done": bool, "finish_reason": str (optional) }
`=

`!protobuf`! — a 'CodecFrame' message:

`F999`*code (proto):`*`f
`=
message CodecFrame {
  repeated uint32 ids = 1 [packed = true];
  bool done = 2;
  optional string finish_reason = 3;
}
`=

Both bind to identical semantics. Pick msgpack if you want zero schema dependencies; pick protobuf if you want stricter typing or already have a 'protoc' toolchain.

>>>Same payload, different planet

The seven-token request '"What is the capital of France?"' on the wire, both ways:

`!JSON`! — ~142 bytes, text:

`F999`*code (http):`*`f
`=
POST /v1/chat/completions HTTP/2
content-type: application/json

{
  "model": "gpt-4",
  "messages": [
    { "role": "user",
      "content": "What is the capital of France?" }
  ]
}
`=

`!Codec`! — 32 bytes, binary:

`F999`*code (http):`*`f
`=
POST /v1/chat HTTP/2
content-type: application/codec

01 00 00 04   // control: vocab=gpt-4 / role=user
00 00 0F A1   // "What"
00 00 09 BE   //  " is"
00 00 04 21   //  " the"
00 00 1C 33   //  " capital"
00 00 02 5A   //  " of"
00 00 1F 90   //  " France"
00 00 02 30   //  "?"
`=

JSON pays the tokenizer twice — once when the client serializes, once when the server retokenizes the UTF-8. Codec ships the IDs the model already speaks, with one control word at the head naming the vocab and message role. That's the only framing.

>>>Vocab handshake

A `*dialect map`* is a JSON document that fully describes a tokenizer:

• 'vocab' — the token-string-to-ID map
• 'merges' — BPE merge rules
• 'special_tokens' — reserved control IDs ('<|im_start|>', '<tool_call>', etc.)
• 'encoder_type' — 'byte_level', 'metaspace', or omitted
• 'pre_tokenizer_program' (optional) — a small instruction list that replaces the legacy GPT-2 regex; deterministic across languages

Maps are addressed by `!sha256 of the canonical JSON bytes`!. 'loadMap({url, hash})' is 'fetch + verify + cache'. A given '(url, hash)' pair always resolves to byte-identical bytes — or 'loadMap' raises.

'github.com/wdunn001/codec-maps' (https://github.com/wdunn001/codec-maps) hosts a starter set of pre-generated maps — Llama, Qwen, Mistral, Phi, Gemma, DeepSeek, Falcon, SmolLM2, Codestral, and more — but the registry isn't a closed list. Any model with a Hugging Face 'tokenizer.json' can have a map: install '@codecai/maps-cli' (https://www.npmjs.com/package/@codecai/maps-cli) and run 'codec-maps generate <tokenizer.json>' to produce a deterministic, sha256-addressable map for your fine-tune, your private model, or anything else — same format, same 'loadMap' call, same wire bytes. The codec-maps repo accepts PRs for new models too, but you don't need to wait on one to use Codec.

>>>>Discovery

If you don't want to track URLs and hashes out of band, model maintainers can publish maps at a stable '/.well-known/codec/' path on a domain they control. Clients then resolve a map from '(origin, id)' alone:

`F999`*code (ts):`*`f
`=
import { discoverMap } from "@codecai/web/discover";
const map = await discoverMap({ origin: "https://example.com", id: "qwen2" });
`=

This is the resolution to PROTOCOL.md's old Open Question #3 (decentralised first; a registry remains an option for cross-org and air-gapped use). Full convention: `[Self-hosted discovery`:/page/codecai/docs/discovery.mu].

>>>HTTP transports

The spec defines three patterns over plain HTTP, in increasing weirdness:

>>>>A. Text prompt in, binary stream out

The drop-in upgrade. Same JSON request body as today's '/v1/completions', plus 'stream_format':

`F999`*code (http):`*`f
`=
POST /v1/completions HTTP/1.1
Content-Type: application/json
Accept-Encoding: gzip

{
  "model": "Qwen/Qwen2.5-7B-Instruct",
  "prompt": "Explain entropy.",
  "stream_format": "msgpack",
  "max_tokens": 256
}
`=

Response body is a sequence of length-prefixed msgpack frames. 'Content-Type: application/codec+msgpack' (or '+protobuf').

>>>>B. Token-ID prompt, binary in, binary out

Skip the server's tokenizer call entirely:

`F999`*code (json):`*`f
`=
{
  "model": "Qwen/Qwen2.5-7B-Instruct",
  "prompt": [4954, 198, 11, 5234, ...],
  "stream_format": "msgpack",
  "max_tokens": 256
}
`=

Useful when the client already has the IDs (e.g., during multi-hop agent flows where a previous Codec response `*is`* the next prompt).

>>>>C. Binary in, binary out: '/v1/completions/codec'

For very large prompts where even the JSON envelope is too big. The whole request body is a Codec frame; the response is a Codec stream. Documented in PROTOCOL.md §3.3 (https://github.com/wdunn001/Codec/blob/main/spec/PROTOCOL.md).

>>>Compression

Codec is `!streaming-safe with gzip`!. Set 'Accept-Encoding: gzip, identity' on the request; the server compresses if it's worth it. Identity is always a valid response. Brotli was broken in v0.4.0 (per-chunk 'flush()' reset the sliding window, inflating small streams); the v0.4.1 fix in both sglang + vllm forks restores brotli's between-chunk dictionary, and brotli is now Pareto-front for 32–256 token msgpack streams — beating both gzip and dict-zstd in that size band. The server's compression negotiator honours spec preference order 'zstd > br > gzip > identity' and picks the smallest.

>>>>zstd is dict-only

zstd without a pre-trained dictionary is a trap on Codec streams: its wire-byte advantage over gzip is essentially zero (both reach ≈3.4 B/token, within noise — RESULTS.md §1f (https://github.com/wdunn001/Codec/blob/main/packages/bench/RESULTS.md)) but the shipped buffered middleware in every gateway eats a `!334× TTFB cliff`! at 2K tokens (11 ms → 3,684 ms). Same bytes as gzip, much worse first-token latency.

`!The pre-trained dictionary is the precondition for using zstd at all`! — not an optimization layered on top. Tokenizer maps now declare zstd dictionaries inline:

`F999`*code (json):`*`f
`=
{
  "id": "qwen/qwen2",
  "vocab": { ... },
  "merges": [ ... ],
  "zstd_dictionaries": [
    {
      "format":     "msgpack",
      "url":        "https://raw.githubusercontent.com/wdunn001/Codec/main/dictionaries/qwen2.5-msgpack-v1.dict",
      "hash":       "sha256:...",
      "size_bytes": 16384
    },
    {
      "format":     "protobuf",
      "url":        "https://raw.githubusercontent.com/wdunn001/Codec/main/dictionaries/qwen2.5-protobuf-v1.dict",
      "hash":       "sha256:...",
      "size_bytes": 16384
    }
  ]
}
`=

A server with a matching dict loaded compresses against it; a client decompresses against the same one (matched by hash). The two formats train against different byte distributions, so dicts are not interchangeable across 'msgpack' / 'protobuf'. Without a loaded dict, servers MUST fall through to gzip — the picker enforces this and the `['@codecai/wire-compress'`:/page/codecai/docs/wire-compress.mu] library refuses to advertise zstd unless a matching dict is in place.

With a dict, dict-zstd beats gzip by `!16–38%`! on bytes (RESULTS.md §1g (https://github.com/wdunn001/Codec/blob/main/packages/bench/RESULTS.md)) at +0.13 ms streaming TTFB — sub-millisecond, dwarfed by network. So for a deployment with a dict shipped alongside the model, zstd is the right pick for both interactive and agent traffic.

>>>>'Codec-Zstd-Dict' response header

When a server responds with 'Content-Encoding: zstd', it MUST emit the hash of the dictionary it used as a 'Codec-Zstd-Dict' header:

`F999`*code (http):`*`f
`=
Content-Encoding: zstd
Codec-Zstd-Dict:  sha256:79b707aea8c2b41c2883ec7913b0c4a0c880044ac844d89a9a03e779eb92db04
Vary:             Accept-Encoding
`=

The header value is 'sha256:' followed by the lowercase hex digest of the raw dictionary bytes — same shape as the 'hash' field in 'zstd_dictionaries[]' entries.

Clients check the hash against a dict they have loaded. Hash mismatch is a fatal stream error (wrong-dict zstd decompression yields garbage); a missing header on a zstd response is a server protocol error. Why a header rather than inferring from 'tokenizer_id': a single tokenizer can have multiple dict versions over time (re-trained on fresher corpora, specialised per workload). The header lets a deployment upgrade its dict without bumping the tokenizer-map version, and lets intermediaries identify the active dict by reading headers alone.

Reference dicts ship at 'dictionaries/' (https://github.com/wdunn001/Codec/tree/main/dictionaries) in the main repo; the training pipeline is 'packages/bench/scripts/train-zstd-dict.py' (https://github.com/wdunn001/Codec/blob/main/packages/bench/scripts/train-zstd-dict.py).

>>>Request vs response — where each Codec knob lives

Codec piggybacks on the OpenAI '/v1/completions' body schema rather than redefining the request envelope. That makes the asymmetry confusing at first — some Codec configuration is in the `!request body`!, some is in `!HTTP headers`! (request and response), some only shows up on the response side. The table:

┌──────────────────────────────────────────────────────┬────────────────────────────┬──────────┐
│ Knob                                                 │ Where                      │ Why      │
├──────────────────────────────────────────────────────┼────────────────────────────┼──────────┤
│ 'stream_format: "msgpack" | "protobuf" | "json"'     │ request body (next to      │ Per-requ │
│                                                      │ 'model', 'prompt',         │ est      │
│                                                      │ 'max_tokens')              │ choice   │
│                                                      │                            │ that     │
│                                                      │                            │ piggybac │
│                                                      │                            │ ks on    │
│                                                      │                            │ the      │
│                                                      │                            │ OpenAI   │
│                                                      │                            │ body.    │
│                                                      │                            │ Default  │
│                                                      │                            │ '"json"' │
│                                                      │                            │ keeps    │
│                                                      │                            │ existing │
│                                                      │                            │ JSON-SSE │
│                                                      │                            │ traffic  │
│                                                      │                            │ byte-ide │
│                                                      │                            │ ntical;  │
│                                                      │                            │ no Codec │
│                                                      │                            │ presence │
│                                                      │                            │ at all   │
│                                                      │                            │ on       │
│                                                      │                            │ requests │
│                                                      │                            │ that     │
│                                                      │                            │ don't    │
│                                                      │                            │ ask for  │
│                                                      │                            │ it.      │
│ 'model', 'prompt', 'max_tokens', 'messages', …       │ `!request body`!               │ Standard │
│                                                      │                            │ OpenAI   │
│                                                      │                            │ fields.  │
│                                                      │                            │ Codec    │
│                                                      │                            │ doesn't  │
│                                                      │                            │ touch    │
│                                                      │                            │ them.    │
│ 'Content-Type: application/json'                     │ request header             │ Standard │
│                                                      │                            │ HTTP for │
│                                                      │                            │ the JSON │
│                                                      │                            │ body.    │
│ 'Accept-Encoding: zstd, br, gzip, identity'          │ `!request header`!             │ The      │
│                                                      │                            │ client's │
│                                                      │                            │ compress │
│                                                      │                            │ ion      │
│                                                      │                            │ menu.    │
│                                                      │                            │ The      │
│                                                      │                            │ server's │
│                                                      │                            │ negotiat │
│                                                      │                            │ or picks │
│                                                      │                            │ per spec │
│                                                      │                            │ preferen │
│                                                      │                            │ ce 'zstd │
│                                                      │                            │ > br >   │
│                                                      │                            │ gzip >   │
│                                                      │                            │ identity │
│                                                      │                            │ ' and    │
│                                                      │                            │ picks    │
│                                                      │                            │ the      │
│                                                      │                            │ smallest │
│                                                      │                            │ valid    │
│                                                      │                            │ for the  │
│                                                      │                            │ response │
│                                                      │                            │ size.    │
│                                                      │                            │ v0.4.1   │
│                                                      │                            │ made     │
│                                                      │                            │ brotli   │
│                                                      │                            │ usable   │
│                                                      │                            │ across   │
│                                                      │                            │ all      │
│                                                      │                            │ sizes    │
│                                                      │                            │ and      │
│                                                      │                            │ landed   │
│                                                      │                            │ dict-zst │
│                                                      │                            │ d decode │
│                                                      │                            │ in every │
│                                                      │                            │ client — │
│                                                      │                            │ advertis │
│                                                      │                            │ ing the  │
│                                                      │                            │ full     │
│                                                      │                            │ menu is  │
│                                                      │                            │ now      │
│                                                      │                            │ correct  │
│                                                      │                            │ for      │
│                                                      │                            │ every    │
│                                                      │                            │ binding. │
│ 'Codec-Client-Version: 0.4'                          │ `!request header`!             │ v0.4     │
│                                                      │                            │ normativ │
│                                                      │                            │ e.       │
│                                                      │                            │ Client   │
│                                                      │                            │ advertis │
│                                                      │                            │ es the   │
│                                                      │                            │ maximum  │
│                                                      │                            │ spec     │
│                                                      │                            │ version  │
│                                                      │                            │ it can   │
│                                                      │                            │ correctl │
│                                                      │                            │ y        │
│                                                      │                            │ decode.  │
│                                                      │                            │ The      │
│                                                      │                            │ server   │
│                                                      │                            │ uses     │
│                                                      │                            │ this to  │
│                                                      │                            │ pick a   │
│                                                      │                            │ graceful │
│                                                      │                            │ downgrad │
│                                                      │                            │ e if the │
│                                                      │                            │ deployme │
│                                                      │                            │ nt       │
│                                                      │                            │ requires │
│                                                      │                            │ newer    │
│                                                      │                            │ features │
│                                                      │                            │ .        │
│                                                      │                            │ Omitting │
│                                                      │                            │ it on a  │
│                                                      │                            │ v0.4     │
│                                                      │                            │ deployme │
│                                                      │                            │ nt is    │
│                                                      │                            │ equivale │
│                                                      │                            │ nt to    │
│                                                      │                            │ claiming │
│                                                      │                            │ v0.3 —   │
│                                                      │                            │ you get  │
│                                                      │                            │ the v0.3 │
│                                                      │                            │ wire     │
│                                                      │                            │ surface. │
│ 'Codec-Tokenizer-Map: <id> sha256:<short>'           │ `!response header`!            │ Identifi │
│                                                      │                            │ es +     │
│                                                      │                            │ hash-pin │
│                                                      │                            │ s the    │
│                                                      │                            │ vocab    │
│                                                      │                            │ the      │
│                                                      │                            │ server   │
│                                                      │                            │ is       │
│                                                      │                            │ using.   │
│                                                      │                            │ Client   │
│                                                      │                            │ verifies │
│                                                      │                            │ before   │
│                                                      │                            │ decoding │
│                                                      │                            │ (mismatc │
│                                                      │                            │ h =      │
│                                                      │                            │ fail-fas │
│                                                      │                            │ t, stops │
│                                                      │                            │ KV-cache │
│                                                      │                            │ poisonin │
│                                                      │                            │ g).      │
│ 'Codec-Zstd-Dict: sha256:<short>'                    │ `!response header`!            │ Identifi │
│                                                      │                            │ es the   │
│                                                      │                            │ pre-trai │
│                                                      │                            │ ned zstd │
│                                                      │                            │ dict     │
│                                                      │                            │ when     │
│                                                      │                            │ 'Content │
│                                                      │                            │ -Encodin │
│                                                      │                            │ g:       │
│                                                      │                            │ zstd'.   │
│                                                      │                            │ Multiple │
│                                                      │                            │ dicts    │
│                                                      │                            │ per      │
│                                                      │                            │ tokenize │
│                                                      │                            │ r is     │
│                                                      │                            │ allowed; │
│                                                      │                            │ the      │
│                                                      │                            │ header   │
│                                                      │                            │ is how   │
│                                                      │                            │ the      │
│                                                      │                            │ client   │
│                                                      │                            │ picks    │
│                                                      │                            │ the      │
│                                                      │                            │ right    │
│                                                      │                            │ local    │
│                                                      │                            │ copy.    │
│ 'Content-Encoding: zstd | br | gzip | identity'      │ `!response header`!            │ The      │
│                                                      │                            │ encoding │
│                                                      │                            │ the      │
│                                                      │                            │ server   │
│                                                      │                            │ chose    │
│                                                      │                            │ from the │
│                                                      │                            │ request' │
│                                                      │                            │ s        │
│                                                      │                            │ 'Accept- │
│                                                      │                            │ Encoding │
│                                                      │                            │ '.       │
│ 'Codec-Safety-Policy-Id', 'Codec-Safety-Policy-Hash' │ `!response header`! (v0.4)     │ Identifi │
│                                                      │                            │ es the   │
│                                                      │                            │ safety   │
│                                                      │                            │ policy   │
│                                                      │                            │ the      │
│                                                      │                            │ server   │
│                                                      │                            │ enforced │
│                                                      │                            │ . Pairs  │
│                                                      │                            │ with the │
│                                                      │                            │ hash-anc │
│                                                      │                            │ hored    │
│                                                      │                            │ descript │
│                                                      │                            │ or at    │
│                                                      │                            │ '/.well- │
│                                                      │                            │ known/co │
│                                                      │                            │ dec/poli │
│                                                      │                            │ cies/<id │
│                                                      │                            │ >.json'. │
│ 'Codec-Min-Version', 'Codec-Required-Features'       │ response header on 426     │ Server's │
│                                                      │ (v0.4)                     │ enforcem │
│                                                      │                            │ ent      │
│                                                      │                            │ floor.   │
│                                                      │                            │ Returned │
│                                                      │                            │ when the │
│                                                      │                            │ client's │
│                                                      │                            │ 'Codec-C │
│                                                      │                            │ lient-Ve │
│                                                      │                            │ rsion'   │
│                                                      │                            │ falls    │
│                                                      │                            │ short.   │
│ 'finish_reason: "policy_violation"'                  │ `!in-frame field`! (v0.4)      │ Surfaces │
│                                                      │                            │ inside a │
│                                                      │                            │ 'CodecFr │
│                                                      │                            │ ame.fini │
│                                                      │                            │ sh_reaso │
│                                                      │                            │ n' when  │
│                                                      │                            │ a        │
│                                                      │                            │ server-s │
│                                                      │                            │ ide      │
│                                                      │                            │ safety   │
│                                                      │                            │ action   │
│                                                      │                            │ fired    │
│                                                      │                            │ mid-stre │
│                                                      │                            │ am. Not  │
│                                                      │                            │ a        │
│                                                      │                            │ header.  │
└──────────────────────────────────────────────────────┴────────────────────────────┴──────────┘

`!Why no 'Codec-Stream-Format' header?`! We considered it. The OpenAI request body already carries 'model' + 'prompt' + 'max_tokens' + 'stream', so making 'stream_format' a sibling field there was the smallest possible patch into upstream sglang / vllm / llama.cpp's request validator — one extra optional field, JSON-Schema-compatible, no header parser changes. The v0.5 plan covers a separate negotiation path (OPTIONS preflight + a persistent 'Codec-Session' token) that would let frequent agent-mesh clients drop most per-request bytes, but the per-request knob staying in the body is by design.

A complete v0.4.1 client request looks like:

`F999`*code (http):`*`f
`=
POST /v1/completions HTTP/1.1
Host: inference.example.com
Content-Type: application/json
Accept-Encoding: zstd, br, gzip, identity
Codec-Client-Version: 0.4

{
  "model": "Qwen/Qwen2.5-7B-Instruct",
  "prompt": "Explain entropy in one paragraph.",
  "stream": true,
  "stream_format": "msgpack",
  "max_tokens": 256
}
`=

And the response headers that come back:

`F999`*code (http):`*`f
`=
HTTP/1.1 200 OK
Content-Type: application/octet-stream
Content-Encoding: zstd
Codec-Tokenizer-Map: qwen2 sha256:62c2f94f...
Codec-Zstd-Dict: sha256:79b707ae...
Codec-Safety-Policy-Id: lab-vinez-prod
Codec-Safety-Policy-Hash: sha256:4d8a91...

<msgpack frames, zstd-compressed against the pinned dict>
`=

The two halves carry different things: the request-side headers + body declare what the client wants and can decode; the response headers tell the client what it actually got and how to interpret it.

>>>Headers — the full v0.4 / v0.4.1 floor

Every Codec response carries a small set of HTTP response headers that name the wire-level capabilities the server is using. v0.4 normalised the floor; v0.4.1 closed the cross-client decode gap. The normative table lives in 'spec/versions/v0.4.md' § Graceful downgrade (https://github.com/wdunn001/Codec/blob/main/spec/versions/v0.4.md). The short version:

┌────────────────────────────┬────────────────┬─────────────────────────────────────┬──────────┐
│ Header                     │ Direction      │ Introduced                          │ Purpose  │
├────────────────────────────┼────────────────┼─────────────────────────────────────┼──────────┤
│ 'Codec-Tokenizer-Map: <id> │ response       │ v0.2                                │ Identifi │
│ sha256:<short>'            │                │                                     │ es +     │
│                            │                │                                     │ hash-pin │
│                            │                │                                     │ s the    │
│                            │                │                                     │ vocab    │
│                            │                │                                     │ the IDs  │
│                            │                │                                     │ belong   │
│                            │                │                                     │ to.      │
│                            │                │                                     │ Receiver │
│                            │                │                                     │ verifies │
│                            │                │                                     │ before   │
│                            │                │                                     │ decoding │
│                            │                │                                     │ (mismatc │
│                            │                │                                     │ h is     │
│                            │                │                                     │ fail-fas │
│                            │                │                                     │ t —      │
│                            │                │                                     │ stops    │
│                            │                │                                     │ KV-cache │
│                            │                │                                     │ poisonin │
│                            │                │                                     │ g).      │
│ 'Codec-Zstd-Dict:          │ response       │ v0.3                                │ Identifi │
│ sha256:<short>'            │                │                                     │ es +     │
│                            │                │                                     │ hash-pin │
│                            │                │                                     │ s the    │
│                            │                │                                     │ pre-trai │
│                            │                │                                     │ ned zstd │
│                            │                │                                     │ dictiona │
│                            │                │                                     │ ry used  │
│                            │                │                                     │ to       │
│                            │                │                                     │ compress │
│                            │                │                                     │ the      │
│                            │                │                                     │ body.    │
│                            │                │                                     │ MUST be  │
│                            │                │                                     │ present  │
│                            │                │                                     │ when     │
│                            │                │                                     │ 'Content │
│                            │                │                                     │ -Encodin │
│                            │                │                                     │ g:       │
│                            │                │                                     │ zstd'.   │
│                            │                │                                     │ Multiple │
│                            │                │                                     │ dict     │
│                            │                │                                     │ versions │
│                            │                │                                     │ can      │
│                            │                │                                     │ coexist  │
│                            │                │                                     │ per      │
│                            │                │                                     │ tokenize │
│                            │                │                                     │ r; the   │
│                            │                │                                     │ header   │
│                            │                │                                     │ lets a   │
│                            │                │                                     │ deployme │
│                            │                │                                     │ nt       │
│                            │                │                                     │ rotate   │
│                            │                │                                     │ dicts    │
│                            │                │                                     │ without  │
│                            │                │                                     │ re-cutti │
│                            │                │                                     │ ng the   │
│                            │                │                                     │ map.     │
│ 'Content-Encoding: zstd |  │ response       │ v0.2 (gzip), v0.3 (zstd), v0.4 (br) │ The      │
│ br | gzip | identity'      │                │                                     │ negotiat │
│                            │                │                                     │ or       │
│                            │                │                                     │ honours  │
│                            │                │                                     │ spec     │
│                            │                │                                     │ preferen │
│                            │                │                                     │ ce order │
│                            │                │                                     │ 'zstd >  │
│                            │                │                                     │ br >     │
│                            │                │                                     │ gzip >   │
│                            │                │                                     │ identity │
│                            │                │                                     │ ' and    │
│                            │                │                                     │ picks    │
│                            │                │                                     │ the      │
│                            │                │                                     │ smallest │
│                            │                │                                     │ valid    │
│                            │                │                                     │ encoding │
│                            │                │                                     │ for the  │
│                            │                │                                     │ response │
│                            │                │                                     │ size.    │
│                            │                │                                     │ v0.4.1   │
│                            │                │                                     │ fixed a  │
│                            │                │                                     │ brotli   │
│                            │                │                                     │ per-chun │
│                            │                │                                     │ k-flush  │
│                            │                │                                     │ bug;     │
│                            │                │                                     │ brotli   │
│                            │                │                                     │ is now   │
│                            │                │                                     │ Pareto-f │
│                            │                │                                     │ ront for │
│                            │                │                                     │ 32–256-t │
│                            │                │                                     │ oken     │
│                            │                │                                     │ msgpack  │
│                            │                │                                     │ streams. │
│ 'Codec-Client-Version:     │ request        │ v0.4                                │ Client   │
│ <major.minor>'             │                │                                     │ advertis │
│                            │                │                                     │ es the   │
│                            │                │                                     │ maximum  │
│                            │                │                                     │ spec     │
│                            │                │                                     │ version  │
│                            │                │                                     │ it can   │
│                            │                │                                     │ correctl │
│                            │                │                                     │ y        │
│                            │                │                                     │ decode.  │
│                            │                │                                     │ Used by  │
│                            │                │                                     │ the      │
│                            │                │                                     │ server   │
│                            │                │                                     │ to pick  │
│                            │                │                                     │ a        │
│                            │                │                                     │ graceful │
│                            │                │                                     │ downgrad │
│                            │                │                                     │ e path.  │
│ 'Codec-Min-Version:        │ response (426) │ v0.4                                │ Server's │
│ <major.minor>'             │                │                                     │ minimum  │
│                            │                │                                     │ supporte │
│                            │                │                                     │ d spec   │
│                            │                │                                     │ version. │
│                            │                │                                     │ Returned │
│                            │                │                                     │ on the   │
│                            │                │                                     │ 426      │
│                            │                │                                     │ Upgrade  │
│                            │                │                                     │ Required │
│                            │                │                                     │ response │
│                            │                │                                     │ when the │
│                            │                │                                     │ client   │
│                            │                │                                     │ falls    │
│                            │                │                                     │ short.   │
│ 'Codec-Required-Features:  │ response (426) │ v0.4                                │ Comma-se │
│ <csv>'                     │                │                                     │ parated  │
│                            │                │                                     │ list of  │
│                            │                │                                     │ feature  │
│                            │                │                                     │ names    │
│                            │                │                                     │ the      │
│                            │                │                                     │ deployme │
│                            │                │                                     │ nt       │
│                            │                │                                     │ requires │
│                            │                │                                     │ (e.g.    │
│                            │                │                                     │ 'safety- │
│                            │                │                                     │ policy-e │
│                            │                │                                     │ nforceme │
│                            │                │                                     │ nt,      │
│                            │                │                                     │ mandator │
│                            │                │                                     │ y-classi │
│                            │                │                                     │ fier').  │
│                            │                │                                     │ Returned │
│                            │                │                                     │ with 426 │
│                            │                │                                     │ alongsid │
│                            │                │                                     │ e        │
│                            │                │                                     │ 'Codec-M │
│                            │                │                                     │ in-Versi │
│                            │                │                                     │ on'.     │
│ 'Codec-Safety-Policy-Id:   │ response       │ v0.4                                │ Identifi │
│ <id>'                      │                │                                     │ es the   │
│                            │                │                                     │ safety   │
│                            │                │                                     │ policy   │
│                            │                │                                     │ the      │
│                            │                │                                     │ server   │
│                            │                │                                     │ enforced │
│                            │                │                                     │ on this  │
│                            │                │                                     │ response │
│                            │                │                                     │ (operato │
│                            │                │                                     │ r-side   │
│                            │                │                                     │ categori │
│                            │                │                                     │ es,      │
│                            │                │                                     │ action   │
│                            │                │                                     │ types).  │
│                            │                │                                     │ Pairs    │
│                            │                │                                     │ with     │
│                            │                │                                     │ 'Codec-S │
│                            │                │                                     │ afety-Po │
│                            │                │                                     │ licy-Has │
│                            │                │                                     │ h'.      │
│ 'Codec-Safety-Policy-Hash: │ response       │ v0.4                                │ Hash of  │
│ sha256:<short>'            │                │                                     │ the      │
│                            │                │                                     │ sanitize │
│                            │                │                                     │ d        │
│                            │                │                                     │ descript │
│                            │                │                                     │ or       │
│                            │                │                                     │ served   │
│                            │                │                                     │ at       │
│                            │                │                                     │ '/.well- │
│                            │                │                                     │ known/co │
│                            │                │                                     │ dec/poli │
│                            │                │                                     │ cies/<id │
│                            │                │                                     │ >.json'. │
│                            │                │                                     │ The      │
│                            │                │                                     │ descript │
│                            │                │                                     │ or       │
│                            │                │                                     │ publishe │
│                            │                │                                     │ s the    │
│                            │                │                                     │ shape of │
│                            │                │                                     │ enforcem │
│                            │                │                                     │ ent but  │
│                            │                │                                     │ never    │
│                            │                │                                     │ operator │
│                            │                │                                     │ -interna │
│                            │                │                                     │ l        │
│                            │                │                                     │ banned-t │
│                            │                │                                     │ oken     │
│                            │                │                                     │ lists or │
│                            │                │                                     │ threshol │
│                            │                │                                     │ ds. Hash │
│                            │                │                                     │ mismatch │
│                            │                │                                     │ → client │
│                            │                │                                     │ refuses  │
│                            │                │                                     │ the      │
│                            │                │                                     │ stream.  │
│ 'finish_reason:            │ response       │ v0.4                                │ Surfaces │
│ "policy_violation"'        │                │                                     │ when a   │
│ (in-frame, not a header)   │                │                                     │ server-s │
│                            │                │                                     │ ide      │
│                            │                │                                     │ safety   │
│                            │                │                                     │ action   │
│                            │                │                                     │ fired    │
│                            │                │                                     │ mid-stre │
│                            │                │                                     │ am.      │
│                            │                │                                     │ Distinct │
│                            │                │                                     │ from     │
│                            │                │                                     │ 'length' │
│                            │                │                                     │ ,        │
│                            │                │                                     │ 'stop',  │
│                            │                │                                     │ 'tool_ca │
│                            │                │                                     │ ll'.     │
└────────────────────────────┴────────────────┴─────────────────────────────────────┴──────────┘

>>>>What v0.4.1 changed about the headers

• `!No new headers, no header bytes on the wire change.`! v0.4.1 is wire-additive over v0.4.
• `!Brotli per-chunk-flush bug fixed`! in both sglang + vllm forks — 'Content-Encoding: br' now compresses correctly across chunk boundaries instead of inflating small streams (was 1,159 B on a 975 B identity stream pre-fix; now Pareto-front for 32–256-token msgpack).
• `!'Codec-Zstd-Dict' decode now works across all 6 clients`! — pre-v0.4.1 only the Python client decoded the dict-zstd payload correctly; the other 5 either silently returned compressed bytes or threw "Dictionary mismatch". v0.4.1 ships real dict-zstd support in TS/Web, .NET, Rust, Java, and C, gated by a shared cross-client interop fixture. The header was always emitted correctly; the client side just couldn't act on it.
• `!llama.cpp gained brotli + zstd`! — pre-v0.4.1 the llama.cpp fork only supported identity + gzip. v0.4.1 adds 'codec_brotli_streamer' + 'codec_zstd_streamer' + the 'codec_zstd_dict_registry', so the same 'Content-Encoding' negotiation now works on all three engines. The '/codec/schema' endpoint also lands so the engine-acceptance pytest can probe llama.cpp the same way it probes sglang and vllm.

>>>>The 426 dance

A v0.4 server that requires a feature the client can't satisfy returns:

`=
HTTP/1.1 426 Upgrade Required
Codec-Min-Version: 0.4
Codec-Required-Features: safety-policy-enforcement, mandatory-classifier
Content-Type: application/json

{
  "error": "codec_version_required",
  "client_version": "0.3",
  "required_features": ["safety-policy-enforcement", "mandatory-classifier"],
  "deployment_id": "lab-vinez-prod"  // optional; operator may omit
}
`=

The client can upgrade and retry, or surface the requirement to the user. A v0.3 client that doesn't understand 426 just sees an HTTP error — graceful from the spec's perspective. The body's 'client_version' echoes what the server saw, so a misconfigured 'Codec-Client-Version' shows up at debug time.

>>>Polyglot bit-identical

The six reference implementations (TypeScript, Python, .NET, C, Rust, Java) all produce `!byte-identical`! wire output for the same inputs. The CI matrix encodes the same prompt with each binding and asserts a SHA match. If your seventh implementation matches the bytes from any one of those, you're correct.

-

`[<< Codec docs index`:/page/codecai/index.mu]

