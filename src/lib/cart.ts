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
		(item.quantity as number) > 0
	);
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
		return parsed.filter(isValidCartItem);
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
) {
	const items = readStorage();
	const quantity = Math.max(1, item.quantity ?? 1);
	const existing = items.find(
		(current) => current.id === item.id,
	);

	if (existing) {
		existing.quantity += quantity;
	} else {
		items.push({ ...item, quantity });
	}

	writeStorage(items);

	if (typeof window !== "undefined") {
		window.dispatchEvent(
			new CustomEvent(CART_ITEM_ADDED_EVENT, {
				detail: { id: item.id, quantity },
			}),
		);
	}
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

	if (quantity <= 0) {
		writeStorage(
			items.filter((item) => item.id !== id),
		);
		return;
	}

	target.quantity = quantity;
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
