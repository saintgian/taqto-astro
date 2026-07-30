# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

Primary audience: individual consumers in Peru (Lima-based, national shipping) buying wood and leather objects for home, kitchen, grill ("parrilla"), office use, or as gifts — often seeking a personalized, laser-engraved piece for a specific person or occasion.

Secondary audience: businesses seeking corporate gifts or wholesale purchasing, served through dedicated pages under "Empresas." The site should be optimized for the individual-consumer path first; the business path is a supporting channel, not the primary design target.

## Product Purpose

TAQTO sells contemporary wood (and leather) objects — for parrilla, kitchen/table, office, home, and gifting — manufactured with precision and offered with free laser-engraved personalization. Success is a visitor understanding a piece, trusting its quality and origin story, and completing an order through the site's cart plus WhatsApp/Yape handoff.

## Positioning

TAQTO differentiates by combining more than 20 years of family workshop tradition in wood and leather with contemporary, precision design, selected Peruvian materials, and free laser personalization. Do not claim sustainability credentials, fully in-house manufacturing, or manufacturing-speed advantages — these are not documented.

## Operating Context

- Content and catalog (products, categories, subcategories, wood types, home campaign banner) are managed in Sanity CMS; the site degrades gracefully to fallback content when Sanity is unavailable at build time.
- Cart state lives in browser `localStorage` (`taqto_cart`), independent of any backend — it must keep working even without Supabase environment variables configured (see cart.ts and its GitHub Pages fallback history).
- Checkout is a deliberate, durable design choice: the cart hands off to WhatsApp and Yape (a Peruvian mobile payment app) for manual order confirmation, not an integrated payment gateway. This is not a stopgap to hide — the experience should read as trustworthy, clear, and personally accompanied. Keep the architecture open to a future payment-gateway integration, but do not design or build one now.
- Deployed as a static build to GitHub Pages under a `/taqto-astro/` base path (see astro.config.mjs).
- Confirmed wood species used across the catalog: Huayruro, Pumaquiro, Shihuahuaco, Cachimbo, Teca.
- Flat shipping fee (S/10) applies to both Lima delivery and provincial agency pickup.
- All site copy and customer-facing communication is in Spanish, for a Peru-based audience; no multi-language support exists or is implied.

## Capabilities and Constraints

- Product browsing by category/subcategory, product detail pages with wood/size options and custom engraving text input, cart, and a dedicated "Empresas" section (corporate gifts, wholesale) with its own static pages.
- Personalization (free laser engraving) is a first-class, recurring product mechanic — not an upsell — and should be treated as core to the buying decision, not a footnote.
- No integrated payment gateway exists or is planned for the current phase; do not design checkout flows that assume one.
- No user accounts or order-history system is evident; cart/session state is local to the browser.

## Brand Commitments

- Name: TAQTO. Tagline: "Diseño con alma de madera." Also described as "Neo-Artesanía Peruana de Precisión."
- Voice: warm, workshop-rooted, precise — emphasizes family tradition (grandfather's workshop, 20+ years), honest materiality (wood/leather grain and tone vary naturally), and closeness with the customer, without leaning on national stereotypes or ornamental "Peruvian-ness."
- "Diseñado y hecho en Lima, Perú" is a standing claim used across marketing pages.
- Brand assets (logotipo, imagotipo, isotipo, isologo in multiple colorways) exist under `public/brand/`.

## Evidence on Hand

- Real client project photos exist for the homepage's customer-proof section (`public/images/home/clientes/proyecto-01.webp` etc.) — do not invent testimonials, review quotes, or customer names beyond what's provided.
- Brand mark files exist in several colorways under `public/brand/` (logotipo, imagotipo, isotipo, isologo).
- No numeric business metrics, press mentions, or third-party certifications are on hand — do not fabricate pricing benchmarks, awards, or sustainability certifications.

## Product Principles

1. The individual buyer's gifting/home-use journey leads; the business/wholesale path supports but doesn't compete for primary attention.
2. Free laser personalization is core to the offer and should be visible and easy to act on, not buried.
3. Checkout stays a warm, accompanied WhatsApp/Yape handoff — clarity and trust matter more than gateway automation right now, and nothing should be built that assumes a payment gateway.
4. Material honesty (natural variation in wood/leather) and workshop-heritage credibility are claims the site is allowed to make; sustainability, speed, and full in-house manufacturing claims are not, absent documentation.
5. Content resilience: the site must degrade gracefully when Sanity or Supabase are unavailable, since it ships as a static GitHub Pages build.
