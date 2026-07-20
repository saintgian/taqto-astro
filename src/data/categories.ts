export interface Subcategory {
	name: string;
	slug: string;
	description: string;
}

export interface ProductCategory {
	name: string;
	slug: string;
	eyebrow: string;
	description: string;
	subcategories: Subcategory[];
}

export const productCategories: ProductCategory[] = [
	{
		name: "Parrilla",
		slug: "parrilla",
		eyebrow: "Para quienes dominan el fuego",
		description:
			"Tablas, accesorios y sets diseñados para una experiencia parrillera robusta, funcional y personalizada.",
		subcategories: [
			{
				name: "Tablas parrilleras",
				slug: "tablas-parrilleras",
				description:
					"Tablas de madera de gran formato para cortar, servir y presentar carnes.",
			},
			{
				name: "Cuchillos y accesorios",
				slug: "cuchillos-y-accesorios",
				description:
					"Complementos funcionales para preparar, cortar y servir en la parrilla.",
			},
			{
				name: "Mandiles",
				slug: "mandiles",
				description:
					"Mandiles de diseño resistente para cocinar y trabajar frente al fuego.",
			},
			{
				name: "Sets parrilleros",
				slug: "sets-parrilleros",
				description:
					"Combinaciones de piezas seleccionadas para regalar o completar la experiencia parrillera.",
			},
		],
	},
	{
		name: "Cocina y Mesa",
		slug: "cocina-y-mesa",
		eyebrow: "Objetos para compartir",
		description:
			"Piezas cálidas y contemporáneas para preparar, presentar y disfrutar cada momento alrededor de la mesa.",
		subcategories: [
			{
				name: "Tablas de cocina",
				slug: "tablas-de-cocina",
				description:
					"Superficies funcionales de madera para la preparación cotidiana de alimentos.",
			},
			{
				name: "Tablas de queso y charcutería",
				slug: "tablas-de-queso-y-charcuteria",
				description:
					"Tablas diseñadas para presentar quesos, embutidos, frutas y aperitivos.",
			},
			{
				name: "Bandejas",
				slug: "bandejas",
				description:
					"Bandejas de madera para servir bebidas, alimentos y pequeños objetos.",
			},
			{
				name: "Posavasos y posatazas",
				slug: "posavasos-y-posatazas",
				description:
					"Piezas compactas que protegen la mesa y aportan calidez a cada bebida.",
			},
			{
				name: "Accesorios de mesa",
				slug: "accesorios-de-mesa",
				description:
					"Complementos de madera para organizar, servir y personalizar la mesa.",
			},
		],
	},
	{
		name: "Oficina",
		slug: "oficina",
		eyebrow: "Orden con carácter",
		description:
			"Accesorios de escritorio que combinan precisión, funcionalidad y una presencia visual cálida.",
		subcategories: [
			{
				name: "Organizadores de escritorio",
				slug: "organizadores-de-escritorio",
				description:
					"Sistemas compactos para mantener dispositivos, útiles y objetos personales organizados.",
			},
			{
				name: "Soportes para celular",
				slug: "soportes-para-celular",
				description:
					"Soportes de madera para mantener el teléfono visible, estable y accesible.",
			},
			{
				name: "Soportes para laptop",
				slug: "soportes-para-laptop",
				description:
					"Soluciones de madera para elevar, organizar y mejorar el espacio de trabajo.",
			},
			{
				name: "Accesorios de escritorio",
				slug: "accesorios-de-escritorio",
				description:
					"Complementos funcionales para construir un escritorio ordenado y coherente.",
			},
		],
	},
	{
		name: "Kits y regalos",
		slug: "kits-y-regalos",
		eyebrow: "Regalos con identidad",
		description:
			"Selecciones de piezas personalizables para celebrar, agradecer y crear recuerdos duraderos.",
		subcategories: [
			{
				name: "Kits parrilleros",
				slug: "kits-parrilleros",
				description:
					"Combinaciones de productos pensadas para aficionados y amantes de la parrilla.",
			},
			{
				name: "Kits de cocina",
				slug: "kits-de-cocina",
				description:
					"Conjuntos funcionales para cocinar, servir y compartir alrededor de la mesa.",
			},
			{
				name: "Regalos personalizados",
				slug: "regalos-personalizados",
				description:
					"Piezas de madera y cuero personalizadas mediante grabado láser gratuito.",
			},
			{
				name: "Regalos para ocasiones",
				slug: "regalos-para-ocasiones",
				description:
					"Opciones diseñadas para aniversarios, cumpleaños, matrimonios y fechas especiales.",
			},
		],
	},
	{
		name: "Empresas",
		slug: "empresas",
		eyebrow: "Soluciones para empresas",
		description:
			"Regalos corporativos y producción al por mayor con atención consultiva, mockup previo y personalización.",
		subcategories: [
			{
				name: "Regalos corporativos",
				slug: "regalos-corporativos",
				description:
					"Propuestas personalizadas para clientes, colaboradores, eventos y campañas corporativas.",
			},
			{
				name: "Ventas al por mayor",
				slug: "ventas-al-por-mayor",
				description:
					"Producción de piezas TAQTO para compras por volumen y necesidades comerciales.",
			},
		],
	},
];

export function getCategoryBySlug(slug: string) {
	return productCategories.find((category) => category.slug === slug);
}

export function getSubcategoryBySlug(
	categorySlug: string,
	subcategorySlug: string,
) {
	const category = getCategoryBySlug(categorySlug);

	const subcategory = category?.subcategories.find(
		(item) => item.slug === subcategorySlug,
	);

	return {
		category,
		subcategory,
	};
}