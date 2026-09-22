import { ConfigService } from '@nestjs/config';
import { CopernicusProvider, CDSE_URLS } from './copernicus.provider';
import { SatelliteProviderError } from '../satellite.types';
import { AreaDeInteres } from '../satellite.types';

/**
 * Todo con `fetch` mockeado: no se llama a Copernicus de verdad en una prueba
 * (gastaría cuota y dependería de la red). Lo que se fija aquí es el
 * comportamiento que la documentación oficial pide expresamente —reutilizar el
 * token, respetar `Retry-After`— y la diferencia entre un fallo temporal y uno
 * de configuración, que es lo que decide si un job se reintenta o se descarta.
 */
describe('CopernicusProvider', () => {
  const aoi: AreaDeInteres = {
    geometry: {
      type: 'MultiPolygon',
      coordinates: [
        [
          [
            [-0.5, 39.5],
            [-0.499, 39.5],
            [-0.499, 39.501],
            [-0.5, 39.501],
            [-0.5, 39.5],
          ],
        ],
      ],
    },
    bbox: [-0.5, 39.5, -0.499, 39.501],
  };

  const config = {
    get: jest.fn((clave: string, porDefecto?: string) => porDefecto),
    getOrThrow: jest.fn((clave: string) => (clave === 'CDSE_CLIENT_ID' ? 'id-cliente' : 'secreto')),
  } as unknown as ConfigService;

  let fetchMock: jest.Mock;

  function respuestaToken(expiresIn = 600) {
    return {
      ok: true,
      status: 200,
      json: async () => ({ access_token: `token-${Date.now()}`, expires_in: expiresIn }),
    };
  }

  function respuestaJson(cuerpo: unknown) {
    return { ok: true, status: 200, json: async () => cuerpo };
  }

  function respuestaError(status: number, cabeceras: Record<string, string> = {}) {
    return {
      ok: false,
      status,
      statusText: `error ${status}`,
      headers: { get: (n: string) => cabeceras[n.toLowerCase()] ?? null },
      text: async () => `detalle del ${status}`,
    };
  }

  beforeEach(() => {
    fetchMock = jest.fn();
    global.fetch = fetchMock as unknown as typeof fetch;
    jest.spyOn(global, 'setTimeout').mockImplementation(((fn: () => void) => {
      fn(); // las esperas no cuentan el tiempo de verdad en una prueba
      return 0 as unknown as NodeJS.Timeout;
    }) as never);
  });

  afterEach(() => jest.restoreAllMocks());

  it('declara lo que sabe hacer, con su resolución nominal', () => {
    const capacidades = new CopernicusProvider(config).capabilities();

    expect(capacidades.provider).toBe('copernicus');
    expect(capacidades.collections).toEqual(['sentinel-2-l2a']);
    expect(capacidades.metrics).toEqual(['ndvi']);
    expect(capacidades.nativeResolutionMeters).toBe(10);
    expect(capacidades.supportsTasking).toBe(false); // Sentinel pasa cuando pasa
    expect(capacidades.commercial).toBe(false);
  });

  it('pide el token una vez y lo reutiliza en las llamadas siguientes', async () => {
    fetchMock
      .mockResolvedValueOnce(respuestaToken())
      .mockResolvedValueOnce(respuestaJson({ features: [] }))
      .mockResolvedValueOnce(respuestaJson({ features: [] }));

    const provider = new CopernicusProvider(config);
    await provider.buscarAdquisiciones({ aoi, desde: new Date(), hasta: new Date() });
    await provider.buscarAdquisiciones({ aoi, desde: new Date(), hasta: new Date() });

    const llamadasDeToken = fetchMock.mock.calls.filter(([url]) => url === CDSE_URLS.token);
    expect(llamadasDeToken).toHaveLength(1);
  });

  it('un token a punto de caducar se renueva antes de usarlo', async () => {
    fetchMock
      .mockResolvedValueOnce(respuestaToken(30)) // caduca dentro del margen de seguridad
      .mockResolvedValueOnce(respuestaJson({ features: [] }))
      .mockResolvedValueOnce(respuestaToken(600))
      .mockResolvedValueOnce(respuestaJson({ features: [] }));

    const provider = new CopernicusProvider(config);
    await provider.buscarAdquisiciones({ aoi, desde: new Date(), hasta: new Date() });
    await provider.buscarAdquisiciones({ aoi, desde: new Date(), hasta: new Date() });

    expect(fetchMock.mock.calls.filter(([url]) => url === CDSE_URLS.token)).toHaveLength(2);
  });

  it('ante un 401 renueva el token y repite la llamada una sola vez', async () => {
    fetchMock
      .mockResolvedValueOnce(respuestaToken())
      .mockResolvedValueOnce(respuestaError(401))
      .mockResolvedValueOnce(respuestaToken())
      .mockResolvedValueOnce(respuestaJson({ features: [] }));

    const provider = new CopernicusProvider(config);
    await expect(
      provider.buscarAdquisiciones({ aoi, desde: new Date(), hasta: new Date() }),
    ).resolves.toEqual([]);

    expect(fetchMock.mock.calls.filter(([url]) => url === CDSE_URLS.token)).toHaveLength(2);
  });

  it('un 401 que se repite es configuración, no un fallo temporal: no insiste', async () => {
    fetchMock.mockResolvedValueOnce(respuestaToken()).mockResolvedValue(respuestaError(401));

    const provider = new CopernicusProvider(config);
    await expect(
      provider.buscarAdquisiciones({ aoi, desde: new Date(), hasta: new Date() }),
    ).rejects.toMatchObject({ opciones: { reintentable: false } });
  });

  it('respeta Retry-After en un 429 y termina bien al segundo intento', async () => {
    const esperas: number[] = [];
    (setTimeout as unknown as jest.Mock).mockImplementation(((fn: () => void, ms: number) => {
      esperas.push(ms);
      fn();
      return 0;
    }) as never);

    fetchMock
      .mockResolvedValueOnce(respuestaToken())
      .mockResolvedValueOnce(respuestaError(429, { 'retry-after': '2' }))
      .mockResolvedValueOnce(respuestaJson({ features: [] }));

    const provider = new CopernicusProvider(config);
    await provider.buscarAdquisiciones({ aoi, desde: new Date(), hasta: new Date() });

    expect(esperas).toContain(2000);
  });

  it('reintenta un 500 y se rinde marcándolo como temporal', async () => {
    fetchMock.mockResolvedValueOnce(respuestaToken()).mockResolvedValue(respuestaError(503));

    const provider = new CopernicusProvider(config);
    const error = await provider
      .buscarAdquisiciones({ aoi, desde: new Date(), hasta: new Date() })
      .catch((e: SatelliteProviderError) => e);

    expect((error as SatelliteProviderError).opciones).toMatchObject({
      status: 503,
      reintentable: true,
    });
    // 1 token + 3 intentos
    expect(fetchMock).toHaveBeenCalledTimes(4);
  });

  it('no reintenta un 400: repetir una petición mal formada solo gasta cuota', async () => {
    fetchMock.mockResolvedValueOnce(respuestaToken()).mockResolvedValue(respuestaError(400));

    const provider = new CopernicusProvider(config);
    await expect(
      provider.buscarAdquisiciones({ aoi, desde: new Date(), hasta: new Date() }),
    ).rejects.toMatchObject({ opciones: { status: 400, reintentable: false } });
    expect(fetchMock).toHaveBeenCalledTimes(2); // token + un único intento
  });

  it('agrupa por día los items de una misma pasada que cae en dos tiles', async () => {
    fetchMock.mockResolvedValueOnce(respuestaToken()).mockResolvedValueOnce(
      respuestaJson({
        features: [
          {
            id: 'S2B_T30SYJ_20260915',
            properties: {
              datetime: '2026-09-15T10:42:31Z',
              platform: 'sentinel-2b',
              'eo:cloud_cover': 4,
            },
          },
          {
            id: 'S2B_T30SYH_20260915',
            properties: {
              datetime: '2026-09-15T10:42:19Z',
              platform: 'sentinel-2b',
              'eo:cloud_cover': 6,
            },
          },
          {
            id: 'S2A_T30SYJ_20260920',
            properties: { datetime: '2026-09-20T10:42:10Z', 'eo:cloud_cover': 80 },
          },
        ],
      }),
    );

    const adquisiciones = await new CopernicusProvider(config).buscarAdquisiciones({
      aoi,
      desde: new Date('2026-09-01'),
      hasta: new Date('2026-09-30'),
    });

    expect(adquisiciones).toHaveLength(2);
    const primera = adquisiciones[0];
    expect(primera.acquisitionDate).toBe('2026-09-15');
    expect(primera.itemIds).toHaveLength(2); // los dos tiles, una sola observación
    expect(primera.acquisitionTime.toISOString()).toBe('2026-09-15T10:42:19.000Z'); // la más temprana
    expect(primera.sceneCloudCover).toBeCloseTo(0.05); // media de 4% y 6%, en 0..1
  });

  it('pide al catálogo GeoJSON: con application/json responde 406', async () => {
    // Primer fallo contra el servicio real (2026-09-22). Las pruebas no lo
    // veían porque el `fetch` simulado contesta a cualquier cabecera.
    fetchMock
      .mockResolvedValueOnce(respuestaToken())
      .mockResolvedValueOnce(respuestaJson({ features: [] }))
      .mockResolvedValueOnce(respuestaEstadisticas());
    const proveedor = new CopernicusProvider(config);

    await proveedor.buscarAdquisiciones({ aoi, desde: new Date('2026-09-01'), hasta: new Date() });
    await proveedor.estadisticas({ aoi, acquisitionDate: '2026-09-15', metricCode: 'ndvi' });

    const accept = (llamada: number) => fetchMock.mock.calls[llamada][1].headers.Accept;
    expect(fetchMock.mock.calls[1][0]).toContain(CDSE_URLS.catalogo);
    expect(accept(1)).toBe('application/geo+json');
    // Las estadísticas sí son JSON normal.
    expect(fetchMock.mock.calls[2][0]).toContain(CDSE_URLS.estadisticas);
    expect(accept(2)).toBe('application/json');
  });

  it('descarta escenas más nubladas que el máximo pedido', async () => {
    fetchMock.mockResolvedValueOnce(respuestaToken()).mockResolvedValueOnce(
      respuestaJson({
        features: [
          {
            id: 'despejada',
            properties: { datetime: '2026-09-15T10:42:31Z', 'eo:cloud_cover': 10 },
          },
          {
            id: 'cubierta',
            properties: { datetime: '2026-09-18T10:42:31Z', 'eo:cloud_cover': 95 },
          },
        ],
      }),
    );

    const adquisiciones = await new CopernicusProvider(config).buscarAdquisiciones({
      aoi,
      desde: new Date('2026-09-01'),
      hasta: new Date('2026-09-30'),
      maxNubesEscena: 0.8,
    });

    expect(adquisiciones.map((a) => a.itemIds[0])).toEqual(['despejada']);
  });

  /**
   * Como responde la API: `sampleCount` es la caja envolvente entera y
   * `noDataCount` incluye lo que queda fuera del contorno. Aquí, una caja de
   * 1000 píxeles con 600 dentro de la parcela, de los que 552 son válidos.
   */
  function respuestaEstadisticas(salidas: { recinto?: boolean } = {}) {
    const conRecinto = salidas.recinto ?? true;
    return respuestaJson({
      data: [
        {
          interval: { from: '2026-09-15T00:00:00Z', to: '2026-09-16T00:00:00Z' },
          outputs: {
            ndvi: {
              bands: {
                B0: {
                  stats: {
                    min: 0.12,
                    max: 0.84,
                    mean: 0.63,
                    stDev: 0.09,
                    sampleCount: 1000,
                    noDataCount: 448,
                    percentiles: { '10.0': 0.4, '50.0': 0.66, '90.0': 0.8 },
                  },
                },
              },
            },
            ...(conRecinto
              ? { recinto: { bands: { B0: { stats: { sampleCount: 1000, noDataCount: 400 } } } } }
              : {}),
          },
        },
      ],
    });
  }

  it('traduce las estadísticas y calcula la fracción válida sobre la parcela, no sobre la caja', async () => {
    fetchMock
      .mockResolvedValueOnce(respuestaToken())
      .mockResolvedValueOnce(respuestaEstadisticas());

    const stats = await new CopernicusProvider(config).estadisticas({
      aoi,
      acquisitionDate: '2026-09-15',
      metricCode: 'ndvi',
    });

    expect(stats.median).toBe(0.66); // la mediana sale del percentil 50
    expect(stats.p10).toBe(0.4);
    // 552 de 600, no 552 de 1000: una parcela que no es un rectángulo no
    // puede salir "nublada" por su forma.
    expect(stats.validPixelFraction).toBeCloseTo(0.92);
    expect(stats.sampleCount).toBe(600);
    expect(stats.noDataCount).toBe(48);
    expect(stats.metricCode).toBe('ndvi');
  });

  it('pide el día exacto y la máscara por salida: sin eso, ni una estadística o una calidad falsa', async () => {
    fetchMock
      .mockResolvedValueOnce(respuestaToken())
      .mockResolvedValueOnce(respuestaEstadisticas());

    await new CopernicusProvider(config).estadisticas({
      aoi,
      acquisitionDate: '2026-09-15',
      metricCode: 'ndvi',
    });

    const cuerpo = JSON.parse(fetchMock.mock.calls[1][1].body);
    // Exactamente P1D: con 23:59:59 la API tiraba el único intervalo.
    expect(cuerpo.aggregation.timeRange).toEqual({
      from: '2026-09-15T00:00:00.000Z',
      to: '2026-09-16T00:00:00.000Z',
    });
    expect(cuerpo.aggregation.lastIntervalBehavior).toBe('SHORTEN');
    expect(cuerpo.aggregation.evalscript).toContain(
      '{ id: "dataMask", bands: ["ndvi", "recinto"] }',
    );
    // El recinto lleva el dataMask de entrada, que es lo que marca el
    // contorno. Con un 1 fijo se contaba la caja entera (ndvi-s2-v1: 67 %
    // válido todos los días en la primera parcela real).
    expect(cuerpo.aggregation.evalscript).toContain(
      'dataMask: [esValido(muestra), muestra.dataMask]',
    );
  });

  it('sin la salida del recinto no se inventa una calidad', async () => {
    fetchMock
      .mockResolvedValueOnce(respuestaToken())
      .mockResolvedValueOnce(respuestaEstadisticas({ recinto: false }));

    await expect(
      new CopernicusProvider(config).estadisticas({
        aoi,
        acquisitionDate: '2026-09-15',
        metricCode: 'ndvi',
      }),
    ).rejects.toMatchObject({ opciones: { reintentable: false } });
  });

  it('una pasada sin estadísticas no es un fallo temporal: no se reintenta', async () => {
    fetchMock
      .mockResolvedValueOnce(respuestaToken())
      .mockResolvedValueOnce(respuestaJson({ data: [] }));

    await expect(
      new CopernicusProvider(config).estadisticas({
        aoi,
        acquisitionDate: '2026-09-15',
        metricCode: 'ndvi',
      }),
    ).rejects.toMatchObject({ opciones: { reintentable: false } });
  });

  it('el ráster pide el tamaño que toca a 10 m y devuelve los bytes', async () => {
    const bytes = new Uint8Array([1, 2, 3, 4]);
    fetchMock.mockResolvedValueOnce(respuestaToken()).mockResolvedValueOnce({
      ok: true,
      status: 200,
      arrayBuffer: async () => bytes.buffer,
    });

    const raster = await new CopernicusProvider(config).raster({
      aoi,
      acquisitionDate: '2026-09-15',
      metricCode: 'ndvi',
      formato: 'geotiff',
    });

    expect(raster.mediaType).toBe('image/tiff');
    expect(raster.crs).toBe('EPSG:4326');
    expect(Number.isNaN(raster.nodata)).toBe(true); // FLOAT32: el hueco es NaN
    // El recinto mide ~86 x 111 m, así que a 10 m son unos 9 x 11 píxeles.
    expect(raster.width).toBeGreaterThan(5);
    expect(raster.width).toBeLessThan(15);
    expect(raster.height).toBeGreaterThan(8);
    expect(raster.height).toBeLessThan(15);

    const cuerpo = JSON.parse(fetchMock.mock.calls[1][1].body);
    expect(cuerpo.output.responses[0].format.type).toBe('image/tiff');
    expect(cuerpo.input.data[0].processing.upsampling).toBe('NEAREST'); // SCL es categórica
  });

  it('un recinto enorme baja de resolución en vez de pedir un ráster imposible', async () => {
    const enorme: AreaDeInteres = { ...aoi, bbox: [-5, 36, 3, 44] }; // media España
    fetchMock.mockResolvedValueOnce(respuestaToken()).mockResolvedValueOnce({
      ok: true,
      status: 200,
      arrayBuffer: async () => new Uint8Array([1]).buffer,
    });

    const raster = await new CopernicusProvider(config).raster({
      aoi: enorme,
      acquisitionDate: '2026-09-15',
      metricCode: 'ndvi',
      formato: 'png',
    });

    expect(Math.max(raster.width, raster.height)).toBeLessThanOrEqual(2500);
  });
});
