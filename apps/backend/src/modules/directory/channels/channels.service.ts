import { ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { Channel } from '@prisma/client';
import { PrismaService } from '../../../common/prisma/prisma.service';
import { AuditLogService } from '../../../common/audit/audit-log.service';
import { AccessTokenClaims } from '../../../common/guards/jwt-auth.guard';
import { resolveInstallationScope } from '../../../common/permissions/installation-scope';
import { resolveOrgContext } from '../../../common/permissions/org-context';
import { ChannelUpdateThresholdDto } from './dto/channel.dto';

/**
 * Los canales se crean automáticamente al ingerir el primer mensaje válido
 * (MQTT_PROTOCOL.md §9, aún no implementado en este paso de la Etapa 13) —
 * este servicio solo cubre lectura y ajuste del umbral (override sobre el
 * valor por defecto de la organización, `org_channel_thresholds`).
 *
 * `explicitOrganizationId` (ADR-0005, `BACKLOG.md` #18) — ver `InstallationsService`.
 */
@Injectable()
export class ChannelsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly auditLog: AuditLogService,
  ) {}

  async findAllForSensor(
    user: AccessTokenClaims,
    sensorId: string,
    explicitOrganizationId?: string,
  ): Promise<Channel[]> {
    const { tenantContext } = resolveOrgContext(user, explicitOrganizationId);
    const sensor = await this.prisma.runInTenantContext(tenantContext, (tx) =>
      tx.sensor.findFirst({
        where: { id: sensorId, deletedAt: null },
        include: { device: { include: { zone: true } } },
      }),
    );
    if (!sensor) {
      throw new NotFoundException('Sensor not found');
    }
    await this.assertInScope(user, sensor.device.zone.installationId);
    return this.prisma.runInTenantContext(tenantContext, (tx) =>
      tx.channel.findMany({ where: { sensorId, deletedAt: null } }),
    );
  }

  async updateThreshold(
    user: AccessTokenClaims,
    id: string,
    dto: ChannelUpdateThresholdDto,
    explicitOrganizationId?: string,
  ): Promise<Channel> {
    const { organizationId, tenantContext } = resolveOrgContext(user, explicitOrganizationId);
    const channel = await this.prisma.runInTenantContext(tenantContext, (tx) =>
      tx.channel.findFirst({
        where: { id, deletedAt: null },
        include: { sensor: { include: { device: { include: { zone: true } } } } },
      }),
    );
    if (!channel) {
      throw new NotFoundException('Channel not found');
    }
    await this.assertInScope(user, channel.sensor.device.zone.installationId);

    return this.prisma.runInTenantContext(tenantContext, async (tx) => {
      const updated = await tx.channel.update({
        where: { id },
        data: {
          alertThresholdMin: dto.alertThresholdMin,
          alertThresholdMax: dto.alertThresholdMax,
        },
      });
      await this.auditLog.record(tx, {
        organizationId,
        actorUserId: user.sub,
        action: 'channels.update_threshold',
        targetType: 'channel',
        targetId: id,
        metadata: { ...dto },
      });
      return updated;
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
