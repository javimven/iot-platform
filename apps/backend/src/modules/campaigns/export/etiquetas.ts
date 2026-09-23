/**
 * Cómo se dice en español lo que la base guarda en inglés, para el cuaderno
 * exportado (fase 7 del #60).
 *
 * Sí, la app tiene sus propias etiquetas (`campaign_labels.dart`): son dos
 * runtimes distintos y un fichero compartido exigiría generar código. Lo que
 * no puede pasar es que digan cosas distintas, así que **los dos salen de los
 * mismos CHECK de las migraciones 0010-0011**; al añadir un valor allí, se
 * añade en los dos sitios.
 *
 * Nada de subíndices (`P₂O₅`) aquí: las fuentes estándar de un PDF no los
 * traen y saldrían como un cuadrado. Se escribe `P2O5`.
 */

export const TIPOS_DE_ACTIVIDAD: Record<string, string> = {
  irrigation: 'Riego',
  fertilization: 'Fertilización',
  phytosanitary: 'Tratamiento fitosanitario',
  field_work: 'Labor agrícola',
  harvest: 'Recolección',
  observation: 'Observación',
  sowing: 'Siembra o plantación',
  other: 'Otra actividad',
};

export const REGIMENES_HIDRICOS: Record<string, string> = {
  rainfed: 'Secano',
  irrigated: 'Regadío',
};

export const ENTORNOS: Record<string, string> = {
  open_field: 'Aire libre',
  greenhouse: 'Invernadero',
  other: 'Otro',
};

export const SISTEMAS_PRODUCTIVOS: Record<string, string> = {
  conventional: 'Convencional',
  integrated: 'Producción integrada',
  organic: 'Ecológica',
};

export const SISTEMAS_DE_RIEGO: Record<string, string> = {
  drip: 'Goteo',
  micro_sprinkler: 'Microaspersión',
  sprinkler_fixed: 'Aspersión fija',
  sprinkler_mobile: 'Aspersión móvil',
  fogging: 'Nebulización',
  surface: 'Superficie o gravedad',
  hydroponic_open: 'Hidroponía a solución perdida',
  hydroponic_recirculating: 'Hidroponía con recirculación',
};

export const MATERIALES_FERTILIZANTES: Record<string, string> = {
  fertilizer_product: 'Producto fertilizante',
  solid_manure: 'Estiércol sólido',
  slurry: 'Purín',
  sewage_sludge: 'Lodo de depuradora',
  compost_digestate: 'Compost o digestato',
  other_waste: 'Otro residuo valorizable',
  other: 'Otro material',
};

export const METODOS_DE_APLICACION: Record<string, string> = {
  broadcast: 'A voleo',
  localized: 'Localizada',
  fertigation: 'Fertirrigación',
  foliar: 'Foliar',
  injection: 'Inyección',
  other: 'Otra',
};

export const CATEGORIAS_DE_PROBLEMA: Record<string, string> = {
  weeds: 'Malas hierbas',
  diseases: 'Enfermedades',
  arthropods: 'Insectos y ácaros',
  growth_regulators: 'Reguladores y otros',
  other: 'Otro',
};

export const TIPOS_DE_LABOR: Record<string, string> = {
  soil_preparation: 'Preparación del terreno',
  tillage: 'Laboreo',
  pruning: 'Poda',
  clearing: 'Desbroce',
  mowing: 'Siega',
  shredding: 'Triturado',
  thinning: 'Aclareo',
  grafting: 'Injerto',
  cover_management: 'Manejo de la cubierta',
  mechanical_control: 'Control mecánico',
  maintenance: 'Mantenimiento',
  other: 'Otra labor',
};

export const UNIDADES: Record<string, string> = {
  m3: 'm³',
  m3_ha: 'm³/ha',
  l: 'l',
  l_ha: 'l/ha',
  l_hl: 'l/hl',
  kg: 'kg',
  kg_ha: 'kg/ha',
  kg_hl: 'kg/hl',
  t: 't',
  t_ha: 't/ha',
  units: 'unidades',
};

export function etiqueta(mapa: Record<string, string>, valor: unknown): string {
  if (typeof valor !== 'string' || valor.length === 0) {
    return '';
  }
  return mapa[valor] ?? valor;
}

/** Cifra con coma decimal y sin decimales inútiles: "15,3" y "1.200". */
export function cifra(valor: unknown, decimales = 2): string {
  if (typeof valor !== 'number' || Number.isNaN(valor)) {
    return '';
  }
  const redondeado = Math.round(valor * 10 ** decimales) / 10 ** decimales;
  return redondeado.toLocaleString('es-ES', { maximumFractionDigits: decimales });
}

/** `2026-02-03` como `03/02/2026`, que es como se lee un cuaderno en papel. */
export function fecha(iso: string | null | undefined): string {
  if (!iso) {
    return '';
  }
  const [anio, mes, dia] = iso.slice(0, 10).split('-');
  return `${dia}/${mes}/${anio}`;
}
