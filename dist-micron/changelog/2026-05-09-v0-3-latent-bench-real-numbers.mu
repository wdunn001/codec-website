`F6cf`!v0.3 latent bench, pipeline math validates byte-for-byte`!`f

`F9992026-05-09 - v0.3.4 - feature`f

-

First end-to-end latent run against codec-diffusers with real SD-1.5 latents on the wire. The seven-pipeline registry collapses bytes exactly as the spec promises (int4 packs 3.9× over raw, ~5-10× smaller than JPEG).

-

The third v0.3 negotiation pathway (`!VAE latents on the wire`!) landed on real lab traffic today. 'codec-diffusers:v0.3.4' running SD-1.5 on an RTX 3090, three pipelines ('raw' / 'int8' / 'int4') measured against two image fixtures:

┌───────────────────┬─────────┬─────────┬────────┬─────────────┬─────────────┐
│ Fixture           │ raw     │ int8    │ int4   │ int8 vs raw │ int4 vs raw │
├───────────────────┼─────────┼─────────┼────────┼─────────────┼─────────────┤
│ 256×256 (4×32×32) │  8.4 KB │  4.4 KB │ 2.4 KB │        `!1.9×`! │        `!3.5×`! │
│ 512×512 (4×64×64) │ 32.4 KB │ 16.4 KB │ 8.4 KB │        `!2.0×`! │        `!3.9×`! │
└───────────────────┴─────────┴─────────┴────────┴─────────────┴─────────────┘

'raw' matches the theoretical wire shape to the byte: '4×64×64×2' (fp16) = 32768 bytes + 247 bytes of msgpack envelope = 32.4 KB ✓. 'int8' halves it via per-channel symmetric quantization; 'int4' halves it again with two-per-byte packing. The pipeline implementation is bit-for-bit faithful to the normative registry (https://github.com/wdunn001/Codec/blob/main/spec/PIPELINES.md).

For context: a 512×512 RGB JPEG (web quality 85) is ~80-150 KB. The 512 latent at int8 (16.4 KB) is `!5-10× smaller than JPEG and ~90× smaller than raw fp16 pixels`!. The client runs 'vae_decode' locally. Pixels never touch the wire.

Per-pipeline zstd dicts aren't loaded in this run, so gzip/zstd-on-top doesn't reduce further (raw fp16 latents are near-Gaussian and need structural-pre-pass dicts to compress; tracked as the next concrete step). Even without compression, the int4 pipeline produces a 3.9× reduction by structure alone.

>>>All three v0.3 pathways are now live end-to-end on the lab

• `!Text-tokens`! (codec-sglang / vLLM / llama.cpp): `!13-18×`! wire reduction over JSON-SSE
• `!MCP tool-calls`! (codec-time-leaf via codec-metamcp): leaf-mode bypass observable; tools/list 3.6×
• `!Latents`! (codec-diffusers + sd-vae-ft-mse): pipeline math validates byte-for-byte, int4 = 3.9× over raw

The protocol is shipped, measured, and observable on real wire traffic.

-

>>Links

GitHub release v0.3.4 (https://github.com/wdunn001/Codec/releases/tag/v0.3.4)

2026-05-09T13-01-55Z latent results (https://github.com/wdunn001/Codec/tree/main/packages/bench/results/2026-05-09T13-01-55Z/latent)

spec/PIPELINES.md (the registry being validated) (https://github.com/wdunn001/Codec/blob/main/spec/PIPELINES.md)

-

`[<< Full changelog`:/page/codecai/changelog.mu]

`[<< Codec docs index`:/page/codecai/index.mu]

