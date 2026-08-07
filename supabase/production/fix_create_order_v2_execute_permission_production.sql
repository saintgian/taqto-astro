-- NO EJECUTADO CONTRA SUPABASE REMOTO. Preparado para que el propietario
-- del proyecto lo corra el mismo (Dashboard de Supabase -> SQL Editor ->
-- pegar -> Run) despues de revisarlo.
--
-- ------------------------------------------------------------
-- Causa raiz (diagnostico, no ejecutado, solo lectura de codigo local)
-- ------------------------------------------------------------
-- El checkout publico (src/pages/carrito.astro) llama:
--   supabase.rpc('create_order_v2', { p_payment_method, p_delivery_method,
--     p_customer_first_name, ..., p_items, p_client_request_id })
-- usando el cliente anonimo (PUBLIC_SUPABASE_PUBLISHABLE_KEY, sin login,
-- ver src/lib/supabase.ts) -- es decir, la llamada siempre corre como el
-- rol `anon`.
--
-- El error reproducido en produccion es exactamente:
--   POST .../rest/v1/rpc/create_order_v2 -> 403
--   "permission denied for function create_order_v2"
-- Ese mensaje es el que Postgres da cuando el rol NO tiene privilegio
-- EXECUTE sobre la funcion -- no "function does not exist" (seria
-- PGRST202/42883, y el frontend ya distingue ese caso en carrito.astro)
-- ni un error de una tabla interna. La comprobacion de EXECUTE ocurre
-- antes de que el cuerpo de la funcion corra, asi que esto no tiene que
-- ver con RLS de `orders`/`order_items`/`catalog_variants` ni con la
-- logica de stock/idempotencia: el rol `anon` no tiene EXECUTE sobre la
-- firma exacta de 14 argumentos de `create_order_v2` en el proyecto
-- remoto ahora mismo, sin importar que los archivos locales
-- (harden_create_order.sql, harden_permissions.sql, harden_stock_atomic.sql)
-- documenten un `grant execute ... to anon` -- ese grant no esta
-- surtiendo efecto en el proyecto real hoy (o se perdio despues de
-- aplicarse, por ejemplo por un hardening posterior que revoco EXECUTE de
-- todas las funciones del schema sin volver a conceder este caso
-- puntual). Confirmar el estado exacto antes/despues de este archivo con
-- supabase/verify_create_order_v2_execute_permission.sql.
--
-- ------------------------------------------------------------
-- Que hace este archivo (minimo, idempotente)
-- ------------------------------------------------------------
-- Un unico GRANT (precedido de un REVOKE explicito, no incremental, para
-- que el resultado final sea el mismo sin importar el estado previo)
-- sobre la funcion `create_order_v2` YA EXISTENTE, usando su firma
-- exacta de 14 argumentos para no tocar por error ninguna otra
-- sobrecarga. No crea, reemplaza ni recrea la funcion. No modifica su
-- logica interna (stock, precio, idempotencia). No toca tablas ni datos.
-- Mantiene la politica de minimo privilegio ya documentada en el
-- proyecto: PUBLIC y authenticated sin EXECUTE, unicamente `anon` (el rol
-- real que usa el checkout publico) con EXECUTE.
--
-- Si en el futuro el proyecto agrega un checkout autenticado que use
-- esta misma RPC, agregar `authenticated` al GRANT de abajo entonces --
-- no antes, sin evidencia de ese flujo.

revoke execute on function public.create_order_v2 (
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
