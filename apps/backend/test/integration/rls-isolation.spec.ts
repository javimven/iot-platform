import { PrismaClient } from '@prisma/client';
import { randomUUID } from 'node:crypto';
import { PrismaService } from '../../src/common/prisma/prisma.service';

/**
 * Prueba de integración contra un Postgres real (TESTING_STRATEGY.md §4) —
 * requiere `DATABASE_URL` apuntando a la base de datos de desarrollo/CI,
 * conectada con el rol de aplicación real (`iot_platform_app`, sin
 * `BYPASSRLS`/superusuario — `infra/docker/postgres-init/01-app-role.sql`),
 * nunca con el rol dueño de las tablas.
 *
 * Existe porque las pruebas unitarias (`src/**\/*.spec.ts`) mockean
 * `PrismaService` por completo y nunca ejercitan RLS de verdad — dos bugs
 * críticos de aislamiento multi-tenant (DATA_MODEL.md §7/§9) fueron
 * invisibles para toda la suite unitaria hasta la primera vez que este
 * proyecto corrió contra un Postgres real (2026-07-28):
 * 1. El rol de conexión de la aplicación se saltaba RLS por completo
 *    (dueño de las tablas / superusuario de arranque de la imagen oficial
 *    de Postgres).
 * 2. `set_config(name, NULL, true)` no guarda `NULL` real (lo convierte en
 *    `''`), y `''::uuid` lanza un error real de Postgres en vez de
 *    evaluarse a `NULL` — cualquier login (sin `organizationId` todavía)
 *    rompía con un 500.
 */
describe('Aislamiento multi-tenant vía RLS (Postgres real)', () => {
  let prisma: PrismaService;
  let orgAId: string;
  let orgBId: string;

  beforeAll(async () => {
    if (!process.env.DATABASE_URL) {
      throw new Error(
        'DATABASE_URL no está definida — esta prueba necesita un Postgres real (TESTING_STRATEGY.md §4), no se puede mockear.',
      );
    }
    prisma = new PrismaService();
    await prisma.onModuleInit();

    // Las organizaciones no llevan RLS (DATA_MODEL.md §7) — se crean sin
    // contexto de tenant, igual que en producción (PlatformOrganizationsService).
    const orgA = await prisma.organization.create({
      data: {
        slug: `rls-test-a-${randomUUID().slice(0, 8)}`,
        name: 'RLS Test Org A',
        contactEmail: 'rls-test-a@example.com',
      },
    });
    const orgB = await prisma.organization.create({
      data: {
        slug: `rls-test-b-${randomUUID().slice(0, 8)}`,
        name: 'RLS Test Org B',
        contactEmail: 'rls-test-b@example.com',
      },
    });
    orgAId = orgA.id;
    orgBId = orgB.id;
  });

  afterAll(async () => {
    // Como cualquier código de producción, la limpieza también pasa por
    // `runInTenantContext` — `isPlatformAdmin: true` para poder borrar en
    // ambas organizaciones a la vez (excepción de Directorio IoT, ADR-0005).
    await prisma.runInTenantContext({ isPlatformAdmin: true }, (tx) =>
      tx.installation.deleteMany({ where: { organizationId: { in: [orgAId, orgBId] } } }),
    );
    await prisma.organization.deleteMany({ where: { id: { in: [orgAId, orgBId] } } });
    await prisma.$disconnect();
  });

  it('una organización nunca ve instalaciones de otra organización', async () => {
    await prisma.runInTenantContext({ organizationId: orgAId }, (tx) =>
      tx.installation.create({ data: { organizationId: orgAId, name: 'Instalación A' } }),
    );
    await prisma.runInTenantContext({ organizationId: orgBId }, (tx) =>
      tx.installation.create({ data: { organizationId: orgBId, name: 'Instalación B' } }),
    );

    const seenByA = await prisma.runInTenantContext({ organizationId: orgAId }, (tx) =>
      tx.installation.findMany({ where: { deletedAt: null } }),
    );
    const seenByB = await prisma.runInTenantContext({ organizationId: orgBId }, (tx) =>
      tx.installation.findMany({ where: { deletedAt: null } }),
    );

    expect(seenByA.map((i) => i.name)).toEqual(['Instalación A']);
    expect(seenByB.map((i) => i.name)).toEqual(['Instalación B']);
  });

  it('el rol de conexión de la aplicación no se salta RLS (no es dueño/superusuario)', async () => {
    const rows = await prisma.$queryRaw<Array<{ rolsuper: boolean; rolbypassrls: boolean }>>`
      SELECT rolsuper, rolbypassrls FROM pg_roles WHERE rolname = current_user
    `;
    expect(rows[0].rolsuper).toBe(false);
    expect(rows[0].rolbypassrls).toBe(false);
  });

  it('una consulta sin organizationId todavía conocido (login) no lanza, solo no filtra por org', async () => {
    // Reproduce exactamente AuthService.login -> findActiveMembershipsForUser:
    // contexto con userId pero sin organizationId, antes de saber a qué
    // organización pertenece el usuario.
    await expect(
      prisma.runInTenantContext({ userId: randomUUID() }, (tx) =>
        tx.member.findMany({ where: { status: 'active' } }),
      ),
    ).resolves.not.toThrow();
  });

  it('un cliente Prisma crudo (sin PrismaService) confirma que set_config(NULL) no rompe con NULLIF', async () => {
    const raw = new PrismaClient();
    await raw.$transaction(async (tx) => {
      await tx.$executeRaw`SELECT set_config('app.current_org_id', ${null}, true)`;
      const result = await tx.$queryRaw<Array<{ val: string | null }>>`
        SELECT NULLIF(current_setting('app.current_org_id', true), '')::uuid AS val
      `;
      expect(result[0].val).toBeNull();
    });
    await raw.$disconnect();
  });
});
