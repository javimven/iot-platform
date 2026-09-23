import { BadRequestException, ConflictException, NotFoundException } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { AuditLogService } from '../../src/common/audit/audit-log.service';
import { AccessTokenClaims } from '../../src/common/guards/jwt-auth.guard';
import { PrismaService } from '../../src/common/prisma/prisma.service';
import { StorageService } from '../../src/common/storage/storage.service';
import { ActivitiesService } from '../../src/modules/campaigns/activities.service';
import { CampaignAccess } from '../../src/modules/campaigns/campaign-access';
import { CampaignsService } from '../../src/modules/campaigns/campaigns.service';
import { DocumentsService } from '../../src/modules/campaigns/documents.service';

/**
 * Fotos y documentos del cuaderno contra un Postgres real (BACKLOG.md #60,
 * fase 6). El almacenamiento va simulado a propósito: lo que hay que probar
 * aquí es el modelo —que un fichero se guarde una sola vez, que quitarlo de un
 * sitio no lo borre de otro, que una campaña cerrada no admita adjuntos— y no
 * el cliente de S3, que tiene su propia prueba (`storage.spec.ts`, contra
 * MinIO). Así esto corre también en el CI, que no levanta MinIO.
 */
class AlmacenamientoSimulado {
  readonly objetos = new Map<string, number>();
  borrados: string[] = [];
  fallaLaSubida = false;

  async subir(objeto: { clave: string; cuerpo: Uint8Array }) {
    if (this.fallaLaSubida) {
      throw new Error('el almacenamiento dice que no');
    }
    this.objetos.set(objeto.clave, objeto.cuerpo.byteLength);
    return { objectKey: objeto.clave, byteSize: objeto.cuerpo.byteLength, checksum: 'x' };
  }

  async urlFirmada(clave: string) {
    return {
      url: `https://ejemplo.invalid/${clave}?firma=abc`,
      expiresAt: new Date(Date.now() + 900_000),
    };
  }

  async borrar(claves: string[]) {
    this.borrados.push(...claves);
    for (const clave of claves) {
      this.objetos.delete(clave);
    }
  }
}

/** Un JPEG de verdad en lo que importa: su cabecera. */
function foto(relleno: string): Buffer {
  return Buffer.concat([Buffer.from([0xff, 0xd8, 0xff, 0xe0]), Buffer.from(relleno, 'utf8')]);
}

