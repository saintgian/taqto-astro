import { defineConfig } from "astro/config";
import tailwindcss from "@tailwindcss/vite";

export default defineConfig({
	site: "https://taqto.com.pe",

	base: "/",

	vite: {
		plugins: [tailwindcss()],
	},
});