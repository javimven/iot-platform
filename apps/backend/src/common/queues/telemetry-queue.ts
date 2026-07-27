/**
 * Contrato de la cola de telemetría entre `ingestion` (productor) y `worker`
 * (consumidor) — ARCHITECTURE.md §8. Un job = un mensaje MQTT ya validado y
 * resuelto (dispositivo/sensor/canal a UUIDs internos, MQTT_PROTOCOL.md §5-6),
 * con las lecturas inválidas ya descartadas.
 */
export const TELEMETRY_QUEUE_NAME = 'telemetry-processing';

export interface TelemetryReadingInput {
  channelId: string;
  value: number;
}

export interface TelemetryJobPayload {
  organizationId: string;
  gatewayId: string;
  deviceId: string;
  tsOrigin: string; // ISO-8601, serializado (BullMQ serializa el job a JSON)
  messageId?: string;
  correlationId: string; // OBSERVABILITY.md §5
  readings: TelemetryReadingInput[];
}

/** Política de reintentos (OBSERVABILITY.md §7): 5 intentos, backoff exponencial base 2s. */
export const TELEMETRY_JOB_OPTIONS = {
  attempts: 5,
  backoff: { type: 'exponential' as const, delay: 2000 },
  removeOnComplete: { age: 3600 },
  removeOnFail: false, // se conservan para inspección manual (dead-letter, OBSERVABILITY.md §7)
};
