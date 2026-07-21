import {defineField, defineType} from 'sanity'

export const woodType = defineType({
  name: 'wood',
  title: 'Maderas',
  type: 'document',

  orderings: [
    {
      title: 'Orden de aparición',
      name: 'orderAscending',
      by: [{field: 'order', direction: 'asc'}],
    },
  ],

  fields: [
    defineField({
      name: 'title',
      title: 'Nombre de la madera',
      type: 'string',
      validation: (rule) =>
        rule.required().min(2).max(60),
    }),

    defineField({
      name: 'slug',
      title: 'Identificador',
      type: 'slug',
      description:
        'Presiona Generate para crearlo automáticamente.',
      options: {
        source: 'title',
        maxLength: 96,
      },
      validation: (rule) => rule.required(),
    }),

    defineField({
      name: 'description',
      title: 'Descripción',
      type: 'text',
      rows: 3,
      description:
        'Descripción breve de la apariencia y cualidades de la madera.',
      validation: (rule) => rule.max(300),
    }),

    defineField({
      name: 'image',
      title: 'Muestra de la madera',
      type: 'image',
      description:
        'Fotografía o textura que ayudará al cliente a reconocer la madera.',
      options: {
        hotspot: true,
      },

      fields: [
        defineField({
          name: 'alt',
          title: 'Texto alternativo',
          type: 'string',
          validation: (rule) =>
            rule.required().max(150),
        }),
      ],
    }),

    defineField({
      name: 'order',
      title: 'Orden de aparición',
      type: 'number',
      initialValue: 1,
      validation: (rule) =>
        rule.required().integer().min(1),
    }),

    defineField({
      name: 'active',
      title: 'Madera disponible',
      type: 'boolean',
      initialValue: true,
    }),
  ],

  preview: {
    select: {
      title: 'title',
      media: 'image',
      active: 'active',
    },

    prepare({title, media, active}) {
      return {
        title: title || 'Madera sin nombre',
        media,
        subtitle:
          active === false
            ? 'No disponible'
            : 'Disponible',
      }
    },
  },
})