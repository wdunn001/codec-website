// RSS feed for the customer-facing What's New changelog. Mirrors the Mass
// Zero `mass-zero-editorial.rss` pattern: one item per changelog entry,
// newest-first, RSS 2.0 with the Atom self-link extension. Consumers
// (RSS readers, third-party aggregators) get notified on every release
// without having to scrape /changelog.
//
// The deeper engineering changelog (commit lists, fork SHAs, image digests)
// stays in GitHub Releases, every <item> SHOULD include at least one
// <link>-equivalent in the body that points to the corresponding release.

import rss from "@astrojs/rss";
import { getCollection } from "astro:content";
import type { APIContext } from "astro";

export async function GET(context: APIContext) {
  const entries = await getCollection("changelog");
  const sorted = entries.sort((a, b) => b.data.date.localeCompare(a.data.date));

  return rss({
    title: "Codec | What's new",
    description:
      "Customer-facing release notes for Codec, the token-native binary transport protocol for AI APIs.",
    site: context.site ?? "https://codecai.net",
    items: sorted.map((entry) => {
      // Slug strips the .md suffix so the URL matches /changelog/[...slug].astro.
      const slug = entry.id.replace(/\.md$/, "");
      // Append the link list to the description so the RSS reader has the
      // GitHub Release / spec / docs anchors inline.
      const linksList = entry.data.links
        .map((l) => `<a href="${l.url}">${l.label}</a>`)
        .join(" &middot; ");
      const description =
        linksList.length > 0
          ? `<p>${entry.data.summary}</p><p>${linksList}</p>`
          : `<p>${entry.data.summary}</p>`;
      return {
        title: entry.data.title,
        link: `/changelog/${slug}/`,
        // Date as ISO at noon UTC to avoid timezone drift in date-only entries.
        pubDate: new Date(`${entry.data.date}T12:00:00Z`),
        description,
        // RSS 2.0 categories double as Atom <category term="…">. Carries the
        // kind chip (feature / improvement / fix) so subscribers can filter.
        categories: [entry.data.kind, ...(entry.data.version ? [entry.data.version] : [])],
      };
    }),
    // The customXMLData hook would let us add Atom self-link / language /
    // ttl, but @astrojs/rss already emits a sensible default, keep this
    // file lean and let the package handle the boilerplate.
    customData: `<language>en-us</language>`,
  });
}
