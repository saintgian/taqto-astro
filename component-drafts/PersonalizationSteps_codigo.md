# PersonalizationSteps.astro

## Archivo nuevo

Ruta:

```text
src/components/PersonalizationSteps.astro
```

```astro
---
interface Props {
	imageSrc: string;
	imageAlt: string;
	ctaHref: string;
}

const {
	imageSrc,
	imageAlt,
	ctaHref,
} = Astro.props;

const steps = [
	{
		number: "01",
		title: "Elige tu pieza",
		description:
			"Encuentra el diseño que acompañará tu mesa, cocina, parrilla o espacio de trabajo.",
	},
	{
		number: "02",
		title: "Selecciona la madera",
		description:
			"Escoge entre las maderas disponibles y sus variaciones naturales de tono y veta.",
	},
	{
		number: "03",
		title: "Añade tu grabado",
		description:
			"Personaliza la pieza con un nombre, una frase o una imagen preparada para grabado láser.",
	},
];
---

<section
	class="personalization"
	aria-labelledby="personalization-title"
	data-personalization
>
	<div class="personalization__container">
		<div class="personalization__media">
			<img
				src={imageSrc}
				alt={imageAlt}
				width="1200"
				height="1500"
				loading="lazy"
				decoding="async"
			/>
		</div>

		<div class="personalization__content">
			<header class="personalization__header">
				<p class="personalization__eyebrow">
					Personalización TAQTO
				</p>

				<h2 id="personalization-title">
					Una pieza hecha para ti
				</h2>

				<p class="personalization__intro">
					Elige el diseño, selecciona la madera y añade un
					nombre, una frase o una imagen.
				</p>
			</header>

			<ol class="personalization__steps">
				{
					steps.map((step, index) => (
						<li
							class="personalization__step"
							style={`--step-index: ${index}`}
						>
							<span
								class="personalization__number"
								aria-hidden="true"
							>
								{step.number}
							</span>

							<div class="personalization__step-copy">
								<h3>{step.title}</h3>
								<p>{step.description}</p>
							</div>
						</li>
					))
				}
			</ol>

			<a class="personalization__cta" href={ctaHref}>
				Empieza a personalizar
				<span aria-hidden="true">→</span>
			</a>
		</div>
	</div>
</section>

<script>
	const initializePersonalization = () => {
		const sections = document.querySelectorAll<HTMLElement>(
			"[data-personalization]",
		);

		sections.forEach((section) => {
			if (section.dataset.initialized === "true") {
				return;
			}

			section.dataset.initialized = "true";

			const reducedMotion = window.matchMedia(
				"(prefers-reduced-motion: reduce)",
			).matches;

			if (
				reducedMotion ||
				!("IntersectionObserver" in window)
			) {
				section.classList.add("is-visible");
				return;
			}

			section.classList.add("is-reveal-ready");

			const observer = new IntersectionObserver(
				(entries) => {
					entries.forEach((entry) => {
						if (!entry.isIntersecting) return;

						section.classList.add("is-visible");
						observer.disconnect();
					});
				},
				{
					threshold: 0.15,
				},
			);

			observer.observe(section);
		});
	};

	initializePersonalization();

	document.addEventListener(
		"astro:page-load",
		initializePersonalization,
	);
</script>

<style>
	.personalization {
		padding:
			clamp(80px, 10vw, 150px)
			var(--page-padding);
		background: var(--color-beige, #fff6ed);
		color: var(--color-black, #141414);
	}

	.personalization__container {
		display: grid;
		width: min(100%, var(--page-width));
		margin-inline: auto;
		grid-template-columns: minmax(0, 1.05fr) minmax(0, 0.95fr);
		align-items: stretch;
		gap: clamp(48px, 7vw, 110px);
	}

	.personalization__media {
		min-height: clamp(520px, 60vw, 760px);
		overflow: hidden;
		border-radius: 28px;
		background: #eadfd3;
	}

	.personalization__media img {
		display: block;
		width: 100%;
		height: 100%;
		object-fit: cover;
		object-position: center;
	}

	.personalization__content {
		display: flex;
		align-self: center;
		flex-direction: column;
		padding-block: clamp(12px, 2vw, 28px);
	}

	.personalization__header {
		max-width: 620px;
	}

	.personalization__eyebrow {
		margin: 0 0 20px;
		color: var(--color-orange, #ff4d2a);
		font-size: 10px;
		font-weight: 700;
		line-height: 1.3;
		letter-spacing: 0.16em;
		text-transform: uppercase;
	}

	.personalization__header h2 {
		margin: 0;
		font-size: clamp(38px, 5vw, 68px);
		font-weight: 600;
		line-height: 0.98;
		letter-spacing: -0.04em;
		text-wrap: balance;
	}

	.personalization__intro {
		max-width: 560px;
		margin: 22px 0 0;
		color: rgba(20, 20, 20, 0.68);
		font-size: clamp(16px, 1.4vw, 19px);
		line-height: 1.6;
		text-wrap: balance;
	}

	.personalization__steps {
		position: relative;
		display: grid;
		gap: 0;
		margin: clamp(40px, 5vw, 64px) 0 0;
		padding: 0;
		list-style: none;
	}

	.personalization__steps::before {
		position: absolute;
		top: 34px;
		bottom: 34px;
		left: 31px;
		width: 1px;
		background: rgba(20, 20, 20, 0.18);
		content: "";
		transform: scaleY(1);
		transform-origin: top;
	}

	.personalization__step {
		position: relative;
		display: grid;
		grid-template-columns: 64px minmax(0, 1fr);
		gap: 24px;
		padding: 0 0 34px;
	}

	.personalization__step:last-child {
		padding-bottom: 0;
	}

	.personalization__number {
		position: relative;
		z-index: 1;
		display: grid;
		width: 64px;
		height: 64px;
		place-items: center;
		border: 1px solid rgba(20, 20, 20, 0.16);
		border-radius: 50%;
		background: var(--color-beige, #fff6ed);
		color: var(--color-brown, #5c312a);
		font-size: 18px;
		font-weight: 600;
		line-height: 1;
		letter-spacing: -0.02em;
	}

	.personalization__step-copy {
		padding-top: 6px;
	}

	.personalization__step-copy h3 {
		margin: 0;
		font-size: clamp(20px, 2vw, 26px);
		font-weight: 600;
		line-height: 1.15;
		letter-spacing: -0.025em;
	}

	.personalization__step-copy p {
		max-width: 500px;
		margin: 9px 0 0;
		color: rgba(20, 20, 20, 0.62);
		font-size: 14px;
		line-height: 1.6;
	}

	.personalization__cta {
		display: inline-flex;
		width: fit-content;
		min-height: 48px;
		align-items: center;
		justify-content: center;
		gap: 12px;
		margin-top: clamp(36px, 5vw, 58px);
		padding: 0 22px;
		border: 1px solid var(--color-brown, #5c312a);
		border-radius: 999px;
		background: var(--color-brown, #5c312a);
		color: var(--color-beige, #fff6ed);
		font-size: 11px;
		font-weight: 700;
		line-height: 1;
		letter-spacing: 0.09em;
		text-decoration: none;
		text-transform: uppercase;
		transition:
			background-color 180ms ease,
			border-color 180ms ease,
			transform 180ms ease;
	}

	.personalization__cta span {
		font-size: 16px;
		transition: transform 180ms ease;
	}

	.personalization__cta:focus-visible {
		outline: 2px solid var(--color-orange, #ff4d2a);
		outline-offset: 4px;
	}

	.personalization__cta:active {
		transform: translateY(1px);
	}

	.personalization.is-reveal-ready
		.personalization__header,
	.personalization.is-reveal-ready
		.personalization__step,
	.personalization.is-reveal-ready
		.personalization__cta {
		opacity: 0;
		transform: translateY(18px);
	}

	.personalization.is-reveal-ready
		.personalization__steps::before {
		transform: scaleY(0);
	}

	.personalization.is-reveal-ready.is-visible
		.personalization__header,
	.personalization.is-reveal-ready.is-visible
		.personalization__step,
	.personalization.is-reveal-ready.is-visible
		.personalization__cta {
		opacity: 1;
		transform: translateY(0);
		transition:
			opacity 520ms ease,
			transform 520ms cubic-bezier(0.22, 1, 0.36, 1);
	}

	.personalization.is-reveal-ready.is-visible
		.personalization__step {
		transition-delay: calc(var(--step-index) * 110ms + 120ms);
	}

	.personalization.is-reveal-ready.is-visible
		.personalization__cta {
		transition-delay: 430ms;
	}

	.personalization.is-reveal-ready.is-visible
		.personalization__steps::before {
		transform: scaleY(1);
		transition: transform 760ms ease 180ms;
	}

	@media (hover: hover) and (pointer: fine) {
		.personalization__cta:hover {
			border-color: var(--color-black, #141414);
			background: var(--color-black, #141414);
		}

		.personalization__cta:hover span {
			transform: translateX(4px);
		}
	}

	@media (max-width: 900px) {
		.personalization__container {
			grid-template-columns: 1fr;
			gap: 48px;
		}

		.personalization__media {
			min-height: auto;
			aspect-ratio: 4 / 5;
		}

		.personalization__content {
			padding-block: 0;
		}
	}

	@media (max-width: 600px) {
		.personalization {
			padding:
				72px
				18px;
		}

		.personalization__container {
			gap: 38px;
		}

		.personalization__media {
			border-radius: 20px;
		}

		.personalization__header h2 {
			font-size: clamp(36px, 12vw, 50px);
		}

		.personalization__steps {
			margin-top: 36px;
		}

		.personalization__steps::before {
			left: 25px;
		}

		.personalization__step {
			grid-template-columns: 52px minmax(0, 1fr);
			gap: 18px;
			padding-bottom: 28px;
		}

		.personalization__number {
			width: 52px;
			height: 52px;
			font-size: 15px;
		}

		.personalization__step-copy {
			padding-top: 3px;
		}

		.personalization__step-copy h3 {
			font-size: 21px;
		}

		.personalization__cta {
			width: 100%;
		}
	}

	@media (prefers-reduced-motion: reduce) {
		.personalization__header,
		.personalization__step,
		.personalization__cta,
		.personalization__steps::before,
		.personalization__cta span {
			opacity: 1 !important;
			transform: none !important;
			transition: none !important;
		}
	}
</style>
```

## Integración en la portada

Archivo:

```text
src/pages/index.astro
```

Añadir la importación:

```astro
import PersonalizationSteps from "../components/PersonalizationSteps.astro";
```

Insertar inmediatamente después de `FeaturedProducts`:

```astro
<FeaturedProducts />

<PersonalizationSteps
	imageSrc={RUTA_REAL_DE_LA_IMAGEN}
	imageAlt="Detalle cercano de una pieza TAQTO personalizada mediante grabado láser"
	ctaHref={RUTA_REAL_HACIA_LOS_PRODUCTOS_PERSONALIZABLES}
/>
```

La integración debe usar una imagen real existente del proyecto y una ruta válida ya definida. No crear rutas nuevas ni usar valores de ejemplo en producción.
