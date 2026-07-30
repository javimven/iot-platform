import { randomUUID } from 'node:crypto';
import { ForbiddenException, Injectable, Logger, NotFoundException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { PrismaService } from '../../../common/prisma/prisma.service';
import { AuditLogService } from '../../../common/audit/audit-log.service';
import { PasswordService } from '../../../common/security/password.service';
import { MailerService } from '../../../common/mailer/mailer.service';
import { AccessTokenClaims } from '../../../common/guards/jwt-auth.guard';
import { RoleCode } from '../../../common/permissions/permissions';
import { MemberInviteDto, MemberUpdateDto } from './dto/member.dto';

export interface ActiveMembership {
  memberId: string;
  organizationId: string;
  organizationName: string;
  roleCode: RoleCode;
}

interface InvitationTokenClaims {
  sub: string; // memberId
  type: 'invitation';
}

/** OPENAPI.yaml `Member` — nunca incluye `passwordHash` (ver `listForOrganization`). */
export interface MemberListItem {
  id: string;
  userId: string;
  email: string;
  fullName: string;
  roleCode: string;
  status: string;
  invitedAt: Date | null;
  activatedAt: Date | null;
}

const INVITATION_TOKEN_TTL = '7d'; // FUNCTIONAL_REQUIREMENTS.md §3 (enlace de invitación)

@Injectable()
export class MembersService {
  private readonly logger = new Logger(MembersService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly auditLog: AuditLogService,
    private readonly passwords: PasswordService,
    private readonly jwt: JwtService,
    private readonly mailer: MailerService,
    private readonly config: ConfigService,
  ) {}

  /**
   * Membresías activas de un usuario, a través de todas sus organizaciones —
   * exactamente el caso que motivó la excepción "propio usuario" de la
   * política RLS de `members` (DATA_MODEL.md §7): antes de elegir
   * organización activa, no hay `app.current_org_id` que filtrar.
   */
  async findActiveMembershipsForUser(userId: string): Promise<ActiveMembership[]> {
    const members = await this.prisma.runInTenantContext({ userId }, (tx) =>
      tx.member.findMany({
        where: { userId, status: 'active', deletedAt: null },
        include: { organization: true },
      }),
    );
    return members.map((m) => ({
      memberId: m.id,
      organizationId: m.organizationId,
      organizationName: m.organization.name,
      roleCode: m.roleCode as RoleCode,
    }));
  }

  async findMembership(
    userId: string,
    organizationId: string,
  ): Promise<{ memberId: string; roleCode: RoleCode } | null> {
    const member = await this.prisma.runInTenantContext({ userId, organizationId }, (tx) =>
      tx.member.findFirst({
        where: { userId, organizationId, status: 'active', deletedAt: null },
      }),
    );
    return member ? { memberId: member.id, roleCode: member.roleCode as RoleCode } : null;
  }

  async listForOrganization(user: AccessTokenClaims): Promise<MemberListItem[]> {
    const members = await this.prisma.runInTenantContext(
      { userId: user.sub, organizationId: user.organizationId },
      (tx) =>
        tx.member.findMany({
          where: { organizationId: user.organizationId!, deletedAt: null },
          // `select` (no `include: { user: true }`) — nunca se pide
          // `passwordHash` a la base de datos, así que no puede filtrarse en
          // la respuesta por descuido de serialización (bug real encontrado
          // en vivo: `include: { user: true }` devolvía el hash de Argon2 de
          // cada miembro a cualquier org_admin que listara `GET /members`).
          include: { user: { select: { email: true, fullName: true } } },
          orderBy: { createdAt: 'asc' },
        }),
    );
    return members.map((member) => ({
      id: member.id,
      userId: member.userId,
      email: member.user.email,
      fullName: member.user.fullName,
      roleCode: member.roleCode,
      status: member.status,
      invitedAt: member.invitedAt,
      activatedAt: member.activatedAt,
    }));
  }

  /**
   * Invita a un miembro (FUNCTIONAL_REQUIREMENTS.md §3): crea el `User` si
   * el email no existe todavía (con una contraseña de relleno inutilizable
   * hasta que acepte la invitación), el `Member` en estado `invited`, y
   * envía el email con el enlace de activación.
   *
   * El envío se hace en el mismo request (no encolado): a diferencia de las
   * notificaciones de alerta (`NotificationDispatchService`, mucho más
   * frecuentes), invitar a un miembro es una acción poco habitual e
   * iniciada por un humano que espera una respuesta — un fallo de SMTP se
   * atrapa y se loguea, pero no bloquea la creación del miembro (Etapa 13,
   * simplificación deliberada frente a montar una cola solo para esto).
   */
  async invite(user: AccessTokenClaims, dto: MemberInviteDto): Promise<MemberListItem> {
    const organizationId = user.organizationId!;
    const { member, targetUser, token } = await this.prisma.runInTenantContext(
      { userId: user.sub, organizationId },
      async (tx) => {
        let targetUser = await tx.user.findUnique({ where: { email: dto.email } });
        if (!targetUser) {
          targetUser = await tx.user.create({
            data: {
              email: dto.email,
              fullName: dto.email,
              // Contraseña de relleno inutilizable — se sustituye al aceptar
              // la invitación (accept-invitation); nadie puede iniciar sesión
              // con esta hasta entonces.
              passwordHash: await this.passwords.hash(randomUUID()),
            },
          });
        }

        const existing = await tx.member.findFirst({
          where: { userId: targetUser.id, organizationId, deletedAt: null },
        });
        if (existing) {
          throw new ForbiddenException('This user is already a member of the organization');
        }

        const createdMember = await tx.member.create({
          data: {
            userId: targetUser.id,
            organizationId,
            roleCode: dto.roleCode,
            status: 'invited',
            invitedById: user.sub,
            invitedAt: new Date(),
          },
        });

        await this.auditLog.record(tx, {
          organizationId,
          actorUserId: user.sub,
          action: 'members.invite',
          targetType: 'member',
          targetId: createdMember.id,
          metadata: { email: dto.email, roleCode: dto.roleCode },
        });

        const invitationToken = await this.jwt.signAsync(
          { sub: createdMember.id, type: 'invitation' } satisfies InvitationTokenClaims,
          { expiresIn: INVITATION_TOKEN_TTL },
        );

        return { member: createdMember, targetUser, token: invitationToken };
      },
    );

    await this.sendInvitationEmail(dto.email, token);
    // Aplanado al esquema `Member` documentado (OPENAPI.yaml) — igual que
    // `listForOrganization`; `targetUser` ya estaba en memoria, no hace
    // falta una consulta extra para email/fullName.
    return {
      id: member.id,
      userId: member.userId,
      email: targetUser.email,
      fullName: targetUser.fullName,
      roleCode: member.roleCode,
      status: member.status,
      invitedAt: member.invitedAt,
      activatedAt: member.activatedAt,
    };
  }

  private async sendInvitationEmail(email: string, token: string): Promise<void> {
    const appBaseUrl = this.config.get<string>('APP_BASE_URL', 'http://localhost:5173');
    const link = `${appBaseUrl}/accept-invitation?token=${token}`;
    const result = await this.mailer.send({
      to: email,
      subject: 'Invitación a la plataforma IoT',
      text: `Se te ha invitado a unirte a una organización. Activa tu cuenta aquí: ${link}\n\nEl enlace caduca en 7 días.`,
    });
    if (!result.ok) {
      this.logger.error(`Failed to email invitation to ${email}: ${result.error}`);
    }
  }

  async updateRoleOrStatus(
    user: AccessTokenClaims,
    memberId: string,
    dto: MemberUpdateDto,
  ): Promise<MemberListItem> {
    const tenantContext = { userId: user.sub, organizationId: user.organizationId };
    const existing = await this.prisma.runInTenantContext(tenantContext, (tx) =>
      tx.member.findFirst({ where: { id: memberId, deletedAt: null } }),
    );
    if (!existing) {
      throw new NotFoundException('Member not found');
    }

    const updated = await this.prisma.runInTenantContext(tenantContext, async (tx) => {
      const result = await tx.member.update({
        where: { id: memberId },
        data: dto,
        // Igual que `listForOrganization`/`invite` — `select` (no
        // `include: { user: true }`) para no pedirle `passwordHash` a la
        // base de datos.
        include: { user: { select: { email: true, fullName: true } } },
      });
      await this.auditLog.record(tx, {
        organizationId: user.organizationId,
        actorUserId: user.sub,
        action: dto.roleCode ? 'members.update_role' : 'members.suspend_or_reactivate',
        targetType: 'member',
        targetId: memberId,
        metadata: { ...dto },
      });
      return result;
    });

    return {
      id: updated.id,
      userId: updated.userId,
      email: updated.user.email,
      fullName: updated.user.fullName,
      roleCode: updated.roleCode,
      status: updated.status,
      invitedAt: updated.invitedAt,
      activatedAt: updated.activatedAt,
    };
  }

  async remove(user: AccessTokenClaims, memberId: string): Promise<void> {
    const tenantContext = { userId: user.sub, organizationId: user.organizationId };
    const existing = await this.prisma.runInTenantContext(tenantContext, (tx) =>
      tx.member.findFirst({ where: { id: memberId, deletedAt: null } }),
    );
    if (!existing) {
      throw new NotFoundException('Member not found');
    }
    await this.prisma.runInTenantContext(tenantContext, async (tx) => {
      await tx.member.update({ where: { id: memberId }, data: { deletedAt: new Date() } });
      await this.auditLog.record(tx, {
        organizationId: user.organizationId,
        actorUserId: user.sub,
        action: 'members.remove',
        targetType: 'member',
        targetId: memberId,
      });
    });
  }

  /** Resuelve un `memberId` a su `userId`, acotado a la organización del que llama (404 si no existe o es de otra organización). */
  async findMemberInOrg(
    user: AccessTokenClaims,
    memberId: string,
  ): Promise<{ id: string; userId: string }> {
    const tenantContext = { userId: user.sub, organizationId: user.organizationId };
    const member = await this.prisma.runInTenantContext(tenantContext, (tx) =>
      tx.member.findFirst({ where: { id: memberId, deletedAt: null } }),
    );
    if (!member) {
      throw new NotFoundException('Member not found');
    }
    return { id: member.id, userId: member.userId };
  }

  async getScope(user: AccessTokenClaims, memberId: string): Promise<string[]> {
    const tenantContext = { userId: user.sub, organizationId: user.organizationId };
    const rows = await this.prisma.runInTenantContext(tenantContext, (tx) =>
      tx.memberInstallationScope.findMany({ where: { memberId } }),
    );
    return rows.map((r) => r.installationId);
  }

  async setScope(
    user: AccessTokenClaims,
    memberId: string,
    installationIds: string[],
  ): Promise<void> {
    const tenantContext = { userId: user.sub, organizationId: user.organizationId };
    await this.prisma.runInTenantContext(tenantContext, async (tx) => {
      await tx.memberInstallationScope.deleteMany({ where: { memberId } });
      if (installationIds.length > 0) {
        await tx.memberInstallationScope.createMany({
          data: installationIds.map((installationId) => ({ memberId, installationId })),
        });
      }
      await this.auditLog.record(tx, {
        organizationId: user.organizationId,
        actorUserId: user.sub,
        action: 'member_scope.assign',
        targetType: 'member',
        targetId: memberId,
        metadata: { installationIds },
      });
    });
  }

  /**
   * Consume un token de invitación (`invite`) y activa la membresía
   * (FUNCTIONAL_REQUIREMENTS.md §3). Simplificación de MVP: siempre exige
   * `newPassword`, aunque el usuario ya tuviera cuenta en otra organización
   * — evita tener que distinguir "contraseña de relleno" de una real sin
   * una columna adicional en el esquema.
   */
  async acceptInvitation(token: string, newPassword: string): Promise<void> {
    let claims: InvitationTokenClaims;
    try {
      claims = await this.jwt.verifyAsync<InvitationTokenClaims>(token);
    } catch {
      throw new ForbiddenException('Invalid or expired invitation token');
    }
    if (claims.type !== 'invitation') {
      throw new ForbiddenException('Token is not an invitation token');
    }

    // Ni organizationId ni userId se conocen todavía en este punto — misma
    // excepción de arranque de identidad que usa el refresh de sesión
    // (DATA_MODEL.md §7, `allowIdentityBootstrap`).
    const member = await this.prisma.runInTenantContext({ allowIdentityBootstrap: true }, (tx) =>
      tx.member.findUnique({ where: { id: claims.sub } }),
    );
    if (!member || member.status !== 'invited') {
      throw new ForbiddenException('Invitation is no longer valid');
    }

    const passwordHash = await this.passwords.hash(newPassword);
    await this.prisma.runInTenantContext(
      { userId: member.userId, organizationId: member.organizationId },
      async (tx) => {
        await tx.user.update({ where: { id: member.userId }, data: { passwordHash } });
        await tx.member.update({
          where: { id: member.id },
          data: { status: 'active', activatedAt: new Date() },
        });
        await this.auditLog.record(tx, {
          organizationId: member.organizationId,
          actorUserId: member.userId,
          action: 'members.accept_invitation',
          targetType: 'member',
          targetId: member.id,
        });
      },
    );
  }
}
