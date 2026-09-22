import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { AccessTokenClaims } from '../../common/guards/jwt-auth.guard';
import { resolveOrgContext } from '../../common/permissions/org-context';
import { PrismaService } from '../../common/prisma/prisma.service';
import { ActividadCompleta, INCLUDE_ACTIVIDAD } from './activity.presenter';
import { CampaignAccess } from './campaign-access';
import { INCLUDE_CAMPANA, presentarDetalle } from './campaign.presenter';
import { escribirFecha } from './fechas';

type Detalle = ReturnType<typeof presentarDetalle>;

/**
 * Qué información falta en un cuaderno completo (ADR-0013, fase 5 del #60).
 *
 * Tres reglas de fondo, y las tres se notan en el código:
 *
 * 1. **Nunca bloquea.** Lo que falta se enseña; guardar y cerrar siguen siendo
 *    posibles. Un cuaderno a medias es lo normal a mitad de campaña.
 * 2. **Nunca dice "cumple".** La obligación depende de la ubicación, el
 *    tamaño, las ayudas y circunstancias que la plataforma no conoce. Aquí se
 *    dice qué información está pendiente y por qué se pide, con su fuente.
 * 3. **Cada regla trae su fuente.** Si no hay fuente comprobada, la regla es
 *    de la plataforma (hace falta para calcular algo) y se dice así, en vez de
 *    presentarla como una exigencia legal.
 *
 * El conjunto va versionado: cuando cambien las reglas, sube la versión y se
 * sabe con qué reglas se revisó cada campaña.
 */
export const CONJUNTO_DE_REGLAS = {
  id: 'ES-2026.1',
  country: 'ES',
  /** Sin extensiones autonómicas todavía (ADR-0014). */
  region: null as string | null,
  effectiveFrom: '2026-01-01',
  effectiveTo: null as string | null,
};

export type FuenteDeRegla =
  | 'ue_2023_564'
  | 'cue_unidad_de_cultivo'
  | 'cue_tratamientos'
  | 'cue_fertilizacion'
  | 'cue_riego'
  | 'cue_identificacion'
  | 'rd_1051_2022'
  | 'plataforma';

/** El texto que se enseña al lado de cada aviso, para poder contrastarlo. */
export const FUENTES: Record<FuenteDeRegla, string> = {
  ue_2023_564: 'Reglamento de Ejecución (UE) 2023/564, anexo (registro de tratamientos)',
  cue_unidad_de_cultivo: 'Cuaderno Único de Explotación (SIEX, Anexo V): unidad de cultivo',
  cue_tratamientos: 'Cuaderno Único de Explotación (SIEX, Anexo V): tratamientos fitosanitarios',
  cue_fertilizacion: 'Cuaderno Único de Explotación (SIEX, Anexo V): fertilización',
  cue_riego: 'Cuaderno Único de Explotación (SIEX, Anexo V): riego',
  cue_identificacion:
    'Cuaderno Único de Explotación (SIEX, Anexo V): identificación de la explotación',
  rd_1051_2022: 'Real Decreto 1051/2022, de nutrición sostenible de suelos agrarios',
  plataforma: 'Necesario para los cálculos de la plataforma, no por normativa',
};

export interface AvisoDelCuaderno {
  /** Estable, para poder contarlos y probarlos sin depender del texto. */
  code: string;
  /** `missing`: información pendiente. `warning`: algo que conviene revisar. */
  kind: 'missing' | 'warning';
  label: string;
  why: string;
  source: FuenteDeRegla;
  sourceLabel: string;
}

export interface FincaParaRevisar {
  holderName: string | null;
  holderNif: string | null;
  regionCode: string | null;
}

export interface EntradaDeCompletitud {
  campana: Detalle;
  finca: FincaParaRevisar;
  actividades: ActividadCompleta[];
}

function aviso(
  code: string,
  kind: AvisoDelCuaderno['kind'],
  label: string,
  why: string,
  source: FuenteDeRegla,
): AvisoDelCuaderno {
  return { code, kind, label, why, source, sourceLabel: FUENTES[source] };
}

function vacio(valor: string | null | undefined): boolean {
  return valor == null || valor.trim().length === 0;
}

/** Las respuestas del asistente, sin la versión del formato. */
function leerPerfil(perfil: unknown): Record<string, boolean> {
  if (typeof perfil !== 'object' || perfil === null) {
    return {};
  }
  return Object.fromEntries(
    Object.entries(perfil as Record<string, unknown>).filter(
      ([, valor]) => typeof valor === 'boolean',
    ),
  ) as Record<string, boolean>;
}

