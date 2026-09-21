import { TelemetryPartitionsService } from './telemetry-partitions.service';
import { PrismaService } from '../../common/prisma/prisma.service';

/**
 * BACKLOG.md #45: sin particiones futuras, `telemetry` rechaza las
 * inserciones del mes nuevo y los trabajos acaban en la cola de fallidos
 * (pasó el 2026-09-16 con 323 lecturas).
 */
describe('TelemetryPartitionsService', () => {
  function build(resultado: unknown) {
    const $queryRaw = jest
      .fn()
      .mockImplementation(() =>
        resultado instanceof Error ? Promise.reject(resultado) : Promise.resolve(resultado),
      );
    const prisma = { $queryRaw } as unknown as PrismaService;
    return { $queryRaw, servicio: new TelemetryPartitionsService(prisma) };
  }

  it('pide a la base de datos las particiones que falten y cuenta las creadas', async () => {
    const { $queryRaw, servicio } = build([{ crear_particiones_telemetry: 2 }]);

    await expect(servicio.asegurarParticiones()).resolves.toBe(2);
    expect($queryRaw).toHaveBeenCalledTimes(1);
  });

  it('no dice nada cuando ya estaban todas', async () => {
    const { servicio } = build([{ crear_particiones_telemetry: 0 }]);
    await expect(servicio.asegurarParticiones()).resolves.toBe(0);
  });

  it('un fallo de base de datos no tumba el worker: se reintenta en la siguiente pasada', async () => {
    const { servicio } = build(new Error('conexión perdida'));
    await expect(servicio.asegurarParticiones()).resolves.toBe(0);
  });

  it('al arrancar lo intenta ya, sin esperar al primer intervalo', async () => {
    const { $queryRaw, servicio } = build([{ crear_particiones_telemetry: 1 }]);

    servicio.onModuleInit();
    servicio.onModuleDestroy();

    expect($queryRaw).toHaveBeenCalledTimes(1);
  });
});
