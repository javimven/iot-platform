import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { SatelliteProvider } from '../satellite-provider.interface';
import {
  Adquisicion,
  AreaDeInteres,
  BusquedaAdquisiciones,
  EstadisticasIndice,
  EstadisticasParams,
  RasterDescargado,
  RasterParams,
  SatelliteProviderCapabilities,
  SatelliteProviderError,
} from '../satellite.types';
import {
  EVALSCRIPT_NDVI_ESTADISTICAS,
  EVALSCRIPT_NDVI_GEOTIFF,
  EVALSCRIPT_NDVI_PNG,
} from './evalscripts';

/**
 * URLs del proveedor, juntas y no repartidas por el código. Comprobadas
 * contra la documentación oficial el 2026-09-21: las rutas cambiaron en marzo
 * de 2026 (`/api/v1/process` -> `/process/v1`, etc.). Las antiguas todavía
 * funcionan, pero se usan las nuevas porque las viejas se retirarán.
 */
export const CDSE_URLS = {
  token: 'https://identity.dataspace.copernicus.eu/auth/realms/CDSE/protocol/openid-connect/token',
  base: 'https://sh.dataspace.copernicus.eu',
  catalogo: '/catalog/v1/search',
  estadisticas: '/statistics/v1',
  proceso: '/process/v1',
} as const;

const COLECCION = 'sentinel-2-l2a';
const RESOLUCION_NOMINAL_M = 10;

/** Lado máximo del ráster que se pide. Por encima, el proveedor rechaza. */
const MAXIMO_PIXELES_LADO = 2500;

const TIEMPO_LIMITE_MS = 60_000;
const MAXIMO_INTENTOS = 3;
const ESPERA_BASE_MS = 1_000;
/** Ni se espera eternamente a un 429 ni se reintenta contra un muro. */
const MAXIMO_ESPERA_MS = 30_000;
/** Margen para renovar el token antes de que caduque de verdad. */
const MARGEN_TOKEN_MS = 60_000;

interface ItemStac {
  id: string;
  properties: { datetime: string; platform?: string; 'eo:cloud_cover'?: number };
}

interface RespuestaEstadisticas {
  data?: Array<{
    interval: { from: string; to: string };
    outputs?: Record<string, { bands: Record<string, { stats: EstadisticasCrudas }> }>;
  }>;
}

interface EstadisticasCrudas {
  min: number;
  max: number;
  mean: number;
  stDev: number;
  sampleCount: number;
  noDataCount: number;
  percentiles?: Record<string, number>;
}

/**
 * Copernicus Data Space Ecosystem sobre Sentinel-2 L2A (BACKLOG.md #36).
 *
 * Tres llamadas, en este orden: **Catalog** (STAC) para saber qué pasadas hay,
 * **Statistical** para las estadísticas de NDVI sobre el recinto, y
 * **Process** para el ráster. Se pide estadística antes que ráster a
 * propósito: si la observación no pasa el listón de calidad, no se gasta
 * cuota ni disco en una imagen que no se va a usar.
 *
 * Nunca se descarga un producto Sentinel completo: para una parcela de unas
 * hectáreas serían cientos de megas por una pasada.
 */
@Injectable()
export class CopernicusProvider implements SatelliteProvider {
  readonly code = 'copernicus';
  private readonly logger = new Logger(CopernicusProvider.name);

  /**
   * Token en memoria. La documentación de CDSE insiste en reutilizarlo y
   * avisa de que pedir uno por llamada acaba en 429.
   */
  private token?: { valor: string; caducaEn: number };

  constructor(private readonly config: ConfigService) {}

  capabilities(): SatelliteProviderCapabilities {
    return {
      provider: this.code,
      collections: [COLECCION],
      metrics: ['ndvi'],
      bands: ['B04', 'B08', 'SCL'],
      nativeResolutionMeters: RESOLUCION_NOMINAL_M,
      supportsStatistics: true,
      supportsRaster: true,
      // Sentinel pasa cuando pasa: no se puede encargar una toma.
      supportsTasking: false,
      commercial: false,
    };
  }

