import {
  defineArrayMember,
  defineField,
  defineType,
} from 'sanity'

const PRODUCT_MODES = {
  UNIQUE: 'unique',
  WOOD: 'wood',
  SIZE: 'size',
  WOOD_SIZE: 'woodSize',
} as const

export const productType = defineType({
  name: 'product',
  title: 'Productos',
  type: 'document',

  groups: [
    {
      name: 'general',
      title: 'Información',
      default: true,
    },
    {
      name: 'media',
      title: 'Imágenes',
    },
    {
      name: 'variations',
      title: 'Precio y variantes',
    },
    {
      name: 'personalization',
      title: 'Personalización',
    },
    {
      name: 'seo',
      title: 'SEO',
    },
  ],

  orderings: [
    {
      title: 'Nombre: A–Z',
      name: 'titleAscending',
      by: [{field: 'title', direction: 'asc'}],
    },

    {
      title: 'Más recientes',
      name: 'createdDescending',
      by: [{field: '_createdAt', direction: 'desc'}],
    },
  ],

  initialValue: {
    productMode: PRODUCT_MODES.UNIQUE,
    active: true,
    featured: false,
    engravingIncluded: true,
    corporateEligible: true,
  },

  fields: [
    defineField({
      name: 'title',
      title: 'Nombre del producto',
      type: 'string',
      group: 'general',
      validation: (rule) =>
        rule.required().min(3).max(120),
    }),

    defineField({
      name: 'slug',
      title: 'URL del producto',
      type: 'slug',
      group: 'general',
      options: {
        source: 'title',
        maxLength: 96,
      },
      validation: (rule) => rule.required(),
    }),

    defineField({
      name: 'sku',
      title: 'SKU general',
      type: 'string',
      group: 'general',
      description:
        'Código del producto. Las variantes también pueden tener su propio SKU.',
      validation: (rule) =>
        rule.required().max(40),
    }),

    defineField({
      name: 'category',
      title: 'Categoría',
      type: 'reference',
      group: 'general',
      to: [{type: 'category'}],
      validation: (rule) => rule.required(),
    }),

    defineField({
      name: 'subcategory',
      title: 'Subcategoría',
      type: 'reference',
      group: 'general',
      to: [{type: 'subcategory'}],
    }),

    defineField({
      name: 'shortDescription',
      title: 'Descripción corta',
      type: 'text',
      rows: 3,
      group: 'general',
      validation: (rule) =>
        rule.required().min(20).max(240),
    }),

    defineField({
      name: 'description',
      title: 'Descripción completa',
      type: 'array',
      group: 'general',

      of: [
        defineArrayMember({
          type: 'block',
        }),
      ],

      validation: (rule) => rule.required(),
    }),

    defineField({
      name: 'materials',
      title: 'Otros materiales',
      type: 'array',
      group: 'general',
      description:
        'Ejemplo: cuero natural, acero inoxidable o aceite apto para alimentos.',

      of: [
        defineArrayMember({
          type: 'string',
        }),
      ],

      options: {
        layout: 'tags',
      },
    }),

    defineField({
      name: 'careInstructions',
      title: 'Cuidados',
      type: 'text',
      rows: 4,
      group: 'general',
    }),

    defineField({
      name: 'gallery',
      title: 'Galería del producto',
      type: 'array',
      group: 'media',
      description:
        'La primera imagen será la fotografía principal.',

      validation: (rule) =>
        rule.required().min(1).max(12),

      of: [
        defineArrayMember({
          name: 'productImage',
          title: 'Fotografía',
          type: 'image',

          options: {
            hotspot: true,
          },

          fields: [
            defineField({
              name: 'alt',
              title: 'Texto alternativo',
              type: 'string',
              validation: (rule) =>
                rule.required().min(5).max(150),
            }),

            defineField({
              name: 'caption',
              title: 'Nota interna',
              type: 'string',
            }),
          ],
        }),
      ],
    }),

    defineField({
      name: 'productMode',
      title: 'Modalidad del producto',
      type: 'string',
      group: 'variations',
      description:
        'Define qué opciones podrá escoger el cliente.',

      options: {
        layout: 'radio',

        list: [
          {
            title: 'Producto único',
            value: PRODUCT_MODES.UNIQUE,
          },
          {
            title: 'El cliente elige madera',
            value: PRODUCT_MODES.WOOD,
          },
          {
            title: 'El cliente elige tamaño',
            value: PRODUCT_MODES.SIZE,
          },
          {
            title: 'El cliente elige madera y tamaño',
            value: PRODUCT_MODES.WOOD_SIZE,
          },
        ],
      },

      validation: (rule) => rule.required(),
    }),

    defineField({
      name: 'uniqueProduct',
      title: 'Precio y stock del producto único',
      type: 'object',
      group: 'variations',

      hidden: ({document}) =>
        document?.productMode !== PRODUCT_MODES.UNIQUE,

      fields: [
        defineField({
          name: 'wood',
          title: 'Madera fija',
          type: 'reference',
          description:
            'Opcional. Sirve para informar la madera aunque el cliente no pueda escogerla.',
          to: [{type: 'wood'}],
        }),

        defineField({
          name: 'size',
          title: 'Tamaño fijo',
          type: 'reference',
          description:
            'Opcional. Sirve para informar el tamaño aunque el cliente no pueda escogerlo.',
          to: [{type: 'productSize'}],
        }),

        defineField({
          name: 'price',
          title: 'Precio regular',
          type: 'number',
          validation: (rule) =>
            rule.required().positive().precision(2),
        }),

        defineField({
          name: 'salePrice',
          title: 'Precio de oferta',
          type: 'number',
          description:
            'Déjalo vacío cuando no haya promoción.',

          validation: (rule) =>
            rule.positive().precision(2).custom(
              (salePrice, context) => {
                const parent = context.parent as {
                  price?: number
                }

                if (
                  typeof salePrice === 'number' &&
                  typeof parent?.price === 'number' &&
                  salePrice >= parent.price
                ) {
                  return 'El precio de oferta debe ser menor que el precio regular.'
                }

                return true
              },
            ),
        }),

        defineField({
          name: 'stockQuantity',
          title: 'Cantidad disponible',
          type: 'number',
          initialValue: 0,
          validation: (rule) =>
            rule.required().integer().min(0),
        }),

        defineField({
          name: 'available',
          title: 'Disponible',
          type: 'boolean',
          initialValue: true,
        }),
      ],
    }),

    defineField({
      name: 'variants',
      title: 'Variantes disponibles',
      type: 'array',
      group: 'variations',
      description:
        'Crea una fila por cada combinación que se pueda comprar.',

      hidden: ({document}) =>
        document?.productMode === PRODUCT_MODES.UNIQUE,

      validation: (rule) =>
        rule.custom((variants, context) => {
          const document = context.document as {
            productMode?: string
          }

          if (
            document?.productMode !== PRODUCT_MODES.UNIQUE &&
            (!Array.isArray(variants) || variants.length === 0)
          ) {
            return 'Añade al menos una variante.'
          }

          return true
        }),

      of: [
        defineArrayMember({
          name: 'productVariant',
          title: 'Variante',
          type: 'object',

          fields: [
            defineField({
              name: 'wood',
              title: 'Madera',
              type: 'reference',
              to: [{type: 'wood'}],

              hidden: ({document}) =>
                document?.productMode !== PRODUCT_MODES.WOOD &&
                document?.productMode !== PRODUCT_MODES.WOOD_SIZE,
            }),

            defineField({
              name: 'size',
              title: 'Tamaño',
              type: 'reference',
              to: [{type: 'productSize'}],

              hidden: ({document}) =>
                document?.productMode !== PRODUCT_MODES.SIZE &&
                document?.productMode !== PRODUCT_MODES.WOOD_SIZE,
            }),

            defineField({
              name: 'sku',
              title: 'SKU de la variante',
              type: 'string',
              validation: (rule) =>
                rule.required().max(50),
            }),

            defineField({
              name: 'price',
              title: 'Precio regular',
              type: 'number',
              validation: (rule) =>
                rule.required().positive().precision(2),
            }),

            defineField({
              name: 'salePrice',
              title: 'Precio de oferta',
              type: 'number',

              validation: (rule) =>
                rule.positive().precision(2).custom(
                  (salePrice, context) => {
                    const parent = context.parent as {
                      price?: number
                    }

                    if (
                      typeof salePrice === 'number' &&
                      typeof parent?.price === 'number' &&
                      salePrice >= parent.price
                    ) {
                      return 'La oferta debe ser menor que el precio regular.'
                    }

                    return true
                  },
                ),
            }),

            defineField({
              name: 'stockQuantity',
              title: 'Cantidad disponible',
              type: 'number',
              initialValue: 0,
              validation: (rule) =>
                rule.required().integer().min(0),
            }),

            defineField({
              name: 'active',
              title: 'Variante disponible',
              type: 'boolean',
              initialValue: true,
            }),
          ],

          preview: {
            select: {
              wood: 'wood.title',
              size: 'size.title',
              sku: 'sku',
              price: 'price',
              salePrice: 'salePrice',
              stock: 'stockQuantity',
              active: 'active',
            },

            prepare({
              wood,
              size,
              sku,
              price,
              salePrice,
              stock,
              active,
            }) {
              const optionName =
                [wood, size].filter(Boolean).join(' · ') ||
                'Variante sin opciones'

              const visiblePrice =
                typeof salePrice === 'number'
                  ? salePrice
                  : price

              return {
                title: optionName,

                subtitle:
                  `${active === false ? 'Inactiva' : 'Activa'} · ` +
                  `${sku || 'Sin SKU'} · ` +
                  `S/ ${visiblePrice ?? 0} · ` +
                  `${stock ?? 0} unidades`,
              }
            },
          },
        }),
      ],
    }),

    defineField({
      name: 'saleStart',
      title: 'Inicio de la oferta',
      type: 'datetime',
      group: 'variations',
      description:
        'Opcional. Se aplica a los precios de oferta definidos.',
    }),

    defineField({
      name: 'saleEnd',
      title: 'Fin de la oferta',
      type: 'datetime',
      group: 'variations',
      description:
        'Opcional. Al finalizar se vuelve a mostrar el precio regular.',
    }),

    defineField({
      name: 'featured',
      title: 'Producto destacado',
      type: 'boolean',
      group: 'variations',
    }),

    defineField({
      name: 'active',
      title: 'Producto visible',
      type: 'boolean',
      group: 'variations',
      description:
        'Desactívalo para ocultarlo sin eliminarlo.',
    }),

    defineField({
      name: 'engravingIncluded',
      title: 'Grabado láser personalizado gratuito',
      type: 'boolean',
      group: 'personalization',
    }),

    defineField({
      name: 'engravingTypes',
      title: 'Contenido permitido para el grabado',
      type: 'array',
      group: 'personalization',

      hidden: ({document}) =>
        document?.engravingIncluded !== true,

      of: [
        defineArrayMember({
          type: 'string',
        }),
      ],

      options: {
        list: [
          {
            title: 'Nombre',
            value: 'name',
          },
          {
            title: 'Frase',
            value: 'phrase',
          },
          {
            title: 'Fecha',
            value: 'date',
          },
          {
            title: 'Logotipo',
            value: 'logo',
          },
        ],
      },
    }),

    defineField({
      name: 'engravingMaxCharacters',
      title: 'Máximo de caracteres',
      type: 'number',
      group: 'personalization',

      hidden: ({document}) =>
        document?.engravingIncluded !== true,

      validation: (rule) =>
        rule.integer().min(1),
    }),

    defineField({
      name: 'personalizationNotes',
      title: 'Indicaciones de personalización',
      type: 'text',
      rows: 4,
      group: 'personalization',

      hidden: ({document}) =>
        document?.engravingIncluded !== true,
    }),

    defineField({
      name: 'corporateEligible',
      title: 'Disponible para pedidos corporativos',
      type: 'boolean',
      group: 'personalization',
    }),

    defineField({
      name: 'corporateBrandRule',
      title: 'Regla corporativa',
      type: 'string',
      group: 'personalization',
      readOnly: true,

      initialValue:
        'El sello TAQTO siempre se muestra junto al logo del cliente. Nunca se ofrece marca blanca.',
    }),

    defineField({
      name: 'metaTitle',
      title: 'Título SEO',
      type: 'string',
      group: 'seo',
      validation: (rule) => rule.max(60),
    }),

    defineField({
      name: 'metaDescription',
      title: 'Descripción SEO',
      type: 'text',
      rows: 3,
      group: 'seo',
      validation: (rule) => rule.max(160),
    }),

    defineField({
      name: 'seoImage',
      title: 'Imagen para compartir',
      type: 'image',
      group: 'seo',
      options: {
        hotspot: true,
      },
    }),
  ],

  preview: {
    select: {
      title: 'title',
      media: 'gallery.0',
      sku: 'sku',
      productMode: 'productMode',
      active: 'active',
    },

    prepare({
      title,
      media,
      sku,
      productMode,
      active,
    }) {
      const modeLabels: Record<string, string> = {
        unique: 'Producto único',
        wood: 'Elección de madera',
        size: 'Elección de tamaño',
        woodSize: 'Madera y tamaño',
      }

      return {
        title: title || 'Producto sin nombre',
        media,

        subtitle:
          `${active === false ? 'Oculto' : 'Visible'} · ` +
          `${sku || 'Sin SKU'} · ` +
          `${modeLabels[productMode] || 'Sin modalidad'}`,
      }
    },
  },
})