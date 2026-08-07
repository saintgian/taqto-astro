-- NO EJECUTADO CONTRA SUPABASE REMOTO. Preparado localmente para que el
-- propietario del proyecto lo revise y lo corra el mismo (Dashboard de
-- Supabase -> SQL Editor -> pegar TODO este archivo -> Run).
--
-- Version de PRODUCCION: contiene unicamente objetos persistentes.
-- No contiene BEGIN/ROLLBACK, tablas temporales, usuarios de prueba,
-- UUID ficticios ni bloques DO de validacion. La verificacion post-
-- aplicacion vive en un archivo separado: verify_admin_orders_dashboard.sql
-- (solo SELECT, no modifica nada, se corre despues de este archivo).
--
-- Que es esto: Fase 1 del panel administrativo de pedidos
-- (/admin/pedidos/). Solo lectura: no cambia estados, no edita ni
-- borra pedidos, no toca stock, no reenvia correos, no ejecuta
-- accion comercial alguna. No modifica create_order_v2, catalog_mirror,
-- harden_create_order, harden_permissions ni harden_stock_atomic: esos
-- archivos siguen siendo la unica via de escritura del checkout
-- publico, intactos.
--
-- Principio de seguridad: el dashboard nunca lee `orders`/`order_items`/
-- `order_status_history`/`order_payments` directamente desde el
-- navegador. Toda lectura pasa por RPC `security definer` que exigen
-- sesion autenticada y verifican `public.is_admin()` antes de devolver
-- una sola fila. `anon` y `authenticated` sin fila activa en
-- `admin_users` no pueden leer nada de pedidos por ningun camino.
--
-- Esquema real verificado por introspeccion remota (information_schema +
-- pg_enum) antes de escribir este archivo -- ninguna columna, tabla o
-- valor de enum de abajo esta inventado:
--   enums: public.order_status (11 valores), public.payment_status (5),
--          public.payment_method (5), public.delivery_method (3)
--   orders: id, order_number, created_at, updated_at, order_status,
--     payment_status, payment_method, delivery_method,
--     customer_first_name, customer_last_name, customer_email,
--     customer_phone, customer_document_type, customer_document_number,
--     delivery_department, delivery_province, delivery_district,
--     delivery_address, delivery_reference, agency_name, subtotal,
--     delivery_cost, discount_total, total, currency, customer_notes,
--     internal_notes, public_tracking_token, client_request_id,
--     client_request_signature
--   order_items: id, order_id, created_at, sanity_product_id,
--     sanity_product_slug, product_name, product_sku, wood_name,
--     wood_slug, size_name, size_slug, dimensions_label, quantity,
--     unit_price, line_total, engraving_requested, engraving_type,
--     engraving_text, engraving_file_path, personalization_notes,
--     corporate_order, customer_logo_requested, taqto_brand_required
--   order_status_history: id, order_id, created_at, previous_status,
--     new_status, note, changed_by
--   order_payments: id, order_id, created_at, verified_at,
--     payment_method, payment_status, amount, currency, operation_code,
--     receipt_file_path, verification_notes
--
-- Deliberadamente NO expuesto por los RPC de abajo (secretos/tecnico
-- irrelevante, ver PARTE 4 de la tarea):
--   orders.client_request_id / client_request_signature (firma interna
--     de idempotencia del checkout, sin uso administrativo);
--   orders.public_tracking_token (token que da acceso de lectura publica
--     sin login a un pedido; exponerlo en el panel seria filtrar una
--     credencial);
--   order_items.engraving_file_path (ruta interna de storage, no un dato
--     que el admin necesite ver como texto plano en esta fase);
--   order_status_history.changed_by (UUID de otro admin; no hay gestion
--     de administradores en esta fase, no aporta sin esa pantalla);
--   order_payments completo (la tarea no lo pide explicitamente en el
--     detalle del pedido; `orders.payment_status` ya cubre el estado de
--     pago sin necesidad de este dato).

-- ============================================================
-- 1) Tabla de administradores
-- ============================================================

create table if not exists public.admin_users (
	user_id uuid primary key references auth.users (id) on delete cascade,
	active boolean not null default true,
	created_at timestamptz not null default now()
);

comment on table public.admin_users is 'Lista blanca de administradores del panel /admin/pedidos/. Sin lectura directa desde el navegador: solo public.is_admin() (security definer) la consulta.';

alter table public.admin_users enable row level security;

-- RLS activo y sin ninguna policy: deniega todo por defecto a cualquier
-- rol, incluido su propietario si accediera via PostgREST. Se revoca
-- ademas el grant de tabla explicitamente, por si alguna policy se
-- agrega mas adelante por error sin querer abrir acceso de tabla.
revoke all on public.admin_users
from
	public,
	anon,
	authenticated;

-- ============================================================
-- 2) Funcion de autorizacion
-- ============================================================

create or replace function public.is_admin () returns boolean language sql stable security definer
set
	search_path = '' as $$
	select exists (
		select 1
		from public.admin_users au
		where au.user_id = auth.uid()
			and au.active = true
	);
$$;

