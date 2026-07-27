import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { PrismaService } from '../../common/prisma/prisma.service';
import { AccessTokenClaims } from '../../common/guards/jwt-auth.guard';
import { resolveInstallationScope } from '../../common/permissions/installation-scope';

const MAX_RAW_RANGE_DAYS = 7; // API_DESIGN.md §8, NON_FUNCTIONAL_REQUIREMENTS.md §18

export type Granularity = 'raw' | 'hourly' | 'daily';

@Injectable()
export class ReadingsService {
  constructor(private readonly prisma: PrismaService) {}

  async getLatest(user: AccessTokenClaims, channelId: string) {
    const tenantContext = { userId: user.sub, organizationId: user.organizationId };
    await this.assertChannelInScope(user, channelId);
    const reading = await this.prisma.runInTenantContext(tenantContext, (tx) =>
      tx.latestReading.findUnique({
        where: { channelId },
        include: { channel: { select: { channelTypeCode: true } } },
      }),
    );
    if (!reading) {
      throw new NotFoundException('No reading recorded for this channel yet');
    }
    return this.flattenChannelTypeCode(reading);
  }

  async getLatestForInstallation(user: AccessTokenClaims, installationId: string) {
    const tenantContext = { userId: user.sub, organizationId: user.organizationId };
    const scope = await resolveInstallationScope(this.prisma, {
      memberId: user.memberId,
      roleCode: user.roleCode,
      isPlatformAdmin: user.isPlatformAdmin,
    });
    if (scope !== 'all' && !scope.includes(installationId)) {
      throw new ForbiddenException('Installation is outside your assigned scope');
    }
    const readings = await this.prisma.runInTenantContext(tenantContext, (tx) =>
      tx.latestReading.findMany({
        where: { channel: { sensor: { device: { zone: { installationId } } } } },
        include: { channel: { select: { channelTypeCode: true } } },
      }),
    );
    return readings.map((reading) => this.flattenChannelTypeCode(reading));
  }

  /**
   * OPENAPI.yaml documenta `channelTypeCode` como campo plano de
   * `LatestReading` (necesario para que el cliente muestre una etiqueta sin
   * una segunda llamada) — `latest_readings` no lo desnormaliza en columna
   * propia (DATA_MODEL.md), así que se aplana aquí desde el `include`.
   */
  private flattenChannelTypeCode<T extends { channel: { channelTypeCode: string } }>(
    reading: T,
  ): Omit<T, 'channel'> & { channelTypeCode: string } {
    const { channel, ...rest } = reading;
    return { ...rest, channelTypeCode: channel.channelTypeCode };
  }

  async getHistory(
    user: AccessTokenClaims,
    channelId: string,
    from: Date,
    to: Date,
    granularity: Granularity,
  ) {
    await this.assertChannelInScope(user, channelId);

    if (granularity === 'raw') {
      const rangeDays = (to.getTime() - from.getTime()) / (1000 * 60 * 60 * 24);
      if (rangeDays > MAX_RAW_RANGE_DAYS) {
        throw new BadRequestException(
          `granularity=raw is limited to ${MAX_RAW_RANGE_DAYS} days (API_DESIGN.md §8); use hourly or daily for longer ranges`,
        );
      }
      return this.prisma.$queryRaw`
        SELECT ts_origin AS "tsOrigin", value FROM telemetry
        WHERE channel_id = ${channelId}::uuid AND ts_origin BETWEEN ${from} AND ${to}
        ORDER BY ts_origin ASC
      `;
    }

    const tenantContext = { userId: user.sub, organizationId: user.organizationId };
    const channel = await this.prisma.runInTenantContext(tenantContext, (tx) =>
      tx.channel.findUniqueOrThrow({ where: { id: channelId }, include: { channelType: true } }),
    );
    const bucket = granularity === 'hourly' ? 'hour' : 'day';

    // MQTT_PROTOCOL.md §9 / DATA_MODEL.md: la función de agregación depende
    // del tipo de canal (media+min/max para continuous, suma para counter) —
    // nunca elegida por el cliente (API_DESIGN.md §8).
    if (channel.channelType.defaultAggregation === 'sum') {
      return this.prisma.$queryRaw`
        SELECT date_trunc(${bucket}, ts_origin) AS "tsOrigin", SUM(value) AS value
        FROM telemetry
        WHERE channel_id = ${channelId}::uuid AND ts_origin BETWEEN ${from} AND ${to}
        GROUP BY 1 ORDER BY 1 ASC
      `;
    }

    return this.prisma.$queryRaw`
      SELECT date_trunc(${bucket}, ts_origin) AS "tsOrigin",
             AVG(value) AS value, MIN(value) AS min, MAX(value) AS max
      FROM telemetry
      WHERE channel_id = ${channelId}::uuid AND ts_origin BETWEEN ${from} AND ${to}
      GROUP BY 1 ORDER BY 1 ASC
    `;
  }

  private async assertChannelInScope(user: AccessTokenClaims, channelId: string): Promise<void> {
    const tenantContext = { userId: user.sub, organizationId: user.organizationId };
    const channel = await this.prisma.runInTenantContext(tenantContext, (tx) =>
      tx.channel.findFirst({
        where: { id: channelId, deletedAt: null },
        include: { sensor: { include: { device: { include: { zone: true } } } } },
      }),
    );
    if (!channel) {
      throw new NotFoundException('Channel not found');
    }
    const scope = await resolveInstallationScope(this.prisma, {
      memberId: user.memberId,
      roleCode: user.roleCode,
      isPlatformAdmin: user.isPlatformAdmin,
    });
    if (scope !== 'all' && !scope.includes(channel.sensor.device.zone.installationId)) {
      throw new ForbiddenException('Installation is outside your assigned scope');
    }
  }
}
