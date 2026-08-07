-- Solo lectura. No modifica datos, no crea nada, no necesita BEGIN ni
-- ROLLBACK. Correr DESPUES de
-- supabase/public_variant_availability_production.sql en Supabase
-- Dashboard -> SQL Editor, y revisar cada resultado a mano.

-- 1) Existencia de la funcion. Debe salir un oid (no null).
select to_regprocedure('public.public_variant_availability(text)') as public_variant_availability;

-- 2) security definer, stable y search_path vacio.
--    Esperado: security_definer = true, volatility = 's',
--    proconfig = {search_path=""}.
select
	p.proname,
	p.prosecdef as security_definer,
	p.provolatile as volatility,
	p.proconfig
from pg_proc p
	join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
	and p.proname = 'public_variant_availability';

-- 3) ACL de la funcion. Esperado: EXACTAMENTE una fila con
--    grantee = 'anon', privilege_type = 'EXECUTE'.
select routine_name, grantee, privilege_type
from information_schema.role_routine_grants
where routine_schema = 'public'
	and routine_name = 'public_variant_availability'
order by grantee;

-- 4) PUBLIC y authenticated explicitamente sin EXECUTE.
--    Esperado: 0 filas.
select routine_name, grantee, privilege_type
from information_schema.role_routine_grants
where routine_schema = 'public'
	and routine_name = 'public_variant_availability'
	and grantee in ('PUBLIC', 'authenticated'); -- esperado: 0 filas

-- 5) catalog_products / catalog_variants SIGUEN sin acceso directo para
--    anon y authenticated. Esperado: 0 filas. Si aparece alguna, este
--    archivo no la creo, pero hay que investigarla antes de seguir.
select table_name, grantee, privilege_type
from information_schema.role_table_grants
where table_schema = 'public'
	and table_name in ('catalog_products', 'catalog_variants')
	and grantee in ('anon', 'authenticated'); -- esperado: 0 filas

-- 6) RLS sigue activo en ambas tablas. Esperado: rowsecurity = true en
--    las dos.
select relname, relrowsecurity as rowsecurity
from pg_class
where relnamespace = 'public'::regnamespace
	and relname in ('catalog_products', 'catalog_variants');

-- 7) Sin policies nuevas sobre esas tablas. Esperado: 0 filas.
select tablename, policyname
from pg_policies
where schemaname = 'public'
	and tablename in ('catalog_products', 'catalog_variants'); -- esperado: 0 filas

-- 8) create_order_v2 intacta: sigue existiendo con su firma de 14
--    argumentos y con EXECUTE solo para anon. Esperado: oid no null y
--    exactamente una fila con grantee = 'anon'.
select to_regprocedure(
	'public.create_order_v2(public.payment_method, public.delivery_method, text, text, text, text, text, text, text, text, text, text, jsonb, text)'
) as create_order_v2;

select routine_name, grantee, privilege_type
from information_schema.role_routine_grants
where routine_schema = 'public'
	and routine_name = 'create_order_v2'
order by grantee;

-- 9) Prueba funcional de la respuesta. Toma un producto activo real y
--    muestra lo que devolveria la funcion. Comparar a mano contra
--    catalog_variants: deben coincidir SKU y stock, y no debe aparecer
--    ninguna variante inactiva ni ninguna columna extra.
select cp.sanity_id, cp.slug, cp.title
from public.catalog_products cp
where cp.active = true
order by cp.slug
limit 5;

-- Reemplazar <SANITY_ID> por uno de los valores de la consulta anterior.
-- select * from public.public_variant_availability('<SANITY_ID>');

-- 10) Contraste: la misma variante vista desde la tabla. Las columnas
--     sku/stock_quantity deben coincidir una a una con el paso 9.
--     Reemplazar <SANITY_ID> igual que arriba.
-- select cv.sku, cv.stock_quantity, cv.active as variant_active, cp.active as product_active
-- from public.catalog_variants cv
-- 	join public.catalog_products cp on cp.id = cv.product_id
-- where cv.sanity_product_id = '<SANITY_ID>'
-- order by cv.sku;

-- 11) Entradas basura no deben lanzar error ni devolver filas.
--     Esperado: 0 filas en las tres.
select * from public.public_variant_availability(null);

select * from public.public_variant_availability('');

select * from public.public_variant_availability('   ');
