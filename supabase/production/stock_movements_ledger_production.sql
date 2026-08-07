-- NO EJECUTADO CONTRA SUPABASE REMOTO. A DIFERENCIA de los demas
-- archivos de esta carpeta, este NO se entrega para "aplicar y listo":
-- toca create_order_v2, la unica via de escritura del checkout publico
-- (hoy en produccion via harden_stock_atomic.sql). Se entrega como
-- PROPUESTA para que el propietario del proyecto la revise con calma,
-- idealmente probandola primero contra una copia/staging, antes de
-- correrla en el proyecto real.
--
-- ------------------------------------------------------------
-- Por que hace falta (respuesta a "verifica si el stock ya se modifica
-- al crear, pagar, cancelar o entregar pedidos")
-- ------------------------------------------------------------
-- Hoy el stock SOLO se descuenta una vez, en el checkout
-- (create_order_v2 / harden_stock_atomic.sql, UPDATE atomico sobre
-- catalog_variants.stock_quantity). Ningun otro camino de codigo lo
-- toca: ni confirmar pago (admin_update_order_status hacia
-- 'payment_verified'), ni marcar 'delivered', ni cancelar. Cancelar un
-- pedido HOY NO devuelve stock: una unidad vendida y luego cancelada
-- queda perdida del inventario disponible hasta que alguien la reponga
-- a mano en Supabase. No existe ninguna tabla de reserva ni de
-- movimientos de inventario en el esquema actual (confirmado por
-- introspeccion: catalog_products/catalog_variants no tienen columnas
-- de stock reservado, y no hay tabla de movimientos).
--
-- ------------------------------------------------------------
-- Diseno: bitacora de movimientos, idempotente por restriccion UNIQUE
-- ------------------------------------------------------------
-- public.stock_movements: una fila por (pedido, variante, tipo de
-- movimiento), con UNIQUE (order_id, variant_id, movement_type). Esa
-- restriccion es lo que hace todo el mecanismo idempotente por
-- construccion, no por logica de aplicacion que se pueda olvidar:
--
--   - 'order_deduction': una fila por cada VARIANTE distinta al momento
--     del checkout (no una fila por order_item), con la cantidad total
--     descontada de esa variante en ese pedido ya sumada. Un mismo
--     pedido puede tener dos order_items para la misma variante (mismo
--     producto/madera/tamaño, distinto grabado -- el carrito los trata
--     como lineas separadas), asi que las cantidades se agregan por
--     variante antes de insertar; de lo contrario el UNIQUE de abajo
--     descartaria la segunda linea con ON CONFLICT DO NOTHING y la
--     bitacora quedaria corta. Junto con el UPDATE atomico que ya
--     existe. Si por cualquier motivo se intentara insertar dos veces
--     la misma fila (mismo pedido, misma variante), ON CONFLICT DO
--     NOTHING la descarta -- nunca se puede registrar (ni por lo tanto
--     interpretar mas adelante) una doble deduccion para el mismo par.
--   - 'cancellation_restock': se inserta solo cuando existe la fila
--     'order_deduction' correspondiente (solo se devuelve lo que antes
--     se desconto) y solo si todavia no existe su propia
--     'cancellation_restock' (evita devolver dos veces). El UPDATE que
--     suma de vuelta a catalog_variants.stock_quantity usa
--     `insert ... on conflict do nothing returning ...` como fuente: si
--     la fila ya existia (reintento, doble clic, recarga), el INSERT no
--     devuelve nada y el UPDATE de stock no se ejecuta -- cero riesgo
--     de sumar stock de mas por un reintento. admin_update_order_status
--     ademas ya bloquea la fila del pedido con FOR UPDATE y exige
--     p_expected_status = estado actual (ORDER_STATUS_CONFLICT /
--     ORDER_STATUS_UNCHANGED si no), asi que no es fisicamente posible
--     cancelar el mismo pedido dos veces por esta funcion; el UNIQUE de
--     stock_movements es una segunda barrera independiente por si ese
--     invariante cambiara en el futuro.
--
-- Reutiliza el 100% de las tablas existentes (orders, order_items,
-- catalog_variants): no crea un catalogo paralelo ni una fuente de
-- verdad alternativa, solo una tabla de auditoria/idempotencia nueva
-- que registra lo que ya pasa.
--
-- ------------------------------------------------------------
-- Cambios que este archivo prepara (sin aplicarlos)
-- ------------------------------------------------------------
--   1) Tabla nueva: public.stock_movements.
--   2) create_order_v2 (create or replace, misma firma de 14
--      argumentos, mismo security definer, mismo search_path): agrega,
--      dentro del mismo loop que ya descuenta stock, un
--      INSERT ... ON CONFLICT DO NOTHING que deja registrada la
--      deduccion de cada item. No cambia precio, validacion de stock
--      disponible, calculo de subtotal/total, ni las reglas de
--      idempotencia por client_request_id que ya existen (esas rutas
--      de retorno temprano siguen retornando ANTES de tocar stock, como
--      hoy).
--   3) admin_update_order_status (create or replace, misma firma):
--      cuando la transicion es HACIA 'cancelled' -- y solo entonces --
--      despues de actualizar order_status, repone stock_quantity de
--      cada item del pedido que tenga una fila 'order_deduction' sin su
--      'cancellation_restock' correspondiente, dejando esa fila
--      registrada. Ninguna otra transicion de estado toca stock. Ademas,
--      'cancelled' pasa a ser terminal: cualquier intento de cambiar un
--      pedido cancelado a otro estado falla con
--      ORDER_STATUS_CANCELLED_FINAL, sin tocar stock ni order_status
--      (decision de negocio: antes de este ledger reactivar un pedido
--      cancelado era inofensivo porque cancelar no devolvia stock; ahora
--      si lo devuelve, asi que reactivarlo dejaria un pedido "activo"
--      sin unidades reservadas).
--
-- ------------------------------------------------------------
-- Limitacion conocida y deliberada
-- ------------------------------------------------------------
-- Pedidos creados ANTES de aplicar este archivo no tienen fila
-- 'order_deduction' (la bitacora no existia todavia): si se cancelan
-- despues de aplicar esto, NO recuperan stock automaticamente -- exacto
-- el mismo comportamiento que existe hoy (ninguna reposicion), asi que
-- no es una regresion, solo alcance no retroactivo desde el momento de
-- aplicacion en adelante. Reponer stock de pedidos historicos
-- cancelados antes de este cambio, si hace falta, es una correccion
-- manual aparte, fuera de esta tarea.

