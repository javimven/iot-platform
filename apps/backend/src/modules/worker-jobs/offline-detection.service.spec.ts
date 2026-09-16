import { Prisma } from '@prisma/client';
import { OfflineDetectionService } from './offline-detection.service';
import { PrismaService } from '../../common/prisma/prisma.service';

/**
 * MQTT_PROTOCOL.md §8: offline a partir de 2,5x el intervalo de heartbeat
 * esperado.
 *
 * `scanGateways`/`scanDevices` recorren TODAS las organizaciones (job de
 * sistema) — regresión de un bug real (2026-08-06, encontrado en vivo: los
 * gateways de prueba nunca pasaban a offline aunque llevaran horas sin
 * dato): antes consultaban `this.prisma.gateway.findMany()` directamente,
 * fuera de `runInTenantContext` — la política RLS de `gateways` evalúa
 * `current_setting('app.is_platform_admin', true)::boolean`, y sin pasar
 * por `runInTenantContext` ese GUC quedaba en un estado inconsistente entre
 * conexiones del pool, lanzando "invalid input syntax for type boolean"
 * en cada escaneo — el job llevaba fallando en cada ejecución desde
 * siempre, nunca había marcado un gateway offline de verdad.
 */
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
      gateway: {
        findMany: jest.fn().mockResolvedValue(params.gateways),
        update: jest.fn().mockResolvedValue({}),
      },
      device: { findMany: jest.fn().mockResolvedValue([]) },
      alert: {
        create: params.createAlertError
          ? jest.fn().mockRejectedValue(params.createAlertError)
          : jest.fn().mockResolvedValue({ id: 'alert-1' }),
      },
    };
    const runInTenantContext = jest.fn(async (_ctx: unknown, fn: (tx: unknown) => unknown) =>
      fn(tx),
    );
    const prisma = { runInTenantContext } as unknown as PrismaService;
    return { prisma, tx, runInTenantContext };
  }

  it('consulta los gateways a través de runInTenantContext con isPlatformAdmin, nunca this.prisma.gateway.findMany a pelo', async () => {
    const { prisma, runInTenantContext } = buildPrisma({ gateways: [] });
    await new OfflineDetectionService(prisma).scanGateways();

    expect(runInTenantContext).toHaveBeenCalledWith(
      expect.objectContaining({ isPlatformAdmin: true }),
      expect.any(Function),
    );
  });

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

  it('sin heartbeatIntervalSeconds propio, usa el valor por defecto (144 min -> umbral de 6h)', async () => {
    const fiveHoursAgo = new Date(Date.now() - 5 * 60 * 60 * 1000); // dentro de las 6h por defecto
    const sevenHoursAgo = new Date(Date.now() - 7 * 60 * 60 * 1000); // fuera

    const { prisma: prismaWithin, tx: txWithin } = buildPrisma({
      gateways: [
        {
          id: 'gw-default-within',
          organizationId: 'org-1',
          status: 'online',
          lastSeenAt: fiveHoursAgo,
          heartbeatIntervalSeconds: null,
          deletedAt: null,
        },
      ],
    });
    await new OfflineDetectionService(prismaWithin).scanGateways();
    expect(txWithin.gateway.update).not.toHaveBeenCalled();

    const { prisma: prismaOutside, tx: txOutside } = buildPrisma({
      gateways: [
        {
          id: 'gw-default-outside',
          organizationId: 'org-1',
          status: 'online',
          lastSeenAt: sevenHoursAgo,
          heartbeatIntervalSeconds: null,
          deletedAt: null,
        },
      ],
    });
    await new OfflineDetectionService(prismaOutside).scanGateways();
    expect(txOutside.gateway.update).toHaveBeenCalledWith({
      where: { id: 'gw-default-outside' },
      data: { status: 'offline' },
    });
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
