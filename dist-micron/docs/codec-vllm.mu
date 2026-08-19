`F6cf`!codec-vllm (Docker)`!`f

`F999Pre-built vLLM server with the Codec patches applied and a control plane bolted on, in one GPU container. OpenAI-compatible.`f

`F999`*Server`*`f

-

'codec-vllm' is the easy way to stand up a Codec-speaking inference server on top of vLLM. It's a pre-built Docker image bundling:

• `!vLLM`! with the Codec patches already applied, token-native binary transport on '/v1/completions' and '/v1/chat/completions'.
• `!codec-supervisor`!, the same FastAPI admin sidecar as `[codec-sglang`:/page/codecai/docs/codec-sglang.mu], handling model uploads, Hugging Face pulls, hot-swaps, and reverse-proxying the vLLM backend.
• All upstream vLLM kernels (compiled '_C.abi3.so', '_flashmla_C.abi3.so', '_moe_C.abi3.so', etc.) intact, the codec patches are a surgical file overlay (9 changed '.py' files), not a recompile.

`F999┃ `!Why this base image?`! The codec routes need vLLM's per-endpoint module split (the post-refactor layout where '/v1/completions' and '/v1/chat/completions' are their own modules). The image is built on top of a vLLM build that has it.`f

>>>Quick start

`F999`*code (bash):`*`f
`=
docker run -d --gpus all \
  -p 8080:8080 \
  -v codec-models:/models \
  -v codec-hf-cache:/root/.cache/huggingface \
  -e CODEC_INITIAL_MODEL=Qwen/Qwen2.5-0.5B-Instruct \
  --shm-size 8g --ipc host \
  wdunn001/codec-vllm:latest
`=

The container boots the supervisor on ':8080', which then launches the vLLM backend with 'Qwen/Qwen2.5-0.5B-Instruct' (or whatever you set in 'CODEC_INITIAL_MODEL'). First boot pulls weights from Hugging Face into the persistent cache volume.

`F999┃ `!GPU prereq:`! NVIDIA Container Toolkit installed, and '--gpus all' (or a specific device list). The image targets recent CUDA. The '--ipc host' flag is required for vLLM's shared-memory CUDA IPC.`f

>>>>First request

`F999`*code (bash):`*`f
`=
# OpenAI-compatible (JSON-SSE)
curl http://localhost:8080/v1/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"Qwen/Qwen2.5-0.5B-Instruct","prompt":"Hello","max_tokens":20}'

# Codec wire format - msgpack frames of token IDs with dict-zstd
curl http://localhost:8080/v1/completions \
  -H "Content-Type: application/json" \
  -H "Accept-Encoding: zstd, br, gzip" \
  -d '{"model":"Qwen/Qwen2.5-0.5B-Instruct","prompt":"Hello","max_tokens":20,"stream":true,"stream_format":"msgpack"}'
`=

Unlike sglang, vLLM `!strictly validates the 'model' field`!. Pass the loaded model id, not a placeholder. Use '/admin/status' to check the current model.

