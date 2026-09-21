import { Inject, Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../../../common/prisma/prisma.service';
import { StorageService } from '../../../common/storage/storage.service';
import {
  MEDIA_TYPES,
  TipoArchivoSatelite,
  claveObjetoSatelite,
} from '../../../common/storage/object-keys';
import { ParcelsRepository } from '../../parcels/parcels.repository';
import { SATELLITE_PROVIDER, SatelliteProvider } from '../providers/satellite-provider.interface';
import { AreaDeInteres, SatelliteProviderError } from '../providers/satellite.types';
import { PROCESSING_VERSION } from '../providers/copernicus/evalscripts';

/**
 * Un trabajo = una observación: una parcela, un proveedor y un día de pasada.
 * Es lo que viaja por la cola `satellite-processing`.
 */
export interface TrabajoObservacion {
  organizationId: string;
  parcelId: string;
  provider: string;
  collection: string;
  /** `YYYY-MM-DD` en UTC: la clave lógica de la observación. */
  acquisitionDate: string;
  acquisitionTime: string; // ISO-8601
  sourceItemIds: string[];
  platform?: string;
  sceneCloudCover?: number;
}

/** Por debajo de esto, la observación no sirve para medir nada. */
const MINIMO_VALIDO_POR_DEFECTO = 0.5;
/** Por encima, la observación se considera limpia. */
const BUENO_POR_DEFECTO = 0.85;

@Injectable()
export class SatelliteProcessingService {
  private readonly logger = new Logger(SatelliteProcessingService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService,
    private readonly parcels: ParcelsRepository,
    private readonly storage: StorageService,
    @Inject(SATELLITE_PROVIDER) private readonly provider: SatelliteProvider,
  ) {}

  /**
   * Procesa una observación de principio a fin:
   *
   *   estadísticas -> ¿calidad suficiente? -> ráster -> S3 -> base de datos
   *
   * En ese orden a propósito. La estadística es barata y dice si la pasada
   * sirve; el ráster es lo caro en cuota y en bytes. Pedirlo antes de saber si
   * la parcela estaba tapada de nubes sería gastar por gastar.
   *
   * **Idempotente**: si ya hay una observación `ready` con esa clave lógica,
   * no se vuelve a procesar. La misma pasada llega por varias vías (el repaso
   * diario, el histórico inicial, un refresco a mano) y no debe costar tres
   * veces.
   */
  async procesar(trabajo: TrabajoObservacion): Promise<void> {
    const comienzo = Date.now();
    const contexto = { organizationId: trabajo.organizationId };

    const parcela = await this.prisma.runInTenantContext(contexto, (tx) =>
      this.parcels.porId(tx, trabajo.parcelId, trabajo.organizationId),
    );
    if (!parcela) {
      // Borrada mientras el trabajo esperaba en la cola. No es un fallo.
      this.logger.log(`Parcela ${trabajo.parcelId} ya no existe; se descarta el trabajo`);
      return;
    }

    const yaEsta = await this.prisma.runInTenantContext(contexto, (tx) =>
      tx.satelliteObservation.findFirst({
        where: {
          parcelId: trabajo.parcelId,
          provider: trabajo.provider,
          collection: trabajo.collection,
          acquisitionDate: new Date(trabajo.acquisitionDate),
          processingVersion: PROCESSING_VERSION,
          status: { in: ['ready', 'rejected_quality'] },
        },
      }),
    );
    if (yaEsta) {
      this.logger.debug(
        `${trabajo.parcelId} ${trabajo.acquisitionDate}: ya procesada (${yaEsta.status})`,
      );
      return;
    }

    const observacion = await this.marcarEnCurso(trabajo, parcela.geometryVersion);
    const aoi: AreaDeInteres = { geometry: parcela.geometry, bbox: parcela.bbox };

    try {
      const estadisticas = await this.provider.estadisticas({
        aoi,
        acquisitionDate: trabajo.acquisitionDate,
        metricCode: 'ndvi',
      });

      const calidad = this.calificar(estadisticas.validPixelFraction);
      if (calidad === 'rejected') {
        // Se guarda igualmente, con su motivo: así la pantalla puede explicar
        // por qué ese día no hay dato en vez de dejar un hueco mudo, y el
        // repaso diario no vuelve a intentarlo cada mañana.
        await this.cerrarPorCalidad(observacion.id, contexto, estadisticas.validPixelFraction);
        this.logger.log(
          `${trabajo.parcelId} ${trabajo.acquisitionDate}: descartada, solo ${Math.round(
            estadisticas.validPixelFraction * 100,
          )} % de superficie válida`,
        );
        return;
      }

      // Solo ahora, con la calidad ya comprobada, se gasta en imágenes.
      const archivos = await this.subirRasters(trabajo, observacion.id, aoi);

      await this.prisma.runInTenantContext(contexto, async (tx) => {
        await tx.satelliteMetric.upsert({
          where: {
            observationId_metricCode: { observationId: observacion.id, metricCode: 'ndvi' },
          },
          create: {
            organizationId: trabajo.organizationId,
            observationId: observacion.id,
            metricCode: 'ndvi',
            mean: estadisticas.mean,
            median: estadisticas.median,
            min: estadisticas.min,
            max: estadisticas.max,
            stdDev: estadisticas.stdDev,
            p10: estadisticas.p10,
            p90: estadisticas.p90,
            sampleCount: estadisticas.sampleCount,
            noDataCount: estadisticas.noDataCount,
          },
          update: {},
        });

        for (const archivo of archivos) {
          await tx.satelliteAsset.upsert({
            where: {
              observationId_assetType: {
                observationId: observacion.id,
                assetType: archivo.assetType,
              },
            },
            create: {
              organizationId: trabajo.organizationId,
              observationId: observacion.id,
              ...archivo,
            },
            update: {},
          });
        }

        await tx.satelliteObservation.update({
          where: { id: observacion.id },
          data: {
            status: 'ready',
            qualityStatus: calidad,
            validPixelFraction: estadisticas.validPixelFraction,
            processedAt: new Date(),
            lastError: null,
          },
        });
      });

      this.logger.log(
        `${trabajo.parcelId} ${trabajo.acquisitionDate}: NDVI medio ${estadisticas.mean.toFixed(
          3,
        )}, ${Math.round(estadisticas.validPixelFraction * 100)} % válido, ${Date.now() - comienzo} ms`,
      );
    } catch (error) {
      await this.marcarFallida(observacion.id, contexto, error as Error);
      throw error; // que BullMQ decida si lo reintenta
    }
  }

  /**
   * Abre (o recupera) la fila de la observación. Se escribe antes de llamar a
   * Copernicus para que un fallo a mitad deje rastro de lo que se intentó, en
   * vez de un silencio.
   */
  private async marcarEnCurso(trabajo: TrabajoObservacion, parcelGeometryVersion: number) {
    return this.prisma.runInTenantContext({ organizationId: trabajo.organizationId }, (tx) =>
      tx.satelliteObservation.upsert({
        where: {
          claveLogica: {
            parcelId: trabajo.parcelId,
            provider: trabajo.provider,
            collection: trabajo.collection,
            acquisitionDate: new Date(trabajo.acquisitionDate),
            processingVersion: PROCESSING_VERSION,
          },
        },
        create: {
          organizationId: trabajo.organizationId,
          parcelId: trabajo.parcelId,
          provider: trabajo.provider,
          collection: trabajo.collection,
          acquisitionTime: new Date(trabajo.acquisitionTime),
          acquisitionDate: new Date(trabajo.acquisitionDate),
          sourceItemIds: trabajo.sourceItemIds as unknown as Prisma.InputJsonValue,
          platform: trabajo.platform,
          processingVersion: PROCESSING_VERSION,
          parcelGeometryVersion,
          sceneCloudCover: trabajo.sceneCloudCover,
          status: 'processing',
        },
        update: { status: 'processing', parcelGeometryVersion, lastError: null },
      }),
    );
  }

  /**
   * Los dos productos, en dos peticiones: el GeoTIFF FLOAT32 es el dato del
   * que se puede recalcular cualquier cosa, y el PNG solo sirve para pintar el
   * mapa. Nunca se toman las estadísticas del PNG.
   *
   * Todo va en memoria y de ahí a S3: **nada se escribe en el disco de la
   * VPS**, que tiene poco sitio (BACKLOG.md #54).
   */
  private async subirRasters(
    trabajo: TrabajoObservacion,
    observationId: string,
    aoi: AreaDeInteres,
  ) {
    const acquisitionTime = new Date(trabajo.acquisitionTime);
    const formatos: Array<{ tipo: TipoArchivoSatelite; formato: 'geotiff' | 'png' }> = [
      { tipo: 'ndvi_raster', formato: 'geotiff' },
      { tipo: 'ndvi_preview', formato: 'png' },
    ];

    const archivos = [];
    for (const { tipo, formato } of formatos) {
      const raster = await this.provider.raster({
        aoi,
        acquisitionDate: trabajo.acquisitionDate,
        metricCode: 'ndvi',
        formato,
      });
      const clave = claveObjetoSatelite({
        organizationId: trabajo.organizationId,
        parcelId: trabajo.parcelId,
        provider: trabajo.provider,
        collection: trabajo.collection,
        acquisitionTime,
        observationId,
        processingVersion: PROCESSING_VERSION,
        tipo,
      });
      const subido = await this.storage.subir({
        clave,
        cuerpo: raster.bytes,
        contentType: MEDIA_TYPES[tipo],
        metadatos: { parcelid: trabajo.parcelId, processingversion: PROCESSING_VERSION },
      });

      archivos.push({
        assetType: tipo,
        objectKey: subido.objectKey,
        mediaType: raster.mediaType,
        width: raster.width,
        height: raster.height,
        bboxMinLon: aoi.bbox[0],
        bboxMinLat: aoi.bbox[1],
        bboxMaxLon: aoi.bbox[2],
        bboxMaxLat: aoi.bbox[3],
        crs: raster.crs,
        // NaN no cabe en una columna `double precision` de Postgres tal cual
        // desde Prisma; el GeoTIFF lo lleva en su cabecera de todos modos.
        nodata: raster.nodata !== null && Number.isNaN(raster.nodata) ? null : raster.nodata,
        byteSize: subido.byteSize,
        checksum: subido.checksum,
      });
    }
    return archivos;
  }

  /**
   * Tres niveles y no dos: entre "sirve" y "no sirve" hay observaciones medio
   * tapadas que valen para ver la tendencia pero no para comparar con otra
   * fecha. Se guardan y se marcan, y es la pantalla la que decide cuánto
   * énfasis darles.
   */
  private calificar(validPixelFraction: number): 'good' | 'partial' | 'rejected' {
    if (
      validPixelFraction >= this.umbral('SATELLITE_GOOD_VALID_PIXEL_FRACTION', BUENO_POR_DEFECTO)
    ) {
      return 'good';
    }
    if (
      validPixelFraction >=
      this.umbral('SATELLITE_MIN_VALID_PIXEL_FRACTION', MINIMO_VALIDO_POR_DEFECTO)
    ) {
      return 'partial';
    }
    return 'rejected';
  }

  /** Configurable a propósito: el listón de calidad no debe estar escondido en el código. */
  private umbral(clave: string, porDefecto: number): number {
    const valor = Number(this.config.get<string>(clave));
    return Number.isFinite(valor) && valor > 0 && valor <= 1 ? valor : porDefecto;
  }

  private async cerrarPorCalidad(
    observationId: string,
    contexto: { organizationId: string },
    validPixelFraction: number,
  ): Promise<void> {
    await this.prisma.runInTenantContext(contexto, (tx) =>
      tx.satelliteObservation.update({
        where: { id: observationId },
        data: {
          status: 'rejected_quality',
          qualityStatus: 'rejected',
          validPixelFraction,
          processedAt: new Date(),
        },
      }),
    );
  }

  /**
   * Deja escrito el motivo del fallo. El mensaje se recorta y nunca lleva
   * credenciales: los errores del proveedor ya vienen saneados
   * (`SatelliteProviderError`) y aquí solo se guarda su texto.
   */
  private async marcarFallida(
    observationId: string,
    contexto: { organizationId: string },
    error: Error,
  ): Promise<void> {
    const temporal = error instanceof SatelliteProviderError && error.opciones.reintentable;
    await this.prisma.runInTenantContext(contexto, (tx) =>
      tx.satelliteObservation.update({
        where: { id: observationId },
        data: {
          // Si es temporal se queda en `pending`: el reintento de la cola la
          // recogerá. `failed` es para lo que no se arregla insistiendo.
          status: temporal ? 'pending' : 'failed',
          lastError: error.message.slice(0, 500),
        },
      }),
    );
  }
}
