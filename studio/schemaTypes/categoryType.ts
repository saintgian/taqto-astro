import {defineField, defineType} from 'sanity'

export const categoryType = defineType({
  name: 'category',
  title: 'Categorías',
  type: 'document',

  fields: [
    defineField({
      name: 'title',
      title: 'Nombre de la categoría',
      type: 'string',
      description: 'Ejemplo: Parrilla, Cocina y Mesa u Oficina.',
      validation: (rule) =>
        rule.required().min(2).max(60),
    }),

    defineField({
      name: 'slug',
      title: 'URL de la categoría',
      type: 'slug',
      description:
        'Presiona Generate para crear la dirección automáticamente.',
      options: {
        source: 'title',
        maxLength: 96,
      },
      validation: (rule) => rule.required(),
    }),

    defineField({
      name: 'eyebrow',
      title: 'Texto superior',
      type: 'string',
      description:
        'Frase corta que acompaña al título. Ejemplo: Para quienes dominan el fuego.',
      validation: (rule) => rule.max(80),
    }),

    defineField({
      name: 'description',
      title: 'Descripción',
      type: 'text',
      rows: 3,
      description:
        'Descripción breve de la categoría para la tienda.',
      validation: (rule) => rule.max(300),
    }),

    defineField({
      name: 'order',
      title: 'Orden de aparición',
      type: 'number',
      description:
        'Usa 1, 2, 3, 4… para ordenar las categorías.',
      initialValue: 1,
      validation: (rule) =>
        rule.required().integer().min(1),
    }),

    defineField({
      name: 'active',
      title: 'Categoría visible',
      type: 'boolean',
      description:
        'Desactívala para ocultarla sin eliminarla.',
      initialValue: true,
    }),
  ],

  preview: {
    select: {
      title: 'title',
      eyebrow: 'eyebrow',
      active: 'active',
    },

    prepare({title, eyebrow, active}) {
      return {
        title: title || 'Categoría sin nombre',
        subtitle: `${active === false ? 'Oculta' : 'Visible'} · ${
          eyebrow || 'Sin texto superior'
        }`,
      }
    },
  },
})