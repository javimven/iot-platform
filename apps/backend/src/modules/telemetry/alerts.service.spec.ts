import { AlertsService } from './alerts.service';
import { PrismaService } from '../../common/prisma/prisma.service';
import { AccessTokenClaims } from '../../common/guards/jwt-auth.guard';

/**
 * FUNCTIONAL_REQUIREMENTS.md §15: la lista de alertas debe mostrar algo
 * legible (nombre de instalación/canal/dispositivo/gateway), no solo IDs —
 * gap real descubierto al construir la pantalla de Alertas en Flutter
 * (Etapa 14), corregido aquí añadiendo campos aditivos sobre `Alert`.
 */
describe('AlertsService', () => {
  const orgAdmin: AccessTokenClaims = {
    sub: 'user-1',
    type: 'access',
    organizationId: 'org-1',
    roleCode: 'org_admin',
    memberId: 'member-1',
  };

  function buildService(alerts: unknown[]) {
    const alertMock = { findMany: jest.fn().mockResolvedValue(alerts) };
    const runInTenantContext = jest.fn(async (_ctx: unknown, fn: (tx: unknown) => unknown) =>
      fn({ alert: alertMock }),
    );
    const prisma = { runInTenantContext } as unknown as PrismaService;
    return { service: new AlertsService(prisma), alertMock };
  }

  it('enriquece una alerta de umbral con el nombre de instalación y el tipo de canal', async () => {
    const { service } = buildService([
      {
        id: 'alert-1',
        alertType: 'threshold',
        status: 'open',
        channel: {
          channelTypeCode: 'temperature_air',
          sensor: {
            device: { zone: { installation: { id: 'inst-1', name: 'Finca Norte' } } },
          },
        },
        device: null,
        gateway: null,
      },
    ]);
    const result = await service.findAll(orgAdmin);
    expect(result).toEqual([
      expect.objectContaining({
        id: 'alert-1',
        installationId: 'inst-1',
        installationName: 'Finca Norte',
        channelTypeCode: 'temperature_air',
        deviceName: null,
        gatewayName: null,
      }),
    ]);
    expect(result[0]).not.toHaveProperty('channel');
  });

  it('enriquece una alerta de offline de gateway con el nombre del gateway', async () => {
    const { service } = buildService([
      {
        id: 'alert-2',
        alertType: 'offline',
        status: 'open',
        channel: null,
        device: null,
        gateway: { name: 'Gateway Sur', installation: { id: 'inst-2', name: 'Finca Sur' } },
      },
    ]);
    const result = await service.findAll(orgAdmin);
    expect(result).toEqual([
      expect.objectContaining({
        installationId: 'inst-2',
        installationName: 'Finca Sur',
        gatewayName: 'Gateway Sur',
        channelTypeCode: null,
        deviceName: null,
      }),
    ]);
  });

  it('enriquece una alerta de offline de dispositivo con el nombre del dispositivo', async () => {
    const { service } = buildService([
      {
        id: 'alert-3',
        alertType: 'offline',
        status: 'open',
        channel: null,
        device: {
          name: 'Estación 4',
          zone: { installation: { id: 'inst-3', name: 'Finca Este' } },
        },
        gateway: null,
      },
    ]);
    const result = await service.findAll(orgAdmin);
    expect(result).toEqual([
      expect.objectContaining({
        installationId: 'inst-3',
        installationName: 'Finca Este',
        deviceName: 'Estación 4',
        gatewayName: null,
        channelTypeCode: null,
      }),
    ]);
  });
});
