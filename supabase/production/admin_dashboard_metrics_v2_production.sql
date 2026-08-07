-- NO EJECUTADO CONTRA SUPABASE REMOTO. Preparado localmente para que el
-- propietario del proyecto lo revise y lo corra el mismo (Dashboard de
-- Supabase -> SQL Editor -> pegar TODO este archivo -> Run).
--
-- Dashboard V2: corrige el criterio de "ventas confirmadas" y anade
-- analitica de solo lectura para la vista Resumen. Migracion
-- INCREMENTAL: no recrea admin_users, is_admin, admin_list_orders,
-- admin_get_order_detail, admin_update_order_status, admin_inventory_metrics
-- ni admin_list_inventory. No toca create_order_v2, catalog_mirror,
-- harden_create_order, harden_permissions ni harden_stock_atomic. No
-- modifica pedidos, pagos ni stock: solo lee.
--
-- ============================================================
-- CAUSA RAIZ de "Ventas confirmadas" mostrando S/ 0.00
-- ============================================================
--
-- admin_orders_metrics() (admin_orders_dashboard_production.sql) suma
-- o.total solo cuando o.payment_status = 'verified'::public.payment_status.
--
-- payment_status es una columna real de public.orders (confirmada por
-- introspeccion previa), pero ningun camino de escritura del proyecto la
-- fija jamas:
--   - supabase/harden_create_order.sql (unica via de creacion de pedidos,
--     usada por el checkout publico) inserta explicitamente payment_method,
--     delivery_method y el resto de columnas del formulario, pero NUNCA
--     incluye payment_status en su INSERT INTO public.orders (...) --
--     columna que por tanto se queda siempre en su valor DEFAULT de la
--     tabla, para siempre, para todo pedido.
--   - supabase/admin_update_order_status_production.sql (unica via de
--     cambio de estado desde el panel admin) solo hace
--     UPDATE public.orders SET order_status = ..., updated_at = ...;
--     jamas toca payment_status.
--   - Busqueda en todo el repositorio de "payment_status =" (como
--     asignacion) no devuelve ningun UPDATE ni INSERT que la fije: solo
--     aparece en el propio admin_orders_metrics como lectura.
-- Conclusion: la columna payment_status esta desconectada del flujo real
-- de la aplicacion. Comparaciones contra ella siempre son verdaderas para
-- cero filas, de ahi el S/ 0.00 constante.
--
-- La confirmacion de pago SI esta modelada en el sistema, pero a traves
-- de public.order_status (11 valores reales, verificados en el propio
-- filtro de estado ya existente en src/pages/admin/pedidos.astro):
--   received -> payment_pending -> payment_verified -> mockup_pending ->
--   mockup_sent -> mockup_approved -> in_production -> ready_to_ship ->
--   shipped -> delivered  (mas 'cancelled', fuera del flujo lineal)
-- El propio nombre 'payment_verified' es el punto del flujo en el que el
-- pago quedo confirmado; admin_update_order_status ya es la unica via de
-- escritura de order_status, y esta activamente en uso (a diferencia de
-- payment_status).
--
-- public.order_payments existe segun la introspeccion documentada en
-- admin_orders_dashboard_production.sql, pero ningun archivo de este
-- repositorio inserta ni actualiza filas ahi (grep de "order_payments" en
-- todo el proyecto solo la encuentra en comentarios/documentacion, nunca
-- en un INSERT/UPDATE), y esta sesion no tiene acceso a la base remota
-- para confirmar si contiene datos reales o cuales son los valores de su
-- columna payment_status (mismo enum de 5 valores que orders.payment_status,
-- nunca observado en uso). Por disciplina de "no inventar estados", este
-- archivo NO consulta order_payments: usar una fuente cuyos valores reales
-- no se pueden verificar seria tan arriesgado como inventarlos. Si en el
-- futuro se confirma que order_payments se llena de verdad (por un
-- proceso externo a este repo), esta funcion se puede volver a revisar.
--
-- ============================================================
-- Criterio final de "venta confirmada" (documentado y aplicado abajo)
-- ============================================================
--
-- Un pedido cuenta una sola vez como venta confirmada cuando:
--   a) su payment_method NO es 'cash_on_delivery' (yape/plin/transferencia/
--      tarjeta: el pago ya se hizo antes o al confirmar el pedido) Y su
--      order_status ya alcanzo o supero 'payment_verified' en el flujo
--      real (payment_verified, mockup_pending, mockup_sent,
--      mockup_approved, in_production, ready_to_ship, shipped, delivered);
--   b) su payment_method SI es 'cash_on_delivery' (el dinero se recibe
--      recien al entregar) Y su order_status es exactamente 'delivered'.
-- 'cancelled' nunca cuenta (no aparece en ninguna de las dos listas).
-- 'received' y 'payment_pending' nunca cuentan (pago aun no confirmado).
-- El total se toma de orders.total (una fila = un pedido = un total), sin
-- joins a order_items ni order_payments: cero riesgo de duplicar importes
-- por multiples productos o multiples pagos.

