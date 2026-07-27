import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { Device } from '@prisma/client';
import { PrismaService } from '../../../common/prisma/prisma.service';
import { AccessTokenClaims } from '../../../common/guards/jwt-auth.guard';
import { resolveInstallationScope } from '../../../common/permissions/installation-scope';
import { DeviceCreateDto, DeviceUpdateDto } from './dto/device.dto';

/**
 * Un dispositivo (hasta 4 sensores, FUNCTIONAL_REQUIREMENTS.md §7) se asocia
 * a un gateway y a una zona. Regla de integridad Zona<->Gateway
 * (DATA_MODEL.md §4): se valida aquí en la capa de aplicación (mensaje de
 * error claro, 400) *antes* de intentar el INSERT — el trigger de Postgres
 * (migration 0002) es el respaldo de última línea, no la experiencia de
 * usuario principal.
 */
@Injectable()
export class DevicesService {
  constructor(private readonly prisma: PrismaService) {}

  async create(user: AccessTokenClaims, gatewayId: string, dto: DeviceCreateDto): Promise<Device> {
    const tenantContext = { userId: user.sub, organizationId: user.organizationId };

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

    return this.prisma.runInTenantContext(tenantContext, (tx) =>
      tx.device.create({
        data: {
          organizationId: user.organizationId!,
          gatewayId,
          zoneId: dto.zoneId,
          externalIdentifier: dto.externalIdentifier,
          name: dto.name,
        },
      }),
    );
  }

  async findAllForGateway(user: AccessTokenClaims, gatewayId: string): Promise<Device[]> {
    const tenantContext = { userId: user.sub, organizationId: user.organizationId };
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

  async findOne(user: AccessTokenClaims, id: string): Promise<Device> {
    const tenantContext = { userId: user.sub, organizationId: user.organizationId };
    const device = await this.prisma.runInTenantContext(tenantContext, (tx) =>
      tx.device.findFirst({ where: { id, deletedAt: null }, include: { zone: true } }),
    );
    if (!device) {
      throw new NotFoundException('Device not found');
    }
    await this.assertInScope(user, device.zone.installationId);
    return device;
  }

  async update(user: AccessTokenClaims, id: string, dto: DeviceUpdateDto): Promise<Device> {
    const tenantContext = { userId: user.sub, organizationId: user.organizationId };
    const device = await this.findOne(user, id);

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

    return this.prisma.runInTenantContext(tenantContext, (tx) =>
      tx.device.update({ where: { id }, data: dto }),
    );
  }

  async disable(user: AccessTokenClaims, id: string): Promise<void> {
    await this.findOne(user, id);
    const tenantContext = { userId: user.sub, organizationId: user.organizationId };
    await this.prisma.runInTenantContext(tenantContext, (tx) =>
      tx.device.update({ where: { id }, data: { status: 'disabled' } }),
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
