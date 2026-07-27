import { randomUUID } from 'node:crypto';
import { Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Queue } from 'bullmq';
import IORedis from 'ioredis';
import mqtt, { MqttClient } from 'mqtt';
import { PrismaService } from '../../common/prisma/prisma.service';
import {
  TELEMETRY_JOB_OPTIONS,
  TELEMETRY_QUEUE_NAME,
  TelemetryJobPayload,
  TelemetryReadingInput,
} from '../../common/queues/telemetry-queue';

const MAX_MESSAGE_BYTES = 8 * 1024; // MQTT_PROTOCOL.md §6.1
const MAX_READINGS_PER_MESSAGE = 8; // MQTT_PROTOCOL.md §6.6
const MAX_CLOCK_SKEW_FUTURE_MS = 5 * 60 * 1000; // §6.5
const MAX_CLOCK_SKEW_PAST_MS = 30 * 24 * 60 * 60 * 1000; // §6.5
const SUPPORTED_SCHEMA_VERSIONS = [1]; // §11 — ampliable, nunca se retira una versión en caliente

interface TelemetryMessage {
  schema_version: number;
  device_id: string;
  sensor_id: string;
  ts: string;
  message_id?: string;
  readings: Array<{ channel: string; value: number }>;
}

/**
 * Único proceso que habla MQTT (ARCHITECTURE.md §5, MQTT_PROTOCOL.md). Valida
 * de forma superficial (§6) y encola en BullMQ — nunca escribe en PostgreSQL
 * directamente más allá de resolver identificadores y el estado online/offline
 * inmediato por LWT (§8).
 *
 * Nota de alcance: código real y compilable, pero sin un broker EMQX vivo en
 * este entorno de desarrollo no se ha podido ejecutar/probar en tiempo real
 * contra un broker de verdad — a verificar en el primer despliegue a
 * staging (`TESTING_STRATEGY.md` §5, "pruebas de contrato MQTT").
 */
