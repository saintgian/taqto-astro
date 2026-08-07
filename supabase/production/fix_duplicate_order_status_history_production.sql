-- NO EJECUTADO CONTRA SUPABASE REMOTO. Preparado localmente para que el
-- propietario del proyecto lo revise y lo corra el mismo (Dashboard de
-- Supabase -> SQL Editor -> pegar TODO este archivo -> Run).
--
-- ============================================================
-- Problema (demostrado en produccion, no supuesto)
-- ============================================================
-- Cada transicion de estado de un pedido produce DOS filas fisicas
-- distintas en public.order_status_history (UUID diferentes, mismo
-- created_at), porque hay DOS productores del mismo evento:
--
--   Fila A -> note = 'Estado actualizado', changed_by = NULL
--      Producida por el trigger orders_log_status_change
--      (AFTER UPDATE OF order_status ON public.orders) via la funcion
--      public.log_order_status_change. Pierde la identidad del admin
--      (changed_by NULL) y pisa la nota real con un texto generico.
--
--   Fila B -> note = NULL o la nota real, changed_by = <uuid del admin>
--      Producida por el INSERT explicito dentro de
--      public.admin_update_order_status, con changed_by = auth.uid().
--
-- ============================================================
-- Por que se elimina el TRIGGER y no el INSERT del RPC
-- ============================================================
--   1) admin_update_order_status es hoy el UNICO escritor de
--      order_status en toda la aplicacion (verificado por busqueda en
--      src/ y supabase/: los unicos `update public.orders set
--      order_status` del repo estan en
--      admin_update_order_status_production.sql:105 y
--      stock_movements_ledger_production.sql:598, ambos DENTRO de esa
--      misma funcion; el unico punto del frontend que cambia estado es
--      src/pages/admin/pedidos.astro:2840, que llama a ese RPC).
--   2) El RPC conserva informacion que el trigger destruye: changed_by
--      (auth.uid(), imposible de recuperar desde un trigger sin sesion)
--      y la nota escrita por el administrador.
--   3) El trigger no aporta nada que el RPC no registre ya.
--
-- ============================================================
-- Alcance: minimo y quirurgico
-- ============================================================
-- Este archivo hace UNA sola cosa: eliminar el trigger redundante
-- orders_log_status_change sobre public.orders.
--
-- NO elimina la funcion public.log_order_status_change (queda intacta,
--   por si algo mas la referencia y para poder recrear el trigger).
-- NO borra ni corrige ninguna fila historica ya duplicada (limpieza
--   aparte, deliberadamente fuera de este archivo).
-- NO modifica admin_update_order_status (ni su firma, ni su oid).
-- NO toca stock_movements, ni la reposicion de stock al cancelar, ni
--   ORDER_STATUS_CANCELLED_FINAL.
-- NO toca orders_create_initial_history (sigue creando la primera
--   entrada del historial al crear el pedido).
-- NO toca orders_set_updated_at.
-- NO toca permisos, grants, RLS ni policies.
--
-- ============================================================
-- ANTES DE CORRER ESTO: guarda tu rollback
-- ============================================================
-- diagnose_order_history_triggers.sql ya te devolvio el
-- pg_get_triggerdef() exacto de orders_log_status_change. GUARDA ESE
-- TEXTO: es la unica sentencia necesaria para recrear el trigger tal
-- cual estaba si alguna vez hiciera falta. El bloque de abajo tambien
-- lo emite por RAISE NOTICE justo antes de eliminarlo.
--
-- ============================================================
-- Riesgo conocido y aceptado
-- ============================================================
-- Tras eliminar el trigger, un cambio de order_status hecho A MANO
-- (Table Editor del dashboard, SQL Editor, service_role) ya NO quedara
-- registrado en order_status_history: solo se registra lo que pase por
-- admin_update_order_status. Es el precio de tener un unico productor.
-- Si en el futuro hiciera falta cambiar estados por fuera del panel, la
-- via correcta es llamar al RPC, no un UPDATE directo.

-- ============================================================
-- Eliminacion guardada e idempotente del trigger redundante
-- ============================================================
-- Es un bloque DO en lugar de un `drop trigger if exists` suelto para
-- poder (a) no hacer nada si ya fue eliminado, (b) ABORTAR sin tocar
-- nada si el trigger encontrado no es exactamente el esperado, y (c)
-- dejar el rollback impreso en la salida.
do $$
declare
	v_trigger_def text;
	v_function_name text;
begin
	select
		pg_get_triggerdef(t.oid),
		fn.nspname || '.' || p.proname
	into v_trigger_def, v_function_name
	from pg_trigger t
		join pg_class c on c.oid = t.tgrelid
		join pg_namespace n on n.oid = c.relnamespace
		join pg_proc p on p.oid = t.tgfoid
		join pg_namespace fn on fn.oid = p.pronamespace
	where n.nspname = 'public'
		and c.relname = 'orders'
		and t.tgname = 'orders_log_status_change'
		and not t.tgisinternal;

	-- (a) Idempotencia: correr este archivo dos veces no es un error.
	if not found then
		raise notice 'NADA QUE HACER: el trigger orders_log_status_change ya no existe sobre public.orders.';
		return;
	end if;

	-- (b) Guarda de identidad: si el trigger con ese nombre ejecutara
	-- otra funcion distinta de la diagnosticada, algo cambio desde el
	-- diagnostico y este archivo ya no es seguro. Se aborta la
	-- transaccion entera sin eliminar nada.
	if v_function_name is distinct from 'public.log_order_status_change' then
		raise exception 'ABORTADO: orders_log_status_change ejecuta % en lugar de public.log_order_status_change. No se elimino nada. Vuelve a correr diagnose_order_history_triggers.sql.', v_function_name;
	end if;

	-- (c) Rollback exacto, impreso antes de que deje de existir.
	raise notice 'ROLLBACK (guardar): %;', v_trigger_def;

	drop trigger orders_log_status_change on public.orders;

	raise notice 'LISTO: trigger orders_log_status_change eliminado de public.orders.';
	raise notice 'La funcion public.log_order_status_change NO fue eliminada: sigue existiendo, solo ya no la dispara ningun UPDATE de order_status.';
	raise notice 'A partir de ahora el unico productor de order_status_history en cambios de estado es admin_update_order_status (con changed_by = auth.uid()).';
end;
$$;

-- ============================================================
-- Fin. Las filas duplicadas YA EXISTENTES siguen ahi a proposito: este
-- archivo solo detiene la duplicacion futura. Para comprobar el
-- resultado, correr a continuacion
-- supabase/verify_duplicate_order_status_history_fix.sql (solo SELECT).
-- ============================================================
