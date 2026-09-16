import { Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../../common/prisma/prisma.service';

// Etapa 2 — valor por defecto si el gateway no fijó su propio
// `heartbeatIntervalSeconds`. Subido de 15 min a 144 min (2026-08-10,
// feedback explícito): con 15 min × `OFFLINE_MULTIPLIER` el umbral por
// defecto era ~37 min, demasiado sensible en la práctica (marcaba offline
// estaciones reales que solo tardaban algo más entre lecturas) — 144 min
// da un umbral por defecto de 6h exactas, con el mismo multiplicador ya
// documentado en MQTT_PROTOCOL.md §8. Sigue siendo configurable por
// gateway si una organización necesita algo más ajustado.
const DEFAULT_HEARTBEAT_SECONDS = 144 * 60;
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
    // Recorre TODAS las organizaciones (job de sistema, no de un tenant
    // concreto) — necesita el bypass de RLS de `is_platform_admin`, nunca
    // `this.prisma.gateway.findMany()` a pelo: sin pasar por
    // `runInTenantContext`, la política RLS de `gateways` evalúa
    // `current_setting('app.is_platform_admin', true)::boolean` sobre un GUC
    // en estado inconsistente entre conexiones del pool — error real en vivo
    // (2026-08-06): el escaneo llevaba fallando en cada ejecución desde
    // siempre, `OfflineDetectionService` nunca había marcado un gateway como
    // offline de verdad hasta arreglar esto (BACKLOG.md).
    const gateways = await this.prisma.runInTenantContext({ isPlatformAdmin: true }, (tx) =>
      tx.gateway.findMany({
        where: { status: { in: ['online', 'offline'] }, deletedAt: null },
      }),
    );
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
    const devices = await this.prisma.runInTenantContext({ isPlatformAdmin: true }, (tx) =>
      tx.device.findMany({
        where: { status: { in: ['online', 'offline'] }, deletedAt: null },
        include: { gateway: true },
      }),
    );
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
