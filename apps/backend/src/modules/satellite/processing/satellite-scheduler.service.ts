import { Inject, Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Queue } from 'bullmq';
import { PrismaService } from '../../../common/prisma/prisma.service';
import {
  HistoricoPayload,
  SATELLITE_JOB_OPTIONS,
  TRABAJO_OBSERVACION,
  idTrabajoObservacion,
} from '../../../common/queues/satellite-queue';
import { ParcelsRepository } from '../../parcels/parcels.repository';
import { SATELLITE_PROVIDER, SatelliteProvider } from '../providers/satellite-provider.interface';
import { TrabajoObservacion } from './satellite-processing.service';

/** Ventana del histórico al dar de alta una parcela. */
const DIAS_HISTORICO_POR_DEFECTO = 90;

/**
 * Margen del repaso diario: se mira algo más atrás que un día por si una
 * pasada aparece en el catálogo con retraso, o por si el repaso de ayer no
 * llegó a correr.
 */
const DIAS_REPASO = 5;

/** Escenas más tapadas que esto no merecen ni pedir estadísticas. */
const MAX_NUBES_ESCENA = 0.9;

/**
 * Decide qué hay que procesar (BACKLOG.md #36). No procesa nada: busca
 * pasadas nuevas y encola un trabajo por observación.
 *
 * Solo mira parcelas de organizaciones **con `satellite_imagery` contratado**:
 * el módulo se cobra aparte, y gastar cuota de Copernicus por una organización
 * que no lo tiene sería regalar el servicio.
 */
@Injectable()
export class SatelliteSchedulerService {
  private readonly logger = new Logger(SatelliteSchedulerService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService,
    private readonly parcels: ParcelsRepository,
    @Inject(SATELLITE_PROVIDER) private readonly provider: SatelliteProvider,
  ) {}

  /**
   * Repaso diario. Recorre las organizaciones con la función contratada y,
   * por cada parcela, busca desde la última pasada que ya tiene hasta hoy.
   *
   * No se agrupa por zona ni se optimiza la búsqueda: con el número de
   * parcelas de hoy, una llamada al catálogo por parcela es barata y el código
   * se entiende. Agrupar por proximidad es una optimización que pide conocer
   * la escala real antes de hacerla.
   */
  async repasar(cola: Queue, ahora: Date = new Date()): Promise<number> {
    const organizaciones = await this.organizacionesConSatelite();
    if (organizaciones.length === 0) {
      this.logger.debug('Ninguna organización tiene el módulo de satélite contratado');
      return 0;
    }

    let encolados = 0;
    for (const organizationId of organizaciones) {
      const parcelas = await this.prisma.runInTenantContext({ organizationId }, (tx) =>
        tx.parcel.findMany({ where: { deletedAt: null }, select: { id: true } }),
      );

      for (const { id: parcelId } of parcelas) {
        try {
          const desde = await this.desdeCuandoBuscar(organizationId, parcelId, ahora);
          encolados += await this.encolarPasadas(cola, organizationId, parcelId, desde, ahora);
        } catch (error) {
          // Una parcela que falla no puede llevarse por delante el repaso de
          // las demás: se registra y se sigue.
          this.logger.error(`Parcela ${parcelId}: ${(error as Error).message}`);
        }
      }
    }

    this.logger.log(`Repaso terminado: ${encolados} observación(es) encolada(s)`);
    return encolados;
  }

  /**
   * Histórico de una parcela recién creada (o redibujada). Va en su propio
   * trabajo, no dentro del repaso diario: son decenas de pasadas de golpe y no
   * deben retrasar el trabajo del día.
   */
  async historico(
    cola: Queue,
    payload: HistoricoPayload,
    ahora: Date = new Date(),
  ): Promise<number> {
    const dias = payload.dias ?? this.diasHistorico();
    const desde = new Date(ahora.getTime() - dias * 24 * 60 * 60 * 1000);
    const encolados = await this.encolarPasadas(
      cola,
      payload.organizationId,
      payload.parcelId,
      desde,
      ahora,
    );
    this.logger.log(
      `Histórico de ${payload.parcelId}: ${encolados} observación(es) de los últimos ${dias} días`,
    );
    return encolados;
  }

