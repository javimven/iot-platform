import { Body, Controller, Delete, Get, HttpCode, Param, Patch, Post, Put } from '@nestjs/common';
import { MembersService } from './members.service';
import { SessionsService } from '../sessions/sessions.service';
import { MemberInviteDto, MemberScopeDto, MemberUpdateDto } from './dto/member.dto';
import { CurrentUser } from '../../../common/decorators/current-user.decorator';
import { RequirePermission } from '../../../common/decorators/require-permission.decorator';
import { AccessTokenClaims } from '../../../common/guards/jwt-auth.guard';

@Controller('members')
export class MembersController {
  constructor(
    private readonly members: MembersService,
    private readonly sessions: SessionsService,
  ) {}

  @RequirePermission('members.read')
  @Get()
  list(@CurrentUser() user: AccessTokenClaims) {
    return this.members.listForOrganization(user);
  }

  @RequirePermission('members.invite')
  @Post()
  invite(@CurrentUser() user: AccessTokenClaims, @Body() dto: MemberInviteDto) {
    return this.members.invite(user, dto);
  }

  @RequirePermission('members.update_role')
  @Patch(':id')
  update(
    @CurrentUser() user: AccessTokenClaims,
    @Param('id') id: string,
    @Body() dto: MemberUpdateDto,
  ) {
    return this.members.updateRoleOrStatus(user, id, dto);
  }

  @RequirePermission('members.remove')
  @Delete(':id')
  @HttpCode(204)
  async remove(@CurrentUser() user: AccessTokenClaims, @Param('id') id: string) {
    await this.members.remove(user, id);
  }

  @RequirePermission('member_scope.read')
  @Get(':id/scope')
  getScope(@CurrentUser() user: AccessTokenClaims, @Param('id') id: string) {
    return this.members.getScope(user, id);
  }

  @RequirePermission('member_scope.assign')
  @Put(':id/scope')
  async setScope(
    @CurrentUser() user: AccessTokenClaims,
    @Param('id') id: string,
    @Body() dto: MemberScopeDto,
  ) {
    await this.members.setScope(user, id, dto.installationIds);
  }

  /** `BACKLOG.md` #14 — un Admin de organización puede ver las sesiones activas de otro miembro de su equipo. */
  @RequirePermission('sessions.read_others')
  @Get(':id/sessions')
  async listSessions(@CurrentUser() user: AccessTokenClaims, @Param('id') id: string) {
    const member = await this.members.findMemberInOrg(user, id);
    return this.sessions.listForUser(user.organizationId!, member.userId);
  }

  /** `BACKLOG.md` #14 — revocar acceso a un empleado que se va o cuya cuenta se ve comprometida. */
  @RequirePermission('sessions.revoke_others')
  @Delete(':id/sessions/:sessionId')
  @HttpCode(204)
  async revokeSession(
    @CurrentUser() user: AccessTokenClaims,
    @Param('id') id: string,
    @Param('sessionId') sessionId: string,
  ) {
    const member = await this.members.findMemberInOrg(user, id);
    await this.sessions.revokeForUser(user.organizationId!, member.userId, sessionId, user.sub);
  }
}
