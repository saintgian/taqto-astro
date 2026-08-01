// Numero de WhatsApp de TAQTO usado en header, footer, boton flotante y checkout.
export const WHATSAPP_NUMBER = "51977600400";

// Fuente unica de los datos de Yape confirmados por el propietario.
// YAPE_NUMBER son solo digitos; YAPE_NUMBER_DISPLAY se deriva de ahi
// (no se repite el numero a mano) solo para mostrarlo con espacios.
export const YAPE_NAME = "Gianmarco Santillán";
export const YAPE_NUMBER = "977600400";
export const YAPE_NUMBER_DISPLAY = YAPE_NUMBER.replace(
	/(\d{3})(\d{3})(\d{3})/,
	"$1 $2 $3",
);

// Tarifa plana de envio: S/10 tanto para delivery en Lima como para entrega
// en agencia en provincia.
export const SHIPPING_COST = 10;

// La categoria "Empresas" vive en Sanity para aparecer en la navegacion,
// pero sus dos paginas (regalos corporativos y venta al por mayor) son
// paginas estaticas de contenido, no subcategorias de producto. Este
// fallback se usa cuando Sanity no trae subcategorias para "empresas".
export const EMPRESAS_CATEGORY_SLUG = "empresas";

export const EMPRESAS_SUBCATEGORIES = [
	{
		_id: "empresas-regalos-corporativos",
		title: "Regalos corporativos",
		slug: "regalos-corporativos",
	},
	{
		_id: "empresas-ventas-al-por-mayor",
		title: "Ventas al por mayor",
		slug: "ventas-al-por-mayor",
	},
];
