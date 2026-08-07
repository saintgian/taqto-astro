-- NO EJECUTADO CONTRA SUPABASE REMOTO. Preparado localmente para que el
-- propietario del proyecto lo revise y lo corra el mismo (Dashboard de
-- Supabase -> SQL Editor -> pegar TODO este archivo -> Run).
--
-- Fase 3 del panel administrativo (/admin/pedidos/): vistas de solo
-- lectura sobre catalogo/inventario dentro del mismo dashboard. Migracion
-- INCREMENTAL: no recrea nada de admin_orders_dashboard_production.sql ni
-- de admin_update_order_status_production.sql (admin_users, is_admin,
-- admin_orders_metrics, admin_list_orders, admin_get_order_detail,
-- admin_update_order_status siguen intactos). No toca create_order_v2,
-- catalog_mirror, harden_create_order, harden_permissions ni
-- harden_stock_atomic. No modifica stock ni catalogo: solo lo lee.
--
-- Version de PRODUCCION: solo objetos persistentes. Sin BEGIN/ROLLBACK,
-- sin tablas temporales, sin filas de prueba, sin UUID ficticios. La
-- verificacion vive en un archivo separado de solo lectura:
-- verify_admin_inventory_dashboard.sql
--
-- Esquema real usado, tal como quedo definido en catalog_mirror.sql
-- (ninguna columna inventada aqui):
--   catalog_products: id, sanity_id, slug, title, product_mode,
--     sale_start, sale_end, active, synced_at, created_at
--   catalog_variants: id, product_id, sanity_product_id, sku,
--     wood_title, wood_slug, size_title, size_slug, dimensions_label,
--     currency, price, sale_price, stock_quantity, active, synced_at,
--     created_at
--
-- El navegador nunca lee catalog_products/catalog_variants directamente:
-- ambas tablas ya tienen RLS activo sin policies y sin grants a
-- anon/authenticated (ver catalog_mirror.sql). Estos dos RPC son la
-- unica via de lectura para el panel, igual que en pedidos.
--
-- Precio efectivo: replica en SQL la misma regla que ya usa el sitio
-- publico en src/lib/productPricing.ts (getVisiblePrice/isSaleActive) --
-- sale_price de la variante cuando la ventana de oferta del producto
-- (catalog_products.sale_start/sale_end) esta vigente ahora mismo,
-- price en cualquier otro caso. No se inventa un campo nuevo: se deriva
-- de los mismos que ya usa el checkout.
--
-- Umbral de stock bajo: parametro con default 5 (no hay una regla
-- comercial ya definida en el proyecto), facil de cambiar en cada
-- llamada via p_low_stock_threshold sin tocar la funcion.

-- ============================================================
-- 1) RPC: metricas de catalogo e inventario
-- ============================================================

create or replace function public.admin_inventory_metrics (p_low_stock_threshold integer default 5) returns table (
	total_products bigint,
	active_products bigint,
	total_variants bigint,
	total_units_in_stock bigint,
	low_stock_variants bigint,
	out_of_stock_variants bigint
) language plpgsql security definer
set
	search_path = '' as $$
declare
	v_threshold integer := greatest(coalesce(p_low_stock_threshold, 5), 0);
begin
	if not public.is_admin() then
		raise exception 'ADMIN_FORBIDDEN';
	end if;

	return query
	select
		(select count(*) from public.catalog_products)::bigint as total_products,
		(select count(*) from public.catalog_products cp where cp.active = true)::bigint as active_products,
		(select count(*) from public.catalog_variants)::bigint as total_variants,
		-- Unidades vendibles reales: solo variantes activas de productos
		-- activos. Una variante despublicada no es stock disponible para
		-- vender, aunque la fila conserve un numero en stock_quantity.
		(
			select coalesce(sum(cv.stock_quantity), 0)
			from public.catalog_variants cv
				join public.catalog_products cp on cp.id = cv.product_id
			where cv.active = true
				and cp.active = true
		)::bigint as total_units_in_stock,
		(
			select count(*)
			from public.catalog_variants cv
				join public.catalog_products cp on cp.id = cv.product_id
			where cv.active = true
				and cp.active = true
				and cv.stock_quantity > 0
				and cv.stock_quantity <= v_threshold
		)::bigint as low_stock_variants,
		(
			select count(*)
			from public.catalog_variants cv
				join public.catalog_products cp on cp.id = cv.product_id
			where cv.active = true
				and cp.active = true
				and cv.stock_quantity = 0
		)::bigint as out_of_stock_variants;
end;
$$;

comment on function public.admin_inventory_metrics (integer) is 'Metricas de solo lectura de catalogo/inventario para el panel admin: totales de productos/variantes y unidades/stock bajo/sin stock, estas tres ultimas restringidas a variantes activas de productos activos. Umbral de stock bajo parametrizable (default 5). Exige is_admin().';

revoke
execute on function public.admin_inventory_metrics (integer)
from
	public,
	anon,
	authenticated;

grant
execute on function public.admin_inventory_metrics (integer) to authenticated;

