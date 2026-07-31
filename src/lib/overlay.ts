/*
 * Estrategia unica de overlay para minicarrito y buscador.
 *
 * Resuelve en un solo sitio lo que antes cada componente hacia (o no
 * hacia) por su cuenta: bloqueo de scroll con conservacion de posicion,
 * focus trap, restauracion del foco al disparador y la regla de que
 * nunca puede haber dos overlays abiertos a la vez.
 */

export interface OverlayHandle {
	/** Cierra este overlay si sigue siendo el activo. */
	release: () => void;
}

interface ActiveOverlay {
	id: string;
	container: HTMLElement;
	trigger: HTMLElement | null;
	close: () => void;
	modal: boolean;
	onKeydown: (event: KeyboardEvent) => void;
	onFocusOut: ((event: FocusEvent) => void) | null;
}

const FOCUSABLE_SELECTOR = [
	"a[href]",
	"button:not([disabled])",
	"input:not([disabled])",
	"select:not([disabled])",
	"textarea:not([disabled])",
	'[tabindex]:not([tabindex="-1"])',
].join(", ");

let active: ActiveOverlay | null = null;
let lockedScrollY = 0;
let lockCount = 0;

function focusableWithin(container: HTMLElement): HTMLElement[] {
	return Array.from(
		container.querySelectorAll<HTMLElement>(FOCUSABLE_SELECTOR),
	).filter(
		(element) =>
			!element.hasAttribute("hidden") &&
			element.offsetWidth + element.offsetHeight > 0,
	);
}

function lockScroll() {
	if (lockCount > 0) {
		lockCount += 1;
		return;
	}

	lockCount = 1;
	lockedScrollY = window.scrollY;

	const body = document.body;

	body.dataset.overlayScrollY = String(lockedScrollY);
	body.style.position = "fixed";
	body.style.top = `-${lockedScrollY}px`;
	body.style.left = "0";
	body.style.right = "0";
	body.style.width = "100%";
	body.style.overflow = "hidden";
}

function unlockScroll() {
	if (lockCount === 0) return;

	lockCount -= 1;
	if (lockCount > 0) return;

	const body = document.body;
	const storedY = Number(body.dataset.overlayScrollY || "0");

	body.style.position = "";
	body.style.top = "";
	body.style.left = "";
	body.style.right = "";
	body.style.width = "";
	body.style.overflow = "";
	delete body.dataset.overlayScrollY;

	// `scroll-behavior: smooth` esta activo en <html>: sin "instant" el
	// navegador animaria el regreso y se veria como un salto.
	window.scrollTo({ top: storedY, behavior: "instant" as ScrollBehavior });
}

/**
 * Registra un overlay como activo. Cierra cualquier otro que estuviera
 * abierto antes de tomar el control.
 */
export function openOverlay(options: {
	id: string;
	container: HTMLElement;
	trigger?: HTMLElement | null;
	close: () => void;
	initialFocus?: HTMLElement | null;
	/*
	 * `true` (por defecto) bloquea el scroll y atrapa el foco: es el
	 * comportamiento de un modal. `false` es un popover anclado, que no
	 * bloquea la pagina y se cierra cuando el foco sale de el.
	 */
	modal?: boolean;
}): OverlayHandle {
	if (active && active.id !== options.id) {
		active.close();
	}

	const modal = options.modal !== false;

	const onKeydown = (event: KeyboardEvent) => {
		if (event.key === "Escape") {
			event.preventDefault();
			options.close();
			return;
		}

		if (!modal || event.key !== "Tab") return;

		const focusables = focusableWithin(options.container);
		if (focusables.length === 0) return;

		const first = focusables[0];
		const last = focusables[focusables.length - 1];
		const current = document.activeElement;

		if (event.shiftKey && (current === first || !options.container.contains(current))) {
			event.preventDefault();
			last.focus();
		} else if (!event.shiftKey && current === last) {
			event.preventDefault();
			first.focus();
		}
	};

	/*
	 * El popover no atrapa el foco: si el usuario tabula fuera de el, se
	 * cierra, que es lo que se espera de un panel no bloqueante.
	 */
	const onFocusOut = modal
		? null
		: (event: FocusEvent) => {
				const next = event.relatedTarget as Node | null;

				if (!next) return;
				if (options.container.contains(next)) return;
				if (options.trigger?.contains(next)) return;

				options.close();
			};

	active = {
		id: options.id,
		container: options.container,
		trigger: options.trigger ?? null,
		close: options.close,
		modal,
		onKeydown,
		onFocusOut,
	};

	if (modal) lockScroll();

	document.addEventListener("keydown", onKeydown, true);

	if (onFocusOut) {
		options.container.addEventListener("focusout", onFocusOut);
	}

	const target =
		options.initialFocus ?? focusableWithin(options.container)[0] ?? null;

	// Un frame de margen: el panel acaba de pasar de `visibility: hidden`
	// y todavia no es enfocable en el mismo tick.
	window.requestAnimationFrame(() => {
		target?.focus();
	});

	return {
		release: () => closeOverlay(options.id),
	};
}

/** Libera el overlay indicado y devuelve el foco a su disparador. */
export function closeOverlay(id: string) {
	if (!active || active.id !== id) return;

	const { trigger, container, modal, onKeydown, onFocusOut } = active;
	active = null;

	document.removeEventListener("keydown", onKeydown, true);

	if (onFocusOut) {
		container.removeEventListener("focusout", onFocusOut);
	}

	if (modal) unlockScroll();

	trigger?.focus();
}

export function activeOverlayId(): string | null {
	return active?.id ?? null;
}
