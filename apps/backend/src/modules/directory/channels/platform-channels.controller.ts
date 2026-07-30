import { Controller, Get, Param } from '@nestjs/common';
import { ChannelsService } from './channels.service';
import { RequirePermission } from '../../../common/decorators/require-permission.decorator';
import { CurrentUser } from '../../../common/decorators/current-user.decorator';
import { AccessTokenClaims } from '../../../common/guards/jwt-auth.guard';

/**
 * Excepción de plataforma sobre canales (ADR-0005, `BACKLOG.md` #18) — ver
 * `PlatformInstallationsController`. Solo lectura: los canales se crean
 * automáticamente al ingerir el primer mensaje MQTT, nunca por `POST`
 * manual (ni siquiera en la ruta de miembro, `ChannelsController`).
 */
@Controller('platform/organizations/:organizationId/sensors/:sensorId/channels')
export class PlatformChannelsController {
  constructor(private readonly channels: ChannelsService) {}

  @RequirePermission('channels.read')
  @Get()
  findAll(
    @CurrentUser() user: AccessTokenClaims,
    @Param('organizationId') organizationId: string,
    @Param('sensorId') sensorId: string,
  ) {
    return this.channels.findAllForSensor(user, sensorId, organizationId);
  }
}
