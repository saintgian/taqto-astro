# Design

<!-- impeccable:design-schema 1 -->

Ver [PRODUCT.md](PRODUCT.md) para verdad de producto y [BRAND_CONTEXT.md](BRAND_CONTEXT.md) para el manual de marca oficial (paleta, tipografía, logo, checklist). Este archivo no duplica esas reglas: documenta cómo la Fase 1 del rediseño las aplica en código.

## Dirección

Minimalismo orgánico y comercial. Referentes conceptuales (no copiados literalmente): Grovemade (materiales, composición limpia, producto protagonista) y Fameg (estructura ecommerce sobria y recorrible). Blanco domina como canvas real; negro se reserva para bloques estructurales estratégicos (franja superior, footer, minicarrito no aplica — minicarrito es blanco); marrón y naranja oficiales son los únicos acentos cromáticos.

## Superficie

- `--surface` (blanco) es el fondo dominante de `html`, `body`, layouts y contenedores generales.
- `--surface-warm` (crema, `--color-beige`) queda reservada para diferenciar puntualmente (p. ej. tile de foto de producto en el minicarrito). Nunca es el fondo base de una sección completa.
- Negro sólido (`--color-black`) solo en: franja superior del header, footer completo, panel del minicarrito ya no lo usa (es blanco).

## Tipografía

Escala fluida en `clamp()`, tokens en `BaseLayout.astro` (`--text-xs` … `--text-3xl`). Pisos: texto auxiliar ≥14px, cuerpo/editorial 17–18px, H3 24–30px, H2 30–48px, H1/display 38–64px. `line-height` de cuerpo 1.55–1.7 (`--leading-normal`/`--leading-relaxed`). Tipografía oficial (Poppins, cargada localmente) sin cambios — Univers LT 53 Extended / Malmo Sans del manual de marca no están implementadas en el proyecto; no se sustituyeron por no haber archivos de fuente disponibles.

## Header

Ya no es una cápsula negra flotante. Es una barra blanca sólida, ancho completo, `sticky top:0`, integrada al sistema de gutters (`--page-padding`/`--page-width`). Estructura: franja negra delgada (34px, personalización/atención) + fila de navegación blanca (logo oscuro `logotipo-colorprincipal01.svg`, nav centrada, acciones a la derecha). Naranja solo para el estado activo de navegación y el contador del carrito (texto negro sobre naranja, combinación validada en BRAND_CONTEXT). Dropdowns, menú móvil y minicarrito son ahora paneles blancos con texto negro y sombra suave (`--shadow-lg`), no glass negro.

## Footer

Ya no es una cápsula flotante con brillo radial. Es una franja negra de ancho completo (`--color-black`), sin sombra, sin border-radius, sin glassmorphism. Tres bloques: cabecera comercial (logo + frase + CTA WhatsApp), navegación de 4 columnas (enlaces 16–17px, títulos de grupo ≥14px), cierre (info de empresas, marca + redes + "Conversemos", "Hecho con ♥ en Lima, Perú", copyright, legal, volver arriba). Acordeón `<details>/<summary>` sin cambios de lógica.

## Tokens nuevos relevantes

`--ink-*` (neutros sobre claro), `--cream-40…90` (texto sobre negro, consolidado), `--line-on-dark` / `--fill-on-dark-1/2` (bordes/rellenos sobre negro), `--shadow-sm/md/lg` (claro) y `--shadow-dark-md/lg` (sobre negro), `--focus-ring` (naranja, por defecto) / `--focus-ring-on-dark` (crema, solo dentro de `.announcement` y `.site-footer`).

## Pendiente para próximas fases

Hero, campaña/portada, catálogo, ficha de producto y carrito conservan su diseño previo (crema incluido) hasta que se aborden explícitamente. No usar esta Fase 1 como excusa para tocarlos.