The codec patches on vLLM ship the full compression stack (gzip + brotli + dict-zstd) and negotiate via 'Accept-Encoding' per the spec preference order 'zstd > br > gzip > identity'. All 6 Codec clients (TS/Web, Python, .NET, Rust, Java, C) decode every encoding byte-identically. On Qwen2.5-0.5B-Instruct at 2 K tokens the dict-zstd path lands at `!3.9 KB`! (~`!137×`! smaller than the 518 KB JSON-SSE baseline; the ratio is content-bound at this engine because vLLM's sampler emits less compressible output at temp 0; see the synthetic-stream cells for the protocol-only headline).

>>>Run your own model

Three ways, same surface as codec-sglang:

>>>>1. Override 'CODEC_INITIAL_MODEL' at 'docker run' time

Any HF repo id:

`F999`*code (bash):`*`f
`=
docker run --gpus all -p 8080:8080 \
  -e CODEC_INITIAL_MODEL=meta-llama/Llama-3.1-8B-Instruct \
  -e HF_TOKEN=hf_xxxxx \
  -v hf-cache:/root/.cache/huggingface \
  --shm-size 8g --ipc host \
  wdunn001/codec-vllm:latest
`=

>>>>2. Bind-mount a local checkpoint

`F999`*code (bash):`*`f
`=
docker run --gpus all -p 8080:8080 \
  -e CODEC_INITIAL_MODEL=/models/my-finetune \
  -v /path/to/my-finetune:/models/my-finetune:ro \
  --shm-size 8g --ipc host \
  wdunn001/codec-vllm:latest
`=

>>>>3. Hot-swap via the admin API

`F999`*code (bash):`*`f
`=
curl -X POST http://localhost:8080/admin/load \
  -H "Content-Type: application/json" \
  -d '{"name":"Qwen/Qwen2.5-7B-Instruct","allow_remote":true}'
`=

Pass 'CODEC_BACKEND_ARGS' to tune vLLM ('--gpu-memory-utilization 0.9 --max-model-len 4096 --tensor-parallel-size 2 ...'). Defaults are vLLM-shaped (not sglang-shaped):

┌───────────────────────┬───────────────────────────────────────────────────────────┬──────────┐
│ Variable              │ Default                                                   │ Effect   │
├───────────────────────┼───────────────────────────────────────────────────────────┼──────────┤
│ 'CODEC_INITIAL_MODEL' │ 'Qwen/Qwen2.5-0.5B-Instruct'                              │ Model to │
│                       │                                                           │ load on  │
│                       │                                                           │ first    │
│                       │                                                           │ boot. HF │
│                       │                                                           │ id,      │
│                       │                                                           │ local    │
│                       │                                                           │ name, or │
│                       │                                                           │ absolute │
│                       │                                                           │ path.    │
│ 'CODEC_BACKEND_ARGS'  │ '--gpu-memory-utilization 0.85 --max-model-len 2048       │ Verbatim │
│                       │ --dtype auto'                                             │ argument │
│                       │                                                           │ s to     │
│                       │                                                           │ 'python3 │
│                       │                                                           │ -m       │
│                       │                                                           │ vllm.ent │
│                       │                                                           │ rypoints │
│                       │                                                           │ .openai. │
│                       │                                                           │ api_serv │
│                       │                                                           │ er'.     │
│ 'CODEC_PORT'          │ '8080'                                                    │ Supervis │
│                       │                                                           │ or port. │
│ 'HF_TOKEN'            │ `*(unset)`*                                                   │ Required │
│                       │                                                           │ only for │
│                       │                                                           │ gated HF │
│                       │                                                           │ models.  │
└───────────────────────┴───────────────────────────────────────────────────────────┴──────────┘

>>>Admin API

Identical to `[codec-sglang`:/page/codecai/docs/codec-sglang.mu], the supervisor is backend-agnostic. '/health', '/admin/status', '/admin/models', '/admin/models/pull', '/admin/models/upload', '/admin/load', '/admin/stop'. Anything not under '/admin' proxies to vLLM.

>>>Source & links

• Image: 'wdunn001/codec-vllm:latest' (https://hub.docker.com/r/wdunn001/codec-vllm) on Docker Hub.
• Source: github.com/wdunn001/codec-supervisor (https://github.com/wdunn001/codec-supervisor) (see 'Dockerfile.vllm').

>>>See also

• `[codec-sglang`:/page/codecai/docs/codec-sglang.mu], same image story, sglang backend.
• `[codec-llamacpp`:/page/codecai/docs/codec-llamacpp.mu], same image story, llama.cpp backend.
• `[TypeScript`:/page/codecai/docs/typescript.mu], `[Python`:/page/codecai/docs/python.mu], `[.NET`:/page/codecai/docs/dotnet.mu], `[C`:/page/codecai/docs/c.mu], `[Rust`:/page/codecai/docs/rust.mu], `[Java`:/page/codecai/docs/java.mu] walkthroughs, client-side patterns.

-

`[<< Codec docs index`:/page/codecai/index.mu]

