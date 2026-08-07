import { defineConfig } from "astro/config";
import tailwindcss from "@tailwindcss/vite";
import sitemap from "@astrojs/sitemap";

const EXCLUDED_PATH_PREFIXES = ["/admin/", "/carrito", "/privacidad"];

export default defineConfig({
	site: "https://taqto.com.pe",

	base: "/",

	integrations: [
		sitemap({
			filter: (page) => {
				const { pathname } = new URL(page);

				return !EXCLUDED_PATH_PREFIXES.some(
					(prefix) => pathname === prefix || pathname.startsWith(prefix),
				);
			},
		}),
	],

	vite: {
		plugins: [tailwindcss()],
	},
});