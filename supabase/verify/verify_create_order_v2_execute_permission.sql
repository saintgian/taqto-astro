-- Solo lectura. No modifica pedidos, stock, funciones ni permisos.
-- Correr en el SQL Editor de Supabase ANTES y DESPUES de
-- fix_create_order_v2_execute_permission_production.sql para comparar.

-- 1) Funcion(es) encontradas con este nombre + firma exacta + owner +
--    security definer + search_path configurado. Si esta consulta
--    devuelve mas de una fila, hay mas de una sobrecarga de
--    create_order_v2 y hay que confirmar cual es la que PostgREST
--    resuelve para la llamada del checkout (14 argumentos).
select
	n.nspname as schema,
	p.proname as function_name,
	pg_get_function_identity_arguments(p.oid) as signature,
	pg_get_function_result(p.oid) as return_type,
	p.prosecdef as security_definer,
	r.rolname as owner,
	p.proconfig as server_config -- debe incluir algo como {search_path=public}
from pg_proc p
	join pg_namespace n on n.oid = p.pronamespace
	join pg_roles r on r.oid = p.proowner
where
	n.nspname = 'public'
	and p.proname = 'create_order_v2';

-- 2) Cuantas sobrecargas existen en total (esperado: 1, la de 14
--    argumentos que usa el checkout).
select count(*) as overload_count
from pg_proc p
	join pg_namespace n on n.oid = p.pronamespace
where
	n.nspname = 'public'
	and p.proname = 'create_order_v2';

-- 3) ACL efectivo, decodificado por rol y privilegio, sobre CADA
--    sobrecarga encontrada. Un grantee vacio/NULL representa a PUBLIC.
--    Esta es la evidencia directa de por que `anon` recibe 403: si no
--    aparece una fila (grantee = 'anon', privilege_type = 'EXECUTE'),
--    el rol no tiene el permiso, sin importar lo que digan los
--    comentarios de otros archivos SQL locales.
select
	p.oid as function_oid,
	pg_get_function_identity_arguments(p.oid) as signature,
	coalesce(r2.rolname, 'PUBLIC') as grantee,
	a.privilege_type,
	a.is_grantable
from pg_proc p
	join pg_namespace n on n.oid = p.pronamespace
	cross join lateral aclexplode(
		coalesce(p.proacl, acldefault('f', p.proowner))
	) a
	left join pg_roles r2 on r2.oid = a.grantee
where
	n.nspname = 'public'
	and p.proname = 'create_order_v2'
order by function_oid, grantee, privilege_type;

-- 4) Chequeo directo, booleano, sobre la firma exacta de 14 argumentos
--    que usa el checkout publico (src/pages/carrito.astro).
select
	has_function_privilege(
		'anon',
		'public.create_order_v2(public.payment_method, public.delivery_method, text, text, text, text, text, text, text, text, text, text, jsonb, text)',
		'EXECUTE'
	) as anon_can_execute,
	has_function_privilege(
		'authenticated',
		'public.create_order_v2(public.payment_method, public.delivery_method, text, text, text, text, text, text, text, text, text, text, jsonb, text)',
		'EXECUTE'
	) as authenticated_can_execute_informative_only;

-- Lectura esperada tras aplicar el fix:
--   - overload_count = 1
--   - fila 3: (grantee='anon', privilege_type='EXECUTE') presente;
--     ninguna fila con grantee='PUBLIC' ni grantee='authenticated' para
--     EXECUTE sobre esta funcion.
--   - fila 4: anon_can_execute = true.
