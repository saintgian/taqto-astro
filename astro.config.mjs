import { defineConfig } from "astro/config";

export default defineConfig(({ command }) => {
	const isBuild = command === "build";

	return {
		site: "https://saintgian.github.io",
		base: isBuild ? "/taqto-astro" : "/",
	};
});