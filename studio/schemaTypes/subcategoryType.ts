import {defineField, defineType} from 'sanity'

export const subcategoryType = defineType({
  name: 'subcategory',
  title: 'Subcategorías',
  type: 'document',

  fields: [
    defineField({
      name: 'title',
      title: 'Nombre de la subcategoría',
      type: 'string',
      description:
        'Ejemplo: Tablas parrilleras, Mandiles o Posavasos.',
      validation: (rule) =>
        rule.required().min(2).max(80),
    }),

    defineField({
      name: 'slug',
      title: 'URL de la subcategoría',
      type: 'slug',
      description:
        'Presiona Generate para crear la URL automáticamente.',
      options: {
        source: 'title',
        maxLength: 96,
      },
      validation: (rule) => rule.required(),
    }),

    defineField({
      name: 'category',
      title: 'Categoría principal',
      type: 'reference',
      description:
        'Selecciona la categoría a la que pertenece.',
      to: [
        {
          type: 'category',
        },
      ],
      validation: (rule) => rule.required(),
    }),

    defineField({
      name: 'description',
      title: 'Descripción',
      type: 'text',
      rows: 3,
      description:
        'Descripción breve para la página de subcategoría.',
      validation: (rule) => rule.max(300),
    }),

    defineField({
      name: 'order',
      title: 'Orden de aparición',
      type: 'number',
      description:
        'Usa 1, 2, 3… para ordenar dentro de su categoría.',
      initialValue: 1,
      validation: (rule) =>
        rule.required().integer().min(1),
    }),

    defineField({
      name: 'active',
      title: 'Subcategoría visible',
      type: 'boolean',
      description:
        'Desactívala para ocultarla sin eliminarla.',
      initialValue: true,
    }),
  ],

  preview: {
    select: {
      title: 'title',
      category: 'category.title',
      active: 'active',
    },

    prepare({title, category, active}) {
      return {
        title: title || 'Subcategoría sin nombre',
        subtitle: `${
          active === false ? 'Oculta' : 'Visible'
        } · ${category || 'Sin categoría asignada'}`,
      }
    },
  },
})