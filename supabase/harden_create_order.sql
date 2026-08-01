-- NO EJECUTADO CONTRA SUPABASE REMOTO. Preparado localmente para que el
-- propietario del proyecto lo revise y lo corra el mismo (Dashboard de
-- Supabase -> SQL Editor -> pegar -> Run).
--
-- Requiere haber corrido antes `supabase/catalog_mirror.sql` (crea las
-- tablas `catalog_products`/`catalog_variants` que esta funcion consulta
-- como fuente de precio/stock). Corre `supabase/harden_permissions.sql`
-- despues de este archivo para revocarle el acceso publico al RPC
-- anterior y dejar el nuevo como unica via.
--
-- Por que una funcion nueva (`create_order_v2`) y no reemplazar
-- `create_order`: esta version quita `p_subtotal`/`p_delivery_cost`/
-- `p_total` de los parametros (el servidor ya no los necesita, los
-- calcula el mismo desde el catalogo), y `create or replace function`
-- NO reemplaza una funcion cuando cambia la lista de parametros: crea
-- un overload nuevo. Si el overload nuevo comparte nombre con uno viejo
-- que PostgREST no puede resolver sin ambiguedad, las llamadas fallan
-- con PGRST203. Usar un nombre distinto evita ese riesgo por completo y
-- de paso dejar el RPC anterior intacto y con acceso revocado (ver
-- harden_permissions.sql) en vez de borrarlo, que es justo lo pedido:
-- no romper compatibilidad si algo mas todavia lo llama.
--
-- Cambios respecto al `create_order` original:
--   1) Precio y stock ya NO se confian del navegador: cada item del
--      pedido llega con `sanityProductId` + `productSku` (el cliente ya
--      los enviaba) y la funcion busca el precio/stock vigentes en
--      `catalog_products`/`catalog_variants`. Si no encuentra el par o
--      esta inactivo, rechaza el pedido completo.
--   2) Cantidad se valida contra el stock del catalogo, no contra lo
--      que haya quedado en el localStorage del navegador.
--   3) Subtotal y total se recalculan siempre en servidor a partir del
--      precio del catalogo, ignorando cualquier valor enviado por el
--      cliente.
--   4) Idempotencia real: `client_request_id` + una firma calculada en
--      servidor (`client_request_signature`, hash de todos los campos
--      que definen el pedido). Mismo id + misma firma = se devuelve el
--      pedido ya creado. Mismo id + firma distinta = se rechaza en vez
--      de reutilizar un pedido con datos desactualizados.
--   5) `order_items.engraving_requested` (columna ya existente en el
--      schema remoto, no llenada por el `create_order` original) ahora
--      se calcula en servidor: `true` cuando `engravingText` tiene
--      contenido real despues de quitar espacios, `false` en cualquier
--      otro caso (null, vacio, o solo espacios).
--   6) A diferencia del `create_order` original, esta funcion revoca
--      explicitamente EXECUTE de PUBLIC (y de paso de anon/authenticated)
--      antes de concederselo solo a `anon`. Postgres concede EXECUTE a
--      PUBLIC por defecto en toda funcion nueva; sin este revoke,
--      cualquier rol heredaria acceso sin importar los GRANT explicitos.
--
-- PENDIENTE / riesgo que sigue abierto (no resuelto aqui, reportado
-- aparte): esta funcion NO descuenta ni reserva stock al crear el
-- pedido. Sanity sigue siendo la unica fuente que se decrementa (a mano,
-- por el propietario), y `catalog_variants.stock_quantity` solo se
-- actualiza cuando corre `npm run sync:catalog`. Eso significa que dos
-- pedidos simultaneos podrian ambos pasar la validacion de stock leyendo
-- el mismo numero antes de que nadie lo actualice (condicion de carrera
-- de baja probabilidad, no de integridad de datos: nunca se inserta un
-- pedido con precio o total incorrecto). Implementar reserva/descuento
-- automatico de stock requeriria sincronizar el descuento de vuelta a
-- Sanity, que el proyecto no contempla todavia y no se debe improvisar
-- aqui.

alter table public.orders
add column if not exists client_request_id text;

alter table public.orders
add column if not exists client_request_signature text;

