import { NoSensorDataService } from './no-sensor-data.service';
import { PrismaService } from '../../common/prisma/prisma.service';

/**
 * BACKLOG.md #57. El caso que lo motiva no es un gateway caído (de eso ya se
 * encarga `OfflineDetectionService`): es la WSC2-N enviando batería y
 * cobertura con normalidad mientras sus sensores RS485, sin declarar tras un
 * reinicio, no dan ni una lectura. Por eso el reloj se mide sobre las
 * lecturas de campo y nunca sobre `last_seen_at`.
 */
describe('NoSensorDataService', () => {
  const AHORA = new Date('2026-09-21T18:00:00Z');

  function buildPrisma(params: { ultima: Date | null; abierta?: { id: string }; reciente?: unknown }) {
    const tx = {
      gateway: {
        findMany: jest
          .fn()
          .mockResolvedValue([{ id: 'gw-1', organizationId: 'org-1', deletedAt: null }]),
      },
      alert: {
        findFirst: jest
          .fn()
          .mockResolvedValueOnce(params.abierta ?? null)
          .mockResolvedValueOnce(params.reciente ?? null),
        create: jest.fn().mockResolvedValue({ id: 'alert-1' }),
        update: jest.fn().mockResolvedValue({}),
      },
      $queryRaw: jest.fn().mockResolvedValue([{ ultima: params.ultima }]),
    };
    const runInTenantContext = jest.fn(async (_ctx: unknown, fn: (tx: unknown) => unknown) =>
      fn(tx),
    );
    return { prisma: { runInTenantContext } as unknown as PrismaService, tx, runInTenantContext };
  }

  it('recorre los gateways como job de sistema, con isPlatformAdmin', async () => {
    const { prisma, runInTenantContext } = buildPrisma({ ultima: AHORA });
    await new NoSensorDataService(prisma).scan(AHORA);

    expect(runInTenantContext).toHaveBeenCalledWith(
      expect.objectContaining({ isPlatformAdmin: true }),
      expect.any(Function),
    );
  });

  it('abre la alerta cuando la última lectura de campo pasa de una hora', async () => {
    const { prisma, tx } = buildPrisma({ ultima: new Date(AHORA.getTime() - 75 * 60 * 1000) });
    await new NoSensorDataService(prisma).scan(AHORA);

    expect(tx.alert.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({ alertType: 'no_sensor_data', gatewayId: 'gw-1' }),
      }),
    );
  });

  it('no abre nada mientras la última lectura esté dentro de la hora', async () => {
    const { prisma, tx } = buildPrisma({ ultima: new Date(AHORA.getTime() - 45 * 60 * 1000) });
    await new NoSensorDataService(prisma).scan(AHORA);

    expect(tx.alert.create).not.toHaveBeenCalled();
    expect(tx.alert.update).not.toHaveBeenCalled();
  });

  it('no abre nada si la estación no ha dado nunca una lectura de campo', async () => {
    // Puede ser una estación recién dada de alta: no se sabe si es un fallo.
    const { prisma, tx } = buildPrisma({ ultima: null });
    await new NoSensorDataService(prisma).scan(AHORA);

    expect(tx.alert.create).not.toHaveBeenCalled();
  });

  it('con una alerta ya abierta no crea otra: un aviso, no un correo por pasada', async () => {
    const { prisma, tx } = buildPrisma({
      ultima: new Date(AHORA.getTime() - 5 * 60 * 60 * 1000),
      abierta: { id: 'alert-abierta' },
    });
    await new NoSensorDataService(prisma).scan(AHORA);

    expect(tx.alert.create).not.toHaveBeenCalled();
  });

  it('tampoco avisa dos veces el mismo día aunque la anterior se diera por resuelta', async () => {
    // El fallo de la WSC2-N va y viene (envía, se reinicia, deja de enviar):
    // sin este freno, cada vaivén sería un correo.
    const { prisma, tx } = buildPrisma({
      ultima: new Date(AHORA.getTime() - 70 * 60 * 1000),
      reciente: { id: 'alert-de-esta-manana' },
    });
    await new NoSensorDataService(prisma).scan(AHORA);

    expect(tx.alert.create).not.toHaveBeenCalled();
  });

  it('resuelve la alerta abierta en cuanto vuelven los datos', async () => {
    const { prisma, tx } = buildPrisma({
      ultima: new Date(AHORA.getTime() - 2 * 60 * 1000),
      abierta: { id: 'alert-abierta' },
    });
    await new NoSensorDataService(prisma).scan(AHORA);

    expect(tx.alert.update).toHaveBeenCalledWith({
      where: { id: 'alert-abierta' },
      data: { status: 'resolved', resolvedAt: AHORA },
    });
  });

  it('un gateway que falla no interrumpe el repaso de los demás', async () => {
    const { prisma, tx } = buildPrisma({ ultima: AHORA });
    tx.gateway.findMany.mockResolvedValue([
      { id: 'gw-roto', organizationId: 'org-1', deletedAt: null },
      { id: 'gw-2', organizationId: 'org-1', deletedAt: null },
    ]);
    tx.$queryRaw
      .mockRejectedValueOnce(new Error('conexión perdida'))
      .mockResolvedValueOnce([{ ultima: new Date(AHORA.getTime() - 90 * 60 * 1000) }]);

    await new NoSensorDataService(prisma).scan(AHORA);

    expect(tx.alert.create).toHaveBeenCalledWith(
      expect.objectContaining({ data: expect.objectContaining({ gatewayId: 'gw-2' }) }),
    );
  });
});
