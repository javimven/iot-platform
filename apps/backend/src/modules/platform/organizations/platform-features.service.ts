import { Injectable } from '@nestjs/common';
import { OrganizationFeature } from '@prisma/client';
import { PrismaService } from '../../../common/prisma/prisma.service';
import { AuditLogService } from '../../../common/audit/audit-log.service';
import { FeatureUpdateItem } from './dto/organization-feature-update.dto';

/** PERMISSIONS.md §14: feature flags por organización, gestión exclusiva del Admin de plataforma. */
@Injectable()
export class PlatformFeaturesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly auditLog: AuditLogService,
  ) {}

  async getForOrganization(organizationId: string): Promise<OrganizationFeature[]> {
    return this.prisma.runInTenantContext({ isPlatformAdmin: true }, (tx) =>
      tx.organizationFeature.findMany({ where: { organizationId } }),
    );
  }

  async setForOrganization(
    actorUserId: string,
    organizationId: string,
    updates: FeatureUpdateItem[],
  ): Promise<void> {
    await this.prisma.runInTenantContext(
      { userId: actorUserId, isPlatformAdmin: true },
      async (tx) => {
        for (const update of updates) {
          await tx.organizationFeature.upsert({
            where: {
              organizationId_featureCode: { organizationId, featureCode: update.featureCode },
            },
            create: {
              organizationId,
              featureCode: update.featureCode,
              enabled: update.enabled,
              updatedById: actorUserId,
            },
            update: { enabled: update.enabled, updatedById: actorUserId },
          });
        }
        await this.auditLog.record(tx, {
          organizationId,
          actorUserId,
          action: 'org_features.update',
          targetType: 'organization',
          targetId: organizationId,
          metadata: { updates },
        });
      },
    );
  }
}
