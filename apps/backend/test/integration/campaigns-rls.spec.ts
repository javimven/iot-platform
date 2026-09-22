import { randomUUID } from 'node:crypto';
import { PrismaService } from '../../src/common/prisma/prisma.service';

/**
 * Campañas y cuaderno de campo contra un Postgres real (migraciones 0010-0012,
 * BACKLOG.md #60). Lo que ninguna prueba unitaria puede cubrir porque mockea
 * `PrismaService`:
 *
 * 1. El aislamiento por organización (RLS) de campañas, actividades y
 *    documentos: una organización no ve nada de otra, ni pidiéndolo por id.
 * 2. Los triggers de coherencia: una unidad de cultivo solo ocupa parcelas de
 *    la finca de su campaña, una actividad solo apunta a parcelas de su
 *    campaña, un documento solo se vincula a cosas de su organización.
 * 3. Que la historia de una campaña cerrada no se toca: ni altas, ni cambios,
 *    ni detalles nuevos, hasta reabrirla.
 * 4. Que las instantáneas de cierre son inmutables y que un mismo fichero no
 *    se guarda dos veces.
 *
 * Se conecta como `iot_platform_app` (en el CI y en local), que no es dueño de
 * las tablas: con el dueño, la RLS no se aplicaría y estas pruebas no
 * demostrarían nada.
 */
