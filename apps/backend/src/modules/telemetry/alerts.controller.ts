import { Controller, Get, Param, Post, Query } from '@nestjs/common';
import { AlertStatus } from '@prisma/client';
import { AlertsService } from './alerts.service';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { RequirePermission } from '../../common/decorators/require-permission.decorator';
import { AccessTokenClaims } from '../../common/guards/jwt-auth.guard';

@Controller('alerts')
export class AlertsController {
  constructor(private readonly alerts: AlertsService) {}

  @RequirePermission('alerts.read')
  @Get()
  findAll(@CurrentUser() user: AccessTokenClaims, @Query('status') status?: AlertStatus) {
    return this.alerts.findAll(user, status);
  }

  @RequirePermission('alerts.acknowledge')
  @Post(':id/acknowledge')
  acknowledge(@CurrentUser() user: AccessTokenClaims, @Param('id') id: string) {
    return this.alerts.acknowledge(user, id);
  }

  @RequirePermission('alerts.resolve')
  @Post(':id/resolve')
  resolve(@CurrentUser() user: AccessTokenClaims, @Param('id') id: string) {
    return this.alerts.resolve(user, id);
  }
}
