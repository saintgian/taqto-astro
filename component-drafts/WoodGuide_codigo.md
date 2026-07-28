# WoodGuide — código para integrar

## Archivo nuevo: `src/components/WoodGuide.astro`

```astro
---
interface WoodProductLink {
	title: string;
	href: string;
}

interface WoodGuideImage {
	src: string;
	alt: string;
	width: number;
	height: number;
}

interface WoodGuideItem {
	id: string;
	name: string;
	tone?: string;
	description?: string;
	characteristics?: string[];
	image: WoodGuideImage;
	products?: WoodProductLink[];
}

interface Props {
	woods: WoodGuideItem[];
}

const { woods = [] } = Astro.props;

const visibleWoods = woods.filter(
	(wood) =>
		wood.id?.trim() &&
		wood.name?.trim() &&
		wood.image?.src?.trim(),
);

const safeId = (
	value: string,
): string =>
	value
		.toLowerCase()
		.trim()
		.replace(/[^a-z0-9-_]+/g, "-")
		.replace(/^-+|-+$/g, "");

const componentId = `wood-guide-${
	safeId(visibleWoods[0]?.id || "materials")
}`;
---

{
	visibleWoods.length > 0 && (
		<section
			class="wood-guide"
			aria-labelledby={`${componentId}-title`}
			data-wood-guide
		>
			<div class="wood-guide__container">
				<header class="wood-guide__header">
					<p class="wood-guide__eyebrow">
						Materiales TAQTO
					</p>

					<div class="wood-guide__heading">
						<h2 id={`${componentId}-title`}>
							Conoce nuestras maderas
						</h2>

						<p>
							Explora las especies disponibles
							en nuestras piezas.
						</p>
					</div>
				</header>

				<div
					class="wood-guide__tabs"
					role="tablist"
					aria-label="Selecciona una especie de madera"
				>
					{
						visibleWoods.map((wood, index) => {
							const tabId =
								`${componentId}-tab-${index}`;

							const panelId =
								`${componentId}-panel-${index}`;

							return (
								<button
									id={tabId}
									class="wood-guide__tab"
									type="button"
									role="tab"
									aria-selected={
										index === 0
											? "true"
											: "false"
									}
									aria-controls={panelId}
									tabindex={index === 0 ? 0 : -1}
									data-wood-tab
									data-wood-tab-index={index}
								>
									{wood.name}
								</button>
							);
						})
					}
				</div>

				<div class="wood-guide__panels">
					{
						visibleWoods.map((wood, index) => {
							const tabId =
								`${componentId}-tab-${index}`;

							const panelId =
								`${componentId}-panel-${index}`;

							const characteristics =
								(wood.characteristics || [])
									.filter(
										(item) =>
											typeof item ===
												"string" &&
											item.trim().length > 0,
									);

							const products =
								(wood.products || [])
									.filter(
										(product) =>
											product.title?.trim() &&
											product.href?.trim(),
									)
									.slice(0, 4);

							return (
								<article
									id={panelId}
									class:list={[
										"wood-guide__panel",
										index === 0 &&
											"is-active",
									]}
									role="tabpanel"
									aria-labelledby={tabId}
									aria-hidden={
										index === 0
											? "false"
											: "true"
									}
									hidden={index !== 0}
									data-wood-panel
								>
									<div class="wood-guide__media">
										<img
											src={wood.image.src}
											alt={wood.image.alt}
											width={wood.image.width}
											height={wood.image.height}
											loading="lazy"
											decoding="async"
										/>
									</div>

									<div class="wood-guide__content">
										<p class="wood-guide__selected-label">
											Madera seleccionada
										</p>

										<h3>{wood.name}</h3>

										{
											wood.tone && (
												<div class="wood-guide__tone">
													<span>
														Tonalidad
													</span>

													<p>
														{wood.tone}
													</p>
												</div>
											)
										}

										{
											wood.description && (
												<p class="wood-guide__description">
													{wood.description}
												</p>
											)
										}

										{
											characteristics.length >
												0 && (
												<div class="wood-guide__details">
													<p class="wood-guide__details-title">
														Características
														confirmadas
													</p>

													<ul>
														{
															characteristics.map(
																(item) => (
																	<li>
																		{item}
																	</li>
																),
															)
														}
													</ul>
												</div>
											)
										}

										{
											products.length > 0 && (
												<div class="wood-guide__products">
													<p class="wood-guide__products-title">
														Productos
														disponibles
													</p>

													<ul>
														{
															products.map(
																(product) => (
																	<li>
																		<a
																			href={
																				product.href
																			}
																		>
																			{
																				product.title
																			}

																			<span
																				aria-hidden="true"
																			>
																				→
																			</span>
																		</a>
																	</li>
																),
															)
														}
													</ul>
												</div>
											)
										}
									</div>
								</article>
							);
						})
					}
				</div>

				<p class="wood-guide__note">
					<span aria-hidden="true">✦</span>
					La veta y el tono pueden variar
					naturalmente entre piezas.
				</p>
			</div>
		</section>
	)
}

<script>
	const initializeWoodGuide = () => {
		const sections =
			document.querySelectorAll<HTMLElement>(
				"[data-wood-guide]",
			);

		sections.forEach((section) => {
			if (
				section.dataset.initialized ===
				"true"
			) {
				return;
			}

			section.dataset.initialized = "true";

			const tabs = Array.from(
				section.querySelectorAll<HTMLButtonElement>(
					"[data-wood-tab]",
				),
			);

			const panels = Array.from(
				section.querySelectorAll<HTMLElement>(
					"[data-wood-panel]",
				),
			);

			if (
				tabs.length === 0 ||
				panels.length === 0
			) {
				return;
			}

			const activateTab = (
				index: number,
				moveFocus = false,
			) => {
				const normalizedIndex =
					((index % tabs.length) +
						tabs.length) %
					tabs.length;

				tabs.forEach((tab, tabIndex) => {
					const isSelected =
						tabIndex === normalizedIndex;

					tab.setAttribute(
						"aria-selected",
						isSelected ? "true" : "false",
					);

					tab.setAttribute(
						"tabindex",
						isSelected ? "0" : "-1",
					);
				});

				panels.forEach(
					(panel, panelIndex) => {
						const isSelected =
							panelIndex ===
							normalizedIndex;

						if (!isSelected) {
							panel.classList.remove(
								"is-active",
							);

							panel.hidden = true;

							panel.setAttribute(
								"aria-hidden",
								"true",
							);

							return;
						}

						panel.hidden = false;

						panel.setAttribute(
							"aria-hidden",
							"false",
						);

						window.requestAnimationFrame(
							() => {
								panel.classList.add(
									"is-active",
								);
							},
						);
					},
				);

				if (moveFocus) {
					tabs[normalizedIndex]?.focus();
				}
			};

			tabs.forEach((tab, index) => {
				tab.addEventListener("click", () => {
					activateTab(index);
				});

				tab.addEventListener(
					"keydown",
					(event) => {
						let nextIndex: number | null =
							null;

						switch (event.key) {
							case "ArrowRight":
							case "ArrowDown":
								nextIndex = index + 1;
								break;

							case "ArrowLeft":
							case "ArrowUp":
								nextIndex = index - 1;
								break;

							case "Home":
								nextIndex = 0;
								break;

							case "End":
								nextIndex =
									tabs.length - 1;
								break;
						}

						if (nextIndex === null) {
							return;
						}

						event.preventDefault();

						activateTab(
							nextIndex,
							true,
						);
					},
				);
			});
		});
	};

	initializeWoodGuide();

	document.addEventListener(
		"astro:page-load",
		initializeWoodGuide,
	);
</script>

<style>
	.wood-guide {
		padding:
			clamp(84px, 10vw, 156px)
			var(--page-padding);
		background: #ffffff;
		color: var(--color-black, #141414);
	}

	.wood-guide__container {
		width: min(100%, var(--page-width));
		margin-inline: auto;
	}

	.wood-guide__header {
		display: grid;
		grid-template-columns:
			minmax(0, 0.42fr)
			minmax(0, 1fr);
		align-items: end;
		gap: clamp(28px, 6vw, 96px);
		margin-bottom: clamp(38px, 5vw, 62px);
	}

	.wood-guide__eyebrow {
		margin: 0 0 8px;
		color: var(--color-orange, #ff4d2a);
		font-size: 10px;
		font-weight: 700;
		line-height: 1.3;
		letter-spacing: 0.16em;
		text-transform: uppercase;
	}

	.wood-guide__heading h2 {
		max-width: 860px;
		margin: 0;
		color: var(--color-black, #141414);
		font-size: clamp(38px, 5.4vw, 72px);
		font-weight: 600;
		line-height: 0.98;
		letter-spacing: -0.04em;
		text-wrap: balance;
	}

	.wood-guide__heading > p {
		max-width: 560px;
		margin: 18px 0 0;
		color: rgba(20, 20, 20, 0.64);
		font-size: clamp(15px, 1.35vw, 18px);
		line-height: 1.6;
	}

	.wood-guide__tabs {
		display: flex;
		gap: clamp(24px, 4vw, 56px);
		overflow-x: auto;
		margin-bottom: clamp(36px, 5vw, 62px);
		border-bottom: 1px solid
			rgba(20, 20, 20, 0.14);
		scrollbar-width: thin;
		scrollbar-color:
			rgba(20, 20, 20, 0.28)
			transparent;
		overscroll-behavior-inline: contain;
	}

	.wood-guide__tab {
		position: relative;
		min-height: 52px;
		flex: 0 0 auto;
		padding: 0 0 17px;
		border: 0;
		background: transparent;
		color: rgba(20, 20, 20, 0.5);
		font: inherit;
		font-size: clamp(18px, 2vw, 28px);
		font-weight: 600;
		line-height: 1.1;
		letter-spacing: -0.025em;
		cursor: pointer;
		transition:
			color 180ms ease;
	}

	.wood-guide__tab::after {
		position: absolute;
		right: 0;
		bottom: -1px;
		left: 0;
		height: 2px;
		background: var(
			--color-brown,
			#5c312a
		);
		content: "";
		transform: scaleX(0);
		transform-origin: left;
		transition:
			transform 220ms ease;
	}

	.wood-guide__tab[aria-selected="true"] {
		color: var(--color-black, #141414);
	}

	.wood-guide__tab[aria-selected="true"]::after {
		transform: scaleX(1);
	}

	.wood-guide__tab:focus-visible {
		outline: 2px solid
			var(--color-orange, #ff4d2a);
		outline-offset: 4px;
	}

	.wood-guide__panel {
		display: grid;
		grid-template-columns:
			minmax(0, 1.18fr)
			minmax(320px, 0.82fr);
		align-items: center;
		gap: clamp(46px, 7vw, 112px);
		opacity: 0;
		transform: translateY(8px);
		transition:
			opacity 220ms ease,
			transform 220ms ease;
	}

	.wood-guide__panel[hidden] {
		display: none;
	}

	.wood-guide__panel.is-active {
		opacity: 1;
		transform: translateY(0);
	}

	.wood-guide__media {
		aspect-ratio: 5 / 4;
		overflow: hidden;
		border-radius: 24px;
		background: var(
			--color-beige,
			#fff6ed
		);
	}

	.wood-guide__media img {
		display: block;
		width: 100%;
		height: 100%;
		object-fit: cover;
		object-position: center;
		transition:
			transform 480ms
			cubic-bezier(0.22, 1, 0.36, 1);
	}

	.wood-guide__content {
		max-width: 560px;
	}

	.wood-guide__selected-label,
	.wood-guide__details-title,
	.wood-guide__products-title {
		margin: 0;
		color: var(--color-orange, #ff4d2a);
		font-size: 9px;
		font-weight: 700;
		line-height: 1.3;
		letter-spacing: 0.14em;
		text-transform: uppercase;
	}

	.wood-guide__content h3 {
		margin: 12px 0 0;
		color: var(--color-black, #141414);
		font-size: clamp(36px, 4.5vw, 62px);
		font-weight: 600;
		line-height: 0.98;
		letter-spacing: -0.04em;
	}

	.wood-guide__tone {
		display: grid;
		grid-template-columns: 92px 1fr;
		gap: 20px;
		margin-top: 28px;
		padding-block: 16px;
		border-top: 1px solid
			rgba(20, 20, 20, 0.12);
		border-bottom: 1px solid
			rgba(20, 20, 20, 0.12);
	}

	.wood-guide__tone span {
		color: rgba(20, 20, 20, 0.52);
		font-size: 11px;
		font-weight: 700;
		line-height: 1.4;
		letter-spacing: 0.08em;
		text-transform: uppercase;
	}

	.wood-guide__tone p {
		margin: 0;
		color: var(--color-black, #141414);
		font-size: 14px;
		line-height: 1.5;
	}

	.wood-guide__description {
		margin: 24px 0 0;
		color: rgba(20, 20, 20, 0.68);
		font-size: clamp(15px, 1.3vw, 18px);
		line-height: 1.65;
	}

	.wood-guide__details,
	.wood-guide__products {
		margin-top: 28px;
	}

	.wood-guide__details ul,
	.wood-guide__products ul {
		margin: 14px 0 0;
		padding: 0;
		list-style: none;
	}

	.wood-guide__details li {
		position: relative;
		padding:
			10px
			0
			10px
			20px;
		border-bottom: 1px solid
			rgba(20, 20, 20, 0.1);
		color: rgba(20, 20, 20, 0.7);
		font-size: 14px;
		line-height: 1.5;
	}

	.wood-guide__details li::before {
		position: absolute;
		top: 18px;
		left: 2px;
		width: 5px;
		height: 5px;
		border-radius: 50%;
		background: var(
			--color-brown,
			#5c312a
		);
		content: "";
	}

	.wood-guide__products ul {
		display: flex;
		flex-wrap: wrap;
		gap: 9px;
	}

	.wood-guide__products a {
		display: inline-flex;
		min-height: 42px;
		align-items: center;
		gap: 8px;
		padding: 0 14px;
		border: 1px solid
			rgba(92, 49, 42, 0.24);
		border-radius: 999px;
		color: var(
			--color-brown,
			#5c312a
		);
		font-size: 10px;
		font-weight: 700;
		line-height: 1.3;
		letter-spacing: 0.07em;
		text-decoration: none;
		text-transform: uppercase;
		transition:
			border-color 180ms ease,
			background-color 180ms ease,
			color 180ms ease;
	}

	.wood-guide__products a:focus-visible {
		outline: 2px solid
			var(--color-orange, #ff4d2a);
		outline-offset: 3px;
	}

	.wood-guide__note {
		display: flex;
		align-items: center;
		gap: 11px;
		margin:
			clamp(40px, 5vw, 66px)
			0
			0;
		padding-top: 22px;
		border-top: 1px solid
			rgba(20, 20, 20, 0.12);
		color: rgba(20, 20, 20, 0.64);
		font-size: 13px;
		line-height: 1.5;
	}

	.wood-guide__note span {
		color: var(
			--color-orange,
			#ff4d2a
		);
		font-size: 12px;
	}

	@media (hover: hover) and (pointer: fine) {
		.wood-guide__tab:hover {
			color: var(
				--color-brown,
				#5c312a
			);
		}

		.wood-guide__panel:hover
			.wood-guide__media img {
			transform: scale(1.012);
		}

		.wood-guide__products a:hover {
			border-color: var(
				--color-brown,
				#5c312a
			);
			background: var(
				--color-brown,
				#5c312a
			);
			color: var(
				--color-beige,
				#fff6ed
			);
		}
	}

	@media (max-width: 960px) {
		.wood-guide__header {
			grid-template-columns: 1fr;
			gap: 14px;
		}

		.wood-guide__panel {
			grid-template-columns: 1fr;
			align-items: start;
			gap: 36px;
		}

		.wood-guide__media {
			aspect-ratio: 16 / 10;
		}

		.wood-guide__content {
			max-width: 680px;
		}
	}

	@media (max-width: 680px) {
		.wood-guide {
			padding:
				72px
				18px;
		}

		.wood-guide__header {
			margin-bottom: 30px;
		}

		.wood-guide__heading h2 {
			font-size: clamp(
				36px,
				11vw,
				50px
			);
		}

		.wood-guide__tabs {
			gap: 28px;
			margin-inline: -18px;
			padding-inline: 18px;
			scroll-padding-inline: 18px;
		}

		.wood-guide__tab {
			min-height: 48px;
			font-size: 20px;
		}

		.wood-guide__panel {
			gap: 28px;
		}

		.wood-guide__media {
			aspect-ratio: 4 / 3;
			border-radius: 18px;
		}

		.wood-guide__content h3 {
			font-size: 40px;
		}

		.wood-guide__tone {
			grid-template-columns: 1fr;
			gap: 6px;
		}

		.wood-guide__products ul {
			display: grid;
			grid-template-columns: 1fr;
		}

		.wood-guide__products a {
			justify-content:
				space-between;
		}
	}

	@media (prefers-reduced-motion: reduce) {
		.wood-guide__tab,
		.wood-guide__tab::after,
		.wood-guide__panel,
		.wood-guide__media img,
		.wood-guide__products a {
			transition: none !important;
		}

		.wood-guide__panel {
			opacity: 1;
			transform: none;
		}
	}
</style>
```