describe('Documentos del cuaderno (Postgres real)', () => {
  let prisma: PrismaService;
  let documentos: DocumentsService;
  let campanas: CampaignsService;
  let actividades: ActivitiesService;
  let almacen: AlmacenamientoSimulado;
  let orgId: string;
  let fincaId: string;
  let parcelaId: string;
  let admin: AccessTokenClaims;

  const poligono = JSON.stringify({
    type: 'Polygon',
    coordinates: [
      [
        [-3.5, 38.5],
        [-3.499, 38.5],
        [-3.499, 38.501],
        [-3.5, 38.501],
        [-3.5, 38.5],
      ],
    ],
  });

  async function crearCampana() {
    return campanas.create(admin, fincaId, {
      managementMode: 'simple',
      startDate: '2026-03-01',
      cropUnits: [{ cropId: 'almendro', parcels: [{ parcelId: parcelaId }] }],
    });
  }

  async function crearActividad(campaignId: string, cropUnitId: string) {
    return actividades.create(admin, campaignId, {
      type: 'harvest',
      startDate: '2026-03-10',
      targets: [{ cropUnitId, parcelId: parcelaId }],
      harvest: { quantity: 1200, quantityUnit: 'kg' },
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
    almacen = new AlmacenamientoSimulado();
    documentos = new DocumentsService(
      prisma,
      auditLog,
      acceso,
      almacen as unknown as StorageService,
    );
    campanas = new CampaignsService(prisma, auditLog, acceso);
    actividades = new ActivitiesService(prisma, auditLog, acceso);

    // El catálogo lo siembra `seed.ts`, que el CI no ejecuta (TESTING_STRATEGY §4).
    if (!(await prisma.crop.findUnique({ where: { id: 'almendro' } }))) {
      await prisma.crop.create({ data: { id: 'almendro', name: 'Almendro', category: 'woody' } });
    }

    orgId = (
      await prisma.organization.create({
        data: {
          slug: `documentos-${randomUUID().slice(0, 8)}`,
          name: 'Explotación con papeles',
          contactEmail: 'papeles@example.com',
        },
      })
    ).id;
    admin = { sub: randomUUID(), type: 'access', organizationId: orgId, roleCode: 'org_admin' };

    fincaId = (
      await prisma.runInTenantContext({ organizationId: orgId }, (tx) =>
        tx.installation.create({ data: { organizationId: orgId, name: 'Finca de los Papeles' } }),
      )
    ).id;

    const filas = await prisma.runInTenantContext(
      { organizationId: orgId },
      (tx) =>
        tx.$queryRaw<Array<{ id: string }>>`
        INSERT INTO parcels (organization_id, installation_id, name, geometry, area_m2,
                             bbox_min_lon, bbox_min_lat, bbox_max_lon, bbox_max_lat)
        SELECT ${orgId}::uuid, ${fincaId}::uuid, 'Los Almendros',
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
      await tx.documentLink.deleteMany({ where: org });
      await tx.document.deleteMany({ where: org });
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

  it('adjunta una foto a una actividad y la devuelve con su enlace firmado', async () => {
    const campana = await crearCampana();
    const actividad = await crearActividad(campana.id, campana.cropUnits[0].id);

    const documento = await documentos.subir(
      admin,
      { campaignId: campana.id, activityId: actividad.id },
      { buffer: foto('albaran-1'), originalname: 'C:\\fotos\\albarán.jpg' },
      { documentType: 'delivery_note', title: 'Albarán de la cooperativa' },
    );

    expect(documento.mediaType).toBe('image/jpeg');
    expect(documento.filename).toBe('albarán.jpg');
    expect(documento.activityId).toBe(actividad.id);
    expect(documento.url).toContain('firma=');
    expect(documento.urlExpiresAt.getTime()).toBeGreaterThan(Date.now());
    // El objeto está donde dice la clave, y la clave no lleva el nombre real.
    expect([...almacen.objetos.keys()].some((k) => k.includes(documento.id))).toBe(true);
    expect([...almacen.objetos.keys()].every((k) => !k.includes('albarán'))).toBe(true);

    const auditoria = await prisma.runInTenantContext({ organizationId: orgId }, (tx) =>
      tx.auditLogEntry.findFirst({ where: { action: 'documents.create', targetId: documento.id } }),
    );
    expect(auditoria).not.toBeNull();
  });

  it('el mismo fichero no se guarda dos veces, aunque se suba a dos sitios', async () => {
    const campana = await crearCampana();
    const actividad = await crearActividad(campana.id, campana.cropUnits[0].id);
    const objetosAntes = almacen.objetos.size;
    const misma = () => foto('factura-compartida');

    const enLaCampana = await documentos.subir(
      admin,
      { campaignId: campana.id },
      { buffer: misma(), originalname: 'factura.jpg' },
      { documentType: 'invoice' },
    );
    const enLaActividad = await documentos.subir(
      admin,
      { campaignId: campana.id, activityId: actividad.id },
      { buffer: misma(), originalname: 'factura.jpg' },
      { documentType: 'invoice' },
    );

    expect(enLaActividad.id).toBe(enLaCampana.id);
    expect(almacen.objetos.size).toBe(objetosAntes + 1);

    const lista = await documentos.listar(admin, campana.id);
    expect(lista.filter((d) => d.id === enLaCampana.id)).toHaveLength(2);
    expect(lista.map((d) => d.activityId)).toContain(actividad.id);
    expect(lista.map((d) => d.activityId)).toContain(null);
  });

  it('subir dos veces lo mismo al mismo sitio no lo duplica', async () => {
    const campana = await crearCampana();
    const subir = () =>
      documentos.subir(
        admin,
        { campaignId: campana.id },
        { buffer: foto('analitica'), originalname: 'analitica.jpg' },
        { documentType: 'analysis' },
      );

    await subir();
    await subir();

    expect(await documentos.listar(admin, campana.id)).toHaveLength(1);
  });

  it('quitarlo de un sitio lo deja en el otro; al quedarse sin sitios, se da de baja', async () => {
    const campana = await crearCampana();
    const actividad = await crearActividad(campana.id, campana.cropUnits[0].id);
    const compartido = () => foto('certificado');

    const documento = await documentos.subir(
      admin,
      { campaignId: campana.id },
      { buffer: compartido(), originalname: 'certificado.jpg' },
      { documentType: 'analysis' },
    );
    await documentos.subir(
      admin,
      { campaignId: campana.id, activityId: actividad.id },
      { buffer: compartido(), originalname: 'certificado.jpg' },
      { documentType: 'analysis' },
    );

    await documentos.quitar(admin, { campaignId: campana.id }, documento.id);
    const tras = await documentos.listar(admin, campana.id);
    expect(tras).toHaveLength(1);
    expect(tras[0].activityId).toBe(actividad.id);

    await documentos.quitar(
      admin,
      { campaignId: campana.id, activityId: actividad.id },
      documento.id,
    );
    expect(await documentos.listar(admin, campana.id)).toHaveLength(0);

    const fila = await prisma.runInTenantContext({ organizationId: orgId }, (tx) =>
      tx.document.findUnique({ where: { id: documento.id } }),
    );
    expect(fila?.deletedAt).not.toBeNull();
    // El objeto se conserva: es la prueba de lo que se subió.
    expect(almacen.borrados).not.toContain(fila?.objectKey);
  });

  it('quitar algo que no está en ese sitio es un 404, no un borrado silencioso', async () => {
    const campana = await crearCampana();
    await expect(
      documentos.quitar(admin, { campaignId: campana.id }, randomUUID()),
    ).rejects.toThrow(NotFoundException);
  });

  it('no deja colgar un documento de una actividad de otra campaña', async () => {
    const campana = await crearCampana();
    const otra = await crearCampana();
    const actividadDeOtra = await crearActividad(otra.id, otra.cropUnits[0].id);

    await expect(
      documentos.subir(
        admin,
        { campaignId: campana.id, activityId: actividadDeOtra.id },
        { buffer: foto('cruzada'), originalname: 'cruzada.jpg' },
        {},
      ),
    ).rejects.toThrow(BadRequestException);
  });

  it('una campaña cerrada no admite adjuntos nuevos ni que se le quiten', async () => {
    const campana = await crearCampana();
    const documento = await documentos.subir(
      admin,
      { campaignId: campana.id },
      { buffer: foto('antes-de-cerrar'), originalname: 'antes.jpg' },
      {},
    );
    await campanas.close(admin, campana.id, { endDate: '2026-09-30' });

    await expect(
      documentos.subir(
        admin,
        { campaignId: campana.id },
        { buffer: foto('despues-de-cerrar'), originalname: 'despues.jpg' },
        {},
      ),
    ).rejects.toThrow(ConflictException);
    await expect(
      documentos.quitar(admin, { campaignId: campana.id }, documento.id),
    ).rejects.toThrow(/reábrela/);
  });

  it('lo que no es una foto ni un PDF no llega ni a subirse', async () => {
    const campana = await crearCampana();
    const objetosAntes = almacen.objetos.size;

    await expect(
      documentos.subir(
        admin,
        { campaignId: campana.id },
        { buffer: Buffer.from('MZ ejecutable', 'latin1'), originalname: 'virus.jpg' },
        {},
      ),
    ).rejects.toThrow(/Solo se admiten fotos/);
    expect(almacen.objetos.size).toBe(objetosAntes);
  });

  it('si la fila no llega a escribirse, el objeto no se queda huérfano', async () => {
    const campana = await crearCampana();
    // Un tipo de documento que el CHECK de la base no admite: la subida sale
    // bien y la fila revienta, que es justo el caso que deja basura.
    await expect(
      documentos.subir(
        admin,
        { campaignId: campana.id },
        { buffer: foto('huerfano'), originalname: 'huerfano.jpg' },
        { documentType: 'selfie' as never },
      ),
    ).rejects.toThrow();

    expect(almacen.borrados.length).toBeGreaterThan(0);
    expect(almacen.objetos.has(almacen.borrados[almacen.borrados.length - 1])).toBe(false);
  });
});
