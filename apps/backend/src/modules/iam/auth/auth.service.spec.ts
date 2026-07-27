import { UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { AuthService, AuthOrgSelection, AuthSuccess } from './auth.service';
import { UsersService } from '../users/users.service';
import { MembersService } from '../members/members.service';
import { SessionsService } from '../sessions/sessions.service';
import { PasswordService } from '../../../common/security/password.service';
import { MailerService } from '../../../common/mailer/mailer.service';
import { ConfigService } from '@nestjs/config';

/**
 * API_DESIGN.md §3: 0/1 membresía -> AuthSuccess directo; >1 -> AuthOrgSelection
 * con preAuthToken. TESTING_STRATEGY.md §13: "login de un usuario con 2
 * membresías recibe preAuthToken, no accessToken".
 */
describe('AuthService', () => {
  const activeUser = {
    id: 'user-1',
    email: 'tecnico@example.com',
    passwordHash: 'hash',
    fullName: 'Técnico Uno',
    status: 'active' as const,
    createdAt: new Date(),
    updatedAt: new Date(),
    deletedAt: null,
  };

  function buildService(overrides?: {
    memberships?: Array<{
      memberId: string;
      organizationId: string;
      organizationName: string;
      roleCode: 'org_admin';
    }>;
    isPlatformAdmin?: boolean;
    passwordValid?: boolean;
  }) {
    const users = {
      findByEmail: jest.fn().mockResolvedValue(activeUser),
      findById: jest.fn().mockResolvedValue(activeUser),
      isPlatformAdmin: jest.fn().mockResolvedValue(overrides?.isPlatformAdmin ?? false),
    } as unknown as jest.Mocked<UsersService>;

    const members = {
      findActiveMembershipsForUser: jest.fn().mockResolvedValue(overrides?.memberships ?? []),
      findMembership: jest.fn(),
    } as unknown as jest.Mocked<MembersService>;

    const sessions = {
      create: jest.fn().mockResolvedValue({ sessionId: 'session-1', secret: 'secret-1' }),
      rotate: jest.fn(),
      revoke: jest.fn(),
      revokeAllForUser: jest.fn(),
      listOwn: jest.fn(),
    } as unknown as jest.Mocked<SessionsService>;

    const passwords = {
      verify: jest.fn().mockResolvedValue(overrides?.passwordValid ?? true),
      hash: jest.fn(),
    } as unknown as jest.Mocked<PasswordService>;

    const jwt = {
      signAsync: jest.fn().mockResolvedValue('signed.jwt.token'),
      verifyAsync: jest.fn(),
    } as unknown as jest.Mocked<JwtService>;

    const mailer = {
      send: jest.fn().mockResolvedValue({ ok: true }),
    } as unknown as jest.Mocked<MailerService>;

    const config = {
      get: jest.fn().mockReturnValue('http://localhost:5173'),
    } as unknown as jest.Mocked<ConfigService>;

    const service = new AuthService(users, members, sessions, passwords, jwt, mailer, config);
    return { service, users, members, sessions, passwords, jwt, mailer, config };
  }

  it('rechaza credenciales inválidas sin filtrar si el email existe', async () => {
    const { service } = buildService({ passwordValid: false });
    await expect(service.login('tecnico@example.com', 'wrong', {})).rejects.toThrow(
      UnauthorizedException,
    );
  });

  it('con 0 membresías (Admin de plataforma puro) devuelve AuthSuccess directo', async () => {
    const { service, sessions } = buildService({ memberships: [], isPlatformAdmin: true });
    const result = (await service.login('tecnico@example.com', 'pw', {})) as AuthSuccess;
    expect(result.accessToken).toBe('signed.jwt.token');
    expect(result.refreshToken.sessionId).toBe('session-1');
    expect(sessions.create).toHaveBeenCalledWith(
      expect.objectContaining({ userId: 'user-1', organizationId: undefined }),
    );
  });

  it('con 1 membresía devuelve AuthSuccess directo con esa organización', async () => {
    const { service, sessions } = buildService({
      memberships: [
        {
          memberId: 'member-1',
          organizationId: 'org-1',
          organizationName: 'Finca A',
          roleCode: 'org_admin',
        },
      ],
    });
    const result = (await service.login('tecnico@example.com', 'pw', {})) as AuthSuccess;
    expect(result.refreshToken.sessionId).toBe('session-1');
    expect(sessions.create).toHaveBeenCalledWith(
      expect.objectContaining({ organizationId: 'org-1' }),
    );
  });

  it('con >1 membresía devuelve AuthOrgSelection con preAuthToken, no un accessToken', async () => {
    const { service, sessions } = buildService({
      memberships: [
        {
          memberId: 'member-1',
          organizationId: 'org-1',
          organizationName: 'Finca A',
          roleCode: 'org_admin',
        },
        {
          memberId: 'member-2',
          organizationId: 'org-2',
          organizationName: 'Finca B',
          roleCode: 'org_admin',
        },
      ],
    });
    const result = (await service.login('tecnico@example.com', 'pw', {})) as AuthOrgSelection;
    expect(result.preAuthToken).toBe('signed.jwt.token');
    expect(result.organizations).toHaveLength(2);
    expect((result as unknown as AuthSuccess).accessToken).toBeUndefined();
    expect(sessions.create).not.toHaveBeenCalled(); // no se crea sesión hasta elegir organización
  });

  it('selectOrganization rechaza un preAuthToken que no sea de tipo pre_auth', async () => {
    const { service, jwt } = buildService();
    jwt.verifyAsync.mockResolvedValue({ sub: 'user-1', type: 'access' });
    await expect(service.selectOrganization('token', 'org-1', {})).rejects.toThrow(
      UnauthorizedException,
    );
  });

  it('selectOrganization rechaza si el usuario ya no es miembro activo de esa organización', async () => {
    const { service, jwt, members } = buildService();
    jwt.verifyAsync.mockResolvedValue({ sub: 'user-1', type: 'pre_auth' });
    (members.findMembership as jest.Mock).mockResolvedValue(null);
    await expect(service.selectOrganization('token', 'org-1', {})).rejects.toThrow(
      UnauthorizedException,
    );
  });
});
