-- Solo lectura. No modifica datos, no crea nada. Correr DESPUES de
-- admin_dashboard_summary_v4_production.sql y de
-- admin_orders_metrics_fix_confirmed_sales_production.sql, autenticado
-- como un usuario con fila activa en admin_users, y revisar cada
-- resultado a mano.

-- 1) Existencia y firma.
select to_regprocedure('public.admin_orders_metrics()') as admin_orders_metrics;
-- esperado: un oid (no NULL).

-- 2) security definer + search_path vacio.
select
	p.proname,
	p.prosecdef as is_security_definer,
	p.proconfig
from pg_proc p
	join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
	and p.proname = 'admin_orders_metrics';
-- esperado: prosecdef = true, proconfig contiene 'search_path='.

-- 3) ACL: solo 'authenticated' con EXECUTE, nunca 'public' ni 'anon'.
select routine_name, grantee, privilege_type
from information_schema.role_routine_grants
where routine_schema = 'public'
	and routine_name = 'admin_orders_metrics'
order by grantee;
-- esperado: solo una fila, grantee = 'authenticated'.

-- 4) Llamada real (requiere sesion autenticada de un admin).
-- select * from public.admin_orders_metrics();

-- 5) Comparar confirmed_sales_total/confirmed_sales_count del paso 4
-- contra confirmed_sales_value/confirmed_sales_count de
-- admin_dashboard_summary_v4() -- deben coincidir exactamente, es la
-- misma fuente.
-- select
-- 	m.confirmed_sales_total,
-- 	m.confirmed_sales_count,
-- 	(s.v ->> 'confirmed_sales_value')::numeric as v4_confirmed_sales_value,
-- 	(s.v ->> 'confirmed_sales_count')::bigint as v4_confirmed_sales_count
-- from public.admin_orders_metrics() m,
-- 	(select public.admin_dashboard_summary_v4() as v) s;
-- esperado: las dos primeras columnas iguales a las dos ultimas.

-- 6) Calculo manual de referencia (mismo criterio documentado en
-- admin_dashboard_summary_v4_production.sql): confirmar que coincide con
-- el paso 4/5.
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
