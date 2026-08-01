-- NO EJECUTADO CONTRA SUPABASE REMOTO. Preparado localmente. Orden de
-- aplicacion (Dashboard de Supabase -> SQL Editor -> pegar -> Run):
--   1) supabase/catalog_mirror.sql        (este archivo)
--   2) supabase/harden_create_order.sql
--   3) supabase/harden_permissions.sql
--
-- Que es esto: un espejo minimo de Sanity dentro de Supabase para que el
-- RPC de creacion de pedidos tenga una fuente de precio/stock que el
-- navegador no puede manipular. No convierte Supabase en un CMS: solo
-- guarda lo indispensable para validar un pedido (precio vigente, stock
-- vigente, si el producto/variante sigue activo) y el identificador
-- estable de Sanity para poder re-sincronizar despues.
--
-- Se llena con `npm run sync:catalog` (scripts/sync-catalog.mjs), que no
-- se ejecuta en esta tarea. Hasta que esa sincronizacion corra al menos
-- una vez, estas tablas estan vacias y el RPC endurecido (que solo
-- vende lo que encuentra aqui) rechazara todos los pedidos: es
-- comportamiento esperado, no un bug, y debe comunicarse al propietario
-- como parte del orden de despliegue.

create table if not exists public.catalog_products (
	id uuid primary key default gen_random_uuid(),
	sanity_id text not null,
	slug text not null,
	title text not null,
	product_mode text not null check (
		product_mode in ('unique', 'wood', 'size', 'woodSize')
	),
	-- Ventana de oferta a nivel de producto (asi vive en el schema de
	-- Sanity: `saleStart`/`saleEnd` estan en el documento de producto,
	-- no por variante). Nulo = sin fecha limite en ese extremo.
	sale_start timestamptz,
	sale_end timestamptz,
	-- El producto sigue existiendo en Sanity pero ya no esta publicado
	-- (`active == true` dejo de cumplirse) o fue despublicado/borrado:
	-- se marca inactivo, nunca se borra la fila.
	active boolean not null default true,
	synced_at timestamptz not null default now(),
	created_at timestamptz not null default now(),
	unique (sanity_id)
);

create table if not exists public.catalog_variants (
	id uuid primary key default gen_random_uuid(),
	product_id uuid not null references public.catalog_products (id) on delete cascade,
	-- Duplicado desde catalog_products a proposito: el RPC busca un item
	-- del pedido por (sanity_product_id, sku) sin necesitar un join, con
	-- un unique index dedicado para esa consulta.
	sanity_product_id text not null,
	sku text not null,
	wood_title text,
	wood_slug text,
	size_title text,
	size_slug text,
	dimensions_label text,
	-- Tienda de una sola moneda: se deja explicito en vez de asumido.
	currency text not null default 'PEN' check (currency = 'PEN'),
	price numeric(10, 2) not null check (price >= 0),
	sale_price numeric(10, 2) check (
		sale_price is null
		or sale_price >= 0
	),
	stock_quantity integer not null check (stock_quantity >= 0),
	active boolean not null default true,
	synced_at timestamptz not null default now(),
	created_at timestamptz not null default now(),
	unique (sanity_product_id, sku)
);

create index if not exists catalog_products_sanity_id_idx on public.catalog_products (sanity_id);

create index if not exists catalog_variants_lookup_idx on public.catalog_variants (sanity_product_id, sku)
where
	active = true;

-- RLS activo y sin policies: nadie (ni anon ni authenticated) puede
-- leer o escribir estas tablas directamente. El unico camino de lectura
-- es el RPC `create_order_v2`, que es `security definer` y por lo tanto
-- no depende de RLS/grants de quien lo llama. La escritura solo la hace
-- el script de sincronizacion con la service role key (que ignora RLS).
alter table public.catalog_products enable row level security;

alter table public.catalog_variants enable row level security;

revoke all on public.catalog_products
from
	anon,
	authenticated;

revoke all on public.catalog_variants
from
	anon,
	authenticated;

comment on table public.catalog_products is 'Espejo minimo de productos de Sanity, usado solo para validar pedidos en create_order_v2. Fuente de verdad sigue siendo Sanity; se actualiza via scripts/sync-catalog.mjs.';

comment on table public.catalog_variants is 'Espejo minimo de variantes/producto-unico de Sanity (precio y stock vigentes). Clave estable: (sanity_product_id, sku).';
