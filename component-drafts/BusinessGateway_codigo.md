# BusinessGateway — código para integrar

## Archivo nuevo: `src/components/BusinessGateway.astro`

```astro
---
interface BusinessImage {
	src: string;
	alt: string;
	width: number;
	height: number;
}

interface BusinessLink {
	label: string;
	href: string;
	description: string;
}

interface Props {
	image: BusinessImage;
	mainHref: string;
	corporateGiftsHref: string;
	wholesaleHref: string;
	theme?: "dark" | "light";
}

const {
	image,
	mainHref,
	corporateGiftsHref,
	wholesaleHref,
	theme = "dark",
} = Astro.props;

const businessLinks: BusinessLink[] = [
	{
		label: "Regalos corporativos",
		href: corporateGiftsHref,
		description:
			"Piezas personalizadas para clientes, equipos y aliados.",
	},
	{
		label: "Ventas al por mayor",
		href: wholesaleHref,
		description:
			"Pedidos en volumen para negocios, tiendas y espacios profesionales.",
	},
];

const hasRequiredData =
	Boolean(image?.src?.trim()) &&
	Boolean(image?.alt?.trim()) &&
	Number.isFinite(image?.width) &&
	Number.isFinite(image?.height) &&
	Boolean(mainHref?.trim()) &&
	Boolean(corporateGiftsHref?.trim()) &&
	Boolean(wholesaleHref?.trim());
---

{
	hasRequiredData && (
		<section
			class:list={[
				"business-gateway",
				theme === "light"
					? "business-gateway--light"
					: "business-gateway--dark",
			]}
			aria-labelledby="business-gateway-title"
			data-business-gateway
		>
			<div class="business-gateway__container">
				<div class="business-gateway__media">
					<img
						src={image.src}
						alt={image.alt}
						width={image.width}
						height={image.height}
						loading="lazy"
						decoding="async"
					/>
				</div>

				<div class="business-gateway__content">
					<p class="business-gateway__eyebrow">
						TAQTO para empresas
					</p>

					<h2 id="business-gateway-title">
						Piezas que representan tu marca
					</h2>

					<p class="business-gateway__description">
						Soluciones de madera personalizadas
						para regalos corporativos y negocios
						que necesitan pedidos en volumen.
					</p>

					<ul
						class="business-gateway__links"
						aria-label="Soluciones para empresas"
					>
						{
							businessLinks.map((link) => (
								<li>
									<a href={link.href}>
										<span class="business-gateway__link-copy">
											<strong>{link.label}</strong>

											<small>
												{link.description}
											</small>
										</span>

										<span
											class="business-gateway__link-arrow"
											aria-hidden="true"
										>
											→
										</span>
									</a>
								</li>
							))
						}
					</ul>

					<a
						class="business-gateway__cta"
						href={mainHref}
					>
						Conoce las soluciones para empresas

						<span aria-hidden="true">→</span>
					</a>
				</div>
			</div>
		</section>
	)
}

<script>
	const initializeBusinessGateway = () => {
		const sections =
			document.querySelectorAll<HTMLElement>(
				"[data-business-gateway]",
			);

		sections.forEach((section) => {
			if (
				section.dataset.initialized ===
				"true"
			) {
				return;
			}

			section.dataset.initialized = "true";

			const reduceMotion =
				window.matchMedia(
					"(prefers-reduced-motion: reduce)",
				).matches;

			if (
				reduceMotion ||
				!("IntersectionObserver" in window)
			) {
				section.classList.add("is-visible");
				return;
			}

			section.classList.add(
				"is-reveal-ready",
			);

			const observer =
				new IntersectionObserver(
					(entries) => {
						const entry = entries[0];

						if (!entry?.isIntersecting) {
							return;
						}

						section.classList.add(
							"is-visible",
						);

						observer.disconnect();
					},
					{
						threshold: 0.16,
					},
				);

			observer.observe(section);
		});
	};

	initializeBusinessGateway();

	document.addEventListener(
		"astro:page-load",
		initializeBusinessGateway,
	);
</script>

<style>
	.business-gateway {
		padding:
			clamp(76px, 9vw, 138px)
			var(--page-padding);
	}

	.business-gateway--dark {
		--business-background:
			var(--color-black, #141414);
		--business-foreground:
			var(--color-beige, #fff6ed);
		--business-muted:
			rgba(255, 246, 237, 0.66);
		--business-line:
			rgba(255, 246, 237, 0.16);
		--business-link-hover:
			rgba(255, 246, 237, 0.07);
		--business-button-background:
			var(--color-beige, #fff6ed);
		--business-button-foreground:
			var(--color-black, #141414);
	}

	.business-gateway--light {
		--business-background:
			var(--color-beige, #fff6ed);
		--business-foreground:
			var(--color-black, #141414);
		--business-muted:
			rgba(20, 20, 20, 0.64);
		--business-line:
			rgba(20, 20, 20, 0.14);
		--business-link-hover:
			rgba(20, 20, 20, 0.045);
		--business-button-background:
			var(--color-brown, #5c312a);
		--business-button-foreground:
			var(--color-beige, #fff6ed);
	}

	.business-gateway {
		background: var(--business-background);
		color: var(--business-foreground);
	}

	.business-gateway__container {
		display: grid;
		width:
			min(100%, var(--page-width));
		grid-template-columns:
			minmax(0, 1.08fr)
			minmax(360px, 0.92fr);
		align-items: stretch;
		gap:
			clamp(44px, 7vw, 112px);
		margin-inline: auto;
	}

	.business-gateway__media {
		position: relative;
		min-height:
			clamp(560px, 62vw, 820px);
		overflow: hidden;
		border-radius: 26px;
		background:
			var(--color-beige, #fff6ed);
		clip-path: inset(
			0 100% 0 0
			round 26px
		);
	}

	.business-gateway__media img {
		display: block;
		width: 100%;
		height: 100%;
		object-fit: cover;
		object-position: center;
		transform: scale(1.025);
		transition:
			transform 720ms
			cubic-bezier(0.22, 1, 0.36, 1);
	}

	.business-gateway__content {
		display: flex;
		align-self: center;
		flex-direction: column;
		padding-block:
			clamp(10px, 2vw, 28px);
	}

	.business-gateway__eyebrow {
		margin: 0 0 20px;
		color:
			var(--color-orange, #ff4d2a);
		font-size: 10px;
		font-weight: 700;
		line-height: 1.3;
		letter-spacing: 0.17em;
		text-transform: uppercase;
	}

	.business-gateway__content h2 {
		max-width: 660px;
		margin: 0;
		color: var(--business-foreground);
		font-size:
			clamp(40px, 5.2vw, 70px);
		font-weight: 600;
		line-height: 0.98;
		letter-spacing: -0.04em;
		text-wrap: balance;
	}

	.business-gateway__description {
		max-width: 580px;
		margin: 24px 0 0;
		color: var(--business-muted);
		font-size:
			clamp(15px, 1.35vw, 18px);
		line-height: 1.65;
	}

	.business-gateway__links {
		margin:
			clamp(34px, 5vw, 54px)
			0
			0;
		padding: 0;
		border-top: 1px solid
			var(--business-line);
		list-style: none;
	}

	.business-gateway__links li {
		border-bottom: 1px solid
			var(--business-line);
	}

	.business-gateway__links a {
		display: flex;
		min-height: 104px;
		align-items: center;
		justify-content: space-between;
		gap: 22px;
		padding:
			20px
			4px;
		color: var(--business-foreground);
		text-decoration: none;
		transition:
			background-color 180ms ease,
			padding-inline 180ms ease;
	}

	.business-gateway__link-copy {
		display: grid;
		gap: 8px;
	}

	.business-gateway__link-copy strong {
		font-size:
			clamp(18px, 1.8vw, 24px);
		font-weight: 600;
		line-height: 1.15;
		letter-spacing: -0.02em;
	}

	.business-gateway__link-copy small {
		max-width: 440px;
		color: var(--business-muted);
		font-size: 12px;
		font-weight: 400;
		line-height: 1.5;
	}

	.business-gateway__link-arrow {
		display: grid;
		width: 44px;
		height: 44px;
		flex: 0 0 auto;
		place-items: center;
		border: 1px solid
			var(--business-line);
		border-radius: 50%;
		font-size: 16px;
		transition:
			transform 180ms ease,
			border-color 180ms ease,
			background-color 180ms ease;
	}

	.business-gateway__cta {
		display: inline-flex;
		width: fit-content;
		min-height: 50px;
		align-items: center;
		justify-content: center;
		gap: 12px;
		margin-top:
			clamp(32px, 4vw, 46px);
		padding: 0 20px;
		border: 1px solid transparent;
		border-radius: 999px;
		background:
			var(--business-button-background);
		color:
			var(--business-button-foreground);
		font-size: 10px;
		font-weight: 700;
		line-height: 1.3;
		letter-spacing: 0.08em;
		text-decoration: none;
		text-transform: uppercase;
		transition:
			transform 160ms ease,
			background-color 180ms ease,
			border-color 180ms ease,
			color 180ms ease;
	}

	.business-gateway__cta span {
		font-size: 15px;
		transition:
			transform 180ms ease;
	}

	.business-gateway__links a:focus-visible,
	.business-gateway__cta:focus-visible {
		outline: 2px solid
			var(--color-orange, #ff4d2a);
		outline-offset: 4px;
	}

	.business-gateway__cta:active {
		transform: translateY(1px);
	}

	.business-gateway.is-reveal-ready
		.business-gateway__content {
		opacity: 0;
		transform: translateY(18px);
	}

	.business-gateway.is-reveal-ready.is-visible
		.business-gateway__media {
		clip-path: inset(
			0 0 0 0
			round 26px
		);
		transition:
			clip-path 820ms
			cubic-bezier(0.22, 1, 0.36, 1);
	}

	.business-gateway.is-reveal-ready.is-visible
		.business-gateway__content {
		opacity: 1;
		transform: translateY(0);
		transition:
			opacity 560ms ease 100ms,
			transform 560ms
			cubic-bezier(0.22, 1, 0.36, 1)
			100ms;
	}

	.business-gateway.is-visible
		.business-gateway__media img {
		transform: scale(1);
	}

	@media (hover: hover) and (pointer: fine) {
		.business-gateway__links a:hover {
			padding-inline: 12px;
			background:
				var(--business-link-hover);
		}

		.business-gateway__links a:hover
			.business-gateway__link-arrow {
			border-color:
				var(--color-orange, #ff4d2a);
			transform: translateX(4px);
		}

		.business-gateway__cta:hover span {
			transform: translateX(4px);
		}

		.business-gateway--dark
			.business-gateway__cta:hover {
			border-color:
				var(--color-orange, #ff4d2a);
			background:
				var(--color-orange, #ff4d2a);
			color:
				var(--color-black, #141414);
		}

		.business-gateway--light
			.business-gateway__cta:hover {
			border-color:
				var(--color-black, #141414);
			background:
				var(--color-black, #141414);
		}
	}

	@media (max-width: 980px) {
		.business-gateway__container {
			grid-template-columns: 1fr;
			gap: 44px;
		}

		.business-gateway__media {
			min-height: 0;
			aspect-ratio: 16 / 10;
		}

		.business-gateway__content {
			max-width: 760px;
			padding-block: 0;
		}
	}

	@media (max-width: 680px) {
		.business-gateway {
			padding:
				72px
				18px;
		}

		.business-gateway__container {
			gap: 34px;
		}

		.business-gateway__media {
			aspect-ratio: 4 / 5;
			border-radius: 18px;
			clip-path: inset(
				0 100% 0 0
				round 18px
			);
		}

		.business-gateway.is-reveal-ready.is-visible
			.business-gateway__media {
			clip-path: inset(
				0 0 0 0
				round 18px
			);
		}

		.business-gateway__content h2 {
			font-size:
				clamp(38px, 11vw, 52px);
		}

		.business-gateway__description {
			margin-top: 18px;
		}

		.business-gateway__links a {
			min-height: 98px;
			padding-block: 18px;
		}

		.business-gateway__link-copy strong {
			font-size: 20px;
		}

		.business-gateway__link-copy small {
			font-size: 11px;
		}

		.business-gateway__cta {
			width: 100%;
			min-height: 52px;
			padding-inline: 18px;
			text-align: center;
		}
	}

	@media (prefers-reduced-motion: reduce) {
		.business-gateway__media,
		.business-gateway__media img,
		.business-gateway__content,
		.business-gateway__links a,
		.business-gateway__link-arrow,
		.business-gateway__cta,
		.business-gateway__cta span {
			opacity: 1 !important;
			transform: none !important;
			transition: none !important;
		}

		.business-gateway__media {
			clip-path: none !important;
		}
	}
</style>
```

