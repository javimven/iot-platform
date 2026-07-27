import { ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { Installation } from '@prisma/client';
import { PrismaService } from '../../../common/prisma/prisma.service';
import { AccessTokenClaims } from '../../../common/guards/jwt-auth.guard';
import {
  resolveInstallationScope,
  scopeWhereClause,
} from '../../../common/permissions/installation-scope';
import { InstallationCreateDto, InstallationUpdateDto } from './dto/installation.dto';

/**
 * Instalaciones (FUNCTIONAL_REQUIREMENTS.md §5, PERMISSIONS.md §2). El
 * alcance por instalación se resuelve y aplica aquí, no en RLS — es una
 * regla de autorización de aplicación (PERMISSIONS.md §2, ya documentado),
 * distinta del aislamiento multitenant (que sí es RLS, DATA_MODEL.md §7).
 */
@Injectable()
export class InstallationsService {
  constructor(private readonly prisma: PrismaService) {}

  async create(user: AccessTokenClaims, dto: InstallationCreateDto): Promise<Installation> {
    return this.prisma.runInTenantContext(
      { userId: user.sub, organizationId: user.organizationId },
      (tx) =>
        tx.installation.create({
          data: { organizationId: user.organizationId!, ...dto },
        }),
    );
  }

  async findAll(user: AccessTokenClaims): Promise<Installation[]> {
    const scope = await this.resolveScope(user);
    return this.prisma.runInTenantContext(
      { userId: user.sub, organizationId: user.organizationId },
      (tx) =>
        tx.installation.findMany({
          where: { deletedAt: null, ...scopeWhereClause(scope, 'id') },
          orderBy: { name: 'asc' },
        }),
    );
  }

  async findOne(user: AccessTokenClaims, id: string): Promise<Installation> {
    const installation = await this.prisma.runInTenantContext(
      { userId: user.sub, organizationId: user.organizationId },
      (tx) => tx.installation.findFirst({ where: { id, deletedAt: null } }),
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
  ): Promise<Installation> {
    await this.findOne(user, id); // valida existencia + alcance
    return this.prisma.runInTenantContext(
      { userId: user.sub, organizationId: user.organizationId },
      (tx) => tx.installation.update({ where: { id }, data: dto }),
    );
  }

  async softDelete(user: AccessTokenClaims, id: string): Promise<void> {
    await this.findOne(user, id);
    await this.prisma.runInTenantContext(
      { userId: user.sub, organizationId: user.organizationId },
      (tx) => tx.installation.update({ where: { id }, data: { deletedAt: new Date() } }),
    );
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