-- ============================================================
-- 1) Bitacora de movimientos de stock
-- ============================================================

create table if not exists public.stock_movements (
	id uuid primary key default gen_random_uuid(),
	order_id uuid not null references public.orders (id) on delete cascade,
	variant_id uuid not null references public.catalog_variants (id) on delete restrict,
	movement_type text not null check (movement_type in ('order_deduction', 'cancellation_restock')),
	quantity integer not null check (quantity > 0),
	created_at timestamptz not null default now(),
	unique (order_id, variant_id, movement_type)
);

comment on table public.stock_movements is 'Bitacora de descuentos/devoluciones de stock por pedido y variante. El UNIQUE (order_id, variant_id, movement_type) es el mecanismo de idempotencia: no permite registrar dos veces el mismo movimiento para el mismo par pedido/variante.';

alter table public.stock_movements enable row level security;

-- Mismo principio que catalog_products/catalog_variants/admin_users:
-- RLS activo sin ninguna policy, mas revoke explicito de grants de
-- tabla. Solo lo escriben create_order_v2 y admin_update_order_status
-- (ambas security definer); nadie lee ni escribe esta tabla
-- directamente desde el navegador.
revoke all on public.stock_movements
from
	public,
	anon,
	authenticated;

create index if not exists stock_movements_order_id_idx on public.stock_movements (order_id);

-- ============================================================
-- 2) create_order_v2: registrar la deduccion junto al descuento
--    atomico que ya existe (harden_stock_atomic.sql)
-- ============================================================

create or replace function public.create_order_v2 (
	p_payment_method public.payment_method,
	p_delivery_method public.delivery_method,
	p_customer_first_name text,
	p_customer_last_name text,
	p_customer_email text,
	p_customer_phone text,
	p_delivery_department text,
	p_delivery_province text,
	p_delivery_district text,
	p_delivery_address text,
	p_delivery_reference text,
	p_customer_notes text,
	p_items jsonb,
	p_client_request_id text default null
) returns text language plpgsql security definer
set
	search_path = public as $$
