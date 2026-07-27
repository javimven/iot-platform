import { CanActivate, ExecutionContext, ForbiddenException, Injectable } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { REQUIRE_PERMISSION_KEY } from '../decorators/require-permission.decorator';
import {
  PermissionAction,
  PlatformAction,
  PLATFORM_ACTIONS,
  platformAdminHasDirectoryPermission,
  roleHasPermission,
} from '../permissions/permissions';
import { AuthenticatedRequest } from './jwt-auth.guard';

/**
 * Aplica PERMISSIONS.md §4-5 sobre cada endpoint anotado con
 * @RequirePermission. El Admin de plataforma nunca cae en `roleHasPermission`
 * (no tiene `roleCode`, ETAPA 3 — no es un rol de organización): se evalúa
 * contra PLATFORM_ACTIONS o la excepción de Directorio IoT (ADR-0005).
 */
@Injectable()
export class PermissionsGuard implements CanActivate {
  constructor(private readonly reflector: Reflector) {}

  canActivate(context: ExecutionContext): boolean {
    const action = this.reflector.getAllAndOverride<PermissionAction | PlatformAction | undefined>(
      REQUIRE_PERMISSION_KEY,
      [context.getHandler(), context.getClass()],
    );
    if (!action) {
      return true; // Endpoint sin permiso específico anotado (p. ej. /me).
    }

    const request = context.switchToHttp().getRequest<AuthenticatedRequest>();
    const { authContext } = request;

    if (authContext.isPlatformAdmin) {
      // PLATFORM_DIRECTORY_ACTIONS es un subconjunto de PermissionAction
      // (ADR-0005) — el cast es seguro: si `action` fuera una PlatformAction
      // pura (p. ej. `platform.organizations.create`), simplemente no estará
      // en esa lista y `platformAdminHasDirectoryPermission` devolverá false.
      const allowed =
        (PLATFORM_ACTIONS as readonly string[]).includes(action) ||
        platformAdminHasDirectoryPermission(action as PermissionAction);
      if (!allowed) {
        throw new ForbiddenException(`Platform admin cannot perform action: ${action}`);
      }
      return true;
    }

    if (!authContext.roleCode) {
      throw new ForbiddenException('No active organization role');
    }

    // Un endpoint de organización nunca se anota con una PlatformAction pura
    // (solo las rutas /platform/* lo hacen, y esas exigen isPlatformAdmin más
    // arriba) — el cast es seguro en la práctica; si algún día se anotara mal,
    // `roleHasPermission` simplemente no encontraría la acción y denegaría.
    if (!roleHasPermission(authContext.roleCode, action as PermissionAction)) {
      throw new ForbiddenException(`Role ${authContext.roleCode} cannot perform action: ${action}`);
    }

    return true;
  }
}
