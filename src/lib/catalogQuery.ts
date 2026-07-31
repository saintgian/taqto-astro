// Extiende productDetailQuery con los campos necesarios para el
// catalogo completo de /tienda/: fecha de creacion (ordenar por mas
// recientes), destacado (orden "Destacados") y si incluye grabado
// (unico campo real de personalizacion en el schema de producto).
//
// El orden "featured desc, _createdAt desc" replica exactamente el
// comparador por defecto ("Destacados") del filtro en cliente
// (tienda/index.astro). Si difirieran, el grid se reordenaria de
// forma visible justo despues de que el script de filtros corra,
// porque ese script siempre llama a apply() (y por lo tanto
// sortItems()) al cargar la pagina, incluso sin filtros activos.
export const catalogQuery = `
	*[
		_type == "product" &&
		active == true &&
		defined(slug.current)
	] | order(featured desc, _createdAt desc) {
		_id,
		_createdAt,
		title,
		"slug": slug.current,
		shortDescription,
		productMode,
		featured,
		saleStart,
		saleEnd,
		engravingIncluded,

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
		}
	}
`;
