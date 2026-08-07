-- NO EJECUTADO CONTRA SUPABASE REMOTO. Preparado localmente para que el
-- propietario del proyecto lo revise y lo corra el mismo (Dashboard de
-- Supabase -> SQL Editor -> pegar TODO este archivo -> Run).
--
-- Dashboard V4: corrige el Resumen de /admin/pedidos/#resumen, que
-- muestra guiones en las 4 tarjetas y los avisos "No se pudieron cargar
-- las metricas del resumen", "Sin datos de pedidos por estado" y "No se
-- pudo consultar el inventario".
--
-- ============================================================
-- CAUSA EXACTA DEL FALLO ACTUAL
-- ============================================================
--
-- admin_dashboard_summary_v3_production.sql y
-- admin_inventory_dashboard_production.sql existen como archivos en este
-- repositorio pero NUNCA se ejecutaron contra la base remota de Supabase
-- (ambos siguen sin comitear, y ninguna migracion los aplico). Por eso:
--   - admin_dashboard_summary_v3(integer) no existe en Postgres remoto:
--     la llamada del frontend devuelve un error de funcion inexistente,
--     summaryRes falla, y las 4 tarjetas (que dependen todas del mismo
--     RPC) caen a "-" junto con "Pedidos por estado" (orders_by_status
--     viene en el mismo payload).
--   - admin_list_inventory(...) tampoco existe en Postgres remoto: la
--     tarjeta "Stock que requiere atencion" cae a su propio mensaje de
--     reemplazo ("No se pudo consultar el inventario").
--   - admin_list_orders SI esta aplicado (fase 1, ya en produccion), por
--     eso "Pedidos recientes" carga con normalidad: confirma que Auth,
--     sesion y is_admin() funcionan.
--
-- No hay ningun desajuste de nombres de columnas ni de firma entre v3 y
-- el frontend: la interfaz DashboardSummaryV3 de pedidos.astro coincide
-- exactamente con las claves que devolvia jsonb_build_object en v3. El
-- unico problema real es que el archivo nunca se aplico.
--
-- v4 no se limita a reaplicar v3: ademas aplana el contrato (sin el
-- objeto anidado "inventory"), usa nombres de clave mas explicitos
-- (orders_total en vez de total_orders, status_counts como arreglo en
-- vez de objeto, daily_active_orders con amount/orders_count), y hace
-- que un fallo de inventario no apague las metricas de pedidos: nunca
-- vuelve a depender de que TODOS los subsistemas esten sanos para
-- mostrar una sola cifra.
--
-- Migracion INCREMENTAL: no recrea admin_users, is_admin, admin_list_orders,
-- admin_get_order_detail, admin_update_order_status, admin_orders_metrics,
-- admin_list_inventory ni admin_inventory_metrics (siguen intactos y en
-- uso por la pestana Pedidos / Inventario). No toca create_order_v2,
-- catalog_mirror, harden_create_order, harden_permissions ni
-- harden_stock_atomic. No modifica pedidos, pagos, catalogo ni stock:
-- solo lee. admin_dashboard_summary_v3(integer) se deja intacta (no se
-- borra) por si algo mas la referencia; el frontend deja de llamarla.
--
-- ============================================================
-- Esquema real usado (mismo que admin_orders_dashboard_production.sql y
-- admin_inventory_dashboard_production.sql; nada inventado aqui):
--   orders: id, order_number, created_at, order_status, payment_method,
--     total (numeric), entre otras.
--   order_status (enum, 11 valores): received, payment_pending,
--     payment_verified, mockup_pending, mockup_sent, mockup_approved,
--     in_production, ready_to_ship, shipped, delivered, cancelled.
--   payment_method (enum, 5 valores): yape, plin, bank_transfer, card,
--     cash_on_delivery.
--   order_payments: id, order_id, payment_status, entre otras. Ningun
--     camino de escritura del repositorio inserta filas aqui todavia
--     (grep de "order_payments" en todo el proyecto solo la encuentra en
--     comentarios/DDL de permisos): el criterio de abajo la consulta de
--     todas formas (EXISTS, sin duplicar), pero en la practica hoy no
--     aporta filas. Limitacion documentada, no oculta.
--   catalog_products: id, active.
--   catalog_variants: id, product_id, active, stock_quantity.
-- ============================================================