/** La dosis del Reglamento (UE) 2023/564 va en kg o l **por hectárea**. */
const DOSIS_POR_HECTAREA = ['kg_ha', 'l_ha'];

function avisosDeTratamiento(actividad: ActividadCompleta): AvisoDelCuaderno[] {
  const avisos: AvisoDelCuaderno[] = [];
  const detalle = actividad.phytosanitary;
  const productos = actividad.phytosanitaryProducts;

  if (productos.length === 0) {
    avisos.push(
      aviso(
        'phyto.product',
        'missing',
        'El producto utilizado',
        'El registro de cada tratamiento identifica el producto aplicado.',
        'ue_2023_564',
      ),
    );
  }
  for (const producto of productos) {
    if (vacio(producto.registryNumber)) {
      avisos.push(
        aviso(
          `phyto.registry_number:${producto.id}`,
          'missing',
          `El número de registro de ${producto.productName}`,
          'Junto al nombre del producto se anota su número de autorización o registro.',
          'ue_2023_564',
        ),
      );
    }
    const porHectarea = producto.doseUnit != null && DOSIS_POR_HECTAREA.includes(producto.doseUnit);
    if (!porHectarea && producto.totalQuantity == null) {
      avisos.push(
        aviso(
          `phyto.dose:${producto.id}`,
          'missing',
          `La dosis de ${producto.productName} en kg o l por hectárea`,
          'La cantidad aplicada se anota en kilogramos o litros por hectárea; si se anotó por hectolitro de caldo, sirve también la cantidad total.',
          'ue_2023_564',
        ),
      );
    }
  }
  if (vacio(actividad.startTime)) {
    avisos.push(
      aviso(
        'phyto.start_time',
        'missing',
        'La hora de inicio del tratamiento',
        'El registro incluye la fecha y la hora de inicio de la aplicación.',
        'ue_2023_564',
      ),
    );
  }
  if (vacio(detalle?.bbchCode) && vacio(detalle?.phenologicalStageLabel)) {
    avisos.push(
      aviso(
        'phyto.stage',
        'missing',
        'El estado del cultivo en el momento del tratamiento',
        'El registro incluye la fase de desarrollo del cultivo tratado.',
        'ue_2023_564',
      ),
    );
  }
  if (detalle?.applicatorId == null && detalle?.applicatorSnapshot == null) {
    avisos.push(
      aviso(
        'phyto.applicator',
        'missing',
        'Quién realizó el tratamiento',
        'El cuaderno identifica al aplicador; se elige de tus personas guardadas.',
        'cue_tratamientos',
      ),
    );
  }
  if (detalle?.equipmentId == null && detalle?.equipmentSnapshot == null) {
    avisos.push(
      aviso(
        'phyto.equipment',
        'missing',
        'El equipo de aplicación',
        'El cuaderno recoge con qué equipo se aplicó; se elige de tus equipos guardados.',
        'cue_tratamientos',
      ),
    );
  }
  if (vacio(detalle?.problem) && vacio(detalle?.problemCategory)) {
    avisos.push(
      aviso(
        'phyto.problem',
        'missing',
        'La plaga o el problema tratado',
        'El cuaderno recoge contra qué se trató.',
        'cue_tratamientos',
      ),
    );
  }
  return avisos;
}

/** Un mes de margen: el RD 1051/2022 pide anotar el abonado dentro del mes. */
function apuntadoConRetraso(actividad: ActividadCompleta): boolean {
  const limite = new Date(actividad.endDate);
  limite.setUTCMonth(limite.getUTCMonth() + 1);
  return actividad.createdAt > limite;
}

