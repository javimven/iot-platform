import { ActividadCompleta, superficieDelDestino } from '../activity.presenter';
import { presentarDetalle } from '../campaign.presenter';
import { calcularResumen } from '../campaign-summary';
import { escribirFecha } from '../fechas';
import { Completitud } from '../notebook-completeness';

/**
 * El cuaderno de una campaña como **datos**, una sola vez, y de ahí salen los
 * tres formatos (BACKLOG.md #60, fase 7). Si el PDF, el JSON y el CSV
 * recogieran cada uno sus datos por su cuenta, tarde o temprano dirían cosas
 * distintas del mismo cuaderno.
 *
 * `schemaVersion` es del **modelo propio**, no del SIEX (ADR-0014): quien lea
 * un JSON exportado sabe con qué forma se escribió. La traducción al formato
 * oficial es cosa de un mapeador aparte, cuando existan los catálogos.
 *
 * **De dónde salen los datos** (ADR-0012): en una campaña cerrada, la
 * cabecera (titular, finca, parcelas, unidades de cultivo) se lee de la
 * instantánea de cierre, no de las tablas. Si mañana cambia el titular o el
 * contorno de una parcela, el cuaderno cerrado de 2026 sigue diciendo lo que
 * decía el día que se cerró.
 */
export const VERSION_DEL_EXPORTADO = 'cuaderno-1';

type Detalle = ReturnType<typeof presentarDetalle>;

export interface FincaExportada {
  name: string;
  holderName: string | null;
  holderNif: string | null;
  reaCode: string | null;
  address: string | null;
  regionCode: string | null;
}

export interface CuadernoExportado {
  schemaVersion: string;
  generatedAt: string;
  /** `snapshot` = de la instantánea de cierre; `live` = de las tablas vivas. */
  source: 'live' | 'snapshot';
  organization: { name: string | null };
  installation: FincaExportada;
  campaign: {
    id: string;
    name: string;
    status: string;
    managementMode: string;
    startDate: string;
    expectedEndDate: string | null;
    endDate: string | null;
    areaHa: number;
    notes: string | null;
    declaredProductionKg: number | null;
    closingNotes: string | null;
    notebookProfile: unknown;
  };
  cropUnits: Array<{
    id: string;
    cropName: string;
    variety: string | null;
    previousCrop: string | null;
    waterRegime: string | null;
    growingEnvironment: string | null;
    productionSystem: string | null;
    areaHa: number;
    expectedYieldKgHa: number | null;
    parcels: Array<{ name: string; areaHa: number }>;
  }>;
  activities: ActividadExportada[];
  summary: ReturnType<typeof calcularResumen>;
  /** Lo que falta, solo en el cuaderno completo. Nunca dice que "cumple". */
  pending: Completitud | null;
}

export interface ActividadExportada {
  id: string;
  type: string;
  startDate: string;
  endDate: string;
  startTime: string | null;
  notes: string | null;
  areaHa: number;
  targets: Array<{ parcelName: string; cropName: string; areaHa: number }>;
  irrigation: Record<string, unknown> | null;
  fertilization: Record<string, unknown> | null;
  phytosanitary: (Record<string, unknown> & { products: Array<Record<string, unknown>> }) | null;
  harvest: Record<string, unknown> | null;
  fieldWork: Record<string, unknown> | null;
}

/** Sin la organización ni la actividad: aquí son ruido. */
function sinClaves<T extends Record<string, unknown>>(
  fila: T | null,
): Record<string, unknown> | null {
  if (!fila) {
    return null;
  }
  const copia = { ...fila };
  delete copia.organizationId;
  delete copia.activityId;
  return copia;
}

