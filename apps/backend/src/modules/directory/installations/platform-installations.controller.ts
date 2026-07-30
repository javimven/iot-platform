import { Body, Controller, Delete, Get, HttpCode, Param, Patch, Post } from '@nestjs/common';
import { InstallationsService } from './installations.service';
import { InstallationCreateDto, InstallationUpdateDto } from './dto/installation.dto';
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
 * nuevo por ninguna vía. Operaciones por ID (`BACKLOG.md` #20, ADR-0005
 * ya las decidía en su alcance original) añadidas el mismo día que se
 * mecanizó crear/listar — el propio servicio ya aceptaba
 * `explicitOrganizationId` en `findOne`/`update`/`softDelete`, solo faltaban
 * las rutas.
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
  findAll(@CurrentUser() user: AccessTokenClaims, @Param('organizationId') organizationId: string) {
    return this.installations.findAll(user, organizationId);
  }

  @RequirePermission('installations.read')
  @Get(':id')
  findOne(
    @CurrentUser() user: AccessTokenClaims,
    @Param('organizationId') organizationId: string,
    @Param('id') id: string,
  ) {
    return this.installations.findOne(user, id, organizationId);
  }

  @RequirePermission('installations.update')
  @Patch(':id')
  update(
    @CurrentUser() user: AccessTokenClaims,
    @Param('organizationId') organizationId: string,
    @Param('id') id: string,
    @Body() dto: InstallationUpdateDto,
  ) {
    return this.installations.update(user, id, dto, organizationId);
  }

  @RequirePermission('installations.delete')
  @Delete(':id')
  @HttpCode(204)
  async remove(
    @CurrentUser() user: AccessTokenClaims,
    @Param('organizationId') organizationId: string,
    @Param('id') id: string,
  ) {
    await this.installations.softDelete(user, id, organizationId);
  }
}
