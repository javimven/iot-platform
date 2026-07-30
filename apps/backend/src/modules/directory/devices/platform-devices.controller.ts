import { Body, Controller, Get, Param, Post } from '@nestjs/common';
import { DevicesService } from './devices.service';
import { DeviceCreateDto } from './dto/device.dto';
import { CurrentUser } from '../../../common/decorators/current-user.decorator';
import { RequirePermission } from '../../../common/decorators/require-permission.decorator';
import { AccessTokenClaims } from '../../../common/guards/jwt-auth.guard';

/** Excepción de plataforma sobre dispositivos (ADR-0005, `BACKLOG.md` #18) — ver `PlatformInstallationsController`. */
@Controller('platform/organizations/:organizationId/gateways/:gatewayId/devices')
export class PlatformDevicesController {
  constructor(private readonly devices: DevicesService) {}

  @RequirePermission('devices.create')
  @Post()
  create(
    @CurrentUser() user: AccessTokenClaims,
    @Param('organizationId') organizationId: string,
    @Param('gatewayId') gatewayId: string,
    @Body() dto: DeviceCreateDto,
  ) {
    return this.devices.create(user, gatewayId, dto, organizationId);
  }

  @RequirePermission('devices.read')
  @Get()
  findAll(
    @CurrentUser() user: AccessTokenClaims,
    @Param('organizationId') organizationId: string,
    @Param('gatewayId') gatewayId: string,
  ) {
    return this.devices.findAllForGateway(user, gatewayId, organizationId);
  }
}
