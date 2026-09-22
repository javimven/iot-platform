import { Body, Controller, Delete, Get, HttpCode, Param, Patch, Post } from '@nestjs/common';
import { ParcelsService } from './parcels.service';
import { ParcelCreateDto, ParcelUpdateDto } from './dto/parcel.dto';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { RequireFeature } from '../../common/decorators/require-feature.decorator';
import { RequirePermission } from '../../common/decorators/require-permission.decorator';
import { AccessTokenClaims } from '../../common/guards/jwt-auth.guard';

/**
 * Parcelas (BACKLOG.md #36). Mismas rutas anidadas que las zonas
 * (`/installations/{id}/zones`) para no inventar un patron nuevo.
 *
 * Todo el controlador exige **Satelite o Campañas**: la parcela es la unidad
 * de los dos modulos (el NDVI se calcula sobre su contorno, y una campaña
 * dice que se cultiva en cada una). Hasta el 2026-09-22 exigia solo
 * `satellite_imagery`; con Campañas, una organizacion sin satelite tiene que
 * poder dibujar sus parcelas igual. Quien no tiene ninguno de los dos no
 * puede crearlas ni listarlas, tampoco llamando a la API directamente.
 */
@RequireFeature('satellite_imagery', 'campaigns')
@Controller()
export class ParcelsController {
  constructor(private readonly parcels: ParcelsService) {}

  @RequirePermission('parcels.create')
  @Post('installations/:installationId/parcels')
  create(
    @CurrentUser() user: AccessTokenClaims,
    @Param('installationId') installationId: string,
    @Body() dto: ParcelCreateDto,
  ) {
    return this.parcels.create(user, installationId, dto);
  }

  @RequirePermission('parcels.read')
  @Get('installations/:installationId/parcels')
  findAllForInstallation(
    @CurrentUser() user: AccessTokenClaims,
    @Param('installationId') installationId: string,
  ) {
    return this.parcels.findAllForInstallation(user, installationId);
  }

  @RequirePermission('parcels.read')
  @Get('parcels/:id')
  findOne(@CurrentUser() user: AccessTokenClaims, @Param('id') id: string) {
    return this.parcels.findOne(user, id);
  }

  @RequirePermission('parcels.update')
  @Patch('parcels/:id')
  update(
    @CurrentUser() user: AccessTokenClaims,
    @Param('id') id: string,
    @Body() dto: ParcelUpdateDto,
  ) {
    return this.parcels.update(user, id, dto);
  }

  @RequirePermission('parcels.delete')
  @Delete('parcels/:id')
  @HttpCode(204)
  async remove(@CurrentUser() user: AccessTokenClaims, @Param('id') id: string) {
    await this.parcels.softDelete(user, id);
  }
}
