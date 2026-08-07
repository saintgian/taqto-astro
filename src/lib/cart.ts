export interface CartItem {
	id: string;
	productId: string;
	slug: string;
	title: string;
	image: string;
	sku: string;
	woodTitle?: string;
	woodSlug?: string;
	sizeTitle?: string;
	sizeSlug?: string;
	dimensionsLabel?: string;
	engravingText?: string;
	unitPrice: number;
	quantity: number;
	/*
	 * Stock capturado en el momento de agregar al carrito (ficha de
	 * producto). No hay una fuente en vivo desde carrito/minicarrito,
	 * asi que este valor es el limite superior que se puede hacer
	 * cumplir sin inventar disponibilidad.
	 */
	stock?: number;
}

const STORAGE_KEY = "taqto_cart";
const CART_UPDATED_EVENT = "cart:updated";

/*
 * Se emite solo cuando un alta termina correctamente. `cart:updated`
 * cubre cualquier cambio (alta, baja, cantidad, rehidratacion desde otra
 * pestaña), asi que no sirve para disparar la animacion de "carrito
 * llenandose" sin animar tambien al quitar o al recargar.
 */
const CART_ITEM_ADDED_EVENT = "cart:item-added";

function isValidCartItem(value: unknown): value is CartItem {
	if (!value || typeof value !== "object") return false;

	const item = value as Partial<CartItem>;

	return (
		typeof item.id === "string" &&
		item.id.length > 0 &&
		typeof item.title === "string" &&
		Number.isFinite(item.unitPrice) &&
		Number.isFinite(item.quantity) &&
		(item.quantity as number) > 0 &&
		(item.stock === undefined || Number.isFinite(item.stock))
	);
}

function stockCapOf(item: Pick<CartItem, "stock">): number | undefined {
	if (typeof item.stock !== "number" || !Number.isFinite(item.stock)) {
		return undefined;
	}

	return Math.max(0, Math.floor(item.stock));
}

/*
 * Corrige en el propio storage las cantidades guardadas antes de tener
 * `stock`, o que quedaron por encima del stock capturado en un alta
 * posterior del mismo producto (variante que se agoto entre visitas).
 * Tambien normaliza decimales y descarta lineas invalidas.
 *
 * Un `stock` de exactamente 0 (item sin disponibilidad, confirmado por
 * `applyAvailability` o por un alta con cap 0) NO se toca aqui: ni se
 * fuerza la cantidad a 0 ni se elimina la linea. El carrito debe seguir
 * mostrandolo como "Temporalmente agotado" en vez de hacerlo desaparecer
 * en silencio.
 */
function clampToStock(items: CartItem[]): {
	items: CartItem[];
	changed: boolean;
} {
	let changed = false;
	const next: CartItem[] = [];

	for (const item of items) {
		const cap = stockCapOf(item);
		let quantity = Math.floor(item.quantity);

		if (cap !== undefined && cap > 0 && quantity > cap) {
			quantity = cap;
		}

		if (quantity !== item.quantity) changed = true;

		if (quantity <= 0) {
			changed = true;
			continue;
		}

		next.push(
			quantity === item.quantity ? item : { ...item, quantity },
		);
	}

	return { items: next, changed };
}

function readStorage(): CartItem[] {
	if (typeof window === "undefined") return [];

	try {
		const raw = window.localStorage.getItem(STORAGE_KEY);
		if (!raw) return [];

		const parsed = JSON.parse(raw);
		if (!Array.isArray(parsed)) return [];

		// Descarta entradas corruptas o de versiones anteriores del
		// carrito (campos faltantes, precios/cantidades no numéricos)
		// para evitar totales en NaN que bloqueen el checkout.
		const valid = (parsed as unknown[]).filter(
			isValidCartItem,
		) as CartItem[];

		const { items, changed } = clampToStock(valid);

		if (changed) {
			try {
				window.localStorage.setItem(
					STORAGE_KEY,
					JSON.stringify(items),
				);
			} catch {
				// Almacenamiento no disponible; se sigue devolviendo la
				// version ya corregida en memoria.
			}
		}

		return items;
	} catch {
		return [];
	}
}

function writeStorage(items: CartItem[]) {
	if (typeof window === "undefined") return;

	try {
		window.localStorage.setItem(
			STORAGE_KEY,
			JSON.stringify(items),
		);
	} catch {
		// Almacenamiento no disponible (modo privado, cuota llena, etc.).
	}

	window.dispatchEvent(new CustomEvent(CART_UPDATED_EVENT));
}

export function getCart(): CartItem[] {
	return readStorage();
}

