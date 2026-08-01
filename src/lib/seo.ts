// Utilidades minimas de SEO compartidas por BaseLayout y las paginas que
// necesitan JSON-LD (breadcrumbs, FAQ). No construyen URLs con un dominio
// propio: siempre reciben `site` (Astro.site) y lo respetan tal cual esta
// configurado en astro.config.mjs.

export interface BreadcrumbLink {
	label: string;
	href?: string;
}

export function absoluteUrl(
	path: string,
	site: URL | undefined,
): string | undefined {
	if (!site) return undefined;
	return new URL(path, site).toString();
}

export function buildBreadcrumbJsonLd(
	items: BreadcrumbLink[],
	site: URL | undefined,
	fallbackUrl?: string,
): Record<string, unknown> | null {
	if (!site || items.length === 0) return null;

	return {
		"@context": "https://schema.org",
		"@type": "BreadcrumbList",
		itemListElement: items.map((item, index) => ({
			"@type": "ListItem",
			position: index + 1,
			name: item.label,
			item: item.href
				? absoluteUrl(item.href, site)
				: fallbackUrl,
		})),
	};
}

export interface FaqEntry {
	q: string;
	a: string | string[];
}

export function buildFaqJsonLd(
	faqs: FaqEntry[],
): Record<string, unknown> | null {
	if (faqs.length === 0) return null;

	return {
		"@context": "https://schema.org",
		"@type": "FAQPage",
		mainEntity: faqs.map((item) => ({
			"@type": "Question",
			name: item.q,
			acceptedAnswer: {
				"@type": "Answer",
				text: Array.isArray(item.a) ? item.a.join(" ") : item.a,
			},
		})),
	};
}
