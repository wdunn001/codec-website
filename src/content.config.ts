import { defineCollection, z } from "astro:content";
import { glob } from "astro/loaders";

const docs = defineCollection({
  loader: glob({ pattern: "**/*.md", base: "./src/content/docs" }),
  schema: z.object({
    title: z.string(),
    description: z.string().optional(),
    section: z.enum(["Start", "Frameworks", "Server", "Reference"]).default("Reference"),
    order: z.number().default(99),
    status: z.enum(["ready", "draft"]).default("ready"),
  }),
});

// Customer-facing "What's new" feed. One entry per release-worthy change.
// The deeper engineering changelog lives in GitHub Releases — every entry
// here SHOULD link out to the corresponding release for the full commit
// list, fork SHAs, and image digests.
//
// Schema mirrors Mass Zero's customerChangelogEntries pattern (kind chips
// + summary + optional details), adapted to Astro's content collections.
const changelog = defineCollection({
  loader: glob({ pattern: "**/*.md", base: "./src/content/changelog" }),
  schema: z.object({
    title: z.string(),
    /** ISO date (YYYY-MM-DD). Sort key — newest first. */
    date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "date must be ISO YYYY-MM-DD"),
    /** Visual chip on the entry card. */
    kind: z.enum(["feature", "improvement", "fix"]),
    /** Customer-language one-liner shown under the title. */
    summary: z.string(),
    /**
     * Optional version this entry shipped as. Free-form (e.g. "v0.3.0",
     * "v0.3.1"). Used for sectioning + version pages later if we add them.
     */
    version: z.string().optional(),
    /**
     * Outbound links — at least one SHOULD point to the corresponding
     * GitHub Release (engineering-grade changelog). Optional spec / docs
     * anchors for deep dives.
     */
    links: z
      .array(
        z.object({
          label: z.string(),
          url: z.string().url(),
        }),
      )
      .default([]),
  }),
});

export const collections = { docs, changelog };
