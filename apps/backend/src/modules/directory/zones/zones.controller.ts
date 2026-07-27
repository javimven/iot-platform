import { Body, Controller, Delete, Get, HttpCode, Param, Patch, Post } from '@nestjs/common';
import { ZonesService } from './zones.service';
import { ZoneCreateDto, ZoneUpdateDto } from './dto/zone.dto';
import { CurrentUser } from '../../../common/decorators/current-user.decorator';
import { RequirePermission } from '../../../common/decorators/require-permission.decorator';
import { AccessTokenClaims } from '../../../common/guards/jwt-auth.guard';

@Controller()
export class ZonesController {
  constructor(private readonly zones: ZonesService) {}

  @RequirePermission('zones.create')
  @Post('installations/:installationId/zones')
  create(
    @CurrentUser() user: AccessTokenClaims,
    @Param('installationId') installationId: string,
    @Body() dto: ZoneCreateDto,
  ) {
    return this.zones.create(user, installationId, dto);
  }

  @RequirePermission('zones.read')
  @Get('installations/:installationId/zones')
  findAllForInstallation(
    @CurrentUser() user: AccessTokenClaims,
    @Param('installationId') installationId: string,
  ) {
    return this.zones.findAllForInstallation(user, installationId);
  }

  @RequirePermission('zones.read')
  @Get('zones/:id')
  findOne(@CurrentUser() user: AccessTokenClaims, @Param('id') id: string) {
    return this.zones.findOne(user, id);
  }

  @RequirePermission('zones.update')
  @Patch('zones/:id')
  update(
    @CurrentUser() user: AccessTokenClaims,
    @Param('id') id: string,
    @Body() dto: ZoneUpdateDto,
  ) {
    return this.zones.update(user, id, dto);
  }

  @RequirePermission('zones.delete')
  @Delete('zones/:id')
  @HttpCode(204)
  async remove(@CurrentUser() user: AccessTokenClaims, @Param('id') id: string) {
    await this.zones.softDelete(user, id);
  }
}
