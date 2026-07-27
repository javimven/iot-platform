import { resolveInstallationScope, scopeWhereClause } from './installation-scope';
import { PrismaService } from '../prisma/prisma.service';

/**
 * PERMISSIONS.md §2: sin asignación = todas las instalaciones (por defecto);
 * con asignación = allowlist. Admin de organización y Admin de plataforma
 * nunca están restringidos.
 */
describe('resolveInstallationScope', () => {
  function buildPrisma(scopeRows: Array<{ installationId: string }>) {
    return {
      memberInstallationScope: {
        findMany: jest.fn().mockResolvedValue(scopeRows),
      },
    } as unknown as PrismaService;
  }

  it('Admin de organización siempre tiene acceso a todas las instalaciones', async () => {
    const prisma = buildPrisma([{ installationId: 'inst-1' }]);
    const scope = await resolveInstallationScope(prisma, {
      memberId: 'member-1',
      roleCode: 'org_admin',
    });
    expect(scope).toBe('all');
  });

  it('Admin de plataforma siempre tiene acceso a todas las instalaciones', async () => {
    const prisma = buildPrisma([]);
    const scope = await resolveInstallationScope(prisma, { isPlatformAdmin: true });
    expect(scope).toBe('all');
  });

  it('Técnico sin asignación ve todas las instalaciones (comportamiento por defecto)', async () => {
    const prisma = buildPrisma([]);
    const scope = await resolveInstallationScope(prisma, {
      memberId: 'member-2',
      roleCode: 'technician',
    });
    expect(scope).toBe('all');
  });

  it('Técnico con asignación queda restringido exactamente a esas instalaciones', async () => {
    const prisma = buildPrisma([{ installationId: 'inst-1' }, { installationId: 'inst-2' }]);
    const scope = await resolveInstallationScope(prisma, {
      memberId: 'member-2',
      roleCode: 'technician',
    });
    expect(scope).toEqual(['inst-1', 'inst-2']);
  });
});

describe('scopeWhereClause', () => {
  it('devuelve una cláusula vacía cuando el alcance es "all"', () => {
    expect(scopeWhereClause('all')).toEqual({});
  });

  it('devuelve un filtro `in` sobre la columna indicada cuando el alcance está restringido', () => {
    expect(scopeWhereClause(['a', 'b'], 'installationId')).toEqual({
      installationId: { in: ['a', 'b'] },
    });
    expect(scopeWhereClause(['a'], 'id')).toEqual({ id: { in: ['a'] } });
  });
});
