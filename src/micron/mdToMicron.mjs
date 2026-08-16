// Plain markdown (Astro content collection) body -> micron body. Adapted from
// themildtake's src/micron/mdxToMicron.mjs, but codec-website's docs and
// changelog entries are PLAIN markdown (no MDX/JSX components), so this
// module only wires unified().use(remarkParse).use(remarkGfm) -- no
// remark-mdx, no component handlers (EChart / Eq / CountryTrajectory), no
// scoreEngine/echart/chart imports. Frontmatter is stripped/parsed by the
// caller (scripts/render-micron.mjs), matching how themildtake's render
// script loads content files.

import { unified } from "unified";
import remarkParse from "remark-parse";
import remarkGfm from "remark-gfm";
import {
  esc,
  guardBlock,
  headingInline,
  paraInline,
  bold,
  italic,
  fg,
  COLOR,
  link,
  citation,
  literalBlock,
  table,
  divider,
} from "./micron.mjs";

const mdProcessor = unified().use(remarkParse).use(remarkGfm);

export function parseMdBody(body) {
  return mdProcessor.parse(body);
}

const SITE_ORIGIN = "https://codecai.net";
const DOCS_RE = /^\/docs\/([a-z0-9][a-z0-9-]*)\/?$/;
const CHANGELOG_ENTRY_RE = /^\/changelog\/([a-z0-9][a-z0-9-]*)\/?$/;

/** Classify a markdown link target against the pages this mirror actually
 *  emits. `ctx.knownDocSlugs` / `ctx.knownChangelogSlugs` are Sets of slugs
 *  (filename minus extension) for the docs/changelog entries being rendered
 *  this run -- only link internally to pages we are actually writing;
 *  everything else (including /protocol-map/, which has no dedicated micron
 *  page -- see render-micron.mjs's text-description section) degrades to a
 *  plain-text citation, since external web URLs have no RNS destination to
 *  follow over Reticulum. */
function classifyLink(url, ctx) {
  if (!url) return { type: "text" };
  if (url.startsWith("#")) return { type: "anchor-drop" };
  if (url.startsWith("mailto:")) return { type: "external", url };

  // Same-origin absolute URLs (a few changelog/doc links write the full
  // https://codecai.net/docs/<slug>/ form instead of a relative path) are
  // internal-link candidates too -- fall through to the relative-path logic
  // below on the URL's own path portion instead of treating them as opaque
  // external citations.
  let rel = url;
  if (rel.startsWith(SITE_ORIGIN)) {
    rel = rel.slice(SITE_ORIGIN.length) || "/";
  } else if (/^https?:\/\//.test(rel)) {
    return { type: "external", url };
  }

  const [pathPart] = rel.split("#"); // internal fragments don't resolve on a mesh page; link to the whole page

  if (pathPart === "" || pathPart === "/") return { type: "internal", target: "/page/codecai/index.mu" };

  let m = DOCS_RE.exec(pathPart);
  if (m) {
    const slug = m[1];
    if (ctx.knownDocSlugs.has(slug)) return { type: "internal", target: `/page/codecai/docs/${slug}.mu` };
    return { type: "external-site", path: pathPart };
  }

  if (pathPart === "/changelog" || pathPart === "/changelog/") return { type: "internal", target: "/page/codecai/changelog.mu" };
  m = CHANGELOG_ENTRY_RE.exec(pathPart);
  if (m) {
    const slug = m[1];
    if (ctx.knownChangelogSlugs.has(slug)) return { type: "internal", target: `/page/codecai/changelog/${slug}.mu` };
    return { type: "external-site", path: pathPart };
  }

  if (pathPart.startsWith("/")) return { type: "external-site", path: pathPart };
  return { type: "external", url };
}

function renderLink(label, url, ctx) {
  const cls = classifyLink(url, ctx);
  if (cls.type === "anchor-drop") return label;
  if (cls.type === "internal") return link(label, cls.target);
  if (cls.type === "external") return citation(label, cls.url);
  if (cls.type === "external-site") return citation(label, SITE_ORIGIN + cls.path);
  return label;
}

function renderInline(nodes, ctx) {
  return nodes.map((n) => renderInlineNode(n, ctx)).join("");
}