declare
	v_order_id uuid;
	v_order_number text;
	v_existing_order_number text;
	v_existing_signature text;
	v_signature text;
	v_item jsonb;
	v_item_count integer;
	v_sanity_product_id text;
	v_sku text;
	v_quantity integer;
	v_engraving text;
	v_engraving_requested boolean;
	v_cat_variant_id uuid;
	v_cat_title text;
	v_cat_wood_title text;
	v_cat_wood_slug text;
	v_cat_size_title text;
	v_cat_size_slug text;
	v_cat_dimensions_label text;
	v_cat_price numeric;
	v_cat_sale_price numeric;
	v_cat_stock integer;
	v_cat_sale_start timestamptz;
	v_cat_sale_end timestamptz;
	v_sale_active boolean;
	v_unit_price numeric;
	v_line_total numeric;
	v_computed_subtotal numeric := 0;
	v_computed_total numeric;
	v_resolved jsonb := '[]'::jsonb;
	v_delivery_cost constant numeric := 10.00;
	v_max_items constant integer := 50;
	v_max_quantity_per_item constant integer := 50;
	v_max_engraving_length constant integer := 500;
begin
	if p_items is null or jsonb_array_length(p_items) = 0 then
		raise exception 'El pedido debe tener al menos un producto.';
	end if;

	v_item_count := jsonb_array_length(p_items);

	if v_item_count > v_max_items then
		raise exception 'El pedido tiene demasiados productos distintos (maximo %).', v_max_items;
	end if;

	if
		coalesce(trim(p_customer_first_name), '') = ''
		or coalesce(trim(p_customer_last_name), '') = ''
		or coalesce(trim(p_customer_email), '') = ''
		or coalesce(trim(p_customer_phone), '') = ''
		or coalesce(trim(p_delivery_department), '') = ''
		or coalesce(trim(p_delivery_province), '') = ''
		or coalesce(trim(p_delivery_district), '') = ''
		or coalesce(trim(p_delivery_address), '') = ''
	then
		raise exception 'Faltan datos obligatorios del cliente o de la direccion de entrega.';
	end if;

	v_signature := md5(
		coalesce(p_payment_method::text, '') || '|' || coalesce(p_delivery_method::text, '') || '|' || coalesce(p_customer_first_name, '') || '|' || coalesce(p_customer_last_name, '') || '|' || coalesce(p_customer_email, '') || '|' || coalesce(p_customer_phone, '') || '|' || coalesce(p_delivery_department, '') || '|' || coalesce(p_delivery_province, '') || '|' || coalesce(p_delivery_district, '') || '|' || coalesce(p_delivery_address, '') || '|' || coalesce(p_delivery_reference, '') || '|' || coalesce(p_customer_notes, '') || '|' || coalesce(p_items::text, '')
	);

	if p_client_request_id is not null then
		perform pg_advisory_xact_lock(hashtextextended(p_client_request_id, 8321));

		select order_number, client_request_signature into v_existing_order_number, v_existing_signature
		from public.orders
		where client_request_id = p_client_request_id;

		if v_existing_order_number is not null then
			if v_existing_signature = v_signature then
				-- Retorno temprano: no se toca stock_movements ni stock,
				-- exactamente igual que hoy.
				return v_existing_order_number;
			else
				raise exception 'IDEMPOTENCY_MISMATCH: la clave de confirmacion ya se uso con datos diferentes.';
			end if;
		end if;
	end if;

	for v_item in select * from jsonb_array_elements(p_items)
	loop
		v_sanity_product_id := v_item->>'sanityProductId';
		v_sku := v_item->>'productSku';
		v_quantity := nullif(v_item->>'quantity', '')::integer;
		v_engraving := left(coalesce(v_item->>'engravingText', ''), v_max_engraving_length);
		v_engraving_requested := trim(v_engraving) <> '';

		if
			coalesce(trim(v_sanity_product_id), '') = ''
			or coalesce(trim(v_sku), '') = ''
		then
			raise exception 'Falta identificar el producto o el SKU de un item del pedido.';
		end if;

		if v_quantity is null or v_quantity <= 0 then
			raise exception 'Cantidad invalida para %.', coalesce(v_item->>'productName', v_sku);
		end if;

		if v_quantity > v_max_quantity_per_item then
			raise exception 'Cantidad fuera de rango para %.', coalesce(v_item->>'productName', v_sku);
		end if;

		update public.catalog_variants cv
		set
			stock_quantity = cv.stock_quantity - v_quantity
		from public.catalog_products cp
		where
			cv.product_id = cp.id
			and cv.sanity_product_id = v_sanity_product_id
			and cv.sku = v_sku
			and cv.active = true
			and cp.active = true
			and cv.stock_quantity >= v_quantity
		returning
			cv.id,
			cp.title,
			cv.wood_title,
			cv.wood_slug,
			cv.size_title,
			cv.size_slug,
			cv.dimensions_label,
			cv.price,
			cv.sale_price,
			cp.sale_start,
			cp.sale_end
		into
			v_cat_variant_id,
			v_cat_title,
			v_cat_wood_title,
			v_cat_wood_slug,
			v_cat_size_title,
			v_cat_size_slug,
			v_cat_dimensions_label,
			v_cat_price,
			v_cat_sale_price,
			v_cat_sale_start,
			v_cat_sale_end;

		if not found then
			select cv.stock_quantity into v_cat_stock
			from public.catalog_variants cv
				join public.catalog_products cp on cp.id = cv.product_id
			where
				cv.sanity_product_id = v_sanity_product_id
				and cv.sku = v_sku
				and cv.active = true
				and cp.active = true;

			if not found then
				raise exception 'El producto % (SKU %) ya no esta disponible.', coalesce(v_item->>'productName', '?'), v_sku;
			else
				raise exception 'Stock insuficiente para % (SKU %): quedan % unidad(es).', coalesce(v_item->>'productName', '?'), v_sku, v_cat_stock;
			end if;
		end if;

		v_sale_active := (
			v_cat_sale_start is null
			or now() >= v_cat_sale_start
		)
		and (
			v_cat_sale_end is null
			or now() <= v_cat_sale_end
		);

		v_unit_price := case
			when v_sale_active
			and v_cat_sale_price is not null then v_cat_sale_price
			else v_cat_price
		end;

		v_line_total := round(v_unit_price * v_quantity, 2);
		v_computed_subtotal := v_computed_subtotal + v_line_total;

		v_resolved := v_resolved || jsonb_build_object(
			'variant_id', v_cat_variant_id,
			'sanity_product_id', v_sanity_product_id,
			'sanity_product_slug', v_item->>'sanityProductSlug',
			'product_name', v_cat_title,
			'product_sku', v_sku,
			'wood_name', v_cat_wood_title,
			'wood_slug', v_cat_wood_slug,
			'size_name', v_cat_size_title,
			'size_slug', v_cat_size_slug,
			'dimensions_label', v_cat_dimensions_label,
			'engraving_text', nullif(v_engraving, ''),
			'engraving_requested', v_engraving_requested,
			'quantity', v_quantity,
			'unit_price', v_unit_price,
			'line_total', v_line_total
		);
	end loop;

	v_computed_total := v_computed_subtotal + v_delivery_cost;

	insert into
		public.orders (
			payment_method,
			delivery_method,
			customer_first_name,
			customer_last_name,
			customer_email,
			customer_phone,
			delivery_department,
			delivery_province,
			delivery_district,
			delivery_address,
			delivery_reference,
			customer_notes,
			subtotal,
			delivery_cost,
			total,
			client_request_id,
			client_request_signature
		)
	values (
		p_payment_method,
		p_delivery_method,
		p_customer_first_name,
		p_customer_last_name,
		p_customer_email,
		p_customer_phone,
		p_delivery_department,
		p_delivery_province,
		p_delivery_district,
		p_delivery_address,
		p_delivery_reference,
		p_customer_notes,
		v_computed_subtotal,
		v_delivery_cost,
		v_computed_total,
		p_client_request_id,
		v_signature
	)
	returning id, order_number into v_order_id, v_order_number;

	for v_item in select * from jsonb_array_elements(v_resolved)
	loop
		insert into
			public.order_items (
				order_id,
				sanity_product_id,
				sanity_product_slug,
				product_name,
				product_sku,
				wood_name,
				wood_slug,
				size_name,
				size_slug,
				dimensions_label,
				engraving_text,
				engraving_requested,
				quantity,
				unit_price,
				line_total
			)
		values (
			v_order_id,
			v_item->>'sanity_product_id',
			v_item->>'sanity_product_slug',
			v_item->>'product_name',
			v_item->>'product_sku',
			v_item->>'wood_name',
			v_item->>'wood_slug',
			v_item->>'size_name',
			v_item->>'size_slug',
			v_item->>'dimensions_label',
			v_item->>'engraving_text',
			(v_item->>'engraving_requested')::boolean,
			(v_item->>'quantity')::integer,
			(v_item->>'unit_price')::numeric,
			(v_item->>'line_total')::numeric
		);
	end loop;

	-- Registro de la deduccion ya aplicada arriba por los UPDATE
	-- atomicos, agregada por variante: un mismo pedido puede tener dos
	-- order_items para la misma variante (mismo producto/madera/tamaño,
	-- distinto grabado -- el carrito los trata como lineas separadas,
	-- ver cartId en productos/[slug].astro), asi que se suma la
	-- cantidad total descontada por variante antes de insertar. Sin
	-- este agregado, insertar una fila por order_item chocaria con el
	-- UNIQUE (order_id, variant_id, movement_type) en la segunda linea
	-- de la misma variante y el ON CONFLICT DO NOTHING la descartaria
	-- silenciosamente, dejando registrada solo una fraccion de lo
	-- realmente descontado (y por lo tanto reponiendo de menos al
	-- cancelar). Con el agregado, hay como maximo una fila por variante
	-- por pedido, con la cantidad total real.
	insert into public.stock_movements (order_id, variant_id, movement_type, quantity)
	select
		v_order_id,
		(item->>'variant_id')::uuid,
		'order_deduction',
		sum((item->>'quantity')::integer)::integer
	from jsonb_array_elements(v_resolved) as item
	group by (item->>'variant_id')::uuid
	on conflict (order_id, variant_id, movement_type) do nothing;

	return v_order_number;
