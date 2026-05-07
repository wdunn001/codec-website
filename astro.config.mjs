import { defineConfig } from "astro/config";

export default defineConfig({
  site: "https://codecai.net",
  build: {
    inlineStylesheets: "auto",
  },
  compressHTML: true,
});
