import { ConfigService } from '@nestjs/config';
import { SatelliteProcessingService, TrabajoObservacion } from './satellite-processing.service';
import { PrismaService } from '../../../common/prisma/prisma.service';
import { StorageService } from '../../../common/storage/storage.service';
import { ParcelsRepository } from '../../parcels/parcels.repository';
import { SatelliteProvider } from '../providers/satellite-provider.interface';
import { EstadisticasIndice, SatelliteProviderError } from '../providers/satellite.types';

/**
 * El corazón del módulo (BACKLOG.md #36): estadísticas → calidad → ráster →
 * S3 → base de datos. Lo que se fija aquí es el orden y el ahorro: una pasada
 * que no pasa el filtro de calidad **no** debe costar un ráster, y una pasada
 * ya procesada no debe costar nada en absoluto.
 */
describe('SatelliteProcessingService', () => {
  const trabajo: TrabajoObservacion = {
    organizationId: 'org-1',
    parcelId: 'parcela-1',
    provider: 'copernicus',
    collection: 'sentinel-2-l2a',
    acquisitionDate: '2026-09-15',
    acquisitionTime: '2026-09-15T10:42:19.000Z',
    sourceItemIds: ['S2B_T30SYJ_20260915', 'S2B_T30SYH_20260915'],
    platform: 'sentinel-2b',
    sceneCloudCover: 0.05,
  };

  const parcela = {
    id: 'parcela-1',
    organizationId: 'org-1',
    installationId: 'finca-1',
    name: 'La Vega',
    notes: null,
    geometry: { type: 'MultiPolygon' as const, coordinates: [] },
    areaM2: 9549,
    bbox: [-0.5, 39.5, -0.499, 39.501] as [number, number, number, number],
    geometryVersion: 3,
    createdAt: new Date(),
    updatedAt: new Date(),
  };

  const estadisticas: EstadisticasIndice = {
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
    validPixelFraction: 0.92,
  };

  function build(params: {
    yaProcesada?: { status: string } | null;
    stats?: EstadisticasIndice;
    errorEstadisticas?: Error;
    errorRaster?: Error;
    errorSubida?: Error;
    parcelaBorrada?: boolean;
    umbrales?: Record<string, string>;
  }) {
    const tx = {
      satelliteObservation: {
        findFirst: jest.fn().mockResolvedValue(params.yaProcesada ?? null),
        upsert: jest.fn().mockResolvedValue({ id: 'obs-1' }),
        update: jest.fn().mockResolvedValue({}),
      },
      satelliteMetric: { upsert: jest.fn().mockResolvedValue({}) },
      satelliteAsset: { upsert: jest.fn().mockResolvedValue({}) },
    };
    const prisma = {
      runInTenantContext: jest.fn(async (_ctx: unknown, fn: (tx: unknown) => unknown) => fn(tx)),
    } as unknown as PrismaService;

    const config = {
      get: jest.fn((clave: string) => params.umbrales?.[clave]),
    } as unknown as ConfigService;

    const parcels = {
      porId: jest.fn().mockResolvedValue(params.parcelaBorrada ? null : parcela),
    } as unknown as ParcelsRepository;

    const storage = {
      subir: params.errorSubida
        ? jest.fn().mockRejectedValue(params.errorSubida)
        : jest.fn(async ({ clave }: { clave: string }) => ({
            objectKey: clave,
            byteSize: 2048,
            checksum: 'abc',
          })),
    } as unknown as StorageService;

    const provider = {
      code: 'copernicus',
      capabilities: jest.fn(),
      buscarAdquisiciones: jest.fn(),
      estadisticas: params.errorEstadisticas
        ? jest.fn().mockRejectedValue(params.errorEstadisticas)
        : jest.fn().mockResolvedValue(params.stats ?? estadisticas),
      raster: params.errorRaster
        ? jest.fn().mockRejectedValue(params.errorRaster)
        : jest.fn().mockResolvedValue({
            bytes: new Uint8Array([1, 2, 3]),
            mediaType: 'image/tiff',
            width: 10,
            height: 12,
            crs: 'EPSG:4326',
            nodata: Number.NaN,
          }),
    } as unknown as SatelliteProvider;

    const service = new SatelliteProcessingService(prisma, config, parcels, storage, provider);
    return { service, tx, provider, storage, parcels };
  }

  it('procesa: estadísticas, ráster, S3 y la observación queda lista', async () => {
    const { service, tx, provider, storage } = build({});

    await service.procesar(trabajo);

    expect(provider.estadisticas).toHaveBeenCalledTimes(1);
    expect(provider.raster).toHaveBeenCalledTimes(2); // GeoTIFF científico + PNG de pintar
    expect(storage.subir).toHaveBeenCalledTimes(2);
    expect(tx.satelliteMetric.upsert).toHaveBeenCalledWith(
      expect.objectContaining({
        create: expect.objectContaining({ metricCode: 'ndvi', mean: 0.63, median: 0.66 }),
      }),
    );
    expect(tx.satelliteObservation.update).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({ status: 'ready', qualityStatus: 'good' }),
      }),
    );
  });

  it('guarda la versión del contorno sobre el que se calculó', async () => {
    const { service, tx } = build({});

    await service.procesar(trabajo);

    expect(tx.satelliteObservation.upsert).toHaveBeenCalledWith(
      expect.objectContaining({
        create: expect.objectContaining({ parcelGeometryVersion: 3 }),
      }),
    );
  });

  it('una pasada ya procesada no cuesta ni una llamada a Copernicus', async () => {
    const { service, provider, storage } = build({ yaProcesada: { status: 'ready' } });

    await service.procesar(trabajo);

    expect(provider.estadisticas).not.toHaveBeenCalled();
    expect(storage.subir).not.toHaveBeenCalled();
  });

  it('una ya descartada por calidad tampoco se vuelve a intentar cada mañana', async () => {
    const { service, provider } = build({ yaProcesada: { status: 'rejected_quality' } });

    await service.procesar(trabajo);

    expect(provider.estadisticas).not.toHaveBeenCalled();
  });

  it('si la parcela está demasiado tapada, NO se pide el ráster', async () => {
    const { service, tx, provider, storage } = build({
      stats: { ...estadisticas, validPixelFraction: 0.2 },
    });

    await service.procesar(trabajo);

    // Lo caro es la imagen: se ahorra en cuanto se sabe que no sirve.
    expect(provider.raster).not.toHaveBeenCalled();
    expect(storage.subir).not.toHaveBeenCalled();
    expect(tx.satelliteObservation.update).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          status: 'rejected_quality',
          qualityStatus: 'rejected',
          validPixelFraction: 0.2,
        }),
      }),
    );
  });

  it('una observación medio tapada se guarda marcada como parcial', async () => {
    const { service, tx, provider } = build({
      stats: { ...estadisticas, validPixelFraction: 0.6 },
    });

    await service.procesar(trabajo);

    expect(provider.raster).toHaveBeenCalled(); // sirve para ver tendencia
    expect(tx.satelliteObservation.update).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({ status: 'ready', qualityStatus: 'partial' }),
      }),
    );
  });

  it('el listón de calidad se puede mover sin tocar el código', async () => {
    const { service, tx } = build({
      stats: { ...estadisticas, validPixelFraction: 0.6 },
      umbrales: { SATELLITE_MIN_VALID_PIXEL_FRACTION: '0.7' },
    });

    await service.procesar(trabajo);

    expect(tx.satelliteObservation.update).toHaveBeenCalledWith(
      expect.objectContaining({ data: expect.objectContaining({ status: 'rejected_quality' }) }),
    );
  });

  it('un fallo temporal de Copernicus deja la observación pendiente para el reintento', async () => {
    const temporal = new SatelliteProviderError('503', {
      status: 503,
      reintentable: true,
      provider: 'copernicus',
    });
    const { service, tx } = build({ errorEstadisticas: temporal });

    await expect(service.procesar(trabajo)).rejects.toThrow(temporal);
    expect(tx.satelliteObservation.update).toHaveBeenCalledWith(
      expect.objectContaining({ data: expect.objectContaining({ status: 'pending' }) }),
    );
  });

  it('un fallo que no se arregla insistiendo se marca como fallida, con su motivo', async () => {
    const permanente = new SatelliteProviderError('400: petición mal formada', {
      status: 400,
      reintentable: false,
      provider: 'copernicus',
    });
    const { service, tx } = build({ errorEstadisticas: permanente });

    await expect(service.procesar(trabajo)).rejects.toThrow(permanente);
    expect(tx.satelliteObservation.update).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          status: 'failed',
          lastError: expect.stringContaining('petición mal formada'),
        }),
      }),
    );
  });

  it('si S3 falla, la observación no queda como lista: sería una fila sin imagen', async () => {
    const { service, tx } = build({ errorSubida: new Error('S3 no responde') });

    await expect(service.procesar(trabajo)).rejects.toThrow('S3 no responde');

    const estados = tx.satelliteObservation.update.mock.calls.map((c) => c[0].data.status);
    expect(estados).not.toContain('ready');
    expect(tx.satelliteMetric.upsert).not.toHaveBeenCalled();
  });

  it('una parcela borrada mientras el trabajo esperaba en la cola no es un fallo', async () => {
    const { service, provider } = build({ parcelaBorrada: true });

    await expect(service.procesar(trabajo)).resolves.toBeUndefined();
    expect(provider.estadisticas).not.toHaveBeenCalled();
  });

  it('el NaN del GeoTIFF no se guarda como número en la base', async () => {
    const { service, tx } = build({});

    await service.procesar(trabajo);

    const assets = tx.satelliteAsset.upsert.mock.calls.map((c) => c[0].create);
    expect(assets.every((a: { nodata: number | null }) => a.nodata === null)).toBe(true);
  });
});