-- ============================================================
-- 2) RPC: listado de inventario (una fila por variante)
-- ============================================================

create or replace function public.admin_list_inventory (
	p_search text default null,
	p_stock_filter text default null, -- 'available' | 'low' | 'out' | null (todos)
	p_active_only boolean default null, -- true = solo productos activos, false = solo inactivos, null = todos
	p_low_stock_threshold integer default 5,
	p_limit integer default 50,
	p_offset integer default 0
) returns table (
	variant_id uuid,
	product_id uuid,
	product_title text,
	product_slug text,
	product_active boolean,
	wood_title text,
	size_title text,
	dimensions_label text,
	sku text,
	variant_active boolean,
	stock_quantity integer,
	price numeric,
	sale_price numeric,
	effective_price numeric,
	stock_status text,
	total_count bigint
) language plpgsql security definer
set
	search_path = '' as $$
declare
	-- Tope duro de 100 por pagina, igual que admin_list_orders.
	v_limit integer := least(greatest(coalesce(p_limit, 50), 1), 100);
	v_offset integer := greatest(coalesce(p_offset, 0), 0);
	v_threshold integer := greatest(coalesce(p_low_stock_threshold, 5), 0);
	-- nullif+trim: busqueda vacia o solo espacios se trata como "sin
	-- busqueda", no como "cero resultados".
	v_search text := nullif(trim(coalesce(p_search, '')), '');
	-- Solo estos tres valores son un filtro real; cualquier otra cosa
	-- (incluido null) se trata como "todos", sin lanzar error.
	v_stock_filter text := nullif(trim(coalesce(p_stock_filter, '')), '');
begin
	if not public.is_admin() then
		raise exception 'ADMIN_FORBIDDEN';
	end if;

	if v_stock_filter is not null and v_stock_filter not in ('available', 'low', 'out') then
		v_stock_filter := null;
	end if;

	return query
	with base as (
		select
			cv.id as variant_id,
			cp.id as product_id,
			cp.title as product_title,
			cp.slug as product_slug,
			cp.active as product_active,
			cv.wood_title,
			cv.size_title,
			cv.dimensions_label,
			cv.sku,
			cv.active as variant_active,
			cv.stock_quantity,
			cv.price,
			cv.sale_price,
			-- Misma regla que src/lib/productPricing.ts: sale_price solo
			-- cuando la ventana de oferta del producto esta vigente ahora.
			case
				when cv.sale_price is not null
					and (cp.sale_start is null or now() >= cp.sale_start)
					and (cp.sale_end is null or now() <= cp.sale_end)
				then cv.sale_price
				else cv.price
			end as effective_price,
			case
				when cv.stock_quantity = 0 then 'out'
				when cv.stock_quantity <= v_threshold then 'low'
				else 'available'
			end as stock_status
		from public.catalog_variants cv
			join public.catalog_products cp on cp.id = cv.product_id
		where
			(p_active_only is null or cp.active = p_active_only)
			and (
				v_search is null
				or cp.title ilike '%' || v_search || '%'
				or cv.sku ilike '%' || v_search || '%'
				or cv.wood_title ilike '%' || v_search || '%'
				or cv.size_title ilike '%' || v_search || '%'
			)
	),
	filtered as (
		select *
		from base b
		where v_stock_filter is null or b.stock_status = v_stock_filter
	),
	counted as (
		select count(*) as cnt from filtered
	)
	select
		f.variant_id,
		f.product_id,
		f.product_title,
		f.product_slug,
		f.product_active,
		f.wood_title,
		f.size_title,
		f.dimensions_label,
		f.sku,
		f.variant_active,
		f.stock_quantity,
		f.price,
		f.sale_price,
		f.effective_price,
		f.stock_status,
		(select cnt from counted) as total_count
	from filtered f
	order by
		case f.stock_status
			when 'out' then 0
			when 'low' then 1
			else 2
		end,
		f.product_title asc,
		f.sku asc
	limit v_limit
	offset v_offset;
end;
$$;

comment on function public.admin_list_inventory (
	text,
	text,
	boolean,
	integer,
	integer,
	integer
) is 'Listado paginado de inventario (una fila por variante) para el panel admin: producto, variante, SKU, estado activo, stock y precio efectivo. Busqueda parametrizada por titulo/SKU/madera/tamano. Filtro opcional de estado de stock (available/low/out) y de producto activo/inactivo. Maximo 100 por pagina. Exige is_admin().';

revoke
execute on function public.admin_list_inventory (
	text,
	text,
	boolean,
	integer,
	integer,
	integer
)
from
	public,
	anon,
	authenticated;

grant
execute on function public.admin_list_inventory (
	text,
	text,
	boolean,
	integer,
	integer,
	integer
) to authenticated;

-- ============================================================
-- Fin. No se concede ningun grant nuevo sobre catalog_products ni sobre
-- catalog_variants: el unico camino de lectura sigue siendo estos dos
-- RPC. Ninguno modifica stock, precio ni catalogo. Para verificar, correr
-- a continuacion supabase/verify_admin_inventory_dashboard.sql (solo
-- SELECT).
-- ============================================================
