-- Como correrlo: Dashboard de Supabase -> SQL Editor -> pegar -> Run.
--
-- Esto asume que YA existe el esquema que compartiste (orders,
-- order_items, order_status_history, order_payments, los enums,
-- generate_order_number(), etc). No crea tablas nuevas, solo agrega
-- la funcion que faltaba: la unica forma en que el checkout (con la
-- publishable key, sin permisos directos sobre las tablas) puede
-- registrar un pedido completo con sus productos.

create or replace function public.create_order(
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
	p_subtotal numeric,
	p_delivery_cost numeric,
	p_total numeric,
	p_items jsonb
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
	v_order_id uuid;
	v_order_number text;
	v_item jsonb;
begin
	if p_items is null or jsonb_array_length(p_items) = 0 then
		raise exception 'El pedido debe tener al menos un producto.';
	end if;

	insert into public.orders (
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
		total
	) values (
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
		p_subtotal,
		p_delivery_cost,
		p_total
	)
	returning id, order_number
	into v_order_id, v_order_number;

	for v_item in select * from jsonb_array_elements(p_items)
	loop
		insert into public.order_items (
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
			quantity,
			unit_price,
			line_total
		) values (
			v_order_id,
			v_item->>'sanityProductId',
			v_item->>'sanityProductSlug',
			v_item->>'productName',
			v_item->>'productSku',
			v_item->>'woodName',
			v_item->>'woodSlug',
			v_item->>'sizeName',
			v_item->>'sizeSlug',
			v_item->>'dimensionsLabel',
			(v_item->>'quantity')::integer,
			(v_item->>'unitPrice')::numeric,
			-- Se calcula aqui, no se confia en el valor que manda el
			-- navegador, para que siempre cumpla el check de la tabla.
			round(
				(v_item->>'unitPrice')::numeric
					* (v_item->>'quantity')::integer,
				2
			)
		);
	end loop;

	return v_order_number;
end;
$$;

comment on function public.create_order is
	'Unica via de escritura para el checkout publico: crea la fila en orders y sus order_items, devuelve solo el order_number.';

grant execute on function public.create_order(
	public.payment_method,
	public.delivery_method,
	text, text, text, text,
	text, text, text, text, text,
	text,
	numeric, numeric, numeric,
	jsonb
) to anon, authenticated;
