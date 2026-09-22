/**
 * Evalscripts de Sentinel-2 L2A para NDVI (BACKLOG.md #36).
 *
 * NDVI = (B08 - B04) / (B08 + B04), ambas bandas a 10 m, así que la v1 no
 * tiene que resolver mezcla de resoluciones espectrales. La que sí viene a
 * 20 m es `SCL`, la clasificación de escena, y por eso se pide
 * `upsampling: NEAREST` en la petición: SCL son **categorías**, y
 * interpolarlas con bilinear inventaría clases que no existen.
 *
 * ## Qué se considera un píxel válido
 *
 * Filtrar nubes no es opcional aunque el índice sea solo uno: sin máscara, un
 * día cubierto da un NDVI bajo que parece un cultivo en apuros. Clases de SCL
 * (Sentinel-2 L2A, valores 0-11):
 *
 * | Valor | Clase                        | v1        | Por qué |
 * |-------|------------------------------|-----------|---------|
 * | 0     | sin dato                     | excluido  | no hay medida |
 * | 1     | saturado / defectuoso        | excluido  | medida inválida |
 * | 2     | sombra proyectada (oscuro)   | excluido  | oscurece el NDVI sin que el cultivo cambie |
 * | 3     | sombra de nube               | excluido  | ídem |
 * | 4     | vegetación                   | VÁLIDO    | es lo que se quiere medir |
 * | 5     | suelo sin vegetación         | VÁLIDO    | un NDVI bajo real es información, no un error |
 * | 6     | agua                         | excluido  | una balsa o un encharcamiento hunde la media |
 * | 7     | sin clasificar               | excluido  | criterio conservador: no se sabe qué hay |
 * | 8     | nube, probabilidad media     | excluido  | |
 * | 9     | nube, probabilidad alta      | excluido  | |
 * | 10    | cirros                       | excluido  | velan el dato sin taparlo del todo |
 * | 11    | nieve / hielo                | excluido  | |
 *
 * Dejar fuera el 7 (sin clasificar) y el 2 (zona oscura) es una decisión
 * discutible: rechaza algún píxel bueno a cambio de no colar ninguno malo.
 * Si algún día se revisa, **hay que subir `processingVersion`**: lo calculado
 * antes deja de ser comparable con lo nuevo.
 */

/** Clases de SCL que entran en las estadísticas. */
export const CLASES_SCL_VALIDAS = [4, 5] as const;

/** Clases de SCL que cuentan como nube (para informar, no para medir). */
export const CLASES_SCL_NUBE = [3, 8, 9, 10] as const;

/**
 * Versión del procesado. Cambia si cambia el evalscript, la máscara, la
 * resolución o la fórmula: es lo que permite reprocesar el histórico y
 * distinguir lo viejo de lo nuevo sin pisarlo (BACKLOG.md #36).
 *
 * - `ndvi-s2-v1`: primera versión. La fracción válida se contaba sobre la caja
 *   envolvente, no sobre la parcela; el NDVI sí era correcto.
 * - `ndvi-s2-v2` (2026-09-22): fracción válida sobre los píxeles de la parcela.
 */
export const PROCESSING_VERSION = 'ndvi-s2-v2';

const MASCARA = `
  // Válido = clase de suelo o vegetación Y con dato (dataMask de entrada, que
  // vale 0 fuera de la escena y fuera del contorno de la parcela).
  function esValido(muestra) {
    var c = muestra.SCL;
    return muestra.dataMask === 1 && (c === 4 || c === 5) ? 1 : 0;
  }
`;

/**
 * Para la Statistical API. Dos salidas, **cada una con su propia máscara**
 * (el `dataMask` con una banda por salida, como en la documentación oficial):
 *
 * - `ndvi`: el índice, contando solo los píxeles válidos (`esValido`).
 * - `recinto`: un 1 en cada píxel, con el `dataMask` de entrada **tal cual**.
 *   Sirve para saber cuántos píxeles tiene la parcela: la API marca el
 *   contorno poniendo a 0 ese `dataMask` fuera de él, así que hay que
 *   pasarlo. Con un 1 fijo (primera versión, `ndvi-s2-v1`) se contaba la caja
 *   entera como si fuera la parcela: en la primera parcela real salía un 67 %
 *   válido todos los días despejados, que era justo su parte de la caja.
 *   Efecto conocido: si una pasada cubre solo parte de la parcela (borde de la
 *   franja del satélite), la fracción se calcula sobre la parte cubierta.
 *
 * Hace falta la segunda porque la API cuenta en `sampleCount` los píxeles de
 * la **caja** que envuelve el recinto, y mete en `noDataCount` los que quedan
 * fuera del contorno. Con una sola salida, una parcela triangular no pasaría
 * nunca del 50 % "válido" aunque el día estuviera despejado.
 */