function avisosDeAbonado(actividad: ActividadCompleta): AvisoDelCuaderno[] {
  const avisos: AvisoDelCuaderno[] = [];
  const detalle = actividad.fertilization;

  if (vacio(detalle?.materialType)) {
    avisos.push(
      aviso(
        'fert.material',
        'missing',
        'El tipo de material fertilizante',
        'El cuaderno distingue producto fertilizante, estiércol, purín, lodo o compost.',
        'cue_fertilizacion',
      ),
    );
  }
  if (detalle?.dose == null) {
    avisos.push(
      aviso(
        'fert.dose',
        'missing',
        'La dosis aplicada',
        'El cuaderno recoge cuánto se aplicó y en qué unidad.',
        'cue_fertilizacion',
      ),
    );
  }
  if (vacio(detalle?.applicationMethod)) {
    avisos.push(
      aviso(
        'fert.method',
        'missing',
        'El método de aplicación',
        'A voleo, localizada, fertirrigación, foliar o inyección.',
        'cue_fertilizacion',
      ),
    );
  }
  if (detalle?.nKgHa == null && detalle?.p2o5KgHa == null && detalle?.k2oKgHa == null) {
    avisos.push(
      aviso(
        'fert.composition',
        'warning',
        'La riqueza del abono (N, P₂O₅, K₂O)',
        'Sin ella no se pueden calcular los kilos de nutriente por hectárea del resumen.',
        'plataforma',
      ),
    );
  }
  if (apuntadoConRetraso(actividad)) {
    avisos.push(
      aviso(
        'fert.delay',
        'warning',
        'Este abonado se apuntó más de un mes después',
        'La norma de nutrición sostenible prevé anotar cada aplicación dentro del mes siguiente.',
        'rd_1051_2022',
      ),
    );
  }
  return avisos;
}

function avisosDeRiego(actividad: ActividadCompleta): AvisoDelCuaderno[] {
  const avisos: AvisoDelCuaderno[] = [];
  const detalle = actividad.irrigation;

  if (detalle?.amount == null) {
    avisos.push(
      aviso(
        'irrigation.amount',
        'missing',
        'El agua aplicada',
        'El cuaderno recoge el volumen de cada riego.',
        'cue_riego',
      ),
    );
  }
  if (vacio(detalle?.system)) {
    avisos.push(
      aviso(
        'irrigation.system',
        'missing',
        'El sistema de riego',
        'Goteo, aspersión, superficie… El cuaderno lo recoge por unidad de cultivo.',
        'cue_riego',
      ),
    );
  }
  return avisos;
}

function avisosDeCosecha(actividad: ActividadCompleta): AvisoDelCuaderno[] {
  if (actividad.harvest?.quantity != null) {
    return [];
  }
  return [
    aviso(
      'harvest.quantity',
      'warning',
      'La cantidad recolectada',
      'Sin ella no se puede calcular el rendimiento de la campaña.',
      'plataforma',
    ),
  ];
}

function avisosDeLaActividad(actividad: ActividadCompleta): AvisoDelCuaderno[] {
  switch (actividad.type) {
    case 'phytosanitary':
      return avisosDeTratamiento(actividad);
    case 'fertilization':
      return avisosDeAbonado(actividad);
    case 'irrigation':
      return avisosDeRiego(actividad);
    case 'harvest':
      return avisosDeCosecha(actividad);
    default:
      return [];
  }
}

function avisosDeLaCampana(entrada: EntradaDeCompletitud): AvisoDelCuaderno[] {
  const { campana, finca, actividades } = entrada;
  const perfil = leerPerfil(campana.notebookProfile);
  const avisos: AvisoDelCuaderno[] = [];

  if (Object.keys(perfil).length === 0) {
    avisos.push(
      aviso(
        'campaign.profile',
        'missing',
        'Las preguntas del cuaderno completo',
        'De las respuestas depende qué apartados se piden; se responden una vez.',
        'plataforma',
      ),
    );
  }
  if (vacio(finca.holderName)) {
    avisos.push(
      aviso(
        'installation.holder_name',
        'missing',
        'El titular de la finca',
        'El cuaderno se presenta a nombre del titular de la explotación.',
        'cue_identificacion',
      ),
    );
  }
  if (vacio(finca.holderNif)) {
    avisos.push(
      aviso(
        'installation.holder_nif',
        'missing',
        'El NIF del titular',
        'Identifica al titular en el cuaderno.',
        'cue_identificacion',
      ),
    );
  }
  if (vacio(finca.regionCode)) {
    avisos.push(
      aviso(
        'installation.region',
        'warning',
        'La comunidad autónoma de la finca',
        'De ella dependen las reglas autonómicas cuando se añadan.',
        'plataforma',
      ),
    );
  }

  for (const unidad of campana.cropUnits) {
    if (vacio(unidad.waterRegime)) {
      avisos.push(
        aviso(
          `crop_unit.water_regime:${unidad.id}`,
          'missing',
          `El régimen hídrico de ${unidad.cropName} (secano o regadío)`,
          'La unidad de cultivo se describe con su régimen hídrico.',
          'cue_unidad_de_cultivo',
        ),
      );
    }
    if (vacio(unidad.productionSystem)) {
      avisos.push(
        aviso(
          `crop_unit.production_system:${unidad.id}`,
          'missing',
          `El sistema de producción de ${unidad.cropName}`,
          'Convencional, integrada o ecológica.',
          'cue_unidad_de_cultivo',
        ),
      );
    }
  }

  // Coherencia entre lo respondido y lo registrado. No es normativa: es que
  // una de las dos cosas está mal, y conviene mirarlo.
  const incoherencias: Array<[string, string, string]> = [
    ['usesPlantProtectionProducts', 'phytosanitary', 'tratamientos fitosanitarios'],
    ['appliesFertilizers', 'fertilization', 'abonados'],
  ];
  for (const [pregunta, tipo, comoSeLlama] of incoherencias) {
    if (perfil[pregunta] === false && actividades.some((a) => a.type === tipo)) {
      avisos.push(
        aviso(
          `campaign.profile_mismatch:${pregunta}`,
          'warning',
          `Hay ${comoSeLlama} registrados y el cuestionario dice que no se hacen`,
          'Revisa la respuesta del cuestionario o el registro de esas actividades.',
          'plataforma',
        ),
      );
    }
  }

  return avisos;
}

