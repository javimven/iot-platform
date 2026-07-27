import { Injectable, Logger } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../../common/prisma/prisma.service';
import { TelemetryJobPayload } from '../../common/queues/telemetry-queue';

/**
 * Procesamiento de un mensaje de telemetría ya validado (un job = un mensaje
 * MQTT, sección "cola de telemetría"). Corre en el proceso `worker`
 * (ARCHITECTURE.md §5). Cubre, en este orden:
 *  1. Actualizar last_seen_at de gateway/dispositivo (señal de vida).
 *  2. Deduplicar e insertar cada lectura en `telemetry`.
 *  3. Actualizar `latest_readings` solo si es más reciente (tolerancia al desorden).
 *  4. Evaluar el umbral de cada canal y abrir/mantener/auto-resolver su alerta.
 */
@Injectable()
export class TelemetryProcessingService {
  private readonly logger = new Logger(TelemetryProcessingService.name);

  constructor(private readonly prisma: PrismaService) {}

  async processMessage(payload: TelemetryJobPayload): Promise<void> {
    const tsOrigin = new Date(payload.tsOrigin);

    await this.prisma.runInTenantContext({ organizationId: payload.organizationId }, async (tx) => {
      await this.touchLastSeen(tx, payload.gatewayId, payload.deviceId);

      for (const reading of payload.readings) {
        const isNew = await this.insertTelemetryIfNew(tx, {
          channelId: reading.channelId,
          organizationId: payload.organizationId,
          tsOrigin,
          value: reading.value,
          messageId: payload.messageId,
        });

        if (!isNew) {
          // Repetición de un mensaje ya procesado (MQTT_PROTOCOL.md §11) —
          // idempotente por diseño: cero efectos secundarios adicionales.
          this.logger.debug(`[${payload.correlationId}] duplicate reading ignored`);
          continue;
        }

        await this.updateLatestReadingIfNewer(tx, {
          channelId: reading.channelId,
          organizationId: payload.organizationId,
          value: reading.value,
          tsOrigin,
        });

        await this.evaluateThreshold(tx, reading.channelId, payload.organizationId, reading.value);
      }
    });
  }

  /**
   * Marca gateway/dispositivo como online y auto-resuelve cualquier alerta de
   * offline abierta (MQTT_PROTOCOL.md §8: "la reconexión resuelve
   * automáticamente esa alerta concreta").
   */
  private async touchLastSeen(
    tx: Prisma.TransactionClient,
    gatewayId: string,
    deviceId: string,
  ): Promise<void> {
    const now = new Date();
    await Promise.all([
      tx.gateway.update({ where: { id: gatewayId }, data: { lastSeenAt: now, status: 'online' } }),
      tx.device.update({ where: { id: deviceId }, data: { lastSeenAt: now, status: 'online' } }),
      tx.alert.updateMany({
        where: { gatewayId, alertType: 'offline', status: { not: 'resolved' } },
        data: { status: 'resolved', resolvedAt: now },
      }),
      tx.alert.updateMany({
        where: { deviceId, alertType: 'offline', status: { not: 'resolved' } },
        data: { status: 'resolved', resolvedAt: now },
      }),
    ]);
  }

  /** `true` si la fila era nueva; `false` si ya existía (duplicado, DATA_MODEL.md §5). */
  private async insertTelemetryIfNew(
    tx: Prisma.TransactionClient,
    reading: {
      channelId: string;
      organizationId: string;
      tsOrigin: Date;
      value: number;
      messageId?: string;
    },
  ): Promise<boolean> {
    const result = await tx.telemetry.createMany({
      data: [reading],
      skipDuplicates: true, // ON CONFLICT DO NOTHING sobre la PK (channel_id, ts_origin)
    });
    return result.count === 1;
  }

  private async updateLatestReadingIfNewer(
    tx: Prisma.TransactionClient,
    reading: { channelId: string; organizationId: string; value: number; tsOrigin: Date },
  ): Promise<void> {
    // "Solo si es más reciente" no se expresa con el upsert fluido de Prisma
    // (DATA_MODEL.md §5) — SQL crudo parametrizado (bind params, no
    // interpolación de texto — SECURITY.md §1).
    await tx.$executeRaw`
      INSERT INTO latest_readings (channel_id, organization_id, value, ts_origin, ts_received, updated_at)
      VALUES (${reading.channelId}::uuid, ${reading.organizationId}::uuid, ${reading.value}, ${reading.tsOrigin}, now(), now())
      ON CONFLICT (channel_id) DO UPDATE
        SET value = EXCLUDED.value,
            ts_origin = EXCLUDED.ts_origin,
            ts_received = EXCLUDED.ts_received,
            updated_at = now()
        WHERE EXCLUDED.ts_origin > latest_readings.ts_origin
    `;
  }

  private async evaluateThreshold(
    tx: Prisma.TransactionClient,
    channelId: string,
    organizationId: string,
    value: number,
  ): Promise<void> {
    const channel = await tx.channel.findUniqueOrThrow({ where: { id: channelId } });
    const orgDefault = await tx.orgChannelThreshold.findUnique({
      where: {
        organizationId_channelTypeCode: {
          organizationId,
          channelTypeCode: channel.channelTypeCode,
        },
      },
    });

    const min = channel.alertThresholdMin ?? orgDefault?.defaultMin ?? null;
    const max = channel.alertThresholdMax ?? orgDefault?.defaultMax ?? null;
    const breached = (min !== null && value < min) || (max !== null && value > max);

    if (breached) {
      await this.openOrKeepThresholdAlert(tx, channelId, organizationId, value, min, max);
    } else {
      await this.autoResolveThresholdAlert(tx, channelId);
    }
  }

  /** Evita duplicar la alerta abierta apoyándose en el índice único parcial (migration 0003). */
  private async openOrKeepThresholdAlert(
    tx: Prisma.TransactionClient,
    channelId: string,
    organizationId: string,
    value: number,
    min: number | null,
    max: number | null,
  ): Promise<void> {
    try {
      await tx.alert.create({
        data: {
          organizationId,
          alertType: 'threshold',
          channelId,
          status: 'open',
          openedAt: new Date(),
          details: { value, min, max },
        },
      });
    } catch (error) {
      if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002') {
        return; // Ya hay una alerta abierta para este canal — comportamiento esperado, no un error.
      }
      throw error;
    }
  }

  /** FUNCTIONAL_REQUIREMENTS.md §14: la alerta de umbral se auto-resuelve al volver a rango. */
  private async autoResolveThresholdAlert(
    tx: Prisma.TransactionClient,
    channelId: string,
  ): Promise<void> {
    await tx.alert.updateMany({
      where: { channelId, alertType: 'threshold', status: { not: 'resolved' } },
      data: { status: 'resolved', resolvedAt: new Date() },
    });
  }
}
