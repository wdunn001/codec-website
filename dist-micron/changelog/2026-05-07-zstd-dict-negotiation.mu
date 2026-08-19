`F6cf`!zstd dictionary negotiation via Codec-Zstd-Dict header`!`f

`F9992026-05-07 - improvement`f

-

Servers advertise the active zstd dict on the wire; clients fetch it once and decompress every frame against it. Identification by sha256, not URL.

-

The pre-trained zstd dictionary mechanism just got the missing piece: a 'Codec-Zstd-Dict: sha256:…' response header so a client can verify the dict it loaded matches what the server compressed against.

A maintainer publishes 'zstd_dictionaries[]' entries on their tokenizer map, keyed by wire format (msgpack / protobuf) for text streams, or by '(format, pipeline)' for v0.3 latent streams. A client loads the matching dict once at session open and reuses it for every frame. Mismatched dict ID is a fail-closed wire error.

Latent dicts are keyed by '(format, pipeline)' because the byte distribution of 'int8' latents is wildly different from 'delta+int8' residuals. A single dict can't compress both. The map schema enforces this; servers MUST NOT respond with 'Content-Encoding: zstd' unless they have a dict whose '(format, pipeline)' matches the response.

-

>>Links

GitHub release v0.2.5 (https://github.com/wdunn001/Codec/releases/tag/v0.2.5)

tokenizer-map.schema.json zstd_dictionaries[] (https://github.com/wdunn001/Codec/blob/main/spec/tokenizer-map.schema.json)

-

`[<< Full changelog`:/page/codecai/changelog.mu]

`[<< Codec docs index`:/page/codecai/index.mu]