  /**
   * Desde cuándo buscar: si la parcela ya tiene observaciones, desde la última
   * (con unos días de margen); si no tiene ninguna, no se hace el histórico
   * aquí — eso es trabajo del job de histórico, que va aparte.
   */
  private async desdeCuandoBuscar(
    organizationId: string,
    parcelId: string,
    ahora: Date,
  ): Promise<Date> {
    const ultima = await this.prisma.runInTenantContext({ organizationId }, (tx) =>
      tx.satelliteObservation.findFirst({
        where: { parcelId },
        orderBy: { acquisitionTime: 'desc' },
        select: { acquisitionTime: true },
      }),
    );
    const margen = DIAS_REPASO * 24 * 60 * 60 * 1000;
    if (!ultima) {
      return new Date(ahora.getTime() - margen);
    }
    return new Date(ultima.acquisitionTime.getTime() - margen);
  }

  /** Busca pasadas en la ventana y encola una por observación nueva. */
  private async encolarPasadas(
    cola: Queue,
    organizationId: string,
    parcelId: string,
    desde: Date,
    hasta: Date,
  ): Promise<number> {
    const parcela = await this.prisma.runInTenantContext({ organizationId }, (tx) =>
      this.parcels.porId(tx, parcelId, organizationId),
    );
    if (!parcela) {
      return 0;
    }

    const adquisiciones = await this.provider.buscarAdquisiciones({
      aoi: { geometry: parcela.geometry, bbox: parcela.bbox },
      desde,
      hasta,
      maxNubesEscena: MAX_NUBES_ESCENA,
    });
    if (adquisiciones.length === 0) {
      return 0;
    }

    // Las que ya están procesadas no se vuelven a encolar: la comprobación
    // también está en el propio procesado, pero hacerla aquí evita llenar la
    // cola de trabajos que no harán nada.
    const conocidas = await this.prisma.runInTenantContext({ organizationId }, (tx) =>
      tx.satelliteObservation.findMany({
        where: {
          parcelId,
          acquisitionDate: { in: adquisiciones.map((a) => new Date(a.acquisitionDate)) },
          status: { in: ['ready', 'rejected_quality'] },
        },
        select: { acquisitionDate: true },
      }),
    );
    const yaProcesadas = new Set(
      conocidas.map((o) => o.acquisitionDate.toISOString().slice(0, 10)),
    );

    let encolados = 0;
    for (const adquisicion of adquisiciones) {
      if (yaProcesadas.has(adquisicion.acquisitionDate)) {
        continue;
      }
      const trabajo: TrabajoObservacion = {
        organizationId,
        parcelId,
        provider: this.provider.code,
        collection: adquisicion.collection,
        acquisitionDate: adquisicion.acquisitionDate,
        acquisitionTime: adquisicion.acquisitionTime.toISOString(),
        sourceItemIds: adquisicion.itemIds,
        platform: adquisicion.platform,
        sceneCloudCover: adquisicion.sceneCloudCover,
      };
      await cola.add(TRABAJO_OBSERVACION, trabajo, {
        ...SATELLITE_JOB_OPTIONS,
        // Determinista: si el repaso y el histórico coinciden, BullMQ se
        // queda con uno solo en vez de procesar la misma pasada dos veces.
        jobId: idTrabajoObservacion(trabajo),
      });
      encolados++;
    }
    return encolados;
  }

  /**
   * Organizaciones con `satellite_imagery` activo. Se consulta como job de
   * sistema (`isPlatformAdmin`), igual que el resto de trabajos periódicos.
   */
  private async organizacionesConSatelite(): Promise<string[]> {
    const filas = await this.prisma.runInTenantContext({ isPlatformAdmin: true }, (tx) =>
      tx.organizationFeature.findMany({
        where: { featureCode: 'satellite_imagery', enabled: true },
        select: { organizationId: true },
      }),
    );
    return filas.map((f) => f.organizationId);
  }

  private diasHistorico(): number {
    const valor = Number(this.config.get<string>('SATELLITE_BACKFILL_DAYS'));
    return Number.isFinite(valor) && valor > 0 ? valor : DIAS_HISTORICO_POR_DEFECTO;
  }
}
