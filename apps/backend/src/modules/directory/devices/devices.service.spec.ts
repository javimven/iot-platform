import { BadRequestException, NotFoundException } from '@nestjs/common';
import { DevicesService } from './devices.service';
import { PrismaService } from '../../../common/prisma/prisma.service';
import { AuditLogService } from '../../../common/audit/audit-log.service';
import { AccessTokenClaims } from '../../../common/guards/jwt-auth.guard';

/**
 * DATA_MODEL.md §4: la zona de un dispositivo debe pertenecer a la misma
 * instalación que su gateway. Se valida en la aplicación (400 claro) antes
 * de llegar al trigger de Postgres (migration 0002), que es el respaldo.
 */
describe('DevicesService', () => {
  const orgAdmin: AccessTokenClaims = {
    sub: 'user-1',
    type: 'access',
    organizationId: 'org-1',
    roleCode: 'org_admin',
    memberId: 'member-1',
  };

  function buildService(params: {
    gateway: { id: string; installationId: string } | null;
    zone: { id: string; installationId: string } | null;
  }) {
    const runInTenantContext = jest.fn(async (_ctx: unknown, fn: (tx: unknown) => unknown) =>
      fn({
        gateway: {
          findFirst: jest.fn().mockResolvedValue(params.gateway),
          findUniqueOrThrow: jest.fn().mockResolvedValue(params.gateway),
        },
        zone: { findFirst: jest.fn().mockResolvedValue(params.zone) },
        device: { create: jest.fn().mockResolvedValue({ id: 'device-1' }) },
      }),
    );
    const prisma = { runInTenantContext } as unknown as PrismaService;
    const auditLog = { record: jest.fn() } as unknown as AuditLogService;
    return new DevicesService(prisma, auditLog);
  }

  it('rechaza con 400 si la zona pertenece a una instalación distinta a la del gateway', async () => {
    const service = buildService({
      gateway: { id: 'gw-1', installationId: 'inst-A' },
      zone: { id: 'zone-1', installationId: 'inst-B' },
    });
    await expect(
      service.create(orgAdmin, 'gw-1', {
        zoneId: 'zone-1',
        externalIdentifier: 'S1',
        name: 'Sensor 1',
      }),
    ).rejects.toThrow(BadRequestException);
  });

  it('acepta cuando la zona pertenece a la misma instalación que el gateway', async () => {
    const service = buildService({
      gateway: { id: 'gw-1', installationId: 'inst-A' },
      zone: { id: 'zone-1', installationId: 'inst-A' },
    });
    await expect(
      service.create(orgAdmin, 'gw-1', {
        zoneId: 'zone-1',
        externalIdentifier: 'S1',
        name: 'Sensor 1',
      }),
    ).resolves.toEqual({ id: 'device-1' });
  });

  it('devuelve 404 si el gateway no existe', async () => {
    const service = buildService({
      gateway: null,
      zone: { id: 'zone-1', installationId: 'inst-A' },
    });
    await expect(
      service.create(orgAdmin, 'gw-missing', {
        zoneId: 'zone-1',
        externalIdentifier: 'S1',
        name: 'Sensor 1',
      }),
    ).rejects.toThrow(NotFoundException);
  });
});