/**
 * Función pura: de una campaña y sus actividades, lo que falta. Sin base de
 * datos, para poder probar cada regla por separado.
 *
 * En modo sencillo no aplica: la campaña sencilla no promete un cuaderno de
 * explotación, y marcarle carencias sería reprocharle algo que no pidió.
 */
export function calcularCompletitud(entrada: EntradaDeCompletitud) {
  const { campana, actividades } = entrada;
  const aplica = campana.managementMode === 'complete';

  const deLaCampana = aplica ? avisosDeLaCampana(entrada) : [];
  const porActividad = aplica
    ? [...actividades]
        .sort(
          (a, b) =>
            b.startDate.getTime() - a.startDate.getTime() ||
            b.createdAt.getTime() - a.createdAt.getTime(),
        )
        .map((actividad) => ({
          activityId: actividad.id,
          type: actividad.type,
          startDate: escribirFecha(actividad.startDate),
          items: avisosDeLaActividad(actividad),
        }))
        .filter((fila) => fila.items.length > 0)
    : [];

  const todos = [...deLaCampana, ...porActividad.flatMap((fila) => fila.items)];

  return {
    campaignId: campana.id,
    rules: CONJUNTO_DE_REGLAS,
    managementMode: campana.managementMode,
    /** El indicador solo existe en el cuaderno completo (ADR-0013). */
    applicable: aplica,
    missingCount: todos.filter((a) => a.kind === 'missing').length,
    warningCount: todos.filter((a) => a.kind === 'warning').length,
    /** Cuántas actividades tienen algo pendiente, de las que se han revisado. */
    activitiesWithPending: porActividad.length,
    reviewedActivities: aplica ? actividades.length : 0,
    campaign: deLaCampana,
    activities: porActividad,
  };
}

export type Completitud = ReturnType<typeof calcularCompletitud>;

@Injectable()
export class NotebookCompletenessService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly acceso: CampaignAccess,
  ) {}

  async completeness(user: AccessTokenClaims, campaignId: string): Promise<Completitud> {
    await this.acceso.cargar(user, campaignId);
    const { tenantContext } = resolveOrgContext(user);
    return this.prisma.runInTenantContext(tenantContext, (tx) => revisar(tx, campaignId));
  }
}

/**
 * La revisión en sí, para poder reutilizarla dentro de la transacción de
 * cierre sin volver a comprobar el acceso.
 */
export async function revisar(
  tx: Prisma.TransactionClient,
  campaignId: string,
): Promise<Completitud> {
  const campana = await tx.campaign.findUniqueOrThrow({
    where: { id: campaignId },
    include: INCLUDE_CAMPANA,
  });
  const finca = await tx.installation.findUniqueOrThrow({
    where: { id: campana.installationId },
    select: { holderName: true, holderNif: true, regionCode: true },
  });
  const actividades = await tx.campaignActivity.findMany({
    where: { campaignId, deletedAt: null },
    include: INCLUDE_ACTIVIDAD,
  });
  return calcularCompletitud({ campana: presentarDetalle(campana), finca, actividades });
}
