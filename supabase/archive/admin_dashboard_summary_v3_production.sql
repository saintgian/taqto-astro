-- NO EJECUTADO CONTRA SUPABASE REMOTO. Preparado localmente para que el
-- propietario del proyecto lo revise y lo corra el mismo (Dashboard de
-- Supabase -> SQL Editor -> pegar TODO este archivo -> Run).
--
-- Dashboard V3: corrige el Resumen del panel admin (/admin/pedidos/).
-- Migracion INCREMENTAL: no recrea admin_users, is_admin, admin_list_orders,
-- admin_get_order_detail, admin_update_order_status, admin_inventory_metrics
-- ni admin_list_inventory. No toca create_order_v2, catalog_mirror,
-- harden_create_order, harden_permissions ni harden_stock_atomic. No
-- modifica pedidos, pagos, catalogo ni stock: solo lee.
--
-- ============================================================
-- 1) CAUSA de "Ventas confirmadas" en S/ 0.00
-- ============================================================
--
-- admin_orders_metrics() (admin_orders_dashboard_production.sql, version
-- desplegada hoy) suma o.total solo cuando o.payment_status = 'verified'.
-- payment_status es una columna real de public.orders, pero ningun camino
-- de escritura del proyecto la fija jamas (harden_create_order.sql nunca
-- la incluye en su INSERT; admin_update_order_status_production.sql solo
-- toca order_status). Se queda por tanto siempre en su DEFAULT de tabla,
-- para todo pedido, y la comparacion es verdadera para cero filas: de ahi
-- el S/ 0.00 constante. Este mismo diagnostico y arreglo ya estaba en
-- admin_dashboard_metrics_v2_production.sql; se repite aqui (create or
-- replace es idempotente) para que este archivo sea autosuficiente.
--
-- ============================================================
-- 2) CAUSA de "Algunos datos del resumen no se pudieron cargar"
-- ============================================================
--
-- El Resumen disparaba 5 llamadas RPC independientes en paralelo
-- (admin_orders_metrics, admin_inventory_metrics, admin_list_orders,
-- admin_list_inventory, admin_dashboard_analytics) y mostraba el aviso
-- generico en cuanto UNA fallara -- incluida admin_dashboard_analytics,
-- que nunca se aplico contra la base remota (solo existe en el archivo
-- v2, tampoco ejecutado). Con esa funcion inexistente, el Resumen queda
-- SIEMPRE con el aviso activo, aunque dinero/pedidos/stock si carguen.
--
-- Arreglo: una sola funcion admin_dashboard_summary_v3() reemplaza a
-- admin_orders_metrics + admin_inventory_metrics + admin_dashboard_analytics
-- para las metricas y graficos del Resumen (recientes/stock critico
-- siguen usando admin_list_orders / admin_list_inventory, que ya existen
-- y funcionan). El frontend pasa de 5 llamadas a 3, y ya no depende de
-- una funcion nunca desplegada.
--
-- ============================================================
-- 3) Criterio de "Valor de pedidos activos" (metrica nueva)
-- ============================================================
--
-- Suma orders.total de todo pedido cuyo order_status no sea 'cancelled'
-- (los 10 estados restantes del flujo real, incluido 'received'). Una
-- sola fila = un pedido = un total: sin joins a order_items ni
-- order_payments, cero riesgo de duplicar importes.
--
-- ============================================================
-- 4) Criterio de "Ventas confirmadas" (idem admin_orders_metrics)
-- ============================================================
--
-- Un pedido cuenta una sola vez como venta confirmada cuando:
--   a) payment_method <> 'cash_on_delivery' y order_status ya alcanzo o
--      supero 'payment_verified' en el flujo real; o
--   b) payment_method = 'cash_on_delivery' y order_status = 'delivered'.
-- 'cancelled', 'received' y 'payment_pending' nunca cuentan. No se usa
-- order_payments: ningun archivo de este repositorio inserta ni
-- actualiza filas ahi (grep de "order_payments" en todo el proyecto solo
-- la encuentra en comentarios), asi que sus valores no se pueden
-- verificar; usarla seria tan arriesgado como inventar un estado.

-- ============================================================
-- 5) RPC: admin_orders_metrics (reemplaza la version con el bug de
--    payment_status). Se mantiene su firma y forma de tabla: la usan
--    tal cual la pestana Pedidos (loadMetrics) y el propio
--    admin_dashboard_summary_v3 de abajo, sin cambios de contrato.
-- ============================================================

