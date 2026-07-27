import { Prisma } from '@prisma/client';
import { TelemetryProcessingService } from './telemetry-processing.service';
import { PrismaService } from '../../common/prisma/prisma.service';
import { TelemetryJobPayload } from '../../common/queues/telemetry-queue';

/**
 * MQTT_PROTOCOL.md §11 / DATA_MODEL.md §5: procesar el mismo mensaje dos
 * veces no debe tener efectos adicionales (idempotencia); FUNCTIONAL_REQUIREMENTS.md
 * §14: la alerta de umbral se abre una sola vez y se auto-resuelve al volver a rango.
 */
describe('TelemetryProcessingService', () => {
  function buildTx(overrides: {
    createManyCount: number;
    channel: {
      channelTypeCode: string;
      alertThresholdMin: number | null;
      alertThresholdMax: number | null;
    };
    orgDefault?: { defaultMin: number | null; defaultMax: number | null } | null;
    createAlertError?: unknown;
  }) {
    return {
      gateway: { update: jest.fn().mockResolvedValue({}) },
      device: { update: jest.fn().mockResolvedValue({}) },
      telemetry: {
        createMany: jest.fn().mockResolvedValue({ count: overrides.createManyCount }),
      },
      $executeRaw: jest.fn().mockResolvedValue(1),
      channel: {
        findUniqueOrThrow: jest.fn().mockResolvedValue(overrides.channel),
      },
      orgChannelThreshold: {
        findUnique: jest.fn().mockResolvedValue(overrides.orgDefault ?? null),
      },
      alert: {
        create: overrides.createAlertError
          ? jest.fn().mockRejectedValue(overrides.createAlertError)
          : jest.fn().mockResolvedValue({ id: 'alert-1' }),
        updateMany: jest.fn().mockResolvedValue({ count: 1 }),
      },
    };
  }

  function buildService(tx: ReturnType<typeof buildTx>) {
    const runInTenantContext = jest.fn(async (_ctx: unknown, fn: (tx: unknown) => unknown) =>
      fn(tx),
    );
    const prisma = { runInTenantContext } as unknown as PrismaService;
    return new TelemetryProcessingService(prisma);
  }

  const basePayload: TelemetryJobPayload = {
    organizationId: 'org-1',
    gatewayId: 'gw-1',
    deviceId: 'device-1',
    tsOrigin: '2026-07-27T10:00:00.000Z',
    correlationId: 'corr-1',
    readings: [{ channelId: 'channel-1', value: 23.4 }],
  };

  it('actualiza last_seen_at de gateway y dispositivo en cada mensaje', async () => {
    const tx = buildTx({
      createManyCount: 1,
      channel: {
        channelTypeCode: 'temperature_air',
        alertThresholdMin: null,
        alertThresholdMax: null,
      },
    });
    const service = buildService(tx);
    await service.processMessage(basePayload);
    expect(tx.gateway.update).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { id: 'gw-1' },
        data: expect.objectContaining({ status: 'online' }),
      }),
    );
    expect(tx.device.update).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { id: 'device-1' },
        data: expect.objectContaining({ status: 'online' }),
      }),
    );
  });

  it('un mensaje duplicado no actualiza latest_readings ni evalúa el umbral', async () => {
    const tx = buildTx({
      createManyCount: 0, // ya existía -> duplicado
      channel: {
        channelTypeCode: 'temperature_air',
        alertThresholdMin: null,
        alertThresholdMax: null,
      },
    });
    const service = buildService(tx);
    await service.processMessage(basePayload);
    expect(tx.$executeRaw).not.toHaveBeenCalled();
    expect(tx.channel.findUniqueOrThrow).not.toHaveBeenCalled();
  });

  it('un valor dentro de rango no crea alerta y resuelve cualquier alerta de umbral abierta', async () => {
    const tx = buildTx({
      createManyCount: 1,
      channel: { channelTypeCode: 'temperature_air', alertThresholdMin: 0, alertThresholdMax: 40 },
    });
    const service = buildService(tx);
    await service.processMessage(basePayload); // value = 23.4, dentro de [0,40]
    expect(tx.alert.create).not.toHaveBeenCalled();
    expect(tx.alert.updateMany).toHaveBeenCalledWith(
      expect.objectContaining({ data: expect.objectContaining({ status: 'resolved' }) }),
    );
  });

  it('un valor fuera de rango crea una alerta de umbral', async () => {
    const tx = buildTx({
      createManyCount: 1,
      channel: { channelTypeCode: 'temperature_air', alertThresholdMin: 0, alertThresholdMax: 20 },
    });
    const service = buildService(tx);
    await service.processMessage(basePayload); // value = 23.4 > 20
    expect(tx.alert.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({ alertType: 'threshold', channelId: 'channel-1' }),
      }),
    );
  });

  it('no falla si ya existe una alerta abierta para el mismo canal (índice único parcial)', async () => {
    const uniqueViolation = new Prisma.PrismaClientKnownRequestError('Unique constraint failed', {
      code: 'P2002',
      clientVersion: '5.20.0',
    });
    const tx = buildTx({
      createManyCount: 1,
      channel: { channelTypeCode: 'temperature_air', alertThresholdMin: 0, alertThresholdMax: 20 },
      createAlertError: uniqueViolation,
    });
    const service = buildService(tx);
    await expect(service.processMessage(basePayload)).resolves.toBeUndefined();
  });

  it('usa el umbral por defecto de la organización cuando el canal no tiene override', async () => {
    const tx = buildTx({
      createManyCount: 1,
      channel: {
        channelTypeCode: 'humidity_air',
        alertThresholdMin: null,
        alertThresholdMax: null,
      },
      orgDefault: { defaultMin: 30, defaultMax: 90 },
    });
    const service = buildService(tx);
    await service.processMessage({
      ...basePayload,
      readings: [{ channelId: 'channel-2', value: 95 }], // > 90 (default de organización)
    });
    expect(tx.alert.create).toHaveBeenCalled();
  });
});
