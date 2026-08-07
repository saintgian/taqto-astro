-- Solo lectura. No modifica datos, no crea nada, no necesita BEGIN ni
-- ROLLBACK. Correr DESPUES de admin_inventory_dashboard_production.sql en
-- Supabase Dashboard -> SQL Editor, y revisar cada resultado a mano.

-- 1) Existencia de los 2 objetos de funcion nuevos. Ambos deben salir
-- con un oid (no null). Si alguno sale null, ese objeto no existe en la
-- base remota.
select
	to_regprocedure('public.admin_inventory_metrics(integer)') as admin_inventory_metrics,
	to_regprocedure(
		'public.admin_list_inventory(text, text, boolean, integer, integer, integer)'
	) as admin_list_inventory;

-- 2) security definer + search_path vacio en ambas funciones.
select
	p.proname,
	p.prosecdef as security_definer,
	p.proconfig
from pg_proc p
	join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
	and p.proname in ('admin_inventory_metrics', 'admin_list_inventory');

-- 3) ACL de funciones: solo 'authenticated' con EXECUTE (nunca 'public'
-- ni 'anon').
select routine_name, grantee, privilege_type
from information_schema.role_routine_grants
where routine_schema = 'public'
	and routine_name in ('admin_inventory_metrics', 'admin_list_inventory')
order by routine_name, grantee;

-- 4) PUBLIC y anon explícitamente sin EXECUTE (0 filas esperadas).
select routine_name, grantee, privilege_type
from information_schema.role_routine_grants
where routine_schema = 'public'
	and routine_name in ('admin_inventory_metrics', 'admin_list_inventory')
	and grantee in ('PUBLIC', 'anon'); -- esperado: 0 filas

-- 5) Confirmar que catalog_products/catalog_variants siguen sin acceso
-- directo para anon/authenticated (ya deberia estar asi desde
-- catalog_mirror.sql; esto solo lo reconfirma, no debio cambiar con
-- esta migracion, y esta migracion no concede nada nuevo sobre ellas).
select grantee, table_name, privilege_type
from information_schema.role_table_grants
where table_schema = 'public'
	and table_name in ('catalog_products', 'catalog_variants')
	and grantee in ('anon', 'authenticated'); -- esperado: 0 filas

-- 6) Muestra rapida del inventario espejado (solo para confirmar que hay
-- datos sincronizados; puede salir vacio si scripts/sync-catalog.mjs
-- todavia no corrio, lo cual es esperado y no es un error de esta
-- migracion).
select
	cp.title,
	cv.sku,
	cv.wood_title,
	cv.size_title,
	cv.stock_quantity,
	cv.active as variant_active,
	cp.active as product_active
from public.catalog_variants cv
	join public.catalog_products cp on cp.id = cv.product_id
order by cp.title, cv.sku
limit 20;