create or replace function public.admin_orders_metrics () returns table (
	total_orders bigint,
	orders_today bigint,
	orders_by_status jsonb,
	confirmed_sales_total numeric,
	confirmed_sales_count bigint
) language plpgsql security definer
set
	search_path = '' as $$
begin
	if not public.is_admin() then
		raise exception 'ADMIN_FORBIDDEN';
	end if;

	return query
	select
		(select count(*) from public.orders)::bigint as total_orders,
		(
			select count(*)
			from public.orders o
			where (o.created_at at time zone 'America/Lima')::date
				= (now() at time zone 'America/Lima')::date
		)::bigint as orders_today,
		(
			select coalesce(jsonb_object_agg(s.status_label::text, s.cnt), '{}'::jsonb)
			from (
				select os.status_label, count(o.id) as cnt
				from unnest(enum_range(null::public.order_status)) as os (status_label)
					left join public.orders o on o.order_status = os.status_label
				group by os.status_label
			) s
		) as orders_by_status,
		(
			select coalesce(sum(o.total), 0)
			from public.orders o
			where
				(
					o.payment_method <> 'cash_on_delivery'::public.payment_method
					and o.order_status = any (
						array['payment_verified', 'mockup_pending', 'mockup_sent', 'mockup_approved', 'in_production', 'ready_to_ship', 'shipped', 'delivered']::public.order_status[]
					)
				)
				or (
					o.payment_method = 'cash_on_delivery'::public.payment_method
					and o.order_status = 'delivered'::public.order_status
				)
		) as confirmed_sales_total,
		(
			select count(*)
			from public.orders o
			where
				(
					o.payment_method <> 'cash_on_delivery'::public.payment_method
					and o.order_status = any (
						array['payment_verified', 'mockup_pending', 'mockup_sent', 'mockup_approved', 'in_production', 'ready_to_ship', 'shipped', 'delivered']::public.order_status[]
					)
				)
				or (
					o.payment_method = 'cash_on_delivery'::public.payment_method
					and o.order_status = 'delivered'::public.order_status
				)
		)::bigint as confirmed_sales_count;
end;
$$;

comment on function public.admin_orders_metrics () is 'Metricas de solo lectura para el panel admin: total, pedidos de hoy (America/Lima), conteo por order_status y ventas confirmadas. Ventas confirmadas = pedidos no-COD con order_status >= payment_verified en el flujo real, mas pedidos COD ya delivered; cancelled nunca cuenta. payment_status se ignora: ningun camino de escritura del repo la fija jamas. Exige is_admin().';

revoke
execute on function public.admin_orders_metrics ()
from
	public,
	anon,
	authenticated;

grant
execute on function public.admin_orders_metrics () to authenticated;

-- ============================================================
-- 6) RPC: admin_dashboard_summary_v3 -- unica llamada para las
--    tarjetas y graficos del Resumen.
-- ============================================================

create or replace function public.admin_dashboard_summary_v3 (p_low_stock_threshold integer default 5) returns jsonb language plpgsql security definer
set
	search_path = '' as $$
declare
	v_threshold integer := greatest(coalesce(p_low_stock_threshold, 5), 0);
	v_active_value numeric;
	v_active_count bigint;
	v_confirmed_value numeric;
	v_confirmed_count bigint;
	v_orders_today bigint;
	v_total_orders bigint;
	v_by_status jsonb;
	v_last_7_days jsonb;
	v_inventory jsonb;
