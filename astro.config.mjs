import { defineConfig } from "astro/config";
import tailwindcss from "@tailwindcss/vite";

const isProduction =
	process.env.NODE_ENV === "production";

export default defineConfig({
	site: "https://saintgian.github.io",

	base: isProduction
		? "/taqto-astro"
		: "/",

	vite: {
		plugins: [tailwindcss()],
	},
});