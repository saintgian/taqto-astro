export const featuredProductsQuery = `
	*[
		_type == "product" &&
		active == true &&
		featured == true &&
		defined(slug.current)
	] | order(_createdAt desc) {
		_id,
		title,
		"slug": slug.current,
		shortDescription,
		sku,
		productMode,
		saleStart,
		saleEnd,

		gallery[] {
			_key,
			alt,
			caption,
			asset
		},

		"category": category->{
			title,
			"slug": slug.current
		},

		"subcategory": subcategory->{
			title,
			"slug": slug.current
		},

		uniqueProduct {
			price,
			salePrice,
			stockQuantity,
			available,

			"wood": wood->{
				title,
				"slug": slug.current,
				image
			},

			"size": size->{
				title,
				"slug": slug.current,
				dimensionsLabel
			}
		},

		variants[] {
			_key,
			sku,
			price,
			salePrice,
			stockQuantity,
			active,

			"wood": wood->{
				title,
				"slug": slug.current,
				image
			},

			"size": size->{
				title,
				"slug": slug.current,
				dimensionsLabel
			}
		}
	}
`;
