import { GeoJsonMultiPolygon } from '../../parcels/parcel-geometry.service';

/**
 * Lo que un proveedor de imágenes sabe hacer. Se declara en vez de darse por
 * supuesto para que añadir Planet o Airbus más adelante no obligue a tocar la
 * lógica general: el pipeline pregunta antes de pedir algo que ese proveedor
 * no ofrece (BACKLOG.md #36).
 */
export interface SatelliteProviderCapabilities {
  provider: string;
  collections: string[];
  metrics: string[];
  bands: string[];
  /** Resolución nominal del dato, en metros. No se promete más detalle que este. */
  nativeResolutionMeters: number;
  supportsStatistics: boolean;
  supportsRaster: boolean;
  /** Programar una toma nueva (los comerciales sí; Sentinel no: pasa cuando pasa). */
  supportsTasking: boolean;
  commercial: boolean;
}

/** El recinto sobre el que se pide todo, siempre en EPSG:4326 (ADR-0009). */
export interface AreaDeInteres {
  geometry: GeoJsonMultiPolygon;
  /** [minLon, minLat, maxLon, maxLat] */
  bbox: [number, number, number, number];
}

export interface BusquedaAdquisiciones {
  aoi: AreaDeInteres;
  desde: Date;
  hasta: Date;
  /** Descarta escenas con más nubes que esto (0..1) antes de mirarlas de cerca. */
  maxNubesEscena?: number;
}

/**
 * Una pasada del satélite sobre la parcela, ya agrupada.
 *
 * `itemIds` es una lista y no un identificador suelto a propósito: una parcela
 * a caballo de dos tiles produce varios items de la **misma** pasada, y para
 * nosotros es una sola observación (BACKLOG.md #36). Por eso la clave lógica
 * es `acquisitionDate`, no el nombre de un tile.
 */
export interface Adquisicion {
  itemIds: string[];
  /** La más temprana de la pasada, en UTC. */
  acquisitionTime: Date;
  /** `YYYY-MM-DD` en UTC: la clave lógica de una observación. */
  acquisitionDate: string;
  collection: string;
  /** `sentinel-2a`, `sentinel-2b`… si el proveedor lo dice. */
  platform?: string;
  /** Nubes de la escena entera (0..1). **No** es la nubosidad sobre la parcela. */
  sceneCloudCover?: number;
}

export interface EstadisticasParams {
  aoi: AreaDeInteres;
  /** `YYYY-MM-DD` en UTC. */
  acquisitionDate: string;
  metricCode: 'ndvi';
}

/**
 * Estadísticas del índice **sobre los píxeles válidos** de la parcela: los
 * nublados, sombreados o de agua no entran (ver `evalscripts.ts`).
 */
export interface EstadisticasIndice {
  metricCode: string;
  mean: number;
  median: number;
  min: number;
  max: number;
  stdDev: number;
  p10: number;
  p90: number;
  /** Píxeles del recinto considerados. */
  sampleCount: number;
  /** De esos, los descartados por la máscara de calidad. */
  noDataCount: number;
  /** 0..1. Es el número que decide si la observación sirve. */
  validPixelFraction: number;
}

export interface RasterParams {
  aoi: AreaDeInteres;
  acquisitionDate: string;
  metricCode: 'ndvi';
  /** `geotiff`: el dato científico FLOAT32. `png`: solo para pintar el mapa. */
  formato: 'geotiff' | 'png';
}

export interface RasterDescargado {
  bytes: Uint8Array;
  mediaType: string;
  width: number;
  height: number;
  /** Sistema de referencia del ráster devuelto. */
  crs: string;
  /** Valor que marca "sin dato" en el GeoTIFF (NaN en FLOAT32). */
  nodata: number | null;
}

/** Error de un proveedor que distingue lo que se puede reintentar de lo que no. */
export class SatelliteProviderError extends Error {
  constructor(
    message: string,
    readonly opciones: { status?: number; reintentable: boolean; provider: string },
  ) {
    super(message);
    this.name = 'SatelliteProviderError';
  }
}
