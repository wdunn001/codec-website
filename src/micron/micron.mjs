// Core micron (.mu) markup primitives, shared by every page builder in
// scripts/render-micron.mjs. Reference: NomadNet's own Guide.py ("Markup" /
// "Fields & Requests" topics) and MicronParser.py -- see the render-micron
// header comment for the exact source paths. Micron's control character is
// the backtick; every other tag is `<letter>[params]`. This module only
// builds strings -- it never decides WHAT to render (that is scoreEngine.mjs
// for numbers, and mdxToMicron.mjs / countryPages.mjs / newsPage.mjs for
// content shape).

// A small, readable-on-dark-terminal palette (12-bit `Fxxx` triads).
export const COLOR = {
  pos: "6f8", // clear positive reading
  neg: "f66", // clear negative reading
  mixed: "fd6", // mixed reading
  muted: "999", // notes / captions / de-emphasized text
  accent: "6cf", // emphasis / headings accent
  warn: "fb6", // caveats, transparency caps
};

/** Escape the micron control character (backtick) in literal text. */
export function esc(s) {
  return String(s ?? "").replace(/`/g, "\\`");
}

/** Guard a line against accidentally starting with a tag/section/divider/
 *  comment character -- ">" starts a heading, "-" (as the FIRST character of
 *  a line) renders as a horizontal divider regardless of what follows it,
 *  and "#" starts a comment line that is silently not displayed at all
 *  (MicronParser.py: divider on any line whose first char is "-"; comment on
 *  first char "#"). Applied to a fully-assembled block of text (not per
 *  inline fragment), since only the true first character of the physical
 *  output line matters. */
function escLineStart(line) {
  return /^[>#-]/.test(line) ? "\\" + line : line;
}

/** Guard every physical line of an already-formatted block (may already
 *  contain micron tags from bold()/link()/etc, which must NOT be re-escaped)
 *  against the line-start ambiguities above. */
export function guardBlock(s) {
  return String(s ?? "")
    .split("\n")
    .map(escLineStart)
    .join("\n");
}

/** Escape a whole block of PLAIN text (no embedded micron tags yet):
 *  backticks anywhere, plus leading tag chars on every physical line. */
export function escText(s) {
  return guardBlock(
    String(s ?? "")
      .split("\n")
      .map(esc)
      .join("\n"),
  );
}

export const bold = (s) => "`!" + s + "`!";
export const italic = (s) => "`*" + s + "`*";
export const underline = (s) => "`_" + s + "`_";
export const fg = (hex, s) => "`F" + hex + s + "`f";
export const bg = (hex, s) => "`B" + hex + s + "`b";

/** Section heading. level 1 = `>`, level 2 = `>>`, etc. Must start a line. */
export function heading(level, text) {
  return ">".repeat(Math.max(1, level)) + (text ? escText(text) : "") + "\n\n";
}

/** Section heading built from ALREADY-formatted inline micron (e.g. mdast
 *  prose that ran through the inline renderer and may carry bold/link tags)
 *  -- guarded for line-start ambiguity but not re-backtick-escaped. */
export function headingInline(level, formattedText) {
  return ">".repeat(Math.max(1, level)) + guardBlock(formattedText) + "\n\n";
}

/** Plain paragraph, blank-line terminated. */
export function para(text) {
  return escText(text) + "\n\n";
}

/** Paragraph built from already-formatted inline micron (see headingInline). */
export function paraInline(formattedText) {
  return guardBlock(formattedText) + "\n\n";
}

export function divider() {
  return "-\n\n";
}

/** Explicit anchor (no heading attached). */
export function anchor(name) {
  return "`:" + name + "\n";
}

/** Internal link. `target` is a `/page/...` path (no destination hash --
 *  resolved against the current node, the convention this mirror's index
 *  links already use). External web URLs are NOT rendered as micron links
 *  (NomadNet has no HTTP transport to follow them); callers should pass
 *  those through `citation()` instead. */
export function link(label, target) {
  return "`[" + escText(label) + "`:" + target + "]";
}

/** A request link that also submits field/var data to the target page. */
export function requestLink(label, target, fields) {
  return "`[" + escText(label) + "`:" + target + "`" + fields + "]";
}

/** A web URL that can't be a real micron link (no RNS destination) --
 *  rendered as visible plain-text citation, matching the prior-art python
 *  converter's treatment of non-mirrored absolute URLs. */
export function citation(text, url) {
  return url ? `${escText(text)} (${url})` : escText(text);
}

/** Literal / monospace block. Per MicronParser.py, `= toggles a literal mode
 *  that suspends ALL tag interpretation (divider/heading/comment/escape)
 *  until the next bare `= line -- content is verbatim, so it must NOT be
 *  backtick-escaped (an inserted backslash would render as a literal
 *  backslash character, not an escape). The only real hazard is a content
 *  line that is exactly "`=", which would prematurely close the block; none
 *  of this module's generated bar charts / sparklines / tables produce that,
 *  so this is a defensive guard rather than an expected path. */
export function literalBlock(lines) {
  const body = (Array.isArray(lines) ? lines.join("\n") : String(lines))
    .split("\n")
    .map((l) => (l === "`=" ? "` =" : l))
    .join("\n");
  return "`=\n" + body + "\n`=\n\n";
}

/** Reduce already-formatted micron cell text to its plain visible form:
 *  links become their label, color/style tags are removed, escaped backticks
 *  become literal backticks. Used by table() both to measure widths and as
 *  the rendered cell content (tables render inside a literal block, where
 *  tags would show raw instead of styling). */
function stripMicron(s) {
  let t = String(s ?? "").replace(/\n/g, " ");
  t = t.replace(/`\[([^`\]]*)`:[^\]]*\]/g, "$1"); // links -> label
  t = t.replace(/`[FB][0-9a-fA-F]{3}/g, ""); // color starts
  t = t.replace(/`[fb!*_=cla]/g, ""); // color/style/align resets + toggles
  t = t.replace(/\\`/g, "`"); // esc()'d backticks back to literal
  t = t.replace(/^\\([>#-])/, "$1"); // guardBlock line-start escapes
  return t;
}

function wrapText(text, width) {
  const words = String(text).split(/\s+/).filter(Boolean);
  const lines = [];
  let cur = "";
  for (const w of words) {
    if (!cur.length) cur = w;
    else if (cur.length + 1 + w.length <= width) cur += " " + w;
    else {
      lines.push(cur);
      cur = w;
    }
    while (cur.length > width) {
      lines.push(cur.slice(0, width));
      cur = cur.slice(width);
    }
  }
  if (cur.length) lines.push(cur);
  return lines.length ? lines : [""];
}

function padCell(text, width, align) {
  const pad = width - text.length;
  if (pad <= 0) return text;
  if (align === "right") return " ".repeat(pad) + text;
  if (align === "center") {
    const l = Math.floor(pad / 2);
    return " ".repeat(l) + text + " ".repeat(pad - l);
  }
  return text + " ".repeat(pad);
}

/** Self-aligned monospace table emitted as NORMAL micron lines. Deliberately
 *  NOT the `t native-table tag: `t is a newer-NomadNet extension -- older
 *  NomadNet builds and MeshChat's web renderer print the raw GFM pipe rows
 *  unaligned ("the spacing is all off"), and even the native renderer
 *  measures raw link syntax when sizing columns. We draw the borders and do
 *  the width math ourselves on STRIPPED visible text, so alignment is exact
 *  on every client. Normal (non-literal) lines keep tag interpretation, so
 *  cells may carry live links and colors (the masthead already proves both
 *  clients preserve runs of spaces in normal lines); a formatted cell is
 *  emitted verbatim when its visible width fits its column, and falls back
 *  to stripped, word-wrapped plain text when it must wrap (wrapping can't
 *  safely split micron tags; never truncated -- mirror prose stays
 *  verbatim). headers: string[]; aligns: ("left"|"center"|"right") same
 *  length; rows: string[][] (formatted cell text; micron tags welcome). */
export function table(headers, aligns, rows) {
  const a = aligns ?? headers.map(() => "left");
  const nCols = headers.length;
  const stripHead = headers.map(stripMicron);
  const stripBody = rows.map((r) => r.map(stripMicron));

  const widths = stripHead.map((h) => h.length);
  for (const r of stripBody) r.forEach((c, i) => { if (i < nCols) widths[i] = Math.max(widths[i], c.length); });

  // Fit to PAGE_WIDTH: total = cells + 3 per column (2 padding + 1 border) + closing border.
  const MIN_COL = 8;
  let excess = widths.reduce((s, w) => s + w, 0) + nCols * 3 + 1 - PAGE_WIDTH;
  if (excess > 0) {
    const order = widths.map((w, i) => [w, i]).sort((x, y) => y[0] - x[0]);
    for (const [, i] of order) {
      if (excess <= 0) break;
      const cut = Math.min(excess, widths[i] - MIN_COL);
      if (cut > 0) {
        widths[i] -= cut;
        excess -= cut;
      }
    }
  }

  // Pad the FORMATTED cell by its visible (stripped) width so embedded tags
  // don't count against the column; renderers display the label/colored text
  // at exactly the stripped width, keeping the borders aligned.
  const padFormatted = (formatted, visible, width, align) => {
    const pad = width - visible.length;
    if (pad <= 0) return formatted;
    if (align === "right") return " ".repeat(pad) + formatted;
    if (align === "center") {
      const l = Math.floor(pad / 2);
      return " ".repeat(l) + formatted + " ".repeat(pad - l);
    }
    return formatted + " ".repeat(pad);
  };

  const hline = (l, m, r) => l + widths.map((w) => "─".repeat(w + 2)).join(m) + r;
  const renderRow = (formattedCells, strippedCells, align) => {
    // Cells that fit stay formatted on a single line; cells that must wrap
    // fall back to stripped text split across continuation lines.
    const cellLines = strippedCells.map((c, i) => {
      const formatted = formattedCells[i] ?? "";
      if (c.length <= widths[i]) return { formatted: [formatted], stripped: [c] };
      const wrapped = wrapText(c, widths[i]);
      return { formatted: wrapped, stripped: wrapped };
    });
    const height = Math.max(...cellLines.map((c) => c.formatted.length));
    const lines = [];
    for (let ln = 0; ln < height; ln++) {
      lines.push(
        "│" +
          widths
            .map((w, i) => {
              const f = cellLines[i]?.formatted[ln] ?? "";
              const s = cellLines[i]?.stripped[ln] ?? "";
              return " " + padFormatted(f, s, w, ln === 0 ? align[i] : "left") + " ";
            })
            .join("│") +
          "│",
      );
    }
    return lines;
  };

  const out = [hline("┌", "┬", "┐")];
  out.push(...renderRow(stripHead, stripHead, stripHead.map(() => "left")));
  out.push(hline("├", "┼", "┤"));
  rows.forEach((r, ri) => out.push(...renderRow(r, stripBody[ri], a)));
  out.push(hline("└", "┴", "┘"));
  return guardBlock(out.join("\n")) + "\n\n";
}

/** Text input field. size/masked optional. */
export function inputField(name, { prefill = "", size, masked = false } = {}) {
  const params = [];
  if (masked) params.push("!");
  if (size) params.push(String(size));
  const prefix = params.length ? params.join("|") + "|" + name : name;
  return "`<" + prefix + "`" + esc(prefill) + ">";
}

export function reading(text, r) {
  const color = r === "clear positive" ? COLOR.pos : r === "clear negative" ? COLOR.neg : r === "insufficient confidence" ? COLOR.muted : COLOR.mixed;
  return fg(color, text);
}

export function scoreColor(score) {
  if (score >= 3) return COLOR.pos;
  if (score <= -3) return COLOR.neg;
  return COLOR.mixed;
}

export function fmtScore(n) {
  if (n === null || n === undefined) return "-";
  const fixed = n.toFixed(n % 1 === 0 ? 1 : 2);
  return n > 0 ? `+${fixed}` : fixed;
}

export function fmtConf(n) {
  if (n === null || n === undefined) return "-";
  return `${Math.round(n * 100)}%`;
}

// -----------------------------------------------------------------------------
// Page-width layout helpers: centering a masthead block and laying out a
// newspaper-style card grid both need a target column budget and a way to
// measure text that may already carry micron color/formatting tags (whose
// bytes must NOT count toward visible width). NomadNet's TUI actually
// reflows to the client's real terminal width -- this is a target, not a
// guarantee, picked to read well in a typical terminal without the grid or
// centered masthead overflowing a narrower one.
// -----------------------------------------------------------------------------
export const PAGE_WIDTH = 96;

/** Strip micron inline-formatting tags so width math counts only what
 *  actually prints. Covers the short 3-hex `F`/`B` color form and the
 *  bold/italic/underline toggles this codebase emits (see fg()/bg()/bold()
 *  above) -- not the `FT truecolor form, which nothing here uses. */
function visibleWidth(s) {
  return String(s ?? "")
    .replace(/`[FB][0-9a-fA-F]{3}/g, "")
    .replace(/`[fb!_*]/g, "").length;
}

/** Center a single already-formatted line within `width` columns by
 *  left-padding with plain spaces (measured on visible, tag-stripped width).
 *  Never truncates -- a line wider than `width` is returned unpadded.
 *  NOTE: this only looks centered on a `width`-column terminal -- NomadNet
 *  reflows to the READER's actual display width, so a reader wider or
 *  narrower than `width` sees it off-center. Kept for callers that genuinely
 *  need a fixed-width layout budget (e.g. cardGrid()'s bordered ASCII cards,
 *  which must hard-wrap at a known column count); the masthead does NOT use
 *  this -- see centerBlockNative() below for the native-alignment-tag path
 *  that centers correctly at the reader's real width. */
export function centerLine(text, width = PAGE_WIDTH) {
  const pad = Math.max(0, Math.floor((width - visibleWidth(text)) / 2));
  return " ".repeat(pad) + text;
}

/** Center a multi-line block as a single unit: every row gets the SAME
 *  left-pad, derived from the block's widest row -- centering each row
 *  independently would stagger a banner/logo out of its own shape. Returns
 *  an array of padded lines (caller joins with "\n"). Same fixed-`width`
 *  caveat as centerLine() -- see centerBlockNative() for the masthead's
 *  actual centering path. */
export function centerBlock(lines, width = PAGE_WIDTH) {
  const maxW = Math.max(0, ...lines.map(visibleWidth));
  const pad = " ".repeat(Math.max(0, Math.floor((width - maxW) / 2)));
  return lines.map((l) => pad + l);
}

// -----------------------------------------------------------------------------
// Native micron alignment: MicronParser.py reads an alignment tag at the
// START of a physical line and centers/aligns THAT line's urwid.Text widget
// at the reader's own real render width (not a guessed column count) --
// state persists line to line until changed, but Guide.py's documented
// convention is to place the tag at the start of every line it should apply
// to, which is what centerBlockNative()/callers below do. `a restores
// whatever the default alignment was (left, for this site).
// -----------------------------------------------------------------------------
export const ALIGN_CENTER = "`c";
export const ALIGN_LEFT = "`l";
export const ALIGN_RIGHT = "`r";
export const ALIGN_RESET = "`a";

/** Right-pad every line to the SAME visible width (the block's widest row),
 *  measured with visibleWidth() so embedded `F/`B color tags don't count.
 *  Used before native `c centering: `c centers each physical line
 *  independently by that line's own width, so a multi-row banner/logo whose
 *  rows differ in visible width would go jagged -- equalizing width first
 *  makes every row shift by the same amount, keeping the block rigid. */
function padBlockToEqualWidth(lines) {
  const maxW = Math.max(0, ...lines.map(visibleWidth));
  return lines.map((l) => l + " ".repeat(Math.max(0, maxW - visibleWidth(l))));
}

/** Center a multi-line block using micron's NATIVE `c alignment tag (see
 *  above) instead of space-padding to a guessed page width -- this is what
 *  the masthead uses. Equalizes row width first (padBlockToEqualWidth) so
 *  the block centers as one rigid unit, then prefixes every row with `c.
 *  Callers MUST emit ALIGN_RESET on its own line afterward -- alignment
 *  otherwise persists into whatever content follows. */
export function centerBlockNative(lines) {
  return padBlockToEqualWidth(lines).map((l) => ALIGN_CENTER + l);
}

// -----------------------------------------------------------------------------
// ASCII masthead: a deterministic 5-row block-letter pixel font, hand-authored
// per glyph (1 = ink, 0 = background), no external asset -- so it regenerates
// exactly the same every render, same discipline as everything else in this
// pipeline. Only the glyphs "THE MILD TAKE" needs are defined; extend GLYPHS
// before calling asciiBanner with new text.
// -----------------------------------------------------------------------------
const GLYPHS = {
  T: ["11111", "00100", "00100", "00100", "00100"],
  H: ["10001", "10001", "11111", "10001", "10001"],
  E: ["11111", "10000", "11110", "10000", "11111"],
  M: ["10001", "11011", "10101", "10001", "10001"],
  I: ["11111", "00100", "00100", "00100", "11111"],
  L: ["10000", "10000", "10000", "10000", "11111"],
  D: ["11110", "10001", "10001", "10001", "11110"],
  A: ["01110", "10001", "11111", "10001", "10001"],
  K: ["10001", "10010", "11100", "10010", "10001"],
  // Added for codec-website's masthead ("CODEC" / "CODEC AI") -- not part of
  // the original themildtake letterforms, same 5-row block-letter style.
  C: ["01111", "10000", "10000", "10000", "01111"],
  O: ["01110", "10001", "10001", "10001", "01110"],
  " ": ["000", "000", "000", "000", "000"],
};
const INK = "█"; // full block
const BG = "░"; // light shade

/** Render `text` as a 5-row block-letter banner using GLYPHS. Uses INK for
 *  "1" pixels and BG (not blank space) for "0" pixels and inter-glyph gaps,
 *  so the result reads as one solid masthead rather than letters floating in
 *  whitespace. Caller wraps the result in literalBlock() so it survives
 *  verbatim (micron line-start escaping would otherwise mangle a row that
 *  happens to start with a tag character). */
export function asciiBanner(text) {
  const chars = text.toUpperCase().split("");
  const rows = ["", "", "", "", ""];
  chars.forEach((ch, i) => {
    const g = GLYPHS[ch];
    if (!g) throw new Error(`asciiBanner: no glyph defined for ${JSON.stringify(ch)}`);
    for (let r = 0; r < 5; r++) {
      rows[r] += g[r].replace(/1/g, INK).replace(/0/g, BG);
      if (i < chars.length - 1) rows[r] += BG; // 1-col gap, same fill as background
    }
  });
  return rows.join("\n");
}

/** Render `words` (e.g. ["THE", "MILD", "TAKE"]) as one block-letter banner,
 *  identical in shape/spacing to asciiBanner(words.join(" ")), but with each
 *  word optionally wrapped in its own `F color (colors[i], or falsy to leave
 *  it the default foreground) -- so the mesh masthead can echo the web
 *  wordmark's "the`MILD`take" treatment (Base.astro .brand__accent, the same
 *  #3B82F6 / `38f as the logo's blue bar). The inter-word gap is derived from
 *  GLYPHS[" "]'s own width (1 gap col + space-glyph width + 1 gap col) so it
 *  exactly matches what asciiBanner() would have produced for a literal
 *  space character between words -- this is a color overlay, not a re-layout.
 *  Colors are real `F tags, so callers must NOT wrap the result in
 *  literalBlock() (same caveat as logoMark()). */
export function asciiBannerColored(words, colors = []) {
  const gap = BG.repeat(1 + GLYPHS[" "][0].length + 1);
  const rows = ["", "", "", "", ""];
  words.forEach((word, wi) => {
    const wordRows = asciiBanner(word).split("\n");
    for (let r = 0; r < 5; r++) {
      if (wi > 0) rows[r] += gap;
      rows[r] += colors[wi] ? fg(colors[wi], wordRows[r]) : wordRows[r];
    }
  });
  return rows.join("\n");
}

// -----------------------------------------------------------------------------
// Logo mark: the site's actual mark (public/favicon.svg, same shape as
// public/logo.svg) is 4 rounded bars rising left to right -- red, amber,
// green, blue -- bottom-aligned, on a dark rounded-square background
// (viewBox 32x32: red y=20.5 h=6.5, amber y=15 h=12, green y=9 h=18,
// blue y=5 h=22, all bottoming out at y=27). Approximated here as a
// LOGO_BAR_ROWS-tall grid of colored block glyphs so it can sit inline next
// to asciiBanner()'s letterforms (same row count). Heights below are each
// bar's SVG height scaled against the tallest bar (blue) and rounded to the
// nearest row -- 6.5/22, 12/22, 18/22, 22/22 of LOGO_BAR_ROWS -- so the
// silhouette matches the source mark's proportions, not just "ascending."
// 12-bit hex triads are each channel's SVG hex byte's high nibble (e.g.
// EF4444 -> e,4,4), the same shorthand COLOR above uses; micron's palette
// depth can't reproduce the SVG's exact hues, only their hue family.
// -----------------------------------------------------------------------------
const LOGO_COLORS = ["e44", "f90", "1b8", "38f"]; // red, amber, green, blue
const LOGO_BAR_ROWS = 5;
const LOGO_HEIGHTS = [2, 3, 4, 5]; // lit rows from the bottom, out of LOGO_BAR_ROWS

/** Render the ascending-bar graph mark as an array of LOGO_BAR_ROWS already
 *  micron-tagged strings (top row first), each bar 2 columns wide with a
 *  1-column gap. Deterministic, no image asset read at render time. Colors
 *  are real micron `F tags, so callers must NOT pass this through
 *  literalBlock() -- literal mode suspends all tag interpretation, which
 *  would print the tag bytes instead of coloring the blocks. */
export function logoMark() {
  const rows = [];
  for (let r = 0; r < LOGO_BAR_ROWS; r++) {
    const fromBottom = LOGO_BAR_ROWS - 1 - r;
    const cells = LOGO_HEIGHTS.map((h, i) => (fromBottom < h ? fg(LOGO_COLORS[i], "██") : "  "));
    rows.push(cells.join(" "));
  }
  return rows;
}

// -----------------------------------------------------------------------------
// Newspaper-style card: a bordered ASCII box for one item (news headline,
// eventually reusable anywhere a "clip" reads better than a line-item list).
// -----------------------------------------------------------------------------
const BOX = { tl: "┌", tr: "┐", bl: "└", br: "┘", h: "─", v: "│" };

/** Greedy word-wrap to `width` columns; a single word longer than `width` is
 *  hard-broken so the card border is never exceeded. */
function wrapWords(text, width) {
  const words = String(text ?? "").split(/\s+/).filter(Boolean);
  const lines = [];
  let cur = "";
  for (const w of words) {
    const next = cur ? `${cur} ${w}` : w;
    if (next.length > width) {
      if (cur) lines.push(cur);
      if (w.length > width) {
        let rest = w;
        while (rest.length > width) {
          lines.push(rest.slice(0, width));
          rest = rest.slice(width);
        }
        cur = rest;
      } else {
        cur = w;
      }
    } else {
      cur = next;
    }
  }
  if (cur) lines.push(cur);
  return lines.length ? lines : [""];
}

/** Draw a bordered ASCII "card": a newspaper-clip box `width` columns wide
 *  (interior), one item per call. `sections` is an array of plain-text
 *  strings (each word-wrapped onto its own row(s)) and/or `{ blank: true }`
 *  spacer rows between them. Plain text only -- this is meant to sit inside
 *  literalBlock(), where micron color/link tags do not render (literal mode
 *  suspends all tag interpretation), so callers should not pass pre-tagged
 *  micron strings here. */
export function card(sections, width = 64) {
  const top = BOX.tl + BOX.h.repeat(width + 2) + BOX.tr;
  const bot = BOX.bl + BOX.h.repeat(width + 2) + BOX.br;
  const rows = [top];
  for (const sec of sections) {
    if (sec == null) continue;
    if (sec.blank) {
      rows.push(BOX.v + " ".repeat(width + 2) + BOX.v);
      continue;
    }
    const text = typeof sec === "string" ? sec : sec.text;
    for (const line of wrapWords(text, width)) {
      rows.push(`${BOX.v} ${line.padEnd(width)} ${BOX.v}`);
    }
  }
  rows.push(bot);
  return rows.join("\n");
}

/** Compose pre-rendered card() blocks into a newspaper-style grid: `cols`
 *  cards per row, left-to-right then top-to-bottom, so handing cards in
 *  already-sorted order (newest/highest-weight first) reads like newspaper
 *  columns. Cards sharing a row are padded to that row's tallest card
 *  (blank bordered interior rows) so ragged content heights don't stagger
 *  the grid; a short final row just leaves the remaining column(s) blank.
 *  All cards must share one `card()` width (the caller's job -- not
 *  validated here). Returns a single block of lines (join with "\n") --
 *  wrap the WHOLE grid in one literalBlock() call, not per card, since a
 *  physical output line here is spliced together from multiple cards. */
export function cardGrid(cardBlocks, { cols = 2, gap = 2 } = {}) {
  if (!cardBlocks.length) return "";
  const grids = cardBlocks.map((b) => b.split("\n"));
  const colWidth = Math.max(...grids.map((lines) => lines[0].length));
  const blankRow = " ".repeat(colWidth);
  const gapStr = " ".repeat(gap);
  const out = [];
  for (let i = 0; i < grids.length; i += cols) {
    const rowCards = grids.slice(i, i + cols);
    const height = Math.max(...rowCards.map((c) => c.length));
    for (let r = 0; r < height; r++) {
      out.push(rowCards.map((c) => (c[r] ?? blankRow).padEnd(colWidth)).join(gapStr));
    }
  }
  return out.join("\n");
}

/** Page header block shared by content pages: title + meta line + divider. */
export function pageHeader({ title, meta, tags }) {
  let out = fg(COLOR.accent, bold(escText(title))) + "\n\n";
  if (meta) out += fg(COLOR.muted, escText(meta)) + "\n\n";
  if (tags && tags.length) out += fg(COLOR.muted, italic(escText(tags.join(", ")))) + "\n\n";
  out += divider();
  return out;
}
