-- Solo lectura. No modifica datos, no crea nada, no necesita BEGIN ni
-- ROLLBACK. Correr DESPUES de admin_update_order_status_production.sql
-- en Supabase Dashboard -> SQL Editor, y revisar cada resultado a mano.

-- 1) Existencia de la funcion (y, de paso, de order_status_history, que
-- la funcion necesita para registrar el historial). Ninguna columna
-- debe salir null.
select
	to_regprocedure(
		'public.admin_update_order_status(uuid, public.order_status, public.order_status, text)'
	) as admin_update_order_status,
	to_regclass('public.order_status_history') as order_status_history;

-- 2) Propietario, security definer y search_path fijado.
-- Esperado: prosecdef = true, proconfig con {search_path=""}.
select
	p.proname,
	pg_get_userbyid(p.proowner) as owner,
	p.prosecdef,
	p.proconfig,
	pg_get_function_identity_arguments(p.oid) as args
from pg_proc p
	join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
	and p.proname = 'admin_update_order_status';

-- 3) ACL cruda de la funcion. Esperado: NO debe aparecer "=X/" sin rol
-- delante (eso seria PUBLIC), ni "anon=X/". Solo authenticated=X/ y el
-- propietario.
select proacl
from pg_proc p
	join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
	and p.proname = 'admin_update_order_status';

-- 4) Lo mismo en forma legible: la unica fila con grantee de cliente
-- debe ser 'authenticated' / EXECUTE. Nunca 'public' ni 'anon'.
select grantee, privilege_type
from information_schema.role_routine_grants
where routine_schema = 'public'
	and routine_name = 'admin_update_order_status'
order by grantee;

-- 5) Comprobacion explicita de denegacion. Esperado:
-- publico_puede = false, anon_puede = false, authenticated_puede = true.
select
	has_function_privilege(
		'public',
		'public.admin_update_order_status(uuid, public.order_status, public.order_status, text)',
		'execute'
	) as publico_puede,
	has_function_privilege(
		'anon',
		'public.admin_update_order_status(uuid, public.order_status, public.order_status, text)',
		'execute'
	) as anon_puede,
	has_function_privilege(
		'authenticated',
		'public.admin_update_order_status(uuid, public.order_status, public.order_status, text)',
		'execute'
	) as authenticated_puede;

-- 6) Esta migracion no debio abrir ningun acceso directo a las tablas.
-- Esperado: 0 filas.
select grantee, table_name, privilege_type
from information_schema.role_table_grants
where table_schema = 'public'
	and table_name in ('orders', 'order_status_history')
	and grantee in ('public', 'anon', 'authenticated');

-- 7) Columnas reales de order_status_history usadas por el RPC
-- (order_id, previous_status, new_status, note, changed_by, created_at).
select column_name, data_type, udt_name, is_nullable, column_default
from information_schema.columns
where table_schema = 'public'
	and table_name = 'order_status_history'
order by ordinal_position;

-- ============================================================
-- Pruebas manuales (COMENTADAS a proposito: modifican datos reales).
-- No hay UUID reales en este archivo. Para probar, reemplaza
-- '<UUID_DE_UN_PEDIDO_REAL>' por un id copiado del panel y descomenta
-- solo la linea que quieras ejecutar. Hazlo sobre un pedido de prueba:
-- estos cambios SI persisten y SI quedan registrados en el historial.
--
-- Ten en cuenta que en el SQL Editor auth.uid() es null, asi que estas
-- llamadas devolveran ADMIN_FORBIDDEN: la prueba real se hace desde el
-- panel, con sesion de administrador. Aqui sirven para confirmar que
-- cada error se dispara con su mensaje esperado.
--
-- a) Cambio valido (estado esperado = el que tiene ahora el pedido):
-- select public.admin_update_order_status(
--     '<UUID_DE_UN_PEDIDO_REAL>'::uuid,
--     'received'::public.order_status,
--     'in_production'::public.order_status,
--     'Nota de prueba'
-- );
--
-- b) Conflicto: se manda un estado esperado que no es el actual.
--    Esperado: ORDER_STATUS_CONFLICT.
-- select public.admin_update_order_status(
--     '<UUID_DE_UN_PEDIDO_REAL>'::uuid,
--     'cancelled'::public.order_status,
--     'shipped'::public.order_status
-- );
--
-- c) Pedido inexistente. Esperado: ORDER_NOT_FOUND.
-- select public.admin_update_order_status(
--     '00000000-0000-0000-0000-000000000000'::uuid,
--     'received'::public.order_status,
--     'shipped'::public.order_status
-- );
--
-- d) Sin cambio real. Esperado: ORDER_STATUS_UNCHANGED.
-- select public.admin_update_order_status(
--     '<UUID_DE_UN_PEDIDO_REAL>'::uuid,
--     'received'::public.order_status,
--     'received'::public.order_status
-- );
--
-- e) Llamada no autorizada: desde el navegador con una sesion que no
--    esta en admin_users, o aqui mismo (auth.uid() es null).
--    Esperado: ADMIN_FORBIDDEN.
-- ============================================================
