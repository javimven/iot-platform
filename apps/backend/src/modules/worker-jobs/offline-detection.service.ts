import { Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../../common/prisma/prisma.service';

const DEFAULT_HEARTBEAT_SECONDS = 15 * 60; // Etapa 2 — valor por defecto si la organización no fijó uno
const OFFLINE_MULTIPLIER = 2.5; // MQTT_PROTOCOL.md §8
const SCAN_INTERVAL_MS = 60_000;

/**
 * Detección de offline por timeout (MQTT_PROTOCOL.md §8, mecanismo 2 —
 * complementario al LWT, que ya cubre la caída de conexión inmediata en
 * `MqttIngestionService`). Recorre gateways/dispositivos cada minuto; a la
 * escala de la Etapa 2 (≤500 gateways) un escaneo completo es más barato que
 * mantener un índice sobre `last_seen_at` (DATA_MODEL.md, tabla `gateways`).
 *
 * Simplificación deliberada: un `setInterval` en vez de un job repetible de
 * BullMQ — evita una segunda cola solo para esto; se revisita si hace falta
 * coordinar el escaneo entre varias réplicas de `worker` en el futuro.
 */
@Injectable()
export class OfflineDetectionService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(OfflineDetectionService.name);
  private timer?: NodeJS.Timeout;

  constructor(private readonly prisma: PrismaService) {}

  onModuleInit(): void {
    this.timer = setInterval(() => {
      this.scan().catch((error) =>
        this.logger.error(`Offline scan failed: ${(error as Error).message}`),
      );
    }, SCAN_INTERVAL_MS);
  }

  onModuleDestroy(): void {
    if (this.timer) {
      clearInterval(this.timer);
    }
  }

  async scan(): Promise<void> {
    await this.scanGateways();
    await this.scanDevices();
  }

  /** Público (no solo por conveniencia de pruebas): útil para forzar un escaneo puntual. */
  async scanGateways(): Promise<void> {
    const gateways = await this.prisma.gateway.findMany({
      where: { status: { in: ['online', 'offline'] }, deletedAt: null },
    });
    for (const gateway of gateways) {
      const thresholdMs =
        (gateway.heartbeatIntervalSeconds ?? DEFAULT_HEARTBEAT_SECONDS) * OFFLINE_MULTIPLIER * 1000;
      const isStale =
        !gateway.lastSeenAt || Date.now() - gateway.lastSeenAt.getTime() > thresholdMs;

      await this.prisma.runInTenantContext(
        { organizationId: gateway.organizationId },
        async (tx) => {
          if (isStale && gateway.status !== 'offline') {
            await tx.gateway.update({ where: { id: gateway.id }, data: { status: 'offline' } });
            await this.openOfflineAlert(tx, {
              gatewayId: gateway.id,
              organizationId: gateway.organizationId,
            });
          }
        },
      );
    }
  }

  async scanDevices(): Promise<void> {
    const devices = await this.prisma.device.findMany({
      where: { status: { in: ['online', 'offline'] }, deletedAt: null },
      include: { gateway: true },
    });
    for (const device of devices) {
      const thresholdMs =
        (device.gateway.heartbeatIntervalSeconds ?? DEFAULT_HEARTBEAT_SECONDS) *
        OFFLINE_MULTIPLIER *
        1000;
      const isStale = !device.lastSeenAt || Date.now() - device.lastSeenAt.getTime() > thresholdMs;

      await this.prisma.runInTenantContext(
        { organizationId: device.organizationId },
        async (tx) => {
          if (isStale && device.status !== 'offline') {
            await tx.device.update({ where: { id: device.id }, data: { status: 'offline' } });
            await this.openOfflineAlert(tx, {
              deviceId: device.id,
              organizationId: device.organizationId,
            });
          }
        },
      );
    }
  }

  private async openOfflineAlert(
    tx: Prisma.TransactionClient,
    target: { gatewayId?: string; deviceId?: string; organizationId: string },
  ): Promise<void> {
    try {
      await tx.alert.create({
        data: {
          organizationId: target.organizationId,
          alertType: 'offline',
          gatewayId: target.gatewayId,
          deviceId: target.deviceId,
          status: 'open',
          openedAt: new Date(),
        },
      });
    } catch (error) {
      if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002') {
        return; // Ya hay una alerta de offline abierta para este gateway/dispositivo.
      }
      throw error;
    }
  }
}
