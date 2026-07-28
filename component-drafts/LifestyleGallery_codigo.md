# LifestyleGallery — código para integrar

## Archivo nuevo: `src/components/LifestyleGallery.astro`

```astro
---
interface LifestyleItem {
	label: string;
	title: string;
	description?: string;
	href: string;
	image: {
		src: string;
		alt: string;
		width: number;
		height: number;
	};
}

interface Props {
	items: LifestyleItem[];
}

const { items = [] } = Astro.props;

const visibleItems = items.slice(0, 3);
---

{
	visibleItems.length > 0 && (
		<section
			class="lifestyle-gallery"
			aria-labelledby="lifestyle-gallery-title"
			data-lifestyle-gallery
		>
			<div class="lifestyle-gallery__container">
				<header class="lifestyle-gallery__header">
					<div>
						<p class="lifestyle-gallery__eyebrow">
							TAQTO en tu día a día
						</p>

						<h2 id="lifestyle-gallery-title">
							Diseñadas para momentos reales
						</h2>
					</div>

					<p class="lifestyle-gallery__intro">
						Piezas funcionales para compartir,
						organizar y acompañar cada día.
					</p>
				</header>

				<ul
					class="lifestyle-gallery__grid"
					aria-label="Momentos y espacios con piezas TAQTO"
				>
					{
						visibleItems.map((item, index) => (
							<li
								class:list={[
									"lifestyle-gallery__item",
									index === 0 &&
										"lifestyle-gallery__item--main",
								]}
								style={`--gallery-index: ${index}`}
							>
								<article class="lifestyle-card">
									<a
										class="lifestyle-card__media"
										href={item.href}
										aria-label={`Ver ${item.title}`}
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

									<div class="lifestyle-card__caption">
										<p class="lifestyle-card__label">
											{item.label}
										</p>

										<h3>
											<a href={item.href}>
												{item.title}
											</a>
										</h3>

										{
											item.description && (
												<p class="lifestyle-card__description">
													{item.description}
												</p>
											)
										}

										<a
											class="lifestyle-card__link"
											href={item.href}
										>
											Descubrir
											<span aria-hidden="true">→</span>
										</a>
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
	const initializeLifestyleGallery = () => {
		const sections = document.querySelectorAll<HTMLElement>(
			"[data-lifestyle-gallery]",
		);

		sections.forEach((section) => {
			if (section.dataset.initialized === "true") {
				return;
			}

			section.dataset.initialized = "true";

			const reduceMotion = window.matchMedia(
				"(prefers-reduced-motion: reduce)",
			).matches;

			if (
				reduceMotion ||
				!("IntersectionObserver" in window)
			) {
				section.classList.add("is-visible");
				return;
			}

			section.classList.add("is-reveal-ready");

			const observer = new IntersectionObserver(
				(entries) => {
					const entry = entries[0];

					if (!entry?.isIntersecting) {
						return;
					}

					section.classList.add("is-visible");
					observer.disconnect();
				},
				{
					threshold: 0.14,
				},
			);

			observer.observe(section);
		});
	};

	initializeLifestyleGallery();

	document.addEventListener(
		"astro:page-load",
		initializeLifestyleGallery,
	);
</script>

<style>
	.lifestyle-gallery {
		padding:
			clamp(84px, 10vw, 156px)
			var(--page-padding);
		background: #ffffff;
		color: var(--color-black, #141414);
	}

	.lifestyle-gallery__container {
		width: min(100%, var(--page-width));
		margin-inline: auto;
	}

	.lifestyle-gallery__header {
		display: grid;
		grid-template-columns:
			minmax(0, 1.25fr)
			minmax(280px, 0.75fr);
		align-items: end;
		gap: clamp(28px, 6vw, 96px);
		margin-bottom: clamp(42px, 6vw, 78px);
	}

	.lifestyle-gallery__eyebrow {
		margin: 0 0 18px;
		color: var(--color-orange, #ff4d2a);
		font-size: 10px;
		font-weight: 700;
		line-height: 1.3;
		letter-spacing: 0.16em;
		text-transform: uppercase;
	}

	.lifestyle-gallery__header h2 {
		max-width: 820px;
		margin: 0;
		color: var(--color-black, #141414);
		font-size: clamp(38px, 5.4vw, 72px);
		font-weight: 600;
		line-height: 0.98;
		letter-spacing: -0.04em;
		text-wrap: balance;
	}

	.lifestyle-gallery__intro {
		max-width: 460px;
		margin: 0 0 6px;
		color: rgba(20, 20, 20, 0.66);
		font-size: clamp(15px, 1.35vw, 18px);
		line-height: 1.6;
		text-wrap: balance;
	}

	.lifestyle-gallery__grid {
		display: grid;
		grid-template-columns:
			minmax(0, 1.55fr)
			minmax(280px, 0.8fr);
		grid-template-rows: repeat(2, minmax(0, 1fr));
		gap: clamp(24px, 3vw, 44px);
		margin: 0;
		padding: 0;
		list-style: none;
	}

	.lifestyle-gallery__item {
		min-width: 0;
	}

	.lifestyle-gallery__item--main {
		grid-row: 1 / 3;
	}

	.lifestyle-card {
		display: flex;
		height: 100%;
		flex-direction: column;
	}

	.lifestyle-card__media {
		position: relative;
		display: block;
		overflow: hidden;
		border-radius: 22px;
		background: var(--color-beige, #fff6ed);
		color: inherit;
		text-decoration: none;
		isolation: isolate;
	}

	.lifestyle-gallery__item--main
		.lifestyle-card__media {
		flex: 1;
		min-height: clamp(560px, 64vw, 880px);
	}

	.lifestyle-gallery__item:not(
			.lifestyle-gallery__item--main
		)
		.lifestyle-card__media {
		aspect-ratio: 4 / 3;
	}

	.lifestyle-card__media img {
		display: block;
		width: 100%;
		height: 100%;
		object-fit: cover;
		object-position: center;
		transition:
			transform 600ms
			cubic-bezier(0.22, 1, 0.36, 1);
	}

	.lifestyle-card__caption {
		padding-top: 18px;
	}

	.lifestyle-card__label {
		margin: 0 0 7px;
		color: var(--color-orange, #ff4d2a);
		font-size: 9px;
		font-weight: 700;
		line-height: 1.3;
		letter-spacing: 0.14em;
		text-transform: uppercase;
	}

	.lifestyle-card__caption h3 {
		margin: 0;
		font-size: clamp(20px, 2vw, 30px);
		font-weight: 600;
		line-height: 1.1;
		letter-spacing: -0.025em;
	}

	.lifestyle-card__caption h3 a {
		color: var(--color-black, #141414);
		text-decoration: none;
		transition: color 180ms ease;
	}

	.lifestyle-card__description {
		max-width: 520px;
		margin: 10px 0 0;
		color: rgba(20, 20, 20, 0.62);
		font-size: 13px;
		line-height: 1.55;
	}

	.lifestyle-card__link {
		display: inline-flex;
		min-height: 44px;
		align-items: center;
		gap: 8px;
		margin-top: 10px;
		color: var(--color-brown, #5c312a);
		font-size: 10px;
		font-weight: 700;
		line-height: 1.3;
		letter-spacing: 0.09em;
		text-decoration: none;
		text-transform: uppercase;
	}

	.lifestyle-card__link span {
		font-size: 14px;
		transition: transform 180ms ease;
	}

	.lifestyle-card__media:focus-visible,
	.lifestyle-card__caption h3 a:focus-visible,
	.lifestyle-card__link:focus-visible {
		outline: 2px solid var(--color-orange, #ff4d2a);
		outline-offset: 4px;
	}

	.lifestyle-gallery.is-reveal-ready
		.lifestyle-gallery__header,
	.lifestyle-gallery.is-reveal-ready
		.lifestyle-gallery__item {
		opacity: 0;
		transform: translateY(18px);
	}

	.lifestyle-gallery.is-reveal-ready.is-visible
		.lifestyle-gallery__header,
	.lifestyle-gallery.is-reveal-ready.is-visible
		.lifestyle-gallery__item {
		opacity: 1;
		transform: translateY(0);
		transition:
			opacity 560ms ease,
			transform 560ms
			cubic-bezier(0.22, 1, 0.36, 1);
	}

	.lifestyle-gallery.is-reveal-ready.is-visible
		.lifestyle-gallery__item {
		transition-delay:
			calc(var(--gallery-index) * 90ms);
	}

	@media (hover: hover) and (pointer: fine) {
		.lifestyle-card:hover
			.lifestyle-card__media img {
			transform: scale(1.018)
				translateY(-2px);
		}

		.lifestyle-card__caption h3 a:hover {
			color: var(--color-brown, #5c312a);
		}

		.lifestyle-card__link:hover span {
			transform: translateX(4px);
		}
	}

	@media (max-width: 980px) {
		.lifestyle-gallery__header {
			grid-template-columns: 1fr;
			gap: 20px;
		}

		.lifestyle-gallery__intro {
			max-width: 600px;
		}

		.lifestyle-gallery__grid {
			grid-template-columns:
				repeat(2, minmax(0, 1fr));
			grid-template-rows: auto;
		}

		.lifestyle-gallery__item--main {
			grid-column: 1 / -1;
			grid-row: auto;
		}

		.lifestyle-gallery__item--main
			.lifestyle-card__media {
			min-height: 0;
			aspect-ratio: 16 / 10;
		}
	}

	@media (max-width: 680px) {
		.lifestyle-gallery {
			padding:
				72px
				18px;
		}

		.lifestyle-gallery__header {
			margin-bottom: 34px;
		}

		.lifestyle-gallery__header h2 {
			font-size: clamp(36px, 11vw, 50px);
		}

		.lifestyle-gallery__grid {
			grid-template-columns: 1fr;
			gap: 38px;
		}

		.lifestyle-gallery__item--main {
			grid-column: auto;
		}

		.lifestyle-gallery__item--main
			.lifestyle-card__media,
		.lifestyle-gallery__item:not(
				.lifestyle-gallery__item--main
			)
			.lifestyle-card__media {
			aspect-ratio: 4 / 5;
			min-height: 0;
		}

		.lifestyle-card__media {
			border-radius: 18px;
		}

		.lifestyle-card__caption {
			padding-top: 15px;
		}

		.lifestyle-card__caption h3 {
			font-size: 23px;
		}
	}

	@media (prefers-reduced-motion: reduce) {
		.lifestyle-gallery__header,
		.lifestyle-gallery__item,
		.lifestyle-card__media img,
		.lifestyle-card__caption h3 a,
		.lifestyle-card__link span {
			opacity: 1 !important;
			transform: none !important;
			transition: none !important;
		}
	}
</style>
```

