import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { Device } from '@prisma/client';
import { PrismaService } from '../../../common/prisma/prisma.service';
import { AuditLogService } from '../../../common/audit/audit-log.service';
import { AccessTokenClaims } from '../../../common/guards/jwt-auth.guard';
import { resolveInstallationScope } from '../../../common/permissions/installation-scope';
import { resolveOrgContext } from '../../../common/permissions/org-context';
import { DeviceCreateDto, DeviceUpdateDto } from './dto/device.dto';

/**
 * Un dispositivo (hasta 4 sensores, FUNCTIONAL_REQUIREMENTS.md §7) se asocia
 * a un gateway y a una zona. Regla de integridad Zona<->Gateway
 * (DATA_MODEL.md §4): se valida aquí en la capa de aplicación (mensaje de
 * error claro, 400) *antes* de intentar el INSERT — el trigger de Postgres
 * (migration 0002) es el respaldo de última línea, no la experiencia de
 * usuario principal.
 *
 * `explicitOrganizationId` (ADR-0005, `BACKLOG.md` #18) — ver `InstallationsService`.
 */
@Injectable()
export class DevicesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly auditLog: AuditLogService,
  ) {}

  async create(
    user: AccessTokenClaims,
    gatewayId: string,
    dto: DeviceCreateDto,
    explicitOrganizationId?: string,
  ): Promise<Device> {
    const { organizationId, tenantContext } = resolveOrgContext(user, explicitOrganizationId);

    const [gateway, zone] = await this.prisma.runInTenantContext(tenantContext, (tx) =>
      Promise.all([
        tx.gateway.findFirst({ where: { id: gatewayId, deletedAt: null } }),
        tx.zone.findFirst({ where: { id: dto.zoneId, deletedAt: null } }),
      ]),
    );
    if (!gateway) {
      throw new NotFoundException('Gateway not found');
    }
    if (!zone) {
      throw new NotFoundException('Zone not found');
    }
    await this.assertInScope(user, gateway.installationId);
    if (zone.installationId !== gateway.installationId) {
      throw new BadRequestException(
        'device.zoneId must belong to the same installation as the gateway (DATA_MODEL.md §4)',
      );
    }

    return this.prisma.runInTenantContext(tenantContext, async (tx) => {
      const device = await tx.device.create({
        data: {
          organizationId,
          gatewayId,
          zoneId: dto.zoneId,
          externalIdentifier: dto.externalIdentifier,
          name: dto.name,
        },
      });
      await this.auditLog.record(tx, {
        organizationId,
        actorUserId: user.sub,
        action: 'devices.create',
        targetType: 'device',
        targetId: device.id,
        metadata: { name: device.name, gatewayId, zoneId: dto.zoneId },
      });
      return device;
    });
  }

  async findAllForGateway(
    user: AccessTokenClaims,
    gatewayId: string,
    explicitOrganizationId?: string,
  ): Promise<Device[]> {
    const { tenantContext } = resolveOrgContext(user, explicitOrganizationId);
    const gateway = await this.prisma.runInTenantContext(tenantContext, (tx) =>
      tx.gateway.findFirst({ where: { id: gatewayId, deletedAt: null } }),
    );
    if (!gateway) {
      throw new NotFoundException('Gateway not found');
    }
    await this.assertInScope(user, gateway.installationId);
    return this.prisma.runInTenantContext(tenantContext, (tx) =>
      tx.device.findMany({ where: { gatewayId, deletedAt: null }, orderBy: { name: 'asc' } }),
    );
  }

  async findOne(
    user: AccessTokenClaims,
    id: string,
    explicitOrganizationId?: string,
  ): Promise<Device> {
    const { tenantContext } = resolveOrgContext(user, explicitOrganizationId);
    const device = await this.prisma.runInTenantContext(tenantContext, (tx) =>
      tx.device.findFirst({ where: { id, deletedAt: null }, include: { zone: true } }),
    );
    if (!device) {
      throw new NotFoundException('Device not found');
    }
    await this.assertInScope(user, device.zone.installationId);
    return device;
  }

  async update(
    user: AccessTokenClaims,
    id: string,
    dto: DeviceUpdateDto,
    explicitOrganizationId?: string,
  ): Promise<Device> {
    const { organizationId, tenantContext } = resolveOrgContext(user, explicitOrganizationId);
    const device = await this.findOne(user, id, explicitOrganizationId);

    if (dto.zoneId) {
      const [gateway, zone] = await this.prisma.runInTenantContext(tenantContext, (tx) =>
        Promise.all([
          tx.gateway.findUniqueOrThrow({ where: { id: device.gatewayId } }),
          tx.zone.findFirst({ where: { id: dto.zoneId, deletedAt: null } }),
        ]),
      );
      if (!zone) {
        throw new NotFoundException('Zone not found');
      }
      if (zone.installationId !== gateway.installationId) {
        throw new BadRequestException(
          'device.zoneId must belong to the same installation as the gateway (DATA_MODEL.md §4)',
        );
      }
    }

    return this.prisma.runInTenantContext(tenantContext, async (tx) => {
      const updated = await tx.device.update({ where: { id }, data: dto });
      await this.auditLog.record(tx, {
        organizationId,
        actorUserId: user.sub,
        action: 'devices.update',
        targetType: 'device',
        targetId: id,
        metadata: { ...dto },
      });
      return updated;
    });
  }

  async disable(
    user: AccessTokenClaims,
    id: string,
    explicitOrganizationId?: string,
  ): Promise<void> {
    await this.findOne(user, id, explicitOrganizationId);
    const { organizationId, tenantContext } = resolveOrgContext(user, explicitOrganizationId);
    await this.prisma.runInTenantContext(tenantContext, async (tx) => {
      await tx.device.update({ where: { id }, data: { status: 'disabled' } });
      await this.auditLog.record(tx, {
        organizationId,
        actorUserId: user.sub,
        action: 'devices.disable',
        targetType: 'device',
        targetId: id,
      });
    });
  }

  private async assertInScope(user: AccessTokenClaims, installationId: string): Promise<void> {
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
