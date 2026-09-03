---
title: C (libcodec)
description: C99 reference implementation. CMake, single header, no dependencies, ABI-stable struct layout. For embedded clients and FFI bridges.
section: Frameworks
order: 4
---

`libcodec` is the C99 reference implementation. Use it when you're embedding Codec in a runtime that doesn't have a managed binding yet (Rust via `bindgen`, Go via `cgo`, embedded environments) or when you need an ABI-stable surface to FFI from.

The library is small (~30 KB stripped binary on x86-64), depends only on the C standard library, and exposes a single header.

## Add to your project

### CMake (recommended)

```cmake
include(FetchContent)
FetchContent_Declare(codec
  GIT_REPOSITORY https://github.com/wdunn001/Codec.git
  GIT_TAG        main
  SOURCE_SUBDIR  packages/c
)
FetchContent_MakeAvailable(codec)

target_link_libraries(your_app PRIVATE codec::codec)
```

### vcpkg / system install

The package builds with a standard `cmake --build && cmake --install`. The C package's [README](https://github.com/wdunn001/Codec/tree/main/packages/c) has up-to-date paths.

## The C API in one header

```c
#include <codec/codec.h>
```

Headline types:

| Type | What it is |
|---|---|
| `codec_tokenizer_map_t` | Vocab map handle (opaque). |
| `codec_detokenizer_t`   | Stateful IDs → UTF-8 buffer. |
| `codec_msgpack_stream_t`| Incremental msgpack frame parser. |
| `codec_tool_watcher_t`  | Region detector over token IDs. |
| `codec_frame_t`         | Owned struct: `{ids, ids_len, done, finish_reason}`. |
| `codec_status_t`        | Return codes (`CODEC_OK`, `CODEC_ENOMEM`, etc). |

