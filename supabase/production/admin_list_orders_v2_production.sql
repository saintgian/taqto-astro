-- NO EJECUTADO CONTRA SUPABASE REMOTO. Preparado localmente para que el
-- propietario del proyecto lo revise y lo corra el mismo (Dashboard de
-- Supabase -> SQL Editor -> pegar TODO este archivo -> Run).
--
-- Dashboard V2: RPC ADICIONAL admin_list_orders_v2, para que la fila de
-- la tabla de Pedidos muestre resumen de productos, primer articulo y
-- unidades sin depender del boton "Ver" ni de una consulta por fila.
-- Migracion INCREMENTAL: admin_list_orders (v1) NO se toca ni se elimina
-- -- sigue intacta y en uso hasta validar v2 en produccion. No toca
-- create_order_v2, catalog_mirror, harden_create_order,
-- harden_permissions ni harden_stock_atomic. No modifica pedidos ni stock:
-- solo lee.
--
-- Misma firma de filtros/paginacion que admin_list_orders (v1): mismos
-- parametros, mismo tope de 100 por pagina, misma busqueda parametrizada,
-- mismo total_count. Se anaden columnas nuevas al final del resultado,
-- todas derivadas de order_items ya real (product_name, wood_name,
-- size_name, dimensions_label, quantity, created_at -- ninguna inventada):
--   first_item_product_name, first_item_variant_label,
--   first_item_quantity, items_extra_count.
--
-- Sin N+1: el "primer articulo" de cada pedido se obtiene con un solo
-- LEFT JOIN LATERAL (una sentencia SQL, no una consulta por fila desde el
-- navegador), igual de eficiente que el items_agg que ya usaba v1 para
-- item_count/unit_count/has_engraving.

create or replace function public.admin_list_orders_v2 (
	p_search text default null,
	p_status public.order_status default null,
	p_payment_method public.payment_method default null,
	p_delivery_method public.delivery_method default null,
	p_date_from date default null,
	p_date_to date default null,
	p_limit integer default 20,
	p_offset integer default 0
) returns table (
	id uuid,
	order_number text,
	created_at timestamptz,
	order_status public.order_status,
	customer_full_name text,
	customer_email text,
	customer_phone text,
	delivery_district text,
	payment_method public.payment_method,
	delivery_method public.delivery_method,
	total numeric,
	item_count bigint,
	unit_count bigint,
	has_engraving boolean,
	first_item_product_name text,
	first_item_variant_label text,
	first_item_quantity integer,
	items_extra_count bigint,
	total_count bigint
) language plpgsql security definer
set
	search_path = '' as $$
declare
	v_limit integer := least(greatest(coalesce(p_limit, 20), 1), 100);
	v_offset integer := greatest(coalesce(p_offset, 0), 0);
	v_search text := nullif(trim(coalesce(p_search, '')), '');
	v_from timestamptz := case
		when p_date_from is null then null
		else (p_date_from::timestamp at time zone 'America/Lima')
	end;
	v_to timestamptz := case
		when p_date_to is null then null
		else ((p_date_to + 1)::timestamp at time zone 'America/Lima')
	end;
begin
	if not public.is_admin() then
		raise exception 'ADMIN_FORBIDDEN';
	end if;

	return query
	with filtered as (
		select o.*
		from public.orders o
		where
			(p_status is null or o.order_status = p_status)
			and (p_payment_method is null or o.payment_method = p_payment_method)
			and (p_delivery_method is null or o.delivery_method = p_delivery_method)
			and (v_from is null or o.created_at >= v_from)
			and (v_to is null or o.created_at < v_to)
			and (
				v_search is null
				or o.order_number ilike '%' || v_search || '%'
				or (o.customer_first_name || ' ' || o.customer_last_name) ilike '%' || v_search || '%'
				or o.customer_email ilike '%' || v_search || '%'
				or o.customer_phone ilike '%' || v_search || '%'
			)
	),
	counted as (
		select count(*) as cnt from filtered
	),
	items_agg as (
		select
			oi.order_id,
			count(*)::bigint as item_count,
			coalesce(sum(oi.quantity), 0)::bigint as unit_count,
			bool_or(oi.engraving_requested) as has_engraving
		from public.order_items oi
		where oi.order_id in (select f.id from filtered f)
		group by oi.order_id
	)
	select
		f.id,
		f.order_number,
		f.created_at,
		f.order_status,
		trim(f.customer_first_name || ' ' || f.customer_last_name) as customer_full_name,
		f.customer_email,
		f.customer_phone,
		f.delivery_district,
		f.payment_method,
		f.delivery_method,
		f.total,
		coalesce(ia.item_count, 0) as item_count,
		coalesce(ia.unit_count, 0) as unit_count,
		coalesce(ia.has_engraving, false) as has_engraving,
		fi.product_name as first_item_product_name,
		nullif(
			trim(
				coalesce(fi.wood_name, '') ||
				case when fi.wood_name is not null and fi.size_name is not null then ' · ' else '' end ||
				coalesce(fi.size_name, '')
			),
			''
		) as first_item_variant_label,
		fi.quantity as first_item_quantity,
		greatest(coalesce(ia.item_count, 0) - 1, 0) as items_extra_count,
		(select cnt from counted) as total_count
	from filtered f
		left join items_agg ia on ia.order_id = f.id
		left join lateral (
			select oi.product_name, oi.wood_name, oi.size_name, oi.quantity
			from public.order_items oi
			where oi.order_id = f.id
			order by oi.created_at asc, oi.id asc
			limit 1
		) fi on true
	order by f.created_at desc
	limit v_limit
	offset v_offset;
end;
$$;

comment on function public.admin_list_orders_v2 (
	text,
	public.order_status,
	public.payment_method,
	public.delivery_method,
	date,
	date,
	integer,
	integer
) is 'Version 2 del listado paginado de pedidos: mismos filtros/paginacion/busqueda que admin_list_orders, mas resumen del primer articulo (nombre, madera+tamano, cantidad) y conteo de articulos adicionales, para mostrar resumen de productos en la fila sin abrir el detalle. admin_list_orders (v1) no se elimina. Exige is_admin().';

revoke
execute on function public.admin_list_orders_v2 (
	text,
	public.order_status,
	public.payment_method,
	public.delivery_method,
	date,
	date,
	integer,
	integer
)
from
	public,
	anon,
	authenticated;

grant
execute on function public.admin_list_orders_v2 (
	text,
	public.order_status,
	public.payment_method,
	public.delivery_method,
	date,
	date,
	integer,
	integer
) to authenticated;

-- ============================================================
-- Fin. No se concede ningun grant nuevo sobre orders ni order_items: el
-- unico camino de lectura sigue siendo RPC security definer. Para
-- verificar, correr a continuacion supabase/verify_admin_list_orders_v2.sql
-- (solo SELECT).
-- ============================================================