exception
	when unique_violation then
		if p_client_request_id is not null then
			select order_number, client_request_signature into v_existing_order_number, v_existing_signature
			from public.orders
			where client_request_id = p_client_request_id;

			if v_existing_order_number is not null then
				if v_existing_signature = v_signature then
					return v_existing_order_number;
				else
					raise exception 'IDEMPOTENCY_MISMATCH: la clave de confirmacion ya se uso con datos diferentes.';
				end if;
			end if;
		end if;

		raise;
end;
$$;

comment on function public.create_order_v2 (
	public.payment_method,
	public.delivery_method,
	text,
	text,
	text,
	text,
	text,
	text,
	text,
	text,
	text,
	text,
	jsonb,
	text
) is 'Unica via de escritura para el checkout publico: valida contra el catalogo autoritativo (catalog_products/catalog_variants), descuenta stock de forma atomica, registra cada deduccion en stock_movements (idempotente via UNIQUE), recalcula precio/subtotal/total en servidor y crea orders + order_items de forma idempotente via client_request_id (con advisory lock para serializar reintentos concurrentes). Devuelve solo el order_number.';

revoke
execute on function public.create_order_v2 (
	public.payment_method,
	public.delivery_method,
	text,
	text,
	text,
	text,
	text,
	text,
	text,
	text,
	text,
	text,
	jsonb,
	text
)
from
	public,
	anon,
	authenticated;