  /**
   * Pasadas sobre el recinto, agrupadas por día. Un recinto a caballo de dos
   * tiles devuelve varios items STAC de la misma pasada; aquí se juntan en una
   * sola adquisición, que es lo que luego será una observación.
   */
  async buscarAdquisiciones(params: BusquedaAdquisiciones): Promise<Adquisicion[]> {
    const cuerpo = {
      collections: [COLECCION],
      intersects: params.aoi.geometry,
      datetime: `${params.desde.toISOString()}/${params.hasta.toISOString()}`,
      limit: 100,
      fields: {
        include: ['id', 'properties.datetime', 'properties.platform', 'properties.eo:cloud_cover'],
      },
    };

    // El catálogo es STAC y solo sirve GeoJSON: con `Accept: application/json`
    // responde 406 antes incluso de mirar el token. Fue lo primero que falló
    // contra el servicio real (2026-09-22); estadísticas y ráster sí aceptan
    // lo que se les pide (comprobado igual, sin credenciales).
    const respuesta = await this.peticionJson<{ features?: ItemStac[] }>(
      CDSE_URLS.catalogo,
      cuerpo,
      'application/geo+json',
    );
    const items = respuesta.features ?? [];

    const porDia = new Map<string, ItemStac[]>();
    for (const item of items) {
      const nubes = item.properties['eo:cloud_cover'];
      if (
        params.maxNubesEscena !== undefined &&
        nubes !== undefined &&
        nubes / 100 > params.maxNubesEscena
      ) {
        continue;
      }
      const dia = item.properties.datetime.slice(0, 10); // YYYY-MM-DD, ya en UTC
      porDia.set(dia, [...(porDia.get(dia) ?? []), item]);
    }

    return [...porDia.entries()]
      .map(([dia, delDia]) => {
        const ordenados = [...delDia].sort((a, b) =>
          a.properties.datetime.localeCompare(b.properties.datetime),
        );
        const nubes = ordenados
          .map((i) => i.properties['eo:cloud_cover'])
          .filter((n): n is number => typeof n === 'number');
        return {
          itemIds: ordenados.map((i) => i.id),
          acquisitionTime: new Date(ordenados[0].properties.datetime),
          acquisitionDate: dia,
          collection: COLECCION,
          platform: ordenados[0].properties.platform,
          // La media de los tiles que tocan el recinto. Sigue siendo de
          // escena: la nubosidad real sobre la parcela la dice
          // `validPixelFraction` de las estadísticas, no esto.
          sceneCloudCover:
            nubes.length > 0 ? nubes.reduce((a, b) => a + b, 0) / nubes.length / 100 : undefined,
        };
      })
      .sort((a, b) => a.acquisitionTime.getTime() - b.acquisitionTime.getTime());
  }

