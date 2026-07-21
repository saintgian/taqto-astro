interface PriceSource {
	price?: number;
	salePrice?: number;
	active?: boolean;
}

interface ProductPriceInput {
	productMode?: string;
	saleStart?: string;
	saleEnd?: string;

	uniqueProduct?: PriceSource;

	variants?: PriceSource[];
}

export function isSaleActive(
	saleStart?: string,
	saleEnd?: string,
) {
	const now = Date.now();

	if (
		saleStart &&
		now < new Date(saleStart).getTime()
	) {
		return false;
	}

	if (
		saleEnd &&
		now > new Date(saleEnd).getTime()
	) {
		return false;
	}

	return true;
}

export function getVisiblePrice(
	source: PriceSource,
	saleActive: boolean,
) {
	if (
		saleActive &&
		typeof source.salePrice === "number"
	) {
		return source.salePrice;
	}

	return source.price;
}

export function getProductPriceRange(
	product: ProductPriceInput,
) {
	const saleActive = isSaleActive(
		product.saleStart,
		product.saleEnd,
	);

	const sources =
		product.productMode === "unique"
			? product.uniqueProduct
				? [product.uniqueProduct]
				: []
			: (product.variants || []).filter(
					(variant) =>
						variant.active !== false,
				);

	const prices = sources
		.map((source) =>
			getVisiblePrice(source, saleActive),
		)
		.filter(
			(price): price is number =>
				typeof price === "number" &&
				price > 0,
		);

	if (prices.length === 0) {
		return {
			minimum: 0,
			maximum: 0,
			hasRange: false,
		};
	}

	const minimum = Math.min(...prices);
	const maximum = Math.max(...prices);

	return {
		minimum,
		maximum,
		hasRange: minimum !== maximum,
	};
}

export function formatPEN(value: number) {
	return new Intl.NumberFormat("es-PE", {
		style: "currency",
		currency: "PEN",
		minimumFractionDigits: 2,
	}).format(value);
}