-- SOLO LECTURA. Un unico SELECT (via UNION ALL) sobre catalogos de
-- sistema (pg_trigger/pg_proc/pg_rules). No ejecuta ningun trigger ni
-- funcion, no las modifica, no crea ni reemplaza nada. No necesita
-- BEGIN/ROLLBACK.
-- NO EJECUTADO CONTRA SUPABASE REMOTO todavia: preparado para que el
-- propietario del proyecto lo corra el mismo (Dashboard de Supabase ->
-- SQL Editor -> pegar TODO este archivo -> Run).
--
-- Motivo de dividirlo en su propio archivo: el SQL Editor de Supabase
-- solo muestra el ultimo result set de un script con varios SELECT, asi
-- que los bloques 5/6/8 del diagnostico original (triggers, sus
-- funciones y reglas) nunca se veian juntos. Este archivo combina todo
-- en una unica consulta (triggers + su funcion completa, y reglas de
-- pg_rules) mediante UNION ALL para que un solo result set lo muestre
-- todo.
--
-- Objetivo: listar todo trigger NO interno sobre public.orders y
-- public.order_status_history (con su definicion exacta y la definicion
-- completa de la funcion que ejecuta), y toda regla de pg_rules sobre
-- esas dos tablas. Si aparece cualquier trigger o regla no documentada
-- en el repo local, es candidato directo a estar produciendo una
-- segunda fila de historial que ningun archivo .sql local explica.
with triggers as (
	select
		'trigger' as kind,
		c.relname as table_name,
		t.tgname as object_name,
		case t.tgenabled
			when 'O' then 'enabled'
			when 'D' then 'disabled'
			when 'R' then 'replica'
			when 'A' then 'always'
		end as enabled,
		pg_get_triggerdef(t.oid) as definition,
		fn.nspname || '.' || p.proname as function_name,
		pg_get_functiondef(p.oid) as function_definition
	from pg_trigger t
		join pg_class c on c.oid = t.tgrelid
		join pg_namespace n on n.oid = c.relnamespace
		join pg_proc p on p.oid = t.tgfoid
		join pg_namespace fn on fn.oid = p.pronamespace
	where n.nspname = 'public'
		and c.relname in ('orders', 'order_status_history')
		and not t.tgisinternal
),
rules as (
	select
		'rule' as kind,
		tablename as table_name,
		rulename as object_name,
		null::text as enabled,
		definition as definition,
		null::text as function_name,
		null::text as function_definition
	from pg_rules
	where schemaname = 'public'
		and tablename in ('orders', 'order_status_history')
)
select * from triggers
union all
select * from rules
order by table_name, kind, object_name;
