import { Body, Controller, Delete, Get, HttpCode, Param, Patch, Post } from '@nestjs/common';
import { GatewaysService } from './gateways.service';
import { GatewayCreateDto, GatewayUpdateDto } from './dto/gateway.dto';
import { CurrentUser } from '../../../common/decorators/current-user.decorator';
import { RequirePermission } from '../../../common/decorators/require-permission.decorator';
import { AccessTokenClaims } from '../../../common/guards/jwt-auth.guard';

/**
 * Excepción global y auditada del Admin de plataforma sobre Directorio IoT
 * ([ADR-0005](../../../../docs/ADR/0005-admin-plataforma-gestion-global-iot.md),
 * API_DESIGN.md §2) — mismo servicio que `GatewaysController`, con el
 * `organizationId` explícito en la ruta porque el Admin de plataforma no
 * tiene una organización activa. Representativo del resto de recursos de
 * Directorio IoT (instalaciones→canales), que se mecanizan igual
 * (OPENAPI.yaml, nota de la sección `platform`). Operaciones por ID
 * (`BACKLOG.md` #20) incluidas desde el principio — ADR-0005 ya decidía
 * "actualización, baja, rotación de credencial" como parte del alcance.
 */
@Controller('platform/organizations/:organizationId/gateways')
export class PlatformGatewaysController {
  constructor(private readonly gateways: GatewaysService) {}

  @RequirePermission('gateways.create')
  @Post()
  create(
    @CurrentUser() user: AccessTokenClaims,
    @Param('organizationId') organizationId: string,
    @Body() dto: GatewayCreateDto,
  ) {
    return this.gateways.create(user, dto, organizationId);
  }

  @RequirePermission('gateways.read')
  @Get()
  findAll(@CurrentUser() user: AccessTokenClaims, @Param('organizationId') organizationId: string) {
    return this.gateways.findAll(user, organizationId);
  }

  @RequirePermission('gateways.read')
  @Get(':id')
  findOne(
    @CurrentUser() user: AccessTokenClaims,
    @Param('organizationId') organizationId: string,
    @Param('id') id: string,
  ) {
    return this.gateways.findOne(user, id, organizationId);
  }

  @RequirePermission('gateways.update')
  @Patch(':id')
  update(
    @CurrentUser() user: AccessTokenClaims,
    @Param('organizationId') organizationId: string,
    @Param('id') id: string,
    @Body() dto: GatewayUpdateDto,
  ) {
    return this.gateways.update(user, id, dto, organizationId);
  }

  @RequirePermission('gateways.disable')
  @Delete(':id')
  @HttpCode(204)
  async remove(
    @CurrentUser() user: AccessTokenClaims,
    @Param('organizationId') organizationId: string,
    @Param('id') id: string,
  ) {
    await this.gateways.disable(user, id, organizationId);
  }

  @RequirePermission('gateways.rotate_credential')
  @Post(':id/rotate-credential')
  rotateCredential(
    @CurrentUser() user: AccessTokenClaims,
    @Param('organizationId') organizationId: string,
    @Param('id') id: string,
  ) {
    return this.gateways.rotateCredential(user, id, organizationId);
  }
}