describe('Campañas: RLS, integridad e inmutabilidad (Postgres real)', () => {
  let prisma: PrismaService;
  let orgA: string;
  let orgB: string;
  let fincaA: string;
  let otraFincaA: string;
  let fincaB: string;
  let parcelaA: string;
  let parcelaOtraFincaA: string;
  let parcelaB: string;
  let campanaA: string;
  let unidadA: string;
  const usuario = randomUUID();

  const poligono = JSON.stringify({
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
  });

  async function crearParcela(organizationId: string, installationId: string, name: string) {
    const filas = await prisma.runInTenantContext(
      { organizationId },
      (tx) =>
        tx.$queryRaw<Array<{ id: string }>>`
        INSERT INTO parcels (organization_id, installation_id, name, geometry, area_m2,
                             bbox_min_lon, bbox_min_lat, bbox_max_lon, bbox_max_lat)
        SELECT ${organizationId}::uuid, ${installationId}::uuid, ${name},
               g, ST_Area(g::geography),
               ST_XMin(g::box3d), ST_YMin(g::box3d), ST_XMax(g::box3d), ST_YMax(g::box3d)
        FROM (SELECT ST_Multi(ST_SetSRID(ST_GeomFromGeoJSON(${poligono}), 4326)) AS g) t
        RETURNING id
      `,
    );
    return filas[0].id;
  }

  async function crearCampana(organizationId: string, installationId: string, nombre: string) {
    return prisma.runInTenantContext({ organizationId }, (tx) =>
      tx.campaign.create({
        data: {
          organizationId,
          installationId,
          name: nombre,
          startDate: new Date('2026-02-03'),
          createdBy: usuario,
        },
      }),
    );
  }

  async function crearRiego(campaignId: string, cropUnitId: string, parcelId: string) {
    return prisma.runInTenantContext({ organizationId: orgA }, (tx) =>
      tx.campaignActivity.create({
        data: {
          organizationId: orgA,
          campaignId,
          type: 'irrigation',
          startDate: new Date('2026-09-18'),
          endDate: new Date('2026-09-18'),
          createdBy: usuario,
          targets: { create: [{ cropUnitId, parcelId, organizationId: orgA }] },
          irrigation: {
            create: { organizationId: orgA, amount: 18, amountUnit: 'm3_ha', volumeM3: 15.3 },
          },
        },
      }),
    );
  }

  async function cambiarEstado(campaignId: string, estado: 'active' | 'closed') {
    await prisma.runInTenantContext({ organizationId: orgA }, (tx) =>
      tx.campaign.update({
        where: { id: campaignId },
        data:
          estado === 'closed'
            ? { status: 'closed', endDate: new Date('2026-10-01'), closedAt: new Date() }
            : { status: 'active', endDate: null, closedAt: null },
      }),
    );
  }

  beforeAll(async () => {
    if (!process.env.DATABASE_URL) {
      throw new Error(
        'DATABASE_URL no está definida — esta prueba necesita un Postgres real con PostGIS (TESTING_STRATEGY.md §4).',
      );
    }
    prisma = new PrismaService();
    await prisma.onModuleInit();

    const sufijo = randomUUID().slice(0, 8);
    orgA = (
      await prisma.organization.create({
        data: { slug: `campanas-a-${sufijo}`, name: 'Campañas A', contactEmail: 'a@example.com' },
      })
    ).id;
    orgB = (
      await prisma.organization.create({
        data: { slug: `campanas-b-${sufijo}`, name: 'Campañas B', contactEmail: 'b@example.com' },
      })
    ).id;

    const finca = (organizationId: string, name: string) =>
      prisma.runInTenantContext({ organizationId }, (tx) =>
        tx.installation.create({ data: { organizationId, name } }),
      );
    fincaA = (await finca(orgA, 'Finca A')).id;
    otraFincaA = (await finca(orgA, 'Otra finca de A')).id;
    fincaB = (await finca(orgB, 'Finca B')).id;

    parcelaA = await crearParcela(orgA, fincaA, 'Norte');
    parcelaOtraFincaA = await crearParcela(orgA, otraFincaA, 'Lejos');
    parcelaB = await crearParcela(orgB, fincaB, 'De B');

    campanaA = (await crearCampana(orgA, fincaA, 'Aguacate Hass · 2026')).id;
    unidadA = (
      await prisma.runInTenantContext({ organizationId: orgA }, (tx) =>
        tx.cropUnit.create({
          data: {
            organizationId: orgA,
            campaignId: campanaA,
            cropName: 'Aguacate',
            variety: 'Hass',
            parcels: { create: [{ parcelId: parcelaA, organizationId: orgA }] },
          },
        }),
      )
    ).id;
  });

  afterAll(async () => {
    // Lo que se puede limpiar, se limpia. Las campañas con instantánea de
    // cierre se quedan (y con ellas su organización): las instantáneas son
    // inmutables por diseño, también para las pruebas. Solo el dueño de la
    // base, desactivando el trigger, podría purgarlas.
    await prisma.runInTenantContext({ isPlatformAdmin: true }, async (tx) => {
      const orgs = { organizationId: { in: [orgA, orgB] } };
      await tx.campaign.updateMany({
        where: { ...orgs, status: 'closed' },
        data: { status: 'active', endDate: null, closedAt: null },
      });
      await tx.documentLink.deleteMany({ where: orgs });
      await tx.document.deleteMany({ where: orgs });
      await tx.campaignActivity.deleteMany({ where: orgs });
      await tx.cropUnitParcel.deleteMany({ where: orgs });
      await tx.cropUnit.deleteMany({ where: orgs });
      const conInstantanea = await tx.campaignSnapshot.findMany({
        where: orgs,
        select: { campaignId: true },
      });
      await tx.campaign.deleteMany({
        where: { ...orgs, id: { notIn: conInstantanea.map((s) => s.campaignId) } },
      });
    });
    await prisma.$disconnect();
  });

  describe('aislamiento entre organizaciones', () => {
    it('B no ve las campañas, unidades ni parcelas de campaña de A', async () => {
      const vistoPorB = await prisma.runInTenantContext({ organizationId: orgB }, async (tx) => ({
        campanas: await tx.campaign.findMany(),
        unidades: await tx.cropUnit.findMany(),
        relaciones: await tx.cropUnitParcel.findMany(),
        porId: await tx.campaign.findFirst({ where: { id: campanaA } }),
      }));

      expect(vistoPorB.campanas).toEqual([]);
      expect(vistoPorB.unidades).toEqual([]);
      expect(vistoPorB.relaciones).toEqual([]);
      expect(vistoPorB.porId).toBeNull();
    });

    it('B no ve las actividades de A ni ninguno de sus detalles', async () => {
      const riego = await crearRiego(campanaA, unidadA, parcelaA);

      const vistoPorB = await prisma.runInTenantContext({ organizationId: orgB }, async (tx) => ({
        actividad: await tx.campaignActivity.findFirst({ where: { id: riego.id } }),
        destinos: await tx.activityTarget.findMany({ where: { activityId: riego.id } }),
        riego: await tx.irrigationDetail.findFirst({ where: { activityId: riego.id } }),
      }));
      const vistoPorA = await prisma.runInTenantContext({ organizationId: orgA }, (tx) =>
        tx.irrigationDetail.findFirst({ where: { activityId: riego.id } }),
      );

      expect(vistoPorB).toEqual({ actividad: null, destinos: [], riego: null });
      expect(vistoPorA?.volumeM3).toBe(15.3);
    });

    it('B no ve los documentos de A', async () => {
      const documento = await prisma.runInTenantContext({ organizationId: orgA }, (tx) =>
        tx.document.create({
          data: {
            organizationId: orgA,
            documentType: 'invoice',
            filename: 'factura.pdf',
            mediaType: 'application/pdf',
            byteSize: 1024,
            checksum: 'a'.repeat(64),
            objectKey: `documents/${orgA}/${randomUUID()}/factura.pdf`,
            uploadedBy: usuario,
          },
        }),
      );

      const vistoPorB = await prisma.runInTenantContext({ organizationId: orgB }, (tx) =>
        tx.document.findFirst({ where: { id: documento.id } }),
      );
      expect(vistoPorB).toBeNull();
    });

    it('el catálogo de cultivos lo lee cualquiera: es de plataforma, no de una organización', async () => {
      await expect(
        prisma.runInTenantContext({ organizationId: orgB }, (tx) => tx.crop.findMany()),
      ).resolves.toBeDefined();
    });
  });

  describe('coherencia entre finca, campaña y parcelas', () => {
    it('una unidad de cultivo no puede ocupar una parcela de otra finca', async () => {
      await expect(
        prisma.runInTenantContext({ organizationId: orgA }, (tx) =>
          tx.cropUnitParcel.create({
            data: { cropUnitId: unidadA, parcelId: parcelaOtraFincaA, organizationId: orgA },
          }),
        ),
      ).rejects.toThrow(/must belong to the campaign installation/);
    });

    it('ni una parcela de otra organización, aunque se sepa su id', async () => {
      // Como Admin de plataforma, que ve las dos: así no es la RLS la que lo
      // para, sino el trigger (las claves foráneas no pasan por RLS).
      await expect(
        prisma.runInTenantContext({ isPlatformAdmin: true }, (tx) =>
          tx.cropUnitParcel.create({
            data: { cropUnitId: unidadA, parcelId: parcelaB, organizationId: orgA },
          }),
        ),
      ).rejects.toThrow(/same organization/);
    });

    it('una campaña no puede ser de una finca de otra organización', async () => {
      await expect(
        prisma.runInTenantContext({ isPlatformAdmin: true }, (tx) =>
          tx.campaign.create({
            data: {
              organizationId: orgA,
              installationId: fincaB,
              name: 'Colada',
              startDate: new Date('2026-01-01'),
              createdBy: usuario,
            },
          }),
        ),
      ).rejects.toThrow(/does not belong to organization/);
    });

    it('una actividad solo apunta a parcelas que están en la unidad de cultivo', async () => {
      await expect(crearRiego(campanaA, unidadA, parcelaOtraFincaA)).rejects.toThrow(
        /foreign key/i,
      );
    });

    it('ni a la unidad de cultivo de otra campaña, aunque la parcela sea la misma', async () => {
      // La misma parcela puede estar en dos campañas (dos cultivos seguidos
      // en el año, o asociados); lo que no vale es cruzarlas.
      const otraCampana = await crearCampana(orgA, fincaA, 'Otra campaña');
      const otraUnidad = await prisma.runInTenantContext({ organizationId: orgA }, (tx) =>
        tx.cropUnit.create({
          data: {
            organizationId: orgA,
            campaignId: otraCampana.id,
            cropName: 'Tomate',
            parcels: { create: [{ parcelId: parcelaA, organizationId: orgA }] },
          },
        }),
      );

      await expect(crearRiego(campanaA, otraUnidad.id, parcelaA)).rejects.toThrow(
        /is not part of the campaign/,
      );
    });

    it('una parcela con actividades no se puede quitar de la unidad sin más', async () => {
      await crearRiego(campanaA, unidadA, parcelaA);

      await expect(
        prisma.runInTenantContext({ organizationId: orgA }, (tx) =>
          tx.cropUnitParcel.delete({
            where: { cropUnitId_parcelId: { cropUnitId: unidadA, parcelId: parcelaA } },
          }),
        ),
      ).rejects.toThrow();
    });
  });

  describe('reglas de las actividades', () => {
    it('el fin no puede ser anterior al inicio', async () => {
      await expect(
        prisma.runInTenantContext({ organizationId: orgA }, (tx) =>
          tx.campaignActivity.create({
            data: {
              organizationId: orgA,
              campaignId: campanaA,
              type: 'field_work',
              startDate: new Date('2026-09-18'),
              endDate: new Date('2026-09-10'),
              createdBy: usuario,
            },
          }),
        ),
      ).rejects.toThrow(/campaign_activities_fechas/);
    });

    it('una actividad "repetida" tiene que decir de cuál viene', async () => {
      await expect(
        prisma.runInTenantContext({ organizationId: orgA }, (tx) =>
          tx.campaignActivity.create({
            data: {
              organizationId: orgA,
              campaignId: campanaA,
              type: 'irrigation',
              startDate: new Date('2026-09-18'),
              endDate: new Date('2026-09-18'),
              origin: 'repeated',
              createdBy: usuario,
            },
          }),
        ),
      ).rejects.toThrow(/campaign_activities_repetida/);
    });

    it('una hora que no es una hora no entra', async () => {
      await expect(
        prisma.runInTenantContext({ organizationId: orgA }, (tx) =>
          tx.campaignActivity.create({
            data: {
              organizationId: orgA,
              campaignId: campanaA,
              type: 'phytosanitary',
              startDate: new Date('2026-09-18'),
              endDate: new Date('2026-09-18'),
              startTime: '25:00',
              createdBy: usuario,
            },
          }),
        ),
      ).rejects.toThrow(/campaign_activities_hora/);
    });
  });

  describe('una campaña cerrada no se toca', () => {
    let campanaCerrada: string;
    let unidadCerrada: string;
    let riegoCerrado: string;

    beforeAll(async () => {
      campanaCerrada = (await crearCampana(orgA, fincaA, 'Olivo 2025/26')).id;
      unidadCerrada = (
        await prisma.runInTenantContext({ organizationId: orgA }, (tx) =>
          tx.cropUnit.create({
            data: {
              organizationId: orgA,
              campaignId: campanaCerrada,
              cropName: 'Olivo',
              parcels: { create: [{ parcelId: parcelaA, organizationId: orgA }] },
            },
          }),
        )
      ).id;
      riegoCerrado = (await crearRiego(campanaCerrada, unidadCerrada, parcelaA)).id;
      await cambiarEstado(campanaCerrada, 'closed');
    });

    it('no admite actividades nuevas', async () => {
      await expect(crearRiego(campanaCerrada, unidadCerrada, parcelaA)).rejects.toThrow(
        /cannot be modified without reopening/,
      );
    });

    it('no deja cambiar ni borrar (tampoco con borrado lógico) lo registrado', async () => {
      await expect(
        prisma.runInTenantContext({ organizationId: orgA }, (tx) =>
          tx.campaignActivity.update({
            where: { id: riegoCerrado },
            data: { notes: 'retocado después de cerrar' },
          }),
        ),
      ).rejects.toThrow(/cannot be modified without reopening/);

      await expect(
        prisma.runInTenantContext({ organizationId: orgA }, (tx) =>
          tx.campaignActivity.update({
            where: { id: riegoCerrado },
            data: { deletedAt: new Date() },
          }),
        ),
      ).rejects.toThrow(/cannot be modified without reopening/);
    });

    it('tampoco los detalles, aunque se toquen sin pasar por la actividad', async () => {
      await expect(
        prisma.runInTenantContext({ organizationId: orgA }, (tx) =>
          tx.irrigationDetail.update({
            where: { activityId: riegoCerrado },
            data: { volumeM3: 999 },
          }),
        ),
      ).rejects.toThrow(/cannot be modified without reopening/);
    });

    it('al reabrirla vuelve a admitir cambios', async () => {
      await cambiarEstado(campanaCerrada, 'active');

      await expect(
        prisma.runInTenantContext({ organizationId: orgA }, (tx) =>
          tx.campaignActivity.update({
            where: { id: riegoCerrado },
            data: { notes: 'corrección tras reabrir' },
          }),
        ),
      ).resolves.toBeDefined();

      await cambiarEstado(campanaCerrada, 'closed');
    });

    it('cerrada tiene que tener fecha de fin', async () => {
      await expect(
        prisma.runInTenantContext({ organizationId: orgA }, (tx) =>
          tx.campaign.update({
            where: { id: campanaA },
            data: { status: 'closed', closedAt: new Date() },
          }),
        ),
      ).rejects.toThrow(/campaigns_cerrada_completa/);
    });

    it('la instantánea de cierre no se modifica ni se borra', async () => {
      const instantanea = await prisma.runInTenantContext({ organizationId: orgA }, (tx) =>
        tx.campaignSnapshot.create({
          data: {
            organizationId: orgA,
            campaignId: campanaCerrada,
            reason: 'close',
            content: { titular: 'Finca A', parcelas: [{ nombre: 'Norte', ha: 1.1 }] },
            createdBy: usuario,
          },
        }),
      );

      await expect(
        prisma.runInTenantContext({ organizationId: orgA }, (tx) =>
          tx.campaignSnapshot.update({
            where: { id: instantanea.id },
            data: { content: { titular: 'Otro' } },
          }),
        ),
      ).rejects.toThrow(/immutable/);
      await expect(
        prisma.runInTenantContext({ organizationId: orgA }, (tx) =>
          tx.campaignSnapshot.delete({ where: { id: instantanea.id } }),
        ),
      ).rejects.toThrow(/immutable/);
    });
  });

  describe('documentos', () => {
    const documento = (organizationId: string, checksum: string) => ({
      organizationId,
      documentType: 'analysis',
      filename: 'analitica.pdf',
      mediaType: 'application/pdf',
      byteSize: 2048,
      checksum,
      objectKey: `documents/${organizationId}/${randomUUID()}/analitica.pdf`,
      uploadedBy: usuario,
    });

    it('el mismo fichero no se guarda dos veces en la misma organización', async () => {
      const checksum = 'b'.repeat(64);
      await prisma.runInTenantContext({ organizationId: orgA }, (tx) =>
        tx.document.create({ data: documento(orgA, checksum) }),
      );

      await expect(
        prisma.runInTenantContext({ organizationId: orgA }, (tx) =>
          tx.document.create({ data: documento(orgA, checksum) }),
        ),
      ).rejects.toThrow(/Unique constraint/);
    });

    it('un vínculo apunta exactamente a una cosa', async () => {
      const doc = await prisma.runInTenantContext({ organizationId: orgA }, (tx) =>
        tx.document.create({ data: documento(orgA, 'c'.repeat(64)) }),
      );
      const riego = await crearRiego(campanaA, unidadA, parcelaA);

      await expect(
        prisma.runInTenantContext({ organizationId: orgA }, (tx) =>
          tx.documentLink.create({
            data: {
              organizationId: orgA,
              documentId: doc.id,
              campaignId: campanaA,
              activityId: riego.id,
              createdBy: usuario,
            },
          }),
        ),
      ).rejects.toThrow(/document_links_un_destino/);
    });

    it('no se puede vincular un documento a una campaña de otra organización', async () => {
      const doc = await prisma.runInTenantContext({ organizationId: orgA }, (tx) =>
        tx.document.create({ data: documento(orgA, 'd'.repeat(64)) }),
      );
      const campanaB = await crearCampana(orgB, fincaB, 'De B');

      await expect(
        prisma.runInTenantContext({ isPlatformAdmin: true }, (tx) =>
          tx.documentLink.create({
            data: {
              organizationId: orgA,
              documentId: doc.id,
              campaignId: campanaB.id,
              createdBy: usuario,
            },
          }),
        ),
      ).rejects.toThrow(/same organization/);
    });
  });
});