  async estadisticas(params: EstadisticasParams): Promise<EstadisticasIndice> {
    const { resx, resy } = this.resolucionEnGrados(params.aoi);
    const cuerpo = {
      input: {
        bounds: {
          geometry: params.aoi.geometry,
          properties: { crs: 'http://www.opengis.net/def/crs/OGC/1.3/CRS84' },
        },
        data: [
          {
            type: COLECCION,
            dataFilter: {},
            // SCL es categórica y viene a 20 m: al llevarla a la malla de
            // 10 m hay que repetir el píxel, nunca promediarlo.
            processing: { upsampling: 'NEAREST', downsampling: 'NEAREST' },
          },
        ],
      },
      aggregation: {
        timeRange: this.ventanaDelDia(params.acquisitionDate),
        aggregationInterval: { of: 'P1D' },
        // La ventana ya es un día exacto; esto es por si deja de serlo. Por
        // defecto (`SKIP`) la API tira el último intervalo incompleto, y con
        // un solo intervalo eso es quedarse sin estadísticas.
        lastIntervalBehavior: 'SHORTEN',
        evalscript: EVALSCRIPT_NDVI_ESTADISTICAS,
        resx,
        resy,
      },
      calculations: { ndvi: { statistics: { default: { percentiles: { k: [10, 50, 90] } } } } },
    };

    const respuesta = await this.peticionJson<RespuestaEstadisticas>(
      CDSE_URLS.estadisticas,
      cuerpo,
    );
    const salidas = respuesta.data?.[0]?.outputs;
    const stats = salidas?.ndvi?.bands?.B0?.stats;
    const recinto = salidas?.recinto?.bands?.B0?.stats;
    if (!stats) {
      throw new SatelliteProviderError(
        `Sin estadísticas para ${params.acquisitionDate}: la pasada no cubre el recinto o no hay dato`,
        { reintentable: false, provider: this.code },
      );
    }
    if (!recinto) {
      // Sin ella no se sabe cuántos píxeles tiene la parcela, y la fracción
      // válida saldría contra la caja envolvente (ver el evalscript). Mejor
      // un fallo claro que una calidad inventada.
      throw new SatelliteProviderError(
        `Estadísticas de ${params.acquisitionDate} sin la salida "recinto": no se puede calcular la calidad`,
        { reintentable: false, provider: this.code },
      );
    }

    // Las dos salidas comparten caja: `sampleCount - noDataCount` es, en cada
    // una, lo que su máscara deja pasar. En `recinto`, todos los píxeles de la
    // parcela; en `ndvi`, solo los válidos.
    const pixelesRecinto = Math.max(recinto.sampleCount - recinto.noDataCount, 0);
    const validos = Math.min(Math.max(stats.sampleCount - stats.noDataCount, 0), pixelesRecinto);
    return {
      metricCode: params.metricCode,
      mean: stats.mean,
      median: stats.percentiles?.['50.0'] ?? stats.percentiles?.['50'] ?? stats.mean,
      min: stats.min,
      max: stats.max,
      stdDev: stats.stDev,
      p10: stats.percentiles?.['10.0'] ?? stats.percentiles?.['10'] ?? stats.min,
      p90: stats.percentiles?.['90.0'] ?? stats.percentiles?.['90'] ?? stats.max,
      // Contados sobre la parcela, no sobre la caja: es lo que promete el tipo.
      sampleCount: pixelesRecinto,
      noDataCount: pixelesRecinto - validos,
      validPixelFraction: pixelesRecinto === 0 ? 0 : validos / pixelesRecinto,
    };
  }

  async raster(params: RasterParams): Promise<RasterDescargado> {
    const { width, height } = this.tamanoEnPixeles(params.aoi);
    const esGeotiff = params.formato === 'geotiff';
    const mediaType = esGeotiff ? 'image/tiff' : 'image/png';

    const cuerpo = {
      input: {
        bounds: {
          geometry: params.aoi.geometry,
          properties: { crs: 'http://www.opengis.net/def/crs/OGC/1.3/CRS84' },
        },
        data: [
          {
            type: COLECCION,
            dataFilter: { timeRange: this.ventanaDelDia(params.acquisitionDate) },
            processing: { upsampling: 'NEAREST', downsampling: 'NEAREST' },
          },
        ],
      },
      output: {
        width,
        height,
        responses: [{ identifier: 'default', format: { type: mediaType } }],
      },
      evalscript: esGeotiff ? EVALSCRIPT_NDVI_GEOTIFF : EVALSCRIPT_NDVI_PNG,
    };

    // Dos peticiones separadas (una por formato) en vez de una multiparte: el
    // TAR de la Process API obligaría a traer un parser al backend para
    // ahorrar una llamada que no es el cuello de botella.
    const bytes = await this.peticionBinaria(CDSE_URLS.proceso, cuerpo, mediaType);
    return {
      bytes,
      mediaType,
      width,
      height,
      crs: 'EPSG:4326',
      nodata: esGeotiff ? Number.NaN : null,
    };
  }

  // -------------------------------------------------------------------------
  // Geometría de la petición
  // -------------------------------------------------------------------------

  /**
   * El recinto va en grados (EPSG:4326), así que la resolución también. Un
   * grado de latitud son ~111 320 m en todas partes; uno de longitud, eso
   * mismo por el coseno de la latitud.
   *
   * Es una aproximación, y por eso la resolución se llama **nominal**: lo que
   * no se hace es fingir más detalle del que Sentinel-2 tiene (10 m).
   */
  private resolucionEnGrados(aoi: AreaDeInteres): { resx: number; resy: number } {
    const latitudMedia = (aoi.bbox[1] + aoi.bbox[3]) / 2;
    const metrosPorGradoLat = 111_320;
    const metrosPorGradoLon = Math.max(
      metrosPorGradoLat * Math.cos((latitudMedia * Math.PI) / 180),
      1,
    );
    return {
      resx: RESOLUCION_NOMINAL_M / metrosPorGradoLon,
      resy: RESOLUCION_NOMINAL_M / metrosPorGradoLat,
    };
  }

