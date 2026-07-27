import { Controller, Get } from '@nestjs/common';
import { CurrentUser } from '../../../common/decorators/current-user.decorator';
import { AccessTokenClaims } from '../../../common/guards/jwt-auth.guard';
import { UsersService } from '../users/users.service';
import { MembersService } from '../members/members.service';
import {
  ROLE_PERMISSIONS,
  PLATFORM_ACTIONS,
  PLATFORM_DIRECTORY_ACTIONS,
} from '../../../common/permissions/permissions';

/** OPENAPI.yaml /me, /me/permissions — PERMISSIONS.md §5. */
@Controller('me')
export class MeController {
  constructor(
    private readonly users: UsersService,
    private readonly members: MembersService,
  ) {}

  @Get()
  async me(@CurrentUser() claims: AccessTokenClaims) {
    const [user, memberships] = await Promise.all([
      this.users.findById(claims.sub),
      this.members.findActiveMembershipsForUser(claims.sub),
    ]);
    return {
      userId: claims.sub,
      fullName: user?.fullName,
      email: user?.email,
      isPlatformAdmin: claims.isPlatformAdmin ?? false,
      activeOrganizationId: claims.organizationId ?? null,
      roleCode: claims.roleCode ?? null,
      memberships,
    };
  }

  @Get('permissions')
  me_permissions(@CurrentUser() claims: AccessTokenClaims): { permissions: string[] } {
    if (claims.isPlatformAdmin) {
      return { permissions: [...PLATFORM_ACTIONS, ...PLATFORM_DIRECTORY_ACTIONS] };
    }
    return { permissions: claims.roleCode ? ROLE_PERMISSIONS[claims.roleCode] : [] };
  }
}