grant
execute on function public.create_order_v2 (
	public.payment_method,
	public.delivery_method,
	text,
	text,
	text,
	text,
	text,
	text,
	text,
	text,
	text,
	text,
	jsonb,
	text
) to anon;

-- ============================================================
-- 3) admin_update_order_status: reponer stock solo al cancelar
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
	v_admin uuid := auth.uid();
	v_current public.order_status;
	v_order_number text;
	v_updated_at timestamptz;
	v_note text := nullif(btrim(coalesce(p_note, '')), '');
	v_restocked_variants integer := 0;
begin
	if v_admin is null or not public.is_admin() then
		raise exception 'ADMIN_FORBIDDEN';
	end if;

	if p_order_id is null or p_expected_status is null or p_new_status is null then
		raise exception 'INVALID_ORDER_STATUS';
	end if;

	if v_note is not null and length(v_note) > 400 then
		v_note := left(v_note, 400);
	end if;

	select o.order_status, o.order_number
	into v_current, v_order_number
	from public.orders o
	where o.id = p_order_id
	for update;

	if not found then
		raise exception 'ORDER_NOT_FOUND';
	end if;

	if v_current is distinct from p_expected_status then
		raise exception 'ORDER_STATUS_CONFLICT';
	end if;

	if p_new_status = v_current then
		raise exception 'ORDER_STATUS_UNCHANGED';
	end if;

	-- 'cancelled' es terminal: a partir de este ledger, cancelar SI
	-- repone stock (ver mas abajo), asi que reactivar un pedido cancelado
	-- lo dejaria "activo" sin que exista ninguna unidad reservada para
	-- el (la que se repuso pudo venderse ya a otro pedido). No se inventa
	-- una maquina de estados nueva -- solo se cierra esta unica
	-- transicion, que antes de este ledger era inofensiva y ahora no lo
	-- es.
	if v_current = 'cancelled'::public.order_status then
		raise exception 'ORDER_STATUS_CANCELLED_FINAL';
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

	-- Reposicion de stock: solo al pasar A 'cancelled'. Idempotente por
	-- construccion: solo repone lo que tiene una 'order_deduction' sin
	-- 'cancellation_restock' todavia (CTE de INSERT ... ON CONFLICT DO
	-- NOTHING ... RETURNING), y el UPDATE de catalog_variants solo suma
	-- lo que ese INSERT realmente inserto en ESTA llamada. Si por algun
	-- motivo se reintentara la misma transicion (no deberia poder pasar:
	-- FOR UPDATE + p_expected_status ya lo impiden), el CTE no
	-- devolveria filas y el UPDATE no tocaria stock_quantity.
	if p_new_status = 'cancelled'::public.order_status then
		with new_restocks as (
			insert into public.stock_movements (order_id, variant_id, movement_type, quantity)
			select
				d.order_id,
				d.variant_id,
				'cancellation_restock',
				d.quantity
			from public.stock_movements d
			where d.order_id = p_order_id
				and d.movement_type = 'order_deduction'
				and not exists (
					select 1
					from public.stock_movements r
					where r.order_id = d.order_id
						and r.variant_id = d.variant_id
						and r.movement_type = 'cancellation_restock'
				)
			on conflict (order_id, variant_id, movement_type) do nothing
			returning variant_id, quantity
		)
		update public.catalog_variants cv
		set stock_quantity = cv.stock_quantity + nr.quantity
		from new_restocks nr
		where cv.id = nr.variant_id;

		get diagnostics v_restocked_variants = row_count;
	end if;

	return jsonb_build_object(
		'order_id', p_order_id,
		'order_number', v_order_number,
		'previous_status', v_current,
		'new_status', p_new_status,
		'updated_at', v_updated_at,
		'restocked_variants', v_restocked_variants
	);
