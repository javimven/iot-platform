import { BadRequestException, Controller, Get, Param, Query } from '@nestjs/common';
import { ReadingsService, Granularity } from './readings.service';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { RequirePermission } from '../../common/decorators/require-permission.decorator';
import { AccessTokenClaims } from '../../common/guards/jwt-auth.guard';

const VALID_GRANULARITIES: Granularity[] = ['raw', 'hourly', 'daily'];

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

  @RequirePermission('telemetry.read_history')
  @Get('channels/:channelId/readings')
  getHistory(
    @CurrentUser() user: AccessTokenClaims,
    @Param('channelId') channelId: string,
    @Query('from') from: string,
    @Query('to') to: string,
    @Query('granularity') granularity: string = 'raw',
  ) {
    if (!VALID_GRANULARITIES.includes(granularity as Granularity)) {
      throw new BadRequestException(`granularity must be one of ${VALID_GRANULARITIES.join(', ')}`);
    }
    const fromDate = new Date(from);
    const toDate = new Date(to);
    if (Number.isNaN(fromDate.getTime()) || Number.isNaN(toDate.getTime())) {
      throw new BadRequestException('from/to must be valid ISO-8601 dates');
    }
    return this.readings.getHistory(user, channelId, fromDate, toDate, granularity as Granularity);
  }
}
