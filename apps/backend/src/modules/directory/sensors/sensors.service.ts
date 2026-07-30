import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { Sensor } from '@prisma/client';
import { PrismaService } from '../../../common/prisma/prisma.service';
import { AuditLogService } from '../../../common/audit/audit-log.service';
import { AccessTokenClaims } from '../../../common/guards/jwt-auth.guard';
import { resolveInstallationScope } from '../../../common/permissions/installation-scope';
import { resolveOrgContext } from '../../../common/permissions/org-context';
import { SensorCreateDto } from './dto/sensor.dto';

/** FUNCTIONAL_REQUIREMENTS.md §7: un dispositivo tiene hasta 4 sensores (límite de negocio, no de BD). */
const MAX_SENSORS_PER_DEVICE = 4;

/** `explicitOrganizationId` (ADR-0005, `BACKLOG.md` #18) — ver `InstallationsService`. */
@Injectable()
export class SensorsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly auditLog: AuditLogService,
  ) {}

  async create(
    user: AccessTokenClaims,
    deviceId: string,
    dto: SensorCreateDto,
    explicitOrganizationId?: string,
  ): Promise<Sensor> {
    const { organizationId, tenantContext } = resolveOrgContext(user, explicitOrganizationId);
    const device = await this.prisma.runInTenantContext(tenantContext, (tx) =>
      tx.device.findFirst({
        where: { id: deviceId, deletedAt: null },
        include: { zone: true, _count: { select: { sensors: { where: { deletedAt: null } } } } },
      }),
    );
    if (!device) {
      throw new NotFoundException('Device not found');
    }
    await this.assertInScope(user, device.zone.installationId);

    if (device._count.sensors >= MAX_SENSORS_PER_DEVICE) {
      throw new BadRequestException(
        `Device already has the maximum of ${MAX_SENSORS_PER_DEVICE} sensors (FUNCTIONAL_REQUIREMENTS.md §7)`,
      );
    }

    return this.prisma.runInTenantContext(tenantContext, async (tx) => {
      const sensor = await tx.sensor.create({
        data: {
          organizationId,
          deviceId,
          externalIdentifier: dto.externalIdentifier,
          label: dto.label,
        },
      });
      await this.auditLog.record(tx, {
        organizationId,
        actorUserId: user.sub,
        action: 'sensors.create',
        targetType: 'sensor',
        targetId: sensor.id,
        metadata: { deviceId, label: dto.label },
      });
      return sensor;
    });
  }

  async findAllForDevice(
    user: AccessTokenClaims,
    deviceId: string,
    explicitOrganizationId?: string,
  ): Promise<Sensor[]> {
    const { tenantContext } = resolveOrgContext(user, explicitOrganizationId);
    const device = await this.prisma.runInTenantContext(tenantContext, (tx) =>
      tx.device.findFirst({ where: { id: deviceId, deletedAt: null }, include: { zone: true } }),
    );
    if (!device) {
      throw new NotFoundException('Device not found');
    }
    await this.assertInScope(user, device.zone.installationId);
    return this.prisma.runInTenantContext(tenantContext, (tx) =>
      tx.sensor.findMany({ where: { deviceId, deletedAt: null } }),
    );
  }

  async findOne(
    user: AccessTokenClaims,
    id: string,
    explicitOrganizationId?: string,
  ): Promise<Sensor> {
    const { organizationId, tenantContext } = resolveOrgContext(user, explicitOrganizationId);
    const sensor = await this.prisma.runInTenantContext(tenantContext, (tx) =>
      tx.sensor.findFirst({
        where: { id, organizationId, deletedAt: null },
        include: { device: { include: { zone: true } } },
      }),
    );
    if (!sensor) {
      throw new NotFoundException('Sensor not found');
    }
    await this.assertInScope(user, sensor.device.zone.installationId);
    return sensor;
  }

  async softDelete(
    user: AccessTokenClaims,
    id: string,
    explicitOrganizationId?: string,
  ): Promise<void> {
    await this.findOne(user, id, explicitOrganizationId);
    const { organizationId, tenantContext } = resolveOrgContext(user, explicitOrganizationId);
    await this.prisma.runInTenantContext(tenantContext, async (tx) => {
      await tx.sensor.update({ where: { id }, data: { deletedAt: new Date() } });
      await this.auditLog.record(tx, {
        organizationId,
        actorUserId: user.sub,
        action: 'sensors.delete',
        targetType: 'sensor',
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
