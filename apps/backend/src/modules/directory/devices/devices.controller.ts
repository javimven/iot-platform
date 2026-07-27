import { Body, Controller, Delete, Get, HttpCode, Param, Patch, Post } from '@nestjs/common';
import { DevicesService } from './devices.service';
import { DeviceCreateDto, DeviceUpdateDto } from './dto/device.dto';
import { CurrentUser } from '../../../common/decorators/current-user.decorator';
import { RequirePermission } from '../../../common/decorators/require-permission.decorator';
import { AccessTokenClaims } from '../../../common/guards/jwt-auth.guard';

@Controller()
export class DevicesController {
  constructor(private readonly devices: DevicesService) {}

  @RequirePermission('devices.create')
  @Post('gateways/:gatewayId/devices')
  create(
    @CurrentUser() user: AccessTokenClaims,
    @Param('gatewayId') gatewayId: string,
    @Body() dto: DeviceCreateDto,
  ) {
    return this.devices.create(user, gatewayId, dto);
  }

  @RequirePermission('devices.read')
  @Get('gateways/:gatewayId/devices')
  findAllForGateway(@CurrentUser() user: AccessTokenClaims, @Param('gatewayId') gatewayId: string) {
    return this.devices.findAllForGateway(user, gatewayId);
  }

  @RequirePermission('devices.read')
  @Get('devices/:id')
  findOne(@CurrentUser() user: AccessTokenClaims, @Param('id') id: string) {
    return this.devices.findOne(user, id);
  }

  @RequirePermission('devices.update')
  @Patch('devices/:id')
  update(
    @CurrentUser() user: AccessTokenClaims,
    @Param('id') id: string,
    @Body() dto: DeviceUpdateDto,
  ) {
    return this.devices.update(user, id, dto);
  }

  @RequirePermission('devices.disable')
  @Delete('devices/:id')
  @HttpCode(204)
  async remove(@CurrentUser() user: AccessTokenClaims, @Param('id') id: string) {
    await this.devices.disable(user, id);
  }
}
