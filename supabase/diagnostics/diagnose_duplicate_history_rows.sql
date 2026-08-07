-- SOLO LECTURA. Un unico SELECT, sin INSERT/UPDATE/DELETE/ALTER/DROP/
-- CREATE OR REPLACE/DO. No modifica pedidos, stock, order_status_history,
-- funciones ni permisos. No necesita BEGIN/ROLLBACK.
-- NO EJECUTADO CONTRA SUPABASE REMOTO todavia: preparado para que el
-- propietario del proyecto lo corra el mismo (Dashboard de Supabase ->
-- SQL Editor -> pegar TODO este archivo -> Run).
--
-- Motivo de dividirlo en su propio archivo: el SQL Editor de Supabase
-- solo muestra el ultimo result set de un script con varios SELECT, asi
-- que diagnose_duplicate_order_status_history.sql (que tiene 8 bloques)
-- solo dejaba ver el bloque final (columnas de la tabla), nunca las filas
-- reales que hacen falta para comparar visualmente. Este archivo tiene
-- una unica consulta para que su resultado sea siempre el que se ve.
--
-- Objetivo: listar las filas FISICAS reales persistidas en
-- public.order_status_history para TAQ-2026-000012 y TAQ-2026-000013,
-- para poder comprobar a ojo si la transicion Recibido -> Cancelado
-- tiene uno o dos UUID (history_id) distintos.
select
	h.id as history_id,
	h.order_id,
	o.order_number,
	to_char(h.created_at, 'YYYY-MM-DD HH24:MI:SS.MS') as created_at_ms,
	h.previous_status,
	h.new_status,
	h.note,
	h.changed_by
from public.order_status_history h
	join public.orders o on o.id = h.order_id
where o.order_number in ('TAQ-2026-000012', 'TAQ-2026-000013')
order by o.order_number, h.created_at asc, h.id asc;
