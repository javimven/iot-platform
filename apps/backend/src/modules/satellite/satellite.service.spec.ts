import { ForbiddenException, HttpException, NotFoundException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PROCESSING_VERSION } from './providers/copernicus/evalscripts';
import { SatelliteService } from './satellite.service';
import { PrismaService } from '../../common/prisma/prisma.service';
import { StorageService } from '../../common/storage/storage.service';
import { SatelliteQueueProducer } from '../../common/queues/satellite-queue.producer';
import { ParcelsService } from '../parcels/parcels.service';
import { AccessTokenClaims } from '../../common/guards/jwt-auth.guard';

/**
 * La cara de lectura del módulo (BACKLOG.md #36). Lo que se fija aquí: quién
 * puede ver una parcela se resuelve en un solo sitio, una observación
 * descartada por nubes no dibuja un punto en la gráfica, y el refresco manual
 * no se puede usar para vaciar la cuota de Copernicus a base de clics.
 */
describe('SatelliteService', () => {
  const usuario: AccessTokenClaims = {
    sub: 'user-1',
    type: 'access',
    organizationId: 'org-1',
    roleCode: 'org_admin',
    memberId: 'member-1',
  };

  const observacion = {
    id: 'obs-1',
    acquisitionTime: new Date('2026-09-15T10:42:19Z'),
    provider: 'copernicus',
    collection: 'sentinel-2-l2a',
    platform: 'sentinel-2b',
    processingVersion: 'ndvi-s2-v1',
    parcelGeometryVersion: 1,
    status: 'ready',
    qualityStatus: 'good',
    validPixelFraction: 0.9234872,
    sceneCloudCover: 0.05,
    metrics: [
      {
        metricCode: 'ndvi',
        mean: 0.63,
        median: 0.66,
        min: 0.12,
        max: 0.84,
        stdDev: 0.09,
        p10: 0.4,
        p90: 0.8,
      },
    ],
    assets: [
      {
        id: 'asset-1',
        assetType: 'ndvi_raster',
        mediaType: 'image/tiff',
        width: 10,
        height: 12,
        byteSize: 2048,
      },
    ],
  };

  function build(
    params: {
      parcelaProhibida?: boolean;
      observaciones?: unknown[];
      primera?: unknown;
      asset?: unknown;
      refrescoAdmitido?: boolean;
    } = {},
  ) {
    const tx = {
      satelliteObservation: {
        // `in` y no `??`: `primera: null` es justo el caso que se quiere probar.
        findFirst: jest.fn().mockResolvedValue('primera' in params ? params.primera : observacion),
        findMany: jest.fn().mockResolvedValue(params.observaciones ?? [observacion]),
      },
      satelliteAsset: { findFirst: jest.fn().mockResolvedValue(params.asset ?? null) },
    };
    const prisma = {
      runInTenantContext: jest.fn(async (_ctx: unknown, fn: (tx: unknown) => unknown) => fn(tx)),
    } as unknown as PrismaService;

    const parcels = {
      findOne: params.parcelaProhibida
        ? jest.fn().mockRejectedValue(new ForbiddenException('fuera de alcance'))
        : jest.fn().mockResolvedValue({ id: 'parcela-1' }),
    } as unknown as ParcelsService;

    const storage = {
      urlFirmada: jest.fn().mockResolvedValue({
        url: 'https://bucket/ndvi.tif?X-Amz-Signature=xxx',
        expiresAt: new Date('2026-09-22T10:15:00Z'),
      }),
    } as unknown as StorageService;

    const cola = {
      encolarRefresco: jest.fn().mockResolvedValue(params.refrescoAdmitido ?? true),
    } as unknown as SatelliteQueueProducer;

    // Sin SATELLITE_BACKFILL_DAYS: vale el de por defecto, 90.
    const config = { get: jest.fn().mockReturnValue(undefined) } as unknown as ConfigService;

    return {
      service: new SatelliteService(prisma, parcels, storage, cola, config),
      tx,
      parcels,
      storage,
      cola,
    };
  }

  it('devuelve la última observación con su calidad en porcentaje entero', async () => {
    const { service } = build();

    const ultima = await service.ultima(usuario, 'parcela-1');

    expect(ultima?.observationId).toBe('obs-1');
    expect(ultima?.metrics.ndvi.mean).toBe(0.63);
    // 92, no 92,348729: el número sirve para saber si fiarse, no para presumir.
    expect(ultima?.quality.validPixelPercent).toBe(92);
  });

  it('la última observación trae sus archivos: de ahí saca la app la imagen del mapa', async () => {
    // La simulación devuelve los archivos se pidan o no, así que se comprueba
    // la consulta. Sin `assets`, en la primera parcela real salían las cifras
    // pero no la imagen (2026-09-22).
    const { service, tx } = build();

    const ultima = await service.ultima(usuario, 'parcela-1');

    expect(tx.satelliteObservation.findFirst).toHaveBeenCalledWith(
      expect.objectContaining({
        // Y solo de la versión vigente: al reprocesar conviven varias.
        where: expect.objectContaining({ processingVersion: PROCESSING_VERSION }),
        include: { metrics: true, assets: true },
      }),
    );
    expect(ultima?.assets?.map((a) => a.assetId)).toEqual(['asset-1']);
  });

  it('una parcela sin observaciones todavía devuelve null, no un error', async () => {
    const { service } = build({ primera: null });

    await expect(service.ultima(usuario, 'parcela-1')).resolves.toBeNull();
  });

  it('el permiso sobre la parcela se comprueba en todas las rutas, no solo en una', async () => {
    const { service } = build({ parcelaProhibida: true });

    await expect(service.ultima(usuario, 'ajena')).rejects.toThrow(ForbiddenException);
    await expect(service.serie(usuario, 'ajena', {})).rejects.toThrow(ForbiddenException);
    await expect(service.observaciones(usuario, 'ajena', {})).rejects.toThrow(ForbiddenException);
    await expect(service.observacion(usuario, 'ajena', 'obs-1')).rejects.toThrow(
      ForbiddenException,
    );
    await expect(service.refrescar(usuario, 'ajena')).rejects.toThrow(ForbiddenException);
  });

  it('la serie va en orden ascendente y solo con observaciones utilizables', async () => {
    const { service, tx } = build();

    const serie = await service.serie(usuario, 'parcela-1', {});

    expect(tx.satelliteObservation.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({ status: 'ready' }), // las descartadas no pintan punto
        orderBy: { acquisitionTime: 'asc' },
      }),
    );
    // Mismo nombre de campo que el histórico de telemetría: la app reutiliza
    // sus gráficas sin traducir nada.
    expect(serie[0]).toEqual(
      expect.objectContaining({ tsOrigin: observacion.acquisitionTime, value: 0.63 }),
    );
    expect(serie[0].qualityStatus).toBe('good');
  });

  it('una observación sin métrica no ensucia la serie', async () => {
    const { service } = build({ observaciones: [{ ...observacion, metrics: [] }] });

    await expect(service.serie(usuario, 'parcela-1', {})).resolves.toEqual([]);
  });

  it('el histórico puede incluir las descartadas: explican los huecos', async () => {
    const { service, tx } = build();

    await service.observaciones(usuario, 'parcela-1', { incluirDescartadas: true });

    expect(tx.satelliteObservation.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({ status: { in: ['ready', 'rejected_quality'] } }),
      }),
    );
  });

  it('filtra por ventana de fechas cuando se pide', async () => {
    const { service, tx } = build();
    const from = new Date('2026-06-01');
    const to = new Date('2026-09-01');

    await service.serie(usuario, 'parcela-1', { from, to });

    expect(tx.satelliteObservation.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({ acquisitionTime: { gte: from, lte: to } }),
      }),
    );
  });

  it('el enlace de descarga va firmado y con caducidad, nunca la clave del bucket', async () => {
    const { service } = build({
      asset: {
        id: 'asset-1',
        assetType: 'ndvi_raster',
        mediaType: 'image/tiff',
        objectKey: 'satellite/org-1/parcela-1/ndvi.tif',
      },
    });

    const enlace = await service.urlDeAsset(usuario, 'parcela-1', 'obs-1', 'asset-1');

    expect(enlace.url).toContain('X-Amz-Signature');
    expect(enlace.expiresAt).toBeInstanceOf(Date);
    expect(JSON.stringify(enlace)).not.toContain('S3_SECRET');
  });

  it('un asset de otra observación no se firma', async () => {
    const { service } = build({ asset: null });

    await expect(
      service.urlDeAsset(usuario, 'parcela-1', 'obs-1', 'asset-de-otra'),
    ).rejects.toThrow(NotFoundException);
  });

  it('el refresco manual encola una ventana corta', async () => {
    const { service, cola } = build();

    const resultado = await service.refrescar(usuario, 'parcela-1');

    expect(resultado).toEqual({ estado: 'encolado', dias: 15 });
    expect(cola.encolarRefresco).toHaveBeenCalledWith({
      organizationId: 'org-1',
      parcelId: 'parcela-1',
      dias: 15,
    });
  });

  it('en una parcela sin ninguna observación, actualizar pide el histórico entero', async () => {
    // Con solo 15 días, el repaso diario seguiría desde ahí y los 75
    // anteriores no llegarían nunca.
    const { service, cola } = build({ primera: null });

    const resultado = await service.refrescar(usuario, 'parcela-1');

    expect(resultado).toEqual({ estado: 'encolado', dias: 90 });
    expect(cola.encolarRefresco).toHaveBeenCalledWith({
      organizationId: 'org-1',
      parcelId: 'parcela-1',
      dias: 90,
    });
  });

  it('pulsar el botón dos veces en la misma hora devuelve 429, no otra tanda de peticiones', async () => {
    const { service } = build({ refrescoAdmitido: false });

    const error = await service.refrescar(usuario, 'parcela-1').catch((e: HttpException) => e);

    expect((error as HttpException).getStatus()).toBe(429);
  });
});
