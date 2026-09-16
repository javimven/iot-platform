import { Controller, Get, Param, Query } from '@nestjs/common';
import { ReadingsService } from './readings.service';
import { parseHistoryQuery } from './readings.controller';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { RequirePermission } from '../../common/decorators/require-permission.decorator';
import { AccessTokenClaims } from '../../common/guards/jwt-auth.guard';

/**
 * Lectura de telemetría de cualquier organización por el Admin de plataforma
 * ([ADR-0007](../../../../docs/ADR/0007-admin-plataforma-lectura-telemetria.md)):
 * solo lectura (últimas lecturas de una estación e histórico de un canal),
 * con el `organizationId` explícito en la ruta como en la excepción de
 * Directorio IoT (ADR-0005). Mismo servicio que `ReadingsController`.
 */
@Controller('platform/organizations/:organizationId')
export class PlatformReadingsController {
  constructor(private readonly readings: ReadingsService) {}

  @RequirePermission('platform.telemetry.read')
  @Get('gateways/:gatewayId/latest-readings')
  getLatestForGateway(
    @CurrentUser() user: AccessTokenClaims,
    @Param('organizationId') organizationId: string,
    @Param('gatewayId') gatewayId: string,
  ) {
    return this.readings.getLatestForGateway(user, gatewayId, organizationId);
  }

  @RequirePermission('platform.telemetry.read')
  @Get('channels/:channelId/readings')
  getHistory(
    @CurrentUser() user: AccessTokenClaims,
    @Param('organizationId') organizationId: string,
    @Param('channelId') channelId: string,
    @Query('from') from: string,
    @Query('to') to: string,
    @Query('granularity') granularity: string = 'raw',
  ) {
    const query = parseHistoryQuery(from, to, granularity);
    return this.readings.getHistory(
      user,
      channelId,
      query.from,
      query.to,
      query.granularity,
      organizationId,
    );
  }
}
