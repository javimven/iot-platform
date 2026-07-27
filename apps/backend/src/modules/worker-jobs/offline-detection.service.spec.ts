import { Prisma } from '@prisma/client';
import { OfflineDetectionService } from './offline-detection.service';
import { PrismaService } from '../../common/prisma/prisma.service';

/** MQTT_PROTOCOL.md §8: offline a partir de 2,5x el intervalo de heartbeat esperado. */
describe('OfflineDetectionService', () => {
  function buildPrisma(params: {
    gateways: Array<{
      id: string;
      organizationId: string;
      status: string;
      lastSeenAt: Date | null;
      heartbeatIntervalSeconds: number | null;
      deletedAt: null;
    }>;
    createAlertError?: unknown;
  }) {
    const tx = {
      gateway: { update: jest.fn().mockResolvedValue({}) },
      alert: {
        create: params.createAlertError
          ? jest.fn().mockRejectedValue(params.createAlertError)
          : jest.fn().mockResolvedValue({ id: 'alert-1' }),
      },
    };
    const prisma = {
      gateway: { findMany: jest.fn().mockResolvedValue(params.gateways) },
      device: { findMany: jest.fn().mockResolvedValue([]) },
      runInTenantContext: jest.fn(async (_ctx: unknown, fn: (tx: unknown) => unknown) => fn(tx)),
    } as unknown as PrismaService;
    return { prisma, tx };
  }

  it('marca offline un gateway sin señal desde hace más de 2,5x su intervalo', async () => {
    const staleDate = new Date(Date.now() - 40 * 60 * 1000); // 40 min, intervalo 15 min -> umbral 37.5 min
    const { prisma, tx } = buildPrisma({
      gateways: [
        {
          id: 'gw-1',
          organizationId: 'org-1',
          status: 'online',
          lastSeenAt: staleDate,
          heartbeatIntervalSeconds: 15 * 60,
          deletedAt: null,
        },
      ],
    });
    const service = new OfflineDetectionService(prisma);
    await service.scanGateways();
    expect(tx.gateway.update).toHaveBeenCalledWith({
      where: { id: 'gw-1' },
      data: { status: 'offline' },
    });
    expect(tx.alert.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({ alertType: 'offline', gatewayId: 'gw-1' }),
      }),
    );
  });

  it('no marca offline un gateway dentro de su ventana de tolerancia', async () => {
    const recentDate = new Date(Date.now() - 20 * 60 * 1000); // 20 min < 37.5 min umbral
    const { prisma, tx } = buildPrisma({
      gateways: [
        {
          id: 'gw-2',
          organizationId: 'org-1',
          status: 'online',
          lastSeenAt: recentDate,
          heartbeatIntervalSeconds: 15 * 60,
          deletedAt: null,
        },
      ],
    });
    const service = new OfflineDetectionService(prisma);
    await service.scanGateways();
    expect(tx.gateway.update).not.toHaveBeenCalled();
    expect(tx.alert.create).not.toHaveBeenCalled();
  });

  it('no falla si ya existe una alerta de offline abierta para el gateway', async () => {
    const uniqueViolation = new Prisma.PrismaClientKnownRequestError('Unique constraint failed', {
      code: 'P2002',
      clientVersion: '5.20.0',
    });
    const staleDate = new Date(Date.now() - 60 * 60 * 1000);
    const { prisma } = buildPrisma({
      gateways: [
        {
          id: 'gw-3',
          organizationId: 'org-1',
          status: 'online',
          lastSeenAt: staleDate,
          heartbeatIntervalSeconds: 15 * 60,
          deletedAt: null,
        },
      ],
      createAlertError: uniqueViolation,
    });
    const service = new OfflineDetectionService(prisma);
    await expect(service.scanGateways()).resolves.toBeUndefined();
  });
});
