import { ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { Installation } from '@prisma/client';
import { PrismaService } from '../../../common/prisma/prisma.service';
import { AuditLogService } from '../../../common/audit/audit-log.service';
import { AccessTokenClaims } from '../../../common/guards/jwt-auth.guard';
import {
  resolveInstallationScope,
  scopeWhereClause,
} from '../../../common/permissions/installation-scope';
import { resolveOrgContext } from '../../../common/permissions/org-context';
import { InstallationCreateDto, InstallationUpdateDto } from './dto/installation.dto';

/**
 * Instalaciones (FUNCTIONAL_REQUIREMENTS.md §5, PERMISSIONS.md §2). El
 * alcance por instalación se resuelve y aplica aquí, no en RLS — es una
 * regla de autorización de aplicación (PERMISSIONS.md §2, ya documentado),
 * distinta del aislamiento multitenant (que sí es RLS, DATA_MODEL.md §7).
 *
 * `explicitOrganizationId` (ADR-0005, `BACKLOG.md` #18): la ruta de
 * plataforma (`/platform/organizations/{id}/installations`) no tiene una
 * organización implícita en el JWT, así que la recibe en la propia URL —
 * mismo patrón ya usado por `GatewaysService`. Las acciones que mutan
 * quedan auditadas (`auditLog.record`, dentro de la misma transacción) —
 * ADR-0005 exige que ninguna acción del Admin de plataforma sobre el
 * Directorio IoT de un cliente sea invisible para ese cliente; hasta el
 * 2026-07-30 ningún servicio de Directorio IoT auditaba nada, ni para
 * miembros normales ni para el Admin de plataforma (encontrado al construir
 * el flujo completo de plataforma y comprobar que no dejaba rastro).
 */
@Injectable()
export class InstallationsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly auditLog: AuditLogService,
  ) {}

  async create(
    user: AccessTokenClaims,
    dto: InstallationCreateDto,
    explicitOrganizationId?: string,
  ): Promise<Installation> {
    const { organizationId, tenantContext } = resolveOrgContext(user, explicitOrganizationId);
    return this.prisma.runInTenantContext(tenantContext, async (tx) => {
      const installation = await tx.installation.create({
        data: { organizationId, ...dto },
      });
      await this.auditLog.record(tx, {
        organizationId,
        actorUserId: user.sub,
        action: 'installations.create',
        targetType: 'installation',
        targetId: installation.id,
        metadata: { name: installation.name },
      });
      return installation;
    });
  }

  async findAll(user: AccessTokenClaims, explicitOrganizationId?: string): Promise<Installation[]> {
    const { tenantContext } = resolveOrgContext(user, explicitOrganizationId);
    const scope = await this.resolveScope(user);
    return this.prisma.runInTenantContext(tenantContext, (tx) =>
      tx.installation.findMany({
        where: { deletedAt: null, ...scopeWhereClause(scope, 'id') },
        orderBy: { name: 'asc' },
      }),
    );
  }

  async findOne(
    user: AccessTokenClaims,
    id: string,
    explicitOrganizationId?: string,
  ): Promise<Installation> {
    const { tenantContext } = resolveOrgContext(user, explicitOrganizationId);
    const installation = await this.prisma.runInTenantContext(tenantContext, (tx) =>
      tx.installation.findFirst({ where: { id, deletedAt: null } }),
    );
    if (!installation) {
      throw new NotFoundException('Installation not found');
    }
    await this.assertInScope(user, installation.id);
    return installation;
  }

  async update(
    user: AccessTokenClaims,
    id: string,
    dto: InstallationUpdateDto,
    explicitOrganizationId?: string,
  ): Promise<Installation> {
    const { organizationId, tenantContext } = resolveOrgContext(user, explicitOrganizationId);
    await this.findOne(user, id, explicitOrganizationId); // valida existencia + alcance
    return this.prisma.runInTenantContext(tenantContext, async (tx) => {
      const installation = await tx.installation.update({ where: { id }, data: dto });
      await this.auditLog.record(tx, {
        organizationId,
        actorUserId: user.sub,
        action: 'installations.update',
        targetType: 'installation',
        targetId: id,
        metadata: { ...dto },
      });
      return installation;
    });
  }

  async softDelete(
    user: AccessTokenClaims,
    id: string,
    explicitOrganizationId?: string,
  ): Promise<void> {
    const { organizationId, tenantContext } = resolveOrgContext(user, explicitOrganizationId);
    await this.findOne(user, id, explicitOrganizationId);
    await this.prisma.runInTenantContext(tenantContext, async (tx) => {
      await tx.installation.update({ where: { id }, data: { deletedAt: new Date() } });
      await this.auditLog.record(tx, {
        organizationId,
        actorUserId: user.sub,
        action: 'installations.delete',
        targetType: 'installation',
        targetId: id,
      });
    });
  }

  private async resolveScope(user: AccessTokenClaims) {
    return resolveInstallationScope(this.prisma, {
      memberId: user.memberId,
      roleCode: user.roleCode,
      isPlatformAdmin: user.isPlatformAdmin,
    });
  }

  /** 403 sin distinguir "no tienes permiso" de "no existe" (PERMISSIONS.md §9/§13). */
  private async assertInScope(user: AccessTokenClaims, installationId: string): Promise<void> {
    const scope = await this.resolveScope(user);
    if (scope !== 'all' && !scope.includes(installationId)) {
      throw new ForbiddenException('Installation is outside your assigned scope');
    }
  }
}
