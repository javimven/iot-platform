import { PrismaService } from '../prisma/prisma.service';
import { RoleCode } from './permissions';

/**
 * Alcance por instalación (PERMISSIONS.md §2): 'all' si el miembro no tiene
 * ninguna instalación asignada (comportamiento por defecto — no obliga a
 * configurar cada miembro desde el día 1), o la lista concreta de
 * instalaciones a las que se restringe. Es una regla de autorización de
 * aplicación, no una barrera de aislamiento multitenant (esa ya la aplica
 * RLS) — nunca se implementa como política de base de datos.
 */
export type InstallationScope = 'all' | string[];

export async function resolveInstallationScope(
  prisma: PrismaService,
  params: { memberId?: string; roleCode?: RoleCode; isPlatformAdmin?: boolean },
): Promise<InstallationScope> {
  // El Admin de plataforma (ADR-0005) y el Admin de organización nunca están
  // restringidos por alcance (PERMISSIONS.md §2, by design).
  if (params.isPlatformAdmin || params.roleCode === 'org_admin' || !params.memberId) {
    return 'all';
  }

  const rows = await prisma.memberInstallationScope.findMany({
    where: { memberId: params.memberId },
    select: { installationId: true },
  });

  return rows.length === 0 ? 'all' : rows.map((r) => r.installationId);
}

/** Traduce el alcance a una cláusula `where` de Prisma sobre una columna `installationId`. */
export function scopeWhereClause(
  scope: InstallationScope,
  column: 'id' | 'installationId' = 'installationId',
): Record<string, unknown> {
  return scope === 'all' ? {} : { [column]: { in: scope } };
}
