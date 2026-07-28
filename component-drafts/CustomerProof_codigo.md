# CustomerProof — código para integrar

## Archivo nuevo: `src/components/CustomerProof.astro`

```astro
---
type CustomerProofMode =
	| "testimonials"
	| "projects";

interface CustomerProofImage {
	src: string;
	alt: string;
	width: number;
	height: number;
}

interface CustomerTestimonial {
	type: "testimonial";
	image: CustomerProofImage;
	customerName: string;
	productName: string;
	quote: string;
	href?: string;
}

interface CustomerProject {
	type: "project";
	image: CustomerProofImage;
	title: string;
	category?: string;
	description?: string;
	href?: string;
}

type CustomerProofItem =
	| CustomerTestimonial
	| CustomerProject;

interface Props {
	mode?: CustomerProofMode;
	items: CustomerProofItem[];
}

const {
	mode = "testimonials",
	items = [],
} = Astro.props;

const visibleItems = items
	.filter((item) => {
		const imageIsValid =
			Boolean(item.image?.src?.trim()) &&
			Boolean(item.image?.alt?.trim()) &&
			Number.isFinite(item.image?.width) &&
			Number.isFinite(item.image?.height);

		if (!imageIsValid) {
			return false;
		}

		if (item.type === "testimonial") {
			return (
				Boolean(item.customerName?.trim()) &&
				Boolean(item.productName?.trim()) &&
				Boolean(item.quote?.trim())
			);
		}

		return Boolean(item.title?.trim());
	})
	.slice(0, 3);

const resolvedItems =
	mode === "projects"
		? visibleItems.filter(
				(item): item is CustomerProject =>
					item.type === "project",
			)
		: visibleItems.filter(
				(item): item is CustomerTestimonial =>
					item.type === "testimonial",
			);
---

{
	resolvedItems.length > 0 && (
		<section
			class="customer-proof"
			aria-labelledby="customer-proof-title"
			data-customer-proof
		>
			<div class="customer-proof__container">
				<header class="customer-proof__header">
					<p class="customer-proof__eyebrow">
						Clientes y proyectos reales
					</p>

					<h2 id="customer-proof-title">
						Piezas que ya encontraron su lugar
					</h2>

					<p class="customer-proof__intro">
						Una selección de piezas personalizadas,
						regalos y pedidos que ya forman parte
						de espacios y momentos reales.
					</p>
				</header>

				<ul
					class="customer-proof__grid"
					aria-label={
						mode === "projects"
							? "Pedidos y proyectos realizados"
							: "Experiencias de clientes"
					}
				>
					{
						resolvedItems.map((item, index) => (
							<li
								class="customer-proof__item"
								style={`--proof-index: ${index}`}
							>
								<article class="customer-proof__card">
									{
										item.href ? (
											<a
												class="customer-proof__media"
												href={item.href}
												aria-label={
													item.type === "testimonial"
														? `Ver ${item.productName}`
														: `Ver ${item.title}`
												}
											>
												<img
													src={item.image.src}
													alt={item.image.alt}
													width={item.image.width}
													height={item.image.height}
													loading="lazy"
													decoding="async"
												/>
											</a>
										) : (
											<div class="customer-proof__media">
												<img
													src={item.image.src}
													alt={item.image.alt}
													width={item.image.width}
													height={item.image.height}
													loading="lazy"
													decoding="async"
												/>
											</div>
										)
									}

									<div class="customer-proof__content">
										{
											item.type === "testimonial" ? (
												<>
													<p class="customer-proof__product">
														{item.productName}
													</p>

													<blockquote>
														<p>
															“{item.quote}”
														</p>
													</blockquote>

													<p class="customer-proof__customer">
														{item.customerName}
													</p>
												</>
											) : (
												<>
													{
														item.category && (
															<p class="customer-proof__product">
																{item.category}
															</p>
														)
													}

													<h3>
														{
															item.href ? (
																<a href={item.href}>
																	{item.title}
																</a>
															) : (
																item.title
															)
														}
													</h3>

													{
														item.description && (
															<p class="customer-proof__description">
																{item.description}
															</p>
														)
													}
												</>
											)
										}
									</div>
								</article>
							</li>
						))
					}
				</ul>
			</div>
		</section>
	)
}

<script>
	const initializeCustomerProof = () => {
		const sections =
			document.querySelectorAll<HTMLElement>(
				"[data-customer-proof]",
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
						threshold: 0.14,
					},
				);

			observer.observe(section);
		});
	};

	initializeCustomerProof();

	document.addEventListener(
		"astro:page-load",
		initializeCustomerProof,
	);
</script>

<style>
	.customer-proof {
		padding:
			clamp(84px, 10vw, 150px)
			var(--page-padding);
		background: #ffffff;
		color:
			var(--color-black, #141414);
	}

	.customer-proof__container {
		width:
			min(100%, var(--page-width));
		margin-inline: auto;
	}

	.customer-proof__header {
		max-width: 820px;
		margin-bottom:
			clamp(40px, 6vw, 72px);
	}

	.customer-proof__eyebrow {
		margin: 0 0 18px;
		color:
			var(--color-orange, #ff4d2a);
		font-size: 10px;
		font-weight: 700;
		line-height: 1.3;
		letter-spacing: 0.16em;
		text-transform: uppercase;
	}

	.customer-proof__header h2 {
		margin: 0;
		color:
			var(--color-black, #141414);
		font-size:
			clamp(38px, 5.2vw, 70px);
		font-weight: 600;
		line-height: 0.98;
		letter-spacing: -0.04em;
		text-wrap: balance;
	}

	.customer-proof__intro {
		max-width: 640px;
		margin: 18px 0 0;
		color: rgba(20, 20, 20, 0.64);
		font-size:
			clamp(15px, 1.3vw, 18px);
		line-height: 1.6;
	}

	.customer-proof__grid {
		display: grid;
		grid-template-columns:
			repeat(3, minmax(0, 1fr));
		gap:
			clamp(22px, 3vw, 38px);
		margin: 0;
		padding: 0;
		list-style: none;
	}

	.customer-proof__item {
		min-width: 0;
	}

	.customer-proof__card {
		display: flex;
		height: 100%;
		flex-direction: column;
	}

	.customer-proof__media {
		position: relative;
		display: block;
		aspect-ratio: 4 / 5;
		overflow: hidden;
		border-radius: 20px;
		background:
			var(--color-beige, #fff6ed);
		color: inherit;
		text-decoration: none;
	}

	.customer-proof__media img {
		display: block;
		width: 100%;
		height: 100%;
		object-fit: cover;
		object-position: center;
		transition:
			transform 420ms
			cubic-bezier(0.22, 1, 0.36, 1);
	}

	.customer-proof__content {
		display: flex;
		flex: 1;
		flex-direction: column;
		padding: 18px 2px 0;
	}

	.customer-proof__product {
		margin: 0 0 10px;
		color:
			var(--color-orange, #ff4d2a);
		font-size: 9px;
		font-weight: 700;
		line-height: 1.3;
		letter-spacing: 0.14em;
		text-transform: uppercase;
	}

	.customer-proof blockquote {
		margin: 0;
		padding: 0;
		border: 0;
	}

	.customer-proof blockquote p {
		margin: 0;
		color:
			var(--color-black, #141414);
		font-size:
			clamp(17px, 1.65vw, 22px);
		font-weight: 500;
		line-height: 1.45;
		letter-spacing: -0.015em;
	}

	.customer-proof__customer {
		margin: 18px 0 0;
		color: rgba(20, 20, 20, 0.6);
		font-size: 12px;
		font-weight: 600;
		line-height: 1.4;
	}

	.customer-proof__content h3 {
		margin: 0;
		font-size:
			clamp(20px, 2vw, 28px);
		font-weight: 600;
		line-height: 1.12;
		letter-spacing: -0.025em;
	}

	.customer-proof__content h3 a {
		color:
			var(--color-black, #141414);
		text-decoration: none;
		transition:
			color 180ms ease;
	}

	.customer-proof__description {
		margin: 11px 0 0;
		color: rgba(20, 20, 20, 0.62);
		font-size: 13px;
		line-height: 1.58;
	}

	.customer-proof__media:focus-visible,
	.customer-proof__content h3 a:focus-visible {
		outline: 2px solid
			var(--color-orange, #ff4d2a);
		outline-offset: 4px;
	}

	.customer-proof.is-reveal-ready
		.customer-proof__header,
	.customer-proof.is-reveal-ready
		.customer-proof__item {
		opacity: 0;
		transform: translateY(16px);
	}

	.customer-proof.is-reveal-ready.is-visible
		.customer-proof__header,
	.customer-proof.is-reveal-ready.is-visible
		.customer-proof__item {
		opacity: 1;
		transform: translateY(0);
		transition:
			opacity 520ms ease,
			transform 520ms
			cubic-bezier(0.22, 1, 0.36, 1);
	}

	.customer-proof.is-reveal-ready.is-visible
		.customer-proof__item {
		transition-delay:
			calc(var(--proof-index) * 90ms);
	}

	@media (hover: hover) and (pointer: fine) {
		.customer-proof__card:hover
			.customer-proof__media img {
			transform: scale(1.016)
				translateY(-2px);
		}

		.customer-proof__content h3 a:hover {
			color:
				var(--color-brown, #5c312a);
		}
	}

	@media (max-width: 920px) {
		.customer-proof__grid {
			grid-template-columns:
				repeat(2, minmax(0, 1fr));
		}

		.customer-proof__item:last-child:nth-child(odd) {
			grid-column: 1 / -1;
			max-width: calc(50% - 19px);
		}
	}

	@media (max-width: 680px) {
		.customer-proof {
			padding:
				72px
				0;
		}

		.customer-proof__header {
			padding-inline: 18px;
			margin-bottom: 34px;
		}

		.customer-proof__header h2 {
			font-size:
				clamp(36px, 11vw, 50px);
		}

		.customer-proof__grid {
			grid-template-columns: none;
			grid-auto-flow: column;
			grid-auto-columns:
				minmax(270px, 84vw);
			gap: 18px;
			overflow-x: auto;
			padding:
				0
				18px
				14px;
			scroll-padding-inline: 18px;
			scroll-snap-type: inline mandatory;
			overscroll-behavior-inline: contain;
			touch-action: pan-x;
			scrollbar-width: thin;
			scrollbar-color:
				rgba(20, 20, 20, 0.28)
				transparent;
		}

		.customer-proof__item,
		.customer-proof__item:last-child:nth-child(odd) {
			grid-column: auto;
			max-width: none;
			scroll-snap-align: start;
		}

		.customer-proof__media {
			border-radius: 17px;
		}
	}

	@media (prefers-reduced-motion: reduce) {
		.customer-proof__header,
		.customer-proof__item,
		.customer-proof__media img,
		.customer-proof__content h3 a {
			opacity: 1 !important;
			transform: none !important;
			transition: none !important;
		}
	}
</style>
```

