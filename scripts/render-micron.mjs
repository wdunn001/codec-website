// Pre-render codec-website's docs + changelog to NomadNet micron (.mu) pages
// for the quasarke off-grid base station's NomadNet node. Deliberately
// separate from `astro build`: writes to dist-micron/, never touches dist/.
// This node mounts the codec-website mirror under the subpath /page/codecai/
// -- The Mild Take owns the node root (/page/index.mu, /page/...), so every
// internal link this script emits is an ABSOLUTE /page/codecai/... path (a
// bare relative target resolves wrong from nested pages -- see mdToMicron.mjs
// and the binding rules in the task brief this script was written against).
//
// Micron syntax reference: NomadNet's own Guide.py ("Markup" / "Fields &
// Requests" topics) and MicronParser.py. Toolkit is adapted from
// themildtake's src/micron/{micron,mdxToMicron}.mjs -- see those files' own
// header comments and src/micron/mdToMicron.mjs here for what changed and why
// (plain markdown, no MDX/JSX, no chart/country-data math).
//
// Usage: npm run render-micron
//        node scripts/render-micron.mjs [--out <dir>]

import { promises as fs } from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import yaml from "js-yaml";

import { mdToMicron } from "../src/micron/mdToMicron.mjs";
import {
  heading,
  para,
  paraInline,
  divider,
  link,
  citation,
  pageHeader,
  fg,
  COLOR,
  asciiBannerColored,
  centerBlockNative,
  ALIGN_CENTER,
  ALIGN_RESET,
} from "../src/micron/micron.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(here, "..");

const argOut = process.argv.includes("--out") ? process.argv[process.argv.indexOf("--out") + 1] : null;
const outDir = argOut ? path.resolve(argOut) : path.join(repoRoot, "dist-micron");

// codec-website's own DocsSidebar.astro section order (src/components/DocsSidebar.astro).
const DOC_SECTION_ORDER = ["Start", "Frameworks", "Server", "Reference"];
const FM_RE = /^---\n([\s\S]*?)\n---\n?([\s\S]*)$/;

const warnings = [];
function warn(file, msg) {
  warnings.push({ file, msg });
}

async function readContentFile(dir, filename) {
  const abs = path.join(dir, filename);
  const raw = await fs.readFile(abs, "utf8");
  const m = FM_RE.exec(raw);
  if (!m) {
    warn(filename, "no YAML frontmatter block found; skipped");
    return null;
  }
  const [, fmText, body] = m;
  let fm;
  try {
    fm = yaml.load(fmText) ?? {};
  } catch (e) {
    warn(filename, `frontmatter YAML failed to parse (${e.message}); skipped`);
    return null;
  }
  const slug = filename.replace(/\.md$/, "");
  return { slug, filename, fm, body };
}

async function loadEntries(dir) {
  const entries = [];
  const files = (await fs.readdir(dir)).filter((f) => f.endsWith(".md"));
  for (const f of files) {
    const entry = await readContentFile(dir, f);
    if (entry) entries.push(entry);
  }
  return entries;
}

