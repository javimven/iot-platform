import { ActividadExportada, CuadernoExportado } from './export-model';

/**
 * El cuaderno en JSON y en CSV (fase 7 del #60).
 *
 * - **JSON**: el modelo propio entero, con su `schemaVersion`. Para que otro
 *   programa lo lea y para poder reconstruir lo exportado tal cual.
 * - **CSV**: una fila por actividad, con las columnas que de verdad se miran
 *   en una hoja de cálculo. No es el modelo entero: es lo que un técnico
 *   ordena y filtra. Lo que no aplica a un tipo se queda vacío, **nunca a
 *   cero**: un cero es una medida, y un hueco es un hueco.
 */

export function aJson(cuaderno: CuadernoExportado): Buffer {
  return Buffer.from(JSON.stringify(cuaderno, null, 2), 'utf8');
}

const COLUMNAS = [
  'fecha_inicio',
  'fecha_fin',
  'hora',
  'tipo',
  'cultivo',
  'parcelas',
  'superficie_ha',
  'producto',
  'numero_registro',
  'dosis',
  'unidad_dosis',
  'cantidad',
  'unidad_cantidad',
  'detalle',
  'notas',
] as const;

const TIPOS_EN_ESPANOL: Record<string, string> = {
  irrigation: 'Riego',
  fertilization: 'Fertilización',
  phytosanitary: 'Tratamiento fitosanitario',
  field_work: 'Labor agrícola',
  harvest: 'Recolección',
  observation: 'Observación',
  sowing: 'Siembra o plantación',
  other: 'Otra actividad',
};

function texto(valor: unknown): string {
  return valor === null || valor === undefined ? '' : String(valor);
}

function numero(valor: unknown): string {
  // Coma decimal: el CSV se abre en Excel en español, y "1.5" allí es mil
  // quinientos.
  return typeof valor === 'number' ? String(valor).replace('.', ',') : '';
}

/** Una actividad puede dar varias filas: un tratamiento, una por producto. */
function filasDe(actividad: ActividadExportada): Array<Record<string, string>> {
  const comun = {
    fecha_inicio: actividad.startDate,
    fecha_fin: actividad.endDate,
    hora: texto(actividad.startTime),
    tipo: TIPOS_EN_ESPANOL[actividad.type] ?? actividad.type,
    cultivo: [...new Set(actividad.targets.map((d) => d.cropName))].join(' / '),
    parcelas: actividad.targets.map((d) => d.parcelName).join(' / '),
    superficie_ha: numero(Math.round(actividad.areaHa * 10000) / 10000),
    notas: texto(actividad.notes),
  };

  switch (actividad.type) {
    case 'irrigation': {
      const d = actividad.irrigation ?? {};
      return [
        {
          ...comun,
          cantidad: numero(d.amount),
          unidad_cantidad: texto(d.amountUnit),
          detalle: [texto(d.system), d.volumeM3 == null ? '' : `${numero(d.volumeM3)} m3 totales`]
            .filter(Boolean)
            .join(' · '),
        },
      ];
    }
    case 'fertilization': {
      const d = actividad.fertilization ?? {};
      const riqueza = [
        d.nKgHa == null ? null : `N ${numero(d.nKgHa)} kg/ha`,
        d.p2o5KgHa == null ? null : `P2O5 ${numero(d.p2o5KgHa)} kg/ha`,
        d.k2oKgHa == null ? null : `K2O ${numero(d.k2oKgHa)} kg/ha`,
      ].filter(Boolean);
      return [
        {
          ...comun,
          producto: texto(d.productName),
          dosis: numero(d.dose),
          unidad_dosis: texto(d.doseUnit),
          detalle: [texto(d.materialType), texto(d.applicationMethod), ...riqueza]
            .filter(Boolean)
            .join(' · '),
        },
      ];
    }
    case 'phytosanitary': {
      const d = actividad.phytosanitary;
      const contexto = [
        texto(d?.problem),
        d?.phenologicalStageLabel ? `Estado: ${texto(d.phenologicalStageLabel)}` : '',
      ]
        .filter(Boolean)
        .join(' · ');
      const productos = d?.products ?? [];
      if (productos.length === 0) {
        return [{ ...comun, detalle: contexto }];
      }
      return productos.map((producto) => ({
        ...comun,
        producto: texto(producto.productName),
        numero_registro: texto(producto.registryNumber),
        dosis: numero(producto.dose),
        unidad_dosis: texto(producto.doseUnit),
        cantidad: numero(producto.totalQuantity),
        unidad_cantidad: texto(producto.totalQuantityUnit),
        detalle: contexto,
      }));
    }
    case 'harvest': {
      const d = actividad.harvest ?? {};
      return [
        {
          ...comun,
          producto: texto(d.product),
          cantidad: numero(d.quantity),
          unidad_cantidad: texto(d.quantityUnit),
          detalle: [texto(d.destination), texto(d.lotCode)].filter(Boolean).join(' · '),
        },
      ];
    }
    case 'field_work': {
      const d = actividad.fieldWork ?? {};
      return [
        { ...comun, detalle: [texto(d.workType), texto(d.machinery)].filter(Boolean).join(' · ') },
      ];
    }
    default:
      return [comun];
  }
}

/** Comillas al estilo RFC 4180, y solo cuando hacen falta. */
function celda(valor: string): string {
  return /[";\n\r]/.test(valor) ? `"${valor.replace(/"/g, '""')}"` : valor;
}

export function aCsv(cuaderno: CuadernoExportado): Buffer {
  const filas = cuaderno.activities.flatMap(filasDe);
  const lineas = [
    COLUMNAS.join(';'),
    ...filas.map((fila) => COLUMNAS.map((columna) => celda(fila[columna] ?? '')).join(';')),
  ];
  // Punto y coma y BOM: es lo que abre Excel en español en columnas y con los
  // acentos bien. Con coma y sin BOM, el fichero sale ilegible de un doble
  // clic, que es como se abre el 99 % de las veces.
  return Buffer.concat([Buffer.from('﻿', 'utf8'), Buffer.from(lineas.join('\r\n'), 'utf8')]);
}

/** Nombre del fichero que descarga el usuario. */
export function nombreDelFichero(cuaderno: CuadernoExportado, extension: string): string {
  const limpio = cuaderno.campaign.name
    .replace(/[\\/:*?"<>|]/g, '')
    .replace(/\s+/g, ' ')
    .trim();
  return `Cuaderno - ${limpio}.${extension}`;
}
