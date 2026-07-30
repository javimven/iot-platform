import { Body, Controller, Get, Param, Post } from '@nestjs/common';
import { InstallationsService } from './installations.service';
import { InstallationCreateDto } from './dto/installation.dto';
import { CurrentUser } from '../../../common/decorators/current-user.decorator';
import { RequirePermission } from '../../../common/decorators/require-permission.decorator';
import { AccessTokenClaims } from '../../../common/guards/jwt-auth.guard';

/**
 * Excepción global y auditada del Admin de plataforma sobre Directorio IoT
 * ([ADR-0005](../../../../docs/ADR/0005-admin-plataforma-gestion-global-iot.md)) —
 * mismo servicio que `InstallationsController`, con el `organizationId`
 * explícito en la ruta porque el Admin de plataforma no tiene una
 * organización activa. `BACKLOG.md` #18: hasta el 2026-07-30 solo existía el
 * equivalente para gateways (`PlatformGatewaysController`) — sin esto, un
 * Admin de plataforma no podía crear la instalación inicial de un cliente
 * nuevo por ninguna vía.
 */
@Controller('platform/organizations/:organizationId/installations')
export class PlatformInstallationsController {
  constructor(private readonly installations: InstallationsService) {}

  @RequirePermission('installations.create')
  @Post()
  create(
    @CurrentUser() user: AccessTokenClaims,
    @Param('organizationId') organizationId: string,
    @Body() dto: InstallationCreateDto,
  ) {
    return this.installations.create(user, dto, organizationId);
  }

  @RequirePermission('installations.read')
  @Get()
  findAll(
    @CurrentUser() user: AccessTokenClaims,
    @Param('organizationId') organizationId: string,
  ) {
    return this.installations.findAll(user, organizationId);
  }
}
