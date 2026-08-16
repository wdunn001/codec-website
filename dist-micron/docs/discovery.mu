`F6cf`!Self-hosted discovery — .well-known/codec/`!`f

`F999Publish vocab maps at a known URL on a domain you control. Clients then only need the origin and the map ID — no out-of-band URL+hash exchange.`f

`F999`*Reference`*`f

-

There are `!two paths to a loaded map`!, and you almost always want the first:

1. `!Automatic discovery`! — the server's response carries a 'Codec-Tokenizer-Map: <id> sha256:<short>' header. The client extracts '<id>' + the server's origin, fetches '<origin>/.well-known/codec/maps/<id>.json' (which is either the inline map or a hash-pinned pointer to a CDN), verifies the hash, and caches the parsed map. `!No URL or hash in your config — the protocol carries them.`! See 'discoverMap({ origin, id })' in '@codecai/web/discover' and 'discover_map(origin=..., id=...)' in 'codecai.discover'.
2. `!Manual pinning`! — 'loadMap({ url, hash })' if you want to bind to a specific URL and sha256 yourself (e.g. air-gapped deployments, supply-chain audits, or pinning a frozen version against vendor rotations).

'.well-known/codec/' is the convention that makes path 1 work without a central registry: a model maintainer publishes a small static document at a stable path on their domain, and clients resolve from '(origin, id)' alone. No registry, no central authority — just the same trust model as 'robots.txt' or '.well-known/openid-configuration'.

`F999┃ The full convention is specified in 'spec/WELL_KNOWN_DISCOVERY.md' (https://github.com/wdunn001/Codec/blob/main/spec/WELL_KNOWN_DISCOVERY.md). PROTOCOL.md (https://github.com/wdunn001/Codec/blob/main/spec/PROTOCOL.md) lists it as the resolution to Open Question #3 (decentralised first; a registry remains an option for cross-org and air-gapped use).`f

>>>URL layout

┌────────────────┬─────────────────────────────────────────────────────┐
│ What           │ URL                                                 │
├────────────────┼─────────────────────────────────────────────────────┤
│ One map        │ 'https://<origin>/.well-known/codec/maps/<id>.json' │
│ Optional index │ 'https://<origin>/.well-known/codec/index.json'     │
└────────────────┴─────────────────────────────────────────────────────┘

Map IDs preserve '/' as a path separator ('qwen/qwen2' → 'maps/qwen/qwen2.json'). IDs must match '[a-z0-9._/-]+'; '..', leading '/', and any other path-traversal-shaped strings are rejected before the network is touched.

>>>Two forms for the per-map document

>>>>Form A — pointer (recommended)

A small JSON document (~150 bytes) that says "the real map is over there at the CDN, and here's its sha256":

`F999`*code (json):`*`f
`=
{
  "id": "qwen2",
  "url": "https://cdn.example.com/qwen2.json",
  "hash": "sha256:887311099cdc09e7022001a01fa1da396750d669b7ed2c242a000b9badd09791",
  "published_at": "2026-05-06T12:00:00Z"
}
`=

The client fetches this once (cached), validates that the pointer's 'id' matches the requested ID, follows the 'url', and verifies the bytes against 'hash'. If the CDN is later compromised, the hash mismatch fails closed — the trust anchor is the origin's TLS plus the pointer's 'hash' field.

Pointers do `!not`! chain: a pointer that points at another pointer is rejected.

>>>>Form B — inline map

For small maps it's fine to serve the entire 'TokenizerMap' directly at the well-known path:

`F999`*code (json):`*`f
`=
{
  "id": "qwen2",
  "version": "2",
  "vocab_size": 151665,
  "vocab": { "...": "..." },
  "encoder": "byte_level",
  "merges": [ "...": "..." ]
}
`=

Detected by the presence of 'vocab' (v2) or 'tokens' (v1). Integrity rests on the origin's TLS; clients may cache the bytes' hash on first fetch and re-verify on subsequent loads.

>>>The optional index

'/.well-known/codec/index.json' is an advisory directory listing every map you publish:

`F999`*code (json):`*`f
`=
{
  "codec_version": "0.2",
  "maps": [
    { "id": "qwen2",   "url": "https://cdn.example.com/qwen2.json",   "hash": "sha256:887311..." },
    { "id": "qwen2.5", "url": "https://cdn.example.com/qwen2.5.json", "hash": "sha256:7af121..." }
  ]
}
`=

Clients `!may`! read the index to enumerate available maps, but it's never required — resolving an individual map by ID always works.

>>>Recommended HTTP headers

Maintainers should serve the well-known documents with:

`=
Content-Type:               application/json
Access-Control-Allow-Origin: *
Cache-Control:              public, max-age=300, stale-while-revalidate=86400
`=

CORS is required if browser clients will fetch directly.

>>>Client API

>>>>TypeScript — '@codecai/web/discover'

`F999`*code (ts):`*`f
`=
import { discoverMap, discoverIndex } from "@codecai/web/discover";
import { Detokenizer, decodeStream } from "@codecai/web";

// Resolve a map from (origin, id). No URL or hash needed in your config.
const map = await discoverMap({
  origin: "https://example.com",
  id:     "qwen2",
});

const detok = new Detokenizer(map);
// ... use as normal ...
`=

