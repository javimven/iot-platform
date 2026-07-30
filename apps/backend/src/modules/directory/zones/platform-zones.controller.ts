import { Body, Controller, Delete, Get, HttpCode, Param, Patch, Post } from '@nestjs/common';
import { ZonesService } from './zones.service';
import { ZoneCreateDto, ZoneUpdateDto } from './dto/zone.dto';
import { CurrentUser } from '../../../common/decorators/current-user.decorator';
import { RequirePermission } from '../../../common/decorators/require-permission.decorator';
import { AccessTokenClaims } from '../../../common/guards/jwt-auth.guard';

/**
 * Excepción de plataforma sobre zonas (ADR-0005, `BACKLOG.md` #18/#20) — ver
 * `PlatformInstallationsController`. `installationId` no hace falta para las
 * operaciones por ID (`id` de zona ya es único), pero se mantiene en la ruta
 * por consistencia con la colección.
 */
@Controller('platform/organizations/:organizationId/installations/:installationId/zones')
export class PlatformZonesController {
  constructor(private readonly zones: ZonesService) {}

  @RequirePermission('zones.create')
  @Post()
  create(
    @CurrentUser() user: AccessTokenClaims,
    @Param('organizationId') organizationId: string,
    @Param('installationId') installationId: string,
    @Body() dto: ZoneCreateDto,
  ) {
    return this.zones.create(user, installationId, dto, organizationId);
  }

  @RequirePermission('zones.read')
  @Get()
  findAll(
    @CurrentUser() user: AccessTokenClaims,
    @Param('organizationId') organizationId: string,
    @Param('installationId') installationId: string,
  ) {
    return this.zones.findAllForInstallation(user, installationId, organizationId);
  }

  @RequirePermission('zones.read')
  @Get(':id')
  findOne(
    @CurrentUser() user: AccessTokenClaims,
    @Param('organizationId') organizationId: string,
    @Param('id') id: string,
  ) {
    return this.zones.findOne(user, id, organizationId);
  }

  @RequirePermission('zones.update')
  @Patch(':id')
  update(
    @CurrentUser() user: AccessTokenClaims,
    @Param('organizationId') organizationId: string,
    @Param('id') id: string,
    @Body() dto: ZoneUpdateDto,
  ) {
    return this.zones.update(user, id, dto, organizationId);
  }

  @RequirePermission('zones.delete')
  @Delete(':id')
  @HttpCode(204)
  async remove(
    @CurrentUser() user: AccessTokenClaims,
    @Param('organizationId') organizationId: string,
    @Param('id') id: string,
  ) {
    await this.zones.softDelete(user, id, organizationId);
  }
}