comment on function public.is_admin () is 'true si auth.uid() tiene una fila activa en admin_users. No acepta user_id del cliente: siempre usa la sesion actual. Solo la llaman internamente los RPC admin_* (security definer, corren como el propietario), por eso no se concede EXECUTE a ningun rol de cliente.';

-- Nadie externo necesita llamar a is_admin() directamente: los RPC
-- admin_* la usan desde su propio cuerpo security definer, lo que no
-- requiere que authenticated tenga EXECUTE sobre ella. Minimo privilegio
-- real, no solo nominal. create function concede EXECUTE a PUBLIC por
-- defecto: se revoca explicitamente aqui.
revoke
execute on function public.is_admin ()
from
	public,
	anon,
	authenticated;

-- ============================================================
-- 3) RPC: metricas
-- ============================================================

create or replace function public.admin_orders_metrics () returns table (
	total_orders bigint,
	orders_today bigint,
	orders_by_status jsonb,
	confirmed_sales_total numeric,
	confirmed_sales_count bigint
) language plpgsql security definer
set
	search_path = '' as $$
begin
	if not public.is_admin() then
		raise exception 'ADMIN_FORBIDDEN';
	end if;

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
			-- presentes (con 0), para que la UI no las haga aparecer y
			-- desaparecer segun haya o no pedidos en ese estado.
			select coalesce(jsonb_object_agg(s.status_label::text, s.cnt), '{}'::jsonb)
			from (
				select os.status_label, count(o.id) as cnt
				from unnest(enum_range(null::public.order_status)) as os (status_label)
					left join public.orders o on o.order_status = os.status_label
				group by os.status_label
			) s
		) as orders_by_status,
		-- "Ventas confirmadas": unico criterio que el esquema permite
		-- demostrar de forma fiable (payment_status = 'verified' es un
		-- estado explicito de pago confirmado). No se llama "ventas" a
		-- pedidos simplemente recibidos.
		(
			select coalesce(sum(o.total), 0)
			from public.orders o
			where o.payment_status = 'verified'::public.payment_status
		) as confirmed_sales_total,
		(
			select count(*)
			from public.orders o
			where o.payment_status = 'verified'::public.payment_status
		)::bigint as confirmed_sales_count;
end;
$$;

comment on function public.admin_orders_metrics () is 'Metricas de solo lectura para el panel admin: total, pedidos de hoy (America/Lima), conteo por order_status y ventas confirmadas (payment_status=verified). Exige is_admin().';

revoke
execute on function public.admin_orders_metrics ()
from
	public,
	anon,
	authenticated;

grant
execute on function public.admin_orders_metrics () to authenticated;

-- ============================================================
-- 4) RPC: listado de pedidos
-- ============================================================

create or replace function public.admin_list_orders (
	p_search text default null,
	p_status public.order_status default null,
	p_payment_method public.payment_method default null,
	p_delivery_method public.delivery_method default null,
	p_date_from date default null,
	p_date_to date default null,
	p_limit integer default 20,
	p_offset integer default 0
) returns table (
	id uuid,
	order_number text,
	created_at timestamptz,
	order_status public.order_status,
	customer_full_name text,
	customer_email text,
	customer_phone text,
	delivery_district text,
	payment_method public.payment_method,
	delivery_method public.delivery_method,
	total numeric,
	item_count bigint,
	unit_count bigint,
	has_engraving boolean,
	total_count bigint
) language plpgsql security definer
set
	search_path = '' as $$
declare
	-- Tope duro de 100 por pagina sin importar lo que pida el cliente.
	v_limit integer := least(greatest(coalesce(p_limit, 20), 1), 100);
	v_offset integer := greatest(coalesce(p_offset, 0), 0);
	-- nullif+trim: una busqueda vacia o solo espacios se trata como "sin
	-- busqueda", no como "cero resultados".
	v_search text := nullif(trim(coalesce(p_search, '')), '');
	-- Rango de fecha en zona horaria de Peru (America/Lima, sin DST), no
	-- UTC: un filtro "hoy" con input <input type="date"> debe cubrir el
	-- dia completo en hora local, no el dia UTC.
	v_from timestamptz := case
		when p_date_from is null then null
		else (p_date_from::timestamp at time zone 'America/Lima')
	end;
	v_to timestamptz := case
		when p_date_to is null then null
		else ((p_date_to + 1)::timestamp at time zone 'America/Lima')
	end;
