import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  Query,
} from '@nestjs/common';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { RequireFeature } from '../../common/decorators/require-feature.decorator';
import { RequirePermission } from '../../common/decorators/require-permission.decorator';
import { AccessTokenClaims } from '../../common/guards/jwt-auth.guard';
import { CampaignsService } from './campaigns.service';
import { CropUnitsService } from './crop-units.service';
import {
  CampaignCloseDto,
  CampaignCreateDto,
  CampaignListQueryDto,
  CampaignReopenDto,
  CampaignUpdateDto,
  CampaignUpgradeDto,
} from './dto/campaign.dto';
import { CropUnitCreateDto, CropUnitUpdateDto } from './dto/crop-unit.dto';

/**
 * Campañas y unidades de cultivo (BACKLOG.md #60). Todo exige la función
 * `campaigns`: ocultar la pestaña en la app no basta, la API es pública.
 *
 * El alta cuelga de la finca (`/installations/{id}/campaigns`), como las
 * parcelas y las zonas; el resto, de la propia campaña. Los identificadores
 * se validan como UUID: uno mal formado es un 400, no un error de la base.
 */
@RequireFeature('campaigns')
@Controller()
export class CampaignsController {
  constructor(
    private readonly campaigns: CampaignsService,
    private readonly cropUnits: CropUnitsService,
  ) {}

  @RequirePermission('campaigns.read')
  @Get('campaigns')
  list(@CurrentUser() user: AccessTokenClaims, @Query() filtros: CampaignListQueryDto) {
    return this.campaigns.list(user, filtros);
  }

  @RequirePermission('campaigns.create')
  @Post('installations/:installationId/campaigns')
  create(
    @CurrentUser() user: AccessTokenClaims,
    @Param('installationId', ParseUUIDPipe) installationId: string,
    @Body() dto: CampaignCreateDto,
  ) {
    return this.campaigns.create(user, installationId, dto);
  }

  @RequirePermission('campaigns.read')
  @Get('campaigns/:id')
  findOne(@CurrentUser() user: AccessTokenClaims, @Param('id', ParseUUIDPipe) id: string) {
    return this.campaigns.findOne(user, id);
  }

  @RequirePermission('campaigns.update')
  @Patch('campaigns/:id')
  update(
    @CurrentUser() user: AccessTokenClaims,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: CampaignUpdateDto,
  ) {
    return this.campaigns.update(user, id, dto);
  }

  @RequirePermission('campaigns.update')
  @Post('campaigns/:id/upgrade')
  @HttpCode(200)
  upgrade(
    @CurrentUser() user: AccessTokenClaims,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: CampaignUpgradeDto,
  ) {
    return this.campaigns.upgrade(user, id, dto);
  }

  @RequirePermission('campaigns.close')
  @Post('campaigns/:id/close')
  @HttpCode(200)
  close(
    @CurrentUser() user: AccessTokenClaims,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: CampaignCloseDto,
  ) {
    return this.campaigns.close(user, id, dto);
  }

  @RequirePermission('campaigns.close')
  @Post('campaigns/:id/reopen')
  @HttpCode(200)
  reopen(
    @CurrentUser() user: AccessTokenClaims,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: CampaignReopenDto,
  ) {
    return this.campaigns.reopen(user, id, dto);
  }

  @RequirePermission('campaigns.delete')
  @Delete('campaigns/:id')
  @HttpCode(204)
  async remove(@CurrentUser() user: AccessTokenClaims, @Param('id', ParseUUIDPipe) id: string) {
    await this.campaigns.softDelete(user, id);
  }

  @RequirePermission('campaigns.update')
  @Post('campaigns/:id/crop-units')
  addCropUnit(
    @CurrentUser() user: AccessTokenClaims,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: CropUnitCreateDto,
  ) {
    return this.cropUnits.add(user, id, dto);
  }

  @RequirePermission('campaigns.update')
  @Patch('campaigns/:id/crop-units/:unitId')
  updateCropUnit(
    @CurrentUser() user: AccessTokenClaims,
    @Param('id', ParseUUIDPipe) id: string,
    @Param('unitId', ParseUUIDPipe) unitId: string,
    @Body() dto: CropUnitUpdateDto,
  ) {
    return this.cropUnits.update(user, id, unitId, dto);
  }

  @RequirePermission('campaigns.update')
  @Delete('campaigns/:id/crop-units/:unitId')
  @HttpCode(204)
  async removeCropUnit(
    @CurrentUser() user: AccessTokenClaims,
    @Param('id', ParseUUIDPipe) id: string,
    @Param('unitId', ParseUUIDPipe) unitId: string,
  ) {
    await this.cropUnits.remove(user, id, unitId);
  }
}
