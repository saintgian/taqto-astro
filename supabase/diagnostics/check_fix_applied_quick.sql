-- SOLO LECTURA. Un unico SELECT sobre catalogos de sistema
-- (pg_trigger/pg_class/pg_proc). No hay INSERT/UPDATE/DELETE/ALTER/
-- DROP/CREATE/DO. No necesita BEGIN/ROLLBACK.
-- NO EJECUTADO CONTRA SUPABASE REMOTO.
--
-- Proposito: un vistazo de 3 filas para saber, sin leer nada mas, si
-- fix_duplicate_order_status_history_production.sql ya se aplico. Para
-- el analisis completo (admin_update_order_status, productores
-- restantes, etc.) usar verify_duplicate_order_status_history_fix.sql.
--
-- Lectura esperada DESPUES de aplicar el fix:
--   orders_log_status_change    -> AUSENTE
--   orders_create_initial_history -> enabled
--   orders_set_updated_at       -> enabled
select
	'orders_log_status_change' as trigger_esperado,
	coalesce(
		case t.tgenabled
			when 'O' then 'enabled'
			when 'D' then 'disabled'
			when 'R' then 'replica'
			when 'A' then 'always'
		end,
		'AUSENTE'
	) as estado_actual,
	case when t.tgname is null then 'OK: fix aplicado (trigger ausente)' else 'REVISAR: el fix aun no se aplico o fallo' end as lectura
from pg_class c
	join pg_namespace n on n.oid = c.relnamespace
	left join pg_trigger t
		on t.tgrelid = c.oid
		and t.tgname = 'orders_log_status_change'
		and not t.tgisinternal
where n.nspname = 'public'
	and c.relname = 'orders'

union all

select
	'orders_create_initial_history',
	coalesce(
		case t.tgenabled
			when 'O' then 'enabled'
			when 'D' then 'disabled'
			when 'R' then 'replica'
			when 'A' then 'always'
		end,
		'AUSENTE'
	),
	case
		when t.tgenabled = 'O' then 'OK: presente y habilitado'
		when t.tgname is not null then 'REVISAR: presente pero no habilitado'
		else 'REVISAR: no deberia haberse tocado, pero no aparece'
	end
from pg_class c
	join pg_namespace n on n.oid = c.relnamespace
	left join pg_trigger t
		on t.tgrelid = c.oid
		and t.tgname = 'orders_create_initial_history'
		and not t.tgisinternal
where n.nspname = 'public'
	and c.relname = 'orders'

union all

select
	'orders_set_updated_at',
	coalesce(
		case t.tgenabled
			when 'O' then 'enabled'
			when 'D' then 'disabled'
			when 'R' then 'replica'
			when 'A' then 'always'
		end,
		'AUSENTE'
	),
	case
		when t.tgenabled = 'O' then 'OK: presente y habilitado'
		when t.tgname is not null then 'REVISAR: presente pero no habilitado'
		else 'REVISAR: no deberia haberse tocado, pero no aparece'
	end
from pg_class c
	join pg_namespace n on n.oid = c.relnamespace
	left join pg_trigger t
		on t.tgrelid = c.oid
		and t.tgname = 'orders_set_updated_at'
		and not t.tgisinternal
where n.nspname = 'public'
	and c.relname = 'orders';