-- ============================================================
-- 1) RPC: admin_orders_metrics (reemplaza la version con el bug)
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

comment on function public.admin_orders_metrics () is 'Metricas de solo lectura para el panel admin: total, pedidos de hoy (America/Lima), conteo por order_status y ventas confirmadas. Ventas confirmadas = pedidos no-COD con order_status >= payment_verified en el flujo real, mas pedidos COD ya delivered; cancelled nunca cuenta. payment_status se ignora: ningun camino de escritura del repo la fija jamas (ver comentario de cabecera). Exige is_admin().';

revoke
execute on function public.admin_orders_metrics ()
from
	public,
	anon,
	authenticated;

grant
execute on function public.admin_orders_metrics () to authenticated;

-- ============================================================
-- 2) RPC: analitica para el Resumen (ventas 7 dias + inventario)
-- ============================================================
--
-- "Pedidos por estado" NO se duplica aqui: el frontend ya recibe
-- orders_by_status completo (11 claves, siempre con 0 en las que no
-- tienen pedidos) desde admin_orders_metrics() de arriba.

create or replace function public.admin_dashboard_analytics (p_low_stock_threshold integer default 5) returns jsonb language plpgsql security definer
set
	search_path = '' as $$
declare
	v_threshold integer := greatest(coalesce(p_low_stock_threshold, 5), 0);
	v_sales_7d jsonb;
	v_inventory jsonb;
begin
	if not public.is_admin() then
		raise exception 'ADMIN_FORBIDDEN';
	end if;

	-- Serie de 7 dias (America/Lima), hoy incluido, sin huecos: genera los
	-- 7 dias con generate_series y hace LEFT JOIN contra los pedidos
	-- confirmados de ese rango, para que un dia sin ventas aparezca con 0
	-- en vez de desaparecer de la serie.
	select coalesce(jsonb_agg(d order by d->>'date'), '[]'::jsonb)
	into v_sales_7d
	from (
		select jsonb_build_object(
			'date', to_char(day_series.day, 'YYYY-MM-DD'),
			'confirmed_total', coalesce(sum(o.total), 0),
			'confirmed_count', coalesce(count(o.id), 0)
		) as d
		from generate_series(
			(now() at time zone 'America/Lima')::date - interval '6 days',
			(now() at time zone 'America/Lima')::date,
			interval '1 day'
		) as day_series (day)
			left join public.orders o
				on (o.created_at at time zone 'America/Lima')::date = day_series.day::date
				and (
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
				)
		group by day_series.day
	) days;

	-- Estado de inventario: mismas tres categorias, mismo alcance
	-- (variantes activas de productos activos) para que las tres barras
	-- sumen el total real y sean comparables entre si.
	select jsonb_build_object(
		'available', coalesce(count(*) filter (where cv.stock_quantity > v_threshold), 0),
		'low', coalesce(count(*) filter (where cv.stock_quantity > 0 and cv.stock_quantity <= v_threshold), 0),
		'out', coalesce(count(*) filter (where cv.stock_quantity = 0), 0)
	)
	into v_inventory
	from public.catalog_variants cv
		join public.catalog_products cp on cp.id = cv.product_id
	where cv.active = true
		and cp.active = true;

	return jsonb_build_object(
		'sales_last_7_days', v_sales_7d,
		'inventory_status', v_inventory
	);
end;
$$;

comment on function public.admin_dashboard_analytics (integer) is 'Analitica de solo lectura para la vista Resumen del panel admin: ventas confirmadas de los ultimos 7 dias (America/Lima, sin huecos, mismo criterio que admin_orders_metrics) y estado de inventario (available/low/out, variantes activas de productos activos, mismo umbral que admin_inventory_metrics). No duplica pedidos por estado: ya disponible en admin_orders_metrics(). Exige is_admin().';

revoke
execute on function public.admin_dashboard_analytics (integer)
from
	public,
	anon,
	authenticated;

grant
execute on function public.admin_dashboard_analytics (integer) to authenticated;

-- ============================================================
-- Fin. No se concede ningun grant nuevo sobre orders, order_items,
-- catalog_products ni catalog_variants: el unico camino de lectura sigue
-- siendo RPC security definer. Para verificar, correr a continuacion
-- supabase/verify_admin_dashboard_metrics_v2.sql (solo SELECT).
-- ============================================================
