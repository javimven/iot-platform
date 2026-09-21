import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { HealthController } from './common/health/health.controller';
import { PrismaService } from './common/prisma/prisma.service';
import { MailerService } from './common/mailer/mailer.service';
import { TelemetryProcessingService } from './modules/telemetry/telemetry-processing.service';
import { TelemetryWorkerService } from './modules/worker-jobs/telemetry-worker.service';
import { NoSensorDataService } from './modules/worker-jobs/no-sensor-data.service';
import { OfflineDetectionService } from './modules/worker-jobs/offline-detection.service';
import { TelemetryPartitionsService } from './modules/worker-jobs/telemetry-partitions.service';
import { NotificationDispatchService } from './modules/notifications/notification-dispatch.service';

/**
 * Root module del proceso `worker` (ARCHITECTURE.md §5): consumidor de
 * BullMQ + sondeos periódicos (offline, notificaciones, particiones de
 * telemetría). Expone solo
 * `/health`.
 */
@Module({
  imports: [ConfigModule.forRoot({ isGlobal: true })],
  controllers: [HealthController],
  providers: [
    PrismaService,
    MailerService,
    TelemetryProcessingService,
    TelemetryWorkerService,
    OfflineDetectionService,
    NoSensorDataService,
    TelemetryPartitionsService,
    NotificationDispatchService,
  ],
})
export class WorkerModule {}
