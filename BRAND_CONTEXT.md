# TAQTO — Brand Context para desarrollo web

Fuente: Manual Maestro de Marca TAQTO, versión consolidada 14-07-2026.  
Uso: contexto compacto para diseño, contenido y frontend. Las reglas **OFICIALES** son obligatorias. Las **RECOMENDADAS** son inferencias técnicas y no forman parte del manual.

## 1. Núcleo de marca — OFICIAL

- Marca peruana de piezas de madera y cuero para parrilla, mesa, hogar, oficina y regalo.
- Posicionamiento: **Neo-Artesanía Peruana de Precisión**.
- Línea expresiva opcional: **Diseño con alma de madera**.
- Promesa: diseño útil y sobrio, precisión, materiales honestos y personalización significativa.
- Personalidad: sobria, cálida, minimalista y técnica cuando se requiere detalle.
- Evitar: folclorismo, saturación, improvisación, lujo artificial, ruido visual y afirmaciones difíciles de verificar.
- Criterio rector: precisión, honestidad material y utilidad cotidiana.

## 2. Identidad verbal — OFICIAL

- Voz: sobria, cálida, precisa y visualmente contenida.
- Español claro para Perú; no forzar peruanismos.
- Explicar valor con hechos: especie, veta, tono, grosor, acabado, medidas, uso, cuidados, grabado y entrega.
- Evitar “premium” sin prueba, superlativos vacíos, promesas no demostrables y clichés artesanales.
- Indicar cuando corresponda: fotos referenciales; veta y tono varían naturalmente entre piezas.
- Personalización incluida: un logo o imagen y una frase o nombre, sujeto a viabilidad técnica y condiciones vigentes.
- Empresas: usar **co-branding**, no “marca blanca”; TAQTO permanece visible junto a la marca del cliente.

## 3. Paleta — OFICIAL

| Token sugerido | Valor | Uso oficial |
|---|---:|---|
| `--color-ink` | `#141414` | Texto principal, fondos sobrios, marca monocromática oscura |
| `--color-cream` | `#FFF6ED` | Fondo cálido y superficies secundarias |
| `--color-accent` | `#FF4D2A` | Acento minoritario para CTA, etiquetas y estados |
| `--color-brand` | `#5C312A` | Marrón corporativo e identitario principal |

Contrastes validados:
- Negro sobre beige: 17.24:1.
- Marrón sobre beige: 10.20:1.
- Negro sobre anaranjado: 5.57:1.
- Beige sobre marrón: 10.20:1.

Reglas:
- El anaranjado es una señal minoritaria, no el color dominante de la interfaz.
- No sustituir el marrón oficial por versiones anteriores.
- No introducir colores de marca adicionales sin una fuente aprobada.

## 4. Tipografía — OFICIAL

- **Univers LT 53 Extended**: títulos, destacados y CTA breves.
- **Malmo Sans**: textos largos, navegación, fichas técnicas, formularios, precios y avisos.
- Usar únicamente archivos licenciados conservados por TAQTO; no descargar ni reemplazar fuentes sin autorización.
- Si una fuente no carga, corregir rutas y declaraciones existentes antes de proponer otra tipografía.

## 5. Logo e iconografía — OFICIAL

- Isotipo: pájaro carpintero geométrico.
- Imagotipo: símbolo + TAQTO y, cuando corresponda, línea expresiva.
- Versiones aprobadas: principal, complementaria y monocromática. Los artes vectoriales externos son la referencia definitiva.
- Tamaños digitales de referencia: 22.7 px, 51 px y 107.7 px; en UI suelen redondearse a 24 px, 52 px y 108 px si se conserva la legibilidad.
- No reconstruir, deformar, recolorear arbitrariamente ni alterar proporciones del logo.
- El manual no define una familia de iconos UI. No presentar un estilo iconográfico inferido como regla oficial.

## 6. Dirección visual y composición — OFICIAL