-- ============================================================
-- RPC: admin_dashboard_summary_v4 -- unica llamada para las tarjetas y
-- graficos del Resumen. Sin parametros: umbral de stock bajo fijo en 5
-- (mismo default que ya usaba el dashboard).
-- ============================================================

create or replace function public.admin_dashboard_summary_v4 () returns jsonb language plpgsql security definer
set
	search_path = '' as $$
declare
	v_threshold constant integer := 5;
	v_active_value numeric;
	v_active_count bigint;
	v_confirmed_value numeric;
	v_confirmed_count bigint;
	v_orders_today bigint;
	v_orders_total bigint;
	v_status_counts jsonb;
	v_daily jsonb;
	v_inventory_total_products bigint := 0;
	v_inventory_total_variants bigint := 0;
	v_inventory_total_units bigint := 0;
	v_inventory_low_stock bigint := 0;
	v_inventory_out_of_stock bigint := 0;
	v_inventory_available bigint := 0;
	v_inventory_error text := null;
begin
	if not public.is_admin() then
		raise exception 'ADMIN_FORBIDDEN';
	end if;

	-- Valor de pedidos activos: todo pedido no cancelado, un pedido = una
	-- fila = un total. Sin joins a order_items ni order_payments: cero
	-- riesgo de duplicar importes.
	select coalesce(sum(o.total), 0), count(*)
	into v_active_value, v_active_count
	from public.orders o
	where o.order_status <> 'cancelled'::public.order_status;

	-- Ventas confirmadas: un pedido cuenta una sola vez cuando su estado
	-- real es payment_verified, o delivered, o existe evidencia real de
	-- pago aprobado/verificado en order_payments. EXISTS evita duplicar
	-- por multiples filas de pago. cancelled nunca cuenta (ya excluido:
	-- ninguno de los tres criterios puede ser cierto a la vez que
	-- cancelled, pero se deja explicito por claridad y por seguridad ante
	-- cambios futuros del enum).
	select coalesce(sum(o.total), 0), count(*)
	into v_confirmed_value, v_confirmed_count
	from public.orders o
	where o.order_status <> 'cancelled'::public.order_status
		and (
			o.order_status = 'payment_verified'::public.order_status
			or o.order_status = 'delivered'::public.order_status
			or exists (
				select 1
				from public.order_payments op
				where op.order_id = o.id
					and op.payment_status = 'verified'::public.payment_status
			)
		);

	select count(*)
	into v_orders_today
	from public.orders o
	where (o.created_at at time zone 'America/Lima')::date
		= (now() at time zone 'America/Lima')::date;

	select count(*) into v_orders_total from public.orders;

	-- Pedidos por estado: arreglo con las 11 claves reales del enum,
	-- incluidas las que tengan cero pedidos.
	select coalesce(jsonb_agg(jsonb_build_object('status', s.status_label::text, 'count', s.cnt) order by s.status_label::text), '[]'::jsonb)
	into v_status_counts
	from (
		select os.status_label, count(o.id) as cnt
		from unnest(enum_range(null::public.order_status)) as os (status_label)
			left join public.orders o on o.order_status = os.status_label
		group by os.status_label
	) s;

	-- Ultimos 7 dias (America/Lima), hoy incluido, sin huecos: monto y
	-- cantidad de pedidos ACTIVOS (no cancelados) creados cada dia.
	select coalesce(jsonb_agg(d order by d->>'date'), '[]'::jsonb)
	into v_daily
	from (
		select jsonb_build_object(
			'date', to_char(day_series.day, 'YYYY-MM-DD'),
			'amount', coalesce(sum(o.total), 0),
			'orders_count', coalesce(count(o.id), 0)
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

	-- Inventario: aislado en su propio bloque. Si catalog_products o
	-- catalog_variants no existen o cambian de forma, el resto del
	-- resumen (pedidos/dinero/estados/7 dias) igual se devuelve: solo el
	-- panel de inventario queda en cero con inventory_error poblado.
	begin
		select
			(select count(*) from public.catalog_products),
			(select count(*) from public.catalog_variants),
			(
				select coalesce(sum(cv.stock_quantity), 0)
				from public.catalog_variants cv
					join public.catalog_products cp on cp.id = cv.product_id
				where cv.active = true and cp.active = true
			),
			(
				select count(*)
				from public.catalog_variants cv
					join public.catalog_products cp on cp.id = cv.product_id
				where cv.active = true and cp.active = true
					and cv.stock_quantity > 0 and cv.stock_quantity <= v_threshold
			),
			(
				select count(*)
				from public.catalog_variants cv
					join public.catalog_products cp on cp.id = cv.product_id
				where cv.active = true and cp.active = true
					and cv.stock_quantity = 0
			),
			(
				select count(*)
				from public.catalog_variants cv
					join public.catalog_products cp on cp.id = cv.product_id
				where cv.active = true and cp.active = true
					and cv.stock_quantity > v_threshold
			)
		into
			v_inventory_total_products,
			v_inventory_total_variants,
			v_inventory_total_units,
			v_inventory_low_stock,
			v_inventory_out_of_stock,
			v_inventory_available;
	exception
		when others then
			v_inventory_total_products := 0;
			v_inventory_total_variants := 0;
			v_inventory_total_units := 0;
			v_inventory_low_stock := 0;
			v_inventory_out_of_stock := 0;
			v_inventory_available := 0;
			-- Nunca se propaga sqlerrm/sqlstate al cliente: solo un codigo
			-- generico, sin detalle interno de PostgreSQL.
			v_inventory_error := 'INVENTORY_UNAVAILABLE';
	end;

	return jsonb_build_object(
		'active_orders_value', coalesce(v_active_value, 0),
		'active_orders_count', coalesce(v_active_count, 0),
		'confirmed_sales_value', coalesce(v_confirmed_value, 0),
		'confirmed_sales_count', coalesce(v_confirmed_count, 0),
		'orders_today', coalesce(v_orders_today, 0),
		'orders_total', coalesce(v_orders_total, 0),
		'status_counts', coalesce(v_status_counts, '[]'::jsonb),
		'daily_active_orders', coalesce(v_daily, '[]'::jsonb),
		'inventory_total_products', v_inventory_total_products,
		'inventory_total_variants', v_inventory_total_variants,
		'inventory_total_units', v_inventory_total_units,
		'inventory_low_stock', v_inventory_low_stock,
		'inventory_out_of_stock', v_inventory_out_of_stock,
		'inventory_available', v_inventory_available,
		'inventory_error', v_inventory_error
	);
end;
$$;

comment on function public.admin_dashboard_summary_v4 () is 'Resumen unico de solo lectura para el panel admin (vista Resumen): valor/conteo de pedidos activos (no cancelados, incluye received), ventas confirmadas (payment_verified, delivered, o evidencia real en order_payments), pedidos de hoy, total de pedidos, conteo por order_status (11 claves, arreglo status/count), serie de pedidos activos de los ultimos 7 dias (America/Lima, sin huecos, amount/orders_count), e inventario aplanado (productos/variantes/unidades/disponible/stock bajo/sin stock) con inventory_error si el catalogo no se pudo leer. Nunca null en importes o cantidades. Exige is_admin(). Reemplaza a admin_dashboard_summary_v3 para el Resumen; Pedidos e Inventario siguen usando admin_orders_metrics/admin_list_orders/admin_list_inventory/admin_inventory_metrics sin cambios.';

revoke
execute on function public.admin_dashboard_summary_v4 ()
from
	public,
	anon,
	authenticated;

grant
execute on function public.admin_dashboard_summary_v4 () to authenticated;

-- ============================================================
-- Fin. No se concede ningun grant nuevo sobre orders, order_payments,
-- catalog_products ni catalog_variants: el unico camino de lectura sigue
-- siendo este RPC security definer. Para verificar, correr a
-- continuacion supabase/verify_admin_dashboard_summary_v4.sql (solo
-- SELECT).
-- ============================================================
