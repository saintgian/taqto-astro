-- SOLO LECTURA. Un unico SELECT sobre catalogos de sistema. No hay
-- INSERT/UPDATE/DELETE/ALTER/DROP/CREATE/DO. No ejecuta ninguna funcion
-- ni trigger. No necesita BEGIN/ROLLBACK.
-- NO EJECUTADO CONTRA SUPABASE REMOTO: para que lo corra el propietario
-- del proyecto (Dashboard de Supabase -> SQL Editor -> pegar TODO ->
-- Run) DESPUES de fix_duplicate_order_status_history_production.sql.
--
-- Es una unica consulta a proposito: el SQL Editor de Supabase solo
-- muestra el ultimo result set de un script, asi que todas las
-- comprobaciones se combinan por UNION ALL en una sola tabla de salida.
--
-- ============================================================
-- CORRECCION sobre la version anterior: ERROR 42809
-- ============================================================
-- La version anterior fallaba con:
--   ERROR: 42809: "array_agg" is an aggregate function
-- Causa exacta: el CTE `producers` filtraba pg_proc por
-- `nspname = 'public' and lanname in ('plpgsql','sql')` y ademas
-- llamaba `pg_get_functiondef(p.oid) ~* '...'` en la MISMA lista de
-- condiciones del WHERE. Ese ultimo predicado solo depende de `p.oid`
-- (una sola tabla), asi que Postgres puede aplicarlo por predicate
-- pushdown directamente sobre el scan de pg_proc, ANTES de los joins
-- que debian restringirlo a funciones/procedimientos reales de
-- `public`. Postgres NO garantiza evaluar los terminos de un AND en
-- el orden escrito (solo CASE WHEN lo garantiza), y desde PG12 un
-- `WITH` simple ya no es una barrera de optimizacion automatica -- el
-- planner puede reordenar libremente. Resultado: pg_get_functiondef()
-- se ejecuto contra pg_catalog.array_agg (un agregado) antes de que el
-- filtro de esquema/lenguaje pudiera excluirlo.
--
-- Fix: el nuevo CTE `public_functions`, mas abajo, esta marcado
-- `MATERIALIZED` (barrera de optimizacion explicita, ya no implicita)
-- y filtra por `p.prokind in ('f', 'p')` -- solo funciones ('f') y
-- procedimientos ('p') reales, nunca agregados ('a') ni funciones
-- ventana ('w'). pg_get_functiondef() solo se llama DESPUES, sobre
-- oids ya materializados y garantizados validos, y ademas con un
-- `case when ... then ... else false end` como segunda barrera (CASE
-- si garantiza orden de evaluacion). SECURITY DEFINER tambien se lee
-- ahora de la columna nativa `pg_proc.prosecdef` en lugar de buscarlo
-- por texto, por ser mas confiable.
--
-- Como leerlo: columna `resultado`.
--   OK       -> la comprobacion paso.
--   REVISAR  -> algo no quedo como se esperaba; no sigas sin mirarlo.
--   LISTADO  -> inventario, una fila por objeto encontrado.
with
trg as (
	select
		c.relname as table_name,
		t.tgname as trigger_name,
		case t.tgenabled
			when 'O' then 'enabled'
			when 'D' then 'disabled'
			when 'R' then 'replica'
			when 'A' then 'always'
		end as enabled,
		fn.nspname || '.' || p.proname as function_name
	from pg_trigger t
		join pg_class c on c.oid = t.tgrelid
		join pg_namespace n on n.oid = c.relnamespace
		join pg_proc p on p.oid = t.tgfoid
		join pg_namespace fn on fn.oid = p.pronamespace
	where n.nspname = 'public'
		and c.relname in ('orders', 'order_status_history')
		and not t.tgisinternal
),
-- Barrera de optimizacion EXPLICITA: solo funciones ('f') y
-- procedimientos ('p') reales de public, nunca agregados ni funciones
-- ventana. MATERIALIZED impide que Postgres empuje o reordene
-- predicados de fuera hacia dentro de este CTE -- es la causa raiz del
-- 42809 explicada arriba.
public_functions as materialized (
	select
		p.oid,
		p.proname,
		n.nspname,
		p.prosecdef,
		p.prokind
	from pg_proc p
		join pg_namespace n on n.oid = p.pronamespace
	where n.nspname = 'public'
		and p.prokind in ('f', 'p')
),
aupd as (
	select
		pf.oid,
		pf.prosecdef,
		pg_get_functiondef(pf.oid) as def
	from public_functions pf
	where pf.proname = 'admin_update_order_status'
),
-- Cualquier funcion/procedimiento real del esquema public cuyo cuerpo
-- inserte en order_status_history: la lista completa de productores
-- posibles, sin depender de que algun archivo local los documente.
-- El `case` es una segunda barrera (ademas de MATERIALIZED arriba):
-- CASE WHEN si garantiza que solo se evalua pg_get_functiondef cuando
-- prokind ya es 'f'/'p', pase lo que pase con el orden que elija el
-- planner.
producers as (
	select distinct
		pf.nspname || '.' || pf.proname as function_name
	from public_functions pf
	where case
		when pf.prokind in ('f', 'p')
			then pg_get_functiondef(pf.oid) ~* 'insert\s+into\s+(public\.)?order_status_history'
		else false
	end
)