begin
	if not public.is_admin() then
		raise exception 'ADMIN_FORBIDDEN';
	end if;

	return query
	with filtered as (
		select o.*
		from public.orders o
		where
			(p_status is null or o.order_status = p_status)
			and (p_payment_method is null or o.payment_method = p_payment_method)
			and (p_delivery_method is null or o.delivery_method = p_delivery_method)
			and (v_from is null or o.created_at >= v_from)
			and (v_to is null or o.created_at < v_to)
			and (
				-- Busqueda parametrizada: v_search es un valor, nunca SQL
				-- concatenado. Coincide con numero de pedido, nombre
				-- completo, email o telefono.
				v_search is null
				or o.order_number ilike '%' || v_search || '%'
				or (o.customer_first_name || ' ' || o.customer_last_name) ilike '%' || v_search || '%'
				or o.customer_email ilike '%' || v_search || '%'
				or o.customer_phone ilike '%' || v_search || '%'
			)
	),
	counted as (
		select count(*) as cnt from filtered
	),
	items_agg as (
		select
			oi.order_id,
			count(*)::bigint as item_count,
			coalesce(sum(oi.quantity), 0)::bigint as unit_count,
			bool_or(oi.engraving_requested) as has_engraving
		from public.order_items oi
		where oi.order_id in (select f.id from filtered f)
		group by oi.order_id
	)
	select
		f.id,
		f.order_number,
		f.created_at,
		f.order_status,
		trim(f.customer_first_name || ' ' || f.customer_last_name) as customer_full_name,
		f.customer_email,
		f.customer_phone,
		f.delivery_district,
		f.payment_method,
		f.delivery_method,
		f.total,
		coalesce(ia.item_count, 0) as item_count,
		coalesce(ia.unit_count, 0) as unit_count,
		coalesce(ia.has_engraving, false) as has_engraving,
		(select cnt from counted) as total_count
	from filtered f
		left join items_agg ia on ia.order_id = f.id
	order by f.created_at desc
	limit v_limit
	offset v_offset;
end;
$$;

comment on function public.admin_list_orders (
	text,
	public.order_status,
	public.payment_method,
	public.delivery_method,
	date,
	date,
	integer,
	integer
) is 'Listado paginado de pedidos para el panel admin: una fila por pedido con totales agregados de order_items. Busqueda parametrizada por numero/nombre/email/telefono. Maximo 100 por pagina. Exige is_admin().';

revoke
execute on function public.admin_list_orders (
	text,
	public.order_status,
	public.payment_method,
	public.delivery_method,
	date,
	date,
	integer,
	integer
)
from
	public,
	anon,
	authenticated;

grant
execute on function public.admin_list_orders (
	text,
	public.order_status,
	public.payment_method,
	public.delivery_method,
	date,
	date,
	integer,
	integer
) to authenticated;

-- ============================================================
-- 5) RPC: detalle de un pedido
-- ============================================================

create or replace function public.admin_get_order_detail (p_order_id uuid) returns jsonb language plpgsql security definer
set
	search_path = '' as $$
declare
	v_order jsonb;
	v_items jsonb;
	v_history jsonb;
begin
	if not public.is_admin() then
		raise exception 'ADMIN_FORBIDDEN';
	end if;

	select to_jsonb(o) into v_order
	from (
		select
			id, order_number, created_at, updated_at,
			order_status, payment_status, payment_method, delivery_method,
			customer_first_name, customer_last_name, customer_email, customer_phone,
			customer_document_type, customer_document_number,
			delivery_department, delivery_province, delivery_district, delivery_address,
			delivery_reference, agency_name,
			subtotal, delivery_cost, discount_total, total, currency,
			customer_notes, internal_notes
		from public.orders
		where id = p_order_id
	) o;

	if v_order is null then
		-- Mismo estilo de senal generica ya usado en create_order_v2
		-- (IDEMPOTENCY_MISMATCH): el frontend distingue "no encontrado" de
		-- un error tecnico sin mostrar detalle de Postgres.
		raise exception 'ORDER_NOT_FOUND';
	end if;

	select coalesce(jsonb_agg(to_jsonb(oi) order by oi.created_at asc, oi.id), '[]'::jsonb)
	into v_items
	from (
		select
			id, product_name, product_sku,
			wood_name, wood_slug, size_name, size_slug, dimensions_label,
			quantity, unit_price, line_total,
			engraving_requested, engraving_type, engraving_text, personalization_notes,
			created_at
		from public.order_items
		where order_id = p_order_id
	) oi;

	select coalesce(jsonb_agg(to_jsonb(h) order by h.created_at asc, h.id), '[]'::jsonb)
	into v_history
	from (
		select id, previous_status, new_status, note, created_at
		from public.order_status_history
		where order_id = p_order_id
	) h;

	return jsonb_build_object(
		'order', v_order,
		'items', v_items,
		'history', v_history
	);
end;
$$;

comment on function public.admin_get_order_detail (uuid) is 'Detalle completo de un pedido (cabecera + articulos + historial de estados cronologico) para el panel admin. No devuelve client_request_id/signature, public_tracking_token, engraving_file_path ni changed_by. Exige is_admin(); ORDER_NOT_FOUND si el id no existe.';

revoke
execute on function public.admin_get_order_detail (uuid)
from
	public,
	anon,
	authenticated;

grant
execute on function public.admin_get_order_detail (uuid) to authenticated;

-- ============================================================
-- Fin. No hay bloque de prueba en este archivo. Para verificar que
-- todo quedo creado y con los permisos correctos, correr a continuacion
-- supabase/verify_admin_orders_dashboard.sql (solo SELECT, no modifica
-- nada). Para dar de alta al primer administrador, ver los pasos
-- manuales entregados en el reporte de la tarea (Supabase Auth ->
-- crear usuario -> copiar UUID -> insert manual en admin_users).
-- ============================================================
