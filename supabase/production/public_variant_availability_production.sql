-- NO EJECUTADO CONTRA SUPABASE REMOTO. Preparado localmente para que el
-- propietario del proyecto lo revise y lo corra el mismo (Dashboard de
-- Supabase -> SQL Editor -> pegar -> Run).
--
-- Requiere que ya esten aplicados (los tres ya estan activos en el
-- proyecto remoto):
--   1) supabase/catalog_mirror.sql
--   2) supabase/harden_create_order.sql
--   3) supabase/harden_permissions.sql
--   4) supabase/harden_stock_atomic.sql
--
-- Este archivo NO modifica ninguna de esas piezas. No toca
-- create_order_v2, no toca su logica atomica, no crea ni altera tablas,
-- no agrega policies de RLS y no concede ningun acceso directo sobre
-- catalog_products ni catalog_variants. Solo agrega una funcion de
-- lectura. Es idempotente: `create or replace` + revoke/grant explicitos,
-- asi que correrlo dos veces deja exactamente el mismo estado final.
--
-- ------------------------------------------------------------
-- Por que hace falta
-- ------------------------------------------------------------
-- Astro genera las fichas de producto estaticamente: el numero de stock
-- que ve el cliente es el que tenia Sanity en el momento del build. Desde
-- harden_stock_atomic.sql, Supabase descuenta
-- catalog_variants.stock_quantity en el mismo instante de la compra. Los
-- dos numeros se separan apenas ocurre la primera venta y no vuelven a
-- coincidir hasta el siguiente build + `npm run sync:catalog`.
--
-- Eso NO es un agujero de sobreventa: create_order_v2 sigue siendo la
-- autoridad atomica y rechaza cualquier pedido por encima del stock real.
-- Es un problema de UX: la ficha puede ofrecer unidades que ya no existen
-- y el cliente solo se entera al final del checkout.
--
-- Esta funcion le da al navegador la minima informacion necesaria para
-- mostrar disponibilidad al dia, sin abrirle la tabla.
--
-- ------------------------------------------------------------
-- Superficie expuesta (deliberadamente minima)
-- ------------------------------------------------------------
-- Entra:  el _id de Sanity del producto (dato publico: ya viaja en el
--         HTML de la ficha y en cada pedido).
-- Sale:   una fila por variante VENDIBLE, con solo dos campos:
--           sku             -- ya impreso en la ficha publica
--           stock_quantity  -- ya impreso en la ficha publica
--
-- NO devuelve: price, sale_price, currency, ids internos (variant.id,
-- product_id), sanity_product_id, fechas de sincronizacion, ni ningun
-- dato de pedidos o de movimientos de stock. Tampoco permite listar el
-- catalogo: hay que conocer de antemano el _id del producto, y ese _id
-- solo se obtiene de una ficha que ya publica su propio stock. Es decir,
-- no revela nada que la pagina publica no muestre ya -- solo lo muestra
-- actualizado.
--
-- Variantes inactivas y productos inactivos se omiten de la respuesta en
-- vez de devolverse con stock 0: el frontend trata un SKU ausente como no
-- vendible, que es exactamente lo que create_order_v2 haria con el.
--
-- `stable` (no `volatile`): la funcion no escribe nada.
-- `security definer` + `search_path = ''`: mismo patron que las funciones
-- ya aplicadas en este proyecto (admin_inventory_metrics,
-- admin_list_inventory); todos los objetos van calificados con `public.`
-- para que un search_path vacio no pueda resolver a otro esquema.

create or replace function public.public_variant_availability (p_sanity_product_id text) returns table (sku text, stock_quantity integer) language sql stable security definer
set
	search_path = '' as $$
	select cv.sku, cv.stock_quantity
	from public.catalog_variants cv
		join public.catalog_products cp on cp.id = cv.product_id
	where
		-- nullif+trim: un argumento nulo, vacio o de solo espacios no
		-- coincide con ninguna fila (la comparacion da null), asi que la
		-- funcion devuelve cero filas en vez de lanzar un error.
		cv.sanity_product_id = nullif(trim(coalesce(p_sanity_product_id, '')), '')
		and cv.active = true
		and cp.active = true;
$$;

comment on function public.public_variant_availability (text) is 'Disponibilidad publica de un producto: devuelve solo (sku, stock_quantity) de las variantes activas de un producto activo, dado el _id de Sanity. Sirve para que la ficha estatica de Astro reemplace el stock del build por el stock operativo real. No expone precios, ids internos ni ningun otro campo. La autoridad final sobre el stock sigue siendo create_order_v2.';

-- Postgres concede EXECUTE a PUBLIC automaticamente en toda funcion
-- nueva, salvo que se revoque explicitamente. Sin este revoke, cualquier
-- rol heredaria acceso sin que nadie se lo hubiera concedido a proposito.
-- Se revoca tambien a `authenticated`: la ficha publica consulta con
-- `supabasePublic` (src/lib/supabase.ts), un cliente sin sesion que
-- siempre sale como `anon` aunque el administrador tenga el panel abierto
-- en el mismo navegador. `anon` es por lo tanto el unico rol que la
-- necesita, igual que ya ocurre con create_order_v2.
revoke
execute on function public.public_variant_availability (text)
from
	public,
	anon,
	authenticated;

grant
execute on function public.public_variant_availability (text) to anon;

-- Fin. No se concede ningun grant nuevo sobre catalog_products ni sobre
-- catalog_variants: siguen con RLS activo, sin policies y sin acceso
-- directo para anon/authenticated.
