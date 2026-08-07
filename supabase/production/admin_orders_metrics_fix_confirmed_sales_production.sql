-- NO EJECUTADO CONTRA SUPABASE REMOTO. Preparado localmente para que el
-- propietario del proyecto lo revise y lo corra el mismo (Dashboard de
-- Supabase -> SQL Editor -> pegar TODO este archivo -> Run).
--
-- REQUIERE que admin_dashboard_summary_v4_production.sql ya este
-- aplicado en el proyecto remoto (crea public.admin_dashboard_summary_v4()).
-- Aplicar ese archivo PRIMERO, este DESPUES.
--
-- Causa del bug observado ("Ventas confirmadas" = S/ 0.00 en la pestana
-- Pedidos, aunque haya un pedido con order_status = payment_verified y
-- tres con order_status = delivered): admin_orders_metrics() (creada en
-- admin_orders_dashboard_production.sql) calculaba confirmed_sales_total
-- / confirmed_sales_count con `orders.payment_status = 'verified'`. Esa
-- columna existe en la tabla pero ningun camino de escritura del repo la
-- toca -- ni create_order_v2 (harden_stock_atomic.sql) ni
-- admin_update_order_status (admin_update_order_status_production.sql)
-- -- asi que siempre esta en su valor por defecto y el filtro nunca
-- encuentra filas. No es un problema de aplicacion (la funcion si esta
-- viva en produccion, por eso total_orders/orders_today/orders_by_status
-- cargan bien): es un criterio de negocio construido sobre una columna
-- muerta.
--
-- Correccion: en vez de duplicar aqui el criterio correcto (ya escrito y
-- razonado en admin_dashboard_summary_v4_production.sql: order_status =
-- payment_verified o delivered, o evidencia real en order_payments
-- verificado, siempre excluyendo cancelado), admin_orders_metrics llama
-- una vez a public.admin_dashboard_summary_v4() y reutiliza
-- confirmed_sales_value/confirmed_sales_count de ahi. Una sola fuente de
-- verdad para "ventas confirmadas" en todo el panel (Resumen y Pedidos),
-- nada de logica duplicada. total_orders, orders_today y
-- orders_by_status no cambian: siguen calculandose igual que antes,
-- directamente contra orders.
--
-- Migracion INCREMENTAL: create or replace sobre la misma firma
-- (sin parametros, misma tabla de salida de 5 columnas), mismos permisos
-- (security definer, search_path = '', solo authenticated con EXECUTE).
-- No toca admin_users, is_admin, admin_list_orders, admin_list_orders_v2,
-- admin_get_order_detail, admin_update_order_status, ni ninguna tabla.

create or replace function public.admin_orders_metrics () returns table (
	total_orders bigint,
	orders_today bigint,
	orders_by_status jsonb,
	confirmed_sales_total numeric,
	confirmed_sales_count bigint
) language plpgsql security definer
set
	search_path = '' as $$
declare
	v_summary jsonb;
begin
	if not public.is_admin() then
		raise exception 'ADMIN_FORBIDDEN';
	end if;

	-- Unica llamada al resumen v4: de ahi solo se leen los dos campos de
	-- ventas confirmadas, ya calculados con el criterio correcto.
	v_summary := public.admin_dashboard_summary_v4();

	return query
	select
		(select count(*) from public.orders)::bigint as total_orders,
		(
			select count(*)
			from public.orders o
			where (o.created_at at time zone 'America/Lima')::date
				= (now() at time zone 'America/Lima')::date
		)::bigint as orders_today,
		(
			-- unnest(enum_range(...)) garantiza las 11 claves siempre
			-- presentes (con 0), igual que antes.
			select coalesce(jsonb_object_agg(s.status_label::text, s.cnt), '{}'::jsonb)
			from (
				select os.status_label, count(o.id) as cnt
				from unnest(enum_range(null::public.order_status)) as os (status_label)
					left join public.orders o on o.order_status = os.status_label
				group by os.status_label
			) s
		) as orders_by_status,
		coalesce((v_summary ->> 'confirmed_sales_value')::numeric, 0) as confirmed_sales_total,
		coalesce((v_summary ->> 'confirmed_sales_count')::bigint, 0) as confirmed_sales_count;
end;
$$;

comment on function public.admin_orders_metrics () is 'Metricas de solo lectura para el panel admin: total, pedidos de hoy (America/Lima), conteo por order_status, y ventas confirmadas reutilizando admin_dashboard_summary_v4() (payment_verified/delivered/evidencia en order_payments) en vez del abandonado orders.payment_status. Exige is_admin().';

-- create function concede EXECUTE a PUBLIC por defecto: se revoca
-- explicitamente antes de conceder nada, igual que la version anterior.
revoke
execute on function public.admin_orders_metrics ()
from
	public,
	anon,
	authenticated;

grant
execute on function public.admin_orders_metrics () to authenticated;

-- ============================================================
-- Fin. No se concede ningun grant nuevo. Para verificar, correr a
-- continuacion supabase/verify_admin_orders_metrics_fix.sql (solo
-- SELECT).
-- ============================================================