## Datos que recibe el componente

El componente no contiene especies ni características escritas a mano. Recibe un arreglo `woods` para que la integración use exclusivamente información real de Sanity o de la documentación aprobada.

```ts
interface WoodGuideItem {
	id: string;
	name: string;
	tone?: string;
	description?: string;
	characteristics?: string[];
	image: {
		src: string;
		alt: string;
		width: number;
		height: number;
	};
	products?: {
		title: string;
		href: string;
	}[];
}
```

Reglas para construir el arreglo:

- `name`: nombre existente de la especie.
- `tone`, `description` y `characteristics`: incluirlos solo cuando estén confirmados.
- `image.src`: fotografía real o macro real de esa madera; nunca una textura CSS ni un degradado.
- `products`: únicamente productos activos que realmente estén disponibles en esa madera.
- No rellenar campos faltantes con información estimada.
- No afirmar dureza, resistencia, procedencia, sostenibilidad o durabilidad si esos datos no existen en la fuente aprobada.

## Integración en `src/pages/index.astro`

Añade la importación:

```astro
import WoodGuide from "../components/WoodGuide.astro";
```

Pasa el arreglo real obtenido durante la integración:

```astro
<WoodGuide woods={woodGuideItems} />
```

Insértalo inmediatamente después de `LifestyleGallery` y antes de la sección que cuenta la historia de TAQTO:

```astro
<LifestyleGallery items={lifestyleItems} />

<WoodGuide woods={woodGuideItems} />

<OriginStats />
```

Si la historia de TAQTO está representada por otro componente, conserva ese componente y coloca `WoodGuide` justo antes de él.

## Verificación

- Los tabs funcionan con clic, `Tab`, flechas, `Home` y `End`.
- En móvil, el selector se desplaza horizontalmente sin mover toda la página.
- Al cambiar de madera se actualizan fotografía, nombre, tonalidad, descripción, características y productos.
- No aparece información vacía ni texto inventado.
- Todas las imágenes tienen dimensiones, `alt`, carga diferida y proporción estable.
- La nota sobre variación natural permanece visible.
- `prefers-reduced-motion` elimina las transiciones.