export function addItem(
	item: Omit<CartItem, "quantity"> & { quantity?: number },
): { quantity: number; capped: boolean } {
	const items = readStorage();
	const cap = stockCapOf(item);
	const requested = Math.max(
		1,
		Math.floor(item.quantity ?? 1) || 1,
	);

	if (cap !== undefined && cap <= 0) {
		return { quantity: 0, capped: true };
	}

	const existing = items.find(
		(current) => current.id === item.id,
	);

	const desiredQuantity =
		(existing?.quantity ?? 0) + requested;

	const quantity =
		cap !== undefined
			? Math.min(desiredQuantity, cap)
			: desiredQuantity;

	if (existing) {
		existing.quantity = quantity;
		existing.stock = cap;
	} else {
		items.push({ ...item, quantity, stock: cap });
	}

	writeStorage(items);

	if (typeof window !== "undefined") {
		window.dispatchEvent(
			new CustomEvent(CART_ITEM_ADDED_EVENT, {
				detail: { id: item.id, quantity },
			}),
		);
	}

	return {
		quantity,
		capped: cap !== undefined && desiredQuantity > cap,
	};
}

export function onCartItemAdded(
	callback: () => void,
): () => void {
	if (typeof window === "undefined") return () => {};

	window.addEventListener(CART_ITEM_ADDED_EVENT, callback);

	return () => {
		window.removeEventListener(
			CART_ITEM_ADDED_EVENT,
			callback,
		);
	};
}

export function updateQuantity(id: string, quantity: number) {
	const items = readStorage();
	const target = items.find((item) => item.id === id);
	if (!target) return;

	const safeQuantity = Number.isFinite(quantity)
		? Math.floor(quantity)
		: 0;

	if (safeQuantity <= 0) {
		writeStorage(
			items.filter((item) => item.id !== id),
		);
		return;
	}

	const cap = stockCapOf(target);

	target.quantity =
		cap !== undefined
			? Math.min(safeQuantity, cap)
			: safeQuantity;

	writeStorage(items);
}

export function removeItem(id: string) {
	writeStorage(
		readStorage().filter((item) => item.id !== id),
	);
}

export function clearCart() {
	writeStorage([]);
}

export function getItemCount(): number {
	return readStorage().reduce(
		(total, item) => total + item.quantity,
		0,
	);
}

export function getSubtotal(): number {
	return readStorage().reduce(
		(total, item) =>
			total + item.unitPrice * item.quantity,
		0,
	);
}

/**
 * IDs de producto (Sanity) distintos presentes en el carrito, en el orden
 * en que aparecen. El carrito puede tener varias variantes del mismo
 * producto (mismo `productId`, distinto `sku`); esto evita pedir la misma
 * disponibilidad dos veces.
 */
export function getDistinctProductIds(): string[] {
	const seen = new Set<string>();
	const ids: string[] = [];

	for (const item of readStorage()) {
		if (!seen.has(item.productId)) {
			seen.add(item.productId);
			ids.push(item.productId);
		}
	}

	return ids;
}

export interface AvailabilityAdjustment {
	id: string;
	title: string;
	from: number;
	to: number;
}

export interface AvailabilityUpdateResult {
	adjusted: AvailabilityAdjustment[];
	outOfStock: Array<{ id: string; title: string }>;
}

/**
 * Cruza el carrito guardado contra disponibilidad real obtenida de
 * `public_variant_availability` (sku -> stock_quantity), para los
 * `queriedProductIds` que sí se pudieron consultar. Los items cuyo
 * `productId` no esta en `queriedProductIds` (RPC fallida o no consultada)
 * se dejan intactos: no hay base real para tocarlos.
 *
 * Un sku ausente del mapa (variante/producto inactivo) se trata igual que
 * stock 0: create_order_v2 tampoco lo aceptaria.
 */
export function applyAvailability(
	availability: Map<string, number>,
	queriedProductIds: Set<string>,
): AvailabilityUpdateResult {
	const items = readStorage();
	const adjusted: AvailabilityAdjustment[] = [];
	const outOfStock: AvailabilityUpdateResult["outOfStock"] = [];
	let changed = false;

	const next = items.map((item) => {
		if (!queriedProductIds.has(item.productId)) return item;

		const stock = availability.has(item.sku)
			? Math.max(0, Math.floor(availability.get(item.sku)!))
			: 0;

		let quantity = item.quantity;

		if (stock > 0 && quantity > stock) {
			adjusted.push({
				id: item.id,
				title: item.title,
				from: quantity,
				to: stock,
			});
			quantity = stock;
		}

		if (stock <= 0) {
			outOfStock.push({ id: item.id, title: item.title });
		}

		if (stock === item.stock && quantity === item.quantity) {
			return item;
		}

		changed = true;
		return { ...item, stock, quantity };
	});

	if (changed) writeStorage(next);

	return { adjusted, outOfStock };
}

export function onCartUpdated(
	callback: () => void,
): () => void {
	if (typeof window === "undefined") return () => {};

	window.addEventListener(CART_UPDATED_EVENT, callback);
	window.addEventListener("storage", callback);

	return () => {
		window.removeEventListener(
			CART_UPDATED_EVENT,
			callback,
		);
		window.removeEventListener("storage", callback);
	};
}