function renderInlineNode(node, ctx) {
  switch (node.type) {
    case "text":
      return esc(node.value);
    case "inlineCode":
      return "'" + esc(node.value) + "'";
    case "strong":
      return bold(renderInline(node.children, ctx));
    case "emphasis":
      return italic(renderInline(node.children, ctx));
    case "delete":
      return "~" + renderInline(node.children, ctx) + "~";
    case "break":
      return "\n";
    case "link":
      return renderLink(renderInline(node.children, ctx) || node.url, node.url, ctx);
    case "image":
      // No images actually appear in codec-website's docs/changelog bodies
      // (grep confirmed) -- kept defensively per the mirror rule that images
      // can't render over Reticulum: emit the alt text + a citation back to
      // the live page.
      return (
        fg(COLOR.muted, italic(`[image omitted in mesh mirror: ${esc(node.alt || "image")}]`)) +
        " " +
        citation("view on site", SITE_ORIGIN + (ctx.canonicalPath ?? "/"))
      );
    default:
      if (node.children) return renderInline(node.children, ctx);
      return "";
  }
}

function renderListItems(node, ctx, ordered, depth) {
  const indent = "  ".repeat(depth);
  let out = "";
  let n = node.start ?? 1;
  for (const item of node.children) {
    const marker = ordered ? `${n}. ` : "• "; // bullet, NOT "-" (a leading "-" is a divider tag)
    n++;
    const inlineParts = [];
    const blockParts = [];
    for (const child of item.children ?? []) {
      if (child.type === "paragraph") inlineParts.push(renderInline(child.children, ctx));
      else if (child.type === "list") blockParts.push(renderListItems(child, ctx, child.ordered, depth + 1));
      else blockParts.push(renderBlockNode(child, ctx));
    }
    const head = indent + marker + guardBlock(inlineParts.join(" "));
    out += head + "\n";
    if (blockParts.length) out += blockParts.join("");
  }
  return out + "\n";
}

function renderBlockquote(node, ctx) {
  const inner = renderBlockChildren(node.children, ctx);
  const quoted = inner
    .trimEnd()
    .split("\n")
    .map((l) => "┃ " + l)
    .join("\n");
  return fg(COLOR.muted, quoted) + "\n\n";
}

function renderTable(node, ctx) {
  const [headerRow, ...bodyRows] = node.children;
  const aligns = (node.align ?? headerRow.children.map(() => null)).map((a) => a ?? "left");
  const headers = headerRow.children.map((cell) => guardBlock(renderInline(cell.children, ctx)));
  const rows = bodyRows.map((row) => row.children.map((cell) => guardBlock(renderInline(cell.children, ctx))));
  return table(headers, aligns, rows);
}

function renderCode(node) {
  const lines = node.value.split("\n");
  const header = node.lang ? fg(COLOR.muted, italic(`code (${esc(node.lang)}):`)) + "\n" : "";
  return header + literalBlock(lines);
}

function renderBlockNode(node, ctx) {
  switch (node.type) {
    case "heading":
      return headingInline(Math.min(6, node.depth + 1), renderInline(node.children, ctx));
    case "paragraph":
      return paraInline(renderInline(node.children, ctx));
    case "blockquote":
      return renderBlockquote(node, ctx);
    case "list":
      return renderListItems(node, ctx, node.ordered, 0);
    case "table":
      return renderTable(node, ctx);
    case "code":
      return renderCode(node);
    case "thematicBreak":
      return divider();
    case "html":
      return ""; // stray raw HTML: drop rather than leak unrendered tags into the mesh page
    default:
      if (node.children) return renderBlockChildren(node.children, ctx);
      return "";
  }
}

function renderBlockChildren(nodes, ctx) {
  return nodes.map((n) => renderBlockNode(n, ctx)).join("");
}

/** Convert one content page's markdown body to a micron body string.
 *  ctx: { knownDocSlugs: Set<string>, knownChangelogSlugs: Set<string>,
 *         canonicalPath?: string ("/docs/<slug>/" etc, for image citations),
 *         warn: fn } */
export function mdToMicron(body, ctx) {
  const tree = parseMdBody(body);
  return renderBlockChildren(tree.children, ctx);
}
