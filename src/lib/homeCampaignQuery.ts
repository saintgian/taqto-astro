export const homeCampaignQuery = `
	*[_type == "homeCampaign"][0] {
		enabled,
		eyebrow,
		title,
		description,
		ctaLabel,
		ctaLink,
		alt,
		theme,
		layoutMode,
		contentPosition,
		overlayStrength,
		desktopImage,
		mobileImage,

		featuredProduct-> {
			_id,
			title,
			"slug": slug.current,
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
				available
			},

			variants[] {
				_key,
				sku,
				price,
				salePrice,
				stockQuantity,
				active
			}
		}
	}
`;
