import { Body, Controller, Delete, Get, HttpCode, Param, Patch, Post, Put } from '@nestjs/common';
import { MembersService } from './members.service';
import { MemberInviteDto, MemberScopeDto, MemberUpdateDto } from './dto/member.dto';
import { CurrentUser } from '../../../common/decorators/current-user.decorator';
import { RequirePermission } from '../../../common/decorators/require-permission.decorator';
import { AccessTokenClaims } from '../../../common/guards/jwt-auth.guard';

@Controller('members')
export class MembersController {
  constructor(private readonly members: MembersService) {}

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
}
