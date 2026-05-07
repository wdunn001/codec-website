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

export const collections = { docs };
