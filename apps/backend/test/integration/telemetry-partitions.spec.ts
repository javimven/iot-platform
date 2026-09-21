import { PrismaClient } from '@prisma/client';

/**
 * La función `crear_particiones_telemetry` (migración 0006) contra un Postgres
 * real, como la de RLS: lo que falló el 2026-09-16 fue precisamente la base de
 * datos rechazando filas de un mes sin partición (BACKLOG.md #45), algo que
 * ninguna prueba con `PrismaService` mockeado puede ver.
 *
 * Requiere `DATABASE_URL` con las migraciones aplicadas (TESTING_STRATEGY.md §4).
 */
describe('Particiones mensuales de telemetry (Postgres real)', () => {
  const prisma = new PrismaClient();

  const nombresEsperados = (meses: number): string[] => {
    const hoy = new Date();
    return Array.from({ length: meses + 1 }, (_, i) => {
      const fecha = new Date(Date.UTC(hoy.getUTCFullYear(), hoy.getUTCMonth() + i, 1));
      const mes = `${fecha.getUTCMonth() + 1}`.padStart(2, '0');
      return `telemetry_${fecha.getUTCFullYear()}_${mes}`;
    });
  };

  const particiones = async (): Promise<string[]> => {
    const filas = await prisma.$queryRaw<{ relname: string }[]>`
      SELECT c.relname
      FROM pg_class c
      JOIN pg_inherits i ON i.inhrelid = c.oid
      JOIN pg_class p ON p.oid = i.inhparent
      WHERE p.relname = 'telemetry'
    `;
    return filas.map((f) => f.relname);
  };

  afterAll(async () => {
    await prisma.$disconnect();
  });

  it('deja creadas las particiones del mes actual y de los siguientes', async () => {
    await prisma.$queryRaw`SELECT crear_particiones_telemetry(3::int)`;

    const existentes = await particiones();
    for (const nombre of nombresEsperados(3)) {
      expect(existentes).toContain(nombre);
    }
  });

  it('es idempotente: llamarla otra vez no crea ninguna', async () => {
    const [{ crear_particiones_telemetry: creadas }] = await prisma.$queryRaw<
      { crear_particiones_telemetry: number }[]
    >`SELECT crear_particiones_telemetry(3::int)`;

    expect(Number(creadas)).toBe(0);
  });

  it('con un mes de margen, el dato del mes que viene ya tiene sitio', async () => {
    // El fallo real: "no partition of relation telemetry found for row".
    const [{ existe }] = await prisma.$queryRaw<{ existe: boolean }[]>`
      SELECT to_regclass(${nombresEsperados(1)[1]}) IS NOT NULL AS existe
    `;
    expect(existe).toBe(true);
  });

  it('rechaza un margen absurdo en vez de crear cientos de tablas', async () => {
    await expect(prisma.$queryRaw`SELECT crear_particiones_telemetry(99::int)`).rejects.toThrow(
      /meses fuera de rango/,
    );
  });
});
