#!/usr/bin/env node
// Sincroniza el catalogo autoritativo de Supabase (catalog_products /
// catalog_variants, ver supabase/catalog_mirror.sql) desde Sanity.
//
// NO se ejecuta como parte de esta tarea. Cuando el propietario decida
// correrlo:
//   1) Aplicar supabase/catalog_mirror.sql en Supabase (si no esta).
//   2) Agregar SUPABASE_SECRET_KEY a su .env local (el valor esta en el
//      dashboard de Supabase, Project Settings -> API -> secret keys --
//      NUNCA usar esa key en codigo de frontend/navegador).
//   3) Correr: npm run sync:catalog
//
// Por que no importa src/lib/sanity.ts / catalogQuery.ts directamente:
// este script corre con Node puro (node --env-file=.env ...), sin el
// pipeline de TypeScript/Vite que usa Astro, asi que no puede importar
// archivos .ts tal cual. Se duplica aqui la configuracion minima
// (mismo projectId/dataset que src/lib/sanity.ts) en vez de armar un
// build step nuevo solo para este script.
//
// No instala dependencias nuevas: usa @sanity/client y
// @supabase/supabase-js, que ya estan en package.json.
//
// Politica de stock (desde que create_order_v2 descuenta stock de forma
// atomica en Supabase, ver supabase/harden_stock_atomic.sql):
//   - Uso normal (`npm run sync:catalog`): actualiza titulo, slug,
//     precio, oferta y estado activo desde Sanity, y crea variantes
//     nuevas con el stock inicial de Sanity, pero NUNCA reescribe
//     stock_quantity de una variante que ya existia -- eso es lo que se
//     vendio via create_order_v2 desde la ultima sincronizacion, y
//     reponerlo solo aqui borraria descuentos reales.
//   - Ejecutar esto cuando cambien productos/precios/ofertas en Sanity y
//     haya que reflejarlos antes de publicar. El build (`astro build`)
//     NO llama a este script; sincronizar es un paso manual aparte.
//   - Ajustes manuales de inventario (una unidad danada, un recuento
//     fisico distinto) se hacen directo en Supabase (tabla
//     catalog_variants) o, si el numero correcto ya esta actualizado en
//     Sanity, con el modo explicito de abajo -- nunca editando Sanity y
//     esperando que un sync normal lo traslade, porque no lo hace.
//   - Modo explicito `npm run sync:catalog -- --sync-stock`: SI puede
//     reemplazar stock_quantity desde Sanity, pero por defecto solo
//     previsualiza (muestra advertencia + cuantas variantes cambiarian,
//     no escribe nada). Para aplicar de verdad hace falta agregar
//     tambien --yes: `npm run sync:catalog -- --sync-stock --yes`. No
//     se activa nunca automaticamente durante build o deploy.

import { createClient as createSanityClient } from "@sanity/client";
import { createClient as createSupabaseClient } from "@supabase/supabase-js";

const SANITY_PROJECT_ID = "bap0il8i";
const SANITY_DATASET = "production";

const supabaseUrl = process.env.PUBLIC_SUPABASE_URL;

// SUPABASE_SECRET_KEY es la nomenclatura moderna de Supabase (reemplaza
// a la service role key). Se acepta SUPABASE_SERVICE_ROLE_KEY como
// fallback legado solo por si el proyecto todavia no migro esa clave en
// su dashboard, pero SUPABASE_SECRET_KEY es la preferida y se resuelve
// primero.
const secretKey =
	process.env.SUPABASE_SECRET_KEY || process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!supabaseUrl || !secretKey) {
	console.error(
		[
			"Faltan variables de entorno.",
			"Requeridas: PUBLIC_SUPABASE_URL, y SUPABASE_SECRET_KEY (o, como fallback legado, SUPABASE_SERVICE_ROLE_KEY).",
			"Corre este script con: node --env-file=.env scripts/sync-catalog.mjs",
			"Esa clave se agrega solo al .env local (o al entorno seguro de despliegue), nunca al frontend.",
		].join("\n"),
	);
	process.exit(1);
}

const cliArgs = process.argv.slice(2);
// --sync-stock: activa el modo que puede reemplazar stock_quantity desde
// Sanity (por defecto solo previsualiza). --yes: confirma la aplicacion
// real; sin ella, --sync-stock por si solo nunca escribe stock.
const syncStockRequested = cliArgs.includes("--sync-stock");
const syncStockApply = cliArgs.includes("--yes");