The full surface, from 'packages/web/src/discover.ts' (https://github.com/wdunn001/Codec/blob/main/packages/web/src/discover.ts):

`F999`*code (ts):`*`f
`=
export const WELL_KNOWN_BASE: string;  // "/.well-known/codec"

export function wellKnownMapUrl(origin: string, id: string): string;
export function wellKnownIndexUrl(origin: string): string;

export interface DiscoverMapOptions {
  origin: string;          // HTTPS origin
  id: string;              // map ID (e.g. "qwen2", "qwen/qwen2")
  cache?: MapCache;        // shared with loadMap
  signal?: AbortSignal;
  fetchImpl?: typeof fetch;
}

export function discoverMap(opts: DiscoverMapOptions): Promise<TokenizerMap>;

export interface DiscoverIndexOptions {
  origin: string;
  signal?: AbortSignal;
  fetchImpl?: typeof fetch;
}

export function discoverIndex(opts: DiscoverIndexOptions): Promise<MapIndex>;

export interface MapPointer {
  readonly id: string;
  readonly url: string;
  readonly hash: string;
  readonly published_at?: string;
}

export interface MapIndex {
  readonly codec_version: string;
  readonly maps: ReadonlyArray<MapPointer>;
}

export class MapDiscoveryError extends Error {}
export class MapDiscoveryNotFoundError extends MapDiscoveryError {
  constructor(url: string, status: number);
}
`=

The 'discover' module is a separate subpath import so tree-shaking can drop it when you don't use it. Maps loaded via 'discoverMap' share the 'loadMap' cache — subsequent calls hit memory, no network.

>>>>Python — 'codecai.discover'

`F999`*code (python):`*`f
`=
from codecai import Detokenizer, discover_map

map = await discover_map(origin="https://example.com", id="qwen2")
detok = Detokenizer(map)
# ... use as normal ...
`=

The full surface, from 'packages/python/src/codecai/discover.py' (https://github.com/wdunn001/Codec/blob/main/packages/python/src/codecai/discover.py):

`F999`*code (python):`*`f
`=
def well_known_map_url(origin: str, id: str) -> str: ...
def well_known_index_url(origin: str) -> str: ...

@dataclass(frozen=True)
class MapPointer:
    id: str
    url: str
    hash: str
    published_at: str | None = None

@dataclass(frozen=True)
class MapIndex:
    codec_version: str
    maps: tuple[MapPointer, ...]

class MapDiscoveryError(ValueError): ...
class MapDiscoveryNotFoundError(MapDiscoveryError):
    def __init__(self, url: str, status: int): ...

async def discover_map(
    *,
    origin: str,
    id: str,
    cache: MapCache | None = None,
    client: httpx.AsyncClient | None = None,
    timeout: float = 30.0,
) -> TokenizerMap: ...

async def discover_index(
    *,
    origin: str,
    client: httpx.AsyncClient | None = None,
    timeout: float = 30.0,
) -> MapIndex: ...
`=

Both functions are coroutines. A 404 raises 'MapDiscoveryNotFoundError'; malformed pointers raise 'MapDiscoveryError'; CDN bytes that don't match the pointer's hash raise 'TokenizerMapHashMismatchError'.

>>>Publishing — 'codecai-maps well-known'

The maps CLI ships a 'well-known' subcommand to emit the static directory tree for you:

`F999`*code (bash):`*`f
`=
# Pointer form (recommended)
codecai-maps well-known \
  --map=./qwen2.json \
  --url=https://cdn.example.com/qwen2.json \
  --out-dir=./public

# Inline form (for small maps)
codecai-maps well-known --map=./qwen2.json --inline --out-dir=./public
`=

After running with '--url', the tree under '--out-dir' contains:

`=
public/
  .well-known/
    codec/
      maps/
        qwen2.json          # pointer document
      index.json            # auto-updated, sorted by id
`=

'--url' and '--inline' are mutually exclusive. Re-running with '--url' for an ID already in the index replaces that entry. '--inline' only emits the per-map document; it does not touch the index.

>>>End-to-end

Putting it together — vendor side once:

`F999`*code (bash):`*`f
`=
codecai-maps well-known --map=./qwen2.json \
  --url=https://cdn.example.com/qwen2.json \
  --out-dir=./public
# rsync public/.well-known/ to https://example.com/.well-known/
`=

Client side, anywhere thereafter:

`F999`*code (ts):`*`f
`=
import { discoverMap } from "@codecai/web/discover";

const map = await discoverMap({ origin: "https://example.com", id: "qwen2" });
`=

Network trace:

1. 'GET https://example.com/.well-known/codec/maps/qwen2.json' — pointer doc, ~150 bytes.
2. Client validates that 'pointer.id === "qwen2"' and the hash format is well-formed.
3. 'GET https://cdn.example.com/qwen2.json' — the actual map, hash-verified.
4. Parsed and cached. Subsequent 'discoverMap({ origin, id })' calls hit memory.

>>>When to use this vs 'loadMap'

• `!You're a model vendor or maintainer.`! Publish at '.well-known/codec/' so consumers can resolve your map by ID alone. They don't have to track URL changes or hash rotations through your release notes; the pointer is the source of truth.
• `!You're a consumer pinning to a frozen map.`! Keep using 'loadMap({ url, hash })' — you already know exactly what you want, and a pinned hash is stricter than "whatever the vendor publishes today."

The two coexist. 'discoverMap' ultimately calls into the same loader, so caching, error types, and the rest of the pipeline are identical.

>>>See also

• 'spec/WELL_KNOWN_DISCOVERY.md' (https://github.com/wdunn001/Codec/blob/main/spec/WELL_KNOWN_DISCOVERY.md) — the full convention.
• `[TypeScript walkthrough`:/page/codecai/docs/typescript.mu] — 'loadMap' and the rest of the surface.
• `[Python walkthrough`:/page/codecai/docs/python.mu] — 'load_map' and friends.
• `[Protocol overview`:/page/codecai/docs/protocol.mu] — where this fits in the spec.

-

`[<< Codec docs index`:/page/codecai/index.mu]

