import { Injectable, Logger, OnModuleDestroy } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Queue } from 'bullmq';
import IORedis from 'ioredis';
import {
  HistoricoPayload,
  SATELLITE_JOB_OPTIONS,
  SATELLITE_QUEUE_NAME,
  TRABAJO_HISTORICO,
} from './satellite-queue';

/**
 * Lado productor de la cola de satélite, para los procesos que **no** la
 * consumen. Hoy solo lo usa `api`, al dar de alta una parcela: sin esto, una
 * parcela recién creada no tendría ni un dato hasta el repaso de la mañana
 * siguiente, y eso es una primera impresión muy pobre.
 *
 * La conexión se abre la primera vez que se usa. `api` ya tiene `REDIS_URL`
 * (docker-compose), pero no todos los entornos de prueba lo tienen, y abrirla
 * al arrancar rompería el proceso por algo que casi nunca se usa.
 *
 * Nunca lanza: que el histórico no se encole no puede tumbar la creación de
 * la parcela. El repaso diario lo recogerá igualmente.
 */
@Injectable()
export class SatelliteQueueProducer implements OnModuleDestroy {
  private readonly logger = new Logger(SatelliteQueueProducer.name);
  private cola?: Queue;
  private conexion?: IORedis;

  constructor(private readonly config: ConfigService) {}

  async encolarHistorico(payload: HistoricoPayload): Promise<void> {
    try {
      const cola = this.obtenerCola();
      await cola.add(TRABAJO_HISTORICO, payload, {
        ...SATELLITE_JOB_OPTIONS,
        // Uno por parcela: si alguien crea y redibuja varias veces seguidas,
        // no se acumulan históricos idénticos.
        jobId: `historico:${payload.parcelId}`,
      });
      this.logger.log(`Histórico de satélite encolado para la parcela ${payload.parcelId}`);
    } catch (error) {
      this.logger.error(
        `No se pudo encolar el histórico de ${payload.parcelId}: ${(error as Error).message}`,
      );
    }
  }

  /**
   * Refresco pedido a mano desde la app. Devuelve `false` si esa parcela ya
   * tuvo uno en la última hora.
   *
   * El cortafuegos va en el identificador del trabajo: lleva la hora, así que
   * dos refrescos de la misma hora son el mismo trabajo para BullMQ. Eso evita
   * que alguien se ponga a pulsar el botón y nos coma la cuota de Copernicus,
   * sin necesidad de guardar en ninguna parte cuándo fue el último.
   */
  async encolarRefresco(payload: HistoricoPayload): Promise<boolean> {
    const hora = new Date().toISOString().slice(0, 13); // YYYY-MM-DDTHH
    const jobId = `refresco:${payload.parcelId}:${hora}`;
    const cola = this.obtenerCola();

    if (await cola.getJob(jobId)) {
      return false;
    }
    await cola.add(TRABAJO_HISTORICO, payload, { ...SATELLITE_JOB_OPTIONS, jobId });
    this.logger.log(`Refresco manual encolado para la parcela ${payload.parcelId}`);
    return true;
  }

  async onModuleDestroy(): Promise<void> {
    await this.cola?.close();
    this.conexion?.disconnect();
  }

  private obtenerCola(): Queue {
    if (!this.cola) {
      this.conexion = new IORedis(this.config.getOrThrow<string>('REDIS_URL'), {
        maxRetriesPerRequest: null,
      });
      this.cola = new Queue(SATELLITE_QUEUE_NAME, { connection: this.conexion });
    }
    return this.cola;
  }
}
