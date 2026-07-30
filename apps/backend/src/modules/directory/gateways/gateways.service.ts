import { randomBytes } from 'node:crypto';
import { ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { Gateway } from '@prisma/client';
import { PrismaService } from '../../../common/prisma/prisma.service';
import { AuditLogService } from '../../../common/audit/audit-log.service';
import { AccessTokenClaims } from '../../../common/guards/jwt-auth.guard';
import {
  resolveInstallationScope,
  scopeWhereClause,
} from '../../../common/permissions/installation-scope';
import { resolveOrgContext } from '../../../common/permissions/org-context';
import {
  generateOpaqueSecret,
  hashOpaqueSecret,
} from '../../../common/security/opaque-secret.util';
import { GatewayCreateDto, GatewayUpdateDto } from './dto/gateway.dto';

export interface GatewayWithCredential extends Gateway {
  credentialUsername: string;
  credentialSecret: string;
}

/**
 * Gateways = unidad de conexión MQTT (ADR-0004: concentrador LoRa o estación
 * directa). El secreto de la credencial solo se devuelve en la creación y en
 * la rotación (API_DESIGN.md §7) — nunca se puede recuperar después, solo
 * rotar. Las acciones que mutan quedan auditadas (nunca el secreto en sí,
 * solo el nombre de usuario de la credencial) — ver `InstallationsService`.
 */
@Injectable()
export class GatewaysService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly auditLog: AuditLogService,
  ) {}

  async create(
    user: AccessTokenClaims,
    dto: GatewayCreateDto,
    explicitOrganizationId?: string,
  ): Promise<GatewayWithCredential> {
    const { organizationId, tenantContext } = resolveOrgContext(user, explicitOrganizationId);
    await this.assertInstallationInScope(user, dto.installationId, explicitOrganizationId);

    const externalIdentifier = `gw-${randomBytes(8).toString('hex')}`;
    const secret = generateOpaqueSecret();

    const gateway = await this.prisma.runInTenantContext(tenantContext, async (tx) => {
      const created = await tx.gateway.create({
        data: {
          organizationId,
          installationId: dto.installationId,
          name: dto.name,
          connectivityType: dto.connectivityType,
          externalIdentifier,
          credentials: { create: { secretHash: hashOpaqueSecret(secret) } },
        },
      });
      await this.auditLog.record(tx, {
        organizationId,
        actorUserId: user.sub,
        action: 'gateways.create',
        targetType: 'gateway',
        targetId: created.id,
        metadata: { name: created.name, installationId: dto.installationId },
      });
      return created;
    });

    return { ...gateway, credentialUsername: externalIdentifier, credentialSecret: secret };
  }

  async findAll(user: AccessTokenClaims, explicitOrganizationId?: string): Promise<Gateway[]> {
    const { organizationId, tenantContext } = resolveOrgContext(user, explicitOrganizationId);
    const scope = await this.resolveScope(user, explicitOrganizationId);
    return this.prisma.runInTenantContext(tenantContext, (tx) =>
      tx.gateway.findMany({
        where: { organizationId, deletedAt: null, ...scopeWhereClause(scope, 'installationId') },
        orderBy: { name: 'asc' },
      }),
    );
  }

  async findOne(
    user: AccessTokenClaims,
    id: string,
    explicitOrganizationId?: string,
  ): Promise<Gateway> {
    const { organizationId, tenantContext } = resolveOrgContext(user, explicitOrganizationId);
    const gateway = await this.prisma.runInTenantContext(tenantContext, (tx) =>
      tx.gateway.findFirst({ where: { id, organizationId, deletedAt: null } }),
    );
    if (!gateway) {
      throw new NotFoundException('Gateway not found');
    }
    await this.assertInstallationInScope(user, gateway.installationId, explicitOrganizationId);
    return gateway;
  }

  async update(
    user: AccessTokenClaims,
    id: string,
    dto: GatewayUpdateDto,
    explicitOrganizationId?: string,
  ): Promise<Gateway> {
    const { organizationId, tenantContext } = resolveOrgContext(user, explicitOrganizationId);
    await this.findOne(user, id, explicitOrganizationId);
    return this.prisma.runInTenantContext(tenantContext, async (tx) => {
      const gateway = await tx.gateway.update({ where: { id }, data: dto });
      await this.auditLog.record(tx, {
        organizationId,
        actorUserId: user.sub,
        action: 'gateways.update',
        targetType: 'gateway',
        targetId: id,
        metadata: { ...dto },
      });
      return gateway;
    });
  }

  async disable(
    user: AccessTokenClaims,
    id: string,
    explicitOrganizationId?: string,
  ): Promise<void> {
    const { organizationId, tenantContext } = resolveOrgContext(user, explicitOrganizationId);
    await this.findOne(user, id, explicitOrganizationId);
    await this.prisma.runInTenantContext(tenantContext, async (tx) => {
      await tx.gateway.update({ where: { id }, data: { status: 'disabled' } });
      await this.auditLog.record(tx, {
        organizationId,
        actorUserId: user.sub,
        action: 'gateways.disable',
        targetType: 'gateway',
        targetId: id,
      });
    });
  }

  /** Revoca la credencial activa y emite una nueva (rotación, API_DESIGN.md §7). */
  async rotateCredential(
    user: AccessTokenClaims,
    id: string,
    explicitOrganizationId?: string,
  ): Promise<GatewayWithCredential> {
    const { organizationId, tenantContext } = resolveOrgContext(user, explicitOrganizationId);
    const gateway = await this.findOne(user, id, explicitOrganizationId);
    const secret = generateOpaqueSecret();

    await this.prisma.runInTenantContext(tenantContext, async (tx) => {
      await tx.gatewayCredential.updateMany({
        where: { gatewayId: id, status: 'active' },
        data: { status: 'revoked', revokedAt: new Date() },
      });
      await tx.gatewayCredential.create({
        data: { gatewayId: id, secretHash: hashOpaqueSecret(secret) },
      });
      await this.auditLog.record(tx, {
        organizationId,
        actorUserId: user.sub,
        action: 'gateways.rotate_credential',
        targetType: 'gateway',
        targetId: id,
        metadata: { credentialUsername: gateway.externalIdentifier },
      });
    });

    return { ...gateway, credentialUsername: gateway.externalIdentifier, credentialSecret: secret };
  }

  private async resolveScope(user: AccessTokenClaims, explicitOrganizationId?: string) {
    if (explicitOrganizationId) {
      return 'all' as const; // Admin de plataforma: sin alcance por instalación (PERMISSIONS.md §2)
    }
    return resolveInstallationScope(this.prisma, {
      memberId: user.memberId,
      roleCode: user.roleCode,
      isPlatformAdmin: user.isPlatformAdmin,
    });
  }

  private async assertInstallationInScope(
    user: AccessTokenClaims,
    installationId: string,
    explicitOrganizationId?: string,
  ): Promise<void> {
    const scope = await this.resolveScope(user, explicitOrganizationId);
    if (scope !== 'all' && !scope.includes(installationId)) {
      throw new ForbiddenException('Installation is outside your assigned scope');
    }
  }
}
