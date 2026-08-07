-- Solo lectura. No modifica datos, no crea nada. Correr DESPUES de
-- stock_movements_ledger_production.sql, revisar cada resultado a mano
-- ANTES de confiar en el mecanismo con pedidos reales.

-- 1) Existencia de la tabla y de la restriccion UNIQUE que garantiza la
-- idempotencia.
select
	c.relname as tabla,
	con.conname as restriccion,
	con.contype as tipo
from pg_constraint con
	join pg_class c on c.oid = con.conrelid
where c.relname = 'stock_movements'
	and con.contype = 'u';
-- esperado: una fila, tipo 'u' (unique), sobre (order_id, variant_id,
-- movement_type).

-- 2) RLS activo y sin grants directos para anon/authenticated.
select relrowsecurity
from pg_class
where relname = 'stock_movements';
-- esperado: true.

select grantee, privilege_type
from information_schema.role_table_grants
where table_schema = 'public'
	and table_name = 'stock_movements'
	and grantee in ('anon', 'authenticated');
-- esperado: 0 filas.

-- 3) Firma y seguridad de las dos funciones modificadas.
select
	p.proname,
	pg_get_userbyid(p.proowner) as owner,
	p.prosecdef as is_security_definer,
	p.proconfig
from pg_proc p
	join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
	and p.proname in ('create_order_v2', 'admin_update_order_status');
-- esperado: prosecdef = true en ambas.

-- 4) ACL de create_order_v2: solo 'anon' (mismo criterio que hoy, el
-- checkout publico no requiere sesion). ACL de admin_update_order_status:
-- solo 'authenticated'.
select routine_name, grantee, privilege_type
from information_schema.role_routine_grants
where routine_schema = 'public'
	and routine_name in ('create_order_v2', 'admin_update_order_status')
order by routine_name, grantee;

-- 5) Prueba funcional MANUAL (no ejecutar sin supervision; requiere un
-- pedido de prueba real creado via el checkout, no UUIDs inventados):
--   a) crear un pedido de prueba;
--   b) select * from public.stock_movements where order_id = '<id>';
--      esperado: una fila 'order_deduction' por cada item, con la
--      cantidad correcta.
--   c) tomar nota de catalog_variants.stock_quantity ANTES de cancelar;
--   d) cancelar el pedido de prueba via admin_update_order_status;
--   e) select * from public.stock_movements where order_id = '<id>';
--      esperado: ahora tambien una fila 'cancellation_restock' por cada
--      variante, con la misma cantidad que su 'order_deduction'.
--   f) confirmar que catalog_variants.stock_quantity volvio exactamente
--      a su valor de antes de crear el pedido de prueba (ni mas ni
--      menos).
--   g) reintentar el mismo cambio de estado (llamar de nuevo
--      admin_update_order_status con el mismo p_expected_status =
--      'cancelled' ya no aplica -- deberia fallar con
--      ORDER_STATUS_UNCHANGED, que es la barrera principal) para
--      confirmar que no hay una segunda reposicion posible.
--   h) intentar mover ese mismo pedido (ya cancelado) a cualquier otro
--      estado activo -- esperado: falla con ORDER_STATUS_CANCELLED_FINAL,
--      order_status sigue en 'cancelled' y stock_quantity no cambia.

-- ============================================================
-- 6) Prueba automatizada dentro de una transaccion con ROLLBACK:
-- confirma que cancelar repone stock una sola vez y que un pedido
-- cancelado no se puede reactivar. No crea pedidos reales ni usuarios
-- nuevos: usa create_order_v2 (el mismo camino que el checkout publico)
-- sobre una variante activa real, y REUTILIZA un administrador YA
-- existente y activo en admin_users (no crea ninguno, no toca
-- auth.users) para simular su sesion con
-- set_config('request.jwt.claims', ...), que es como auth.uid() resuelve
-- la identidad en Supabase (funcion propia de la plataforma, no definida
-- en este repo, por lo que no se pudo confirmar su codigo exacto sin
-- conectarse -- si el entorno real difiere, los pasos 6d/6g quedaran
-- marcados como ERROR en vez de OMITIDO/ok, avisando del desajuste en
-- vez de fallar en silencio). Si no hay ningun admin activo, esos mismos
-- pasos se marcan 'OMITIDO' y el resto del script sigue. Todo se revierte
-- al final: ningun dato de esta seccion queda en la base.
-- ============================================================

begin;

create temporary table test_ctx as
select
	cv.sanity_product_id,
	cv.sku,
	(
		select enumlabel from pg_enum
		where enumtypid = 'public.payment_method'::regtype
		order by enumsortorder limit 1
	)::public.payment_method as payment_method,
	(
		select enumlabel from pg_enum
		where enumtypid = 'public.delivery_method'::regtype
		order by enumsortorder limit 1
	)::public.delivery_method as delivery_method
from public.catalog_variants cv
where cv.active = true
limit 1;

update public.catalog_variants cv
set stock_quantity = 10
from test_ctx tc
where cv.sanity_product_id = tc.sanity_product_id
	and cv.sku = tc.sku;

create temporary table test_admin as
select user_id from public.admin_users where active = true limit 1;

create temporary table test_results (step text, result text);

-- 6a) Pedido de prueba: 1 item, cantidad 2.
do $$
declare
	v_pid text;
	v_sku text;
	v_pm public.payment_method;
	v_dm public.delivery_method;
	v_order text;
