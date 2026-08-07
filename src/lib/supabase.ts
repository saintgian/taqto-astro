import {createClient} from '@supabase/supabase-js'

const supabaseUrl =
  import.meta.env.PUBLIC_SUPABASE_URL

const supabasePublishableKey =
  import.meta.env.PUBLIC_SUPABASE_PUBLISHABLE_KEY

// Si estas variables faltan (por ejemplo, en un build de CI sin el
// .env local), NO lanzamos aqui: este modulo se importa desde el
// script de /carrito/, y una excepcion durante la evaluacion del
// modulo detiene TODO ese script, incluido el render del carrito, que
// no depende de Supabase. En su lugar, `supabase` queda en null y
// quien intente usarlo (crear pedido) debe comprobarlo antes.
//
// persistSession/autoRefreshToken en true: lo necesita /admin/pedidos/
// (unico consumidor de supabase.auth en el proyecto): sin persistSession
// la sesion del administrador se perderia en cada recarga de pagina, y
// sin autoRefreshToken expiraria en plena sesion de trabajo.
// detectSessionInUrl se deja en false: el proyecto no usa magic link ni
// OAuth (login solo por email+password), asi que no hay redirect con
// token en la URL que procesar.
//
// OJO: este cliente SI puede arrastrar la sesion del admin al resto del
// sitio. Al persistir la sesion en localStorage (mismo origen), cualquier
// pagina que importe `supabase` mientras el admin esta logueado envia el
// JWT `authenticated` en vez de la clave `anon`, y create_order_v2 solo
// esta autorizado para `anon`: el checkout fallaba en el navegador del
// administrador. Por eso el checkout publico usa `supabasePublic` (abajo),
// que nunca lee ni escribe esa sesion.
export const supabase =
  supabaseUrl && supabasePublishableKey
    ? createClient(
        supabaseUrl,
        supabasePublishableKey,
        {
          auth: {
            persistSession: true,
            autoRefreshToken: true,
            detectSessionInUrl: false,
          },
        },
      )
    : null

// Cliente para el sitio publico (checkout / crear pedido). Mismo proyecto
// y misma publishable key que `supabase`, pero deliberadamente sin sesion:
// no persiste, no refresca y usa su propio storageKey, de modo que jamas
// lee la sesion que /admin/ deja en localStorage. Asi las llamadas del
// checkout siempre salen como `anon`, que es el rol al que se le concedio
// EXECUTE sobre create_order_v2, incluso si el administrador tiene el
// panel abierto en el mismo navegador y perfil.
export const supabasePublic =
  supabaseUrl && supabasePublishableKey
    ? createClient(supabaseUrl, supabasePublishableKey, {
        auth: {
          persistSession: false,
          autoRefreshToken: false,
          detectSessionInUrl: false,
          storageKey: 'taqto-public-no-session',
        },
      })
    : null