-- NO EJECUTADO CONTRA SUPABASE REMOTO. Preparado localmente para que el
-- propietario del proyecto lo revise y lo corra el mismo (Dashboard de
-- Supabase -> SQL Editor -> pegar -> Run).
--
-- Requiere que ya esten aplicados, en este orden:
--   1) supabase/catalog_mirror.sql
--   2) supabase/harden_create_order.sql
--   3) supabase/harden_permissions.sql
-- (los tres ya estan activos en el proyecto remoto). Este archivo NO
-- reescribe ese historial: usa `create or replace function` sobre la
-- misma `create_order_v2` (misma firma de 14 argumentos, mismo
-- `security definer`, mismo `search_path`), asi que aplicarlo es una
-- actualizacion in-place de la funcion existente, no una funcion nueva
-- ni una migracion de datos.
--
-- Que resuelve: hasta ahora `create_order_v2` validaba que hubiera
-- stock suficiente leyendo `catalog_variants.stock_quantity`, pero
-- nunca lo descontaba -- dos pedidos simultaneos por la misma unidad
-- podian pasar ambos la validacion antes de que nadie actualizara el
-- numero. Esta version:
--
--   1) Descuenta stock de forma atomica dentro del mismo UPDATE que
--      valida disponibilidad:
--         update catalog_variants
--         set stock_quantity = stock_quantity - cantidad
--         where ... and stock_quantity >= cantidad
--         returning ...
--      Si dos transacciones compiten por la misma fila, Postgres serializa
--      el UPDATE a nivel de fila: la segunda espera a que la primera
--      termine y vuelve a evaluar `stock_quantity >= cantidad` con el
--      valor ya actualizado. La condicion esta en el propio WHERE del
--      UPDATE, asi que nunca puede quedar stock_quantity negativo.
--   2) Si el UPDATE no afecta ninguna fila (producto/variante inactivo,
--      inexistente, o sin stock suficiente) se rechaza el item -- y por
--      extension el pedido completo, ver punto 4.
--   3) La idempotencia por `client_request_id` ahora se resuelve con un
--      advisory lock (`pg_advisory_xact_lock`) ademas de la comparacion
--      de firma que ya existia: dos llamadas con la MISMA clave se
--      serializan (la segunda espera a que la primera termine), asi que
--      solo la primera descuenta stock; la segunda, al esperar, vuelve a
--      leer el pedido ya creado y lo devuelve tal cual, sin tocar stock.
--      Esto pasa ANTES de tocar cualquier fila de catalog_variants, tal
--      como pide la politica: idempotencia primero, stock despues.
--   4) Sigue habiendo una sola transaccion por llamada al RPC (la que
--      abre Supabase/PostgREST para cada request): si cualquier item
--      falla (precio, stock, dato faltante) la funcion lanza una
--      excepcion y Postgres deshace automaticamente todo lo hecho en esa
--      llamada -- incluidos los descuentos de stock de items anteriores
--      del mismo pedido -- sin necesidad de un rollback manual.
--   5) El manejador de `unique_violation` que ya existia se conserva
--      como defensa adicional (no como mecanismo principal: el advisory
--      lock ya deberia evitar que se llegue ahi por una carrera real de
--      client_request_id).
--
-- Lo que NO cambia: firma de la funcion, permisos (sigue siendo
-- security definer, sigue result solo devolviendo order_number, sigue
-- sin conceder EXECUTE a PUBLIC/authenticated), calculo de precio/oferta,
-- calculo de engraving_requested, insercion de orders/order_items.
--
-- No se implementan reservas temporales de stock. El pedido confirmado
-- descuenta stock inmediatamente y de forma definitiva; no hay
-- expiracion ni liberacion automatica (fuera de alcance de esta tarea).

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
		-- Advisory lock por client_request_id: serializa dos llamadas
		-- concurrentes con la MISMA clave para que la segunda espere a
		-- que la primera termine (commit o rollback) antes de repetir el
		-- chequeo de idempotencia. Sin este lock, dos requests
		-- simultaneos con la misma clave podrian pasar ambos el chequeo
		-- de abajo (ninguno ve todavia la fila del otro), descontar
		-- stock dos veces, y recien despues chocar en el indice unico --
		-- momento en el que el stock ya quedo descontado de mas para la
		-- llamada perdedora. El lock se libera solo al terminar esta
		-- transaccion (commit o rollback), que es exactamente la
		-- duracion de esta llamada al RPC.
		perform pg_advisory_xact_lock(hashtextextended(p_client_request_id, 8321));

		select order_number, client_request_signature into v_existing_order_number, v_existing_signature
		from public.orders
		where client_request_id = p_client_request_id;

		if v_existing_order_number is not null then
			if v_existing_signature = v_signature then
				-- Mismo intento exacto (doble click, Enter repetido,
				-- reintento de red, recargo de pagina): se devuelve el
				-- pedido que ya existe en vez de crear otro o descontar
				-- stock de nuevo.
				return v_existing_order_number;
			else
				-- La clave se genera de nuevo en el cliente cuando
				-- cambia el carrito o los datos (ver buildOrderSignature
				-- en carrito.astro), asi que llegar aqui con la misma
				-- clave y otra firma es una senal de datos corruptos o
				-- manipulados: se rechaza en vez de reutilizar un pedido
				-- desactualizado.
				raise exception 'IDEMPOTENCY_MISMATCH: la clave de confirmacion ya se uso con datos diferentes.';
			end if;
		end if;
	end if;

	-- Por cada item: valida datos basicos, descuenta stock de forma
	-- atomica (el UPDATE con `stock_quantity >= v_quantity` en el WHERE
	-- es la unica fuente de verdad sobre si habia stock suficiente -- no
	-- se confia en una lectura previa) y guarda el precio ya resuelto
	-- para la insercion de order_items mas abajo.
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
			-- El UPDATE no afecto ninguna fila: el producto/variante ya
			-- no existe o esta inactivo, o el stock disponible es menor
			-- a la cantidad pedida (incluida la carrera contra otro
			-- pedido simultaneo que se quedo con la ultima unidad justo
			-- antes). Se hace una lectura aparte, de solo consulta,
			-- unicamente para dar un mensaje claro -- el rechazo del
			-- pedido ya es definitivo sin importar lo que diga esta
			-- lectura.
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
		-- Defensa adicional: con el advisory lock de arriba, dos
		-- llamadas con el mismo client_request_id ya no deberian llegar
		-- aqui compitiendo de verdad. Se conserva el mismo chequeo de
		-- firma por si acaso (p. ej. una migracion futura que quite el
		-- lock por error), nunca se devuelve un pedido existente sin
		-- confirmar que su contenido coincide.
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
) is 'Unica via de escritura para el checkout publico: valida contra el catalogo autoritativo (catalog_products/catalog_variants), descuenta stock de forma atomica, recalcula precio/subtotal/total en servidor y crea orders + order_items de forma idempotente via client_request_id (con advisory lock para serializar reintentos concurrentes). Devuelve solo el order_number.';

-- Postgres concede EXECUTE a PUBLIC automaticamente en toda funcion
-- nueva/reemplazada, salvo que se revoque explicitamente. Se repite aqui
-- el mismo revoke+grant que ya esta activo en el proyecto remoto (via
-- harden_create_order.sql + harden_permissions.sql) para que el
-- resultado final sea identico sin importar el estado previo.
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
