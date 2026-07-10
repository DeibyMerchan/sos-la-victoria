import { defineConfig } from "astro/config";
import tailwind from "@astrojs/tailwind";
import vercel from "@astrojs/vercel";
import sitemap from "@astrojs/sitemap";

export default defineConfig({
  site: "https://sos-la-victoria.vercel.app",
  output: "server",
  integrations: [tailwind(), sitemap()],
  adapter: vercel(),
});
