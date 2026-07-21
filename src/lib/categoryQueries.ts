export const categoryPathsQuery = `
	*[
		_type == "category" &&
		active == true &&
		defined(slug.current)
	] | order(order asc) {
		_id,
		title,
		eyebrow,
		description,
		order,
		"slug": slug.current
	}
`;

export const navigationCategoriesQuery = `
	*[
		_type == "category" &&
		active == true &&
		defined(slug.current)
	] | order(order asc) {
		_id,
		title,
		eyebrow,
		"slug": slug.current,

		"subcategories": *[
			_type == "subcategory" &&
			active == true &&
			defined(slug.current) &&
			category._ref == ^._id
		] | order(order asc) {
			_id,
			title,
			"slug": slug.current
		}
	}
`;

export const categoryPageQuery = `
	*[
		_type == "category" &&
		active == true &&
		slug.current == $categorySlug
	][0] {
		_id,
		title,
		eyebrow,
		description,
		order,
		"slug": slug.current,

		"subcategories": *[
			_type == "subcategory" &&
			active == true &&
			category._ref == ^._id
		] | order(order asc) {
			_id,
			title,
			description,
			order,
			"slug": slug.current,

			"productCount": count(
				*[
					_type == "product" &&
					active == true &&
					subcategory._ref == ^._id
				]
			)
		},

		"products": *[
			_type == "product" &&
			active == true &&
			category._ref == ^._id &&
			defined(slug.current)
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
	}
`;