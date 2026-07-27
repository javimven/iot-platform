import {
  PERMISSION_ACTIONS,
  PLATFORM_ACTIONS,
  PLATFORM_DIRECTORY_ACTIONS,
  platformAdminHasDirectoryPermission,
  roleHasPermission,
  ROLE_CODES,
} from './permissions';

/**
 * TESTING_STRATEGY.md §8: la matriz de PERMISSIONS.md se usa como dato de
 * prueba — si PERMISSIONS.md cambia sin actualizar `permissions.ts`, estas
 * aserciones (transcritas directamente de la tabla de la sección 4) fallan.
 */
describe('permission matrix (PERMISSIONS.md §4)', () => {
  it('Admin de organización tiene audit.read_technical además de audit.read_full (endpoint compartido, Etapa 13)', () => {
    expect(roleHasPermission('org_admin', 'audit.read_full')).toBe(true);
    expect(roleHasPermission('org_admin', 'audit.read_technical')).toBe(true);
  });

  it('Admin de organización puede gestionar miembros; Técnico/Operador/Solo lectura no', () => {
    expect(roleHasPermission('org_admin', 'members.invite')).toBe(true);
    expect(roleHasPermission('technician', 'members.invite')).toBe(false);
    expect(roleHasPermission('operator', 'members.invite')).toBe(false);
    expect(roleHasPermission('read_only', 'members.invite')).toBe(false);
  });

  it('Técnico puede gestionar Directorio IoT pero no miembros ni auditoría completa', () => {
    expect(roleHasPermission('technician', 'gateways.create')).toBe(true);
    expect(roleHasPermission('technician', 'sensors.update')).toBe(true);
    expect(roleHasPermission('technician', 'members.read')).toBe(false);
    expect(roleHasPermission('technician', 'audit.read_full')).toBe(false);
    expect(roleHasPermission('technician', 'audit.read_technical')).toBe(true);
  });

  it('Operador puede reconocer/resolver alertas pero no gestionar infraestructura', () => {
    expect(roleHasPermission('operator', 'alerts.acknowledge')).toBe(true);
    expect(roleHasPermission('operator', 'alerts.resolve')).toBe(true);
    expect(roleHasPermission('operator', 'gateways.create')).toBe(false);
    expect(roleHasPermission('operator', 'zones.update')).toBe(false);
  });

  it('Solo lectura no puede reconocer ni resolver alertas', () => {
    expect(roleHasPermission('read_only', 'alerts.read')).toBe(true);
    expect(roleHasPermission('read_only', 'alerts.acknowledge')).toBe(false);
    expect(roleHasPermission('read_only', 'alerts.resolve')).toBe(false);
  });

  it('todos los roles pueden gestionar sus propias sesiones', () => {
    for (const role of ROLE_CODES) {
      expect(roleHasPermission(role, 'sessions.read_own')).toBe(true);
      expect(roleHasPermission(role, 'sessions.revoke_own')).toBe(true);
    }
  });

  it('solo Admin de organización puede revocar sesiones de otros miembros', () => {
    expect(roleHasPermission('org_admin', 'sessions.revoke_others')).toBe(true);
    expect(roleHasPermission('technician', 'sessions.revoke_others')).toBe(false);
  });

  it('el Admin de plataforma tiene la excepción de Directorio IoT (ADR-0005) pero no telemetría/alertas/miembros', () => {
    expect(platformAdminHasDirectoryPermission('gateways.create')).toBe(true);
    expect(platformAdminHasDirectoryPermission('installations.delete')).toBe(true);
    expect(platformAdminHasDirectoryPermission('telemetry.read_latest')).toBe(false);
    expect(platformAdminHasDirectoryPermission('alerts.read')).toBe(false);
    expect(platformAdminHasDirectoryPermission('members.read')).toBe(false);
  });

  it('platform.organizations.* y org_features.update son exclusivos del Admin de plataforma', () => {
    expect(PLATFORM_ACTIONS).toContain('platform.organizations.create');
    expect(PLATFORM_ACTIONS).toContain('org_features.update');
    // Ninguna acción de plataforma aparece en la matriz de roles de organización,
    // salvo org_features.read, que también es una acción de organización.
    for (const action of PLATFORM_ACTIONS) {
      expect((PERMISSION_ACTIONS as readonly string[]).includes(action)).toBe(
        action === 'org_features.read',
      );
    }
  });

  it('PLATFORM_DIRECTORY_ACTIONS es un subconjunto de PERMISSION_ACTIONS', () => {
    for (const action of PLATFORM_DIRECTORY_ACTIONS) {
      expect(PERMISSION_ACTIONS as readonly string[]).toContain(action);
    }
  });
});
