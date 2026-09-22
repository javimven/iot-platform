/**
 * Matriz de permisos como código (PERMISSIONS.md §3-4). Fuente única de verdad:
 * vive en código, no en una tabla editable (Etapa 4 — no configurable por
 * organización en el MVP). TESTING_STRATEGY.md §8 usa este mismo objeto como
 * dato de prueba, para que la matriz documentada y el comportamiento real no
 * puedan divergir en silencio.
 *
 * "Alcance" (instalación, PERMISSIONS.md §2) no se codifica aquí: esta matriz
 * solo responde "¿puede este rol, en principio, hacer esta acción?" — el
 * filtro de alcance se aplica después, sobre los propios datos, en los módulos
 * que gestionan Directorio IoT (aún no implementados en este paso de la
 * Etapa 13).
 */

export const ROLE_CODES = ['org_admin', 'technician', 'operator', 'read_only'] as const;
export type RoleCode = (typeof ROLE_CODES)[number];

export const PERMISSION_ACTIONS = [
  'org.profile.read',
  'org.profile.update',
  'members.read',
  'members.invite',
  'members.update_role',
  'members.suspend',
  'members.reactivate',
  'members.remove',
  'member_scope.read',
  'member_scope.assign',
  'installations.create',
  'installations.read',
  'installations.update',
  'installations.delete',
  'parcels.create',
  'parcels.read',
  'parcels.update',
  'parcels.delete',
  'zones.create',
  'zones.read',
  'zones.update',
  'zones.delete',
  'gateways.create',
  'gateways.read',
  'gateways.update',
  'gateways.disable',
  'gateways.rotate_credential',
  'devices.create',
  'devices.read',
  'devices.update',
  'devices.disable',
  'sensors.create',
  'sensors.read',
  'sensors.update',
  'sensors.delete',
  'channels.read',
  'channels.update_threshold',
  'telemetry.read_latest',
  'telemetry.read_history',
  // Satelite (BACKLOG.md #36). `satellite.read` cubre observaciones, metricas
  // y assets de una parcela; `satellite.refresh` es forzar una busqueda a
  // mano: util para diagnostico, pero gasta cuota de Copernicus, asi que no
  // la tiene quien solo consulta.
  'satellite.read',
  'satellite.refresh',
  // Campañas y cuaderno de campo (BACKLOG.md #60). `campaigns.record` es
  // registrar lo que se ha hecho (actividades, fotos, documentos) y va aparte
  // de `campaigns.update` (la campaña en si, sus unidades de cultivo, los
  // catalogos): quien trabaja en el campo apunta lo que hace sin poder
  // cambiar como esta montada la campaña. Exportar el cuaderno es leerlo:
  // entra en `campaigns.read`.
  'campaigns.read',
  'campaigns.record',
  'campaigns.create',
  'campaigns.update',
  'campaigns.close',
  'campaigns.delete',
  'alerts.read',
  'alerts.acknowledge',
  'alerts.resolve',
  'sessions.read_own',
  'sessions.revoke_own',
  'sessions.read_others',
  'sessions.revoke_others',
  'audit.read_full',
  'audit.read_technical',
  'org_features.read',
] as const;
export type PermissionAction = (typeof PERMISSION_ACTIONS)[number];