@Injectable()
export class MqttIngestionService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(MqttIngestionService.name);
  private client?: MqttClient;
  private queue?: Queue<TelemetryJobPayload>;

  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService,
  ) {}

  onModuleInit(): void {
    const connection = new IORedis(this.config.getOrThrow<string>('REDIS_URL'), {
      maxRetriesPerRequest: null,
    });
    this.queue = new Queue<TelemetryJobPayload>(TELEMETRY_QUEUE_NAME, { connection });

    // Credencial propia de ingestion, de solo-suscripción — nunca una
    // credencial de gateway (MQTT_PROTOCOL.md §4).
    this.client = mqtt.connect(this.config.getOrThrow<string>('MQTT_BROKER_URL'), {
      username: this.config.get<string>('MQTT_INGESTION_USERNAME'),
      password: this.config.get<string>('MQTT_INGESTION_PASSWORD'),
      clientId: `ingestion-${randomUUID()}`,
    });

    this.client.on('connect', () => {
      this.client?.subscribe(['org/+/gw/+/data', 'org/+/gw/+/status'], { qos: 1 });
      this.logger.log('Connected to MQTT broker and subscribed');
    });

    this.client.on('message', (topic, payload) => {
      this.handleMessage(topic, payload).catch((error) => {
        this.logger.error(`Error handling MQTT message on ${topic}: ${(error as Error).message}`);
      });
    });
  }

  async onModuleDestroy(): Promise<void> {
    await this.queue?.close();
    this.client?.end();
  }

  private async handleMessage(topic: string, payload: Buffer): Promise<void> {
    const parts = topic.split('/'); // org/{orgId}/gw/{gatewayExternalId}/{data|status}
    const organizationId = parts[1];
    const gatewayExternalId = parts[3];
    const kind = parts[4];

    if (kind === 'status') {
      await this.handleStatus(organizationId, gatewayExternalId, payload);
      return;
    }
    if (kind === 'data') {
      await this.handleData(organizationId, gatewayExternalId, payload);
    }
  }

  private async handleStatus(
    organizationId: string,
    gatewayExternalId: string,
    payload: Buffer,
  ): Promise<void> {
    let body: { online?: boolean };
    try {
      body = JSON.parse(payload.toString('utf8'));
    } catch {
      return;
    }
    await this.prisma.runInTenantContext({ organizationId }, async (tx) => {
      const gateway = await tx.gateway.findFirst({
        where: { organizationId, externalIdentifier: gatewayExternalId },
      });
      if (!gateway) {
        return;
      }
      await tx.gateway.update({
        where: { id: gateway.id },
        data: { status: body.online ? 'online' : 'offline' },
      });
      if (body.online) {
        // Reconexión vía LWT: resuelve la alerta de offline igual que un
        // mensaje de datos normal (MQTT_PROTOCOL.md §8, TelemetryProcessingService).
        await tx.alert.updateMany({
          where: { gatewayId: gateway.id, alertType: 'offline', status: { not: 'resolved' } },
          data: { status: 'resolved', resolvedAt: new Date() },
        });
      }
    });
  }

  private async handleData(
    organizationId: string,
    gatewayExternalId: string,
    payload: Buffer,
  ): Promise<void> {
    const correlationId = randomUUID();

    // 1. Tamaño (MQTT_PROTOCOL.md §6.1) — se rechaza sin parsear si lo excede.
    if (payload.byteLength > MAX_MESSAGE_BYTES) {
      this.logger.warn(
        `[${correlationId}] message too large (${payload.byteLength} bytes), rejected`,
      );
      return;
    }

    let message: TelemetryMessage;
    try {
      message = JSON.parse(payload.toString('utf8'));
    } catch {
      this.logger.warn(`[${correlationId}] malformed JSON, rejected`);
      return;
    }

    // 2. Versión de esquema (§11).
    if (!SUPPORTED_SCHEMA_VERSIONS.includes(message.schema_version)) {
      this.logger.warn(`[${correlationId}] unsupported schema_version ${message.schema_version}`);
      return;
    }

    // 5. Reloj del dispositivo (§6.5).
    const tsOrigin = new Date(message.ts);
    const now = Date.now();
    if (
      Number.isNaN(tsOrigin.getTime()) ||
      tsOrigin.getTime() > now + MAX_CLOCK_SKEW_FUTURE_MS ||
      tsOrigin.getTime() < now - MAX_CLOCK_SKEW_PAST_MS
    ) {
      this.logger.warn(`[${correlationId}] ts out of acceptable range, rejected`);
      return;
    }

    // 6. Máximo de lecturas por mensaje (§6.6).
    if (message.readings.length > MAX_READINGS_PER_MESSAGE) {
      this.logger.warn(`[${correlationId}] too many readings in one message, rejected`);
      return;
    }

    await this.prisma.runInTenantContext({ organizationId }, async (tx) => {
      // 3-4. Gateway y dispositivo pre-registrados (§6.3-6.4).
      const gateway = await tx.gateway.findFirst({
        where: { organizationId, externalIdentifier: gatewayExternalId, deletedAt: null },
      });
      if (!gateway) {
        this.logger.warn(`[${correlationId}] unknown gateway ${gatewayExternalId}, rejected`);
        return;
      }
      const device = await tx.device.findFirst({
        where: { gatewayId: gateway.id, externalIdentifier: message.device_id, deletedAt: null },
      });
      if (!device) {
        this.logger.warn(`[${correlationId}] unregistered device ${message.device_id}, rejected`);
        return;
      }
      const sensor = await tx.sensor.findFirst({
        where: { deviceId: device.id, externalIdentifier: message.sensor_id, deletedAt: null },
      });
      if (!sensor) {
        this.logger.warn(`[${correlationId}] unregistered sensor ${message.sensor_id}, rejected`);
        return;
      }

      // 7. Cada lectura se valida de forma independiente (§6.7) y el canal
      // se crea automáticamente en el primer mensaje válido (§9).
      const resolvedReadings: TelemetryReadingInput[] = [];
      for (const reading of message.readings) {
        const channelType = await tx.channelType.findUnique({ where: { code: reading.channel } });
        if (!channelType) {
          this.logger.debug(
            `[${correlationId}] unknown channel type ${reading.channel}, reading dropped`,
          );
          continue;
        }
        if (
          (channelType.minValid !== null && reading.value < channelType.minValid) ||
          (channelType.maxValid !== null && reading.value > channelType.maxValid)
        ) {
          this.logger.debug(
            `[${correlationId}] value out of physical range for ${reading.channel}, dropped`,
          );
          continue;
        }

        const channel = await tx.channel.upsert({
          where: {
            sensorId_channelTypeCode: { sensorId: sensor.id, channelTypeCode: reading.channel },
          },
          create: { organizationId, sensorId: sensor.id, channelTypeCode: reading.channel },
          update: {},
        });
        resolvedReadings.push({ channelId: channel.id, value: reading.value });
      }

      if (resolvedReadings.length === 0) {
        return; // todas las lecturas se descartaron; nada que encolar
      }

      const jobPayload: TelemetryJobPayload = {
        organizationId,
        gatewayId: gateway.id,
        deviceId: device.id,
        tsOrigin: tsOrigin.toISOString(),
        messageId: message.message_id,
        correlationId,
        readings: resolvedReadings,
      };
      await this.queue?.add('telemetry-message', jobPayload, TELEMETRY_JOB_OPTIONS);
    });
  }
}
