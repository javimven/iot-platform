import { Body, Controller, Delete, Get, HttpCode, Param, Post, Req } from '@nestjs/common';
import { Request } from 'express';
import { AuthService } from './auth.service';
import { SessionsService } from '../sessions/sessions.service';
import { MembersService } from '../members/members.service';
import { LoginDto } from './dto/login.dto';
import { SelectOrganizationDto } from './dto/select-organization.dto';
import { RefreshDto } from './dto/refresh.dto';
import { AcceptInvitationDto } from './dto/accept-invitation.dto';
import { ForgotPasswordDto } from './dto/forgot-password.dto';
import { ResetPasswordDto } from './dto/reset-password.dto';
import { Public } from '../../../common/decorators/public.decorator';
import { CurrentUser } from '../../../common/decorators/current-user.decorator';
import { AccessTokenClaims } from '../../../common/guards/jwt-auth.guard';

/** API_DESIGN.md §3, OPENAPI.yaml /auth/*. */
@Controller('auth')
export class AuthController {
  constructor(
    private readonly auth: AuthService,
    private readonly sessions: SessionsService,
    private readonly members: MembersService,
  ) {}

  @Public()
  @Post('login')
  async login(@Body() dto: LoginDto, @Req() req: Request) {
    return this.auth.login(dto.email, dto.password, {
      userAgent: req.headers['user-agent'],
      ipAddress: req.ip,
    });
  }

  @Public()
  @Post('select-organization')
  async selectOrganization(@Body() dto: SelectOrganizationDto, @Req() req: Request) {
    return this.auth.selectOrganization(dto.preAuthToken, dto.organizationId, {
      userAgent: req.headers['user-agent'],
      ipAddress: req.ip,
    });
  }

  @Public()
  @Post('refresh')
  async refresh(@Body() dto: RefreshDto) {
    return this.auth.refresh(dto.sessionId, dto.secret);
  }

  @Post('logout')
  @HttpCode(204)
  async logout(@CurrentUser() user: AccessTokenClaims, @Body() dto: { sessionId: string }) {
    await this.auth.logout(dto.sessionId, user.sub);
  }

  @Get('sessions')
  async listSessions(@CurrentUser() user: AccessTokenClaims) {
    return this.sessions.listOwn(user.sub);
  }

  @Delete('sessions/:sessionId')
  @HttpCode(204)
  async revokeSession(
    @CurrentUser() user: AccessTokenClaims,
    @Param('sessionId') sessionId: string,
  ) {
    await this.sessions.revoke(sessionId, user.sub);
  }

  @Public()
  @Post('accept-invitation')
  @HttpCode(200)
  async acceptInvitation(@Body() dto: AcceptInvitationDto) {
    await this.members.acceptInvitation(dto.token, dto.newPassword);
    return { status: 'ok' };
  }

  @Public()
  @Post('forgot-password')
  @HttpCode(202)
  async forgotPassword(@Body() dto: ForgotPasswordDto) {
    await this.auth.forgotPassword(dto.email);
    // Siempre 202, exista o no la cuenta (API_DESIGN.md §3) — no se filtra
    // qué emails están registrados.
  }

  @Public()
  @Post('reset-password')
  @HttpCode(200)
  async resetPassword(@Body() dto: ResetPasswordDto) {
    await this.auth.resetPassword(dto.token, dto.newPassword);
    return { status: 'ok' };
  }
}