## Datos que recibe el componente

El componente no inventa rutas ni imágenes. La integración debe pasar una fotografía real y los enlaces existentes del proyecto.

```ts
interface BusinessImage {
	src: string;
	alt: string;
	width: number;
	height: number;
}

interface Props {
	image: BusinessImage;
	mainHref: string;
	corporateGiftsHref: string;
	wholesaleHref: string;
	theme?: "dark" | "light";
}
```

Ejemplo de estructura:

```ts
const businessGatewayImage = {
	src: "RUTA_REAL_DE_LA_IMAGEN",
	alt: "Varias piezas TAQTO personalizadas presentadas para un pedido corporativo",
	width: 1600,
	height: 2000,
};
```

No reemplazar la ruta con una imagen genérica. Usar una fotografía cálida y bien iluminada de varias piezas personalizadas, un pedido corporativo o una presentación real de productos TAQTO.

## Integración en `src/pages/index.astro`

Añade la importación:

```astro
import BusinessGateway from "../components/BusinessGateway.astro";
```

Inserta el componente cerca del final de la portada, después de testimonios o de `PurchaseProcess` y antes del CTA final:

```astro
<PurchaseProcess links={purchaseLinks} />

<BusinessGateway
	image={businessGatewayImage}
	mainHref="RUTA_REAL_DE_EMPRESAS"
	corporateGiftsHref="RUTA_REAL_DE_REGALOS_CORPORATIVOS"
	wholesaleHref="RUTA_REAL_DE_VENTAS_AL_POR_MAYOR"
	theme="dark"
/>
```

