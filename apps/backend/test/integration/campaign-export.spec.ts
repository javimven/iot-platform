import { randomUUID } from 'node:crypto';
import { AuditLogService } from '../../src/common/audit/audit-log.service';
import { AccessTokenClaims } from '../../src/common/guards/jwt-auth.guard';
import { PrismaService } from '../../src/common/prisma/prisma.service';
import { ActivitiesService } from '../../src/modules/campaigns/activities.service';
import { CampaignAccess } from '../../src/modules/campaigns/campaign-access';
import { CampaignsService } from '../../src/modules/campaigns/campaigns.service';
import { CampaignExportService } from '../../src/modules/campaigns/export/export.service';

/**
 * Exportar el cuaderno contra un Postgres real (BACKLOG.md #60, fase 7). Lo
 * que solo se puede probar aquí: que una campaña cerrada se exporte desde su
 * instantánea y no desde las tablas — es decir, que cambiar el titular hoy no
 * cambie el cuaderno cerrado de ayer (ADR-0012).
 */
describe('Exportación del cuaderno (Postgres real)', () => {
  let prisma: PrismaService;
  let exportacion: CampaignExportService;
  let campanas: CampaignsService;
  let actividades: ActivitiesService;
  let orgId: string;
  let fincaId: string;
  let parcelaId: string;
  let admin: AccessTokenClaims;

  const poligono = JSON.stringify({
    type: 'Polygon',
    coordinates: [
      [
        [-2.5, 37.5],
        [-2.499, 37.5],
        [-2.499, 37.501],
        [-2.5, 37.501],
        [-2.5, 37.5],
      ],
    ],
  });

  async function campanaConActividades() {
    const campana = await campanas.create(admin, fincaId, {
      managementMode: 'complete',
      startDate: '2026-03-01',
      notebookProfile: { usesPlantProtectionProducts: true },
      cropUnits: [
        {
          cropId: 'vid',
          variety: 'Tempranillo',
          waterRegime: 'rainfed',
          productionSystem: 'organic',
          parcels: [{ parcelId: parcelaId }],
        },
      ],
    });
    const unidad = campana.cropUnits[0].id;

    await actividades.create(admin, campana.id, {
      type: 'phytosanitary',
      startDate: '2026-05-10',
      startTime: '08:30',
      targets: [{ cropUnitId: unidad, parcelId: parcelaId }],
      phytosanitary: {
        problem: 'Mildiu',
        products: [
          { productName: 'Cobre 50', registryNumber: '25.123', dose: 2, doseUnit: 'kg_ha' },
          { productName: 'Mojante', dose: 0.2, doseUnit: 'l_hl' },
        ],
      },
    });
    await actividades.create(admin, campana.id, {
      type: 'irrigation',
      startDate: '2026-06-01',
      endDate: '2026-06-15',
      targets: [{ cropUnitId: unidad, parcelId: parcelaId }],
      irrigation: { amount: 18, amountUnit: 'm3_ha', system: 'drip' },
    });
    return campana;
  }

  beforeAll(async () => {
    if (!process.env.DATABASE_URL) {
      throw new Error('DATABASE_URL no está definida — esta prueba necesita un Postgres real.');
    }
    prisma = new PrismaService();
    await prisma.onModuleInit();
    const acceso = new CampaignAccess(prisma);
    const auditLog = new AuditLogService();
    exportacion = new CampaignExportService(prisma, acceso);
    campanas = new CampaignsService(prisma, auditLog, acceso);
    actividades = new ActivitiesService(prisma, auditLog, acceso);

    // El catálogo lo siembra `seed.ts`, que el CI no ejecuta (TESTING_STRATEGY §4).
    if (!(await prisma.crop.findUnique({ where: { id: 'vid' } }))) {
      await prisma.crop.create({ data: { id: 'vid', name: 'Vid', category: 'woody' } });
    }

    orgId = (
      await prisma.organization.create({
        data: {
          slug: `export-${randomUUID().slice(0, 8)}`,
          name: 'Bodega de prueba',
          contactEmail: 'export@example.com',
        },
      })
    ).id;
    admin = { sub: randomUUID(), type: 'access', organizationId: orgId, roleCode: 'org_admin' };

    fincaId = (
      await prisma.runInTenantContext({ organizationId: orgId }, (tx) =>
        tx.installation.create({
          data: {
            organizationId: orgId,
            name: 'Viña Vieja',
            holderName: 'Ana Ruiz',
            holderNif: '12345678Z',
            regionCode: 'ES-CM',
          },
        }),
      )
    ).id;

    const filas = await prisma.runInTenantContext(
      { organizationId: orgId },
      (tx) =>
        tx.$queryRaw<Array<{ id: string }>>`
        INSERT INTO parcels (organization_id, installation_id, name, geometry, area_m2,
                             bbox_min_lon, bbox_min_lat, bbox_max_lon, bbox_max_lat)
        SELECT ${orgId}::uuid, ${fincaId}::uuid, 'Majuelo',
               g, ST_Area(g::geography),
               ST_XMin(g::box3d), ST_YMin(g::box3d), ST_XMax(g::box3d), ST_YMax(g::box3d)
        FROM (SELECT ST_Multi(ST_SetSRID(ST_GeomFromGeoJSON(${poligono}), 4326)) AS g) t
        RETURNING id
      `,
    );
    parcelaId = filas[0].id;
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

  it('el JSON lleva el cuaderno entero, con su versión de formato', async () => {
    const campana = await campanaConActividades();
    const fichero = await exportacion.exportar(admin, campana.id, { formato: 'json' });
    const json = JSON.parse(fichero.bytes.toString('utf8'));

    expect(fichero.mediaType).toContain('application/json');
    expect(fichero.filename).toBe(`Cuaderno - ${campana.name}.json`);
    expect(json.schemaVersion).toBe('cuaderno-1');
    expect(json.source).toBe('live');
    expect(json.installation.holderName).toBe('Ana Ruiz');
    expect(json.cropUnits[0].variety).toBe('Tempranillo');
    expect(json.activities).toHaveLength(2);
    // Los normalizados que calcula el servidor viajan con el resto.
    const riego = json.activities.find((a: { type: string }) => a.type === 'irrigation');
    expect(riego.irrigation.volumeM3).toBeGreaterThan(0);
    // La revisión del cuaderno completo va dentro, y nunca dice que cumple.
    expect(json.pending.rules.id).toMatch(/^ES-/);
    expect(fichero.bytes.toString('utf8')).not.toMatch(/cumple/i);
  });

  it('el CSV saca una fila por producto del tratamiento', async () => {
    const campana = await campanaConActividades();
    const fichero = await exportacion.exportar(admin, campana.id, { formato: 'csv' });
    const lineas = fichero.bytes.toString('utf8').split('\r\n');

    expect(fichero.mediaType).toContain('text/csv');
    expect(lineas[0]).toContain('fecha_inicio');
    expect(lineas.filter((l) => l.includes('Tratamiento fitosanitario'))).toHaveLength(2);
    expect(lineas.some((l) => l.includes('Cobre 50') && l.includes('25.123'))).toBe(true);
  });

  it('el PDF sale en las dos disposiciones, con nombres distintos', async () => {
    const campana = await campanaConActividades();
    const informe = await exportacion.exportar(admin, campana.id, { formato: 'pdf' });
    const cue = await exportacion.exportar(admin, campana.id, {
      formato: 'pdf',
      disposicion: 'cue',
    });

    expect(informe.mediaType).toBe('application/pdf');
    expect(informe.bytes.subarray(0, 5).toString('latin1')).toBe('%PDF-');
    expect(cue.bytes.subarray(0, 5).toString('latin1')).toBe('%PDF-');
    expect(informe.filename.endsWith('.pdf')).toBe(true);
    expect(cue.filename.endsWith('.cue.pdf')).toBe(true);
  });

  it('una campaña cerrada se exporta desde su instantánea: el titular de entonces', async () => {
    const campana = await campanaConActividades();
    await campanas.close(admin, campana.id, { endDate: '2026-09-30' });

    // El titular cambia después de cerrar (una herencia, un arrendamiento).
    await prisma.runInTenantContext({ organizationId: orgId }, (tx) =>
      tx.installation.update({
        where: { id: fincaId },
        data: { holderName: 'Nuevo titular S.L.', holderNif: 'B00000000' },
      }),
    );

    const fichero = await exportacion.exportar(admin, campana.id, { formato: 'json' });
    const json = JSON.parse(fichero.bytes.toString('utf8'));

    expect(json.source).toBe('snapshot');
    expect(json.installation.holderName).toBe('Ana Ruiz');
    expect(json.installation.holderNif).toBe('12345678Z');
    expect(json.campaign.status).toBe('closed');

    // Y una campaña viva de la misma finca sí ve el titular nuevo.
    const viva = await campanaConActividades();
    const deLaViva = JSON.parse(
      (await exportacion.exportar(admin, viva.id, { formato: 'json' })).bytes.toString('utf8'),
    );
    expect(deLaViva.source).toBe('live');
    expect(deLaViva.installation.holderName).toBe('Nuevo titular S.L.');

    // Se deja la finca como estaba para las demás pruebas.
    await prisma.runInTenantContext({ organizationId: orgId }, (tx) =>
      tx.installation.update({
        where: { id: fincaId },
        data: { holderName: 'Ana Ruiz', holderNif: '12345678Z' },
      }),
    );
  });

  it('una campaña de otra organización no se exporta', async () => {
    const campana = await campanaConActividades();
    const otro: AccessTokenClaims = {
      sub: randomUUID(),
      type: 'access',
      organizationId: randomUUID(),
      roleCode: 'org_admin',
    };

    await expect(exportacion.exportar(otro, campana.id, { formato: 'json' })).rejects.toThrow(
      /not found/i,
    );
  });
});
