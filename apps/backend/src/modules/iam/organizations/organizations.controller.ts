import { Body, Controller, Get, Patch } from '@nestjs/common';
import { OrganizationsService } from './organizations.service';
import { OrganizationUpdateDto } from './dto/organization.dto';
import { CurrentUser } from '../../../common/decorators/current-user.decorator';
import { RequirePermission } from '../../../common/decorators/require-permission.decorator';
import { AccessTokenClaims } from '../../../common/guards/jwt-auth.guard';

@Controller('organization')
export class OrganizationsController {
  constructor(private readonly organizations: OrganizationsService) {}

  @RequirePermission('org.profile.read')
  @Get()
  getProfile(@CurrentUser() user: AccessTokenClaims) {
    return this.organizations.getProfile(user);
  }

  @RequirePermission('org.profile.update')
  @Patch()
  updateProfile(@CurrentUser() user: AccessTokenClaims, @Body() dto: OrganizationUpdateDto) {
    return this.organizations.updateProfile(user, dto);
  }

  @RequirePermission('org_features.read')
  @Get('features')
  getFeatures(@CurrentUser() user: AccessTokenClaims) {
    return this.organizations.getFeatures(user);
  }
}