begin
	if not public.is_admin() then
		raise exception 'ADMIN_FORBIDDEN';
	end if;

	-- Pedidos activos: todo pedido no cancelado, sin importar su etapa de
	-- pago (incluye 'received'). Un pedido = una fila = un total.
	select coalesce(sum(o.total), 0), count(*)
	into v_active_value, v_active_count
	from public.orders o
	where o.order_status <> 'cancelled'::public.order_status;

	-- Ventas confirmadas: mismo criterio que admin_orders_metrics de
	-- arriba (no-COD >= payment_verified, o COD ya delivered).
	select coalesce(sum(o.total), 0), count(*)
	into v_confirmed_value, v_confirmed_count
	from public.orders o
	where
		(
			o.payment_method <> 'cash_on_delivery'::public.payment_method
			and o.order_status = any (
				array['payment_verified', 'mockup_pending', 'mockup_sent', 'mockup_approved', 'in_production', 'ready_to_ship', 'shipped', 'delivered']::public.order_status[]
			)
		)
		or (
			o.payment_method = 'cash_on_delivery'::public.payment_method
			and o.order_status = 'delivered'::public.order_status
		);

	select count(*)
	into v_orders_today
	from public.orders o
	where (o.created_at at time zone 'America/Lima')::date
		= (now() at time zone 'America/Lima')::date;

	select count(*) into v_total_orders from public.orders;

	select coalesce(jsonb_object_agg(s.status_label::text, s.cnt), '{}'::jsonb)
	into v_by_status
	from (
		select os.status_label, count(o.id) as cnt
		from unnest(enum_range(null::public.order_status)) as os (status_label)
			left join public.orders o on o.order_status = os.status_label
		group by os.status_label
	) s;

	-- Serie de 7 dias (America/Lima), hoy incluido, sin huecos: valor y
	-- cantidad de pedidos ACTIVOS (no cancelados) creados cada dia --
	-- no solo ventas confirmadas, para que 'received' tambien se vea en
	-- el grafico del Resumen.
	select coalesce(jsonb_agg(d order by d->>'date'), '[]'::jsonb)
	into v_last_7_days
	from (
		select jsonb_build_object(
			'date', to_char(day_series.day, 'YYYY-MM-DD'),
			'value', coalesce(sum(o.total), 0),
			'count', coalesce(count(o.id), 0)
		) as d
		from generate_series(
			(now() at time zone 'America/Lima')::date - interval '6 days',
			(now() at time zone 'America/Lima')::date,
			interval '1 day'
		) as day_series (day)
			left join public.orders o
				on (o.created_at at time zone 'America/Lima')::date = day_series.day::date
				and o.order_status <> 'cancelled'::public.order_status
		group by day_series.day
	) days;

	-- Inventario: mismo alcance y umbral que admin_inventory_metrics
	-- (variantes activas de productos activos), duplicado aqui en linea
	-- para que este RPC no dependa de que admin_inventory_dashboard_
	-- production.sql ya este aplicado en la base remota.
	select jsonb_build_object(
		'total_products', (select count(*) from public.catalog_products),
		'active_products', (select count(*) from public.catalog_products cp where cp.active = true),
		'total_variants', (select count(*) from public.catalog_variants),
		'total_units_in_stock', (
			select coalesce(sum(cv.stock_quantity), 0)
			from public.catalog_variants cv
				join public.catalog_products cp on cp.id = cv.product_id
			where cv.active = true and cp.active = true
		),
		'low_stock_variants', (
			select count(*)
			from public.catalog_variants cv
				join public.catalog_products cp on cp.id = cv.product_id
			where cv.active = true and cp.active = true
				and cv.stock_quantity > 0 and cv.stock_quantity <= v_threshold
		),
		'out_of_stock_variants', (
			select count(*)
			from public.catalog_variants cv
				join public.catalog_products cp on cp.id = cv.product_id
			where cv.active = true and cp.active = true
				and cv.stock_quantity = 0
		)
	)
	into v_inventory;

	return jsonb_build_object(
		'active_orders_value', v_active_value,
		'active_orders_count', v_active_count,
		'confirmed_sales_value', v_confirmed_value,
		'confirmed_sales_count', v_confirmed_count,
		'orders_today', v_orders_today,
		'total_orders', v_total_orders,
		'orders_by_status', v_by_status,
		'active_orders_last_7_days', v_last_7_days,
		'inventory', v_inventory
	);
end;
$$;

comment on function public.admin_dashboard_summary_v3 (integer) is 'Resumen unico de solo lectura para el panel admin (vista Resumen): valor/conteo de pedidos activos (no cancelados, incluye received), ventas confirmadas (no-COD >= payment_verified o COD delivered), pedidos de hoy, total de pedidos, conteo por order_status (11 claves), serie de pedidos activos de los ultimos 7 dias (America/Lima, sin huecos) e inventario (total/activos/variantes/unidades/stock bajo/sin stock, variantes activas de productos activos). Reemplaza para el Resumen a admin_orders_metrics + admin_inventory_metrics + admin_dashboard_analytics (siguen existiendo para Pedidos/Inventario). Exige is_admin().';

revoke
execute on function public.admin_dashboard_summary_v3 (integer)
from
	public,
	anon,
	authenticated;

grant
execute on function public.admin_dashboard_summary_v3 (integer) to authenticated;

-- ============================================================
-- Fin. No se concede ningun grant nuevo sobre orders, order_items,
-- catalog_products ni catalog_variants: el unico camino de lectura sigue
-- siendo RPC security definer. Para verificar, correr a continuacion
-- supabase/verify_admin_dashboard_summary_v3.sql (solo SELECT).
-- ============================================================
