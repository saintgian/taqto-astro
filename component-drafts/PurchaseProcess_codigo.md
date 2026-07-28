# PurchaseProcess — código para integrar

## Archivo nuevo: `src/components/PurchaseProcess.astro`

```astro
---
interface PurchaseLink {
	label: string;
	href: string;
}

interface Props {
	links?: PurchaseLink[];
}

const { links = [] } = Astro.props;

const steps = [
	{
		number: "01",
		title: "Elige tu pieza",
		description:
			"Explora el catálogo y encuentra el diseño que mejor se adapte a tu espacio, uso o regalo.",
	},
	{
		number: "02",
		title: "Define la personalización",
		description:
			"Selecciona las opciones disponibles y añade el nombre, frase o imagen que quieras grabar.",
	},
	{
		number: "03",
		title: "Confirmamos los detalles",
		description:
			"Revisamos la información necesaria para preparar correctamente tu pieza antes de producirla.",
	},
	{
		number: "04",
		title: "Preparamos y enviamos",
		description:
			"Trabajamos tu pedido, lo embalamos con cuidado y coordinamos el envío correspondiente.",
	},
];

const visibleLinks = links.filter(
	(link) =>
		typeof link.label === "string" &&
		link.label.trim().length > 0 &&
		typeof link.href === "string" &&
		link.href.trim().length > 0,
);
---

<section
	class="purchase-process"
	aria-labelledby="purchase-process-title"
	data-purchase-process
>
	<div class="purchase-process__container">
		<header class="purchase-process__header">
			<p class="purchase-process__eyebrow">
				Proceso de compra
			</p>

			<h2 id="purchase-process-title">
				De tu elección a tu entrega
			</h2>

			<p class="purchase-process__intro">
				Un proceso claro para que sepas qué ocurre
				desde que eliges tu pieza hasta que la recibes.
			</p>
		</header>

		<ol class="purchase-process__steps">
			{
				steps.map((step, index) => (
					<li
						class="purchase-process__step"
						style={`--step-index: ${index}`}
					>
						<div
							class="purchase-process__marker"
							aria-hidden="true"
						>
							<span>{step.number}</span>
						</div>

						<div class="purchase-process__content">
							<h3>{step.title}</h3>

							<p>{step.description}</p>
						</div>
					</li>
				))
			}
		</ol>

		{
			visibleLinks.length > 0 && (
				<nav
					class="purchase-process__links"
					aria-label="Información sobre tu compra"
				>
					<ul>
						{
							visibleLinks.map((link) => (
								<li>
									<a href={link.href}>
										{link.label}

										<span aria-hidden="true">
											→
										</span>
									</a>
								</li>
							))
						}
					</ul>
				</nav>
			)
		}
	</div>
</section>

<script>
	const initializePurchaseProcess = () => {
		const sections =
			document.querySelectorAll<HTMLElement>(
				"[data-purchase-process]",
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
				section.classList.add(
					"is-visible",
				);

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
						threshold: 0.18,
					},
				);

			observer.observe(section);
		});
	};

	initializePurchaseProcess();

	document.addEventListener(
		"astro:page-load",
		initializePurchaseProcess,
	);
</script>

<style>
	.purchase-process {
		padding:
			clamp(78px, 9vw, 138px)
			var(--page-padding);
		background:
			var(--color-beige, #fff6ed);
		color:
			var(--color-black, #141414);
	}

	.purchase-process__container {
		width:
			min(100%, var(--page-width));
		margin-inline: auto;
	}

	.purchase-process__header {
		max-width: 780px;
		margin-bottom:
			clamp(44px, 6vw, 76px);
	}

	.purchase-process__eyebrow {
		margin: 0 0 18px;
		color:
			var(--color-orange, #ff4d2a);
		font-size: 10px;
		font-weight: 700;
		line-height: 1.3;
		letter-spacing: 0.16em;
		text-transform: uppercase;
	}

	.purchase-process__header h2 {
		margin: 0;
		color:
			var(--color-black, #141414);
		font-size:
			clamp(38px, 5.4vw, 70px);
		font-weight: 600;
		line-height: 0.98;
		letter-spacing: -0.04em;
		text-wrap: balance;
	}

	.purchase-process__intro {
		max-width: 620px;
		margin: 18px 0 0;
		color: rgba(20, 20, 20, 0.65);
		font-size:
			clamp(15px, 1.3vw, 18px);
		line-height: 1.6;
		text-wrap: balance;
	}

	.purchase-process__steps {
		position: relative;
		display: grid;
		grid-template-columns:
			repeat(4, minmax(0, 1fr));
		gap:
			clamp(22px, 3vw, 40px);
		margin: 0;
		padding: 0;
		list-style: none;
	}

	.purchase-process__steps::before {
		position: absolute;
		z-index: 0;
		top: 29px;
		right:
			calc(12.5% - 1px);
		left:
			calc(12.5% - 1px);
		height: 1px;
		background:
			rgba(20, 20, 20, 0.16);
		content: "";
	}

	.purchase-process__steps::after {
		position: absolute;
		z-index: 0;
		top: 29px;
		left:
			calc(12.5% - 1px);
		width: 75%;
		height: 1px;
		background:
			var(--color-brown, #5c312a);
		content: "";
		transform: scaleX(0);
		transform-origin: left;
	}

	.purchase-process__step {
		position: relative;
		z-index: 1;
		min-width: 0;
	}

	.purchase-process__marker {
		display: grid;
		width: 58px;
		height: 58px;
		place-items: center;
		border: 1px solid
			rgba(92, 49, 42, 0.28);
		border-radius: 50%;
		background:
			var(--color-beige, #fff6ed);
	}

	.purchase-process__marker span {
		color:
			var(--color-brown, #5c312a);
		font-size: 13px;
		font-weight: 700;
		line-height: 1;
		letter-spacing: 0.08em;
	}

	.purchase-process__content {
		padding-top: 24px;
	}

	.purchase-process__content h3 {
		margin: 0;
		color:
			var(--color-black, #141414);
		font-size:
			clamp(19px, 1.75vw, 24px);
		font-weight: 600;
		line-height: 1.15;
		letter-spacing: -0.025em;
	}

	.purchase-process__content p {
		margin: 12px 0 0;
		color: rgba(20, 20, 20, 0.64);
		font-size: 13px;
		line-height: 1.6;
	}

	.purchase-process__links {
		margin-top:
			clamp(46px, 6vw, 74px);
		padding-top: 24px;
		border-top: 1px solid
			rgba(20, 20, 20, 0.14);
	}

	.purchase-process__links ul {
		display: flex;
		align-items: center;
		flex-wrap: wrap;
		gap: 10px 28px;
		margin: 0;
		padding: 0;
		list-style: none;
	}

	.purchase-process__links a {
		display: inline-flex;
		min-height: 44px;
		align-items: center;
		gap: 8px;
		color:
			var(--color-brown, #5c312a);
		font-size: 10px;
		font-weight: 700;
		line-height: 1.3;
		letter-spacing: 0.08em;
		text-decoration: none;
		text-transform: uppercase;
	}

	.purchase-process__links a span {
		font-size: 14px;
		transition:
			transform 180ms ease;
	}

	.purchase-process__links a:focus-visible {
		outline: 2px solid
			var(--color-orange, #ff4d2a);
		outline-offset: 4px;
	}

	.purchase-process.is-reveal-ready
		.purchase-process__header,
	.purchase-process.is-reveal-ready
		.purchase-process__step,
	.purchase-process.is-reveal-ready
		.purchase-process__links {
		opacity: 0;
		transform: translateY(16px);
	}

	.purchase-process.is-reveal-ready.is-visible
		.purchase-process__header,
	.purchase-process.is-reveal-ready.is-visible
		.purchase-process__step,
	.purchase-process.is-reveal-ready.is-visible
		.purchase-process__links {
		opacity: 1;
		transform: translateY(0);
		transition:
			opacity 520ms ease,
			transform 520ms
			cubic-bezier(0.22, 1, 0.36, 1);
	}

	.purchase-process.is-reveal-ready.is-visible
		.purchase-process__step {
		transition-delay:
			calc(var(--step-index) * 110ms);
	}

	.purchase-process.is-reveal-ready.is-visible
		.purchase-process__links {
		transition-delay: 460ms;
	}

	.purchase-process.is-reveal-ready.is-visible
		.purchase-process__steps::after {
		transform: scaleX(1);
		transition:
			transform 850ms
			cubic-bezier(0.22, 1, 0.36, 1)
			120ms;
	}

	@media (hover: hover) and (pointer: fine) {
		.purchase-process__links a:hover span {
			transform: translateX(4px);
		}
	}

	@media (max-width: 920px) {
		.purchase-process__steps {
			grid-template-columns:
				repeat(2, minmax(0, 1fr));
			row-gap: 44px;
		}

		.purchase-process__steps::before,
		.purchase-process__steps::after {
			display: none;
		}
	}

	@media (max-width: 640px) {
		.purchase-process {
			padding:
				72px
				18px;
		}

		.purchase-process__header {
			margin-bottom: 38px;
		}

		.purchase-process__header h2 {
			font-size:
				clamp(36px, 11vw, 50px);
		}

		.purchase-process__steps {
			display: block;
		}

		.purchase-process__step {
			display: grid;
			grid-template-columns:
				58px
				minmax(0, 1fr);
			gap: 20px;
			padding-bottom: 36px;
		}

		.purchase-process__step:not(
				:last-child
			)::after {
			position: absolute;
			top: 58px;
			bottom: 0;
			left: 28px;
			width: 1px;
			background:
				rgba(92, 49, 42, 0.26);
			content: "";
			transform: scaleY(0);
			transform-origin: top;
		}

		.purchase-process.is-visible
			.purchase-process__step:not(
				:last-child
			)::after {
			transform: scaleY(1);
			transition:
				transform 460ms ease;
			transition-delay:
				calc(
					120ms +
					var(--step-index) * 110ms
				);
		}

		.purchase-process__marker {
			width: 58px;
			height: 58px;
		}

		.purchase-process__content {
			padding-top: 5px;
		}

		.purchase-process__content h3 {
			font-size: 21px;
		}

		.purchase-process__content p {
			font-size: 13px;
		}

		.purchase-process__links {
			margin-top: 14px;
		}

		.purchase-process__links ul {
			display: grid;
			grid-template-columns: 1fr;
			gap: 0;
		}

		.purchase-process__links li {
			border-bottom: 1px solid
				rgba(20, 20, 20, 0.1);
		}

		.purchase-process__links a {
			width: 100%;
			justify-content: space-between;
			padding-block: 4px;
		}
	}

	@media (prefers-reduced-motion: reduce) {
		.purchase-process__header,
		.purchase-process__step,
		.purchase-process__links,
		.purchase-process__steps::after,
		.purchase-process__step::after,
		.purchase-process__links a span {
			opacity: 1 !important;
			transform: none !important;
			transition: none !important;
		}
	}
</style>
```

