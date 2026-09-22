import { Queue } from 'bullmq';
import IORedis from 'ioredis';
import { randomUUID } from 'node:crypto';
import {
  SATELLITE_JOB_OPTIONS,
  TRABAJO_HISTORICO,
  TRABAJO_OBSERVACION,
  idTrabajoHistorico,
  idTrabajoObservacion,
  idTrabajoRefresco,
} from '../../src/common/queues/satellite-queue';

/**
 * La cola de satélite contra Redis y BullMQ de verdad.
 *
 * Existe por un fallo real (2026-09-22): los identificadores de trabajo
 * llevaban `:` y BullMQ los rechaza. Todas las pruebas unitarias pasaban
 * porque simulaban la cola; el primer histórico de la primera parcela real no
 * se encoló. Esta prueba mete en una cola de verdad los tres tipos de
 * identificador y comprueba además que el mismo id no se encola dos veces, que
 * es de lo que depende el cortafuegos del refresco manual.
 *
 * Se salta si el entorno no tiene `REDIS_URL`, igual que la de S3.
 */
const hayRedis = Boolean(process.env.REDIS_URL);
const describeSiHayRedis = hayRedis ? describe : describe.skip;

describeSiHayRedis('Cola de satélite contra Redis real', () => {
  let conexion: IORedis;
  let cola: Queue;

  beforeAll(() => {
    conexion = new IORedis(process.env.REDIS_URL as string, { maxRetriesPerRequest: null });
    // Nombre propio para no mezclarse con la cola real si se corre en local.
    cola = new Queue(`satellite-processing-prueba-${randomUUID().slice(0, 8)}`, {
      connection: conexion,
    });
  });

  afterAll(async () => {
    await cola.obliterate({ force: true });
    await cola.close();
    conexion.disconnect();
  });

  const parcelId = randomUUID();

  it('acepta los tres tipos de identificador', async () => {
    const trabajo = {
      organizationId: randomUUID(),
      parcelId,
      provider: 'copernicus',
      collection: 'sentinel-2-l2a',
      acquisitionDate: '2026-09-15',
      acquisitionTime: '2026-09-15T10:42:19.000Z',
      sourceItemIds: ['S2B_T30SYJ_20260915'],
    };

    await expect(
      cola.add(TRABAJO_OBSERVACION, trabajo, {
        ...SATELLITE_JOB_OPTIONS,
        jobId: idTrabajoObservacion(trabajo),
      }),
    ).resolves.toBeDefined();
    await expect(
      cola.add(
        TRABAJO_HISTORICO,
        { organizationId: trabajo.organizationId, parcelId },
        {
          ...SATELLITE_JOB_OPTIONS,
          jobId: idTrabajoHistorico(parcelId),
        },
      ),
    ).resolves.toBeDefined();
    await expect(
      cola.add(
        TRABAJO_HISTORICO,
        { organizationId: trabajo.organizationId, parcelId },
        {
          ...SATELLITE_JOB_OPTIONS,
          jobId: idTrabajoRefresco(parcelId),
        },
      ),
    ).resolves.toBeDefined();
  });

  it('el mismo identificador no se encola dos veces: de ahí depende el límite del refresco', async () => {
    const jobId = idTrabajoRefresco(parcelId);

    // Ya encolado en la prueba anterior: getJob lo encuentra, y eso es lo que
    // hace que el segundo refresco de la hora responda 429.
    expect(await cola.getJob(jobId)).toBeDefined();

    await cola.add(TRABAJO_HISTORICO, { parcelId }, { ...SATELLITE_JOB_OPTIONS, jobId });
    const conEseId = (await cola.getJobs(['waiting', 'delayed'])).filter((j) => j.id === jobId);
    expect(conEseId).toHaveLength(1);
  });
});

if (!hayRedis) {
  it('se salta: no hay Redis configurado en este entorno', () => {
    expect(hayRedis).toBe(false);
  });
}
