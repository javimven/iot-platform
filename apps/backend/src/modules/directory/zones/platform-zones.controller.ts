import { Body, Controller, Get, Param, Post } from '@nestjs/common';
import { ZonesService } from './zones.service';
import { ZoneCreateDto } from './dto/zone.dto';
import { CurrentUser } from '../../../common/decorators/current-user.decorator';
import { RequirePermission } from '../../../common/decorators/require-permission.decorator';
import { AccessTokenClaims } from '../../../common/guards/jwt-auth.guard';

/** Excepción de plataforma sobre zonas (ADR-0005, `BACKLOG.md` #18) — ver `PlatformInstallationsController`. */
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
}