/** Matriz rol de organización -> acciones permitidas (PERMISSIONS.md §4). */
export const ROLE_PERMISSIONS: Record<RoleCode, PermissionAction[]> = {
  org_admin: [
    'org.profile.read',
    'org.profile.update',
    'members.read',
    'members.invite',
    'members.update_role',
    'members.suspend',
    'members.reactivate',
    'members.remove',
    'member_scope.read',
    'member_scope.assign',
    'installations.create',
    'installations.read',
    'installations.update',
    'installations.delete',
    'parcels.create',
    'parcels.read',
    'parcels.update',
    'parcels.delete',
    'zones.create',
    'zones.read',
    'zones.update',
    'zones.delete',
    'gateways.create',
    'gateways.read',
    'gateways.update',
    'gateways.disable',
    'gateways.rotate_credential',
    'devices.create',
    'devices.read',
    'devices.update',
    'devices.disable',
    'sensors.create',
    'sensors.read',
    'sensors.update',
    'sensors.delete',
    'channels.read',
    'channels.update_threshold',
    'telemetry.read_latest',
    'telemetry.read_history',
    'satellite.read',
    'satellite.refresh',
    'campaigns.read',
    'campaigns.record',
    'campaigns.create',
    'campaigns.update',
    'campaigns.close',
    'campaigns.delete',
    'alerts.read',
    'alerts.acknowledge',
    'alerts.resolve',
    'sessions.read_own',
    'sessions.revoke_own',
    'sessions.read_others',
    'sessions.revoke_others',
    'audit.read_full',
    // `audit.read_technical` explícito también aquí (no solo `audit.read_full`):
    // PERMISSIONS.md §4 dice "incluida en full", y el endpoint compartido de
    // auditoría (AuditController) exige literalmente uno de los dos permisos
    // — sin esto, un Admin de organización quedaría bloqueado por el guard
    // (descubierto al implementar el controlador, Etapa 13).
    'audit.read_technical',
    'org_features.read',
  ],
  technician: [
    'org.profile.read',
    'installations.read',
    'parcels.create',
    'parcels.read',
    'parcels.update',
    'zones.create',
    'zones.read',
    'zones.update',
    'zones.delete',
    'gateways.create',
    'gateways.read',
    'gateways.update',
    'gateways.disable',
    'gateways.rotate_credential',
    'devices.create',
    'devices.read',
    'devices.update',
    'devices.disable',
    'sensors.create',
    'sensors.read',
    'sensors.update',
    'sensors.delete',
    'channels.read',
    'channels.update_threshold',
    'telemetry.read_latest',
    'telemetry.read_history',
    'satellite.read',
    'satellite.refresh',
    // Sin `campaigns.delete`, como con las parcelas: borrar una campaña se
    // lleva su cuaderno.
    'campaigns.read',
    'campaigns.record',
    'campaigns.create',
    'campaigns.update',
    'campaigns.close',
    'alerts.read',
    'alerts.acknowledge',
    'alerts.resolve',
    'sessions.read_own',
    'sessions.revoke_own',
    'audit.read_technical',
  ],
  operator: [
    'org.profile.read',
    'installations.read',
    'parcels.read',
    'zones.read',
    'gateways.read',
    'devices.read',
    'sensors.read',
    'channels.read',
    'telemetry.read_latest',
    'telemetry.read_history',
    'satellite.read',
    // El operario registra lo que hace en campo; no monta ni cierra campañas.
    'campaigns.read',
    'campaigns.record',
    'alerts.read',
    'alerts.acknowledge',
    'alerts.resolve',
    'sessions.read_own',
    'sessions.revoke_own',
  ],
  read_only: [
    'org.profile.read',
    'installations.read',
    'parcels.read',
    'zones.read',
    'gateways.read',
    'devices.read',
    'sensors.read',
    'channels.read',
    'telemetry.read_latest',
    'telemetry.read_history',
    'satellite.read',
    'campaigns.read',
    'alerts.read',
    'sessions.read_own',
    'sessions.revoke_own',
  ],
};

/**
 * Acciones del Admin de plataforma. `platform.*` no está en PERMISSION_ACTIONS
 * (vive fuera del contexto de organización, PERMISSIONS.md §3) — se modela
 * aparte porque no es un rol de `members`, es la tabla `platform_admins`
 * (DATA_MODEL.md §3).
 */
export const PLATFORM_ACTIONS = [
  'platform.organizations.create',
  'platform.organizations.read',
  'platform.organizations.suspend',
  'platform.organizations.reactivate',
  'platform.audit.read',
  // Solo lectura de telemetría de cualquier organización (ADR-0007).
  'platform.telemetry.read',
  'org_features.update',
  'org_features.read',
] as const;
export type PlatformAction = (typeof PLATFORM_ACTIONS)[number];

/**
 * Directorio IoT: excepción global y auditada del Admin de plataforma
 * (ADR-0005, PERMISSIONS.md §4 nota ²) — mismas acciones que un Admin de
 * organización, pero sin pertenecer a la organización.
 */
export const PLATFORM_DIRECTORY_ACTIONS: PermissionAction[] = [
  'installations.create',
  'installations.read',
  'installations.update',
  'installations.delete',
  'zones.create',
  'zones.read',
  'zones.update',
  'zones.delete',
  'gateways.create',
  'gateways.read',
  'gateways.update',
  'gateways.disable',
  'gateways.rotate_credential',
  'devices.create',
  'devices.read',
  'devices.update',
  'devices.disable',
  'sensors.create',
  'sensors.read',
  'sensors.update',
  'sensors.delete',
  'channels.read',
  'channels.update_threshold',
];

export function roleHasPermission(role: RoleCode, action: PermissionAction): boolean {
  return ROLE_PERMISSIONS[role].includes(action);
}

export function platformAdminHasDirectoryPermission(action: PermissionAction): boolean {
  return PLATFORM_DIRECTORY_ACTIONS.includes(action);
}
