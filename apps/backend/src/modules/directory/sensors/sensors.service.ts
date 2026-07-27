import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { Sensor } from '@prisma/client';
import { PrismaService } from '../../../common/prisma/prisma.service';
import { AccessTokenClaims } from '../../../common/guards/jwt-auth.guard';
import { resolveInstallationScope } from '../../../common/permissions/installation-scope';
import { SensorCreateDto } from './dto/sensor.dto';

/** FUNCTIONAL_REQUIREMENTS.md §7: un dispositivo tiene hasta 4 sensores (límite de negocio, no de BD). */
const MAX_SENSORS_PER_DEVICE = 4;

@Injectable()
export class SensorsService {
  constructor(private readonly prisma: PrismaService) {}

  async create(user: AccessTokenClaims, deviceId: string, dto: SensorCreateDto): Promise<Sensor> {
    const tenantContext = { userId: user.sub, organizationId: user.organizationId };
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

    return this.prisma.runInTenantContext(tenantContext, (tx) =>
      tx.sensor.create({
        data: {
          organizationId: user.organizationId!,
          deviceId,
          externalIdentifier: dto.externalIdentifier,
          label: dto.label,
        },
      }),
    );
  }

  async findAllForDevice(user: AccessTokenClaims, deviceId: string): Promise<Sensor[]> {
    const tenantContext = { userId: user.sub, organizationId: user.organizationId };
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

  async findOne(user: AccessTokenClaims, id: string): Promise<Sensor> {
    const tenantContext = { userId: user.sub, organizationId: user.organizationId };
    const sensor = await this.prisma.runInTenantContext(tenantContext, (tx) =>
      tx.sensor.findFirst({
        where: { id, deletedAt: null },
        include: { device: { include: { zone: true } } },
      }),
    );
    if (!sensor) {
      throw new NotFoundException('Sensor not found');
    }
    await this.assertInScope(user, sensor.device.zone.installationId);
    return sensor;
  }

  async softDelete(user: AccessTokenClaims, id: string): Promise<void> {
    await this.findOne(user, id);
    const tenantContext = { userId: user.sub, organizationId: user.organizationId };
    await this.prisma.runInTenantContext(tenantContext, (tx) =>
      tx.sensor.update({ where: { id }, data: { deletedAt: new Date() } }),
    );
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
