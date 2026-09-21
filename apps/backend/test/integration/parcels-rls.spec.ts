import { randomUUID } from 'node:crypto';
import { PrismaService } from '../../src/common/prisma/prisma.service';
import { ParcelGeometryService } from '../../src/modules/parcels/parcel-geometry.service';
import { ParcelsRepository } from '../../src/modules/parcels/parcels.repository';

/**
 * Parcelas contra un Postgres real con PostGIS (TESTING_STRATEGY.md §4,
 * migración 0008). Cubre lo que ninguna prueba unitaria puede cubrir porque
 * mockea `PrismaService`:
 *
 * 1. El aislamiento por organización de `parcels` (RLS), que es la razón por
 *    la que la tabla lleva `organization_id`.
 * 2. El trigger `gateway_parcel_matches_installation`: una estación no puede
 *    apuntar a una parcela de otra finca ni de otra organización. Es la
 *    integridad que una clave foránea no sabe expresar — mismo caso que el
 *    trigger Zona<->Gateway de la migración 0002.
 * 3. Que la geometría va y vuelve como GeoJSON en EPSG:4326 y que el área se
 *    calcula en metros sobre el elipsoide, no en grados.
 */
describe('Parcelas: RLS, integridad y geometría (Postgres real)', () => {
  let prisma: PrismaService;
  let orgAId: string;
  let orgBId: string;
  let fincaAId: string;
  let otraFincaAId: string;
  let parcelaAId: string;

  /** Rectángulo de ~100 x 110 m cerca de Valencia, como lo dibujaría la app. */
  const poligono = {
    type: 'Polygon',
    coordinates: [
      [
        [-0.5, 39.5],
        [-0.499, 39.5],
        [-0.499, 39.501],
        [-0.5, 39.501],
        [-0.5, 39.5],
      ],
    ],
  };

  /** Alta de parcela tal y como la hará `ParcelsRepository`: PostGIS calcula área y caja. */
  async function crearParcela(organizationId: string, installationId: string, name: string) {
    const filas = await prisma.runInTenantContext(
      { organizationId },
      (tx) =>
        tx.$queryRaw<Array<{ id: string; area_m2: number }>>`
        INSERT INTO parcels (organization_id, installation_id, name, geometry, area_m2,
                             bbox_min_lon, bbox_min_lat, bbox_max_lon, bbox_max_lat)
        SELECT ${organizationId}::uuid, ${installationId}::uuid, ${name},
               g, ST_Area(g::geography),
               ST_XMin(g::box3d), ST_YMin(g::box3d), ST_XMax(g::box3d), ST_YMax(g::box3d)
        FROM (SELECT ST_Multi(ST_SetSRID(ST_GeomFromGeoJSON(${JSON.stringify(poligono)}), 4326)) AS g) t
        RETURNING id, area_m2
      `,
    );
    return filas[0];
  }

  beforeAll(async () => {
    if (!process.env.DATABASE_URL) {
      throw new Error(
        'DATABASE_URL no está definida — esta prueba necesita un Postgres real con PostGIS (TESTING_STRATEGY.md §4).',
      );
    }
    prisma = new PrismaService();
    await prisma.onModuleInit();

    const orgA = await prisma.organization.create({
      data: {
        slug: `parcels-a-${randomUUID().slice(0, 8)}`,
        name: 'Parcelas Org A',
        contactEmail: 'parcels-a@example.com',
      },
    });
    const orgB = await prisma.organization.create({
      data: {
        slug: `parcels-b-${randomUUID().slice(0, 8)}`,
        name: 'Parcelas Org B',
        contactEmail: 'parcels-b@example.com',
      },
    });
    orgAId = orgA.id;
    orgBId = orgB.id;

    const fincaA = await prisma.runInTenantContext({ organizationId: orgAId }, (tx) =>
      tx.installation.create({ data: { organizationId: orgAId, name: 'Finca A' } }),
    );
    const otraFincaA = await prisma.runInTenantContext({ organizationId: orgAId }, (tx) =>
      tx.installation.create({ data: { organizationId: orgAId, name: 'Otra finca de A' } }),
    );
    fincaAId = fincaA.id;
    otraFincaAId = otraFincaA.id;

    parcelaAId = (await crearParcela(orgAId, fincaAId, 'Parcela de A')).id;
  });

  afterAll(async () => {
    await prisma.runInTenantContext({ isPlatformAdmin: true }, async (tx) => {
      await tx.gateway.deleteMany({ where: { organizationId: { in: [orgAId, orgBId] } } });
      await tx.parcel.deleteMany({ where: { organizationId: { in: [orgAId, orgBId] } } });
      await tx.installation.deleteMany({ where: { organizationId: { in: [orgAId, orgBId] } } });
    });
    await prisma.organization.deleteMany({ where: { id: { in: [orgAId, orgBId] } } });
    await prisma.$disconnect();
  });

  it('una organización nunca ve las parcelas de otra', async () => {
    const vistasPorA = await prisma.runInTenantContext({ organizationId: orgAId }, (tx) =>
      tx.parcel.findMany({ where: { deletedAt: null } }),
    );
    const vistasPorB = await prisma.runInTenantContext({ organizationId: orgBId }, (tx) =>
      tx.parcel.findMany({ where: { deletedAt: null } }),
    );

    expect(vistasPorA.map((p) => p.name)).toEqual(['Parcela de A']);
    expect(vistasPorB).toEqual([]);
  });

  it('la organización ajena tampoco la alcanza pidiéndola por su id', async () => {
    const encontrada = await prisma.runInTenantContext({ organizationId: orgBId }, (tx) =>
      tx.parcel.findFirst({ where: { id: parcelaAId } }),
    );
    expect(encontrada).toBeNull();
  });

  it('la geometría vuelve como GeoJSON en 4326 y el área sale en metros', async () => {
    const filas = await prisma.runInTenantContext(
      { organizationId: orgAId },
      (tx) =>
        tx.$queryRaw<Array<{ tipo: string; srid: number; geojson: string; area_m2: number }>>`
        SELECT ST_GeometryType(geometry) AS tipo, ST_SRID(geometry) AS srid,
               ST_AsGeoJSON(geometry) AS geojson, area_m2
        FROM parcels WHERE id = ${parcelaAId}::uuid
      `,
    );

    expect(filas[0].tipo).toBe('ST_MultiPolygon'); // un Polygon de entrada se normaliza
    expect(filas[0].srid).toBe(4326);
    expect(JSON.parse(filas[0].geojson).type).toBe('MultiPolygon');
    // ~86 m x 111 m: del orden de una hectárea, nunca el 1e-6 que daría medir en grados.
    expect(filas[0].area_m2).toBeGreaterThan(8000);
    expect(filas[0].area_m2).toBeLessThan(11000);
  });

  it('una estación de otra finca no puede asignarse a la parcela', async () => {
    const gateway = await prisma.runInTenantContext({ organizationId: orgAId }, (tx) =>
      tx.gateway.create({
        data: {
          organizationId: orgAId,
          installationId: otraFincaAId,
          externalIdentifier: `gw-otra-finca-${randomUUID().slice(0, 8)}`,
          name: 'Estación de otra finca',
          connectivityType: 'direct_nbiot',
        },
      }),
    );

    await expect(
      prisma.runInTenantContext({ organizationId: orgAId }, (tx) =>
        tx.gateway.update({ where: { id: gateway.id }, data: { parcelId: parcelaAId } }),
      ),
    ).rejects.toThrow(/must belong to the same installation/);
  });

  it('una estación de la misma finca sí se asigna, y puede quedarse sin parcela', async () => {
    const gateway = await prisma.runInTenantContext({ organizationId: orgAId }, (tx) =>
      tx.gateway.create({
        data: {
          organizationId: orgAId,
          installationId: fincaAId,
          externalIdentifier: `gw-misma-finca-${randomUUID().slice(0, 8)}`,
          name: 'Estación de la finca',
          connectivityType: 'direct_nbiot',
        },
      }),
    );
    expect(gateway.parcelId).toBeNull(); // las estaciones existentes siguen sin parcela

    const asignado = await prisma.runInTenantContext({ organizationId: orgAId }, (tx) =>
      tx.gateway.update({ where: { id: gateway.id }, data: { parcelId: parcelaAId } }),
    );
    expect(asignado.parcelId).toBe(parcelaAId);

    const desasignado = await prisma.runInTenantContext({ organizationId: orgAId }, (tx) =>
      tx.gateway.update({ where: { id: gateway.id }, data: { parcelId: null } }),
    );
    expect(desasignado.parcelId).toBeNull();
  });

  it('dos parcelas de la misma finca no pueden llamarse igual', async () => {
    await expect(crearParcela(orgAId, fincaAId, 'Parcela de A')).rejects.toThrow();
  });

  describe('ParcelsRepository contra la base real', () => {
    // El repositorio es el único sitio con SQL escrito a mano (ADR-0009): una
    // errata ahí no la ve ninguna prueba unitaria, porque todas mockean
    // `PrismaService`. Estas sí ejecutan ese SQL de verdad.
    const repositorio = new ParcelsRepository();
    const geometria = new ParcelGeometryService();

    it('crea, lee por id y lista por finca, siempre con el contorno en GeoJSON', async () => {
      const creada = await prisma.runInTenantContext({ organizationId: orgAId }, (tx) =>
        repositorio.crear(tx, {
          organizationId: orgAId,
          installationId: fincaAId,
          name: 'Parcela del repositorio',
          notes: 'con nota',
          geometry: geometria.normalizar(poligono),
        }),
      );

      expect(creada.geometry.type).toBe('MultiPolygon');
      expect(creada.areaM2).toBeGreaterThan(8000);
      expect(creada.bbox).toEqual([-0.5, 39.5, -0.499, 39.501]);
      expect(creada.geometryVersion).toBe(1);
      expect(creada.notes).toBe('con nota');

      const porId = await prisma.runInTenantContext({ organizationId: orgAId }, (tx) =>
        repositorio.porId(tx, creada.id, orgAId),
      );
      expect(porId?.name).toBe('Parcela del repositorio');

      const listado = await prisma.runInTenantContext({ organizationId: orgAId }, (tx) =>
        repositorio.porInstalacion(tx, fincaAId),
      );
      expect(listado.map((p) => p.name)).toContain('Parcela del repositorio');
      expect(listado.every((p) => p.geometry.type === 'MultiPolygon')).toBe(true);
    });

    it('redibujar el contorno recalcula área y caja y sube la versión', async () => {
      const creada = await prisma.runInTenantContext({ organizationId: orgAId }, (tx) =>
        repositorio.crear(tx, {
          organizationId: orgAId,
          installationId: fincaAId,
          name: 'Parcela a redibujar',
          geometry: geometria.normalizar(poligono),
        }),
      );

      // El doble de ancho: el área tiene que subir de verdad, no quedarse igual.
      const masAncho = {
        type: 'Polygon',
        coordinates: [
          [
            [-0.5, 39.5],
            [-0.498, 39.5],
            [-0.498, 39.501],
            [-0.5, 39.501],
            [-0.5, 39.5],
          ],
        ],
      };
      const actualizada = await prisma.runInTenantContext({ organizationId: orgAId }, (tx) =>
        repositorio.actualizarGeometria(tx, creada.id, geometria.normalizar(masAncho)),
      );

      expect(actualizada.geometryVersion).toBe(2);
      expect(actualizada.areaM2).toBeGreaterThan(creada.areaM2 * 1.8);
      expect(actualizada.bbox[2]).toBeCloseTo(-0.498, 6);
    });

    it('rechaza un recinto que se cruza a sí mismo, con el motivo de PostGIS', async () => {
      // Un "lazo": los lados se cruzan. ST_IsValid lo detecta; sin esa
      // comprobación entraría en la tabla y reventaría al pedirle el área o
      // al mandarlo a Copernicus.
      const lazo = {
        type: 'Polygon',
        coordinates: [
          [
            [-0.5, 39.5],
            [-0.499, 39.501],
            [-0.499, 39.5],
            [-0.5, 39.501],
            [-0.5, 39.5],
          ],
        ],
      };

      await expect(
        prisma.runInTenantContext({ organizationId: orgAId }, (tx) =>
          repositorio.crear(tx, {
            organizationId: orgAId,
            installationId: fincaAId,
            name: 'Parcela imposible',
            geometry: geometria.normalizar(lazo),
          }),
        ),
      ).rejects.toThrow(/no es un recinto válido/);
    });
  });
});
