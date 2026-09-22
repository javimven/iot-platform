import {
  idDeTrabajo,
  idTrabajoHistorico,
  idTrabajoObservacion,
  idTrabajoRefresco,
} from './satellite-queue';
import { PROCESSING_VERSION } from '../../modules/satellite/providers/copernicus/evalscripts';

/**
 * Identificadores de trabajo de la cola de satélite. BullMQ rechaza los que
 * llevan `:` ("Custom Id cannot contain :"), y la primera versión los usaba: en
 * staging no se encoló ni un trabajo (2026-09-22). Estas pruebas fijan el
 * formato; la de integración (`test/integration/satellite-queue.spec.ts`)
 * comprueba que Redis de verdad los acepta.
 */
describe('identificadores de la cola de satélite', () => {
  const parcelId = '0b6c1f8e-4b1e-4c52-9d2a-6c1f0b1e2d3a';

  it('ninguno lleva ":"', () => {
    const ids = [
      idTrabajoObservacion({
        organizationId: 'org-1',
        parcelId,
        provider: 'copernicus',
        collection: 'sentinel-2-l2a',
        acquisitionDate: '2026-09-15',
        acquisitionTime: '2026-09-15T10:42:19.000Z', // este sí lleva ':', y no entra en el id
        sourceItemIds: [],
      }),
      idTrabajoHistorico(parcelId),
      idTrabajoRefresco(parcelId, new Date('2026-09-22T11:47:42Z')),
    ];

    for (const id of ids) {
      expect(id).not.toContain(':');
    }
  });

  it('son deterministas: la misma pasada da el mismo id', () => {
    const trabajo = {
      organizationId: 'org-1',
      parcelId,
      provider: 'copernicus',
      collection: 'sentinel-2-l2a',
      acquisitionDate: '2026-09-15',
      acquisitionTime: '2026-09-15T10:42:19.000Z',
      sourceItemIds: ['a'],
    };
    expect(idTrabajoObservacion(trabajo)).toBe(
      idTrabajoObservacion({ ...trabajo, sourceItemIds: ['a', 'b'] }),
    );
  });

  it('la versión de procesado entra en el id: al subirla, la misma pasada es otro trabajo', () => {
    // BullMQ guarda un día los terminados y descarta un id repetido. Sin la
    // versión, al pasar a ndvi-s2-v2 (2026-09-22) no se habría reprocesado
    // nada de lo procesado ese mismo día.
    const trabajo = {
      organizationId: 'org-1',
      parcelId,
      provider: 'copernicus',
      collection: 'sentinel-2-l2a',
      acquisitionDate: '2026-09-15',
      acquisitionTime: '2026-09-15T10:42:19.000Z',
      sourceItemIds: [],
    };
    expect(idTrabajoObservacion(trabajo, 'ndvi-s2-v1')).not.toBe(
      idTrabajoObservacion(trabajo, 'ndvi-s2-v2'),
    );
    expect(idTrabajoObservacion(trabajo)).toContain(PROCESSING_VERSION);
  });

  it('el refresco lleva la hora sin minutos: dos en la misma hora son el mismo', () => {
    expect(idTrabajoRefresco(parcelId, new Date('2026-09-22T11:05:00Z'))).toBe(
      idTrabajoRefresco(parcelId, new Date('2026-09-22T11:59:00Z')),
    );
    expect(idTrabajoRefresco(parcelId, new Date('2026-09-22T11:59:00Z'))).not.toBe(
      idTrabajoRefresco(parcelId, new Date('2026-09-22T12:00:00Z')),
    );
  });

  it('si alguien cuela un ":", falla aquí y no en la cola', () => {
    expect(() => idDeTrabajo('algo', 'con:dos-puntos')).toThrow(/BullMQ lo rechaza/);
  });
});
