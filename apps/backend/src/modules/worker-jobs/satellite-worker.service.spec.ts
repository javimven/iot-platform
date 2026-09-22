import { UnrecoverableError } from 'bullmq';
import { paraLaCola } from './satellite-worker.service';
import { SatelliteProviderError } from '../../modules/satellite/providers/satellite.types';

/**
 * Qué errores reintenta la cola de satélite. El 2026-09-22 un 406 de
 * Copernicus, que es una petición mal hecha, se intentó tres veces: tres
 * llamadas contra la cuota para el mismo error.
 */
describe('paraLaCola', () => {
  it('lo que el proveedor da por perdido no se reintenta', () => {
    const error = new SatelliteProviderError('Copernicus respondió 406', {
      status: 406,
      reintentable: false,
      provider: 'copernicus',
    });

    const traducido = paraLaCola(error);

    expect(traducido).toBeInstanceOf(UnrecoverableError);
    expect((traducido as Error).message).toBe('Copernicus respondió 406');
  });

  it('lo temporal del proveedor sigue reintentándose', () => {
    const error = new SatelliteProviderError('Copernicus respondió 503', {
      status: 503,
      reintentable: true,
      provider: 'copernicus',
    });

    expect(paraLaCola(error)).toBe(error);
  });

  it('cualquier otro fallo (base de datos, S3…) se deja como está', () => {
    const error = new Error('conexión perdida');

    expect(paraLaCola(error)).toBe(error);
  });
});
