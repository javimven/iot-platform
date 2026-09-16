import { ForbiddenException, NotFoundException } from '@nestjs/common';
import { ReadingsService } from './readings.service';
import { PrismaService } from '../../common/prisma/prisma.service';
import { AccessTokenClaims } from '../../common/guards/jwt-auth.guard';

/**
 * `getLatestForGateway` (BACKLOG.md #30, pantalla "Estaciones") — equivalente
 * a `getLatestForInstallation` un nivel más superficial (`Device.gatewayId`
 * es FK directo, no hace falta pasar por `zone`), pero comprobando el
 * alcance por instalación (`resolveInstallationScope`) contra
 * `gateway.installationId`, no contra el propio gateway.
 */
describe('ReadingsService.getLatestForGateway', () => {
  const orgAdmin: AccessTokenClaims = {
    sub: 'user-1',
    type: 'access',
    organizationId: 'org-1',
    roleCode: 'org_admin',
    memberId: 'member-1',
  };

  const scopedTechnician: AccessTokenClaims = {
    sub: 'user-2',
    type: 'access',
    organizationId: 'org-1',
    roleCode: 'technician',
    memberId: 'member-2',
  };

  function buildService(params: {
    gateway: { id: string; installationId: string } | null;
    latestReadings?: Array<{
      value: number;
      channel: {
        channelTypeCode: string;
        sensor: { id: string; externalIdentifier: string; label: string | null };
      };
    }>;
    memberInstallationScope?: Array<{ installationId: string }>;
  }) {
    const runInTenantContext = jest.fn(async (_ctx: unknown, fn: (tx: unknown) => unknown) =>
      fn({
        gateway: { findFirst: jest.fn().mockResolvedValue(params.gateway) },
        latestReading: { findMany: jest.fn().mockResolvedValue(params.latestReadings ?? []) },
      }),
    );
    const memberInstallationScope = {
      findMany: jest.fn().mockResolvedValue(params.memberInstallationScope ?? []),
    };
    const prisma = { runInTenantContext, memberInstallationScope } as unknown as PrismaService;
    return new ReadingsService(prisma);
  }

  it('devuelve 404 si el gateway no existe', async () => {
    const service = buildService({ gateway: null });
    await expect(service.getLatestForGateway(orgAdmin, 'gw-missing')).rejects.toThrow(
      NotFoundException,
    );
  });

  it('devuelve 403 si la instalación del gateway está fuera del alcance del miembro', async () => {
    const service = buildService({
      gateway: { id: 'gw-1', installationId: 'inst-A' },
      memberInstallationScope: [{ installationId: 'inst-B' }],
    });
    await expect(service.getLatestForGateway(scopedTechnician, 'gw-1')).rejects.toThrow(
      ForbiddenException,
    );
  });

  it('devuelve las lecturas aplanadas cuando el rol no tiene alcance restringido (org_admin -> "all")', async () => {
    const service = buildService({
      gateway: { id: 'gw-1', installationId: 'inst-A' },
      latestReadings: [
        {
          value: 21.5,
          channel: {
            channelTypeCode: 'temperature_air',
            sensor: { id: 'sensor-1', externalIdentifier: 'A4', label: 'Ambiente' },
          },
        },
      ],
    });
    await expect(service.getLatestForGateway(orgAdmin, 'gw-1')).resolves.toEqual([
      {
        value: 21.5,
        channelTypeCode: 'temperature_air',
        sensorId: 'sensor-1',
        sensorExternalIdentifier: 'A4',
        sensorLabel: 'Ambiente',
      },
    ]);
  });

  it('devuelve las lecturas cuando la instalación del gateway sí está dentro del alcance del miembro', async () => {
    const service = buildService({
      gateway: { id: 'gw-1', installationId: 'inst-A' },
      latestReadings: [
        {
          value: 60,
          channel: {
            channelTypeCode: 'humidity_soil',
            sensor: { id: 'sensor-2', externalIdentifier: 'A3', label: null },
          },
        },
      ],
      memberInstallationScope: [{ installationId: 'inst-A' }],
    });
    // Sin nombre puesto, el sensor se muestra por su identificador externo.
    await expect(service.getLatestForGateway(scopedTechnician, 'gw-1')).resolves.toEqual([
      {
        value: 60,
        channelTypeCode: 'humidity_soil',
        sensorId: 'sensor-2',
        sensorExternalIdentifier: 'A3',
        sensorLabel: 'A3',
      },
    ]);
  });
});

/**
 * Ruta de plataforma (ADR-0007): el Admin de plataforma lee la telemetría de
 * la organización de la URL. La transacción fija esa organización como
 * `app.current_org_id` (nunca `isPlatformAdmin`), de modo que la política RLS
 * de `telemetry`/`latest_readings` sigue acotando a una sola organización.
 */