const sanity = createSanityClient({
	projectId: SANITY_PROJECT_ID,
	dataset: SANITY_DATASET,
	apiVersion: "2026-07-20",
	useCdn: false,
});

const supabase = createSupabaseClient(supabaseUrl, secretKey, {
	auth: { persistSession: false, autoRefreshToken: false },
});

// Sin token, el cliente de Sanity solo puede leer documentos publicados
// (no drafts): ya cumple "leer unicamente productos publicados" sin
// necesidad de filtrar por `active` en la consulta. `active` es un flag
// de negocio aparte ("publicado pero ya no a la venta"), no de
// publicacion, y se necesita ver tanto true como false para poder
// desactivar en el espejo lo que dejo de venderse.
const QUERY = `
	*[_type == "product" && defined(slug.current)] {
		_id,
		"slug": slug.current,
		title,
		active,
		productMode,
		saleStart,
		saleEnd,
		sku,
		uniqueProduct {
			price,
			salePrice,
			stockQuantity,
			available,
			"woodTitle": wood->title,
			"woodSlug": wood->slug.current,
			"sizeTitle": size->title,
			"sizeSlug": size->slug.current,
			"dimensionsLabel": size->dimensionsLabel
		},
		variants[] {
			sku,
			price,
			salePrice,
			stockQuantity,
			active,
			"woodTitle": wood->title,
			"woodSlug": wood->slug.current,
			"sizeTitle": size->title,
			"sizeSlug": size->slug.current,
			"dimensionsLabel": size->dimensionsLabel
		}
	}
`;

function isNonEmptyString(value) {
	return typeof value === "string" && value.trim().length > 0;
}

function isValidMoney(value) {
	return typeof value === "number" && Number.isFinite(value) && value >= 0;
}

function isValidStock(value) {
	return Number.isInteger(value) && value >= 0;
}

/**
 * Convierte un producto de Sanity en filas listas para catalog_variants.
 * Devuelve tanto las validas como las rechazadas (con motivo), y nunca
 * lanza: un producto o variante invalido se reporta, no tumba el script.
 */
function resolveVariantRows(product) {
	const accepted = [];
	const rejected = [];
	const seenSkus = new Set();

	// En modo "unique" el producto no tiene su propio array de variantes
	// ni un `sku` dentro de `uniqueProduct` (ese campo no existe en el
	// schema de Sanity, ver studio/schemaTypes/productType.ts): el SKU
	// vive en el documento raiz (`product.sku`, campo obligatorio "SKU
	// general"), igual que ya lo lee productDetailQuery.ts.
	const sourceVariants =
		product.productMode === "unique"
			? product.uniqueProduct
				? [
						{
							...product.uniqueProduct,
							sku: product.sku,
							active: product.uniqueProduct.available !== false,
						},
					]
				: []
			: Array.isArray(product.variants)
				? product.variants
				: [];

	for (const [index, variant] of sourceVariants.entries()) {
		const label = `${product.slug} [${variant?.sku || `variante #${index}`}]`;

		if (!isNonEmptyString(variant?.sku)) {
			rejected.push({ label, reason: "sin SKU" });
			continue;
		}

		if (seenSkus.has(variant.sku)) {
			rejected.push({
				label,
				reason: `SKU duplicado dentro del mismo producto (${variant.sku})`,
			});
			continue;
		}

		if (!isValidMoney(variant.price)) {
			rejected.push({ label, reason: "precio invalido o negativo" });
			continue;
		}

		if (
			variant.salePrice !== undefined &&
			variant.salePrice !== null &&
			!isValidMoney(variant.salePrice)
		) {
			rejected.push({ label, reason: "precio de oferta invalido o negativo" });
			continue;
		}

		if (!isValidStock(variant.stockQuantity)) {
			rejected.push({ label, reason: "stock invalido (debe ser entero >= 0)" });
			continue;
		}

		seenSkus.add(variant.sku);

		accepted.push({
			sku: variant.sku,
			wood_title: variant.woodTitle || null,
			wood_slug: variant.woodSlug || null,
			size_title: variant.sizeTitle || null,
			size_slug: variant.sizeSlug || null,
			dimensions_label: variant.dimensionsLabel || null,
			price: variant.price,
			sale_price:
				typeof variant.salePrice === "number" ? variant.salePrice : null,
			stock_quantity: variant.stockQuantity,
			active: variant.active !== false,
		});
	}

	return { accepted, rejected, seenSkus };
}

