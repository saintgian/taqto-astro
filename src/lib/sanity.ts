import {createClient} from '@sanity/client'

import {
  createImageUrlBuilder,
  type SanityImageSource,
} from '@sanity/image-url'

export const sanityClient = createClient({
  projectId: 'bap0il8i',
  dataset: 'production',
  apiVersion: '2026-07-20',
  useCdn: false,
})

const builder = createImageUrlBuilder(sanityClient)

export function urlForImage(
  source: SanityImageSource,
) {
  return builder.image(source)
}