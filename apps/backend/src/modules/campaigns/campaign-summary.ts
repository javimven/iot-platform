import { Injectable } from '@nestjs/common';
import { AccessTokenClaims } from '../../common/guards/jwt-auth.guard';
import { resolveOrgContext } from '../../common/permissions/org-context';
import { PrismaService } from '../../common/prisma/prisma.service';
import { ActividadCompleta, INCLUDE_ACTIVIDAD, superficieDelDestino } from './activity.presenter';
import { CampaignAccess } from './campaign-access';
import { INCLUDE_CAMPANA, presentarDetalle } from './campaign.presenter';
import { escribirFecha } from './fechas';

type Detalle = ReturnType<typeof presentarDetalle>;

function redondear(valor: number, decimales = 1): number {
  const factor = 10 ** decimales;
  return Math.round(valor * factor) / factor;
}

function porHectarea(total: number, superficieHa: number): number | null {
  return superficieHa > 0 ? redondear(total / superficieHa) : null;
}

function superficieDe(actividad: ActividadCompleta): number {
  return actividad.targets.reduce((suma, d) => suma + superficieDelDestino(d), 0);
}

/**
 * El resumen de una campaña, calculado de sus actividades. Sin nada que no
 * salga de ellas, y **sin métricas vacías**: un apartado sin actividades es
 * nulo, no un cero que parezca una medida. Lo que no se pudo calcular se
 * cuenta aparte ("3 riegos sin cantidad"), para que se vea qué falta.
 *
 * Función pura, para poder probar los números sin base de datos.
 */
export function calcularResumen(campana: Detalle, actividades: ActividadCompleta[]) {
  const superficie = campana.areaHa;
  const deTipo = (tipo: string) => actividades.filter((a) => a.type === tipo);

  const riegos = deTipo('irrigation');
  const metrosCubicos = riegos.reduce((suma, a) => suma + (a.irrigation?.volumeM3 ?? 0), 0);

  const abonados = deTipo('fertilization');
  const kilosDe = (campo: 'nKgHa' | 'p2o5KgHa' | 'k2oKgHa') =>
    abonados.reduce((suma, a) => suma + (a.fertilization?.[campo] ?? 0) * superficieDe(a), 0);
  const [n, p2o5, k2o] = [kilosDe('nKgHa'), kilosDe('p2o5KgHa'), kilosDe('k2oKgHa')];

  const tratamientos = deTipo('phytosanitary');
  const productos = new Set(
    tratamientos.flatMap((a) => a.phytosanitaryProducts.map((p) => p.productName.toLowerCase())),
  );

  const cosechas = deTipo('harvest');
  const kilos = cosechas.reduce((suma, a) => suma + (a.harvest?.quantityKg ?? 0), 0);

  // El esperado, de las unidades que lo tienen y sobre su propia superficie.
  const conEsperado = campana.cropUnits.filter((u) => u.expectedYieldKgHa != null);
  const superficieConEsperado = conEsperado.reduce((suma, u) => suma + u.effectiveAreaHa, 0);
  const esperado =
    superficieConEsperado > 0
      ? redondear(
          conEsperado.reduce((suma, u) => suma + u.expectedYieldKgHa! * u.effectiveAreaHa, 0) /
            superficieConEsperado,
        )
      : null;

  const ultima = [...actividades].sort(
    (a, b) =>
      b.startDate.getTime() - a.startDate.getTime() ||
      b.createdAt.getTime() - a.createdAt.getTime(),
  )[0];

  return {
    campaignId: campana.id,
    areaHa: superficie,
    activityCount: actividades.length,
    lastActivity: ultima ? { type: ultima.type, date: escribirFecha(ultima.startDate) } : null,
    irrigation:
      riegos.length === 0
        ? null
        : {
            count: riegos.length,
            volumeM3: redondear(metrosCubicos),
            volumeM3PerHa: porHectarea(metrosCubicos, superficie),
            withoutVolume: riegos.filter((a) => a.irrigation?.volumeM3 == null).length,
          },
    fertilization:
      abonados.length === 0
        ? null
        : {
            count: abonados.length,
            nKg: redondear(n),
            p2o5Kg: redondear(p2o5),
            k2oKg: redondear(k2o),
            nKgHa: porHectarea(n, superficie),
            p2o5KgHa: porHectarea(p2o5, superficie),
            k2oKgHa: porHectarea(k2o, superficie),
            // Sin riqueza o con la dosis en litros: no se puede pasar a kg de nutriente.
            withoutComposition: abonados.filter(
              (a) =>
                a.fertilization?.nKgHa == null &&
                a.fertilization?.p2o5KgHa == null &&
                a.fertilization?.k2oKgHa == null,
            ).length,
          },
    phytosanitary:
      tratamientos.length === 0
        ? null
        : { count: tratamientos.length, distinctProducts: productos.size },
    harvest:
      cosechas.length === 0
        ? null
        : {
            count: cosechas.length,
            quantityKg: redondear(kilos),
            yieldKgHa: kilos > 0 ? porHectarea(kilos, superficie) : null,
            expectedYieldKgHa: esperado,
            withoutKg: cosechas.filter((a) => a.harvest?.quantityKg == null).length,
          },
    fieldWork: deTipo('field_work').length === 0 ? null : { count: deTipo('field_work').length },
    observations:
      deTipo('observation').length === 0 ? null : { count: deTipo('observation').length },
    cropUnits: campana.cropUnits.map((unidad) => {
      // Solo las cosechas enteras de esta unidad: repartir por superficie una
      // cosecha de dos cultivos sería inventarse el reparto.
      const suyas = cosechas.filter(
        (a) => a.targets.length > 0 && a.targets.every((d) => d.cropUnitId === unidad.id),
      );
      const kilosUnidad = suyas.reduce((suma, a) => suma + (a.harvest?.quantityKg ?? 0), 0);
      return {
        id: unidad.id,
        cropName: unidad.variety ? `${unidad.cropName} ${unidad.variety}` : unidad.cropName,
        areaHa: unidad.effectiveAreaHa,
        harvestKg: suyas.length > 0 ? redondear(kilosUnidad) : null,
        yieldKgHa: kilosUnidad > 0 ? porHectarea(kilosUnidad, unidad.effectiveAreaHa) : null,
        expectedYieldKgHa: unidad.expectedYieldKgHa,
      };
    }),
  };
}

@Injectable()
export class CampaignSummaryService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly acceso: CampaignAccess,
  ) {}

  async summary(user: AccessTokenClaims, campaignId: string) {
    await this.acceso.cargar(user, campaignId);
    const { tenantContext } = resolveOrgContext(user);
    return this.prisma.runInTenantContext(tenantContext, async (tx) => {
      const campana = await tx.campaign.findUniqueOrThrow({
        where: { id: campaignId },
        include: INCLUDE_CAMPANA,
      });
      const actividades = await tx.campaignActivity.findMany({
        where: { campaignId, deletedAt: null },
        include: INCLUDE_ACTIVIDAD,
      });
      return calcularResumen(presentarDetalle(campana), actividades);
    });
  }
}