Usa `theme="dark"` cuando la sección anterior no tenga fondo negro.

Usa `theme="light"` cuando la historia de TAQTO u otra sección cercana ya tenga fondo negro y sea necesario evitar dos bloques oscuros consecutivos:

```astro
<BusinessGateway
	image={businessGatewayImage}
	mainHref="RUTA_REAL_DE_EMPRESAS"
	corporateGiftsHref="RUTA_REAL_DE_REGALOS_CORPORATIVOS"
	wholesaleHref="RUTA_REAL_DE_VENTAS_AL_POR_MAYOR"
	theme="light"
/>
```

No inventar las rutas. Reutilizar las rutas existentes de:

- Empresas.
- Regalos corporativos.
- Ventas al por mayor.

## Verificación

- En escritorio se muestran imagen y contenido en dos columnas.
- En móvil aparece primero la imagen y después el contenido.
- Los dos accesos funcionan como enlaces independientes y tienen un área táctil amplia.
- El CTA principal lleva a la página general de empresas.
- La imagen conserva su proporción, tiene dimensiones explícitas y texto alternativo descriptivo.
- La máscara se ejecuta una sola vez al entrar en pantalla.
- `prefers-reduced-motion` elimina la animación.
- No aparecen sellos, garantías o afirmaciones comerciales no confirmadas.
