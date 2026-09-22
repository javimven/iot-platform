import { Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Job, Queue, UnrecoverableError, Worker } from 'bullmq';
import IORedis from 'ioredis';
import {
  HistoricoPayload,
  SATELLITE_JOB_OPTIONS,
  SATELLITE_QUEUE_NAME,
  SatelliteJobPayload,
  TRABAJO_HISTORICO,
  TRABAJO_OBSERVACION,
  TRABAJO_REPASO,
} from '../../common/queues/satellite-queue';
import {
  SatelliteProcessingService,
  TrabajoObservacion,
} from '../../modules/satellite/processing/satellite-processing.service';
import { SatelliteSchedulerService } from '../../modules/satellite/processing/satellite-scheduler.service';
import { SatelliteProviderError } from '../../modules/satellite/providers/satellite.types';

/**
 * Lo que el proveedor marca como no reintentable llega a BullMQ como
 * `UnrecoverableError`, y la cola no lo repite. Sin esto, un 406 de Copernicus
 * (petición mal hecha) se intentó tres veces el 2026-09-22: cada intento, otra
 * llamada contra la cuota, para obtener el mismo error.
 */
export function paraLaCola(error: unknown): unknown {
  if (error instanceof SatelliteProviderError && !error.opciones.reintentable) {
    return new UnrecoverableError(error.message);
  }
  return error;
}

/** Identificador del repaso programado. Fijo: no se acumulan planificaciones. */
const PLANIFICACION_REPASO = 'satelite-repaso-diario';

/**
 * A las 4:30 UTC: de madrugada, y a una hora rara a propósito para no caer en
 * el minuto en punto en el que medio mundo lanza sus cron.
 */
const CRON_REPASO = '30 4 * * *';

/**
 * Consumidor de la cola de satélite en el proceso `worker` (BACKLOG.md #36).
 * Tres tipos de trabajo sobre la misma cola: el repaso diario, el histórico de
 * una parcela nueva y una observación concreta.
 *
 * ## Por qué un job repetible de BullMQ y no `setInterval`
 *
 * El resto de trabajos periódicos del proyecto usan `setInterval`
 * (`OfflineDetectionService` y compañía) y funcionan bien **porque hoy hay un
 * solo `worker`**. Eso está escrito como limitación conocida desde entonces.
 * Aquí no se hereda ese patrón: el planificador de BullMQ guarda la
 * planificación en Redis, así que con dos réplicas el repaso se ejecuta **una
 * vez**, no dos. Dos escaneos simultáneos no solo duplicarían trabajo: sobre
 * una API con cuota, duplicarían el gasto.
 *
 * Además sale gratis lo que `setInterval` no da: reintentos, historial de
 * fallos y un trabajo que no se pierde si el proceso se reinicia a mitad.
 * Ninguna tecnología nueva — BullMQ ya estaba.
 */
@Injectable()
export class SatelliteWorkerService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(SatelliteWorkerService.name);
  private worker?: Worker<SatelliteJobPayload>;
  private cola?: Queue<SatelliteJobPayload>;
  private conexion?: IORedis;

  constructor(
    private readonly procesado: SatelliteProcessingService,
    private readonly planificador: SatelliteSchedulerService,
    private readonly config: ConfigService,
  ) {}

  async onModuleInit(): Promise<void> {
    this.conexion = new IORedis(this.config.getOrThrow<string>('REDIS_URL'), {
      maxRetriesPerRequest: null, // requerido por BullMQ
    });
    this.cola = new Queue<SatelliteJobPayload>(SATELLITE_QUEUE_NAME, {
      connection: this.conexion,
    });

    this.worker = new Worker<SatelliteJobPayload>(
      SATELLITE_QUEUE_NAME,
      (job) => this.ejecutar(job),
      {
        connection: this.conexion,
        // De uno en uno: al otro lado hay una API con cuota, y el ráster se
        // arma en memoria. Ir en paralelo aquí no acelera nada que importe.
        concurrency: 1,
      },
    );

    this.worker.on('failed', (job, error) => {
      this.logger.error(
        `Trabajo ${job?.name} ${job?.id} falló (intento ${job?.attemptsMade}): ${error.message}`,
      );
    });

    await this.programarRepaso();
  }

  async onModuleDestroy(): Promise<void> {
    await this.worker?.close();
    await this.cola?.close();
    this.conexion?.disconnect();
  }

  /**
   * Deja registrado el repaso diario. `upsertJobScheduler` es idempotente:
   * arrancar el worker diez veces no crea diez planificaciones, y si un día se
   * cambia la hora, se actualiza la que hay.
   */
  private async programarRepaso(): Promise<void> {
    if (!this.cola) {
      return;
    }
    await this.cola.upsertJobScheduler(
      PLANIFICACION_REPASO,
      { pattern: CRON_REPASO, tz: 'UTC' },
      {
        name: TRABAJO_REPASO,
        data: { origen: 'programado' },
        opts: { ...SATELLITE_JOB_OPTIONS, attempts: 1 },
      },
    );
    this.logger.log(`Repaso de satélite programado (${CRON_REPASO} UTC)`);
  }

  private async ejecutar(job: Job<SatelliteJobPayload>): Promise<void> {
    if (!this.cola) {
      throw new Error('La cola de satélite no está lista');
    }

    try {
      await this.despachar(job, this.cola);
    } catch (error) {
      throw paraLaCola(error);
    }
  }

  private async despachar(job: Job<SatelliteJobPayload>, cola: Queue<SatelliteJobPayload>) {
    switch (job.name) {
      case TRABAJO_REPASO:
        await this.planificador.repasar(cola);
        return;
      case TRABAJO_HISTORICO:
        await this.planificador.historico(cola, job.data as HistoricoPayload);
        return;
      case TRABAJO_OBSERVACION:
        await this.procesado.procesar(job.data as TrabajoObservacion);
        return;
      default:
        // Un trabajo de un tipo que este worker no conoce: probablemente una
        // versión anterior. Se registra y se descarta en vez de reintentarlo
        // para siempre.
        this.logger.warn(`Tipo de trabajo desconocido, se descarta: ${job.name}`);
    }
  }
}
