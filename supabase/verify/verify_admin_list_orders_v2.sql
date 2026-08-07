-- Solo lectura. No modifica datos, no crea nada. Correr DESPUES de
-- admin_list_orders_v2_production.sql en Supabase Dashboard -> SQL
-- Editor, y revisar cada resultado a mano.

-- 1) Existencia y firma.
select to_regprocedure(
	'public.admin_list_orders_v2(text, public.order_status, public.payment_method, public.delivery_method, date, date, integer, integer)'
) as admin_list_orders_v2;

-- 2) security definer + search_path vacio.
select p.proname, p.prosecdef as is_security_definer, p.proconfig
from pg_proc p
	join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
	and p.proname = 'admin_list_orders_v2';

-- 3) ACL: solo 'authenticated' con EXECUTE.
select routine_name, grantee, privilege_type
from information_schema.role_routine_grants
where routine_schema = 'public'
	and routine_name = 'admin_list_orders_v2'
order by grantee;

-- 4) admin_list_orders (v1) sigue existiendo intacta, no fue reemplazada.
select to_regprocedure(
	'public.admin_list_orders(text, public.order_status, public.payment_method, public.delivery_method, date, date, integer, integer)'
) as admin_list_orders_v1_sigue_existiendo;

-- 5) No se agrego ningun grant directo nuevo sobre orders/order_items.
select grantee, table_name, privilege_type
from information_schema.role_table_grants
where table_schema = 'public'
	and table_name in ('orders', 'order_items')
	and grantee in ('anon', 'authenticated'); -- esperado: 0 filas

-- 6) v1 y v2 deben devolver el mismo total_count y los mismos ids en el
-- mismo orden para los mismos filtros (sin filtros, primera pagina).
select id, order_number, total_count from public.admin_list_orders(null, null, null, null, null, null, 20, 0);

select id, order_number, total_count, first_item_product_name, first_item_variant_label, first_item_quantity, items_extra_count
from public.admin_list_orders_v2(null, null, null, null, null, null, 20, 0);
-- esperado: mismas filas/orden/total_count en ambas; v2 ademas trae el
-- resumen del primer articulo sin filas adicionales.
