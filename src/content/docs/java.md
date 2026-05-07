---
title: Java — codec
description: JDK 17+ binding. java.net.http.HttpClient, Iterator + Flow.Publisher streams, Jackson JSON, msgpack-java for frames. Maven-ready.
section: Frameworks
order: 6
---

`codec` (Maven artifact `io.github.wdunn001:codec`) is the Java binding. Targets **JDK 17+** so it has access to records, sealed types, and the modern `java.net.http.HttpClient`. Streaming is exposed both as `Iterator<CodecFrame>` (synchronous, the canonical shape) and as `Flow.Publisher<CodecFrame>` (reactive callers).

## Install

```xml
<dependency>
    <groupId>io.github.wdunn001</groupId>
    <artifactId>codec</artifactId>
    <version>0.1.0</version>
</dependency>
```

(Maven Central publish queued. Until then, `mvn install` from `packages/java/` to a local repo.)

The library brings two transitive dependencies: `com.fasterxml.jackson.core:jackson-databind` for map JSON and `org.msgpack:msgpack-core` for frame parsing. Everything else is JDK built-in &mdash; sha256 via `java.security.MessageDigest`, regex with `Pattern.UNICODE_CHARACTER_CLASS`, HTTP via `java.net.http.HttpClient`.

## The four-step shape

```java
import ai.codec.*;
// 1. fetch + verify map        → MapLoader.load(...)
// 2. send                      → HttpClient (JDK)
// 3. stream → frames           → StreamDecoder.decodeMsgpackStream(...)
// 4. IDs → text                → Detokenizer.render(...)
```

### 1. Load the vocab map

```java
TokenizerMap map = MapLoader.load(new LoadOptions.Builder()
    .url("https://cdn.jsdelivr.net/gh/wdunn001/codec-maps/maps/qwen/qwen2.json")
    .hash("sha256:887311099cdc09e7022001a01fa1da396750d669b7ed2c242a000b9badd09791")
    .build());
```

The hash is verified against the bytes on the wire before the JSON parses. Mismatch throws `TokenizerMapHashMismatchException`. For an async fetch, use `MapLoader.loadAsync(...)` — returns a `CompletableFuture<TokenizerMap>`.

### 2. Send a request

```java
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;

HttpClient http = HttpClient.newBuilder()
    .connectTimeout(Duration.ofSeconds(10))
    .build();

String body = """
    {"model":"Qwen/Qwen2.5-7B-Instruct",
     "prompt":"Explain entropy in one paragraph.",
     "stream_format":"msgpack",
     "max_tokens":256}
    """;

HttpRequest req = HttpRequest.newBuilder()
    .uri(URI.create("http://localhost:8000/v1/completions"))
    .header("Content-Type", "application/json")
    .header("Accept-Encoding", "gzip")
    .POST(HttpRequest.BodyPublishers.ofString(body))
    .build();

HttpResponse<java.io.InputStream> resp = http.send(req,
    HttpResponse.BodyHandlers.ofInputStream());
```

`HttpResponse.BodyHandlers.ofInputStream()` is the JDK equivalent of "don't buffer the body" — exactly what streaming needs.

### 3. Decode the binary stream

```java
import java.util.Iterator;

Iterator<CodecFrame> frames = StreamDecoder.decodeMsgpackStream(resp.body());
while (frames.hasNext()) {
    CodecFrame frame = frames.next();
    // frame.ids():          int[]
    // frame.done():         boolean
    // frame.finishReason(): String  (nullable)
}
```

For reactive callers there's a `Flow.Publisher<CodecFrame>` variant:

```java
import java.util.concurrent.Flow;

Flow.Publisher<CodecFrame> publisher =
    StreamDecoder.publishMsgpack(resp.body());
publisher.subscribe(mySubscriber);
```

`decodeProtobufStream` / `publishProtobuf` cover the length-prefixed protobuf wire mode.

### 4. Detokenize at the edge

```java
Detokenizer detok = new Detokenizer(map);

while (frames.hasNext()) {
    CodecFrame frame = frames.next();
    String text = detok.render(frame.ids(),
        new DetokenizeOptions(/* partial */ !frame.done(), /* renderSpecial */ false));
    System.out.print(text);
}
```