create unique index if not exists orders_client_request_id_key on public.orders (client_request_id)
where
	client_request_id is not null;

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
	v_cat_title text;
	v_cat_wood_title text;
	v_cat_wood_slug text;
	v_cat_size_title text;
	v_cat_size_slug text;
	v_cat_dimensions_label text;
	v_cat_price numeric;
	v_cat_sale_price numeric;
	v_cat_stock integer;
	v_cat_product_active boolean;
	v_cat_variant_active boolean;
	v_cat_sale_start timestamptz;
	v_cat_sale_end timestamptz;
	v_sale_active boolean;
	v_unit_price numeric;
	v_line_total numeric;
	v_computed_subtotal numeric := 0;
	v_computed_total numeric;
	v_resolved jsonb := '[]'::jsonb;
	-- Tarifa plana vigente (S/ 10, ver src/lib/constants.ts SHIPPING_COST).
	-- No hay tarifas por distancia/peso en el proyecto; si el negocio
	-- agrega alguna, hay que actualizar los dos lugares a la vez.
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

	-- Firma en servidor de todo lo que define el pedido. `jsonb::text`
	-- normaliza el orden de las claves, asi que dos llamadas con el
	-- mismo contenido logico (aunque el JSON original tenga las claves
	-- en otro orden) producen la misma firma.
	v_signature := md5(
		coalesce(p_payment_method::text, '') || '|' || coalesce(p_delivery_method::text, '') || '|' || coalesce(p_customer_first_name, '') || '|' || coalesce(p_customer_last_name, '') || '|' || coalesce(p_customer_email, '') || '|' || coalesce(p_customer_phone, '') || '|' || coalesce(p_delivery_department, '') || '|' || coalesce(p_delivery_province, '') || '|' || coalesce(p_delivery_district, '') || '|' || coalesce(p_delivery_address, '') || '|' || coalesce(p_delivery_reference, '') || '|' || coalesce(p_customer_notes, '') || '|' || coalesce(p_items::text, '')
	);

	if p_client_request_id is not null then
		select order_number, client_request_signature into v_existing_order_number, v_existing_signature
		from public.orders
		where client_request_id = p_client_request_id;

		if v_existing_order_number is not null then
			if v_existing_signature = v_signature then
				-- Mismo intento exacto (doble click, Enter repetido,
				-- reintento de red, recargo de pagina): se devuelve el
				-- pedido que ya existe en vez de crear otro.
				return v_existing_order_number;
			else
				-- La clave se genera de nuevo en el cliente cuando
				-- cambia el carrito o los datos (ver buildOrderSignature
				-- en carrito.astro), asi que llegar aqui con la misma
				-- clave y otra firma es una senal de datos corruptos o
				-- manipulados: se rechaza en vez de reutilizar un pedido
				-- desactualizado. El prefijo es para que el cliente
				-- distinga este caso de un error generico sin mostrar
				-- texto tecnico al usuario.
				raise exception 'IDEMPOTENCY_MISMATCH: la clave de confirmacion ya se uso con datos diferentes.';
			end if;
		end if;
	end if;

	-- Primera pasada: valida cada item contra el catalogo autoritativo,
	-- calcula precio/subtotal en servidor y guarda los datos ya
	-- resueltos para la segunda pasada (no se vuelve a consultar el
	-- catalogo, para no leer un valor distinto si algo cambia entre
	-- medio de las dos pasadas).
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

		select
			cp.title,
			cp.active,
			cp.sale_start,
			cp.sale_end,
			cv.wood_title,
			cv.wood_slug,
			cv.size_title,
			cv.size_slug,
			cv.dimensions_label,
			cv.price,
			cv.sale_price,
			cv.stock_quantity,
			cv.active
		into
			v_cat_title,
			v_cat_product_active,
			v_cat_sale_start,
			v_cat_sale_end,
			v_cat_wood_title,
			v_cat_wood_slug,
			v_cat_size_title,
			v_cat_size_slug,
			v_cat_dimensions_label,
			v_cat_price,
			v_cat_sale_price,
			v_cat_stock,
			v_cat_variant_active
		from public.catalog_variants cv
			join public.catalog_products cp on cp.id = cv.product_id
		where
			cv.sanity_product_id = v_sanity_product_id
			and cv.sku = v_sku;

		if not found then
			raise exception 'El producto % (SKU %) ya no esta disponible.', coalesce(v_item->>'productName', '?'), v_sku;
		end if;

		if not v_cat_product_active or not v_cat_variant_active then
			raise exception 'El producto % ya no esta disponible para la venta.', v_cat_title;
		end if;

		if v_quantity > v_cat_stock then
			raise exception 'Stock insuficiente para %: quedan % unidad(es).', v_cat_title, v_cat_stock;
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

	return v_order_number;
exception
	when unique_violation then
		-- Carrera entre dos llamadas con el mismo client_request_id
		-- (doble envio casi simultaneo): la que perdio la carrera
		-- vuelve a comparar la firma antes de responder, igual que el
		-- chequeo de idempotencia normal mas arriba. Nunca se devuelve
		-- un pedido existente sin confirmar que su contenido coincide.
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
) is 'Unica via de escritura para el checkout publico: valida contra el catalogo autoritativo (catalog_products/catalog_variants), recalcula precio/subtotal/total en servidor y crea orders + order_items de forma idempotente via client_request_id. Devuelve solo el order_number.';

-- Postgres concede EXECUTE a PUBLIC automaticamente en toda funcion
-- nueva, salvo que se revoque explicitamente. Sin este revoke, cualquier
-- rol (no solo anon) heredaria acceso a create_order_v2 por defecto.
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
