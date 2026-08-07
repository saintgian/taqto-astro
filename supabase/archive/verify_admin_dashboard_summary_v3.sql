-- Solo lectura. No modifica datos, no crea nada. Correr DESPUES de
-- admin_dashboard_summary_v3_production.sql en Supabase Dashboard -> SQL
-- Editor, y revisar cada resultado a mano.

-- 1) Existencia y firma de las 2 funciones.
select
	to_regprocedure('public.admin_orders_metrics()') as admin_orders_metrics,
	to_regprocedure('public.admin_dashboard_summary_v3(integer)') as admin_dashboard_summary_v3;
-- esperado: ambas columnas con un oid (no NULL).

-- 2) security definer + search_path vacio en ambas.
select
	p.proname,
	p.prosecdef as is_security_definer,
	p.proconfig
from pg_proc p
	join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
	and p.proname in ('admin_orders_metrics', 'admin_dashboard_summary_v3');
-- esperado: prosecdef = true, proconfig contiene 'search_path='.

-- 3) ACL: solo 'authenticated' con EXECUTE, nunca 'public' ni 'anon'.
select routine_name, grantee, privilege_type
from information_schema.role_routine_grants
where routine_schema = 'public'
	and routine_name in ('admin_orders_metrics', 'admin_dashboard_summary_v3')
order by routine_name, grantee;
-- esperado: solo filas con grantee = 'authenticated'.

-- 4) Confirmar que no se agrego ningun grant directo de tabla nuevo sobre
-- orders/order_items/catalog_products/catalog_variants para anon/authenticated.
select grantee, table_name, privilege_type
from information_schema.role_table_grants
where table_schema = 'public'
	and table_name in ('orders', 'order_items', 'catalog_products', 'catalog_variants')
	and grantee in ('anon', 'authenticated'); -- esperado: 0 filas

-- 5) Llamada real (autenticado como admin: la funcion exige is_admin()).
select public.admin_dashboard_summary_v3() as resumen;

-- 6) Valor de pedidos activos: comparar contra un calculo manual con el
-- mismo criterio documentado (todo pedido no cancelado).
select
	coalesce(sum(o.total), 0) as manual_active_value,
	count(*) as manual_active_count
from public.orders o
where o.order_status <> 'cancelled'::public.order_status;
-- esperado: debe coincidir con active_orders_value/active_orders_count
-- dentro del jsonb devuelto en el paso 5.

-- 7) Ventas confirmadas: mismo calculo manual que ya usaba
-- verify_admin_dashboard_metrics_v2.sql.
select
	coalesce(sum(o.total), 0) as manual_confirmed_value,
	count(*) as manual_confirmed_count
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
-- esperado: debe coincidir con confirmed_sales_value/confirmed_sales_count
-- del paso 5, y con el resultado de admin_orders_metrics() (paso 8).

-- 8) admin_orders_metrics() sigue siendo consistente con el paso 7 (la
-- pestana Pedidos la sigue usando directamente).
select * from public.admin_orders_metrics();

-- 9) La serie de 7 dias debe traer exactamente 7 fechas (America/Lima),
-- sin huecos, y cubrir hoy.
select
	jsonb_array_length(v->'active_orders_last_7_days') as dias_en_serie,
	v->'active_orders_last_7_days' as serie
from (select public.admin_dashboard_summary_v3() as v) s;
-- esperado: dias_en_serie = 7.

-- 10) Inventario dentro del jsonb: comparar contra admin_inventory_metrics
-- si ya esta aplicado (opcional, no falla si la funcion no existe todavia).
select v->'inventory' as inventario
from (select public.admin_dashboard_summary_v3() as v) s;