begin
	select sanity_product_id, sku, payment_method, delivery_method
	into v_pid, v_sku, v_pm, v_dm from test_ctx;

	v_order := public.create_order_v2(
		v_pm, v_dm, 'Prueba', 'Ledger', 'prueba-ledger@example.com', '999999995',
		'Lima', 'Lima', 'Miraflores', 'Av. Prueba 321', null, null,
		jsonb_build_array(jsonb_build_object(
			'sanityProductId', v_pid, 'productSku', v_sku,
			'sanityProductSlug', 'prueba', 'productName', 'Prueba',
			'quantity', 2, 'unitPrice', 1
		)),
		'test-ledger-001'
	);
	insert into test_results values ('6a_pedido_creado', 'order=' || v_order);
exception when others then
	insert into test_results values ('6a_pedido_creado', 'ERROR: ' || sqlerrm);
end $$;

create temporary table test_order as
select id, order_status from public.orders where client_request_id = 'test-ledger-001';

insert into test_results
select '6b_stock_tras_pedido', stock_quantity::text
from public.catalog_variants cv join test_ctx tc
	on cv.sanity_product_id = tc.sanity_product_id and cv.sku = tc.sku;
-- esperado: 8 (10 - 2)

insert into test_results
select '6c_deducciones_registradas', count(*)::text || ' fila(s), cantidad=' || coalesce(sum(quantity)::text, '0')
from public.stock_movements sm join test_order o on o.id = sm.order_id
where sm.movement_type = 'order_deduction';
-- esperado: 1 fila(s), cantidad=2

-- 6d) Cancelar (requiere sesion admin simulada; se omite si no hay
-- ningun admin activo).
do $$
declare
	v_admin uuid;
	v_order_id uuid;
	v_current public.order_status;
	v_result jsonb;
begin
	select user_id into v_admin from test_admin;
	select id, order_status into v_order_id, v_current from test_order;

	if v_admin is null then
		insert into test_results values ('6d_cancelar', 'OMITIDO: no hay ningun admin activo en admin_users para simular la sesion');
		return;
	end if;

	perform set_config('request.jwt.claims', jsonb_build_object('sub', v_admin)::text, true);

	v_result := public.admin_update_order_status(v_order_id, v_current, 'cancelled'::public.order_status, 'prueba automatizada');
	insert into test_results values ('6d_cancelar', v_result::text);
exception when others then
	insert into test_results values ('6d_cancelar', 'ERROR: ' || sqlerrm);
end $$;

insert into test_results
select '6e_stock_tras_cancelar', stock_quantity::text
from public.catalog_variants cv join test_ctx tc
	on cv.sanity_product_id = tc.sanity_product_id and cv.sku = tc.sku;
-- esperado (solo si 6d no fue OMITIDO): 10 -- exactamente lo descontado,
-- ni mas ni menos

insert into test_results
select '6f_restocks_registrados', count(*)::text || ' fila(s), cantidad=' || coalesce(sum(quantity)::text, '0')
from public.stock_movements sm join test_order o on o.id = sm.order_id
where sm.movement_type = 'cancellation_restock';
-- esperado (solo si 6d no fue OMITIDO): 1 fila(s), cantidad=2

-- 6g) Intentar reactivar el pedido ya cancelado: debe fallar con
-- ORDER_STATUS_CANCELLED_FINAL, sin tocar stock ni order_status.
do $$
declare
	v_admin uuid;
	v_order_id uuid;
	v_target public.order_status;
begin
	select user_id into v_admin from test_admin;
	select id into v_order_id from test_order;

	if v_admin is null then
		insert into test_results values ('6g_reactivar', 'OMITIDO: no hay ningun admin activo en admin_users para simular la sesion');
		return;
	end if;

	select t.status_label into v_target
	from unnest(enum_range(null::public.order_status)) as t (status_label)
	where t.status_label <> 'cancelled'::public.order_status
	limit 1;

	perform set_config('request.jwt.claims', jsonb_build_object('sub', v_admin)::text, true);

	perform public.admin_update_order_status(v_order_id, 'cancelled'::public.order_status, v_target, 'intento de reactivacion');
	insert into test_results values ('6g_reactivar', 'FALLO: no debio permitir la reactivacion');
exception when others then
	insert into test_results values ('6g_reactivar', 'ERROR (esperado ORDER_STATUS_CANCELLED_FINAL): ' || sqlerrm);
end $$;

insert into test_results
select '6h_stock_tras_intento_reactivar', stock_quantity::text
from public.catalog_variants cv join test_ctx tc
	on cv.sanity_product_id = tc.sanity_product_id and cv.sku = tc.sku;
-- esperado: igual que 6e -- el intento fallido de reactivar no debe
-- tocar stock

insert into test_results
select '6i_estado_final_pedido', order_status::text
from public.orders where id = (select id from test_order);
-- esperado: 'cancelled' (sin cambio)

select * from test_results order by step;

rollback;

-- ============================================================
-- 7) Cobertura: cuantos pedidos NO tienen ninguna fila en
-- stock_movements (pedidos creados antes de aplicar este archivo --
-- limitacion documentada, no se les repone stock automaticamente si se
-- cancelan).
-- ============================================================
select count(*) as pedidos_sin_bitacora
from public.orders o
where not exists (
	select 1 from public.stock_movements sm where sm.order_id = o.id
);