-- ---------- A) El trigger redundante quedo fuera ----------
select
	'01' as orden,
	'A. Trigger redundante' as bloque,
	'orders_log_status_change ya no esta sobre public.orders' as comprobacion,
	case
		when exists (select 1 from trg where trigger_name = 'orders_log_status_change')
			then 'REVISAR'
		else 'OK'
	end as resultado,
	coalesce(
		(
			select 'SIGUE PRESENTE (estado: ' || enabled || ', funcion: ' || function_name || ')'
			from trg
			where trigger_name = 'orders_log_status_change'
		),
		'no existe ningun trigger con ese nombre sobre orders'
	) as detalle

-- ---------- B) log_order_status_change conservada (huerfana) ----------
union all
select
	'02',
	'A. Trigger redundante',
	'la funcion public.log_order_status_change NO fue eliminada',
	case
		when exists (select 1 from public_functions where proname = 'log_order_status_change')
			then 'OK'
		else 'REVISAR'
	end,
	'el fix solo debia quitar el trigger; la funcion debe seguir existiendo, sin que nada la dispare'

-- ---------- C) Triggers que debian conservarse ----------
union all
select
	'03',
	'B. Triggers conservados',
	'orders_create_initial_history sigue presente y habilitado',
	coalesce(
		(
			select case when enabled = 'enabled' then 'OK' else 'REVISAR' end
			from trg
			where trigger_name = 'orders_create_initial_history'
		),
		'REVISAR'
	),
	coalesce(
		(
			select 'estado: ' || enabled || ', funcion: ' || function_name
			from trg
			where trigger_name = 'orders_create_initial_history'
		),
		'NO ENCONTRADO sobre orders/order_status_history'
	)

union all
select
	'04',
	'B. Triggers conservados',
	'orders_set_updated_at sigue presente y habilitado',
	coalesce(
		(
			select case when enabled = 'enabled' then 'OK' else 'REVISAR' end
			from trg
			where trigger_name = 'orders_set_updated_at'
		),
		'REVISAR'
	),
	coalesce(
		(
			select 'estado: ' || enabled || ', funcion: ' || function_name
			from trg
			where trigger_name = 'orders_set_updated_at'
		),
		'NO ENCONTRADO sobre orders/order_status_history'
	)

-- ---------- D) admin_update_order_status intacta ----------
union all
select
	'05',
	'C. admin_update_order_status',
	'existe una sola firma activa (sin sobrecargas duplicadas)',
	case
		when (select count(*) from aupd) = 1 then 'OK'
		else 'REVISAR'
	end,
	'versiones activas encontradas: ' || (select count(*)::text from aupd)

union all
select
	'06',
	'C. admin_update_order_status',
	'sigue siendo SECURITY DEFINER',
	case
		when exists (select 1 from aupd where prosecdef) then 'OK'
		else 'REVISAR'
	end,
	'leido de pg_proc.prosecdef (columna nativa, no texto) para cada oid activo'

union all
select
	'07',
	'C. admin_update_order_status',
	'conserva su INSERT hacia order_status_history',
	case
		when exists (select 1 from aupd where def ~* 'insert\s+into\s+(public\.)?order_status_history')
			then 'OK'
		else 'REVISAR'
	end,
	'es el productor canonico que debe quedar: sin este INSERT no se registraria ningun cambio de estado'

union all
select
	'08',
	'C. admin_update_order_status',
	'sigue registrando changed_by = auth.uid()',
	case
		when exists (select 1 from aupd where def ~* 'auth\.uid\(\)') then 'OK'
		else 'REVISAR'
	end,
	'la identidad del admin es justo lo que el trigger perdia (changed_by NULL)'

union all
select
	'09',
	'C. admin_update_order_status',
	'conserva ORDER_STATUS_CANCELLED_FINAL (cancelado como estado terminal)',
	case
		when exists (select 1 from aupd where def ~* 'ORDER_STATUS_CANCELLED_FINAL') then 'OK'
		else 'REVISAR'
	end,
	'este fix NO debia tocar la logica de cancelacion; debe seguir presente tal cual estaba'

union all
select
	'10',
	'C. admin_update_order_status',
	'conserva la logica de stock_movements / cancellation_restock',
	case
		when exists (
			select 1 from aupd
			where def ~* 'stock_movements' and def ~* 'cancellation_restock'
		) then 'OK'
		else 'REVISAR'
	end,
	'este fix NO debia tocar reposicion de stock; ambos terminos deben seguir presentes'

union all
select
	'11',
	'C. admin_update_order_status',
	'la funcion no fue reemplazada (huella por oid)',
	'LISTADO',
	'oid actual: ' || coalesce((select string_agg(oid::text, ', ' order by oid) from aupd), 'ninguno')
		|| ' -- compara contra el oid que devolvio diagnose_admin_update_order_status_runtime.sql ANTES del fix; si coincide, la funcion no se recreo'

-- ---------- E) Inventario final ----------
union all
select
	'12',
	'D. Triggers actuales',
	trg.table_name || ' -> ' || trg.trigger_name,
	'LISTADO',
	'estado: ' || trg.enabled || ' | ejecuta: ' || trg.function_name
from trg

union all
select
	'13',
	'D. Productores restantes de order_status_history',
	producers.function_name,
	'LISTADO',
	'se espera EXACTAMENTE: admin_update_order_status (RPC, unico productor de cambios de estado), la funcion detras de orders_create_initial_history (primera entrada al crear el pedido) y log_order_status_change (huerfana: existe pero ya no la dispara nada)'
from producers

order by orden, comprobacion;