end;
$$;

comment on function public.admin_update_order_status (
	uuid,
	public.order_status,
	public.order_status,
	text
) is 'Cambia el estado de un pedido desde el panel admin. Atomico: bloquea la fila con FOR UPDATE, exige que el estado actual coincida con p_expected_status (ORDER_STATUS_CONFLICT si no) y registra el cambio en order_status_history con changed_by = auth.uid(). Al cancelar, repone stock_quantity de forma idempotente usando stock_movements (solo lo previamente descontado para ese pedido, nunca dos veces). "cancelled" es terminal: no se puede reactivar (ORDER_STATUS_CANCELLED_FINAL). Exige is_admin(). Errores: ADMIN_FORBIDDEN, ORDER_NOT_FOUND, ORDER_STATUS_CONFLICT, ORDER_STATUS_UNCHANGED, ORDER_STATUS_CANCELLED_FINAL, INVALID_ORDER_STATUS.';

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
-- Fin. No se concede ningun grant nuevo sobre orders/order_items/
-- catalog_variants: el unico camino de escritura de stock sigue siendo
-- create_order_v2 (descuento) y admin_update_order_status (devolucion
-- al cancelar), ambas security definer. Para verificar, correr a
-- continuacion supabase/verify_stock_movements_ledger.sql (solo
-- SELECT).
-- ============================================================
