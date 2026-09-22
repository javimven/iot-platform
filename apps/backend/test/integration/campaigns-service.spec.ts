import { BadRequestException, ConflictException, NotFoundException } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { AuditLogService } from '../../src/common/audit/audit-log.service';
import { AccessTokenClaims } from '../../src/common/guards/jwt-auth.guard';
import { PrismaService } from '../../src/common/prisma/prisma.service';
import { CampaignAccess } from '../../src/modules/campaigns/campaign-access';
import { CampaignsService } from '../../src/modules/campaigns/campaigns.service';
import { CropUnitsService } from '../../src/modules/campaigns/crop-units.service';

/**
 * Los servicios de campañas contra un Postgres real (BACKLOG.md #60, fase 2).
 * Las pruebas unitarias simulan Prisma, y eso ya escondió un fallo en el
 * satélite (una consulta que no traía los archivos). Aquí se ejecutan de
 * verdad las consultas anidadas, los cálculos de superficie, la instantánea
 * de cierre y los triggers.
 */
describe('Campañas: servicios (Postgres real)', () => {
  let prisma: PrismaService;
  let campanas: CampaignsService;
  let unidades: CropUnitsService;
  let orgId: string;
  let fincaId: string;
  let otraFincaId: string;
  let norte: string;
  let sur: string;
  let lejos: string;
  let superficieNorte: number;
  let admin: AccessTokenClaims;

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

  async function crearParcela(installationId: string, name: string) {
    const filas = await prisma.runInTenantContext(
      { organizationId: orgId },
      (tx) =>
        tx.$queryRaw<Array<{ id: string; area_m2: number }>>`
        INSERT INTO parcels (organization_id, installation_id, name, geometry, area_m2,
                             bbox_min_lon, bbox_min_lat, bbox_max_lon, bbox_max_lat)
        SELECT ${orgId}::uuid, ${installationId}::uuid, ${name},
               g, ST_Area(g::geography),
               ST_XMin(g::box3d), ST_YMin(g::box3d), ST_XMax(g::box3d), ST_YMax(g::box3d)
        FROM (SELECT ST_Multi(ST_SetSRID(ST_GeomFromGeoJSON(${poligono}), 4326)) AS g) t
        RETURNING id, area_m2
      `,
    );
    return filas[0];
  }

  function altaSencilla(parcelas: Array<{ parcelId: string; areaHa?: number }>) {
    return campanas.create(admin, fincaId, {
      managementMode: 'simple',
      startDate: '2026-02-03',
      cropUnits: [{ cropId: 'aguacate', variety: 'Hass', parcels: parcelas }],
    });
  }

  async function auditoria(action: string, targetId: string) {
    return prisma.runInTenantContext({ organizationId: orgId }, (tx) =>
      tx.auditLogEntry.findFirst({ where: { action, targetId } }),
    );
  }

  beforeAll(async () => {
    if (!process.env.DATABASE_URL) {
      throw new Error('DATABASE_URL no está definida — esta prueba necesita un Postgres real.');
    }
    prisma = new PrismaService();
    await prisma.onModuleInit();
    const acceso = new CampaignAccess(prisma);
    const auditLog = new AuditLogService();
    campanas = new CampaignsService(prisma, auditLog, acceso);
    unidades = new CropUnitsService(prisma, auditLog, acceso);

    // El catálogo lo siembra `seed.ts`, que el CI no ejecuta antes de estas
    // pruebas: si falta el aguacate, se da de alta aquí.
    if (!(await prisma.crop.findUnique({ where: { id: 'aguacate' } }))) {
      await prisma.crop.create({ data: { id: 'aguacate', name: 'Aguacate', category: 'woody' } });
    }

    orgId = (
      await prisma.organization.create({
        data: {
          slug: `campanas-svc-${randomUUID().slice(0, 8)}`,
          name: 'Explotación de prueba',
          contactEmail: 'svc@example.com',
        },
      })
    ).id;
    admin = { sub: randomUUID(), type: 'access', organizationId: orgId, roleCode: 'org_admin' };

    const finca = (name: string) =>
      prisma.runInTenantContext({ organizationId: orgId }, (tx) =>
        tx.installation.create({
          data: { organizationId: orgId, name, holderName: 'Ana Pérez', regionCode: 'ES-AN' },
        }),
      );
    fincaId = (await finca('Finca Norte')).id;
    otraFincaId = (await finca('Finca Lejana')).id;

    const parcelaNorte = await crearParcela(fincaId, 'Norte');
    norte = parcelaNorte.id;
    superficieNorte = parcelaNorte.area_m2 / 10000;
    sur = (await crearParcela(fincaId, 'Sur')).id;
    lejos = (await crearParcela(otraFincaId, 'Lejos')).id;
  });

  afterAll(async () => {
    await prisma.runInTenantContext({ isPlatformAdmin: true }, async (tx) => {
      const org = { organizationId: orgId };
      await tx.campaign.updateMany({
        where: { ...org, status: 'closed' },
        data: { status: 'active', endDate: null, closedAt: null },
      });
      await tx.campaignActivity.deleteMany({ where: org });
      await tx.cropUnitParcel.deleteMany({ where: org });
      await tx.cropUnit.deleteMany({ where: org });
      const conInstantanea = await tx.campaignSnapshot.findMany({
        where: org,
        select: { campaignId: true },
      });
      await tx.campaign.deleteMany({
        where: { ...org, id: { notIn: conInstantanea.map((s) => s.campaignId) } },
      });
    });
    await prisma.$disconnect();
  });

  it('crea una campaña sencilla con nombre automático, superficies calculadas y auditoría', async () => {
    const campana = await altaSencilla([{ parcelId: norte }, { parcelId: sur, areaHa: 0.5 }]);

    expect(campana.name).toBe('Aguacate Hass · 2026');
    expect(campana.status).toBe('active');
    expect(campana.managementMode).toBe('simple');
    expect(campana.startDate).toBe('2026-02-03');
    expect(campana.installation.name).toBe('Finca Norte');
    expect(campana.parcelCount).toBe(2);
    // Norte entera + medio hectárea declarada de Sur.
    expect(campana.areaHa).toBeCloseTo(superficieNorte + 0.5, 3);
    expect(campana.cropUnits[0].cropName).toBe('Aguacate');
    expect(campana.cropUnits[0].parcels.map((p) => p.name)).toEqual(['Norte', 'Sur']);
    expect(await auditoria('campaigns.create', campana.id)).not.toBeNull();
  });

  it('no deja meter una parcela de otra finca', async () => {
    await expect(altaSencilla([{ parcelId: lejos }])).rejects.toThrow(BadRequestException);
  });

  it('no deja declarar más superficie que la de la parcela', async () => {
    await expect(altaSencilla([{ parcelId: norte, areaHa: 50 }])).rejects.toThrow(
      /mayor que la de la parcela/,
    );
  });

  it('un cultivo que no está en el catálogo se escribe a mano', async () => {
    const campana = await campanas.create(admin, fincaId, {
      managementMode: 'simple',
      startDate: '2026-10-01',
      expectedEndDate: '2027-06-30',
      cropUnits: [{ cropName: 'Chirivía', parcels: [{ parcelId: sur }] }],
    });

    expect(campana.name).toBe('Chirivía · 2026/27');
    expect(campana.cropUnits[0].cropId).toBeNull();
  });

  it('el listado filtra por año y por cultivo, y enseña la última actividad', async () => {
    const campana = await altaSencilla([{ parcelId: norte }]);
    const unidad = campana.cropUnits[0].id;
    await prisma.runInTenantContext({ organizationId: orgId }, (tx) =>
      tx.campaignActivity.create({
        data: {
          organizationId: orgId,
          campaignId: campana.id,
          type: 'irrigation',
          startDate: new Date('2026-09-18'),
          endDate: new Date('2026-09-18'),
          createdBy: admin.sub,
          targets: { create: [{ cropUnitId: unidad, parcelId: norte, organizationId: orgId }] },
        },
      }),
    );

    const de2026 = await campanas.list(admin, { year: 2026, cropId: 'aguacate' });
    const de2025 = await campanas.list(admin, { year: 2025 });

    const enLista = de2026.find((c) => c.id === campana.id);
    expect(enLista?.lastActivity).toEqual({ type: 'irrigation', date: '2026-09-18' });
    expect(enLista?.crops).toEqual(['Aguacate Hass']);
    expect(de2025.find((c) => c.id === campana.id)).toBeUndefined();
  });

  describe('unidades de cultivo', () => {
    it('se añaden, cambian de parcelas y se quitan', async () => {
      const campana = await altaSencilla([{ parcelId: norte }]);

      const conDos = await unidades.add(admin, campana.id, {
        cropName: 'Tomate',
        parcels: [{ parcelId: sur }],
      });
      expect(conDos.cropUnits.map((u) => u.cropName)).toEqual(['Aguacate', 'Tomate']);

      const tomate = conDos.cropUnits[1].id;
      const cambiada = await unidades.update(admin, campana.id, tomate, {
        parcels: [{ parcelId: sur, areaHa: 0.2 }, { parcelId: norte }],
      });
      expect(cambiada.cropUnits[1].parcels.map((p) => p.name)).toEqual(['Sur', 'Norte']);
      expect(cambiada.cropUnits[1].parcels[0].areaHa).toBe(0.2);

      await unidades.remove(admin, campana.id, tomate);
      const final = await campanas.findOne(admin, campana.id);
      expect(final.cropUnits).toHaveLength(1);
    });

    it('no se quita la última unidad de una campaña', async () => {
      const campana = await altaSencilla([{ parcelId: norte }]);

      await expect(unidades.remove(admin, campana.id, campana.cropUnits[0].id)).rejects.toThrow(
        /al menos una unidad/,
      );
    });

    it('no se quita de la unidad una parcela con actividades, y lo dice por su nombre', async () => {
      const campana = await altaSencilla([{ parcelId: norte }, { parcelId: sur }]);
      const unidad = campana.cropUnits[0].id;
      await prisma.runInTenantContext({ organizationId: orgId }, (tx) =>
        tx.campaignActivity.create({
          data: {
            organizationId: orgId,
            campaignId: campana.id,
            type: 'harvest',
            startDate: new Date('2026-09-12'),
            endDate: new Date('2026-09-12'),
            createdBy: admin.sub,
            targets: { create: [{ cropUnitId: unidad, parcelId: norte, organizationId: orgId }] },
          },
        }),
      );

      await expect(
        unidades.update(admin, campana.id, unidad, { parcels: [{ parcelId: sur }] }),
      ).rejects.toThrow(/"Norte" tiene actividades registradas/);
    });
  });

  describe('modo, cierre y reapertura', () => {
    it('pasa de sencilla a completa sin copiar nada, y solo una vez', async () => {
      const campana = await altaSencilla([{ parcelId: norte }]);

      const completa = await campanas.upgrade(admin, campana.id, {
        notebookProfile: { usesPlantProtectionProducts: true, appliesFertilizers: false },
      });

      expect(completa.id).toBe(campana.id);
      expect(completa.managementMode).toBe('complete');
      expect(completa.notebookProfile).toEqual({
        version: 1,
        usesPlantProtectionProducts: true,
        appliesFertilizers: false,
      });
      await expect(campanas.upgrade(admin, campana.id, {})).rejects.toThrow(ConflictException);
    });

    it('cerrar congela la campaña y guarda una instantánea de cómo era todo', async () => {
      const campana = await altaSencilla([{ parcelId: norte }]);

      const cerrada = await campanas.close(admin, campana.id, {
        endDate: '2026-10-30',
        declaredProductionKg: 12500,
        closingNotes: 'Buena campaña',
      });

      expect(cerrada.status).toBe('closed');
      expect(cerrada.endDate).toBe('2026-10-30');
      const instantanea = await prisma.runInTenantContext({ organizationId: orgId }, (tx) =>
        tx.campaignSnapshot.findFirst({ where: { campaignId: campana.id } }),
      );
      const contenido = instantanea?.content as {
        organization: { name: string };
        installation: { name: string; holderName: string; regionCode: string };
        cropUnits: Array<{ cropName: string; parcels: Array<{ name: string }> }>;
        campaign: { endDate: string };
      };
      expect(contenido.organization.name).toBe('Explotación de prueba');
      expect(contenido.installation).toMatchObject({
        name: 'Finca Norte',
        holderName: 'Ana Pérez',
        regionCode: 'ES-AN',
      });
      expect(contenido.cropUnits[0].parcels[0].name).toBe('Norte');
      expect(contenido.campaign.endDate).toBe('2026-10-30');
      expect(await auditoria('campaigns.close', campana.id)).not.toBeNull();

      await expect(campanas.update(admin, campana.id, { notes: 'tarde' })).rejects.toThrow(
        /reábrela/,
      );
      await expect(campanas.softDelete(admin, campana.id)).rejects.toThrow(/no se borra/);
      await expect(campanas.close(admin, campana.id, { endDate: '2026-11-01' })).rejects.toThrow(
        /ya está cerrada/,
      );
    });

    it('reabrir exige motivo, queda auditado y deja volver a editar', async () => {
      const campana = await altaSencilla([{ parcelId: norte }]);
      await campanas.close(admin, campana.id, { endDate: '2026-10-30' });

      const reabierta = await campanas.reopen(admin, campana.id, {
        reason: 'Falta un tratamiento de octubre',
      });

      expect(reabierta.status).toBe('active');
      const entrada = await auditoria('campaigns.reopen', campana.id);
      expect(entrada?.metadata).toMatchObject({ reason: 'Falta un tratamiento de octubre' });
      await expect(
        campanas.update(admin, campana.id, { notes: 'corregida' }),
      ).resolves.toMatchObject({ notes: 'corregida' });
    });

    it('el fin no puede ser anterior al inicio', async () => {
      const campana = await altaSencilla([{ parcelId: norte }]);
      await expect(campanas.close(admin, campana.id, { endDate: '2026-01-01' })).rejects.toThrow(
        BadRequestException,
      );
    });
  });

  it('una campaña borrada desaparece del listado y de su ficha', async () => {
    const campana = await altaSencilla([{ parcelId: norte }]);

    await campanas.softDelete(admin, campana.id);

    await expect(campanas.findOne(admin, campana.id)).rejects.toThrow(NotFoundException);
    const lista = await campanas.list(admin, {});
    expect(lista.find((c) => c.id === campana.id)).toBeUndefined();
  });
});
