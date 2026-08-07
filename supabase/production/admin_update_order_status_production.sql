-- NO EJECUTADO CONTRA SUPABASE REMOTO. Preparado localmente para que el
-- propietario del proyecto lo revise y lo corra el mismo (Dashboard de
-- Supabase -> SQL Editor -> pegar TODO este archivo -> Run).
--
-- Fase 2 del panel administrativo de pedidos (/admin/pedidos/):
-- cambio de estado de un pedido. Migracion INCREMENTAL: no recrea nada
-- de la Fase 1 (admin_users, is_admin, admin_orders_metrics,
-- admin_list_orders, admin_get_order_detail siguen intactos, tal como
-- los dejo admin_orders_dashboard_production.sql). Tampoco toca
-- create_order_v2, catalog_mirror, harden_create_order,
-- harden_permissions ni harden_stock_atomic.
--
-- Version de PRODUCCION: solo objetos persistentes. Sin BEGIN/ROLLBACK,
-- sin tablas temporales, sin pedidos ni usuarios de prueba, sin UUID
-- ficticios, sin bloques DO destructivos. La verificacion vive en un
-- archivo separado de solo lectura: verify_admin_update_order_status.sql
--
-- Esquema real utilizado (columnas ya verificadas por introspeccion en
-- la Fase 1, ninguna inventada aqui):
--   orders: id (uuid), order_number (text), order_status
--     (public.order_status), updated_at (timestamptz)
--   order_status_history: id, order_id, created_at, previous_status,
--     new_status, note, changed_by
--
-- No se altera order_status_history: ya tiene columnas equivalentes para
-- pedido, estado anterior, estado nuevo, fecha (created_at con default),
-- administrador (changed_by) y nota (note). No se crea ninguna tabla
-- paralela.
--
-- Reglas de transicion: el proyecto no documenta ninguna maquina de
-- estados, asi que aqui NO se inventa una. La funcion acepta cualquier
-- valor valido del enum distinto del actual; las confirmaciones extra
-- (cancelar, o corregir un pedido ya entregado/cancelado) viven en la
-- interfaz, y todo cambio queda registrado en el historial.

-- ============================================================
-- RPC: cambiar el estado de un pedido
-- ============================================================

create or replace function public.admin_update_order_status (
	p_order_id uuid,
	p_expected_status public.order_status,
	p_new_status public.order_status,
	p_note text default null
) returns jsonb language plpgsql security definer
set
	search_path = '' as $$
declare
	-- auth.uid() es la UNICA fuente de identidad del administrador. La
	-- funcion no acepta ningun user_id del navegador: no existe tal
	-- parametro, asi que no hay forma de suplantar a otro admin.
	v_admin uuid := auth.uid();
	v_current public.order_status;
	v_order_number text;
	v_updated_at timestamptz;
	-- Nota opcional: se recortan espacios exteriores, vacio equivale a
	-- "sin nota" y se limita a 400 caracteres para que un pegado
	-- accidental no llene la tabla.
	v_note text := nullif(btrim(coalesce(p_note, '')), '');
begin
	-- Sesion autenticada + fila activa en admin_users. security definer
	-- es imprescindible aqui: `authenticated` no tiene (ni debe tener)
	-- ningun grant directo sobre orders ni order_status_history.
	if v_admin is null or not public.is_admin() then
		raise exception 'ADMIN_FORBIDDEN';
	end if;

	-- Los enums ya rechazan cualquier texto que no sea un estado real
	-- (Postgres falla al castear antes de entrar aqui); esto cubre el
	-- caso de un null explicito.
	if p_order_id is null or p_expected_status is null or p_new_status is null then
		raise exception 'INVALID_ORDER_STATUS';
	end if;

	if v_note is not null and length(v_note) > 400 then
		v_note := left(v_note, 400);
	end if;

	-- FOR UPDATE bloquea la fila hasta el final de la funcion (una sola
	-- transaccion implicita): dos pestanas que intenten cambiar el mismo
	-- pedido a la vez se serializan, y la segunda vera el estado ya
	-- actualizado por la primera y fallara con ORDER_STATUS_CONFLICT en
	-- lugar de pisar el cambio.
	select o.order_status, o.order_number
	into v_current, v_order_number
	from public.orders o
	where o.id = p_order_id
	for update;

	if not found then
		raise exception 'ORDER_NOT_FOUND';
	end if;

	-- Control de concurrencia optimista: el cliente manda el estado que
	-- tenia cargado en pantalla. Si no coincide con el real, alguien mas
	-- ya lo cambio.
	if v_current is distinct from p_expected_status then
		raise exception 'ORDER_STATUS_CONFLICT';
	end if;

	if p_new_status = v_current then
		raise exception 'ORDER_STATUS_UNCHANGED';
	end if;

	update public.orders
	set
		order_status = p_new_status,
		updated_at = now()
	where id = p_order_id
	returning updated_at into v_updated_at;

	insert into public.order_status_history (
		order_id,
		previous_status,
		new_status,
		note,
		changed_by
	)
	values (
		p_order_id,
		v_current,
		p_new_status,
		v_note,
		v_admin
	);

	-- Solo datos del pedido afectado. Nada de otros pedidos, ningun
	-- token, ningun dato de pago.
	return jsonb_build_object(
		'order_id', p_order_id,
		'order_number', v_order_number,
		'previous_status', v_current,
		'new_status', p_new_status,
		'updated_at', v_updated_at
	);
end;
$$;

comment on function public.admin_update_order_status (
	uuid,
	public.order_status,
	public.order_status,
	text
) is 'Cambia el estado de un pedido desde el panel admin. Atomico: bloquea la fila con FOR UPDATE, exige que el estado actual coincida con p_expected_status (ORDER_STATUS_CONFLICT si no) y registra el cambio en order_status_history con changed_by = auth.uid(). Exige is_admin(). Errores: ADMIN_FORBIDDEN, ORDER_NOT_FOUND, ORDER_STATUS_CONFLICT, ORDER_STATUS_UNCHANGED, INVALID_ORDER_STATUS.';

-- create function concede EXECUTE a PUBLIC por defecto: se revoca
-- explicitamente antes de conceder nada.
revoke
execute on function public.admin_update_order_status (
	uuid,
	public.order_status,
	public.order_status,
	text
)
from
	public,
	anon,
	authenticated;

grant
execute on function public.admin_update_order_status (
	uuid,
	public.order_status,
	public.order_status,
	text
) to authenticated;

-- ============================================================
-- Fin. No se concede ningun grant nuevo sobre orders ni sobre
-- order_status_history: el unico camino de escritura sigue siendo este
-- RPC. Para verificar, correr a continuacion
-- supabase/verify_admin_update_order_status.sql (solo SELECT).
-- ============================================================
