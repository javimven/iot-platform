import { Injectable } from '@nestjs/common';
import { Organization, OrganizationFeature } from '@prisma/client';
import { PrismaService } from '../../../common/prisma/prisma.service';
import { AuditLogService } from '../../../common/audit/audit-log.service';
import { AccessTokenClaims } from '../../../common/guards/jwt-auth.guard';
import { OrganizationUpdateDto } from './dto/organization.dto';

/** Perfil de la organización activa (org.profile.read/update, PERMISSIONS.md §4). */
@Injectable()
export class OrganizationsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly auditLog: AuditLogService,
  ) {}

  async getProfile(user: AccessTokenClaims): Promise<Organization> {
    return this.prisma.runInTenantContext(
      { userId: user.sub, organizationId: user.organizationId },
      (tx) => tx.organization.findUniqueOrThrow({ where: { id: user.organizationId! } }),
    );
  }

  async updateProfile(user: AccessTokenClaims, dto: OrganizationUpdateDto): Promise<Organization> {
    return this.prisma.runInTenantContext(
      { userId: user.sub, organizationId: user.organizationId },
      async (tx) => {
        const updated = await tx.organization.update({
          where: { id: user.organizationId! },
          data: dto,
        });
        await this.auditLog.record(tx, {
          organizationId: user.organizationId,
          actorUserId: user.sub,
          action: 'org.profile.update',
          targetType: 'organization',
          targetId: user.organizationId,
          metadata: { ...dto },
        });
        return updated;
      },
    );
  }

  async getFeatures(user: AccessTokenClaims): Promise<OrganizationFeature[]> {
    return this.prisma.runInTenantContext(
      { userId: user.sub, organizationId: user.organizationId },
      (tx) => tx.organizationFeature.findMany({ where: { organizationId: user.organizationId! } }),
    );
  }
}
