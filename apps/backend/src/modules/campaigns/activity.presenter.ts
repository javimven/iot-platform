import { Prisma } from '@prisma/client';
import { hectareas } from './campaign.presenter';
import { escribirFecha } from './fechas';

/**
 * Lo que se lee de una actividad para enseñarla: sus destinos con el nombre
 * de la parcela y del cultivo (para la línea de tiempo), y su detalle.
 */
export const INCLUDE_ACTIVIDAD = {
  targets: {
    include: {
      cropUnitParcel: {
        include: {
          parcel: { select: { name: true, areaM2: true } },
          cropUnit: { select: { cropName: true, variety: true } },
        },
      },
    },
  },
  irrigation: true,
  fertilization: true,
  phytosanitary: true,
  phytosanitaryProducts: { orderBy: { position: 'asc' } },
  harvest: true,
  fieldWork: true,
} satisfies Prisma.CampaignActivityInclude;

export type ActividadCompleta = Prisma.CampaignActivityGetPayload<{
  include: typeof INCLUDE_ACTIVIDAD;
}>;

type Destino = ActividadCompleta['targets'][number];

/** Lo que ocupa un destino: lo declarado, o lo que ocupa la parcela en la unidad. */
export function superficieDelDestino(destino: Destino): number {
  const enLaUnidad = destino.cropUnitParcel.areaHa ?? destino.cropUnitParcel.parcel.areaM2 / 10000;
  return hectareas(destino.areaHa ?? enLaUnidad);
}

/** Sin la organización ni la actividad: son redundantes en la respuesta. */
function sinClaves<T extends { organizationId: string; activityId: string }>(fila: T | null) {
  if (!fila) {
    return null;
  }
  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  const { organizationId, activityId, ...resto } = fila;
  return resto;
}

export function presentarActividad(actividad: ActividadCompleta) {
  const destinos = actividad.targets.map((d) => ({
    parcelId: d.parcelId,
    parcelName: d.cropUnitParcel.parcel.name,
    cropUnitId: d.cropUnitId,
    cropName: d.cropUnitParcel.cropUnit.variety
      ? `${d.cropUnitParcel.cropUnit.cropName} ${d.cropUnitParcel.cropUnit.variety}`
      : d.cropUnitParcel.cropUnit.cropName,
    areaHa: d.areaHa,
    effectiveAreaHa: superficieDelDestino(d),
  }));

  const tratamiento = sinClaves(actividad.phytosanitary);

  return {
    id: actividad.id,
    campaignId: actividad.campaignId,
    type: actividad.type,
    startDate: escribirFecha(actividad.startDate),
    endDate: escribirFecha(actividad.endDate),
    startTime: actividad.startTime,
    notes: actividad.notes,
    origin: actividad.origin,
    repeatedFromId: actividad.repeatedFromId,
    areaHa: hectareas(destinos.reduce((suma, d) => suma + d.effectiveAreaHa, 0)),
    targets: destinos,
    irrigation: sinClaves(actividad.irrigation),
    fertilization: sinClaves(actividad.fertilization),
    phytosanitary: tratamiento
      ? {
          ...tratamiento,
          products: actividad.phytosanitaryProducts.map((p) => ({
            id: p.id,
            productName: p.productName,
            registryNumber: p.registryNumber,
            activeSubstances: p.activeSubstances,
            dose: p.dose,
            doseUnit: p.doseUnit,
            totalQuantity: p.totalQuantity,
            totalQuantityUnit: p.totalQuantityUnit,
            source: p.source,
            sourceUpdatedAt: p.sourceUpdatedAt,
          })),
        }
      : null,
    harvest: sinClaves(actividad.harvest),
    fieldWork: sinClaves(actividad.fieldWork),
    createdBy: actividad.createdBy,
    createdAt: actividad.createdAt,
    updatedAt: actividad.updatedAt,
  };
}
