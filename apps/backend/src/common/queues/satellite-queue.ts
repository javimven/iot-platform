import { TrabajoObservacion } from '../../modules/satellite/processing/satellite-processing.service';

/**
 * Cola del módulo de satélite, **separada de `telemetry-processing`** a
 * propósito (BACKLOG.md #36): procesar una imagen tarda segundos y depende de
 * una API de terceros, y eso nunca debe ponerse por delante de un mensaje de
 * una estación. Las consume el mismo proceso `worker`; no hace falta un
 * contenedor aparte mientras el volumen sea este.
 */
export const SATELLITE_QUEUE_NAME = 'satellite-processing';

/** Tipos de trabajo que viajan por la cola. */
export const TRABAJO_REPASO = 'repaso-diario';
export const TRABAJO_OBSERVACION = 'observacion';
export const TRABAJO_HISTORICO = 'historico-parcela';

/** Repaso diario: busca pasadas nuevas de todas las parcelas con satélite. */
export interface RepasoPayload {
  /** Marca de qué disparó el repaso, solo para el log. */
  origen: 'programado' | 'manual';
}

/** Histórico inicial de una parcela recién creada o redibujada. */
export interface HistoricoPayload {
  organizationId: string;
  parcelId: string;
  /** Días hacia atrás; por defecto, `SATELLITE_BACKFILL_DAYS`. */
  dias?: number;
}

export type SatelliteJobPayload = RepasoPayload | HistoricoPayload | TrabajoObservacion;

/**
 * Política de reintentos. Menos intentos y más espera que en telemetría: al
 * otro lado hay una API con cuota, y machacarla no la arregla. Los fallos se
 * conservan para poder mirarlos (dead-letter, OBSERVABILITY.md §7).
 */
export const SATELLITE_JOB_OPTIONS = {
  attempts: 3,
  backoff: { type: 'exponential' as const, delay: 30_000 },
  removeOnComplete: { age: 24 * 3600 },
  removeOnFail: false,
};

/**
 * Separador de las partes de un identificador de trabajo.
 *
 * **Nunca `:`.** BullMQ rechaza los identificadores propios que lo llevan
 * (`Custom Id cannot contain :`), porque es su separador de claves en Redis.
 * La primera versión usaba `:` y en staging (2026-09-22) no se encoló ni un
 * trabajo: la parcela recién creada se quedó sin histórico. Las pruebas no lo
 * vieron porque simulaban la cola; ahora hay una contra Redis de verdad.
 */
const SEPARADOR = '__';

/** Une las partes y comprueba que el resultado es un identificador válido. */
export function idDeTrabajo(...partes: string[]): string {
  const id = partes.join(SEPARADOR);
  if (id.includes(':')) {
    throw new Error(`Identificador de trabajo con ':' (BullMQ lo rechaza): ${id}`);
  }
  return id;
}

/**
 * Identificador determinista de un trabajo de observación: la misma pasada
 * encolada dos veces (el repaso diario y el histórico, por ejemplo) es **un
 * solo** trabajo. Es la primera barrera contra el trabajo repetido; la segunda
 * es el índice único de la base (migración 0009).
 */
export function idTrabajoObservacion(trabajo: TrabajoObservacion): string {
  return idDeTrabajo(
    trabajo.parcelId,
    trabajo.provider,
    trabajo.collection,
    trabajo.acquisitionDate,
  );
}

/** Histórico inicial de una parcela: uno por parcela. */
export function idTrabajoHistorico(parcelId: string): string {
  return idDeTrabajo('historico', parcelId);
}

/**
 * Refresco manual: uno por parcela y hora. La hora va en el identificador, así
 * que dos refrescos de la misma hora son el mismo trabajo (y el segundo se
 * rechaza con 429). `YYYY-MM-DDTHH`, sin minutos: no lleva `:`.
 */
export function idTrabajoRefresco(parcelId: string, ahora: Date = new Date()): string {
  return idDeTrabajo('refresco', parcelId, ahora.toISOString().slice(0, 13));
}
