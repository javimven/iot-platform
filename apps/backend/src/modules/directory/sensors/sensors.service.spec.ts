import { BadRequestException } from '@nestjs/common';
import { SensorsService } from './sensors.service';
import { PrismaService } from '../../../common/prisma/prisma.service';
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

  function buildService(existingSensorCount: number) {
    const device = {
      id: 'device-1',
      zone: { installationId: 'inst-A' },
      _count: { sensors: existingSensorCount },
    };
    const runInTenantContext = jest.fn(async (_ctx: unknown, fn: (tx: unknown) => unknown) =>
      fn({
        device: { findFirst: jest.fn().mockResolvedValue(device) },
        sensor: { create: jest.fn().mockResolvedValue({ id: 'sensor-new' }) },
      }),
    );
    const prisma = { runInTenantContext } as unknown as PrismaService;
    return new SensorsService(prisma);
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
});
