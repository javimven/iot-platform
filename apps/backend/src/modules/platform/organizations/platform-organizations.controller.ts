import { Body, Controller, Get, Param, Post } from '@nestjs/common';
import { PlatformOrganizationsService } from './platform-organizations.service';
import { PlatformOrganizationCreateDto } from './dto/platform-organization.dto';
import { CurrentUser } from '../../../common/decorators/current-user.decorator';
import { RequirePermission } from '../../../common/decorators/require-permission.decorator';
import { AccessTokenClaims } from '../../../common/guards/jwt-auth.guard';

@Controller('platform/organizations')
export class PlatformOrganizationsController {
  constructor(private readonly organizations: PlatformOrganizationsService) {}

  @RequirePermission('platform.organizations.create')
  @Post()
  create(@CurrentUser() user: AccessTokenClaims, @Body() dto: PlatformOrganizationCreateDto) {
    return this.organizations.create(user.sub, dto);
  }

  @RequirePermission('platform.organizations.read')
  @Get()
  list() {
    return this.organizations.list();
  }

  @RequirePermission('platform.organizations.suspend')
  @Post(':id/suspend')
  suspend(@CurrentUser() user: AccessTokenClaims, @Param('id') id: string) {
    return this.organizations.setStatus(user.sub, id, 'suspended');
  }

  @RequirePermission('platform.organizations.reactivate')
  @Post(':id/reactivate')
  reactivate(@CurrentUser() user: AccessTokenClaims, @Param('id') id: string) {
    return this.organizations.setStatus(user.sub, id, 'active');
  }
}
