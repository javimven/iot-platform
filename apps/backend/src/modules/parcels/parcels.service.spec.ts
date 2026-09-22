import { ConflictException, ForbiddenException, NotFoundException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { ParcelsService } from './parcels.service';
import { ParcelGeometryService } from './parcel-geometry.service';
import { ParcelsRepository } from './parcels.repository';
import { PrismaService } from '../../common/prisma/prisma.service';
import { AuditLogService } from '../../common/audit/audit-log.service';
import { AccessTokenClaims } from '../../common/guards/jwt-auth.guard';
import { SatelliteQueueProducer } from '../../common/queues/satellite-queue.producer';

/**
 * BACKLOG.md #36. Lo que no cubren ni la prueba de integración (que ejercita
 * RLS y PostGIS de verdad) ni la de geometría: el alcance por instalación, la
 * auditoría, y qué pasa con las estaciones al borrar una parcela.
 */
describe('ParcelsService', () => {
  const usuario: AccessTokenClaims = {
    sub: 'user-1',
    type: 'access',
    organizationId: 'org-1',
    roleCode: 'org_admin',
    memberId: 'member-1',
  };

  const parcela = {
    id: 'parcel-1',
    organizationId: 'org-1',
    installationId: 'finca-1',
    name: 'La Vega',
    notes: null,
    geometry: { type: 'MultiPolygon' as const, coordinates: [] },
    areaM2: 9549.5,
    bbox: [-0.5, 39.5, -0.499, 39.501] as [number, number, number, number],
    geometryVersion: 1,
    createdAt: new Date(),
    updatedAt: new Date(),
  };

  const geometriaEntrada = {
    type: 'Polygon',
    coordinates: [
      [
        [-0.5, 39.5],
        [-0.499, 39.5],
        [-0.499, 39.501],
      ],
    ],
  };

  function build(
    params: {
      alcance?: Array<{ installationId: string }>;
      existeFinca?: boolean;
      conSatelite?: boolean;
    } = {},
  ) {
    const tx = {
      installation: {
        findFirst: jest
          .fn()
          .mockResolvedValue(params.existeFinca === false ? null : { id: 'finca-1' }),
      },
      parcel: { update: jest.fn().mockResolvedValue({}) },
      gateway: { updateMany: jest.fn().mockResolvedValue({ count: 2 }) },
      organizationFeature: {
        findFirst: jest
          .fn()
          .mockResolvedValue(
            params.conSatelite === false ? null : { featureCode: 'satellite_imagery' },
          ),
      },
      $executeRaw: jest.fn().mockResolvedValue(1),
    };
    const prisma = {
      runInTenantContext: jest.fn(async (_ctx: unknown, fn: (tx: unknown) => unknown) => fn(tx)),
      memberInstallationScope: {
        findMany: jest.fn().mockResolvedValue(params.alcance ?? []),
      },
    } as unknown as PrismaService;

    const auditLog = {
      record: jest.fn().mockResolvedValue(undefined),
    } as unknown as AuditLogService;
    const repositorio = {
      crear: jest.fn().mockResolvedValue(parcela),
      porId: jest.fn().mockResolvedValue(parcela),
      porInstalacion: jest.fn().mockResolvedValue([parcela]),
      actualizarGeometria: jest.fn().mockResolvedValue({ ...parcela, geometryVersion: 2 }),
    } as unknown as ParcelsRepository;

    // La cola de satélite es un efecto de borde, no parte del alta: se mockea
    // para comprobar que se avisa, y que un fallo suyo no tumba la creación.
    const colaSatelite = {
      encolarHistorico: jest.fn().mockResolvedValue(undefined),
    } as unknown as SatelliteQueueProducer;

    const service = new ParcelsService(
      prisma,
      auditLog,
      new ParcelGeometryService(),
      repositorio,
      colaSatelite,
    );
    return { service, tx, prisma, auditLog, repositorio, colaSatelite };
  }

  it('crea la parcela con la geometría ya normalizada y la audita sin volcar coordenadas', async () => {
    const { service, repositorio, auditLog } = build();

    const creada = await service.create(usuario, 'finca-1', {
      name: 'La Vega',
      geometry: geometriaEntrada,
    });

    expect(creada).toEqual(parcela);
    const argumentos = (repositorio.crear as jest.Mock).mock.calls[0][1];
    expect(argumentos.geometry.type).toBe('MultiPolygon'); // normalizada antes de tocar SQL
    expect(auditLog.record).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({
        action: 'parcels.create',
        targetType: 'parcel',
        metadata: expect.objectContaining({ name: 'La Vega', areaM2: 9550 }),
      }),
    );
    expect(JSON.stringify((auditLog.record as jest.Mock).mock.calls[0][1].metadata)).not.toContain(
      'coordinates',
    );
  });

  it('rechaza crear en una finca fuera del alcance del miembro', async () => {
    const { service } = build({ alcance: [{ installationId: 'otra-finca' }] });

    await expect(
      service.create({ ...usuario, roleCode: 'technician' }, 'finca-1', {
        name: 'La Vega',
        geometry: geometriaEntrada,
      }),
    ).rejects.toThrow(ForbiddenException);
  });

  it('rechaza crear en una finca que no existe en esa organización', async () => {
    const { service } = build({ existeFinca: false });

    await expect(
      service.create(usuario, 'finca-fantasma', { name: 'La Vega', geometry: geometriaEntrada }),
    ).rejects.toThrow(NotFoundException);
  });

  it('traduce el nombre repetido a un 409 con el nombre que choca', async () => {
    const { service, repositorio } = build();
    (repositorio.crear as jest.Mock).mockRejectedValue(
      new Prisma.PrismaClientKnownRequestError('Unique constraint failed', {
        code: 'P2002',
        clientVersion: '5.20.0',
      }),
    );

    await expect(
      service.create(usuario, 'finca-1', { name: 'La Vega', geometry: geometriaEntrada }),
    ).rejects.toThrow(ConflictException);
  });

  it('redibujar el contorno sube la versión de geometría', async () => {
    const { service, repositorio, auditLog } = build();

    const actualizada = await service.update(usuario, 'parcel-1', { geometry: geometriaEntrada });

    expect(repositorio.actualizarGeometria).toHaveBeenCalled();
    expect(actualizada.geometryVersion).toBe(2);
    expect(auditLog.record).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ metadata: expect.objectContaining({ contornoRedibujado: true }) }),
    );
  });

  it('cambiar solo el nombre no toca la geometría', async () => {
    const { service, repositorio } = build();

    await service.update(usuario, 'parcel-1', { name: 'La Vega Norte' });

    expect(repositorio.actualizarGeometria).not.toHaveBeenCalled();
  });

  it('borrar una parcela desasigna sus estaciones en vez de bloquear el borrado', async () => {
    const { service, tx, auditLog } = build();

    await service.softDelete(usuario, 'parcel-1');

    expect(tx.gateway.updateMany).toHaveBeenCalledWith({
      where: { parcelId: 'parcel-1' },
      data: { parcelId: null },
    });
    expect(tx.parcel.update).toHaveBeenCalledWith({
      where: { id: 'parcel-1' },
      data: { deletedAt: expect.any(Date) }, // borrado lógico, como el resto del Directorio
    });
    expect(auditLog.record).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({
        action: 'parcels.delete',
        metadata: expect.objectContaining({ estacionesDesasignadas: 2 }),
      }),
    );
  });

  it('al crear una parcela se encola su historico de satelite', async () => {
    // Sin esto, una parcela recien dibujada no tendria ni un dato hasta el
    // repaso de la manana siguiente.
    const { service, colaSatelite } = build();

    await service.create(usuario, 'finca-1', { name: 'La Vega', geometry: geometriaEntrada });

    expect(colaSatelite.encolarHistorico).toHaveBeenCalledWith({
      organizationId: 'org-1',
      parcelId: 'parcel-1',
    });
  });

  it('sin el satélite contratado no se encola nada: una parcela de Campañas no gasta cuota', async () => {
    const { service, colaSatelite, tx } = build({ conSatelite: false });

    await service.create(usuario, 'finca-1', { name: 'La Vega', geometry: geometriaEntrada });

    expect(tx.organizationFeature.findFirst).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({ featureCode: 'satellite_imagery', enabled: true }),
      }),
    );
    expect(colaSatelite.encolarHistorico).not.toHaveBeenCalled();
  });

  it('una parcela de otra organización no existe para quien pregunta', async () => {
    const { service, repositorio } = build();
    (repositorio.porId as jest.Mock).mockResolvedValue(null);

    await expect(service.findOne(usuario, 'parcel-ajena')).rejects.toThrow(NotFoundException);
  });
});
