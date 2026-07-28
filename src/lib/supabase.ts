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
export const supabase =
  supabaseUrl && supabasePublishableKey
    ? createClient(
        supabaseUrl,
        supabasePublishableKey,
        {
          auth: {
            persistSession: false,
            autoRefreshToken: false,
            detectSessionInUrl: false,
          },
        },
      )
    : null