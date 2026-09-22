import { Prisma } from '@prisma/client';
import { escribirFecha, escribirFechaONulo } from './fechas';

/**
 * Lo que se lee de una campaña para enseñarla: su finca, sus unidades de
 * cultivo vivas y, de cada parcela, lo justo para calcular superficies (el
 * contorno no hace falta aquí; lo sirve la API de parcelas).
 */
export const INCLUDE_CAMPANA = {
  installation: { select: { id: true, name: true } },
  cropUnits: {
    where: { deletedAt: null },
    orderBy: { createdAt: 'asc' },
    include: {
      parcels: {
        orderBy: { createdAt: 'asc' },
        include: { parcel: { select: { id: true, name: true, areaM2: true, deletedAt: true } } },
      },
    },
  },
} satisfies Prisma.CampaignInclude;

export type CampanaCompleta = Prisma.CampaignGetPayload<{ include: typeof INCLUDE_CAMPANA }>;
type Unidad = CampanaCompleta['cropUnits'][number];

export interface UltimaActividad {
  campaignId: string;
  type: string;
  startDate: Date;
}

/** Hectáreas con cuatro decimales: un metro cuadrado. Más es falsa precisión. */
export function hectareas(valor: number): number {
  return Math.round(valor * 10000) / 10000;
}

function presentarUnidad(unidad: Unidad) {
  const parcelas = unidad.parcels.map((relacion) => {
    const superficieParcela = hectareas(relacion.parcel.areaM2 / 10000);
    return {
      parcelId: relacion.parcelId,
      name: relacion.parcel.name,
      parcelAreaHa: superficieParcela,
      /** Lo declarado; nulo = la parcela entera. */
      areaHa: relacion.areaHa,
      effectiveAreaHa: hectareas(relacion.areaHa ?? superficieParcela),
      /** La parcela se borró después: sigue en la campaña por su historia. */
      deleted: relacion.parcel.deletedAt !== null,
    };
  });
  const sumaParcelas = hectareas(parcelas.reduce((suma, p) => suma + p.effectiveAreaHa, 0));

  return {
    id: unidad.id,
    cropId: unidad.cropId,
    cropName: unidad.cropName,
    variety: unidad.variety,
    previousCrop: unidad.previousCrop,
    waterRegime: unidad.waterRegime,
    growingEnvironment: unidad.growingEnvironment,
    productionSystem: unidad.productionSystem,
    /** Superficie cultivada declarada, si la hay. */
    areaHa: unidad.areaHa,
    /** La suma de sus parcelas. */
    parcelsAreaHa: sumaParcelas,
    /** La que vale para los cálculos: la declarada o, si no, la de sus parcelas. */
    effectiveAreaHa: hectareas(unidad.areaHa ?? sumaParcelas),
    expectedYieldKgHa: unidad.expectedYieldKgHa,
    notes: unidad.notes,
    parcels: parcelas,
  };
}

function resumen(campana: CampanaCompleta) {
  const unidades = campana.cropUnits.map(presentarUnidad);
  const parcelas = new Set(unidades.flatMap((u) => u.parcels.map((p) => p.parcelId)));
  return {
    unidades,
    parcelCount: parcelas.size,
    areaHa: hectareas(unidades.reduce((suma, u) => suma + u.effectiveAreaHa, 0)),
    // "Aguacate Hass", "Tomate": para la tarjeta del listado.
    crops: unidades.map((u) => (u.variety ? `${u.cropName} ${u.variety}` : u.cropName)),
  };
}

function ultima(actividad: UltimaActividad | undefined) {
  return actividad ? { type: actividad.type, date: escribirFecha(actividad.startDate) } : null;
}

/** Tarjeta del listado. */
export function presentarEnLista(campana: CampanaCompleta, actividad?: UltimaActividad) {
  const { parcelCount, areaHa, crops } = resumen(campana);
  return {
    id: campana.id,
    name: campana.name,
    status: campana.status,
    managementMode: campana.managementMode,
    installation: campana.installation,
    startDate: escribirFecha(campana.startDate),
    expectedEndDate: escribirFechaONulo(campana.expectedEndDate),
    endDate: escribirFechaONulo(campana.endDate),
    crops,
    parcelCount,
    areaHa,
    lastActivity: ultima(actividad),
  };
}

/** Ficha completa. */
export function presentarDetalle(campana: CampanaCompleta, actividad?: UltimaActividad) {
  const { unidades, parcelCount, areaHa, crops } = resumen(campana);
  return {
    id: campana.id,
    name: campana.name,
    status: campana.status,
    managementMode: campana.managementMode,
    installation: campana.installation,
    startDate: escribirFecha(campana.startDate),
    expectedEndDate: escribirFechaONulo(campana.expectedEndDate),
    endDate: escribirFechaONulo(campana.endDate),
    notes: campana.notes,
    notebookProfile: campana.notebookProfile,
    declaredProductionKg: campana.declaredProductionKg,
    closingNotes: campana.closingNotes,
    closedAt: campana.closedAt,
    crops,
    parcelCount,
    areaHa,
    lastActivity: ultima(actividad),
    cropUnits: unidades,
    createdAt: campana.createdAt,
    updatedAt: campana.updatedAt,
  };
}

/**
 * Nombre automático: "Aguacate Hass · 2026", o "Olivo · 2026/27" si la campaña
 * cruza de año. Es lo que la gente escribe a mano, y así no hay que pedirlo.
 */
export function nombreAutomatico(
  cultivo: string,
  variedad: string | undefined,
  inicio: Date,
  finPrevista: Date | undefined,
): string {
  const anyoInicio = inicio.getUTCFullYear();
  const anyoFin = finPrevista?.getUTCFullYear();
  const anyos =
    anyoFin !== undefined && anyoFin > anyoInicio
      ? `${anyoInicio}/${String(anyoFin).slice(-2)}`
      : String(anyoInicio);
  const quien = variedad?.trim() ? `${cultivo} ${variedad.trim()}` : cultivo;
  return `${quien} · ${anyos}`;
}