## Formato de datos: opción A — testimonios reales

Usa este modo solo cuando exista un comentario auténtico del cliente.

```ts
const customerProofItems = [
	{
		type: "testimonial",
		image: {
			src: "RUTA_REAL_DE_LA_FOTOGRAFIA",
			alt: "Tabla TAQTO personalizada utilizada en una mesa familiar",
			width: 1600,
			height: 2000,
		},
		customerName: "Nombre o inicial real",
		productName: "Nombre real del producto adquirido",
		quote: "Comentario breve y auténtico del cliente",
		href: "RUTA_REAL_DEL_PRODUCTO",
	},
] satisfies CustomerProofItem[];
```

Integración:

```astro
<CustomerProof
	mode="testimonials"
	items={customerProofItems}
/>
```

No corregir el testimonio de forma que cambie su significado. Puede limpiarse ortografía mínima, pero no inventar entusiasmo, resultados ni calificaciones.

## Formato de datos: opción B — galería de pedidos realizados

Usa este modo cuando todavía no existan testimonios verificables.

```ts
const customerProofItems = [
	{
		type: "project",
		image: {
			src: "RUTA_REAL_DE_LA_FOTOGRAFIA",
			alt: "Pedido de tablas TAQTO con grabados personalizados",
			width: 1600,
			height: 2000,
		},
		title: "Pedido personalizado",
		category: "Grabado personalizado",
		description:
			"Descripción breve basada únicamente en el pedido real.",
		href: "RUTA_REAL_RELACIONADA",
	},
] satisfies CustomerProofItem[];
```