## Integración en `src/pages/index.astro`

Añade la importación:

```astro
import LifestyleGallery from "../components/LifestyleGallery.astro";
```

Define un arreglo con **tres imágenes reales ya existentes en el proyecto**. No inventes rutas: usa los archivos y enlaces actuales del repositorio.

Cada elemento debe tener esta forma:

```ts
{
	label: "Parrilla",
	title: "Encuentros alrededor del fuego",
	description: "Piezas resistentes para preparar, servir y compartir.",
	href: "RUTA_REAL_DE_CATEGORIA_O_PRODUCTO",
	image: {
		src: "RUTA_REAL_DE_LA_IMAGEN",
		alt: "Descripción precisa de la escena y del producto TAQTO",
		width: 1600,
		height: 2000,
	},
}
```

Usa esta distribución:

1. Imagen principal: **Parrilla**.
2. Imagen secundaria: **Oficina** o **Regalo**.
3. Imagen secundaria: **Cocina y mesa**.

Inserta el componente inmediatamente después de la sección de campaña:

```astro
<LifestyleGallery items={lifestyleItems} />
```

El orden debe quedar así:

```astro
<section class="campaign-section">
	<div class="campaign-section__container">
		<CampaignBanner />
	</div>
</section>

<LifestyleGallery items={lifestyleItems} />

<CategoriesTeaser />
```

## Requisitos de las imágenes

- Usar fotografías reales de productos TAQTO, no imágenes genéricas.
- Mantener el producto visible y sin texto encima de sus zonas importantes.
- Preferir imágenes verticales de buena resolución.
- Usar `alt` descriptivo, sin repetir palabras como “imagen de”.
- No añadir más de tres imágenes en esta versión.
- La escena principal debe tener mayor peso visual que las dos secundarias.
