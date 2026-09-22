import { BadRequestException, Controller, Get, Param, Post, Query } from '@nestjs/common';
import { SatelliteService } from './satellite.service';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { RequireFeature } from '../../common/decorators/require-feature.decorator';
import { RequirePermission } from '../../common/decorators/require-permission.decorator';
import { AccessTokenClaims } from '../../common/guards/jwt-auth.guard';

/**
 * Consulta de lo que el worker ha ido calculando (BACKLOG.md #36). Rutas
 * colgando de la parcela, que es la unidad del módulo.
 *
 * Toda la clase exige la función `satellite_imagery` contratada: el módulo se
 * cobra aparte y la API es pública, así que esconderlo en la app no basta.
 */
@RequireFeature('satellite_imagery')
@Controller('parcels/:parcelId/satellite')
export class SatelliteController {
  constructor(private readonly satellite: SatelliteService) {}

  @RequirePermission('satellite.read')
  @Get('latest')
  latest(@CurrentUser() user: AccessTokenClaims, @Param('parcelId') parcelId: string) {
    return this.satellite.ultima(user, parcelId);
  }

  @RequirePermission('satellite.read')
  @Get('observations')
  observations(
    @CurrentUser() user: AccessTokenClaims,
    @Param('parcelId') parcelId: string,
    @Query('from') from?: string,
    @Query('to') to?: string,
    @Query('includeRejected') includeRejected?: string,
  ) {
    return this.satellite.observaciones(user, parcelId, {
      from: this.fecha(from, 'from'),
      to: this.fecha(to, 'to'),
      incluirDescartadas: includeRejected === 'true',
    });
  }

  @RequirePermission('satellite.read')
  @Get('timeseries')
  timeseries(
    @CurrentUser() user: AccessTokenClaims,
    @Param('parcelId') parcelId: string,
    @Query('from') from?: string,
    @Query('to') to?: string,
  ) {
    return this.satellite.serie(user, parcelId, {
      from: this.fecha(from, 'from'),
      to: this.fecha(to, 'to'),
    });
  }

  @RequirePermission('satellite.read')
  @Get('observations/:observationId')
  observation(
    @CurrentUser() user: AccessTokenClaims,
    @Param('parcelId') parcelId: string,
    @Param('observationId') observationId: string,
  ) {
    return this.satellite.observacion(user, parcelId, observationId);
  }

  @RequirePermission('satellite.read')
  @Get('observations/:observationId/assets')
  assets(
    @CurrentUser() user: AccessTokenClaims,
    @Param('parcelId') parcelId: string,
    @Param('observationId') observationId: string,
  ) {
    return this.satellite.assets(user, parcelId, observationId);
  }

  /** Enlace firmado y con caducidad: el bucket nunca se abre al cliente. */
  @RequirePermission('satellite.read')
  @Get('observations/:observationId/assets/:assetId/url')
  assetUrl(
    @CurrentUser() user: AccessTokenClaims,
    @Param('parcelId') parcelId: string,
    @Param('observationId') observationId: string,
    @Param('assetId') assetId: string,
  ) {
    return this.satellite.urlDeAsset(user, parcelId, observationId, assetId);
  }

  /**
   * Fuerza una búsqueda. Permiso propio (`satellite.refresh`) porque gasta
   * cuota de Copernicus: no lo tiene quien solo consulta. Responde 429 si esa
   * parcela ya se actualizó hace menos de una hora.
   */
  @RequirePermission('satellite.refresh')
  @Post('refresh')
  refresh(@CurrentUser() user: AccessTokenClaims, @Param('parcelId') parcelId: string) {
    return this.satellite.refrescar(user, parcelId);
  }

  private fecha(valor: string | undefined, campo: string): Date | undefined {
    if (!valor) {
      return undefined;
    }
    const fecha = new Date(valor);
    if (Number.isNaN(fecha.getTime())) {
      throw new BadRequestException(`El parámetro ${campo} no es una fecha válida (ISO-8601).`);
    }
    return fecha;
  }
}
