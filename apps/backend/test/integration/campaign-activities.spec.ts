import { randomUUID } from 'node:crypto';
import { AuditLogService } from '../../src/common/audit/audit-log.service';
import { AccessTokenClaims } from '../../src/common/guards/jwt-auth.guard';
import { PrismaService } from '../../src/common/prisma/prisma.service';
import { ActivitiesService } from '../../src/modules/campaigns/activities.service';
import { CampaignAccess } from '../../src/modules/campaigns/campaign-access';
import { CampaignSummaryService } from '../../src/modules/campaigns/campaign-summary';
import { CampaignsService } from '../../src/modules/campaigns/campaigns.service';
import { CropUnitsService } from '../../src/modules/campaigns/crop-units.service';

/**
 * Actividades del cuaderno contra un Postgres real (BACKLOG.md #60, fase 3):
 * las consultas anidadas, los valores normalizados guardados, la copia del
 * aplicador, la auditoría de los cambios y el resumen con números de verdad.
 */
describe('Campañas: actividades (Postgres real)', () => {
  let prisma: PrismaService;
  let campanas: CampaignsService;
  let unidades: CropUnitsService;
  let actividades: ActivitiesService;
  let resumen: CampaignSummaryService;
  let orgId: string;
  let fincaId: string;
  let norte: string;
  let sur: string;
  let superficieNorte: number;
  let admin: AccessTokenClaims;

  // ~100 x 110 m: algo menos de una hectárea.
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

  async function crearParcela(name: string) {
    const filas = await prisma.runInTenantContext(
      { organizationId: orgId },
      (tx) =>
        tx.$queryRaw<Array<{ id: string; area_m2: number }>>`
        INSERT INTO parcels (organization_id, installation_id, name, geometry, area_m2,
                             bbox_min_lon, bbox_min_lat, bbox_max_lon, bbox_max_lat)
        SELECT ${orgId}::uuid, ${fincaId}::uuid, ${name},
               g, ST_Area(g::geography),
               ST_XMin(g::box3d), ST_YMin(g::box3d), ST_XMax(g::box3d), ST_YMax(g::box3d)
        FROM (SELECT ST_Multi(ST_SetSRID(ST_GeomFromGeoJSON(${poligono}), 4326)) AS g) t
        RETURNING id, area_m2
      `,
    );
    return filas[0];
  }

  async function nuevaCampana() {
    return campanas.create(admin, fincaId, {
      managementMode: 'simple',
      startDate: '2026-02-03',
      cropUnits: [{ cropName: 'Aguacate', variety: 'Hass', parcels: [{ parcelId: norte }] }],
    });
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
    actividades = new ActivitiesService(prisma, auditLog, acceso);
    resumen = new CampaignSummaryService(prisma, acceso);

    orgId = (
      await prisma.organization.create({
        data: {
          slug: `actividades-${randomUUID().slice(0, 8)}`,
          name: 'Actividades',
          contactEmail: 'act@example.com',
        },
      })
    ).id;
    admin = { sub: randomUUID(), type: 'access', organizationId: orgId, roleCode: 'org_admin' };
    fincaId = (
      await prisma.runInTenantContext({ organizationId: orgId }, (tx) =>
        tx.installation.create({ data: { organizationId: orgId, name: 'Finca' } }),
      )
    ).id;
    const parcelaNorte = await crearParcela('Norte');
    norte = parcelaNorte.id;
    superficieNorte = parcelaNorte.area_m2 / 10000;
    sur = (await crearParcela('Sur')).id;
  });

  afterAll(async () => {
    await prisma.runInTenantContext({ isPlatformAdmin: true }, async (tx) => {
      const org = { organizationId: orgId };
      await tx.campaign.updateMany({
        where: { ...org, status: 'closed' },
        data: { status: 'active', endDate: null, closedAt: null },
      });
      // Las dos cosas a la vez: el CHECK `campaign_activities_repetida` no deja
      // una sin la otra.
      await tx.campaignActivity.updateMany({
        where: org,
        data: { repeatedFromId: null, origin: 'manual' },
      });
      await tx.campaignActivity.deleteMany({ where: org });
      await tx.notebookPerson.deleteMany({ where: org });
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

  it('un riego en m³/ha se guarda también en m³ totales', async () => {
    const campana = await nuevaCampana();

    const riego = await actividades.create(admin, campana.id, {
      type: 'irrigation',
      startDate: '2026-09-18',
      targets: [{ parcelId: norte }],
      irrigation: { system: 'drip', amount: 18, amountUnit: 'm3_ha' },
    });

    expect(riego.endDate).toBe('2026-09-18'); // un día: fin = inicio
    expect(riego.targets[0].parcelName).toBe('Norte');
    expect(riego.targets[0].cropName).toBe('Aguacate Hass');
    expect(riego.irrigation?.volumeM3).toBeCloseTo(18 * superficieNorte, 2);
  });

  it('un tratamiento con dos productos guarda quién lo aplicó tal como era ese día', async () => {
    const campana = await nuevaCampana();
    const aplicador = await prisma.runInTenantContext({ organizationId: orgId }, (tx) =>
      tx.notebookPerson.create({
        data: {
          organizationId: orgId,
          kind: 'own_staff',
          firstName: 'Juan',
          surname1: 'Pérez',
          ropoNumber: 'ROPO-123',
        },
      }),
    );

    const tratamiento = await actividades.create(admin, campana.id, {
      type: 'phytosanitary',
      startDate: '2026-09-10',
      startTime: '07:30',
      targets: [{ parcelId: norte }],
      phytosanitary: {
        problem: 'Araña roja',
        problemCategory: 'arthropods',
        bbchCode: '71',
        phenologicalStageLabel: 'Cuajado',
        applicatorId: aplicador.id,
        products: [
          { productName: 'Azufre mojable', dose: 3, doseUnit: 'kg_ha' },
          { productName: 'Aceite de parafina', dose: 1.5, doseUnit: 'l_ha' },
        ],
      },
    });

    // La ficha del aplicador cambia después; el tratamiento no.
    await prisma.runInTenantContext({ organizationId: orgId }, (tx) =>
      tx.notebookPerson.update({ where: { id: aplicador.id }, data: { ropoNumber: 'ROPO-999' } }),
    );
    const leido = await actividades.findOne(admin, campana.id, tratamiento.id);

    expect(leido.phytosanitary?.products.map((p) => p.productName)).toEqual([
      'Azufre mojable',
      'Aceite de parafina',
    ]);
    expect(leido.phytosanitary?.applicatorSnapshot).toMatchObject({
      firstName: 'Juan',
      ropoNumber: 'ROPO-123',
    });
    expect(leido.startTime).toBe('07:30');
  });

  it('"Repetir" deja dicho de cuál viene', async () => {
    const campana = await nuevaCampana();
    const original = await actividades.create(admin, campana.id, {
      type: 'irrigation',
      startDate: '2026-09-01',
      targets: [{ parcelId: norte }],
      irrigation: { amount: 20, amountUnit: 'm3' },
    });

    const repetida = await actividades.create(admin, campana.id, {
      type: 'irrigation',
      startDate: '2026-09-02',
      targets: [{ parcelId: norte }],
      irrigation: { amount: 20, amountUnit: 'm3' },
      repeatedFromId: original.id,
    });

    expect(repetida.origin).toBe('repeated');
    expect(repetida.repeatedFromId).toBe(original.id);
  });

  it('cambiar un abonado recalcula sus kilos de nutriente y deja lo anterior en la auditoría', async () => {
    const campana = await nuevaCampana();
    const abonado = await actividades.create(admin, campana.id, {
      type: 'fertilization',
      startDate: '2026-08-01',
      targets: [{ parcelId: norte }],
      fertilization: { productName: 'NPK 15-15-15', dose: 320, doseUnit: 'kg_ha', nPct: 15 },
    });
    expect(abonado.fertilization?.nKgHa).toBe(48);

    const cambiado = await actividades.update(admin, campana.id, abonado.id, {
      fertilization: { productName: 'NPK 20-10-10', dose: 300, doseUnit: 'kg_ha', nPct: 20 },
    });

    expect(cambiado.fertilization?.nKgHa).toBe(60);
    const entrada = await prisma.runInTenantContext({ organizationId: orgId }, (tx) =>
      tx.auditLogEntry.findFirst({
        where: { action: 'campaign_activities.update', targetId: abonado.id },
      }),
    );
    expect(entrada?.metadata).toMatchObject({
      antes: { fertilization: { productName: 'NPK 15-15-15', nKgHa: 48 } },
    });
  });

  it('un riego de un día que se cambia de día sigue siendo de un día', async () => {
    const campana = await nuevaCampana();
    const riego = await actividades.create(admin, campana.id, {
      type: 'irrigation',
      startDate: '2026-09-05',
      targets: [{ parcelId: norte }],
    });

    const movido = await actividades.update(admin, campana.id, riego.id, {
      startDate: '2026-09-06',
    });

    expect(movido.startDate).toBe('2026-09-06');
    expect(movido.endDate).toBe('2026-09-06');
  });

  it('borrar pide motivo opcional, lo guarda y la actividad deja de salir', async () => {
    const campana = await nuevaCampana();
    const labor = await actividades.create(admin, campana.id, {
      type: 'field_work',
      startDate: '2026-03-15',
      targets: [{ parcelId: norte }],
      fieldWork: { workType: 'pruning', pruningResiduesLeft: true },
    });

    await actividades.remove(admin, campana.id, labor.id, 'Apuntada en la campaña equivocada');

    const linea = await actividades.list(admin, campana.id, {});
    expect(linea.find((a) => a.id === labor.id)).toBeUndefined();
    const guardada = await prisma.runInTenantContext({ organizationId: orgId }, (tx) =>
      tx.campaignActivity.findUnique({ where: { id: labor.id } }),
    );
    expect(guardada?.deletedAt).not.toBeNull();
    expect(guardada?.deleteReason).toBe('Apuntada en la campaña equivocada');
  });

  it('la línea de tiempo va de lo último a lo primero y se filtra por tipo y fechas', async () => {
    const campana = await nuevaCampana();
    const alta = (type: 'irrigation' | 'observation', startDate: string) =>
      actividades.create(admin, campana.id, { type, startDate, targets: [{ parcelId: norte }] });
    await alta('irrigation', '2026-09-01');
    await alta('observation', '2026-09-10');
    await alta('irrigation', '2026-09-15');

    const todas = await actividades.list(admin, campana.id, {});
    const riegosDeSeptiembre = await actividades.list(admin, campana.id, {
      type: 'irrigation',
      from: '2026-09-05',
      to: '2026-09-30',
    });

    expect(todas.map((a) => a.startDate)).toEqual(['2026-09-15', '2026-09-10', '2026-09-01']);
    expect(riegosDeSeptiembre.map((a) => a.startDate)).toEqual(['2026-09-15']);
  });

  it('nada antes de que empiece la campaña ni que todavía no haya pasado', async () => {
    const campana = await nuevaCampana();
    const en = (startDate: string) =>
      actividades.create(admin, campana.id, {
        type: 'observation',
        startDate,
        targets: [{ parcelId: norte }],
      });

    await expect(en('2026-01-10')).rejects.toThrow(
      /anterior al inicio de la campaña \(03\/02\/2026\)/,
    );
    await expect(en('2099-01-01')).rejects.toThrow(/no ha pasado/);
  });

  it('una parcela que está en dos unidades exige decir en cuál', async () => {
    const campana = await nuevaCampana();
    const conTomate = await unidades.add(admin, campana.id, {
      cropName: 'Tomate',
      parcels: [{ parcelId: norte, areaHa: 0.2 }],
    });
    const tomate = conTomate.cropUnits[1].id;

    await expect(
      actividades.create(admin, campana.id, {
        type: 'harvest',
        startDate: '2026-09-12',
        targets: [{ parcelId: norte }],
      }),
    ).rejects.toThrow(/"Norte" está en más de una unidad/);

    const cosecha = await actividades.create(admin, campana.id, {
      type: 'harvest',
      startDate: '2026-09-12',
      targets: [{ parcelId: norte, cropUnitId: tomate }],
      harvest: { quantity: 1.2, quantityUnit: 't' },
    });
    expect(cosecha.targets[0].effectiveAreaHa).toBe(0.2);
    expect(cosecha.harvest?.quantityKg).toBe(1200);
  });

  it('en una campaña cerrada no se apunta ni se cambia nada', async () => {
    const campana = await nuevaCampana();
    const riego = await actividades.create(admin, campana.id, {
      type: 'irrigation',
      startDate: '2026-09-01',
      targets: [{ parcelId: norte }],
    });
    await campanas.close(admin, campana.id, { endDate: '2026-10-30' });

    await expect(
      actividades.create(admin, campana.id, {
        type: 'irrigation',
        startDate: '2026-09-02',
        targets: [{ parcelId: norte }],
      }),
    ).rejects.toThrow(/reábrela/);
    await expect(
      actividades.update(admin, campana.id, riego.id, { notes: 'tarde' }),
    ).rejects.toThrow(/reábrela/);
    await expect(actividades.remove(admin, campana.id, riego.id)).rejects.toThrow(/reábrela/);
  });

  it('la campaña no puede empezar después de lo que ya se ha hecho en ella', async () => {
    const campana = await nuevaCampana();
    await actividades.create(admin, campana.id, {
      type: 'observation',
      startDate: '2026-03-01',
      targets: [{ parcelId: norte }],
    });

    await expect(campanas.update(admin, campana.id, { startDate: '2026-04-01' })).rejects.toThrow(
      /desde el 01\/03\/2026/,
    );
  });

  it('el resumen sale de las actividades, con los números guardados', async () => {
    const campana = await campanas.create(admin, fincaId, {
      managementMode: 'simple',
      startDate: '2026-02-03',
      cropUnits: [
        {
          cropName: 'Aguacate',
          expectedYieldKgHa: 12000,
          parcels: [{ parcelId: norte }, { parcelId: sur }],
        },
      ],
    });
    const ambas = [{ parcelId: norte }, { parcelId: sur }];
    await actividades.create(admin, campana.id, {
      type: 'irrigation',
      startDate: '2026-09-01',
      targets: ambas,
      irrigation: { amount: 100, amountUnit: 'm3' },
    });
    await actividades.create(admin, campana.id, {
      type: 'fertilization',
      startDate: '2026-08-01',
      targets: ambas,
      fertilization: { productName: 'NPK 15-15-15', dose: 320, doseUnit: 'kg_ha', nPct: 15 },
    });
    await actividades.create(admin, campana.id, {
      type: 'harvest',
      startDate: '2026-09-20',
      targets: ambas,
      harvest: { quantity: 18, quantityUnit: 't' },
    });

    const datos = await resumen.summary(admin, campana.id);

    expect(datos.activityCount).toBe(3);
    expect(datos.irrigation).toMatchObject({ count: 1, volumeM3: 100, withoutVolume: 0 });
    expect(datos.fertilization?.nKgHa).toBe(48);
    expect(datos.harvest?.quantityKg).toBe(18000);
    expect(datos.harvest?.yieldKgHa).toBeCloseTo(18000 / datos.areaHa, 0);
    expect(datos.harvest?.expectedYieldKgHa).toBe(12000);
    expect(datos.phytosanitary).toBeNull();
    expect(datos.lastActivity).toEqual({ type: 'harvest', date: '2026-09-20' });
  });
});
