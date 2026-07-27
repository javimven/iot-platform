import { Body, Controller, Get, HttpCode, Param, ParseArrayPipe, Put } from '@nestjs/common';
import { PlatformFeaturesService } from './platform-features.service';
import { FeatureUpdateItem } from './dto/organization-feature-update.dto';
import { CurrentUser } from '../../../common/decorators/current-user.decorator';
import { RequirePermission } from '../../../common/decorators/require-permission.decorator';
import { AccessTokenClaims } from '../../../common/guards/jwt-auth.guard';

@Controller('platform/organizations/:organizationId/features')
export class PlatformFeaturesController {
  constructor(private readonly features: PlatformFeaturesService) {}

  @RequirePermission('org_features.read')
  @Get()
  getForOrganization(@Param('organizationId') organizationId: string) {
    return this.features.getForOrganization(organizationId);
  }

  @RequirePermission('org_features.update')
  @Put()
  @HttpCode(200)
  async setForOrganization(
    @CurrentUser() user: AccessTokenClaims,
    @Param('organizationId') organizationId: string,
    @Body(new ParseArrayPipe({ items: FeatureUpdateItem }))
    updates: FeatureUpdateItem[],
  ) {
    await this.features.setForOrganization(user.sub, organizationId, updates);
    return { status: 'ok' };
  }
}