async function main() {
  await fs.rm(outDir, { recursive: true, force: true });
  for (const d of ["docs", "changelog"]) {
    await fs.mkdir(path.join(outDir, d), { recursive: true });
  }

  console.log("[render-micron] loading content...");
  const docs = await loadEntries(path.join(repoRoot, "src", "content", "docs"));
  const changelog = await loadEntries(path.join(repoRoot, "src", "content", "changelog"));

  const knownDocSlugs = new Set(docs.map((e) => e.slug));
  const knownChangelogSlugs = new Set(changelog.map((e) => e.slug));

  // --- docs/<slug>.mu ---------------------------------------------------
  console.log(`[render-micron] converting ${docs.length} doc pages...`);
  for (const entry of docs) {
    const ctx = {
      knownDocSlugs,
      knownChangelogSlugs,
      canonicalPath: `/docs/${entry.slug}/`,
      warn: (msg) => warn(`docs/${entry.filename}`, msg),
    };
    let bodyMicron;
    try {
      bodyMicron = mdToMicron(entry.body, ctx);
    } catch (e) {
      console.error(`[render-micron] FAILED converting docs/${entry.filename}:`);
      throw e;
    }

    let page = pageHeader({
      title: entry.fm.title,
      meta: entry.fm.description,
      tags: entry.fm.section ? [entry.fm.section] : undefined,
    });
    page += bodyMicron;
    page += divider();
    page += paraInline(link("<< Codec docs index", "/page/codecai/index.mu"));

    await fs.writeFile(path.join(outDir, "docs", `${entry.slug}.mu`), page, "utf8");
  }

  // --- changelog/<slug>.mu + changelog.mu overview -----------------------
  console.log(`[render-micron] converting ${changelog.length} changelog entries...`);
  const changelogSorted = [...changelog].sort((a, b) => String(b.fm.date).localeCompare(String(a.fm.date)));

  for (const entry of changelog) {
    const ctx = {
      knownDocSlugs,
      knownChangelogSlugs,
      canonicalPath: `/changelog/${entry.slug}/`,
      warn: (msg) => warn(`changelog/${entry.filename}`, msg),
    };
    let bodyMicron;
    try {
      bodyMicron = mdToMicron(entry.body, ctx);
    } catch (e) {
      console.error(`[render-micron] FAILED converting changelog/${entry.filename}:`);
      throw e;
    }

    const metaBits = [entry.fm.date];
    if (entry.fm.version) metaBits.push(entry.fm.version);
    if (entry.fm.kind) metaBits.push(entry.fm.kind);

    let page = pageHeader({ title: entry.fm.title, meta: metaBits.join(" - ") });
    if (entry.fm.summary) {
      page += para(entry.fm.summary);
      page += divider();
    }
    page += bodyMicron;

    if (Array.isArray(entry.fm.links) && entry.fm.links.length) {
      page += divider();
      page += heading(2, "Links");
      for (const l of entry.fm.links) {
        if (!l?.url) continue;
        page += paraInline(citation(l.label ?? l.url, l.url));
      }
    }

    page += divider();
    page += paraInline(link("<< Full changelog", "/page/codecai/changelog.mu"));
    page += paraInline(link("<< Codec docs index", "/page/codecai/index.mu"));

    await fs.writeFile(path.join(outDir, "changelog", `${entry.slug}.mu`), page, "utf8");
  }

  let changelogPage = pageHeader({
    title: "Codec changelog",
    meta: "Customer-facing what's-new feed - newest first",
  });
  for (const entry of changelogSorted) {
    changelogPage += paraInline(link(entry.fm.title, `/page/codecai/changelog/${entry.slug}.mu`) + `  ${entry.fm.date}`);
    if (entry.fm.summary) changelogPage += para(entry.fm.summary);
  }
  changelogPage += divider();
  changelogPage += paraInline(link("<< Codec docs index", "/page/codecai/index.mu"));
  await fs.writeFile(path.join(outDir, "changelog.mu"), changelogPage, "utf8");

  // --- top-level index.mu --------------------------------------------------
  // Masthead: block-letter "CODEC" in the site's brand accent blue (#3B82F6,
  // the --data token in src/styles/global.css -- `38f as a 12-bit micron
  // triad), centered with micron's NATIVE `c alignment tag (not space-padding
  // to a guessed page width -- see centerBlockNative()'s own comment in
  // micron.mjs for why that's the correct approach; NomadNet reflows to the
  // reader's actual display width).
  console.log("[render-micron] building index.mu...");
  const bannerRows = asciiBannerColored(["CODEC"], ["38f"]).split("\n");
  let index = centerBlockNative(bannerRows).join("\n") + "\n\n";
  index += ALIGN_CENTER + fg(COLOR.muted, "The control plane for AI inference.") + "\n\n";
  index += ALIGN_RESET + "\n\n";
  index += divider();

  // Description sourced faithfully from the landing page's hero copy
  // (src/components/Hero.astro <p class="hero__lede">) -- prose unedited,
  // only the markup changed, per the mirror-faithfulness rule.
  index += para(
    "AI inference is burning megawatts of GPU power and datacenter buildout is racing to keep up. Meanwhile your inference stack is paying again at every hop on top of the GPU bill. Models think in tokens, but the rest of the stack speaks text. Every gateway, router, tool dispatcher, and middleware in the path does the same ritual: detokenize the model's IDs to text, encode as UTF-8, wrap in JSON, ship it, parse it, decode UTF-8, re-tokenize back to IDs, burning CPU, memory, and latency on lossy conversions the AI never asked for, and risking KV-cache corruption when the re-tokenize doesn't round-trip cleanly. Codec is a drop-in upgrade that keeps token IDs as the wire format end-to-end: gateways forward IDs verbatim, tool dispatchers match on raw IDs, cross-model handoffs translate vocabularies in-process. Same model, same prompts, same answers; typically 16x less data on the wire on real agent traffic, up to ~1,700x when the content compresses well. How big the win is depends on what your AI generates. Plug-in libraries for TypeScript, Python, Rust, Java, .NET, and C work with the AI servers you already use (sglang, vllm, llama.cpp). Your code doesn't change.",
  );
  index += divider();

  // --- Docs section: grouped by codec-website's own section order --------
  index += heading(2, "Docs");
  index += para("Codec is a token-native binary transport protocol for AI APIs. Reference implementations, engine integrations, and protocol references, grouped the same way as the live docs sidebar.");
  const docsBySection = new Map(DOC_SECTION_ORDER.map((s) => [s, []]));
  for (const d of docs) {
    const list = docsBySection.get(d.fm.section) ?? docsBySection.get("Reference");
    list.push(d);
  }
  for (const section of DOC_SECTION_ORDER) {
    const items = (docsBySection.get(section) ?? []).sort((a, b) => (a.fm.order ?? 0) - (b.fm.order ?? 0));
    if (!items.length) continue;
    index += heading(3, section);
    for (const d of items) {
      index += paraInline(link(d.fm.title, `/page/codecai/docs/${d.slug}.mu`));
    }
  }
  index += divider();

  // --- Changelog section: all entries + the overview page ----------------
  index += heading(2, "Changelog");
  index += para("What's new, newest first.");
  index += paraInline(link("Full changelog (overview)", "/page/codecai/changelog.mu"));
  for (const entry of changelogSorted) {
    index += paraInline(link(entry.fm.title, `/page/codecai/changelog/${entry.slug}.mu`) + `  ${entry.fm.date}`);
  }
  index += divider();

  // --- Protocol map: text description + web citation (no image transport) -
  index += heading(2, "Protocol map");
  index += para(
    "Codec runs on one client/gateway/engine triangle. The wire frame, the per-modality map, and the response headers shift per pathway. The triangle does not. Four negotiation pathways: text-tokens (v0.2, uint32 token-ID frames), MCP tool-calls with leaf-mode bypass (pre-tokenized results via a pinned tokenizer map), latents (v0.3, VAE latents instead of decoded pixels for image/video diffusion), and safety policies (v0.4, a TLS-style capability axis with hash-anchored policy descriptors). Full diagram and normative spec:",
  );
  index += paraInline(citation("Protocol map", `${"https://codecai.net"}/protocol-map/`));
  index += divider();

  index += paraInline(
    fg(
      COLOR.muted,
      "About this mirror: pre-rendered from codecai.net for the quasarke NomadNet node. " +
        "Prose is unedited, only the markup changed. Images and diagrams are described in " +
        "text with a citation back to the live site (no image transport over Reticulum).",
    ),
  );
  index += paraInline(link("<< Node index (The Mild Take)", "/page/index.mu"));

  await fs.writeFile(path.join(outDir, "index.mu"), index, "utf8");

  console.log(`\n[render-micron] wrote index.mu, ${docs.length} doc pages, changelog.mu + ${changelog.length} changelog entries.`);
  if (warnings.length) {
    console.log(`[render-micron] ${warnings.length} warnings:`);
    for (const w of warnings) console.log(`  [${w.file}] ${w.msg}`);
  } else {
    console.log("[render-micron] no warnings.");
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((e) => {
    console.error(e);
    process.exit(1);
  });
}