**Memory model.** Functions that produce heap allocations document the ownership in the header (`out_text` is malloc'd; caller frees). The opaque types each have a paired `_free`. There are no global allocators. If you need an arena, wrap the `_new` calls.

## Loading a vocab map

```c
char *json = NULL;
size_t json_len = 0;
read_whole_file("qwen2.json", &json, &json_len); /* your code */

/* Constant-time SHA-256 verification, panic if it doesn't match. */
codec_status_t st = codec_map_verify_sha256(
    json, json_len,
    "sha256:887311099cdc09e7022001a01fa1da396750d669b7ed2c242a000b9badd09791"
);
if (st != CODEC_OK) { fprintf(stderr, "map hash mismatch\n"); return 1; }

codec_tokenizer_map_t *map = NULL;
st = codec_map_from_json(json, json_len, &map);
if (st != CODEC_OK) { fprintf(stderr, "map parse failed\n"); return 1; }

free(json); /* the parsed map owns its own copy */
```

Unlike the higher-level bindings, `libcodec` does not fetch over HTTP. You bring the bytes. This keeps the dependency surface to libc.

## Decoding a stream

```c
#include <codec/codec.h>

/* HTTP body chunks come from your HTTP client of choice (libcurl, picohttp, etc.). */
codec_msgpack_stream_t *stream = NULL;
codec_msgpack_stream_new(&stream);

codec_detokenizer_t *detok = NULL;
codec_detokenizer_new(map, &detok);

while (have_more_http_chunks()) {
    const uint8_t *chunk; size_t chunk_len;
    next_http_chunk(&chunk, &chunk_len);
    codec_msgpack_stream_feed(stream, chunk, chunk_len);

    codec_frame_t frame;
    while (codec_msgpack_stream_next(stream, &frame) == CODEC_OK) {
        char *text = NULL;
        size_t text_len = 0;
        codec_detokenize_opts_t opts = {
            .partial         = !frame.done,
            .render_special  = false,
        };
        codec_detokenizer_render(detok, frame.ids, frame.ids_len, opts, &text, &text_len);

        if (text) {
            fwrite(text, 1, text_len, stdout);
            free(text);
        }

        bool done = frame.done;
        codec_frame_destroy(&frame);
        if (done) goto end;
    }
}

end:
codec_detokenizer_free(detok);
codec_msgpack_stream_free(stream);
```

This is `packages/c/examples/stream_decode.c` boiled down. The runnable version (with libcurl wired in) lives in the repo.

## Watching for tool calls

```c
codec_tool_watcher_t *w = NULL;
codec_tool_watcher_new(map, "<tool_call>", "</tool_call>", &w);

codec_frame_t frame;
while (codec_msgpack_stream_next(stream, &frame) == CODEC_OK) {
    codec_watcher_event_t *events = NULL;
    size_t n = 0;
    codec_tool_watcher_feed(w, frame.ids, frame.ids_len, &events, &n);

    for (size_t i = 0; i < n; i++) {
        if (events[i].kind == CODEC_WATCHER_PASSTHROUGH) {
            forward(events[i].ids, events[i].ids_len);
        } else { /* CODEC_WATCHER_CAPTURED */
            dispatch_tool_with_ids(events[i].ids, events[i].ids_len);
        }
    }

    free(events);
    codec_frame_destroy(&frame);
}

codec_tool_watcher_free(w);
```

This hot loop is the one we benchmark at **0.61 ns/token**. On a 1M-token stream that's 0.61 ms total. The text-path equivalent (detokenize + regex) takes 60.4 ms. See [`bench_watcher.c`](https://github.com/wdunn001/Codec/blob/main/packages/c/examples/bench_watcher.c) for the full microbench harness.

## Encoding (text &rarr; IDs)

libcodec ships a runtime BPE encoder bit-identical to the higher-level bindings. Pretok runs on the regex-free [pre-tokenizer program](https://github.com/wdunn001/Codec/blob/main/spec/PRETOKENIZER_PROGRAM.md) using generated Unicode tables, **no PCRE2 dependency**.

```c
codec_bpe_encoder_t *enc = NULL;
codec_bpe_encoder_new(map, &enc);

uint32_t *ids = NULL;
size_t ids_len = 0;
const char *text = "System: be concise.";
codec_bpe_encode(enc, text, strlen(text), &ids, &ids_len);

/* ... use ids ... */

free(ids);
codec_bpe_encoder_free(enc);
```

Output matches the upstream model's tokenizer to the exact ID sequence (verified against the real Qwen-2 tokenizer fixture under `test/test_bpe.c`).

The companion [`codec_translator`](https://github.com/wdunn001/Codec/blob/main/packages/c/src/translator.c) does cross-vocab handoff (`ids_A → utf-8 → ids_B`) the same way the other Codec clients do, streaming-safe with word-boundary buffering.

### Optional at build time: opt out for embedded / IoT (~25 KB lighter)

Most embedded / IoT consumers of libcodec only need the decode side: firmware that displays AI responses, IoT endpoints that ship pre-cached IDs via the [`@codecai/tool-kit`](/docs/codec-tool-kit/) pattern, observers / middleware that route raw token streams without BPE. For those callers, the BPE encoder + Translator + pretok runtime + Unicode tables are dead weight.

Build with `-DCODEC_WITH_BPE_ENCODER=OFF` to drop ~25 KB of compiled code + data:

```bash
cmake -S . -B build \
  -DCMAKE_BUILD_TYPE=MinSizeRel \
  -DCODEC_WITH_BPE_ENCODER=OFF
```

The decode-side API surface (Detokenizer, ToolWatcher, stream decoders, frame codec, compression, safety-policy) is unchanged. The public-API symbols for the dropped surface still link (`codec_bpe_encoder_new` / `codec_bpe_encode` / `codec_translator_new` / `codec_translator_translate` / `codec_pretok_run_program` and friends return `CODEC_ERR_NOT_BUILT` consistently). Consumer code needs no `#ifdef` guards.

| Build | `libcodec.a` size (x86-64 Release) |
|---|---|
| Default (encoder ON) | 128,278 bytes |
| `-DCODEC_WITH_BPE_ENCODER=OFF` | **103,178 bytes** (~25 KB lighter) |

Cortex-M / Xtensa / RISC-V cross-compiles save proportionally more after `-Os` strips the Unicode tables.

## When to use libcodec specifically

- **Embedded / cross-compile targets** such as routers, smart speakers, and microcontrollers with enough RAM for a vocab map (LoRaWAN / NB-IoT endpoints typically pair with the decode-only build + a [`@codecai/tool-kit`](/docs/codec-tool-kit/) bolt-on for the encode side).
- **FFI from another runtime** (Rust crate via `bindgen`, Go via `cgo`, Lua via FFI). The C ABI is the lingua franca.
- **You want the smallest possible footprint.** libcodec is < 30 KB stripped (decode-only) / ~50 KB stripped (full BPE). No JIT, no GC, no runtime.

For day-to-day server work, prefer one of the higher-level bindings.

## See also

- [stream_decode.c](https://github.com/wdunn001/Codec/blob/main/packages/c/examples/stream_decode.c), the canonical runnable example.
- [bench_watcher.c](https://github.com/wdunn001/Codec/blob/main/packages/c/examples/bench_watcher.c), microbench harness.
- [packages/c/ on GitHub](https://github.com/wdunn001/Codec/tree/main/packages/c), full source.
