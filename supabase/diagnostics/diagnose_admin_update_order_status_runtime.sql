-- SOLO LECTURA. Un unico SELECT sobre catalogos de sistema
-- (pg_proc/pg_namespace). No ejecuta la funcion admin_update_order_status,
-- no la modifica, no crea ni reemplaza nada. No necesita BEGIN/ROLLBACK.
-- NO EJECUTADO CONTRA SUPABASE REMOTO todavia: preparado para que el
-- propietario del proyecto lo corra el mismo (Dashboard de Supabase ->
-- SQL Editor -> pegar TODO este archivo -> Run).
--
-- Motivo de dividirlo en su propio archivo: el SQL Editor de Supabase
-- solo muestra el ultimo result set de un script con varios SELECT, asi
-- que el bloque 4 del diagnostico original nunca se veia solo. Este
-- archivo tiene una unica consulta para que su resultado sea siempre el
-- que se ve.
--
-- Objetivo: mostrar TODAS las versiones/oids activos de
-- public.admin_update_order_status realmente vigentes en produccion
-- ahora mismo -- schema, nombre, oid, firma exacta, owner, si es
-- SECURITY DEFINER, su search_path fijado y la definicion completa via
-- pg_get_functiondef(). Si aparece mas de una fila, hay sobrecargas
-- (overloads) duplicadas de la funcion, lo que explicaria comportamiento
-- inconsistente segun cual overload resuelva Postgres en cada llamada.
select
	n.nspname as schema,
	p.proname as nombre,
	p.oid as oid,
	pg_get_function_identity_arguments(p.oid) as firma_exacta,
	pg_get_userbyid(p.proowner) as owner,
	p.prosecdef as security_definer,
	(
		select cfg
		from unnest(coalesce(p.proconfig, array[]::text[])) as cfg
		where cfg like 'search_path=%'
	) as search_path,
	pg_get_functiondef(p.oid) as definicion_completa
from pg_proc p
	join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
	and p.proname = 'admin_update_order_status'
order by p.oid;
