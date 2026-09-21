import { randomUUID } from 'node:crypto';
import { PrismaService } from '../../src/common/prisma/prisma.service';
import { ParcelGeometryService } from '../../src/modules/parcels/parcel-geometry.service';
import { ParcelsRepository } from '../../src/modules/parcels/parcels.repository';

/**
 * Aislamiento multi-tenant de las tablas de satélite (migración 0009) contra
 * un Postgres real. Las pruebas unitarias mockean `PrismaService`, así que no
 * ejercitan ni una política de RLS: si una de estas tres tablas se quedara sin
 * política, nadie se enteraría hasta que un cliente viera el NDVI de otro.
 *
 * También comprueba la idempotencia de verdad —el índice único de la clave
 * lógica— en vez de confiar en que la aplicación no lo intente dos veces.
 */
describe('Satélite: RLS e idempotencia (Postgres real)', () => {
  let prisma: PrismaService;
  const repositorio = new ParcelsRepository();
  const geometria = new ParcelGeometryService();

  let orgAId: string;
  let orgBId: string;
  let parcelaAId: string;
  let observacionAId: string;

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

  const claveLogica = {
    provider: 'copernicus',
    collection: 'sentinel-2-l2a',
    acquisitionDate: new Date('2026-09-15'),
    processingVersion: 'ndvi-s2-v1',
  };

  async function crearObservacion(organizationId: string, parcelId: string, extra = {}) {
    return prisma.runInTenantContext({ organizationId }, (tx) =>
      tx.satelliteObservation.create({
        data: {
          organizationId,
          parcelId,
          ...claveLogica,
          acquisitionTime: new Date('2026-09-15T10:42:19Z'),
          sourceItemIds: ['S2B_T30SYJ_20260915', 'S2B_T30SYH_20260915'],
          platform: 'sentinel-2b',
          parcelGeometryVersion: 1,
          status: 'ready',
          qualityStatus: 'good',
          validPixelFraction: 0.92,
          ...extra,
        },
      }),
    );
  }

  beforeAll(async () => {
    if (!process.env.DATABASE_URL) {
      throw new Error('DATABASE_URL no está definida — esta prueba necesita un Postgres real.');
    }
    prisma = new PrismaService();
    await prisma.onModuleInit();

    const orgA = await prisma.organization.create({
      data: {
        slug: `sat-a-${randomUUID().slice(0, 8)}`,
        name: 'Satélite Org A',
        contactEmail: 'sat-a@example.com',
      },
    });
    const orgB = await prisma.organization.create({
      data: {
        slug: `sat-b-${randomUUID().slice(0, 8)}`,
        name: 'Satélite Org B',
        contactEmail: 'sat-b@example.com',
      },
    });
    orgAId = orgA.id;
    orgBId = orgB.id;

    const finca = await prisma.runInTenantContext({ organizationId: orgAId }, (tx) =>
      tx.installation.create({ data: { organizationId: orgAId, name: 'Finca A' } }),
    );
    const parcela = await prisma.runInTenantContext({ organizationId: orgAId }, (tx) =>
      repositorio.crear(tx, {
        organizationId: orgAId,
        installationId: finca.id,
        name: 'Parcela de A',
        geometry: geometria.normalizar(poligono),
      }),
    );
    parcelaAId = parcela.id;

    const observacion = await crearObservacion(orgAId, parcelaAId);
    observacionAId = observacion.id;

    await prisma.runInTenantContext({ organizationId: orgAId }, async (tx) => {
      await tx.satelliteMetric.create({
        data: {
          organizationId: orgAId,
          observationId: observacionAId,
          metricCode: 'ndvi',
          mean: 0.63,
          median: 0.66,
          min: 0.12,
          max: 0.84,
          stdDev: 0.09,
          p10: 0.4,
          p90: 0.8,
          sampleCount: 1000,
          noDataCount: 80,
        },
      });
      await tx.satelliteAsset.create({
        data: {
          organizationId: orgAId,
          observationId: observacionAId,
          assetType: 'ndvi_raster',
          objectKey: 'satellite/org-a/parcela/ndvi.tif',
          mediaType: 'image/tiff',
          width: 10,
          height: 12,
          bboxMinLon: -0.5,
          bboxMinLat: 39.5,
          bboxMaxLon: -0.499,
          bboxMaxLat: 39.501,
          crs: 'EPSG:4326',
          byteSize: 2048,
          checksum: 'abc',
        },
      });
    });
  });

  afterAll(async () => {
    await prisma.runInTenantContext({ isPlatformAdmin: true }, async (tx) => {
      // Métricas y assets caen con la observación (ON DELETE CASCADE).
      await tx.satelliteObservation.deleteMany({
        where: { organizationId: { in: [orgAId, orgBId] } },
      });
      await tx.parcel.deleteMany({ where: { organizationId: { in: [orgAId, orgBId] } } });
      await tx.installation.deleteMany({ where: { organizationId: { in: [orgAId, orgBId] } } });
    });
    await prisma.organization.deleteMany({ where: { id: { in: [orgAId, orgBId] } } });
    await prisma.$disconnect();
  });

  it('una organización no ve las observaciones de otra', async () => {
    const deA = await prisma.runInTenantContext({ organizationId: orgAId }, (tx) =>
      tx.satelliteObservation.findMany(),
    );
    const deB = await prisma.runInTenantContext({ organizationId: orgBId }, (tx) =>
      tx.satelliteObservation.findMany(),
    );

    expect(deA).toHaveLength(1);
    expect(deB).toEqual([]);
  });

  it('tampoco ve sus métricas', async () => {
    const deB = await prisma.runInTenantContext({ organizationId: orgBId }, (tx) =>
      tx.satelliteMetric.findMany(),
    );
    expect(deB).toEqual([]);
  });

  it('tampoco ve sus archivos: ahí está la clave del objeto en S3', async () => {
    const deB = await prisma.runInTenantContext({ organizationId: orgBId }, (tx) =>
      tx.satelliteAsset.findMany(),
    );
    expect(deB).toEqual([]);
  });

  it('pedir la observación ajena por su id devuelve nada, no un 500', async () => {
    const encontrada = await prisma.runInTenantContext({ organizationId: orgBId }, (tx) =>
      tx.satelliteObservation.findFirst({ where: { id: observacionAId } }),
    );
    expect(encontrada).toBeNull();
  });

  it('la misma pasada no se puede guardar dos veces: lo impide la base, no la aplicación', async () => {
    await expect(crearObservacion(orgAId, parcelaAId)).rejects.toThrow();
  });

  it('pero otra versión de procesado sí convive con la anterior', async () => {
    const reprocesada = await crearObservacion(orgAId, parcelaAId, {
      processingVersion: 'ndvi-s2-v2',
    });

    expect(reprocesada.id).not.toBe(observacionAId);
    const todas = await prisma.runInTenantContext({ organizationId: orgAId }, (tx) =>
      tx.satelliteObservation.findMany({ where: { parcelId: parcelaAId } }),
    );
    expect(todas).toHaveLength(2);
  });

  it('un índice repetido en la misma observación tampoco cabe dos veces', async () => {
    await expect(
      prisma.runInTenantContext({ organizationId: orgAId }, (tx) =>
        tx.satelliteMetric.create({
          data: {
            organizationId: orgAId,
            observationId: observacionAId,
            metricCode: 'ndvi',
            mean: 0.1,
            median: 0.1,
            min: 0,
            max: 0.2,
            stdDev: 0.01,
            p10: 0.05,
            p90: 0.15,
            sampleCount: 10,
            noDataCount: 0,
          },
        }),
      ),
    ).rejects.toThrow();
  });

  it('la base rechaza una fracción imposible', async () => {
    await expect(
      prisma.runInTenantContext({ organizationId: orgAId }, (tx) =>
        tx.satelliteObservation.update({
          where: { id: observacionAId },
          data: { validPixelFraction: 1.5 },
        }),
      ),
    ).rejects.toThrow();
  });
});
