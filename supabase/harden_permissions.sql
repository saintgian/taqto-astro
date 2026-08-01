-- NO EJECUTADO CONTRA SUPABASE REMOTO. Correr DESPUES de
-- supabase/catalog_mirror.sql y supabase/harden_create_order.sql
-- (Dashboard de Supabase -> SQL Editor -> pegar -> Run).
--
-- Que hace: deja `create_order_v2` (supabase/harden_create_order.sql)
-- como la unica via de checkout publico, sin borrar nada.
--   1) Revoca EXECUTE de PUBLIC, anon y authenticated sobre el RPC
--      anterior (`create_order` de 16 argumentos, sin idempotencia ni
--      validacion contra catalogo). La funcion se queda tal cual esta
--      por si algo mas la usa (via el rol propietario o service_role);
--      simplemente ningun rol de cliente puede llamarla.
--   2) Revoca EXECUTE de PUBLIC y authenticated sobre `create_order_v2`
--      y se lo vuelve a conceder solo a `anon` (revoke+grant explicito,
--      no incremental, para que el resultado final sea el mismo sin
--      importar el estado previo de los grants).
--   3) Confirma que RLS este activo en las tablas de pedidos y le
--      revoca a `anon` cualquier acceso directo (select/insert/update/
--      delete) que pudiera existir sobre ellas. La escritura sigue
--      siendo solo a traves de `create_order_v2` (security definer).
--
-- Por que ahora si se toca `authenticated` en las funciones (a
-- diferencia de una version anterior de este archivo): la introspeccion
-- del esquema remoto encontro que Postgres concede EXECUTE a PUBLIC por
-- defecto en toda funcion nueva, salvo que se revoque explicitamente.
-- Eso significaba que `authenticated` (y cualquier otro rol) heredaba
-- acceso a ambos RPC sin que nadie lo hubiera concedido a proposito. Se
-- revoca aqui para las funciones especificamente por minimo privilegio,
-- aunque el proyecto no tiene hoy un flujo de login visible en el repo
-- (el cliente de Supabase se crea con `persistSession: false` y la
-- publishable key, ver src/lib/supabase.ts) y el checkout en la practica
-- siempre corre como `anon`.
--
-- Las tablas (`orders`/`order_items`/etc.) solo se revocan para `anon`,
-- sin tocar `authenticated`: si en el dashboard existe algo mas (un
-- panel interno, por ejemplo) que dependa de `authenticated` sobre esas
-- tablas, no se puede verificar desde el repositorio local -- revisarlo
-- antes de correr este archivo.

revoke
execute on function public.create_order (
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
	numeric,
	numeric,
	numeric,
	jsonb
)
from
	public,
	anon,
	authenticated;

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

alter table if exists public.orders enable row level security;

alter table if exists public.order_items enable row level security;

alter table if exists public.order_status_history enable row level security;

alter table if exists public.order_payments enable row level security;

revoke all on public.orders
from
	anon;

revoke all on public.order_items
from
	anon;

do $$
begin
	if to_regclass('public.order_status_history') is not null then
		execute 'revoke all on public.order_status_history from anon';
	end if;

	if to_regclass('public.order_payments') is not null then
		execute 'revoke all on public.order_payments from anon';
	end if;
end;
$$;

-- Verificacion manual pendiente (no se puede confirmar desde el repo):
-- revisar en el dashboard que ninguna policy de RLS ya existente sobre
-- `orders`/`order_items`/`order_status_history`/`order_payments` le
-- otorgue a `anon` lectura o escritura por otra via (por ejemplo una
-- policy `using (true)` heredada de una prueba). RLS activo sin
-- policies deniega todo por defecto, pero una policy vieja permisiva
-- seguiria abriendo el acceso.
