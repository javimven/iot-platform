import {
  Adquisicion,
  BusquedaAdquisiciones,
  EstadisticasIndice,
  EstadisticasParams,
  RasterDescargado,
  RasterParams,
  SatelliteProviderCapabilities,
} from './satellite.types';

/**
 * Contrato de un proveedor de imágenes de satélite. Hoy solo lo implementa
 * `CopernicusProvider` (Sentinel-2 L2A), pero el dominio está escrito para que
 * entren Planet, Airbus o Maxar sin tocar `Parcel`, `SatelliteObservation`,
 * `SatelliteMetric`, `SatelliteAsset` ni el frontend (BACKLOG.md #36).
 *
 * No hay clases vacías de esos proveedores: cuando llegue uno, se implementa
 * esta interfaz y se cambia qué instancia resuelve el token de inyección.
 */
export interface SatelliteProvider {
  /** Lo que se guarda en `satellite_observations.provider`. */
  readonly code: string;

  capabilities(): SatelliteProviderCapabilities;

  /** Pasadas disponibles sobre el recinto en una ventana de tiempo. */
  buscarAdquisiciones(params: BusquedaAdquisiciones): Promise<Adquisicion[]>;

  /**
   * Estadísticas del índice sobre el recinto, calculadas por el proveedor.
   * Se piden así, y no descargando el ráster para promediarlo aquí, porque es
   * mucho más barato en cuota y en memoria.
   */
  estadisticas(params: EstadisticasParams): Promise<EstadisticasIndice>;

  /** El ráster del índice recortado al recinto. */
  raster(params: RasterParams): Promise<RasterDescargado>;
}

/**
 * Token de inyección de Nest. Se resuelve con `useFactory` + `ConfigService`,
 * igual que `JwtModule.registerAsync` en `api.module.ts`: el día que haya dos
 * proveedores, se elige aquí y nadie más se entera.
 */
export const SATELLITE_PROVIDER = Symbol('SATELLITE_PROVIDER');
