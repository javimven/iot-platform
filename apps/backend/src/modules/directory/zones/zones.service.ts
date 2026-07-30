import { ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { Zone } from '@prisma/client';
import { PrismaService } from '../../../common/prisma/prisma.service';
import { AuditLogService } from '../../../common/audit/audit-log.service';
import { AccessTokenClaims } from '../../../common/guards/jwt-auth.guard';
import { resolveInstallationScope } from '../../../common/permissions/installation-scope';
import { resolveOrgContext } from '../../../common/permissions/org-context';
import { ZoneCreateDto, ZoneUpdateDto } from './dto/zone.dto';

/** `explicitOrganizationId` (ADR-0005, `BACKLOG.md` #18) — ver `InstallationsService`. */
@Injectable()
export class ZonesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly auditLog: AuditLogService,
  ) {}

  async create(
    user: AccessTokenClaims,
    installationId: string,
    dto: ZoneCreateDto,
    explicitOrganizationId?: string,
  ): Promise<Zone> {
    const { organizationId, tenantContext } = resolveOrgContext(user, explicitOrganizationId);
    await this.assertInstallationInScope(user, installationId);
    return this.prisma.runInTenantContext(tenantContext, async (tx) => {
      const zone = await tx.zone.create({
        data: { installationId, organizationId, ...dto },
      });
      await this.auditLog.record(tx, {
        organizationId,
        actorUserId: user.sub,
        action: 'zones.create',
        targetType: 'zone',
        targetId: zone.id,
        metadata: { name: zone.name, installationId },
      });
      return zone;
    });
  }

  async findAllForInstallation(
    user: AccessTokenClaims,
    installationId: string,
    explicitOrganizationId?: string,
  ): Promise<Zone[]> {
    const { tenantContext } = resolveOrgContext(user, explicitOrganizationId);
    await this.assertInstallationInScope(user, installationId);
    return this.prisma.runInTenantContext(tenantContext, (tx) =>
      tx.zone.findMany({ where: { installationId, deletedAt: null }, orderBy: { name: 'asc' } }),
    );
  }

  async findOne(
    user: AccessTokenClaims,
    id: string,
    explicitOrganizationId?: string,
  ): Promise<Zone> {
    const { tenantContext } = resolveOrgContext(user, explicitOrganizationId);
    const zone = await this.prisma.runInTenantContext(tenantContext, (tx) =>
      tx.zone.findFirst({ where: { id, deletedAt: null } }),
    );
    if (!zone) {
      throw new NotFoundException('Zone not found');
    }
    await this.assertInstallationInScope(user, zone.installationId);
    return zone;
  }

  async update(
    user: AccessTokenClaims,
    id: string,
    dto: ZoneUpdateDto,
    explicitOrganizationId?: string,
  ): Promise<Zone> {
    const { organizationId, tenantContext } = resolveOrgContext(user, explicitOrganizationId);
    await this.findOne(user, id, explicitOrganizationId);
    return this.prisma.runInTenantContext(tenantContext, async (tx) => {
      const zone = await tx.zone.update({ where: { id }, data: dto });
      await this.auditLog.record(tx, {
        organizationId,
        actorUserId: user.sub,
        action: 'zones.update',
        targetType: 'zone',
        targetId: id,
        metadata: { ...dto },
      });
      return zone;
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
      await tx.zone.update({ where: { id }, data: { deletedAt: new Date() } });
      await this.auditLog.record(tx, {
        organizationId,
        actorUserId: user.sub,
        action: 'zones.delete',
        targetType: 'zone',
        targetId: id,
      });
    });
  }

  private async assertInstallationInScope(
    user: AccessTokenClaims,
    installationId: string,
  ): Promise<void> {
    const scope = await resolveInstallationScope(this.prisma, {
      memberId: user.memberId,
      roleCode: user.roleCode,
      isPlatformAdmin: user.isPlatformAdmin,
    });
    if (scope !== 'all' && !scope.includes(installationId)) {
      throw new ForbiddenException('Installation is outside your assigned scope');
    }
  }
}