export const EVALSCRIPT_NDVI_ESTADISTICAS = `//VERSION=3
function setup() {
  return {
    input: [{ bands: ["B04", "B08", "SCL", "dataMask"] }],
    output: [
      { id: "ndvi", bands: 1, sampleType: "FLOAT32" },
      { id: "recinto", bands: 1, sampleType: "UINT8" },
      { id: "dataMask", bands: ["ndvi", "recinto"] }
    ]
  };
}
${MASCARA}
function evaluatePixel(muestra) {
  var ndvi = (muestra.B08 - muestra.B04) / (muestra.B08 + muestra.B04);
  return { ndvi: [ndvi], recinto: [1], dataMask: [esValido(muestra), muestra.dataMask] };
}
`;

/**
 * Para la Process API, salida científica: un GeoTIFF FLOAT32 con el NDVI y
 * `NaN` donde el píxel no es válido. Se guarda esto, y no solo el PNG
 * coloreado, para poder recalcular o reprocesar más adelante.
 */
export const EVALSCRIPT_NDVI_GEOTIFF = `//VERSION=3
function setup() {
  return {
    input: [{ bands: ["B04", "B08", "SCL", "dataMask"] }],
    output: { bands: 1, sampleType: "FLOAT32" }
  };
}
${MASCARA}
function evaluatePixel(muestra) {
  if (esValido(muestra) === 0) {
    return [NaN];
  }
  return [(muestra.B08 - muestra.B04) / (muestra.B08 + muestra.B04)];
}
`;

/**
 * Para la Process API, salida de visualización: PNG con transparencia donde
 * no hay dato válido. **Nunca es la fuente de verdad**: las estadísticas
 * salen del FLOAT32, no de estos colores.
 *
 * La escala va de 0 a 0,8 con un degradado marrón → verde. A propósito no
 * lleva etiquetas del tipo "sano" o "estresado": qué NDVI es bueno depende
 * del cultivo, la fase y la época, y poner un rótulo así sería inventarse
 * agronomía.
 */
export const EVALSCRIPT_NDVI_PNG = `//VERSION=3
function setup() {
  return {
    input: [{ bands: ["B04", "B08", "SCL", "dataMask"] }],
    output: { bands: 4, sampleType: "UINT8" }
  };
}
${MASCARA}
var RAMPA = [
  [0.0, [140, 106, 74]],
  [0.2, [186, 160, 96]],
  [0.4, [166, 186, 96]],
  [0.6, [92, 150, 66]],
  [0.8, [26, 96, 46]]
];
function color(ndvi) {
  if (ndvi <= RAMPA[0][0]) return RAMPA[0][1];
  for (var i = 1; i < RAMPA.length; i++) {
    if (ndvi <= RAMPA[i][0]) {
      var t = (ndvi - RAMPA[i - 1][0]) / (RAMPA[i][0] - RAMPA[i - 1][0]);
      var a = RAMPA[i - 1][1];
      var b = RAMPA[i][1];
      return [
        Math.round(a[0] + (b[0] - a[0]) * t),
        Math.round(a[1] + (b[1] - a[1]) * t),
        Math.round(a[2] + (b[2] - a[2]) * t)
      ];
    }
  }
  return RAMPA[RAMPA.length - 1][1];
}
function evaluatePixel(muestra) {
  if (esValido(muestra) === 0) {
    return [0, 0, 0, 0]; // transparente: sin dato no se pinta nada
  }
  var ndvi = (muestra.B08 - muestra.B04) / (muestra.B08 + muestra.B04);
  var c = color(ndvi);
  return [c[0], c[1], c[2], 255];
}
`;