`Detokenizer` is **stateful** — partial multi-byte UTF-8 sequences buffer across `render()` calls when `partial=true`. A 4-byte 🚀 split across two frames round-trips identically. Call `detok.reset()` between unrelated streams.

## Encoding (sending IDs, not text)

```java
BPETokenizer tok = new BPETokenizer(map);
int[] ids = tok.encode("System: be concise.\nUser: what's BPE?");

ObjectMapper json = new ObjectMapper();
String body = json.writeValueAsString(Map.of(
    "model",         "Qwen/Qwen2.5-7B-Instruct",
    "prompt",        ids,           // int[] — the server reads as token IDs
    "stream_format", "msgpack",
    "max_tokens",    256
));
```

Greedy by merge priority — not left-to-right. Bit-identical to the upstream tokenizer across all reference bindings.

## Watching for tool calls

```java
ToolWatcher watcher = new ToolWatcher(map, "<tool_call>", "</tool_call>");

while (frames.hasNext()) {
    CodecFrame frame = frames.next();
    for (WatcherEvent ev : watcher.feed(frame.ids())) {
        switch (ev.kind()) {
            case PASSTHROUGH -> forward(ev.ids());
            case CAPTURED    -> {
                int[] ids = toIntArray(ev.ids());            // long[] → int[]
                String text = detok.render(ids, new DetokenizeOptions(false, false));
                ToolCall call = parseToolCall(text);
                dispatch(call.name(), call.args());
            }
        }
    }
}
```

The watcher's IDs are `long[]` because Java has no unsigned 32-bit primitive — `long` losslessly carries the full uint32 range. A single compare per token; no detokenization on the hot path. See [Tool calling](/docs/tool-calling/).

## Translating across vocabularies

```java
TokenizerMap qwen  = MapLoader.load(new LoadOptions.Builder()
    .url("https://cdn.jsdelivr.net/gh/wdunn001/codec-maps/maps/qwen/qwen2.json")
    .hash("sha256:887311099cdc09e7022001a01fa1da396750d669b7ed2c242a000b9badd09791")
    .build());
TokenizerMap llama = MapLoader.load(new LoadOptions.Builder()
    .url("https://cdn.jsdelivr.net/gh/wdunn001/codec-maps/maps/meta-llama/llama-3.json")
    .hash("sha256:79b707aea8c2b41c2883ec7913b0c4a0c880044ac844d89a9a03e779eb92db04")
    .build());

Translator tr = new Translator(qwen, llama);

while (frames.hasNext()) {
    CodecFrame frame = frames.next();
    int[] llamaIds = tr.translate(frame.ids(), !frame.done());
    forwardToLlama(llamaIds);
}
```

See [Translator](/docs/translator/).

## Spring / reactive integration

For a Spring WebFlux endpoint that proxies a Codec stream out as SSE:

```java
@PostMapping(value = "/chat", produces = MediaType.TEXT_EVENT_STREAM_VALUE)
public Flux<String> chat(@RequestBody ChatRequest req) {
    Detokenizer detok = new Detokenizer(map);
    return Flux.from(StreamDecoder.publishMsgpack(openCodecStream(req)))
               .map(frame -> detok.render(frame.ids(),
                       new DetokenizeOptions(!frame.done(), false)));
}
```

`Flow.Publisher` adapts to Reactor `Flux` via `Flux.from(...)`. RxJava and Mutiny work the same way through their respective `Publisher` adapters.

## Production checklist

- **Pin the map hash** in `LoadOptions`.
- **`HttpResponse.BodyHandlers.ofInputStream()`** — anything else buffers the whole response.
- **Reuse `HttpClient` and `Detokenizer`.** Both are designed for reuse; new `Detokenizer` instances mid-stream drop the UTF-8 buffer. Call `reset()` at stream boundaries instead.
- **Maven Central** is the target — until publish, install locally with `mvn install` from `packages/java/`.

## See also

- [Tool calling](/docs/tool-calling/)
- [Translator](/docs/translator/)
- [Maven Central listing](https://central.sonatype.com/artifact/io.github.wdunn001/codec) (publish queued)
- [packages/java/ on GitHub](https://github.com/wdunn001/Codec/tree/main/packages/java)
