-- Solo lectura. No modifica datos, no crea nada. Correr DESPUES de
-- admin_dashboard_summary_v4_production.sql en Supabase Dashboard -> SQL
-- Editor, autenticado como un usuario con fila activa en admin_users, y
-- revisar cada resultado a mano.

-- 1) Existencia y firma.
select to_regprocedure('public.admin_dashboard_summary_v4()') as admin_dashboard_summary_v4;
-- esperado: un oid (no NULL).

-- 2) Propietario, security definer y search_path vacio.
select
	p.proname,
	pg_get_userbyid(p.proowner) as owner,
	p.prosecdef as is_security_definer,
	p.proconfig
from pg_proc p
	join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
	and p.proname = 'admin_dashboard_summary_v4';
-- esperado: prosecdef = true, proconfig contiene 'search_path='.

-- 3) ACL: solo 'authenticated' con EXECUTE, nunca 'public' ni 'anon'.
select routine_name, grantee, privilege_type
from information_schema.role_routine_grants
where routine_schema = 'public'
	and routine_name = 'admin_dashboard_summary_v4'
order by grantee;
-- esperado: solo una fila, grantee = 'authenticated'.

-- 3b) Confirmar explicitamente que PUBLIC y anon NO tienen EXECUTE.
select count(*) as filas_no_esperadas
from information_schema.role_routine_grants
where routine_schema = 'public'
	and routine_name = 'admin_dashboard_summary_v4'
	and grantee in ('PUBLIC', 'anon');
-- esperado: 0.

-- 4) Confirmar que no se agrego ningun grant directo de tabla nuevo sobre
-- orders/order_payments/catalog_products/catalog_variants para anon/authenticated.
select grantee, table_name, privilege_type
from information_schema.role_table_grants
where table_schema = 'public'
	and table_name in ('orders', 'order_payments', 'catalog_products', 'catalog_variants')
	and grantee in ('anon', 'authenticated');
-- esperado: 0 filas (el unico camino de lectura sigue siendo el RPC).

-- 5) Llamada real (requiere sesion autenticada de un admin: la funcion
-- exige is_admin() y lanza ADMIN_FORBIDDEN si no lo es).
-- select public.admin_dashboard_summary_v4() as resumen;

-- 6) Valor de pedidos activos: comparar contra un calculo manual con el
-- mismo criterio documentado (todo pedido no cancelado). Descomentar y
-- correr como administrador junto con el punto 5 para comparar contra
-- active_orders_value/active_orders_count.
-- select
-- 	coalesce(sum(o.total), 0) as manual_active_value,
-- 	count(*) as manual_active_count
-- from public.orders o
-- where o.order_status <> 'cancelled'::public.order_status;

-- 7) Ventas confirmadas: mismo calculo manual que usa la funcion.
-- Comparar contra confirmed_sales_value/confirmed_sales_count del punto 5.
-- select
-- 	coalesce(sum(o.total), 0) as manual_confirmed_value,
-- 	count(*) as manual_confirmed_count
-- from public.orders o
-- where o.order_status <> 'cancelled'::public.order_status
-- 	and (
-- 		o.order_status = 'payment_verified'::public.order_status
-- 		or o.order_status = 'delivered'::public.order_status
-- 		or exists (
-- 			select 1
-- 			from public.order_payments op
-- 			where op.order_id = o.id
-- 				and op.payment_status = 'verified'::public.payment_status
-- 		)
-- 	);

-- 8) status_counts debe traer exactamente 11 elementos (uno por valor del
-- enum order_status), y daily_active_orders exactamente 7 (America/Lima,
-- sin huecos, hoy incluido).
-- select
-- 	jsonb_array_length(v->'status_counts') as estados_en_arreglo,
-- 	jsonb_array_length(v->'daily_active_orders') as dias_en_serie
-- from (select public.admin_dashboard_summary_v4() as v) s;
-- esperado: 11 y 7.

-- 9) Ningun importe/cantidad debe volver null. Comparar el jsonb del
-- punto 5 a mano: active_orders_value, confirmed_sales_value,
-- orders_today, orders_total y los 6 campos inventory_* nunca deben ser
-- JSON null (0 es valido, null no).
