import { ConfigService } from '@nestjs/config';
import { MqttIngestionService } from './mqtt-ingestion.service';
import { PrismaService } from '../../common/prisma/prisma.service';

/**
 * MQTT_PROTOCOL.md §6 punto 4: un `sensor_id` sin pre-registrar se rechaza,
 * salvo el reservado para los datos del propio equipo, que se crea solo en el
 * primer mensaje (ADR-0008).
 */
describe('MqttIngestionService, resolución del sensor', () => {
  function build(options: {
    existingSensor?: { id: string } | null;
    upserted?: { id: string; deletedAt: Date | null };
  }) {
    const tx = {
      gateway: { findFirst: jest.fn().mockResolvedValue({ id: 'gw-1' }) },
      device: { findFirst: jest.fn().mockResolvedValue({ id: 'device-1' }) },
      sensor: {
        findFirst: jest.fn().mockResolvedValue(options.existingSensor ?? null),
        upsert: jest
          .fn()
          .mockResolvedValue(options.upserted ?? { id: 'status-1', deletedAt: null }),
      },
      channelType: {
        findUnique: jest.fn(async ({ where }: { where: { code: string } }) => ({
          code: where.code,
          minValid: null,
          maxValid: null,
        })),
      },
      channel: {
        upsert: jest.fn(async ({ create }: { create: { channelTypeCode: string } }) => ({
          id: `ch-${create.channelTypeCode}`,
        })),
      },
    };
    const prisma = {
      runInTenantContext: jest.fn(async (_ctx: unknown, fn: (t: unknown) => unknown) => fn(tx)),
    } as unknown as PrismaService;
    const service = new MqttIngestionService(prisma, {} as ConfigService);
    const queue = { add: jest.fn() };
    (service as unknown as { queue: unknown }).queue = queue;
    const send = (sensorId: string) =>
      (
        service as unknown as { handleData: (o: string, g: string, p: Buffer) => Promise<void> }
      ).handleData(
        'org-1',
        'gw-ext',
        Buffer.from(
          JSON.stringify({
            schema_version: 1,
            device_id: 'WSC2N-01',
            sensor_id: sensorId,
            ts: new Date().toISOString(),
            readings: [
              { channel: 'battery_voltage', value: 3.45 },
              { channel: 'signal_strength', value: -75 },
            ],
          }),
        ),
      );
    return { tx, queue, send };
  }

  it('rechaza un sensor sin pre-registrar y no lo crea', async () => {
    const { tx, queue, send } = build({});
    await send('A5');
    expect(tx.sensor.upsert).not.toHaveBeenCalled();
    expect(queue.add).not.toHaveBeenCalled();
  });

  it('crea el sensor de datos del propio equipo en el primer mensaje y encola sus lecturas', async () => {
    const { tx, queue, send } = build({});
    await send('_device');
    expect(tx.sensor.upsert).toHaveBeenCalledWith({
      where: {
        deviceId_externalIdentifier: { deviceId: 'device-1', externalIdentifier: '_device' },
      },
      create: { organizationId: 'org-1', deviceId: 'device-1', externalIdentifier: '_device' },
      update: {},
    });
    expect(queue.add).toHaveBeenCalledTimes(1);
    expect(queue.add.mock.calls[0][1]).toMatchObject({
      deviceId: 'device-1',
      readings: [
        { channelId: 'ch-battery_voltage', value: 3.45 },
        { channelId: 'ch-signal_strength', value: -75 },
      ],
    });
  });

  it('si ya existe, no lo vuelve a crear', async () => {
    const { tx, queue, send } = build({ existingSensor: { id: 'status-1' } });
    await send('_device');
    expect(tx.sensor.upsert).not.toHaveBeenCalled();
    expect(queue.add).toHaveBeenCalledTimes(1);
  });

  it('si estaba borrado, se sigue rechazando', async () => {
    const { queue, send } = build({ upserted: { id: 'status-1', deletedAt: new Date() } });
    await send('_device');
    expect(queue.add).not.toHaveBeenCalled();
  });
});
