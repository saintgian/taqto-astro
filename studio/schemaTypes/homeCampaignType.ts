import {defineField, defineType} from 'sanity'

export const homeCampaignType = defineType({
  name: 'homeCampaign',
  title: 'Campaña de inicio',
  type: 'document',

  fields: [
    defineField({
      name: 'enabled',
      title: 'Campaña activa',
      type: 'boolean',
      initialValue: false,
      description:
        'Actívala para mostrar la campaña en la portada. Si está apagada o incompleta, la portada usa el contenido de respaldo.',
    }),

    defineField({
      name: 'eyebrow',
      title: 'Etiqueta breve',
      type: 'string',
      validation: (rule) => rule.max(60),
    }),

    defineField({
      name: 'title',
      title: 'Título',
      type: 'string',
      validation: (rule) => rule.max(120),
    }),

    defineField({
      name: 'description',
      title: 'Descripción',
      type: 'text',
      rows: 3,
      validation: (rule) => rule.max(240),
    }),

    defineField({
      name: 'ctaLabel',
      title: 'Texto del botón',
      type: 'string',
      validation: (rule) => rule.max(40),
    }),

    defineField({
      name: 'ctaLink',
      title: 'Enlace del botón',
      type: 'string',
      description:
        'Ruta interna (ej: categorias/kits-y-regalos/) o URL completa.',
    }),

    defineField({
      name: 'desktopImage',
      title: 'Imagen principal',
      type: 'image',
      options: {
        hotspot: true,
      },
    }),

    defineField({
      name: 'mobileImage',
      title: 'Imagen para móvil (opcional)',
      type: 'image',
      options: {
        hotspot: true,
      },
    }),

    defineField({
      name: 'alt',
      title: 'Texto alternativo',
      type: 'string',
      validation: (rule) => rule.max(150),
    }),

    defineField({
      name: 'theme',
      title: 'Tema',
      type: 'string',
      options: {
        layout: 'radio',
        list: [
          {title: 'Claro', value: 'light'},
          {title: 'Oscuro', value: 'dark'},
        ],
      },
      initialValue: 'dark',
    }),

    defineField({
      name: 'layoutMode',
      title: 'Modo de composición',
      type: 'string',
      description:
        'Editorial: texto sobre la imagen. Producto destacado: contenido de campaña junto a una tarjeta de producto.',
      options: {
        layout: 'radio',
        list: [
          {title: 'Editorial', value: 'editorial'},
          {title: 'Producto destacado', value: 'productSpotlight'},
        ],
      },
      initialValue: 'editorial',
    }),

    defineField({
      name: 'contentPosition',
      title: 'Posición del texto',
      type: 'string',
      description: 'Solo aplica al modo editorial.',
      options: {
        layout: 'radio',
        list: [
          {title: 'Izquierda', value: 'left'},
          {title: 'Centro', value: 'center'},
          {title: 'Derecha', value: 'right'},
        ],
      },
      initialValue: 'left',
      hidden: ({document}) => document?.layoutMode === 'productSpotlight',
    }),

    defineField({
      name: 'featuredProduct',
      title: 'Producto destacado',
      type: 'reference',
      description:
        'Solo aplica al modo "Producto destacado". Debe ser un producto publicado y visible.',
      to: [{type: 'product'}],
      hidden: ({document}) => document?.layoutMode !== 'productSpotlight',
    }),

    defineField({
      name: 'overlayStrength',
      title: 'Intensidad del overlay',
      type: 'string',
      description:
        'Controla el oscurecimiento sobre la imagen para asegurar contraste del texto.',
      options: {
        layout: 'radio',
        list: [
          {title: 'Suave', value: 'soft'},
          {title: 'Media', value: 'medium'},
          {title: 'Fuerte', value: 'strong'},
        ],
      },
      initialValue: 'medium',
    }),
  ],

  preview: {
    select: {
      title: 'title',
      enabled: 'enabled',
      media: 'desktopImage',
    },

    prepare({title, enabled, media}) {
      return {
        title: title || 'Campaña de inicio',
        media,
        subtitle: enabled ? 'Activa' : 'Inactiva',
      }
    },
  },
})
