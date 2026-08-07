-- Solo lectura. No modifica datos, no crea nada, no necesita BEGIN ni
-- ROLLBACK. Correr DESPUES de admin_orders_dashboard_production.sql en
-- Supabase Dashboard -> SQL Editor, y revisar cada resultado a mano.

-- 1) Existencia de la tabla y de los 4 objetos de funcion.
-- Todas las columnas deben salir con un oid (no null). Si alguna sale
-- null, ese objeto no existe en la base remota.
select
	to_regclass('public.admin_users') as admin_users,
	to_regprocedure('public.is_admin()') as is_admin,
	to_regprocedure('public.admin_orders_metrics()') as admin_orders_metrics,
	to_regprocedure(
		'public.admin_list_orders(text, public.order_status, public.payment_method, public.delivery_method, date, date, integer, integer)'
	) as admin_list_orders,
	to_regprocedure('public.admin_get_order_detail(uuid)') as admin_get_order_detail;

-- 2) admin_users: RLS activo y cero policies (deniega todo por
-- defecto). relrowsecurity debe ser true; la segunda consulta debe
-- devolver 0 filas.
select relrowsecurity, relforcerowsecurity
from pg_class
where oid = 'public.admin_users'::regclass;

select *
from pg_policies
where schemaname = 'public'
	and tablename = 'admin_users'; -- esperado: 0 filas

-- 3) admin_users: cero grants de tabla a public/anon/authenticated
-- (solo debe aparecer el propietario, si acaso).
select grantee, privilege_type
from information_schema.role_table_grants
where table_schema = 'public'
	and table_name = 'admin_users'
	and grantee in ('public', 'anon', 'authenticated'); -- esperado: 0 filas

-- 4) ACL de funciones: is_admin sin ningun grantee de cliente;
-- los 3 admin_* solo con 'authenticated' (nunca 'public' ni 'anon').
select routine_name, grantee, privilege_type
from information_schema.role_routine_grants
where routine_schema = 'public'
	and routine_name in (
		'is_admin',
		'admin_orders_metrics',
		'admin_list_orders',
		'admin_get_order_detail'
	)
order by routine_name, grantee;

-- 5) Confirmar que orders/order_items/order_status_history/order_payments
-- siguen sin acceso directo para anon/authenticated (ya deberia estar
-- asi desde harden_permissions.sql; esto solo lo reconfirma, no debio
-- cambiar con esta migracion).
select grantee, table_name, privilege_type
from information_schema.role_table_grants
where table_schema = 'public'
	and table_name in (
		'orders',
		'order_items',
		'order_status_history',
		'order_payments'
	)
	and grantee in ('anon', 'authenticated'); -- esperado: 0 filas

-- 6) Administradores activos actuales (vacio hasta completar la PARTE 2
-- manual: crear usuario en Auth e insertarlo en admin_users).
select user_id, active, created_at
from public.admin_users
order by created_at;