  /**
   * Tamaño del ráster a 10 m. Si el recinto es tan grande que se pasa del
   * máximo del proveedor, se baja la resolución en vez de trocear: partir en
   * mosaicos es trabajo de verdad y no se hace antes de saber si alguien
   * dibuja parcelas así de grandes.
   */
  private tamanoEnPixeles(aoi: AreaDeInteres): { width: number; height: number } {
    const { resx, resy } = this.resolucionEnGrados(aoi);
    const ancho = Math.ceil((aoi.bbox[2] - aoi.bbox[0]) / resx);
    const alto = Math.ceil((aoi.bbox[3] - aoi.bbox[1]) / resy);
    const mayor = Math.max(ancho, alto, 1);
    const factor = mayor > MAXIMO_PIXELES_LADO ? MAXIMO_PIXELES_LADO / mayor : 1;
    if (factor < 1) {
      this.logger.warn(
        `Recinto demasiado grande para 10 m (${ancho}x${alto}); se pide a ${Math.round(RESOLUCION_NOMINAL_M / factor)} m`,
      );
    }
    return {
      width: Math.max(Math.floor(ancho * factor), 1),
      height: Math.max(Math.floor(alto * factor), 1),
    };
  }

  /**
   * Un día entero en UTC, **exacto**: de las 00:00 a las 00:00 del siguiente.
   * La primera versión acababa a las 23:59:59, un segundo menos que el
   * intervalo `P1D` de las estadísticas, y la API descarta por defecto el
   * intervalo incompleto: ni una estadística. Visto en la documentación antes
   * del primer procesado real (2026-09-22). Las pasadas sobre España son hacia
   * las 10:40 UTC, así que el borde no se toca.
   */
  private ventanaDelDia(acquisitionDate: string): { from: string; to: string } {
    const inicio = new Date(`${acquisitionDate}T00:00:00Z`);
    const fin = new Date(inicio.getTime() + 24 * 60 * 60 * 1000);
    return { from: inicio.toISOString(), to: fin.toISOString() };
  }

  // -------------------------------------------------------------------------
  // HTTP
  // -------------------------------------------------------------------------

  private async peticionJson<T>(
    ruta: string,
    cuerpo: unknown,
    accept = 'application/json',
  ): Promise<T> {
    const respuesta = await this.peticion(ruta, cuerpo, accept);
    return (await respuesta.json()) as T;
  }

  private async peticionBinaria(
    ruta: string,
    cuerpo: unknown,
    mediaType: string,
  ): Promise<Uint8Array> {
    const respuesta = await this.peticion(ruta, cuerpo, mediaType);
    return new Uint8Array(await respuesta.arrayBuffer());
  }

