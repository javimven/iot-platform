import { Controller, Delete, Get, HttpCode, Param, Post, Body } from '@nestjs/common';
import { SensorsService } from './sensors.service';
import { SensorCreateDto } from './dto/sensor.dto';
import { CurrentUser } from '../../../common/decorators/current-user.decorator';
import { RequirePermission } from '../../../common/decorators/require-permission.decorator';
import { AccessTokenClaims } from '../../../common/guards/jwt-auth.guard';

@Controller()
export class SensorsController {
  constructor(private readonly sensors: SensorsService) {}

  @RequirePermission('sensors.create')
  @Post('devices/:deviceId/sensors')
  create(
    @CurrentUser() user: AccessTokenClaims,
    @Param('deviceId') deviceId: string,
    @Body() dto: SensorCreateDto,
  ) {
    return this.sensors.create(user, deviceId, dto);
  }

  @RequirePermission('sensors.read')
  @Get('devices/:deviceId/sensors')
  findAllForDevice(@CurrentUser() user: AccessTokenClaims, @Param('deviceId') deviceId: string) {
    return this.sensors.findAllForDevice(user, deviceId);
  }

  @RequirePermission('sensors.read')
  @Get('sensors/:id')
  findOne(@CurrentUser() user: AccessTokenClaims, @Param('id') id: string) {
    return this.sensors.findOne(user, id);
  }

  @RequirePermission('sensors.delete')
  @Delete('sensors/:id')
  @HttpCode(204)
  async remove(@CurrentUser() user: AccessTokenClaims, @Param('id') id: string) {
    await this.sensors.softDelete(user, id);
  }
}
