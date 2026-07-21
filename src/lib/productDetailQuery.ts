export const productDetailQuery = `
	*[
		_type == "product" &&
		active == true &&
		defined(slug.current)
	] | order(_createdAt desc) {
		_id,
		title,
		"slug": slug.current,
		sku,
		shortDescription,
		description,
		productMode,
		materials,
		careInstructions,
		saleStart,
		saleEnd,
		engravingIncluded,
		engravingTypes,
		engravingMaxCharacters,
		personalizationNotes,
		corporateEligible,
		metaTitle,
		metaDescription,

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