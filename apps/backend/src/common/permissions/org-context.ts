import { ForbiddenException } from '@nestjs/common';
import { TenantContext } from '../prisma/prisma.service';
import { AccessTokenClaims } from '../guards/jwt-auth.guard';

/**
 * Resuelve la organización efectiva de una petición sobre Directorio IoT
 * (API_DESIGN.md §2): la ruta de miembro toma `organizationId` del JWT; la
 * ruta de plataforma ([ADR-0005](../../../../docs/ADR/0005-admin-plataforma-gestion-global-iot.md))
 * lo recibe explícito en el path porque el Admin de plataforma no tiene una
 * organización activa. Ambas reutilizan el mismo servicio de aplicación.
 */
export interface EffectiveOrgContext {
  organizationId: string;
  tenantContext: TenantContext;
}

export function resolveOrgContext(
  user: AccessTokenClaims,
  explicitOrganizationId?: string,
): EffectiveOrgContext {
  if (explicitOrganizationId) {
    if (!user.isPlatformAdmin) {
      // Defensa en profundidad: PermissionsGuard ya debería haber bloqueado
      // esto antes de llegar aquí (solo el Admin de plataforma usa la ruta
      // /platform/organizations/{id}/...), pero un servicio nunca debe
      // asumir que el guard es la única barrera.
      throw new ForbiddenException('Only platform admins can act on an explicit organization');
    }
    return {
      organizationId: explicitOrganizationId,
      tenantContext: { userId: user.sub, isPlatformAdmin: true },
    };
  }

  if (!user.organizationId) {
    throw new ForbiddenException('No active organization');
  }

  return {
    organizationId: user.organizationId,
    tenantContext: { userId: user.sub, organizationId: user.organizationId },
  };
}
