import { Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Worker } from 'bullmq';
import IORedis from 'ioredis';
import { TelemetryProcessingService } from '../telemetry/telemetry-processing.service';
import { TELEMETRY_QUEUE_NAME, TelemetryJobPayload } from '../../common/queues/telemetry-queue';

/**
 * Consumidor BullMQ del proceso `worker` (ARCHITECTURE.md §5, §8). La
 * política de reintentos/backoff vive en el productor (`TELEMETRY_JOB_OPTIONS`,
 * `ingestion`) — aquí solo se define qué hace un job al ejecutarse y qué pasa
 * si agota reintentos (dead-letter, OBSERVABILITY.md §7: BullMQ mueve el job
 * a `failed` automáticamente, sin necesidad de código adicional aquí).
 */
@Injectable()
export class TelemetryWorkerService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(TelemetryWorkerService.name);
  private worker?: Worker<TelemetryJobPayload>;

  constructor(
    private readonly processing: TelemetryProcessingService,
    private readonly config: ConfigService,
  ) {}

  onModuleInit(): void {
    const connection = new IORedis(this.config.getOrThrow<string>('REDIS_URL'), {
      maxRetriesPerRequest: null, // requerido por BullMQ
    });

    this.worker = new Worker<TelemetryJobPayload>(
      TELEMETRY_QUEUE_NAME,
      async (job) => {
        await this.processing.processMessage(job.data);
      },
      { connection },
    );

    this.worker.on('failed', (job, error) => {
      this.logger.error(
        `[${job?.data.correlationId}] telemetry job failed (attempt ${job?.attemptsMade}): ${error.message}`,
      );
    });
  }

  async onModuleDestroy(): Promise<void> {
    await this.worker?.close();
  }
}
