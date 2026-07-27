import { randomUUID } from 'node:crypto';
import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { Organization, Prisma } from '@prisma/client';
import { PrismaService } from '../../../common/prisma/prisma.service';
import { AuditLogService } from '../../../common/audit/audit-log.service';
import { PasswordService } from '../../../common/security/password.service';
import { MailerService } from '../../../common/mailer/mailer.service';
import { PlatformOrganizationCreateDto } from './dto/platform-organization.dto';

/**
 * Alta/baja de organizaciones (FUNCTIONAL_REQUIREMENTS.md §2). `create` es la
 * única acción que escribe en `members` como Admin de plataforma —
 * PERMISSIONS.md nota ³ explica por qué no es una puerta trasera general.
 */
@Injectable()
export class PlatformOrganizationsService {
  private readonly logger = new Logger(PlatformOrganizationsService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly auditLog: AuditLogService,
    private readonly passwords: PasswordService,
    private readonly jwt: JwtService,
    private readonly mailer: MailerService,
    private readonly config: ConfigService,
  ) {}

  async create(actorUserId: string, dto: PlatformOrganizationCreateDto): Promise<Organization> {
    const { organization, invitationToken } = await this.prisma.runInTenantContext(
      { userId: actorUserId, isPlatformAdmin: true },
      async (tx) => {
        const slug = await this.uniqueSlug(tx, dto.name);
        const organization = await tx.organization.create({
          data: { name: dto.name, slug, contactEmail: dto.contactEmail },
        });

        let firstAdminUser = await tx.user.findUnique({ where: { email: dto.firstAdminEmail } });
        if (!firstAdminUser) {
          firstAdminUser = await tx.user.create({
            data: {
              email: dto.firstAdminEmail,
              fullName: dto.firstAdminEmail,
              passwordHash: await this.passwords.hash(randomUUID()),
            },
          });
        }
        const firstAdminMember = await tx.member.create({
          data: {
            userId: firstAdminUser.id,
            organizationId: organization.id,
            roleCode: 'org_admin',
            status: 'invited',
            invitedById: actorUserId,
            invitedAt: new Date(),
          },
        });
        const invitationToken = await this.jwt.signAsync(
          { sub: firstAdminMember.id, type: 'invitation' },
          { expiresIn: '7d' },
        );

        await this.auditLog.record(tx, {
          organizationId: organization.id,
          actorUserId,
          action: 'platform.organizations.create',
          targetType: 'organization',
          targetId: organization.id,
          metadata: { name: dto.name, firstAdminEmail: dto.firstAdminEmail },
        });

        return { organization, invitationToken };
      },
    );

    const appBaseUrl = this.config.get<string>('APP_BASE_URL', 'http://localhost:5173');
    const link = `${appBaseUrl}/accept-invitation?token=${invitationToken}`;
    const result = await this.mailer.send({
      to: dto.firstAdminEmail,
      subject: 'Tu organización ha sido creada — activa tu cuenta',
      text: `Se ha creado la organización "${dto.name}" y se te ha invitado como su primer Administrador. Activa tu cuenta aquí: ${link}\n\nEl enlace caduca en 7 días.`,
    });
    if (!result.ok) {
      this.logger.error(
        `Failed to email first-admin invitation to ${dto.firstAdminEmail}: ${result.error}`,
      );
    }

    return organization;
  }

  async list(): Promise<Organization[]> {
    // `organizations` no tiene RLS (DATA_MODEL.md §7, es de ámbito de
    // plataforma) — el propio PermissionsGuard ya garantiza que solo un
    // Admin de plataforma llega hasta aquí.
    return this.prisma.organization.findMany({
      where: { deletedAt: null },
      orderBy: { createdAt: 'desc' },
    });
  }

  async setStatus(
    actorUserId: string,
    id: string,
    status: 'active' | 'suspended',
  ): Promise<Organization> {
    return this.prisma.runInTenantContext(
      { userId: actorUserId, isPlatformAdmin: true },
      async (tx) => {
        const updated = await tx.organization.update({ where: { id }, data: { status } });
        await this.auditLog.record(tx, {
          organizationId: id,
          actorUserId,
          action:
            status === 'suspended'
              ? 'platform.organizations.suspend'
              : 'platform.organizations.reactivate',
          targetType: 'organization',
          targetId: id,
        });
        return updated;
      },
    );
  }

  private async uniqueSlug(tx: Prisma.TransactionClient, name: string): Promise<string> {
    // NFD + rango Unicode de diacríticos combinantes (U+0300-U+036F) — forma
    // estándar de quitar acentos en JS/TS antes de generar un slug.
    const base = name
      .toLowerCase()
      .normalize('NFD')
      .replace(/[\u0300-\u036f]/g, '')
      .replace(/[^a-z0-9]+/g, '-')
      .replace(/(^-|-$)/g, '');
    let candidate = base || 'org';
    let attempt = 0;
    while (attempt < 5) {
      const existing = await tx.organization.findUnique({ where: { slug: candidate } });
      if (!existing) {
        return candidate;
      }
      candidate = `${base}-${randomUUID().slice(0, 6)}`;
      attempt += 1;
    }
    return `${base}-${randomUUID()}`;
  }
}