- Lenguaje geométrico, preciso y contenido: rectas, módulos, líneas de corte, contenedores limpios y espacios cálidos.
- Peruanidad contemporánea mediante materiales, diseño y rituales reales; no mediante ornamento folclórico o estereotipos.
- La madera debe aparecer como material real, con veta y variación; nunca como textura simulada decorativa.
- Priorizar utilidad, escala, medidas, espesores, acabados y construcción por encima de mensajes aspiracionales genéricos.
- Fondos oficiales aplicables: beige para superficies cálidas/secundarias; negro para fondos sobrios. El manual no prescribe porcentajes de uso.

## 7. Fotografía — OFICIAL

- Luz cálida, natural y controlada.
- Mostrar textura, canto, grosor, veta y acabado.
- Contextos contemporáneos: parrilla, mesa, cocina, escritorio, regalo y servicio profesional.
- Conservar forma, proporción, veta, color base y terminación reales del producto.
- No estilizar, modificar o idealizar el producto hasta volverlo distinto de la pieza real.

## 8. Botones y estados — OFICIAL

El manual solo establece:
- Univers LT 53 Extended para CTA breves.
- Anaranjado como acento minoritario para CTA, etiquetas y estados.
- Combinaciones legibles validadas: negro/anaranjado y beige/marrón.

No define alturas, radios, bordes, sombras, hover, focus, iconos, jerarquías ni tamaños de botón.

## 9. Responsive y espaciado — OFICIAL

- No existen breakpoints, grids, escalas de espaciado, tamaños fluidos ni reglas responsive oficiales.
- Solo existen tamaños digitales de referencia para la marca: 24/52/108 px aproximadamente, sujetos a legibilidad.
- No atribuir al manual decisiones responsive que no contiene.

## 10. Inferencias técnicas recomendadas — NO OFICIALES

Aplicar solo cuando el proyecto existente no tenga una regla equivalente:

- Reutilizar los tokens, componentes, grid y escala de espacios ya presentes; no crear un segundo sistema visual.
- Usar una escala de espaciado consistente basada en 4 u 8 px y limitar el ancho de lectura de textos largos.
- Mantener fondos mayormente crema/neutros; reservar negro para secciones sobrias y anaranjado para señales puntuales.
- CTA principal recomendado: fondo marrón + texto beige. CTA destacado puntual: anaranjado + texto negro. No es una jerarquía oficial.
- Objetivos táctiles de al menos 44 × 44 px, foco visible, navegación por teclado y estados disabled/loading/error comprensibles.
- Iconos UI recomendados: geométricos, simples, consistentes en trazo y sin decoración folclórica.
- Imágenes responsive con proporción estable, `object-fit` adecuado, dimensiones declaradas y formatos optimizados sin deformar el producto.
- Breakpoints y columnas deben derivarse del contenido y del sistema actual, no de valores arbitrarios. Verificar como mínimo móvil estrecho, tablet y escritorio.
- En móvil: conservar jerarquía, evitar texto superpuesto sobre el producto, mantener CTA accesibles y convertir submenús en controles operables por toque y teclado.
- Usar `clamp()` únicamente si encaja con la tipografía existente y no compromete legibilidad.

## 11. Empresas — OFICIAL

Arquitectura comercial:
- Página matriz: **Empresas**.
- Subpáginas: **Regalos corporativos** y **Ventas al por mayor**.
- Información relevante: personalización, co-branding, tiempos, pedido mínimo y cotización.
- Mayorista: mínimo 12 unidades, pago al contado y sin crédito.
- Co-branding: sello TAQTO preferentemente al reverso; según producto, base o esquina.
- Cobertura nacional; tarifa plana en Lima y embalaje según producto.
- No inventar plazos, descuentos, certificaciones, capacidad productiva ni promesas ambientales.

## 12. Checklist de implementación

- [ ] Usa colores y tipografías oficiales sin sustituciones.
- [ ] Mantiene el anaranjado como acento minoritario.
- [ ] Presenta producto y material con fidelidad real.
- [ ] El texto demuestra el valor con especificaciones verificables.
- [ ] Evita folclorismo, lujo artificial, superlativos y claims ambientales absolutos.
- [ ] Respeta artes de logo aprobados y su legibilidad.
- [ ] Distingue reglas oficiales de decisiones técnicas inferidas.
- [ ] Verifica contraste, teclado, focus, responsive, rendimiento y ausencia de deformación en imágenes.