## Datos que recibe el componente

El componente incluye los cuatro pasos solicitados y recibe únicamente los enlaces informativos, para que la integración use rutas reales del proyecto.

```ts
interface PurchaseLink {
	label: string;
	href: string;
}
```

Ejemplo de estructura:

```ts
const purchaseLinks = [
	{
		label: "Envíos",
		href: "RUTA_REAL_DE_ENVIOS",
	},
	{
		label: "Personalización",
		href: "RUTA_REAL_DE_PERSONALIZACION",
	},
	{
		label: "Cambios y devoluciones",
		href: "RUTA_REAL_DE_CAMBIOS",
	},
	{
		label: "Preguntas frecuentes",
		href: "RUTA_REAL_DE_PREGUNTAS_FRECUENTES",
	},
];
```

No inventar rutas. Si alguna página aún no existe, omitir temporalmente ese enlace del arreglo.

## Integración en `src/pages/index.astro`

Añade la importación:

```astro
import PurchaseProcess from "../components/PurchaseProcess.astro";
```

Inserta el componente después del componente que cuenta la historia de TAQTO:

```astro
<OriginStats />

<PurchaseProcess links={purchaseLinks} />
```

Si la historia está en otro componente, conserva el orden actual y coloca `PurchaseProcess` inmediatamente después.

## Verificación

- En escritorio aparecen cuatro pasos en una línea horizontal.
- En móvil los pasos forman una línea vertical.
- Cada paso se entiende sin hover.
- La animación ocurre una sola vez al entrar en pantalla.
- `prefers-reduced-motion` elimina las transiciones.
- Los enlaces usan rutas reales y son accesibles con teclado.
- No se muestran sellos, garantías o afirmaciones de seguridad no confirmadas.
