import { Module } from '@nestjs/common';
import { PrismaService } from '../../common/prisma/prisma.service';
import { ReadingsController } from './readings.controller';
import { PlatformReadingsController } from './platform-readings.controller';
import { ReadingsService } from './readings.service';
import { AlertsController } from './alerts.controller';
import { AlertsService } from './alerts.service';

/** API de lectura de telemetría y gestión de alertas (ARCHITECTURE.md §5, proceso `api`). */
@Module({
  controllers: [ReadingsController, PlatformReadingsController, AlertsController],
  providers: [PrismaService, ReadingsService, AlertsService],
})
export class TelemetryModule {}
