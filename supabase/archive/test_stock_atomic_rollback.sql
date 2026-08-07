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

create temporary table test_results (step text, result text);

-- 1) Compra normal, cantidad 1, precio manipulado a 1 en el payload
do $$
declare v_pid text; v_sku text; v_pm public.payment_method; v_dm public.delivery_method; v_order text;
begin
	select sanity_product_id, sku, payment_method, delivery_method
	into v_pid, v_sku, v_pm, v_dm from test_ctx;

	v_order := public.create_order_v2(
		v_pm, v_dm, 'Prueba','Uno','prueba1@example.com','999999999',
		'Lima','Lima','Miraflores','Av. Prueba 123', null, null,
		jsonb_build_array(jsonb_build_object(
			'sanityProductId', v_pid, 'productSku', v_sku,
			'sanityProductSlug','prueba','productName','Prueba',
			'quantity',1,'unitPrice',1
		)),
		'test-req-001'
	);
	insert into test_results values ('1_compra_normal', 'order=' || v_order);
exception when others then
	insert into test_results values ('1_compra_normal', 'ERROR: ' || sqlerrm);
end $$;

insert into test_results
select '1_stock_tras_compra', stock_quantity::text
from public.catalog_variants cv join test_ctx tc
	on cv.sanity_product_id = tc.sanity_product_id and cv.sku = tc.sku;

-- 2) Misma clave repetida, mismos datos -> debe devolver el mismo pedido,
--    stock debe seguir en 9 (no bajar a 8)
do $$
declare v_pid text; v_sku text; v_pm public.payment_method; v_dm public.delivery_method; v_order text;
begin
	select sanity_product_id, sku, payment_method, delivery_method
	into v_pid, v_sku, v_pm, v_dm from test_ctx;

	v_order := public.create_order_v2(
		v_pm, v_dm, 'Prueba','Uno','prueba1@example.com','999999999',
		'Lima','Lima','Miraflores','Av. Prueba 123', null, null,
		jsonb_build_array(jsonb_build_object(
			'sanityProductId', v_pid, 'productSku', v_sku,
			'sanityProductSlug','prueba','productName','Prueba',
			'quantity',1,'unitPrice',1
		)),
		'test-req-001'
	);
	insert into test_results values ('2_misma_clave_repetida', 'order=' || v_order);
exception when others then
	insert into test_results values ('2_misma_clave_repetida', 'ERROR: ' || sqlerrm);
end $$;

insert into test_results
select '2_stock_tras_repetir', stock_quantity::text
from public.catalog_variants cv join test_ctx tc
	on cv.sanity_product_id = tc.sanity_product_id and cv.sku = tc.sku;

-- 3) Clave distinta pidiendo mas del disponible (9) -> stock insuficiente
do $$
declare v_pid text; v_sku text; v_pm public.payment_method; v_dm public.delivery_method; v_order text;
begin
	select sanity_product_id, sku, payment_method, delivery_method
	into v_pid, v_sku, v_pm, v_dm from test_ctx;

	v_order := public.create_order_v2(
		v_pm, v_dm, 'Prueba','Dos','prueba2@example.com','999999998',
		'Lima','Lima','Miraflores','Av. Prueba 456', null, null,
		jsonb_build_array(jsonb_build_object(
			'sanityProductId', v_pid, 'productSku', v_sku,
			'sanityProductSlug','prueba','productName','Prueba',
			'quantity',100,'unitPrice',1
		)),
		'test-req-002'
	);
	insert into test_results values ('3_clave_distinta_excede_stock', 'order=' || v_order);
exception when others then
	insert into test_results values ('3_clave_distinta_excede_stock', 'ERROR: ' || sqlerrm);
end $$;

-- 4) Misma clave que el caso 1 (test-req-001) con datos DISTINTOS ->
--    IDEMPOTENCY_MISMATCH, sin tocar stock
do $$
declare v_pid text; v_sku text; v_pm public.payment_method; v_dm public.delivery_method; v_order text;
begin
	select sanity_product_id, sku, payment_method, delivery_method
	into v_pid, v_sku, v_pm, v_dm from test_ctx;

	v_order := public.create_order_v2(
		v_pm, v_dm, 'Prueba','Otro','prueba-otro@example.com','999999997',
		'Lima','Lima','Miraflores','Av. Prueba 789', null, null,
		jsonb_build_array(jsonb_build_object(
			'sanityProductId', v_pid, 'productSku', v_sku,
			'sanityProductSlug','prueba','productName','Prueba',
			'quantity',1,'unitPrice',1
		)),
		'test-req-001'
	);
	insert into test_results values ('4_misma_clave_datos_distintos', 'order=' || v_order);
exception when others then
	insert into test_results values ('4_misma_clave_datos_distintos', 'ERROR: ' || sqlerrm);
end $$;

insert into test_results
select '4_stock_tras_mismatch', stock_quantity::text
from public.catalog_variants cv join test_ctx tc
	on cv.sanity_product_id = tc.sanity_product_id and cv.sku = tc.sku;

-- 5) Pedido con 2 items, el segundo con SKU inexistente -> se revierte
--    todo, incluido el descuento del primer item (stock debe seguir en 9)
do $$
declare v_pid text; v_sku text; v_pm public.payment_method; v_dm public.delivery_method; v_order text;
begin
	select sanity_product_id, sku, payment_method, delivery_method
	into v_pid, v_sku, v_pm, v_dm from test_ctx;

	v_order := public.create_order_v2(
		v_pm, v_dm, 'Prueba','Tres','prueba3@example.com','999999996',
		'Lima','Lima','Miraflores','Av. Prueba 000', null, null,
		jsonb_build_array(
			jsonb_build_object(
				'sanityProductId', v_pid, 'productSku', v_sku,
				'sanityProductSlug','prueba','productName','Prueba',
				'quantity',1,'unitPrice',1
			),
			jsonb_build_object(
				'sanityProductId', 'sku-inexistente-xyz', 'productSku', 'NOPE-000',
				'sanityProductSlug','nope','productName','No existe',
				'quantity',1,'unitPrice',1
			)
		),
		'test-req-003'
	);
	insert into test_results values ('5_segundo_item_falla', 'order=' || v_order);
exception when others then
	insert into test_results values ('5_segundo_item_falla', 'ERROR: ' || sqlerrm);
end $$;

insert into test_results
select '5_stock_tras_fallo_parcial', stock_quantity::text
from public.catalog_variants cv join test_ctx tc
	on cv.sanity_product_id = tc.sanity_product_id and cv.sku = tc.sku;

select * from test_results order by step;

rollback;