Integración:

```astro
<CustomerProof
	mode="projects"
	items={customerProofItems}
/>
```

## Reglas de contenido

- Mostrar un máximo de tres elementos.
- Usar fotografías auténticas de productos, pedidos o proyectos TAQTO.
- No utilizar estrellas si no existe una calificación real documentada.
- No inventar nombres, iniciales, comentarios, productos adquiridos ni resultados.
- No presentar renders o fotografías publicitarias como si fueran imágenes enviadas por clientes.
- Cuando una fotografía pertenezca a una campaña interna, usar el modo `projects`.
- Omitir `href` cuando no exista una página real relacionada.

## Integración en `src/pages/index.astro`

Añade la importación:

```astro
import CustomerProof from "../components/CustomerProof.astro";
```

Coloca la sección después de `PurchaseProcess` y antes de `BusinessGateway`:

```astro
<PurchaseProcess links={purchaseLinks} />

<CustomerProof
	mode="projects"
	items={customerProofItems}
/>

<BusinessGateway
	image={businessGatewayImage}
	mainHref={businessHref}
	corporateGiftsHref={corporateGiftsHref}
	wholesaleHref={wholesaleHref}
	theme="dark"
/>
```

Cambia `mode="projects"` por `mode="testimonials"` únicamente cuando los elementos enviados sean testimonios reales.

## Verificación

- En escritorio aparecen como máximo tres elementos.
- En móvil funciona el desplazamiento horizontal manual y no existe autoplay.
- Las fotografías tienen dimensiones explícitas y texto alternativo descriptivo.
- Los testimonios utilizan comentarios auténticos.
- No aparecen estrellas ni calificaciones no confirmadas.
- Todos los enlaces opcionales usan rutas reales.
- La sección funciona correctamente con teclado.
- `prefers-reduced-motion` desactiva las transiciones.
