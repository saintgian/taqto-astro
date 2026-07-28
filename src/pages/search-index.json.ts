import { sanityClient, urlForImage } from "../lib/sanity";
import { searchIndexQuery } from "../lib/searchIndexQuery";
import {
	formatPEN,
	getProductPriceRange,
} from "../lib/productPricing";

interface PriceSource {
	price?: number;
	salePrice?: number;
	active?: boolean;
	wood?: string;
}

interface IndexedProduct {
	_id: string;
	title: string;
	slug: string;
	productMode?: string;
	saleStart?: string;
	saleEnd?: string;
	category?: string;
	subcategory?: string;
	image?: { alt?: string; asset?: unknown };
	uniqueProduct?: PriceSource;
	variants?: PriceSource[];
}

export async function GET() {
	const products =
		await sanityClient.fetch<IndexedProduct[]>(searchIndexQuery);

	const searchIndex = products.map((product) => {
		const priceRange = getProductPriceRange(product);

		const priceLabel =
			priceRange.minimum > 0
				? priceRange.hasRange
					? `Desde ${formatPEN(priceRange.minimum)}`
					: formatPEN(priceRange.minimum)
				: "";

		const imageUrl = product.image?.asset
			? urlForImage(product.image)
					.width(160)
					.height(160)
					.fit("crop")
					.auto("format")
					.url()
			: "";

		const woods = new Set<string>();

		if (product.uniqueProduct?.wood) {
			woods.add(product.uniqueProduct.wood);
		}

		(product.variants || []).forEach((variant) => {
			if (variant.active !== false && variant.wood) {
				woods.add(variant.wood);
			}
		});

		return {
			id: product._id,
			title: product.title,
			slug: product.slug,
			category: product.category || "",
			subcategory: product.subcategory || "",
			wood: Array.from(woods).join(", "),
			image: imageUrl,
			imageAlt: product.image?.alt || product.title,
			price: priceLabel,
		};
	});

	return new Response(JSON.stringify(searchIndex), {
		headers: {
			"Content-Type": "application/json",
		},
	});
}
