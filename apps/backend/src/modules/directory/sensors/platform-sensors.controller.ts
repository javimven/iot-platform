import { Body, Controller, Delete, Get, HttpCode, Param, Post } from '@nestjs/common';
import { SensorsService } from './sensors.service';
import { SensorCreateDto } from './dto/sensor.dto';
import { CurrentUser } from '../../../common/decorators/current-user.decorator';
import { RequirePermission } from '../../../common/decorators/require-permission.decorator';
import { AccessTokenClaims } from '../../../common/guards/jwt-auth.guard';

/**
 * Excepción de plataforma sobre sensores (ADR-0005, `BACKLOG.md` #18/#20) —
 * ver `PlatformInstallationsController`. Sin `PATCH`: los sensores no tienen
 * DTO de actualización tampoco en la ruta de miembro (solo alta y baja).
 */
@Controller('platform/organizations/:organizationId/devices/:deviceId/sensors')
export class PlatformSensorsController {
  constructor(private readonly sensors: SensorsService) {}

  @RequirePermission('sensors.create')
  @Post()
  create(
    @CurrentUser() user: AccessTokenClaims,
    @Param('organizationId') organizationId: string,
    @Param('deviceId') deviceId: string,
    @Body() dto: SensorCreateDto,
  ) {
    return this.sensors.create(user, deviceId, dto, organizationId);
  }

  @RequirePermission('sensors.read')
  @Get()
  findAll(
    @CurrentUser() user: AccessTokenClaims,
    @Param('organizationId') organizationId: string,
    @Param('deviceId') deviceId: string,
  ) {
    return this.sensors.findAllForDevice(user, deviceId, organizationId);
  }

  @RequirePermission('sensors.read')
  @Get(':id')
  findOne(
    @CurrentUser() user: AccessTokenClaims,
    @Param('organizationId') organizationId: string,
    @Param('id') id: string,
  ) {
    return this.sensors.findOne(user, id, organizationId);
  }

  @RequirePermission('sensors.delete')
  @Delete(':id')
  @HttpCode(204)
  async remove(
    @CurrentUser() user: AccessTokenClaims,
    @Param('organizationId') organizationId: string,
    @Param('id') id: string,
  ) {
    await this.sensors.softDelete(user, id, organizationId);
  }
}
