# codec-website

Marketing site for [Codec](https://github.com/wdunn001/Codec), a token-native
binary transport protocol for AI APIs. Lives at
[codecai.net](https://codecai.net).

Built with **Astro** (zero JS by default), deployed as a static-nginx Docker
container behind the host's existing
[jwilder/nginx-proxy](https://github.com/nginx-proxy/nginx-proxy) +
[letsencrypt-nginx-proxy-companion](https://github.com/nginx-proxy/acme-companion)
for automatic TLS.

## Site map

| Route | What it is | Source |
|---|---|---|
| `/` | Landing (Hero · UseCases · Benchmarks · HowItWorks · Cta) | `src/pages/index.astro` |
| `/protocol-map/` | Visual map of the three negotiation pathways (text-tokens · MCP leaf-mode · v0.3 latents) | `src/pages/protocol-map.astro` + `public/diagrams/protocol-map.svg` |
| `/docs/<slug>/` | Engine + client docs (codec-sglang / codec-vllm / codec-llamacpp / codec-metamcp / codec-comfyui / codec-diffusers / TS / Python / Rust / Java / .NET / C / Translator / etc.) | `src/content/docs/<slug>.md` via `[...slug].astro` |
| `/changelog/` | Customer-facing What's New feed | `src/pages/changelog/index.astro` reading `src/content/changelog/*.md` |
| `/changelog/<slug>/` | Per-entry changelog detail | `src/pages/changelog/[...slug].astro` |
| `/rss.xml` | RSS 2.0 feed of the changelog | `src/pages/rss.xml.ts` (uses `@astrojs/rss`) |

The deeper engineering changelog (commit lists, fork SHAs, image digests) lives in [GitHub Releases](https://github.com/wdunn001/Codec/releases); each `/changelog/` entry links out to the corresponding release.

## Local development

```bash
npm install
npm run dev          # http://localhost:4321
npm run build        # emits dist/
npm run preview      # serve dist/ locally
```

## Deploy

The site runs as a single container that joins the host's pre-existing
`nginx-proxy` Docker network. The proxy + ACME companion handle routing and
TLS for `codecai.net` automatically based on the container's
`VIRTUAL_HOST` / `LETSENCRYPT_HOST` environment variables.

### One-time setup on the host

```bash
# On the deploy host (william@192.168.1.198):
cd /storage
git clone git@github.com:wdunn001/codec-website.git
cd codec-website
cp .env.example .env       # adjust hosts / email if needed
docker compose up -d --build
```

### Redeploy

```bash
# On the deploy host:
cd /storage/codec-website
git pull
docker compose up -d --build
```

### DNS

Point `codecai.net` and `www.codecai.net` at the host's public IP. The ACME
companion will issue a Let's Encrypt cert automatically the first time the
container comes up (typically within 30 seconds).

## Stack

- [Astro 5](https://astro.build) — static site generator, ships zero JS for
  this site (animations are pure CSS on inline SVG).
- TypeScript (strict), system fonts (Inter / JetBrains Mono fallbacks).
- nginx 1.27-alpine for serving, with aggressive gzip + immutable cache
  headers on hashed assets.

## Files

```
src/
  layouts/Base.astro        site shell, header, footer, SEO meta
  components/
    Hero.astro              hero + byte-collapse SVG animation (zero JS)
    Compare.astro           JSON vs Codec wire-format comparison
    HowItWorks.astro        three-step protocol summary
    Cta.astro               final call to action
  pages/index.astro         landing page composition
  styles/global.css         design tokens (data=blue, control=green)
public/
  codec.svg                 logo
  favicon.svg               square favicon
  robots.txt
deploy/
  nginx.conf                static + cache + security headers
Dockerfile                  multi-stage: node:22-alpine -> nginx:1.27-alpine
docker-compose.yml          jwilder/letsencrypt env vars + external network
.env.example                copy to .env on the host
```

## License

Code in this repository is © 2026 Quasarke LLC. All rights reserved.
The Codec protocol itself is published under
[BSL 1.1](https://github.com/wdunn001/Codec/blob/main/LICENSE) in its own
repo. For commercial licensing inquiries: licensing@quasarke.com.
