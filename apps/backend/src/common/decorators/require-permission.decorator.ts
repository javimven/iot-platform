import { SetMetadata } from '@nestjs/common';
import { PermissionAction, PlatformAction } from '../permissions/permissions';

/**
 * Decorador de autorización (PERMISSIONS.md §5): la autorización real siempre
 * se revalida en el backend — nunca se confía en lo que el frontend oculta o
 * muestra (principio ya fijado desde el inicio del proyecto). Acepta tanto
 * acciones de organización (`PermissionAction`) como de plataforma
 * (`PlatformAction`, p. ej. `platform.organizations.create`) — son catálogos
 * separados (PERMISSIONS.md §3) pero un mismo decorador basta para ambos.
 */
export const REQUIRE_PERMISSION_KEY = 'requirePermission';
export const RequirePermission = (
  action: PermissionAction | PlatformAction,
): ReturnType<typeof SetMetadata> => SetMetadata(REQUIRE_PERMISSION_KEY, action);