function exportarActividad(actividad: ActividadCompleta): ActividadExportada {
  const tratamiento = sinClaves(actividad.phytosanitary as unknown as Record<string, unknown>);
  return {
    id: actividad.id,
    type: actividad.type,
    startDate: escribirFecha(actividad.startDate),
    endDate: escribirFecha(actividad.endDate),
    startTime: actividad.startTime,
    notes: actividad.notes,
    areaHa: actividad.targets.reduce((suma, d) => suma + superficieDelDestino(d), 0),
    targets: actividad.targets.map((d) => ({
      parcelName: d.cropUnitParcel.parcel.name,
      cropName: d.cropUnitParcel.cropUnit.variety
        ? `${d.cropUnitParcel.cropUnit.cropName} ${d.cropUnitParcel.cropUnit.variety}`
        : d.cropUnitParcel.cropUnit.cropName,
      areaHa: superficieDelDestino(d),
    })),
    irrigation: sinClaves(actividad.irrigation as unknown as Record<string, unknown>),
    fertilization: sinClaves(actividad.fertilization as unknown as Record<string, unknown>),
    phytosanitary: tratamiento
      ? {
          ...tratamiento,
          products: actividad.phytosanitaryProducts.map((p) => {
            const producto = { ...p } as unknown as Record<string, unknown>;
            delete producto.organizationId;
            delete producto.activityId;
            return producto;
          }),
        }
      : null,
    harvest: sinClaves(actividad.harvest as unknown as Record<string, unknown>),
    fieldWork: sinClaves(actividad.fieldWork as unknown as Record<string, unknown>),
  };
}

/** La cabecera tal como quedó guardada al cerrar, si la hay. */
export interface CabeceraDeInstantanea {
  organization?: { name?: string | null };
  installation?: Partial<FincaExportada>;
  cropUnits?: CuadernoExportado['cropUnits'];
  areaHa?: number;
}

export function construirExportado(entrada: {
  campana: Detalle;
  actividades: ActividadCompleta[];
  organizacion: { name: string | null };
  finca: FincaExportada;
  instantanea: CabeceraDeInstantanea | null;
  pendiente: Completitud | null;
  ahora?: Date;
}): CuadernoExportado {
  const { campana, actividades, instantanea } = entrada;
  const deLaInstantanea = instantanea !== null;

  const finca: FincaExportada = deLaInstantanea
    ? {
        name: instantanea.installation?.name ?? entrada.finca.name,
        holderName: instantanea.installation?.holderName ?? null,
        holderNif: instantanea.installation?.holderNif ?? null,
        reaCode: instantanea.installation?.reaCode ?? null,
        address: instantanea.installation?.address ?? null,
        regionCode: instantanea.installation?.regionCode ?? null,
      }
    : entrada.finca;

  const unidades =
    deLaInstantanea && instantanea.cropUnits
      ? instantanea.cropUnits
      : campana.cropUnits.map((u) => ({
          id: u.id,
          cropName: u.cropName,
          variety: u.variety,
          previousCrop: u.previousCrop,
          waterRegime: u.waterRegime,
          growingEnvironment: u.growingEnvironment,
          productionSystem: u.productionSystem,
          areaHa: u.effectiveAreaHa,
          expectedYieldKgHa: u.expectedYieldKgHa,
          parcels: u.parcels.map((p) => ({ name: p.name, areaHa: p.effectiveAreaHa })),
        }));

  return {
    schemaVersion: VERSION_DEL_EXPORTADO,
    generatedAt: (entrada.ahora ?? new Date()).toISOString(),
    source: deLaInstantanea ? 'snapshot' : 'live',
    organization: deLaInstantanea
      ? { name: instantanea.organization?.name ?? entrada.organizacion.name }
      : entrada.organizacion,
    installation: finca,
    campaign: {
      id: campana.id,
      name: campana.name,
      status: campana.status,
      managementMode: campana.managementMode,
      startDate: campana.startDate,
      expectedEndDate: campana.expectedEndDate,
      endDate: campana.endDate,
      areaHa: deLaInstantanea ? (instantanea.areaHa ?? campana.areaHa) : campana.areaHa,
      notes: campana.notes,
      declaredProductionKg: campana.declaredProductionKg,
      closingNotes: campana.closingNotes,
      notebookProfile: campana.notebookProfile,
    },
    cropUnits: unidades,
    activities: [...actividades]
      .sort(
        (a, b) =>
          a.startDate.getTime() - b.startDate.getTime() ||
          a.createdAt.getTime() - b.createdAt.getTime(),
      )
      .map(exportarActividad),
    summary: calcularResumen(campana, actividades),
    pending: entrada.pendiente,
  };
}
