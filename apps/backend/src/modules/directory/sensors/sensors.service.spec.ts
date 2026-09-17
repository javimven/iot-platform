import { BadRequestException } from '@nestjs/common';
import { SensorsService } from './sensors.service';
import { PrismaService } from '../../../common/prisma/prisma.service';
import { AuditLogService } from '../../../common/audit/audit-log.service';
import { AccessTokenClaims } from '../../../common/guards/jwt-auth.guard';

/** FUNCTIONAL_REQUIREMENTS.md §7: un dispositivo tiene hasta 4 sensores (límite de negocio). */
describe('SensorsService', () => {
  const orgAdmin: AccessTokenClaims = {
    sub: 'user-1',
    type: 'access',
    organizationId: 'org-1',
    roleCode: 'org_admin',
    memberId: 'member-1',
  };

  function buildMocks(existingSensorCount: number) {
    const device = {
      id: 'device-1',
      zone: { installationId: 'inst-A' },
      _count: { sensors: existingSensorCount },
    };
    const tx = {
      device: { findFirst: jest.fn().mockResolvedValue(device) },
      sensor: {
        create: jest.fn().mockResolvedValue({ id: 'sensor-new' }),
        findMany: jest.fn().mockResolvedValue([]),
      },
    };
    const runInTenantContext = jest.fn(async (_ctx: unknown, fn: (t: unknown) => unknown) =>
      fn(tx),
    );
    const prisma = { runInTenantContext } as unknown as PrismaService;
    const auditLog = { record: jest.fn() } as unknown as AuditLogService;
    return { tx, service: new SensorsService(prisma, auditLog) };
  }

  function buildService(existingSensorCount: number) {
    return buildMocks(existingSensorCount).service;
  }

  it('permite crear el cuarto sensor de un dispositivo', async () => {
    const service = buildService(3);
    await expect(
      service.create(orgAdmin, 'device-1', { externalIdentifier: 'S4' }),
    ).resolves.toEqual({ id: 'sensor-new' });
  });

  it('rechaza crear un quinto sensor en el mismo dispositivo', async () => {
    const service = buildService(4);
    await expect(
      service.create(orgAdmin, 'device-1', { externalIdentifier: 'S5' }),
    ).rejects.toThrow(BadRequestException);
  });

  describe('datos del propio equipo (ADR-0008)', () => {
    it('no se pueden registrar a mano con el identificador reservado', async () => {
      const { tx, service } = buildMocks(0);
      await expect(
        service.create(orgAdmin, 'device-1', { externalIdentifier: '_device' }),
      ).rejects.toThrow(BadRequestException);
      expect(tx.sensor.create).not.toHaveBeenCalled();
    });

    it('no cuentan para el máximo de 4 sensores', async () => {
      const { tx, service } = buildMocks(3);
      await service.create(orgAdmin, 'device-1', { externalIdentifier: 'S4' });
      expect(tx.device.findFirst.mock.calls[0][0].include._count.select.sensors.where).toEqual({
        deletedAt: null,
        externalIdentifier: { not: '_device' },
      });
    });

    it('no salen en la lista de sensores del dispositivo', async () => {
      const { tx, service } = buildMocks(0);
      await service.findAllForDevice(orgAdmin, 'device-1');
      expect(tx.sensor.findMany).toHaveBeenCalledWith({
        where: { deviceId: 'device-1', deletedAt: null, externalIdentifier: { not: '_device' } },
      });
    });
  });
});
