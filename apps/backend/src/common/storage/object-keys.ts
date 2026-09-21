/**
 * Claves de los objetos del módulo de satélite. Deterministas a propósito:
 * con los mismos datos de entrada sale la misma ruta, así que reprocesar
 * sobreescribe en su sitio en vez de dejar basura suelta.
 *
 * Forma:
 *
 *   satellite/{organizationId}/{parcelId}/{provider}/{collection}/{YYYY}/{MM}/
 *     {observationId}/{processingVersion}/{fichero}
 *
 * Por qué así:
 *
 * - **La organización primero**: deja aplicar una política de ciclo de vida o
 *   borrar todo lo de un cliente con un prefijo, sin recorrer el bucket.
 * - **El proveedor y la colección en la ruta**: cuando entre Planet al lado de
 *   Copernicus, sus objetos no se mezclan con los de Sentinel-2 (BACKLOG.md
 *   #36) y se pueden separar por coste.
 * - **Año y mes**: hace navegable el bucket a mano y agrupa lo que se querrá
 *   caducar junto.
 * - **`processingVersion` al final, no en el nombre del fichero**: al cambiar
 *   el evalscript o la máscara de nubes, lo nuevo convive con lo viejo en vez
 *   de pisarlo, que es lo que permite comparar dos procesados de la misma
 *   pasada antes de tirar el anterior.
 */

export type TipoArchivoSatelite = 'ndvi_raster' | 'ndvi_preview';

const NOMBRES: Record<TipoArchivoSatelite, string> = {
  // GeoTIFF FLOAT32: el dato científico, del que salen las estadísticas y
  // cualquier recálculo futuro.
  ndvi_raster: 'ndvi.tif',
  // PNG coloreado para pintarlo sobre el mapa. Nunca es la fuente de verdad.
  ndvi_preview: 'ndvi.png',
};

export const MEDIA_TYPES: Record<TipoArchivoSatelite, string> = {
  ndvi_raster: 'image/tiff',
  ndvi_preview: 'image/png',
};

export interface ClaveSatelite {
  organizationId: string;
  parcelId: string;
  provider: string;
  collection: string;
  acquisitionTime: Date;
  observationId: string;
  processingVersion: string;
  tipo: TipoArchivoSatelite;
}

export function claveObjetoSatelite(datos: ClaveSatelite): string {
  const anio = datos.acquisitionTime.getUTCFullYear();
  const mes = String(datos.acquisitionTime.getUTCMonth() + 1).padStart(2, '0');
  return [
    'satellite',
    datos.organizationId,
    datos.parcelId,
    datos.provider,
    datos.collection,
    String(anio),
    mes,
    datos.observationId,
    datos.processingVersion,
    NOMBRES[datos.tipo],
  ].join('/');
}

/** Prefijo de todo lo de una parcela: para borrarlo entero cuando se borre. */
export function prefijoParcela(organizationId: string, parcelId: string): string {
  return `satellite/${organizationId}/${parcelId}/`;
}
