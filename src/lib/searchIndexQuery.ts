export const searchIndexQuery = `
	*[
		_type == "product" &&
		active == true &&
		defined(slug.current)
	] | order(_createdAt desc) {
		_id,
		title,
		"slug": slug.current,
		productMode,
		saleStart,
		saleEnd,

		"category": category->title,
		"subcategory": subcategory->title,

		"image": gallery[0]{ alt, asset },

		uniqueProduct {
			price,
			salePrice,
			"wood": wood->title
		},

		variants[] {
			price,
			salePrice,
			active,
			"wood": wood->title
		}
	}
`;
