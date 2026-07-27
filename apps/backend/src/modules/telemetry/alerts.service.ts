import { ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { AlertStatus } from '@prisma/client';
import { PrismaService } from '../../common/prisma/prisma.service';
import { AccessTokenClaims } from '../../common/guards/jwt-auth.guard';
import { resolveInstallationScope } from '../../common/permissions/installation-scope';

@Injectable()
export class AlertsService {
  constructor(private readonly prisma: PrismaService) {}

  async findAll(user: AccessTokenClaims, status?: AlertStatus) {
    const tenantContext = { userId: user.sub, organizationId: user.organizationId };
    const scope = await resolveInstallationScope(this.prisma, {
      memberId: user.memberId,
      roleCode: user.roleCode,
      isPlatformAdmin: user.isPlatformAdmin,
    });

    // El alcance por instalación (PERMISSIONS.md §2) se aplica también a
    // alertas: se filtra a través de la cadena canal/dispositivo/gateway ->
    // zona -> instalación, según cuál de los tres esté presente.
    return this.prisma.runInTenantContext(tenantContext, (tx) =>
      tx.alert.findMany({
        where: {
          ...(status ? { status } : {}),
          ...(scope === 'all'
            ? {}
            : {
                OR: [
                  { channel: { sensor: { device: { zone: { installationId: { in: scope } } } } } },
                  { device: { zone: { installationId: { in: scope } } } },
                  { gateway: { installationId: { in: scope } } },
                ],
              }),
        },
        orderBy: { openedAt: 'desc' },
      }),
    );
  }

  async acknowledge(user: AccessTokenClaims, id: string) {
    return this.transition(user, id, 'acknowledged', {
      acknowledgedAt: new Date(),
      acknowledgedById: user.sub,
    });
  }

  async resolve(user: AccessTokenClaims, id: string) {
    return this.transition(user, id, 'resolved', {
      resolvedAt: new Date(),
      resolvedById: user.sub,
    });
  }

  private async transition(
    user: AccessTokenClaims,
    id: string,
    status: AlertStatus,
    extra: Record<string, unknown>,
  ) {
    const tenantContext = { userId: user.sub, organizationId: user.organizationId };
    const alert = await this.prisma.runInTenantContext(tenantContext, (tx) =>
      tx.alert.findUnique({ where: { id } }),
    );
    if (!alert) {
      throw new NotFoundException('Alert not found');
    }
    await this.assertAlertInScope(user, alert);
    return this.prisma.runInTenantContext(tenantContext, (tx) =>
      tx.alert.update({ where: { id }, data: { status, ...extra } }),
    );
  }

  private async assertAlertInScope(
    user: AccessTokenClaims,
    alert: { channelId: string | null; deviceId: string | null; gatewayId: string | null },
  ): Promise<void> {
    const scope = await resolveInstallationScope(this.prisma, {
      memberId: user.memberId,
      roleCode: user.roleCode,
      isPlatformAdmin: user.isPlatformAdmin,
    });
    if (scope === 'all') {
      return;
    }
    const tenantContext = { userId: user.sub, organizationId: user.organizationId };
    const installationId = await this.prisma.runInTenantContext(tenantContext, async (tx) => {
      if (alert.channelId) {
        const channel = await tx.channel.findUnique({
          where: { id: alert.channelId },
          include: { sensor: { include: { device: { include: { zone: true } } } } },
        });
        return channel?.sensor.device.zone.installationId;
      }
      if (alert.deviceId) {
        const device = await tx.device.findUnique({
          where: { id: alert.deviceId },
          include: { zone: true },
        });
        return device?.zone.installationId;
      }
      if (alert.gatewayId) {
        const gateway = await tx.gateway.findUnique({ where: { id: alert.gatewayId } });
        return gateway?.installationId;
      }
      return undefined;
    });

    if (!installationId || !scope.includes(installationId)) {
      throw new ForbiddenException('Alert is outside your assigned scope');
    }
  }
}
