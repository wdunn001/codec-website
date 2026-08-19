`F6cf`!Cross-stack bench cleanup, 24/24 unanimous on every engine`!`f

`F9992026-05-10 - v0.3.2 - improvement`f

-

Re-ran the full cross-stack matrix after patching two bench-driver bugs (C/TS token-decode fallback, vllm REPS=1 noise). All three engines × six client languages now produce byte-identical Codec frames per cell, including vllm, which previously read as 0/24 unanimous in the post-mortem.

-

The 2026-05-08 cross-stack run had a §7 post-mortem flagging three sources of variance; vllm reading as 0/24 unanimous on Codec cells was the loudest. Ran it down to three issues:

1. C and TS demos were emitting 'tokens_emitted=0' for compressed cells (the 'tokens' field was only populated on 'identity' decode), which threw off the unanimity check.
2. vllm at 2 K tokens has ~10-20 % wire-byte variance from non-deterministic batching even at temperature=0; needs ≥2 reps to land a stable median.
3. JSON-SSE rows have 10-16 B per-client framing-accounting drift that's structural, not noise.

Patches shipped (commits '7c12286' (https://github.com/wdunn001/Codec/commit/7c12286), 'eb574b6' (https://github.com/wdunn001/Codec/commit/eb574b6)) and the bench re-ran on the same lab box (vinez@192.168.1.88, 2× RTX 3090).

`!Cross-language unanimity, all engines:`!

┌───────────┬───────────────────────┬──────────────────────────────────────────┐
│ Engine    │ Codec cells unanimous │ Notes                                    │
├───────────┼───────────────────────┼──────────────────────────────────────────┤
│ sglang    │                 `!24/24`! │ clean                                    │
│ vllm      │                 `!24/24`! │ was 0/24 in earlier run                  │
│ llama.cpp │                 `!24/24`! │ only ≤5 B drift remains on JSON-SSE rows │
└───────────┴───────────────────────┴──────────────────────────────────────────┘

`!Headline reduction at 2 K tokens (msgpack + gzip, Python row):`!

┌───────────┬──────────┬──────────────────────┬───────────┐
│ Engine    │ JSON-SSE │ Codec msgpack + gzip │ Reduction │
├───────────┼──────────┼──────────────────────┼───────────┤
│ sglang    │ 485.2 KB │                354 B │    `!1,404×`! │
│ vllm      │ 517.8 KB │              3,874 B │      `!137×`! │
│ llama.cpp │ 529.2 KB │              16.1 KB │       `!33×`! │
└───────────┴──────────┴──────────────────────┴───────────┘

The 'Benchmarks' panel on the front page now points at the new run and the engineRows numbers are refreshed accordingly.

-

>>Links

MATRIX.md, 2026-05-09T17-09-35Z (https://github.com/wdunn001/Codec/blob/main/packages/bench/results/2026-05-09T17-09-35Z/MATRIX.md)

Earlier post-mortem (now resolved) (https://github.com/wdunn001/Codec/blob/main/packages/bench/results/2026-05-08T01-15-02Z/MATRIX.md)

Token-decode fix (commit) (https://github.com/wdunn001/Codec/commit/7c12286)

-

`[<< Full changelog`:/page/codecai/changelog.mu]

`[<< Codec docs index`:/page/codecai/index.mu]