describe('ReadingsService con organización explícita (ADR-0007)', () => {
  const platformAdmin: AccessTokenClaims = {
    sub: 'admin-1',
    type: 'access',
    isPlatformAdmin: true,
  };

  function buildService() {
    const contexts: unknown[] = [];
    const tx = {
      gateway: { findFirst: jest.fn().mockResolvedValue({ id: 'gw-1', installationId: 'inst-A' }) },
      latestReading: { findMany: jest.fn().mockResolvedValue([]) },
      channel: {
        findFirst: jest.fn().mockResolvedValue({
          id: 'channel-1',
          sensor: { device: { zone: { installationId: 'inst-A' } } },
        }),
      },
      $queryRaw: jest.fn().mockResolvedValue([]),
    };
    const runInTenantContext = jest.fn(async (ctx: unknown, fn: (tx: unknown) => unknown) => {
      contexts.push(ctx);
      return fn(tx);
    });
    const prisma = {
      runInTenantContext,
      memberInstallationScope: { findMany: jest.fn().mockResolvedValue([]) },
    } as unknown as PrismaService;
    return { service: new ReadingsService(prisma), contexts, tx };
  }

  it('últimas lecturas de una estación: consulta dentro de la organización de la URL', async () => {
    const { service, contexts, tx } = buildService();
    await service.getLatestForGateway(platformAdmin, 'gw-1', 'org-2');
    expect(contexts).toEqual([
      { userId: 'admin-1', organizationId: 'org-2' },
      { userId: 'admin-1', organizationId: 'org-2' },
    ]);
    expect(tx.gateway.findFirst).toHaveBeenCalledWith({
      where: { id: 'gw-1', organizationId: 'org-2', deletedAt: null },
    });
  });

  it('histórico de un canal: consulta dentro de la organización de la URL', async () => {
    const { service, contexts } = buildService();
    const from = new Date('2026-09-15T00:00:00Z');
    const to = new Date('2026-09-16T00:00:00Z');
    await service.getHistory(platformAdmin, 'channel-1', from, to, 'raw', 'org-2');
    expect(contexts.length).toBeGreaterThan(0);
    for (const ctx of contexts) {
      expect(ctx).toEqual({ userId: 'admin-1', organizationId: 'org-2' });
    }
  });

  it('un miembro normal no puede pedir otra organización', async () => {
    const { service } = buildService();
    const member: AccessTokenClaims = {
      sub: 'user-1',
      type: 'access',
      organizationId: 'org-1',
      roleCode: 'org_admin',
      memberId: 'member-1',
    };
    await expect(service.getLatestForGateway(member, 'gw-1', 'org-2')).rejects.toThrow(
      ForbiddenException,
    );
  });
});

/**
 * `getHistory` — regresión de un bug real (2026-08-05, verificando la
 * pantalla "Estaciones" con datos reales por primera vez): las 3 ramas
 * consultaban `telemetry` con `this.prisma.$queryRaw` directamente, fuera de
 * `runInTenantContext`. `telemetry` tiene una política RLS que exige
 * `app.current_org_id` (solo la fija `runInTenantContext`) — sin pasar por
 * ahí, Postgres devolvía siempre 0 filas, en silencio, para cualquier
 * canal/organización real. Estos tests fijan que la consulta de datos
 * siempre vaya por el `tx` de `runInTenantContext`, nunca por
 * `this.prisma.$queryRaw` a pelo.
 */
describe('ReadingsService.getHistory', () => {
  const orgAdmin: AccessTokenClaims = {
    sub: 'user-1',
    type: 'access',
    organizationId: 'org-1',
    roleCode: 'org_admin',
    memberId: 'member-1',
  };

  function buildService(params: { channelWithType?: Record<string, unknown> }) {
    const txQueryRaw = jest.fn().mockResolvedValue([{ tsOrigin: new Date(), value: 1 }]);
    const ungatedQueryRaw = jest.fn(); // nunca debería llamarse — ver bug arriba
    const tx = {
      channel: {
        findFirst: jest.fn().mockResolvedValue({
          id: 'channel-1',
          sensor: { device: { zone: { installationId: 'inst-A' } } },
        }),
        findUniqueOrThrow: jest.fn().mockResolvedValue(params.channelWithType),
      },
      $queryRaw: txQueryRaw,
    };
    const runInTenantContext = jest.fn(async (_ctx: unknown, fn: (tx: unknown) => unknown) =>
      fn(tx),
    );
    const prisma = {
      runInTenantContext,
      memberInstallationScope: { findMany: jest.fn().mockResolvedValue([]) },
      $queryRaw: ungatedQueryRaw,
    } as unknown as PrismaService;
    return { service: new ReadingsService(prisma), txQueryRaw, ungatedQueryRaw };
  }

  it('granularity=raw consulta a través de runInTenantContext, nunca this.prisma.$queryRaw directo', async () => {
    const { service, txQueryRaw, ungatedQueryRaw } = buildService({});
    const from = new Date('2026-08-01T00:00:00Z');
    const to = new Date('2026-08-02T00:00:00Z');

    await service.getHistory(orgAdmin, 'channel-1', from, to, 'raw');

    expect(txQueryRaw).toHaveBeenCalledTimes(1);
    expect(ungatedQueryRaw).not.toHaveBeenCalled();
  });

  it('granularity=hourly (canal sum) consulta a través de runInTenantContext', async () => {
    const { service, txQueryRaw, ungatedQueryRaw } = buildService({
      channelWithType: { channelType: { defaultAggregation: 'sum' } },
    });
    const from = new Date('2026-07-01T00:00:00Z');
    const to = new Date('2026-08-01T00:00:00Z');

    await service.getHistory(orgAdmin, 'channel-1', from, to, 'hourly');

    expect(txQueryRaw).toHaveBeenCalledTimes(1);
    expect(ungatedQueryRaw).not.toHaveBeenCalled();
  });

  it('granularity=daily (canal average) consulta a través de runInTenantContext', async () => {
    const { service, txQueryRaw, ungatedQueryRaw } = buildService({
      channelWithType: { channelType: { defaultAggregation: 'average' } },
    });
    const from = new Date('2026-07-01T00:00:00Z');
    const to = new Date('2026-08-01T00:00:00Z');

    await service.getHistory(orgAdmin, 'channel-1', from, to, 'daily');

    expect(txQueryRaw).toHaveBeenCalledTimes(1);
    expect(ungatedQueryRaw).not.toHaveBeenCalled();
  });
});