async function main() {
	const summary = {
		productsCreated: 0,
		productsUpdated: 0,
		productsDeactivated: 0,
		variantsCreated: 0,
		variantsUpdated: 0,
		variantsDeactivated: 0,
		variantsStockPreserved: 0,
		rejected: [],
	};

	const products = await sanity.fetch(QUERY);

	if (!Array.isArray(products)) {
		console.error("Sanity no devolvio una lista de productos. Abortando sin escribir nada.");
		process.exit(1);
	}

	const validProducts = [];

	for (const product of products) {
		if (
			!isNonEmptyString(product?._id) ||
			!isNonEmptyString(product?.slug) ||
			!isNonEmptyString(product?.title) ||
			!isNonEmptyString(product?.productMode)
		) {
			summary.rejected.push({
				label: product?.slug || product?._id || "(sin identificador)",
				reason: "falta _id, slug, title o productMode",
			});
			continue;
		}

		validProducts.push(product);
	}

	if (validProducts.length === 0) {
		console.log("No hay productos validos que sincronizar.");
		console.log(JSON.stringify(summary, null, 2));
		return;
	}

	// --- upsert de productos ---

	const { data: existingProducts, error: existingProductsError } =
		await supabase.from("catalog_products").select("id, sanity_id, active");

	if (existingProductsError) {
		throw new Error(`No se pudo leer catalog_products: ${existingProductsError.message}`);
	}

	const existingProductBySanityId = new Map(
		(existingProducts || []).map((row) => [row.sanity_id, row]),
	);

	const syncedAt = new Date().toISOString();

	const productRows = validProducts.map((product) => ({
		sanity_id: product._id,
		slug: product.slug,
		title: product.title,
		product_mode: product.productMode,
		sale_start: product.saleStart || null,
		sale_end: product.saleEnd || null,
		active: product.active !== false,
		synced_at: syncedAt,
	}));

	const { data: upsertedProducts, error: upsertProductsError } = await supabase
		.from("catalog_products")
		.upsert(productRows, { onConflict: "sanity_id" })
		.select("id, sanity_id");

	if (upsertProductsError) {
		throw new Error(`No se pudo escribir catalog_products: ${upsertProductsError.message}`);
	}

	for (const row of productRows) {
		if (existingProductBySanityId.has(row.sanity_id)) {
			summary.productsUpdated += 1;
		} else {
			summary.productsCreated += 1;
		}
	}

	const productIdBySanityId = new Map(
		(upsertedProducts || []).map((row) => [row.sanity_id, row.id]),
	);

	// Productos que existian en el espejo pero ya no vinieron en esta
	// lectura de Sanity (despublicados o borrados): se desactivan, no se
	// borran.
	const seenProductSanityIds = new Set(validProducts.map((p) => p._id));

	const productsToDeactivate = (existingProducts || []).filter(
		(row) => row.active && !seenProductSanityIds.has(row.sanity_id),
	);

	if (productsToDeactivate.length > 0) {
		const { error: deactivateError } = await supabase
			.from("catalog_products")
			.update({ active: false, synced_at: syncedAt })
			.in(
				"id",
				productsToDeactivate.map((row) => row.id),
			);

		if (deactivateError) {
			throw new Error(`No se pudo desactivar productos ausentes: ${deactivateError.message}`);
		}

		summary.productsDeactivated = productsToDeactivate.length;
	}

	// --- upsert de variantes (o del "producto unico" como variante) ---

	const variantRows = [];
	const seenVariantKeysByProduct = new Map();

	for (const product of validProducts) {
		const productId = productIdBySanityId.get(product._id);
		if (!productId) continue;

		const { accepted, rejected, seenSkus } = resolveVariantRows(product);

		for (const rejection of rejected) {
			summary.rejected.push(rejection);
		}

		seenVariantKeysByProduct.set(product._id, seenSkus);

		for (const variant of accepted) {
			variantRows.push({
				product_id: productId,
				sanity_product_id: product._id,
				...variant,
				synced_at: syncedAt,
			});
		}
	}

	if (variantRows.length > 0) {
		const { data: existingVariants, error: existingVariantsError } = await supabase
			.from("catalog_variants")
			.select("sanity_product_id, sku, stock_quantity")
			.in(
				"sanity_product_id",
				[...seenVariantKeysByProduct.keys()],
			);

		if (existingVariantsError) {
			throw new Error(`No se pudo leer catalog_variants: ${existingVariantsError.message}`);
		}

		const existingVariantByKey = new Map(
			(existingVariants || []).map((row) => [`${row.sanity_product_id}::${row.sku}`, row]),
		);

		const newVariantRows = [];
		const existingVariantRows = [];

		for (const row of variantRows) {
			const key = `${row.sanity_product_id}::${row.sku}`;
			if (existingVariantByKey.has(key)) {
				existingVariantRows.push(row);
			} else {
				newVariantRows.push(row);
			}
		}

		// Variantes nuevas: no hay stock previo que preservar, se crean con
		// el stock inicial que trae Sanity.
		if (newVariantRows.length > 0) {
			const { error: insertVariantsError } = await supabase
				.from("catalog_variants")
				.insert(newVariantRows);

			if (insertVariantsError) {
				throw new Error(`No se pudo crear catalog_variants: ${insertVariantsError.message}`);
			}

			summary.variantsCreated = newVariantRows.length;
		}

		// Variantes existentes: se calcula que tanto cambiaria el stock
		// solo para poder informarlo (--sync-stock) o para el conteo de
		// "preservados"; la decision de escribirlo o no se toma abajo.
		const stockDiffs = existingVariantRows
			.map((row) => {
				const existing = existingVariantByKey.get(`${row.sanity_product_id}::${row.sku}`);
				return {
					sku: row.sku,
					from: existing ? existing.stock_quantity : null,
					to: row.stock_quantity,
				};
			})
			.filter((diff) => diff.from !== diff.to);

		if (syncStockRequested) {
			console.warn(
				`--sync-stock: ${stockDiffs.length} variante(s) tienen un stock distinto en Sanity respecto a Supabase.`,
			);
			for (const diff of stockDiffs) {
				console.warn(`  ${diff.sku}: ${diff.from} -> ${diff.to}`);
			}
			console.warn(
				syncStockApply
					? `Aplicando --sync-stock --yes: se sobreescribira el stock de ${stockDiffs.length} variante(s) existente(s) con el valor de Sanity.`
					: "Modo previsualizacion (falta --yes): no se escribio ningun stock. Repite el comando agregando --yes para aplicar estos cambios.",
			);
		}

		// Por defecto (sin --sync-stock, o con --sync-stock pero sin
		// --yes) se preserva stock_quantity de toda variante que ya
		// existia: es lo que create_order_v2 fue descontando desde la
		// ultima sincronizacion, y un sync normal no debe reponerlo solo.
		const applyStockOverride = syncStockRequested && syncStockApply;

		for (const row of existingVariantRows) {
			const { stock_quantity, ...rowWithoutStock } = row;
			const payload = applyStockOverride ? row : rowWithoutStock;

			const { error: updateVariantError } = await supabase
				.from("catalog_variants")
				.update(payload)
				.eq("sanity_product_id", row.sanity_product_id)
				.eq("sku", row.sku);

			if (updateVariantError) {
				throw new Error(
					`No se pudo actualizar la variante ${row.sanity_product_id}/${row.sku}: ${updateVariantError.message}`,
				);
			}
		}

		summary.variantsUpdated = existingVariantRows.length;
		summary.variantsStockPreserved = applyStockOverride ? 0 : existingVariantRows.length;

		if (syncStockRequested) {
			summary.stockDiffCount = stockDiffs.length;
			summary.stockApplied = applyStockOverride;
		}

		// Variantes que existian para este producto pero ya no vienen en
		// su lista actual de Sanity: se desactivan, no se borran.
		const variantsToDeactivate = (existingVariants || []).filter((row) => {
			const seenSkus = seenVariantKeysByProduct.get(row.sanity_product_id);
			return seenSkus && !seenSkus.has(row.sku);
		});

		if (variantsToDeactivate.length > 0) {
			for (const row of variantsToDeactivate) {
				const { error: deactivateVariantError } = await supabase
					.from("catalog_variants")
					.update({ active: false, synced_at: syncedAt })
					.eq("sanity_product_id", row.sanity_product_id)
					.eq("sku", row.sku);

				if (deactivateVariantError) {
					throw new Error(
						`No se pudo desactivar la variante ${row.sanity_product_id}/${row.sku}: ${deactivateVariantError.message}`,
					);
				}
			}

			summary.variantsDeactivated = variantsToDeactivate.length;
		}
	}

	console.log(JSON.stringify(summary, null, 2));
}

main().catch((error) => {
	console.error("Sincronizacion abortada:", error.message);
	process.exit(1);
});
