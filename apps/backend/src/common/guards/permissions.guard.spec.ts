import { ExecutionContext, ForbiddenException } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { PermissionsGuard } from './permissions.guard';
import { AccessTokenClaims } from './jwt-auth.guard';

/**
 * PERMISSIONS.md §4-5 aplicado por endpoint. El caso mixto (Admin de
 * plataforma que además es miembro) salió en staging: su sesión lleva
 * `isPlatformAdmin` y `roleCode`, y la pantalla "Estaciones" recibía 403 al
 * leer la telemetría de su propia organización.
 */
describe('PermissionsGuard', () => {
  function check(action: string, claims: Partial<AccessTokenClaims>) {
    const reflector = {
      getAllAndOverride: jest.fn().mockReturnValue(action),
    } as unknown as Reflector;
    const context = {
      getHandler: () => undefined,
      getClass: () => undefined,
      switchToHttp: () => ({ getRequest: () => ({ authContext: { sub: 'user-1', ...claims } }) }),
    } as unknown as ExecutionContext;
    return () => new PermissionsGuard(reflector).canActivate(context);
  }

  const mixedSession = {
    isPlatformAdmin: true,
    organizationId: 'org-1',
    memberId: 'member-1',
    roleCode: 'org_admin',
  } as const;

  it('Admin de plataforma puro no usa las rutas de telemetría de miembro (PERMISSIONS.md §5)', () => {
    expect(check('telemetry.read_latest', { isPlatformAdmin: true })).toThrow(ForbiddenException);
  });

  it('la telemetría de cualquier organización se lee por la ruta de plataforma, solo como Admin de plataforma (ADR-0007)', () => {
    expect(check('platform.telemetry.read', { isPlatformAdmin: true })()).toBe(true);
    expect(check('platform.telemetry.read', mixedSession)()).toBe(true);
    expect(
      check('platform.telemetry.read', { organizationId: 'org-1', roleCode: 'org_admin' }),
    ).toThrow(ForbiddenException);
  });

  it('Admin de plataforma puro sí gestiona Directorio IoT (ADR-0005)', () => {
    expect(check('gateways.read', { isPlatformAdmin: true })()).toBe(true);
  });

  it('Admin de plataforma que es miembro lee la telemetría de su organización por su rol', () => {
    expect(check('telemetry.read_latest', mixedSession)()).toBe(true);
    expect(check('telemetry.read_history', mixedSession)()).toBe(true);
  });

  it('en sesión mixta conserva las acciones de plataforma', () => {
    expect(check('platform.organizations.create', mixedSession)()).toBe(true);
  });

  it('en sesión mixta su rol no le da lo que ni el rol ni la plataforma permiten', () => {
    expect(check('members.invite', { ...mixedSession, roleCode: 'read_only' })).toThrow(
      ForbiddenException,
    );
  });

  it('un miembro normal sigue limitado a su rol', () => {
    expect(
      check('telemetry.read_latest', { organizationId: 'org-1', roleCode: 'read_only' })(),
    ).toBe(true);
    expect(check('gateways.create', { organizationId: 'org-1', roleCode: 'read_only' })).toThrow(
      ForbiddenException,
    );
  });
});
