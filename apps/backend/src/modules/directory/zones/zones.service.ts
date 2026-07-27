import { ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { Zone } from '@prisma/client';
import { PrismaService } from '../../../common/prisma/prisma.service';
import { AccessTokenClaims } from '../../../common/guards/jwt-auth.guard';
import { resolveInstallationScope } from '../../../common/permissions/installation-scope';
import { ZoneCreateDto, ZoneUpdateDto } from './dto/zone.dto';

@Injectable()
export class ZonesService {
  constructor(private readonly prisma: PrismaService) {}

  async create(user: AccessTokenClaims, installationId: string, dto: ZoneCreateDto): Promise<Zone> {
    await this.assertInstallationInScope(user, installationId);
    return this.prisma.runInTenantContext(
      { userId: user.sub, organizationId: user.organizationId },
      (tx) =>
        tx.zone.create({
          data: { installationId, organizationId: user.organizationId!, ...dto },
        }),
    );
  }

  async findAllForInstallation(user: AccessTokenClaims, installationId: string): Promise<Zone[]> {
    await this.assertInstallationInScope(user, installationId);
    return this.prisma.runInTenantContext(
      { userId: user.sub, organizationId: user.organizationId },
      (tx) =>
        tx.zone.findMany({ where: { installationId, deletedAt: null }, orderBy: { name: 'asc' } }),
    );
  }

  async findOne(user: AccessTokenClaims, id: string): Promise<Zone> {
    const zone = await this.prisma.runInTenantContext(
      { userId: user.sub, organizationId: user.organizationId },
      (tx) => tx.zone.findFirst({ where: { id, deletedAt: null } }),
    );
    if (!zone) {
      throw new NotFoundException('Zone not found');
    }
    await this.assertInstallationInScope(user, zone.installationId);
    return zone;
  }

  async update(user: AccessTokenClaims, id: string, dto: ZoneUpdateDto): Promise<Zone> {
    await this.findOne(user, id);
    return this.prisma.runInTenantContext(
      { userId: user.sub, organizationId: user.organizationId },
      (tx) => tx.zone.update({ where: { id }, data: dto }),
    );
  }

  async softDelete(user: AccessTokenClaims, id: string): Promise<void> {
    await this.findOne(user, id);
    await this.prisma.runInTenantContext(
      { userId: user.sub, organizationId: user.organizationId },
      (tx) => tx.zone.update({ where: { id }, data: { deletedAt: new Date() } }),
    );
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
