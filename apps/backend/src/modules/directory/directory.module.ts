import { Module } from '@nestjs/common';
import { PrismaService } from '../../common/prisma/prisma.service';

import { InstallationsController } from './installations/installations.controller';
import { InstallationsService } from './installations/installations.service';
import { ZonesController } from './zones/zones.controller';
import { ZonesService } from './zones/zones.service';
import { GatewaysController } from './gateways/gateways.controller';
import { PlatformGatewaysController } from './gateways/platform-gateways.controller';
import { GatewaysService } from './gateways/gateways.service';
import { DevicesController } from './devices/devices.controller';
import { DevicesService } from './devices/devices.service';
import { SensorsController } from './sensors/sensors.controller';
import { SensorsService } from './sensors/sensors.service';
import { ChannelsController } from './channels/channels.controller';
import { ChannelsService } from './channels/channels.service';
import { ChannelTypesController } from './channels/channel-types.controller';
import { OrgChannelThresholdsController } from './channels/org-channel-thresholds.controller';

/**
 * Directorio IoT (ARCHITECTURE.md §5): instalaciones→canales. Gestión en
 * `api`; leído también por `ingestion`/`worker` para resolver topic->
 * organización/dispositivo (fuera de alcance de este módulo, Etapa 13
 * siguiente paso — Telemetría/Ingestión).
 */
@Module({
  controllers: [
    InstallationsController,
    ZonesController,
    GatewaysController,
    PlatformGatewaysController,
    DevicesController,
    SensorsController,
    ChannelsController,
    ChannelTypesController,
    OrgChannelThresholdsController,
  ],
  providers: [
    PrismaService,
    InstallationsService,
    ZonesService,
    GatewaysService,
    DevicesService,
    SensorsService,
    ChannelsService,
  ],
})
export class DirectoryModule {}
