export const subcategoryPathsQuery = `
	*[
		_type == "subcategory" &&
		active == true &&
		defined(slug.current) &&
		defined(category)
	] | order(order asc) {
		_id,
		title,
		description,
		order,
		"slug": slug.current,

		"category": category->{
			_id,
			title,
			eyebrow,
			description,
			"slug": slug.current
		}
	}
`;

export const productsForSubcategoryQuery = `
	*[
		_type == "product" &&
		active == true &&
		defined(slug.current) &&
		category->slug.current == $categorySlug &&
		subcategory->slug.current == $subcategorySlug
	] | order(_createdAt desc) {
		_id,
		title,
		"slug": slug.current,
		sku,
		shortDescription,
		productMode,
		saleStart,
		saleEnd,

		gallery[] {
			_key,
			alt,
			caption,
			asset
		},

		uniqueProduct {
			price,
			salePrice,
			stockQuantity,
			available,

			"wood": wood->{
				title,
				"slug": slug.current
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
				"slug": slug.current
			},

			"size": size->{
				title,
				"slug": slug.current,
				dimensionsLabel
			}
		},

		"category": category->{
			title,
			"slug": slug.current
		},

		"subcategory": subcategory->{
			title,
			"slug": slug.current
		}
	}
`;