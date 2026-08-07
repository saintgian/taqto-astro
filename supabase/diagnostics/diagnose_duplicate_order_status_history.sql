-- SOLO LECTURA. No modifica pedidos, stock, order_status_history,
-- funciones ni permisos. No crea nada, no necesita BEGIN/ROLLBACK.
-- NO EJECUTADO CONTRA SUPABASE REMOTO todavia: preparado para que el
-- propietario del proyecto lo corra el mismo (Dashboard de Supabase ->
-- SQL Editor -> pegar TODO este archivo -> Run) y revise cada bloque.
--
-- Objetivo: determinar si TAQ-2026-000012 y TAQ-2026-000013 tienen
-- realmente DOS filas persistidas en order_status_history para la
-- transicion Recibido -> Cancelado, o si el panel admin esta mostrando
-- una sola fila real mas algo sintetizado/duplicado en frontend o RPC.
-- (El analisis de src/pages/admin/pedidos.astro ya descarta la parte de
-- frontend: el historial se pinta con un simple .map() sobre el arreglo
-- que devuelve admin_get_order_detail, sin agregar entradas locales
-- optimistas y sin acumular entre renders -- cada carga reemplaza
-- currentOrderDetail entero. admin_update_order_status, en las dos
-- versiones locales del RPC, hace exactamente UN insert explicito hacia
-- order_status_history por ejecucion. Si aparecen dos filas reales por
-- transicion, la sospecha principal es un trigger sobre `orders` o
-- sobre `order_status_history` que no esta en ningun archivo local del
-- repo -- por eso este script tambien vuelca todos los triggers y sus
-- funciones, no solo las filas.)

-- ============================================================
-- 1) Identificar ambos pedidos
-- ============================================================
select
	id as order_id,
	order_number,
	order_status,
	created_at,
	updated_at
from public.orders
where order_number in ('TAQ-2026-000012', 'TAQ-2026-000013')
order by order_number;

-- ============================================================
-- 2) Filas REALES persistidas en order_status_history para esos
--    pedidos, con precision de milisegundos para poder distinguir dos
--    filas casi simultaneas. Incluye toda columna que pueda servir de
--    "fuente" (changed_by / note) para diferenciar quien inserto cada
--    fila.
-- ============================================================
select
	h.id as history_id,
	o.order_number,
	h.order_id,
	h.previous_status,
	h.new_status,
	to_char(h.created_at, 'YYYY-MM-DD HH24:MI:SS.MS') as created_at_ms,
	h.changed_by,
	u.email as changed_by_email,
	h.note
from public.order_status_history h
	join public.orders o on o.id = h.order_id
	left join auth.users u on u.id = h.changed_by
where o.order_number in ('TAQ-2026-000012', 'TAQ-2026-000013')
order by o.order_number, h.created_at asc, h.id asc;

-- ============================================================
-- 3) Numero total de entradas por transicion (pedido, estado anterior,
--    estado nuevo). Si alguna transicion real (por ejemplo
--    received -> cancelled) muestra count > 1, hay duplicacion real en
--    base de datos, no solo visual.
-- ============================================================
select
	o.order_number,
	h.previous_status,
	h.new_status,
	count(*) as entradas,
	array_agg(h.id order by h.created_at) as history_ids,
	array_agg(
		to_char(h.created_at, 'YYYY-MM-DD HH24:MI:SS.MS')
		order by h.created_at
	) as timestamps
from public.order_status_history h
	join public.orders o on o.id = h.order_id
where o.order_number in ('TAQ-2026-000012', 'TAQ-2026-000013')
group by o.order_number, h.previous_status, h.new_status
order by o.order_number, min(h.created_at);

-- ============================================================
-- 4) Definicion EXACTA de la(s) version(es) de admin_update_order_status
--    que estan realmente vigentes en produccion ahora mismo. Hay dos
--    candidatas distintas en el repo local (una sin reposicion de stock
--    ni estado terminal, en admin_update_order_status_production.sql;
--    otra con ORDER_STATUS_CANCELLED_FINAL + reposicion de stock, en
--    stock_movements_ledger_production.sql, marcada ahi como "NO
--    EJECUTADA"). El sintoma reportado (reactivacion rechazada con
--    ORDER_STATUS_CANCELLED_FINAL) solo existe en la segunda version,
--    asi que probablemente SI esta vigente pese al comentario del
--    archivo -- esta consulta lo confirma sin ambiguedad. Si aparece
--    mas de una fila, hay sobrecargas duplicadas de la funcion (otra
--    posible causa de comportamiento inesperado).
-- ============================================================
select
	p.oid as function_oid,
	pg_get_function_identity_arguments(p.oid) as signature,
	p.prosecdef as security_definer,
	pg_get_functiondef(p.oid) as full_definition
from pg_proc p
	join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
	and p.proname = 'admin_update_order_status';

select count(*) as admin_update_order_status_overload_count
from pg_proc p
	join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
	and p.proname = 'admin_update_order_status';

-- ============================================================
-- 5) TODOS los triggers sobre public.orders y sobre
--    public.order_status_history, via catalogos nativos de Postgres
--    (no depende de que algun archivo local los documente). Si aparece
--    cualquier trigger aqui que no sea uno esperado (por ejemplo uno
--    de updated_at), es un candidato directo a productor duplicado del
--    historial.
-- ============================================================
select
	c.relname as table_name,
	t.tgname as trigger_name,
	t.tgenabled as enabled_status, -- 'O' = enabled (origin), 'D' = disabled
	pg_get_triggerdef(t.oid) as trigger_definition
from pg_trigger t
	join pg_class c on c.oid = t.tgrelid
	join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
	and c.relname in ('orders', 'order_status_history')
	and not t.tgisinternal
order by c.relname, t.tgname;

-- ============================================================
-- 6) Definicion completa de cada funcion ejecutada por esos triggers
--    (si el bloque 5 no devuelve filas, este bloque tambien vendra
--    vacio -- confirma que no hay trigger produciendo la segunda fila).
-- ============================================================
select distinct
	p.oid as function_oid,
	n.nspname || '.' || p.proname as function_name,
	pg_get_functiondef(p.oid) as full_definition
from pg_trigger t
	join pg_class c on c.oid = t.tgrelid
	join pg_namespace cn on cn.oid = c.relnamespace
	join pg_proc p on p.oid = t.tgfoid
	join pg_namespace n on n.oid = p.pronamespace
where cn.nspname = 'public'
	and c.relname in ('orders', 'order_status_history')
	and not t.tgisinternal;

-- ============================================================
-- 7) Columnas reales de order_status_history (por si existe alguna
--    columna extra no documentada en los archivos locales -- p. ej. un
--    "source" o "actor_type" -- que distinga una fila de RPC de una
--    fila de trigger).
-- ============================================================
select column_name, data_type, udt_name, is_nullable, column_default
from information_schema.columns
where table_schema = 'public'
	and table_name = 'order_status_history'
order by ordinal_position;

-- ============================================================
-- 8) Contexto de auditoria adicional: reglas (pg_rules) y otros
--    objetos con "instead of"/"also" sobre estas dos tablas, que
--    tambien podrian insertar sin ser un trigger clasico. Esperado: 0
--    filas (el proyecto no usa reglas en ningun otro archivo local).
-- ============================================================
select
	schemaname,
	tablename,
	rulename,
	definition
from pg_rules
where schemaname = 'public'
	and tablename in ('orders', 'order_status_history');
