-- Solo lectura. No modifica datos, no crea nada. Correr DESPUES de
-- admin_dashboard_metrics_v2_production.sql en Supabase Dashboard -> SQL
-- Editor, y revisar cada resultado a mano.

-- 1) Existencia y firma de las 2 funciones.
select
	to_regprocedure('public.admin_orders_metrics()') as admin_orders_metrics,
	to_regprocedure('public.admin_dashboard_analytics(integer)') as admin_dashboard_analytics;

-- 2) security definer + search_path vacio en ambas.
select
	p.proname,
	p.prosecdef as is_security_definer,
	p.proconfig
from pg_proc p
	join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
	and p.proname in ('admin_orders_metrics', 'admin_dashboard_analytics');
-- esperado: prosecdef = true, proconfig contiene 'search_path='.

-- 3) ACL: solo 'authenticated' con EXECUTE, nunca 'public' ni 'anon'.
select routine_name, grantee, privilege_type
from information_schema.role_routine_grants
where routine_schema = 'public'
	and routine_name in ('admin_orders_metrics', 'admin_dashboard_analytics')
order by routine_name, grantee;
-- esperado: solo filas con grantee = 'authenticated'.

-- 4) Confirmar que no se agrego ningun grant directo de tabla nuevo sobre
-- orders/order_items/catalog_products/catalog_variants para anon/authenticated.
select grantee, table_name, privilege_type
from information_schema.role_table_grants
where table_schema = 'public'
	and table_name in ('orders', 'order_items', 'catalog_products', 'catalog_variants')
	and grantee in ('anon', 'authenticated'); -- esperado: 0 filas

-- 5) Criterio de ventas confirmadas: comparar el resultado de
-- admin_orders_metrics() contra un calculo manual con el mismo criterio
-- documentado (no-COD con order_status >= payment_verified, o COD
-- delivered). Debe llamarse ya autenticado como un admin real (la funcion
-- exige is_admin()).
select * from public.admin_orders_metrics();

select
	coalesce(sum(o.total), 0) as manual_confirmed_total,
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
-- esperado: manual_confirmed_total/count deben coincidir exactamente con
-- confirmed_sales_total/confirmed_sales_count de admin_orders_metrics().

-- 6) Analitica: la serie de 7 dias debe traer exactamente 7 filas
-- (America/Lima), sin huecos.
select jsonb_array_length(v->'sales_last_7_days') as dias_en_serie, v
from (select public.admin_dashboard_analytics() as v) s;
-- esperado: dias_en_serie = 7.