  /**
   * Una llamada con reintentos. Distingue a propósito lo que se puede volver a
   * intentar de lo que no:
   *
   * - **401**: el token ha caducado antes de tiempo. Se renueva y se repite
   *   **una vez**; si vuelve, son credenciales mal puestas y no se insiste.
   * - **429**: se respeta `Retry-After` si viene.
   * - **5xx / red / timeout**: espera exponencial.
   * - **Resto de 4xx**: error de petición. Reintentarlo solo gasta cuota.
   */
  private async peticion(ruta: string, cuerpo: unknown, accept: string): Promise<Response> {
    const url = `${this.baseUrl()}${ruta}`;
    let tokenRenovado = false;

    for (let intento = 1; intento <= MAXIMO_INTENTOS; intento++) {
      // El token se resuelve FUERA del try a propósito: si falla la
      // autenticación, ese error tiene que subir tal cual. Dentro, el catch lo
      // confundiría con una caída de red y lo reintentaría tres veces, que es
      // justo lo que no hay que hacer con unas credenciales mal puestas.
      const token = await this.accessToken();

      let respuesta: Response;
      try {
        respuesta = await fetch(url, {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${token}`,
            'Content-Type': 'application/json',
            Accept: accept,
          },
          body: JSON.stringify(cuerpo),
          signal: AbortSignal.timeout(TIEMPO_LIMITE_MS),
        });
      } catch (error) {
        // Red caída, DNS, timeout: temporal por definición.
        if (intento === MAXIMO_INTENTOS) {
          throw new SatelliteProviderError(`Copernicus no responde (${(error as Error).message})`, {
            reintentable: true,
            provider: this.code,
          });
        }
        await this.esperar(this.esperaExponencial(intento));
        continue;
      }

      if (respuesta.ok) {
        return respuesta;
      }

      if (respuesta.status === 401 && !tokenRenovado) {
        this.logger.warn('Copernicus devolvió 401: se renueva el token y se repite');
        this.token = undefined;
        tokenRenovado = true;
        continue;
      }

      const reintentable = respuesta.status === 429 || respuesta.status >= 500;
      if (!reintentable || intento === MAXIMO_INTENTOS) {
        throw new SatelliteProviderError(
          `Copernicus respondió ${respuesta.status}: ${await this.detalle(respuesta)}`,
          { status: respuesta.status, reintentable, provider: this.code },
        );
      }

      const espera =
        respuesta.status === 429
          ? (this.esperaIndicada(respuesta) ?? this.esperaExponencial(intento))
          : this.esperaExponencial(intento);
      this.logger.warn(`Copernicus ${respuesta.status}; se reintenta en ${espera} ms`);
      await this.esperar(espera);
    }

    // Inalcanzable: el bucle sale por return o por throw.
    throw new SatelliteProviderError('Copernicus: intentos agotados', {
      reintentable: true,
      provider: this.code,
    });
  }

  /** Token de cliente (OAuth2 client_credentials), reutilizado hasta que caduca. */
  private async accessToken(): Promise<string> {
    if (this.token && this.token.caducaEn - MARGEN_TOKEN_MS > Date.now()) {
      return this.token.valor;
    }

    const cuerpo = new URLSearchParams({
      grant_type: 'client_credentials',
      client_id: this.config.getOrThrow<string>('CDSE_CLIENT_ID'),
      client_secret: this.config.getOrThrow<string>('CDSE_CLIENT_SECRET'),
    });

    const respuesta = await fetch(this.config.get<string>('CDSE_TOKEN_URL', CDSE_URLS.token), {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: cuerpo,
      signal: AbortSignal.timeout(TIEMPO_LIMITE_MS),
    });

    if (!respuesta.ok) {
      // Ni el cuerpo ni las credenciales acaban en el log: el detalle de un
      // error de autenticación puede traer de vuelta lo que se envió.
      throw new SatelliteProviderError(
        `No se pudo autenticar contra Copernicus (${respuesta.status})`,
        { status: respuesta.status, reintentable: respuesta.status >= 500, provider: this.code },
      );
    }

    const datos = (await respuesta.json()) as { access_token: string; expires_in: number };
    this.token = {
      valor: datos.access_token,
      caducaEn: Date.now() + datos.expires_in * 1000,
    };
    this.logger.log(`Token de Copernicus renovado (vale ${datos.expires_in} s)`);
    return this.token.valor;
  }

  private baseUrl(): string {
    return this.config.get<string>('CDSE_BASE_URL', CDSE_URLS.base);
  }

  private esperaExponencial(intento: number): number {
    // Con algo de azar para que varios jobs que fallan a la vez no vuelvan
    // todos en el mismo instante.
    const base = Math.min(ESPERA_BASE_MS * 2 ** (intento - 1), MAXIMO_ESPERA_MS);
    return Math.round(base * (0.5 + Math.random()));
  }

  private esperaIndicada(respuesta: Response): number | null {
    const cabecera = respuesta.headers.get('retry-after');
    if (!cabecera) {
      return null;
    }
    const segundos = Number(cabecera);
    if (!Number.isFinite(segundos) || segundos < 0) {
      return null;
    }
    return Math.min(segundos * 1000, MAXIMO_ESPERA_MS);
  }

  /** Un trozo del cuerpo del error, acotado: los mensajes de SH son largos. */
  private async detalle(respuesta: Response): Promise<string> {
    try {
      return (await respuesta.text()).slice(0, 500);
    } catch {
      return respuesta.statusText;
    }
  }

  private esperar(ms: number): Promise<void> {
    return new Promise((resolve) => setTimeout(resolve, ms));
  }
}
