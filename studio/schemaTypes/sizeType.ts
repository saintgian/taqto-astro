import {defineField, defineType} from 'sanity'

export const sizeType = defineType({
  name: 'productSize',
  title: 'Tamaños',
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
      title: 'Nombre del tamaño',
      type: 'string',
      description:
        'Ejemplo: Personal, Grande o XL.',
      validation: (rule) =>
        rule.required().min(2).max(60),
    }),

    defineField({
      name: 'slug',
      title: 'Identificador',
      type: 'slug',
      options: {
        source: 'title',
        maxLength: 96,
      },
      validation: (rule) => rule.required(),
    }),

    defineField({
      name: 'dimensionsLabel',
      title: 'Medidas visibles',
      type: 'string',
      description:
        'Ejemplo: 50 × 28 × 2.5 cm. Usa la medida real.',
      validation: (rule) => rule.max(80),
    }),

    defineField({
      name: 'description',
      title: 'Descripción',
      type: 'text',
      rows: 2,
      validation: (rule) => rule.max(200),
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
      title: 'Tamaño disponible',
      type: 'boolean',
      initialValue: true,
    }),
  ],

  preview: {
    select: {
      title: 'title',
      dimensions: 'dimensionsLabel',
      active: 'active',
    },

    prepare({title, dimensions, active}) {
      return {
        title: title || 'Tamaño sin nombre',
        subtitle:
          `${active === false ? 'No disponible' : 'Disponible'}` +
          `${dimensions ? ` · ${dimensions}` : ''}`,
      }
    },
  },
})