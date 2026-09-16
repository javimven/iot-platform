import { BadRequestException, Controller, Get, Param, Query } from '@nestjs/common';
import { ReadingsService, Granularity } from './readings.service';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { RequirePermission } from '../../common/decorators/require-permission.decorator';
import { AccessTokenClaims } from '../../common/guards/jwt-auth.guard';

const VALID_GRANULARITIES: Granularity[] = ['raw', 'hourly', 'daily'];

/** Validación de `GET .../readings`, compartida con `PlatformReadingsController`. */
export function parseHistoryQuery(
  from: string,
  to: string,
  granularity: string,
): { from: Date; to: Date; granularity: Granularity } {
  if (!VALID_GRANULARITIES.includes(granularity as Granularity)) {
    throw new BadRequestException(`granularity must be one of ${VALID_GRANULARITIES.join(', ')}`);
  }
  const fromDate = new Date(from);
  const toDate = new Date(to);
  if (Number.isNaN(fromDate.getTime()) || Number.isNaN(toDate.getTime())) {
    throw new BadRequestException('from/to must be valid ISO-8601 dates');
  }
  return { from: fromDate, to: toDate, granularity: granularity as Granularity };
}

@Controller()
export class ReadingsController {
  constructor(private readonly readings: ReadingsService) {}

  @RequirePermission('telemetry.read_latest')
  @Get('channels/:channelId/latest-reading')
  getLatest(@CurrentUser() user: AccessTokenClaims, @Param('channelId') channelId: string) {
    return this.readings.getLatest(user, channelId);
  }

  @RequirePermission('telemetry.read_latest')
  @Get('installations/:installationId/latest-readings')
  getLatestForInstallation(
    @CurrentUser() user: AccessTokenClaims,
    @Param('installationId') installationId: string,
  ) {
    return this.readings.getLatestForInstallation(user, installationId);
  }

  @RequirePermission('telemetry.read_latest')
  @Get('gateways/:gatewayId/latest-readings')
  getLatestForGateway(
    @CurrentUser() user: AccessTokenClaims,
    @Param('gatewayId') gatewayId: string,
  ) {
    return this.readings.getLatestForGateway(user, gatewayId);
  }

  @RequirePermission('telemetry.read_history')
  @Get('channels/:channelId/readings')
  getHistory(
    @CurrentUser() user: AccessTokenClaims,
    @Param('channelId') channelId: string,
    @Query('from') from: string,
    @Query('to') to: string,
    @Query('granularity') granularity: string = 'raw',
  ) {
    const query = parseHistoryQuery(from, to, granularity);
    return this.readings.getHistory(user, channelId, query.from, query.to, query.granularity);
  }
}
