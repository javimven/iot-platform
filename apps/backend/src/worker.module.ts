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
import { StorageService } from './common/storage/storage.service';
import { ParcelsRepository } from './modules/parcels/parcels.repository';
import { SATELLITE_PROVIDER } from './modules/satellite/providers/satellite-provider.interface';
import { CopernicusProvider } from './modules/satellite/providers/copernicus/copernicus.provider';
import { SatelliteProcessingService } from './modules/satellite/processing/satellite-processing.service';
import { SatelliteSchedulerService } from './modules/satellite/processing/satellite-scheduler.service';
import { SatelliteWorkerService } from './modules/worker-jobs/satellite-worker.service';

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
    // Satelite (BACKLOG.md #36). El proveedor se resuelve por token: el dia
    // que haya dos (Planet, Airbus), se elige aqui y nadie mas se entera.
    StorageService,
    ParcelsRepository,
    { provide: SATELLITE_PROVIDER, useClass: CopernicusProvider },
    SatelliteProcessingService,
    SatelliteSchedulerService,
    SatelliteWorkerService,
  ],
})
export class WorkerModule {}
