import { ExecutionContext, ForbiddenException } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { FeatureGuard } from './feature.guard';
import { PrismaService } from '../prisma/prisma.service';
import { AccessTokenClaims } from './jwt-auth.guard';

/**
 * PERMISSIONS.md §14. El gating de funciones contratadas era solo de
 * interfaz (`LockedFeatureScreen`): valía para una sección vacía, pero no para
 * una que gasta cuota de una API externa. Este guard es el que impide llamar
 * a la ruta a mano.
 */
describe('FeatureGuard', () => {
  function build(params: {
    feature?: string[];
    user: Partial<AccessTokenClaims>;
    contratada?: boolean;
  }) {
    const reflector = {
      getAllAndOverride: jest.fn().mockReturnValue(params.feature),
    } as unknown as Reflector;

    const findFirst = jest.fn().mockResolvedValue(params.contratada ? { enabled: true } : null);
    const prisma = {
      runInTenantContext: jest.fn(async (_ctx: unknown, fn: (tx: unknown) => unknown) =>
        fn({ organizationFeature: { findFirst } }),
      ),
    } as unknown as PrismaService;

    const context = {
      getHandler: () => undefined,
      getClass: () => undefined,
      switchToHttp: () => ({ getRequest: () => ({ authContext: params.user }) }),
    } as unknown as ExecutionContext;

    return { guard: new FeatureGuard(reflector, prisma), context, findFirst, prisma };
  }

  it('deja pasar un endpoint sin función exigida', async () => {
    const { guard, context, prisma } = build({ user: { sub: 'u1', organizationId: 'org-1' } });
    await expect(guard.canActivate(context)).resolves.toBe(true);
    expect(prisma.runInTenantContext).not.toHaveBeenCalled();
  });

  it('deja pasar si la organización tiene la función contratada', async () => {
    const { guard, context, findFirst } = build({
      feature: ['satellite_imagery'],
      user: { sub: 'u1', organizationId: 'org-1' },
      contratada: true,
    });

    await expect(guard.canActivate(context)).resolves.toBe(true);
    expect(findFirst).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({
          featureCode: { in: ['satellite_imagery'] },
          enabled: true,
        }),
      }),
    );
  });

  it('bloquea a una organización que no la tiene, aunque llame a la API directamente', async () => {
    const { guard, context } = build({
      feature: ['satellite_imagery'],
      user: { sub: 'u1', organizationId: 'org-1' },
      contratada: false,
    });

    await expect(guard.canActivate(context)).rejects.toThrow(ForbiddenException);
  });

  it('con varias funciones, basta con tener una: las parcelas son de Satélite y de Campañas', async () => {
    const { guard, context, findFirst } = build({
      feature: ['satellite_imagery', 'campaigns'],
      user: { sub: 'u1', organizationId: 'org-1' },
      contratada: true,
    });

    await expect(guard.canActivate(context)).resolves.toBe(true);
    expect(findFirst).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({ featureCode: { in: ['satellite_imagery', 'campaigns'] } }),
      }),
    );
  });

  it('el mensaje dice qué funciones valdrían, y la app sigue reconociéndolo', async () => {
    const { guard, context } = build({
      feature: ['satellite_imagery', 'campaigns'],
      user: { sub: 'u1', organizationId: 'org-1' },
      contratada: false,
    });

    // La app detecta el 403 por el principio del título (esModuloNoContratado).
    await expect(guard.canActivate(context)).rejects.toThrow(
      /^Feature not enabled for this organization: satellite_imagery, campaigns$/,
    );
  });

  it('el Admin de plataforma sin organización activa no se bloquea (ADR-0005)', async () => {
    const { guard, context, prisma } = build({
      feature: ['satellite_imagery'],
      user: { sub: 'u1', isPlatformAdmin: true },
      contratada: false,
    });

    await expect(guard.canActivate(context)).resolves.toBe(true);
    expect(prisma.runInTenantContext).not.toHaveBeenCalled();
  });

  it('un Admin de plataforma que además es miembro sí pasa por la comprobación de su organización', async () => {
    const { guard, context } = build({
      feature: ['satellite_imagery'],
      user: { sub: 'u1', isPlatformAdmin: true, organizationId: 'org-1' },
      contratada: false,
    });

    await expect(guard.canActivate(context)).rejects.toThrow(ForbiddenException);
  });

  it('sin organización activa, no hay función que comprobar', async () => {
    const { guard, context } = build({ feature: ['satellite_imagery'], user: { sub: 'u1' } });
    await expect(guard.canActivate(context)).rejects.toThrow(/No active organization/);
  });
});
