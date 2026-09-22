import { ConfigService } from '@nestjs/config';
import { Queue } from 'bullmq';
import { SatelliteSchedulerService } from './satellite-scheduler.service';
import { PrismaService } from '../../../common/prisma/prisma.service';
import { ParcelsRepository } from '../../parcels/parcels.repository';
import { SatelliteProvider } from '../providers/satellite-provider.interface';
import { Adquisicion } from '../providers/satellite.types';

/**
 * Quién decide qué se procesa (BACKLOG.md #36). Lo que se fija aquí es el
 * gasto: solo se mira lo de organizaciones que tienen el módulo contratado, no
 * se vuelve a encolar lo ya procesado, y una parcela que falla no se lleva por
 * delante el repaso de las demás.
 */
describe('SatelliteSchedulerService', () => {
  const AHORA = new Date('2026-09-22T04:30:00Z');

  const parcela = {
    id: 'parcela-1',
    organizationId: 'org-1',
    installationId: 'finca-1',
    name: 'La Vega',
    notes: null,
    geometry: { type: 'MultiPolygon' as const, coordinates: [] },
    areaM2: 9549,
    bbox: [-0.5, 39.5, -0.499, 39.501] as [number, number, number, number],
    geometryVersion: 1,
    createdAt: new Date(),
    updatedAt: new Date(),
  };

  const adquisicion = (dia: string): Adquisicion => ({
    itemIds: [`S2B_${dia}`],
    acquisitionTime: new Date(`${dia}T10:42:19Z`),
    acquisitionDate: dia,
    collection: 'sentinel-2-l2a',
    platform: 'sentinel-2b',
    sceneCloudCover: 0.05,
  });

  function build(params: {
    organizacionesConSatelite?: Array<{ organizationId: string }>;
    parcelas?: Array<{ id: string }>;
    ultimaObservacion?: { acquisitionTime: Date } | null;
    yaProcesadas?: Array<{ acquisitionDate: Date }>;
    adquisiciones?: Adquisicion[];
    errorBusqueda?: Error;
    dias?: string;
  }) {
    const tx = {
      organizationFeature: {
        findMany: jest
          .fn()
          .mockResolvedValue(params.organizacionesConSatelite ?? [{ organizationId: 'org-1' }]),
      },
      parcel: { findMany: jest.fn().mockResolvedValue(params.parcelas ?? [{ id: 'parcela-1' }]) },
      satelliteObservation: {
        findFirst: jest.fn().mockResolvedValue(params.ultimaObservacion ?? null),
        findMany: jest.fn().mockResolvedValue(params.yaProcesadas ?? []),
      },
    };
    const prisma = {
      runInTenantContext: jest.fn(async (_ctx: unknown, fn: (tx: unknown) => unknown) => fn(tx)),
    } as unknown as PrismaService;

    const config = {
      get: jest.fn(() => params.dias),
    } as unknown as ConfigService;

    const parcels = { porId: jest.fn().mockResolvedValue(parcela) } as unknown as ParcelsRepository;

    const provider = {
      code: 'copernicus',
      capabilities: jest.fn(),
      buscarAdquisiciones: params.errorBusqueda
        ? jest.fn().mockRejectedValue(params.errorBusqueda)
        : jest.fn().mockResolvedValue(params.adquisiciones ?? [adquisicion('2026-09-20')]),
      estadisticas: jest.fn(),
      raster: jest.fn(),
    } as unknown as SatelliteProvider;

    const cola = { add: jest.fn().mockResolvedValue({}) } as unknown as Queue;

    return {
      service: new SatelliteSchedulerService(prisma, config, parcels, provider),
      cola,
      provider,
      tx,
    };
  }

  it('encola una observación por pasada nueva, con identificador determinista', async () => {
    const { service, cola } = build({});

    const encolados = await service.repasar(cola, AHORA);

    expect(encolados).toBe(1);
    expect(cola.add).toHaveBeenCalledWith(
      'observacion',
      expect.objectContaining({ parcelId: 'parcela-1', acquisitionDate: '2026-09-20' }),
      expect.objectContaining({ jobId: 'parcela-1__copernicus__sentinel-2-l2a__2026-09-20' }),
    );
  });

  it('no mira nada si ninguna organización tiene el módulo contratado', async () => {
    const { service, cola, provider } = build({ organizacionesConSatelite: [] });

    await expect(service.repasar(cola, AHORA)).resolves.toBe(0);
    expect(provider.buscarAdquisiciones).not.toHaveBeenCalled(); // ni una llamada a Copernicus
    expect(cola.add).not.toHaveBeenCalled();
  });

  it('busca desde la última pasada que ya tiene, con margen', async () => {
    const { service, cola, provider } = build({
      ultimaObservacion: { acquisitionTime: new Date('2026-09-15T10:42:19Z') },
    });

    await service.repasar(cola, AHORA);

    const { desde, hasta } = (provider.buscarAdquisiciones as jest.Mock).mock.calls[0][0];
    // 5 días de margen sobre la última: si una pasada aparece tarde en el
    // catálogo, o si el repaso de ayer no corrió, se recupera igual.
    expect(desde.toISOString()).toBe('2026-09-10T10:42:19.000Z');
    expect(hasta).toBe(AHORA);
  });

  it('una parcela sin ninguna observacion recupera el historico completo en el repaso', async () => {
    // Si el historico del alta no llego a encolarse (paso de verdad el
    // 2026-09-22), el repaso diario es la red de seguridad: no puede mirar
    // solo los ultimos dias.
    const { service, cola, provider } = build({ ultimaObservacion: null });

    await service.repasar(cola, AHORA);

    const { desde } = (provider.buscarAdquisiciones as jest.Mock).mock.calls[0][0];
    expect(Math.round((AHORA.getTime() - desde.getTime()) / 86_400_000)).toBe(90);
  });

  it('no vuelve a encolar una pasada ya procesada', async () => {
    const { service, cola } = build({
      adquisiciones: [adquisicion('2026-09-20'), adquisicion('2026-09-21')],
      yaProcesadas: [{ acquisitionDate: new Date('2026-09-20T00:00:00Z') }],
    });

    const encolados = await service.repasar(cola, AHORA);

    expect(encolados).toBe(1);
    expect(cola.add).toHaveBeenCalledWith(
      'observacion',
      expect.objectContaining({ acquisitionDate: '2026-09-21' }),
      expect.anything(),
    );
  });

  it('una parcela que falla no se lleva por delante el repaso de las demás', async () => {
    const { service, cola } = build({
      parcelas: [{ id: 'parcela-rota' }, { id: 'parcela-1' }],
      errorBusqueda: new Error('Copernicus no responde'),
    });

    // No lanza: registra el fallo de cada una y termina el repaso.
    await expect(service.repasar(cola, AHORA)).resolves.toBe(0);
  });

  it('el histórico mira 90 días atrás por defecto', async () => {
    const { service, cola, provider } = build({});

    await service.historico(cola, { organizationId: 'org-1', parcelId: 'parcela-1' }, AHORA);

    const { desde } = (provider.buscarAdquisiciones as jest.Mock).mock.calls[0][0];
    const dias = Math.round((AHORA.getTime() - desde.getTime()) / 86_400_000);
    expect(dias).toBe(90);
  });

  it('la ventana del histórico es configurable', async () => {
    const { service, cola, provider } = build({ dias: '30' });

    await service.historico(cola, { organizationId: 'org-1', parcelId: 'parcela-1' }, AHORA);

    const { desde } = (provider.buscarAdquisiciones as jest.Mock).mock.calls[0][0];
    expect(Math.round((AHORA.getTime() - desde.getTime()) / 86_400_000)).toBe(30);
  });

  it('descarta de entrada las escenas casi totalmente cubiertas', async () => {
    const { service, cola, provider } = build({});

    await service.repasar(cola, AHORA);

    expect((provider.buscarAdquisiciones as jest.Mock).mock.calls[0][0].maxNubesEscena).toBe(0.9);
  });
});
