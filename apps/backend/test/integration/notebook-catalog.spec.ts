import { BadRequestException, ForbiddenException, NotFoundException } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { AuditLogService } from '../../src/common/audit/audit-log.service';
import { AccessTokenClaims } from '../../src/common/guards/jwt-auth.guard';
import { PrismaService } from '../../src/common/prisma/prisma.service';
import { CampaignAccess } from '../../src/modules/campaigns/campaign-access';
import { CampaignsService } from '../../src/modules/campaigns/campaigns.service';
import { ActivitiesService } from '../../src/modules/campaigns/activities.service';
import { NotebookCompletenessService } from '../../src/modules/campaigns/notebook-completeness';
import { NotebookCatalogService } from '../../src/modules/campaigns/notebook.service';

/**
 * Catálogos del cuaderno y revisión de lo que falta, contra un Postgres real
 * (BACKLOG.md #60, fase 5). Aquí se prueban el alcance por finca con un
 * miembro de verdad, la baja lógica, y que la revisión ve lo mismo que hay
 * guardado: con Prisma simulado, una copia del aplicador que no se guardara
 * pasaría desapercibida.
 */
describe('Cuaderno completo: catálogos y revisión (Postgres real)', () => {
  let prisma: PrismaService;
  let catalogo: NotebookCatalogService;
  let campanas: CampaignsService;
  let actividades: ActivitiesService;
  let completitud: NotebookCompletenessService;
  let orgId: string;
  let fincaId: string;
  let otraFincaId: string;
  let parcelaId: string;
  let admin: AccessTokenClaims;
  let capataz: AccessTokenClaims;

  const poligono = JSON.stringify({
    type: 'Polygon',
    coordinates: [
      [
        [-4.5, 37.5],
        [-4.499, 37.5],
        [-4.499, 37.501],
        [-4.5, 37.501],
        [-4.5, 37.5],
      ],
    ],
  });

  async function crearParcela(installationId: string, name: string) {
    const filas = await prisma.runInTenantContext(
      { organizationId: orgId },
      (tx) =>
        tx.$queryRaw<Array<{ id: string }>>`
        INSERT INTO parcels (organization_id, installation_id, name, geometry, area_m2,
                             bbox_min_lon, bbox_min_lat, bbox_max_lon, bbox_max_lat)
        SELECT ${orgId}::uuid, ${installationId}::uuid, ${name},
               g, ST_Area(g::geography),
               ST_XMin(g::box3d), ST_YMin(g::box3d), ST_XMax(g::box3d), ST_YMax(g::box3d)
        FROM (SELECT ST_Multi(ST_SetSRID(ST_GeomFromGeoJSON(${poligono}), 4326)) AS g) t
        RETURNING id
      `,
    );
    return filas[0].id;
  }

  beforeAll(async () => {
    if (!process.env.DATABASE_URL) {
      throw new Error('DATABASE_URL no está definida — esta prueba necesita un Postgres real.');
    }
    prisma = new PrismaService();
    await prisma.onModuleInit();
    const acceso = new CampaignAccess(prisma);
    const auditLog = new AuditLogService();
    catalogo = new NotebookCatalogService(prisma, auditLog, acceso);
    campanas = new CampaignsService(prisma, auditLog, acceso);
    actividades = new ActivitiesService(prisma, auditLog, acceso);
    completitud = new NotebookCompletenessService(prisma, acceso);

    // Catálogo y roles los siembra `seed.ts`, que el CI **no** ejecuta antes
    // de estas pruebas: sin esto, el miembro con alcance por finca choca con
    // la clave foránea a `roles` y el fallo solo se ve en el pipeline.
    if (!(await prisma.crop.findUnique({ where: { id: 'olivo' } }))) {
      await prisma.crop.create({ data: { id: 'olivo', name: 'Olivo', category: 'woody' } });
    }
    await prisma.role.upsert({
      where: { code: 'technician' },
      update: {},
      create: { code: 'technician', label: 'Técnico' },
    });

    orgId = (
      await prisma.organization.create({
        data: {
          slug: `cuaderno-${randomUUID().slice(0, 8)}`,
          name: 'Explotación del cuaderno',
          contactEmail: 'cuaderno@example.com',
        },
      })
    ).id;
    admin = { sub: randomUUID(), type: 'access', organizationId: orgId, roleCode: 'org_admin' };

    const finca = (name: string, conTitular: boolean) =>
      prisma.runInTenantContext({ organizationId: orgId }, (tx) =>
        tx.installation.create({
          data: {
            organizationId: orgId,
            name,
            ...(conTitular
              ? { holderName: 'Ana Ruiz', holderNif: '12345678Z', regionCode: 'ES-AN' }
              : {}),
          },
        }),
      );
    fincaId = (await finca('Finca del Olivar', true)).id;
    otraFincaId = (await finca('Finca de Arriba', false)).id;
    parcelaId = await crearParcela(fincaId, 'Olivar Bajo');

    // Un miembro restringido a la otra finca: el alcance por finca se prueba
    // con las filas de verdad, no simulando `resolveInstallationScope`.
    const usuario = await prisma.user.create({
      data: {
        email: `capataz-${randomUUID().slice(0, 8)}@example.com`,
        passwordHash: 'x',
        fullName: 'Capataz de la otra finca',
      },
    });
    // Con contexto de organización: `members` tiene RLS y, sin contexto, la
    // política no puede evaluarse (el parámetro de sesión llega vacío).
    const miembro = await prisma.runInTenantContext({ organizationId: orgId }, (tx) =>
      tx.member.create({
        data: {
          userId: usuario.id,
          organizationId: orgId,
          roleCode: 'technician',
          status: 'active',
        },
      }),
    );
    await prisma.runInTenantContext({ organizationId: orgId }, (tx) =>
      tx.memberInstallationScope.create({
        data: { memberId: miembro.id, installationId: otraFincaId },
      }),
    );
    capataz = {
      sub: usuario.id,
      type: 'access',
      organizationId: orgId,
      roleCode: 'technician',
      memberId: miembro.id,
    };
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
      await tx.notebookPerson.deleteMany({ where: org });
      await tx.notebookEquipment.deleteMany({ where: org });
    });
    await prisma.$disconnect();
  });

  describe('personas y equipos', () => {
    it('da de alta una persona, la audita y la deja lista para elegir', async () => {
      const persona = await catalogo.createPerson(admin, {
        kind: 'own_staff',
        firstName: 'Ana',
        surname1: 'Ruiz',
        nif: '12345678z',
        ropoNumber: 'AND-1234',
      });

      expect(persona.displayName).toBe('Ana Ruiz');
      // El NIF en mayúsculas: se busca por él.
      expect(persona.nif).toBe('12345678Z');
      expect(persona.installationId).toBeNull();

      const auditoria = await prisma.runInTenantContext({ organizationId: orgId }, (tx) =>
        tx.auditLogEntry.findFirst({
          where: { action: 'notebook_people.create', targetId: persona.id },
        }),
      );
      expect(auditoria).not.toBeNull();
    });

    it('una persona sin nombre ni razón social no se guarda', async () => {
      await expect(catalogo.createPerson(admin, { kind: 'service_company' })).rejects.toThrow(
        BadRequestException,
      );
    });

    it('da de alta un equipo con sus fechas y lo lee como se escribió', async () => {
      const equipo = await catalogo.createEquipment(admin, {
        description: 'Atomizador',
        brand: 'Hardi',
        romaNumber: '14-123456',
        lastInspectionOn: '2025-11-03',
      });

      expect(equipo.displayName).toBe('Atomizador · Hardi');
      expect(equipo.lastInspectionOn).toBe('2025-11-03');
    });

    it('la baja es lógica: deja de salir, pero se puede consultar', async () => {
      const persona = await catalogo.createPerson(admin, {
        kind: 'adviser',
        companyName: 'Asesoría Agro S.L.',
      });
      await catalogo.removePerson(admin, persona.id);

      const vivas = await catalogo.listPeople(admin, {});
      expect(vivas.map((p) => p.id)).not.toContain(persona.id);

      const todas = await catalogo.listPeople(admin, { includeDeleted: true });
      expect(todas.find((p) => p.id === persona.id)?.deleted).toBe(true);

      // Y no se puede seguir cambiando lo que está de baja.
      await expect(catalogo.removePerson(admin, persona.id)).rejects.toThrow(NotFoundException);
    });

    it('filtra por tipo de persona', async () => {
      const asesores = await catalogo.listPeople(admin, { kind: 'adviser' });
      expect(asesores.every((p) => p.kind === 'adviser')).toBe(true);
    });

    it('quien solo ve una finca ve las suyas y las comunes, no las de otra finca', async () => {
      const deLaFinca = await catalogo.createPerson(admin, {
        kind: 'own_staff',
        firstName: 'Pepe',
        surname1: 'del Olivar',
        installationId: fincaId,
      });
      const comun = await catalogo.createPerson(admin, {
        kind: 'own_staff',
        firstName: 'Lucía',
        surname1: 'de Todas',
      });

      const suyas = await catalogo.listPeople(capataz, {});
      expect(suyas.map((p) => p.id)).toContain(comun.id);
      expect(suyas.map((p) => p.id)).not.toContain(deLaFinca.id);

      // Y ni la ve ni la toca.
      await expect(catalogo.updatePerson(capataz, deLaFinca.id, { notes: 'mía' })).rejects.toThrow(
        ForbiddenException,
      );
      await expect(catalogo.listPeople(capataz, { installationId: fincaId })).rejects.toThrow(
        ForbiddenException,
      );
    });

    it('al cambiar una persona, lo omitido se queda como estaba', async () => {
      const persona = await catalogo.createPerson(admin, {
        kind: 'service_company',
        companyName: 'Tratamientos del Sur S.L.',
        nif: 'B12345678',
      });
      const cambiada = await catalogo.updatePerson(admin, persona.id, { ropoNumber: 'AND-999' });

      expect(cambiada.companyName).toBe('Tratamientos del Sur S.L.');
      expect(cambiada.nif).toBe('B12345678');
      expect(cambiada.ropoNumber).toBe('AND-999');

      // Y una cadena vacía sí borra el dato.
      const sinRopo = await catalogo.updatePerson(admin, persona.id, { ropoNumber: '' });
      expect(sinRopo.ropoNumber).toBeNull();
    });
  });

  describe('revisión del cuaderno', () => {
    async function campanaCompleta(installationId = fincaId) {
      return campanas.create(admin, installationId, {
        managementMode: 'complete',
        startDate: '2026-03-01',
        notebookProfile: { usesPlantProtectionProducts: true },
        cropUnits: [
          {
            cropId: 'olivo',
            waterRegime: 'rainfed',
            productionSystem: 'conventional',
            parcels: [{ parcelId: parcelaId }],
          },
        ],
      });
    }

    it('a una campaña sencilla no se le revisa nada', async () => {
      const campana = await campanas.create(admin, fincaId, {
        managementMode: 'simple',
        startDate: '2026-03-01',
        cropUnits: [{ cropId: 'olivo', parcels: [{ parcelId: parcelaId }] }],
      });

      const revision = await completitud.completeness(admin, campana.id);
      expect(revision.applicable).toBe(false);
      expect(revision.missingCount).toBe(0);
    });

    it('un tratamiento a medias deja ver qué falta y con qué fuente', async () => {
      const campana = await campanaCompleta();
      await actividades.create(admin, campana.id, {
        type: 'phytosanitary',
        startDate: '2026-03-10',
        targets: [{ cropUnitId: campana.cropUnits[0].id, parcelId: parcelaId }],
        phytosanitary: { products: [{ productName: 'Cobre 50' }] },
      });

      const revision = await completitud.completeness(admin, campana.id);
      const codigos = revision.activities[0].items.map((a) => a.code.split(':')[0]);

      expect(revision.applicable).toBe(true);
      expect(codigos).toEqual(
        expect.arrayContaining([
          'phyto.registry_number',
          'phyto.dose',
          'phyto.start_time',
          'phyto.stage',
          'phyto.applicator',
          'phyto.equipment',
        ]),
      );
      expect(revision.activities[0].items[0].sourceLabel).toContain('Reglamento');
    });

    it('con el aplicador y el equipo del catálogo, el tratamiento queda completo', async () => {
      const campana = await campanaCompleta();
      const aplicador = await catalogo.createPerson(admin, {
        kind: 'own_staff',
        firstName: 'Ana',
        surname1: 'Ruiz',
        ropoNumber: 'AND-1234',
      });
      const equipo = await catalogo.createEquipment(admin, { description: 'Atomizador' });

      await actividades.create(admin, campana.id, {
        type: 'phytosanitary',
        startDate: '2026-03-12',
        startTime: '08:30',
        targets: [{ cropUnitId: campana.cropUnits[0].id, parcelId: parcelaId }],
        phytosanitary: {
          problem: 'Repilo',
          phenologicalStageLabel: 'Floración',
          bbchCode: '65',
          applicatorId: aplicador.id,
          equipmentId: equipo.id,
          products: [
            { productName: 'Cobre 50', registryNumber: '25.123', dose: 2, doseUnit: 'kg_ha' },
          ],
        },
      });

      const revision = await completitud.completeness(admin, campana.id);
      expect(revision.activities).toEqual([]);
      expect(revision.missingCount).toBe(0);
    });

    it('la finca sin titular y la unidad sin describir salen en la revisión', async () => {
      const parcelaArriba = await crearParcela(otraFincaId, 'Arriba');
      const campana = await campanas.create(admin, otraFincaId, {
        managementMode: 'complete',
        startDate: '2026-03-01',
        cropUnits: [{ cropId: 'olivo', parcels: [{ parcelId: parcelaArriba }] }],
      });

      const revision = await completitud.completeness(admin, campana.id);
      const codigos = revision.campaign.map((a) => a.code.split(':')[0]);
      expect(codigos).toEqual(
        expect.arrayContaining([
          'campaign.profile',
          'installation.holder_name',
          'installation.holder_nif',
          'crop_unit.water_regime',
          'crop_unit.production_system',
        ]),
      );
    });

    it('cerrar avisa de lo que falta, pero no lo impide, y queda contado', async () => {
      const campana = await campanaCompleta();
      await actividades.create(admin, campana.id, {
        type: 'phytosanitary',
        startDate: '2026-03-10',
        targets: [{ cropUnitId: campana.cropUnits[0].id, parcelId: parcelaId }],
        phytosanitary: { products: [{ productName: 'Cobre 50' }] },
      });

      const cerrada = await campanas.close(admin, campana.id, { endDate: '2026-09-30' });

      expect(cerrada.status).toBe('closed');
      expect(cerrada.completeness.missingCount).toBeGreaterThan(0);

      const auditoria = await prisma.runInTenantContext({ organizationId: orgId }, (tx) =>
        tx.auditLogEntry.findFirst({
          where: { action: 'campaigns.close', targetId: campana.id },
        }),
      );
      const metadatos = auditoria?.metadata as Record<string, unknown>;
      expect(metadatos.informacionPendiente).toBe(cerrada.completeness.missingCount);
      expect(metadatos.reglasDelCuaderno).toBe(cerrada.completeness.rules.id);
    });
  });
});
