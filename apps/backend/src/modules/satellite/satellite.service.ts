import { HttpException, HttpStatus, Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../../common/prisma/prisma.service';
import { StorageService } from '../../common/storage/storage.service';
import { SatelliteQueueProducer } from '../../common/queues/satellite-queue.producer';
import { AccessTokenClaims } from '../../common/guards/jwt-auth.guard';
import { resolveOrgContext } from '../../common/permissions/org-context';
import { ParcelsService } from '../parcels/parcels.service';

/** Días que se vuelven a mirar en un refresco manual. */
const DIAS_REFRESCO = 15;

/**
 * Lo que la app lee del módulo de satélite (BACKLOG.md #36).
 *
 * Cada método empieza por `parcels.findOne`, que ya resuelve organización,
 * alcance por instalación y 404 — así no hay dos maneras distintas de
 * comprobar quién puede ver una parcela.
 *
 * Lo que sale de aquí está pensado para la pantalla: números redondeados
 * donde no tiene sentido la falsa precisión, y la calidad siempre al lado del
 * valor para que nadie pinte un NDVI de un día nublado como si tal cosa.
 */
@Injectable()
export class SatelliteService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly parcels: ParcelsService,
    private readonly storage: StorageService,
    private readonly cola: SatelliteQueueProducer,
  ) {}

  /** La última observación utilizable: lo primero que enseña la pantalla. */
  async ultima(user: AccessTokenClaims, parcelId: string) {
    await this.parcels.findOne(user, parcelId);
    const { tenantContext } = resolveOrgContext(user);

    const observacion = await this.prisma.runInTenantContext(tenantContext, (tx) =>
      tx.satelliteObservation.findFirst({
        where: { parcelId, status: 'ready' },
        orderBy: { acquisitionTime: 'desc' },
        include: { metrics: true },
      }),
    );
    return observacion ? this.comoDetalle(observacion) : null;
  }

  /**
   * Histórico de observaciones. Incluye las descartadas por calidad si se
   * piden: son la explicación de por qué la serie tiene un hueco.
   */
  async observaciones(
    user: AccessTokenClaims,
    parcelId: string,
    filtros: { from?: Date; to?: Date; incluirDescartadas?: boolean },
  ) {
    await this.parcels.findOne(user, parcelId);
    const { tenantContext } = resolveOrgContext(user);

    const observaciones = await this.prisma.runInTenantContext(tenantContext, (tx) =>
      tx.satelliteObservation.findMany({
        where: {
          parcelId,
          status: filtros.incluirDescartadas ? { in: ['ready', 'rejected_quality'] } : 'ready',
          acquisitionTime: this.ventana(filtros.from, filtros.to),
        },
        orderBy: { acquisitionTime: 'desc' },
        include: { metrics: true },
      }),
    );
    return observaciones.map((o) => this.comoDetalle(o));
  }

  /**
   * Serie temporal para la gráfica. Mismo formato que el histórico de un canal
   * de telemetría (`tsOrigin`/`value`), para que la app reutilice lo que ya
   * tiene — con la calidad añadida, que en satélite no es un detalle.
   *
   * Solo entran observaciones utilizables: una descartada por nubes no puede
   * dibujar un punto como si fuera una medida.
   */
  async serie(user: AccessTokenClaims, parcelId: string, filtros: { from?: Date; to?: Date }) {
    await this.parcels.findOne(user, parcelId);
    const { tenantContext } = resolveOrgContext(user);

    const observaciones = await this.prisma.runInTenantContext(tenantContext, (tx) =>
      tx.satelliteObservation.findMany({
        where: {
          parcelId,
          status: 'ready',
          acquisitionTime: this.ventana(filtros.from, filtros.to),
        },
        orderBy: { acquisitionTime: 'asc' }, // ascendente: es una gráfica
        include: { metrics: { where: { metricCode: 'ndvi' } } },
      }),
    );

    return observaciones
      .filter((o) => o.metrics.length > 0)
      .map((o) => ({
        tsOrigin: o.acquisitionTime,
        value: o.metrics[0].mean,
        median: o.metrics[0].median,
        observationId: o.id,
        qualityStatus: o.qualityStatus,
        validPixelFraction: o.validPixelFraction,
      }));
  }

  async observacion(user: AccessTokenClaims, parcelId: string, observationId: string) {
    await this.parcels.findOne(user, parcelId);
    const { tenantContext } = resolveOrgContext(user);

    const observacion = await this.prisma.runInTenantContext(tenantContext, (tx) =>
      tx.satelliteObservation.findFirst({
        where: { id: observationId, parcelId },
        include: { metrics: true, assets: true },
      }),
    );
    if (!observacion) {
      throw new NotFoundException('Satellite observation not found');
    }
    return this.comoDetalle(observacion);
  }

  /** Los archivos de una observación, sin la URL: esa se pide aparte y caduca. */
  async assets(user: AccessTokenClaims, parcelId: string, observationId: string) {
    const observacion = await this.observacion(user, parcelId, observationId);
    return observacion.assets ?? [];
  }

  /**
   * URL temporal de descarga. El bucket es privado y las credenciales no
   * salen del backend (SECURITY.md): lo que recibe el cliente es un enlace
   * firmado que caduca solo.
   */
  async urlDeAsset(
    user: AccessTokenClaims,
    parcelId: string,
    observationId: string,
    assetId: string,
  ) {
    await this.parcels.findOne(user, parcelId);
    const { tenantContext } = resolveOrgContext(user);

    const asset = await this.prisma.runInTenantContext(tenantContext, (tx) =>
      tx.satelliteAsset.findFirst({
        where: { id: assetId, observationId, observation: { parcelId } },
      }),
    );
    if (!asset) {
      throw new NotFoundException('Satellite asset not found');
    }

    const enlace = await this.storage.urlFirmada(asset.objectKey);
    return {
      assetId: asset.id,
      assetType: asset.assetType,
      mediaType: asset.mediaType,
      url: enlace.url,
      expiresAt: enlace.expiresAt,
    };
  }

  /**
   * Refresco a mano. Útil cuando alguien acaba de dibujar una parcela y no
   * quiere esperar, o para diagnosticar. Como cada llamada puede acabar en
   * varias peticiones a Copernicus, solo se admite una por parcela y hora.
   */
  async refrescar(user: AccessTokenClaims, parcelId: string) {
    await this.parcels.findOne(user, parcelId);
    const { organizationId } = resolveOrgContext(user);

    const encolado = await this.cola.encolarRefresco({
      organizationId,
      parcelId,
      dias: DIAS_REFRESCO,
    });
    if (!encolado) {
      throw new HttpException(
        'Esta parcela ya se ha actualizado hace menos de una hora.',
        HttpStatus.TOO_MANY_REQUESTS,
      );
    }
    return { estado: 'encolado', dias: DIAS_REFRESCO };
  }

  private ventana(from?: Date, to?: Date) {
    if (!from && !to) {
      return undefined;
    }
    return { ...(from ? { gte: from } : {}), ...(to ? { lte: to } : {}) };
  }

  /**
   * Forma de salida. La calidad va como porcentaje entero: enseñar
   * "92,348729 % de superficie válida" sería falsa precisión, y el número solo
   * sirve para que el usuario sepa si fiarse del dato.
   */
  private comoDetalle(observacion: {
    id: string;
    acquisitionTime: Date;
    provider: string;
    collection: string;
    platform: string | null;
    processingVersion: string;
    parcelGeometryVersion: number;
    status: string;
    qualityStatus: string | null;
    validPixelFraction: number | null;
    sceneCloudCover: number | null;
    metrics?: Array<{
      metricCode: string;
      mean: number;
      median: number;
      min: number;
      max: number;
      stdDev: number;
      p10: number;
      p90: number;
    }>;
    assets?: Array<{
      id: string;
      assetType: string;
      mediaType: string;
      width: number | null;
      height: number | null;
      byteSize: number;
    }>;
  }) {
    return {
      observationId: observacion.id,
      acquisitionTime: observacion.acquisitionTime,
      provider: observacion.provider,
      collection: observacion.collection,
      platform: observacion.platform,
      processingVersion: observacion.processingVersion,
      parcelGeometryVersion: observacion.parcelGeometryVersion,
      status: observacion.status,
      quality: {
        status: observacion.qualityStatus,
        validPixelFraction: observacion.validPixelFraction,
        validPixelPercent:
          observacion.validPixelFraction === null
            ? null
            : Math.round(observacion.validPixelFraction * 100),
        sceneCloudCover: observacion.sceneCloudCover,
      },
      metrics: Object.fromEntries(
        (observacion.metrics ?? []).map((m) => [
          m.metricCode,
          {
            mean: m.mean,
            median: m.median,
            min: m.min,
            max: m.max,
            stdDev: m.stdDev,
            p10: m.p10,
            p90: m.p90,
          },
        ]),
      ),
      assets: observacion.assets?.map((a) => ({
        assetId: a.id,
        assetType: a.assetType,
        mediaType: a.mediaType,
        width: a.width,
        height: a.height,
        byteSize: a.byteSize,
      })),
    };
  }
}
