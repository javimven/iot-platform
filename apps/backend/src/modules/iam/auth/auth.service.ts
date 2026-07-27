import { Injectable, Logger, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { UsersService } from '../users/users.service';
import { MembersService } from '../members/members.service';
import { SessionsService } from '../sessions/sessions.service';
import { PasswordService } from '../../../common/security/password.service';
import { MailerService } from '../../../common/mailer/mailer.service';
import { AccessTokenClaims } from '../../../common/guards/jwt-auth.guard';

export interface AuthSuccess {
  accessToken: string;
  refreshToken: { sessionId: string; secret: string };
}

export interface AuthOrgSelection {
  preAuthToken: string;
  organizations: Array<{ organizationId: string; name: string; roleCode: string }>;
}

interface PasswordResetTokenClaims {
  sub: string; // userId
  type: 'password_reset';
}

const PRE_AUTH_TOKEN_TTL = '5m'; // API_DESIGN.md §3
const PASSWORD_RESET_TOKEN_TTL = '30m'; // FUNCTIONAL_REQUIREMENTS.md §3, SECURITY.md §3

@Injectable()
export class AuthService {
  private readonly logger = new Logger(AuthService.name);

  constructor(
    private readonly users: UsersService,
    private readonly members: MembersService,
    private readonly sessions: SessionsService,
    private readonly passwords: PasswordService,
    private readonly jwt: JwtService,
    private readonly mailer: MailerService,
    private readonly config: ConfigService,
  ) {}

  /**
   * API_DESIGN.md §3: 0/1 membresía (o Admin de plataforma puro) -> AuthSuccess
   * directo; >1 membresía -> AuthOrgSelection con preAuthToken de vida corta.
   */
  async login(
    email: string,
    password: string,
    meta: { userAgent?: string; ipAddress?: string },
  ): Promise<AuthSuccess | AuthOrgSelection> {
    const user = await this.users.findByEmail(email);
    if (!user || user.status !== 'active') {
      throw new UnauthorizedException('Invalid credentials');
    }
    const validPassword = await this.passwords.verify(user.passwordHash, password);
    if (!validPassword) {
      throw new UnauthorizedException('Invalid credentials');
    }

    const [isPlatformAdmin, memberships] = await Promise.all([
      this.users.isPlatformAdmin(user.id),
      this.members.findActiveMembershipsForUser(user.id),
    ]);

    if (memberships.length > 1) {
      const preAuthToken = await this.jwt.signAsync(
        { sub: user.id, type: 'pre_auth' } satisfies AccessTokenClaims,
        { expiresIn: PRE_AUTH_TOKEN_TTL },
      );
      return {
        preAuthToken,
        organizations: memberships.map((m) => ({
          organizationId: m.organizationId,
          name: m.organizationName,
          roleCode: m.roleCode,
        })),
      };
    }

    const membership = memberships[0];
    return this.issueSession(
      user.id,
      membership?.organizationId,
      membership?.memberId,
      membership?.roleCode,
      isPlatformAdmin,
      meta,
    );
  }

  async selectOrganization(
    preAuthToken: string,
    organizationId: string,
    meta: { userAgent?: string; ipAddress?: string },
  ): Promise<AuthSuccess> {
    let claims: AccessTokenClaims;
    try {
      claims = await this.jwt.verifyAsync<AccessTokenClaims>(preAuthToken);
    } catch {
      throw new UnauthorizedException('Invalid or expired preAuthToken');
    }
    if (claims.type !== 'pre_auth') {
      throw new UnauthorizedException('Token is not a preAuthToken');
    }

    const membership = await this.members.findMembership(claims.sub, organizationId);
    if (!membership) {
      throw new UnauthorizedException('User is not an active member of this organization');
    }

    return this.issueSession(
      claims.sub,
      organizationId,
      membership.memberId,
      membership.roleCode,
      false,
      meta,
    );
  }

  async refresh(sessionId: string, secret: string): Promise<AuthSuccess> {
    const rotated = await this.sessions.rotate(sessionId, secret);
    const membership = rotated.organizationId
      ? await this.members.findMembership(rotated.userId, rotated.organizationId)
      : null;
    const isPlatformAdmin = rotated.organizationId
      ? false
      : await this.users.isPlatformAdmin(rotated.userId);

    const accessToken = await this.signAccessToken({
      sub: rotated.userId,
      organizationId: rotated.organizationId ?? undefined,
      memberId: membership?.memberId,
      roleCode: membership?.roleCode,
      isPlatformAdmin,
    });

    return { accessToken, refreshToken: { sessionId: rotated.sessionId, secret: rotated.secret } };
  }

  async logout(sessionId: string, userId: string): Promise<void> {
    await this.sessions.revoke(sessionId, userId);
  }

  /**
   * API_DESIGN.md §3: respuesta idéntica exista o no la cuenta — nunca se
   * filtra qué emails están registrados. Si el usuario existe, se envía el
   * email (best-effort, igual que la invitación de miembros); si falla el
   * envío, se loguea pero tampoco se distingue en la respuesta al llamador.
   */
  async forgotPassword(email: string): Promise<void> {
    const user = await this.users.findByEmail(email);
    if (!user || user.status !== 'active') {
      return;
    }

    const token = await this.jwt.signAsync(
      { sub: user.id, type: 'password_reset' } satisfies PasswordResetTokenClaims,
      { expiresIn: PASSWORD_RESET_TOKEN_TTL },
    );
    const appBaseUrl = this.config.get<string>('APP_BASE_URL', 'http://localhost:5173');
    const link = `${appBaseUrl}/reset-password?token=${token}`;
    const result = await this.mailer.send({
      to: email,
      subject: 'Restablecer tu contraseña',
      text: `Solicitaste restablecer tu contraseña. Usa este enlace (caduca en 30 min): ${link}\n\nSi no fuiste tú, ignora este email.`,
    });
    if (!result.ok) {
      this.logger.error(`Failed to email password reset to ${email}: ${result.error}`);
    }
  }

  /**
   * Cambiar la contraseña revoca todas las sesiones activas (SECURITY.md §3)
   * — fuerza a reautenticar en todos los dispositivos, igual que un cambio
   * de contraseña desde el perfil.
   */
  async resetPassword(token: string, newPassword: string): Promise<void> {
    let claims: PasswordResetTokenClaims;
    try {
      claims = await this.jwt.verifyAsync<PasswordResetTokenClaims>(token);
    } catch {
      throw new UnauthorizedException('Invalid or expired reset token');
    }
    if (claims.type !== 'password_reset') {
      throw new UnauthorizedException('Token is not a password reset token');
    }

    const passwordHash = await this.passwords.hash(newPassword);
    await this.users.updatePasswordHash(claims.sub, passwordHash);
    await this.sessions.revokeAllForUser(claims.sub);
  }

  private async issueSession(
    userId: string,
    organizationId: string | undefined,
    memberId: string | undefined,
    roleCode: string | undefined,
    isPlatformAdmin: boolean,
    meta: { userAgent?: string; ipAddress?: string },
  ): Promise<AuthSuccess> {
    const accessToken = await this.signAccessToken({
      sub: userId,
      organizationId,
      memberId,
      roleCode: roleCode as AccessTokenClaims['roleCode'],
      isPlatformAdmin,
    });
    const session = await this.sessions.create({ userId, organizationId, ...meta });
    return { accessToken, refreshToken: session };
  }

  private async signAccessToken(claims: Omit<AccessTokenClaims, 'type'>): Promise<string> {
    return this.jwt.signAsync({ ...claims, type: 'access' } satisfies AccessTokenClaims);
  }
}
