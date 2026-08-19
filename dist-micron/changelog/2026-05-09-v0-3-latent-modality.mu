`F6cf`!v0.3 latent modality (VAE latents on the wire)`!`f

`F9992026-05-09 - v0.3.0 - feature`f

-

Image and video diffusion models now stream VAE latents instead of decoded pixels. 48× smaller wire weight, decode at the leaf.

-

Codec v0.3 extends the framing surface from text-tokens to `!VAE latents`!. Two new engine forks ship as pre-built Docker images:

• `['codec-comfyui'`:/page/codecai/docs/codec-comfyui.mu], ComfyUI with the v0.3 latent transport patch. Production image-gen with the full ComfyUI workflow surface.
• `['codec-diffusers'`:/page/codecai/docs/codec-diffusers.mu], the HuggingFace diffusers reference path. Doubles as the bench/golden perceptual-conformance reference for every Codec latent client.

Same wire shape; same registry; same 'LatentStreamDecoder' in '@codecai/web' (https://www.npmjs.com/package/@codecai/web) handles both.

A 512×512 RGB frame at fp16 is ~1.5 MB; the SD-1 latent that produced it is 4×64×64 fp16 = 32 KB, a `!48× reduction`!. Per-channel int8 quantization on top, and (for video) delta-coding against keyframes, take it further. The client runs 'vae_decode' locally. Pixels never touch the wire.

-

>>Links

GitHub release v0.3.0 (https://github.com/wdunn001/Codec/releases/tag/v0.3.0)

codec-comfyui docs (https://codecai.net/docs/codec-comfyui/)

codec-diffusers docs (https://codecai.net/docs/codec-diffusers/)

PROTOCOL.md § Latent Modality (https://github.com/wdunn001/Codec/blob/main/spec/PROTOCOL.md#latent-modality-v03)

-

`[<< Full changelog`:/page/codecai/changelog.mu]

`[<< Codec docs index`:/page/codecai/index.mu]

