import { Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { PrismaService } from '../../common/prisma/prisma.service';

/** Meses por delante que se mantienen siempre creados. */
const MESES_POR_DELANTE = 3;

/** Cada cuánto se comprueba. Con 3 meses de margen, dos veces al día sobra. */
const INTERVALO_MS = 12 * 60 * 60 * 1000;

/**
 * Particiones mensuales de `telemetry` (DATA_MODEL.md §5, BACKLOG.md #45).
 *
 * `telemetry` está particionada por `ts_origin`: si llega un dato de un mes sin
 * partición, PostgreSQL rechaza la inserción entera
 * (`no partition of relation "telemetry" found for row`) y el trabajo acaba en
 * la cola de fallidos. No es hipotético: el 2026-09-16, con la primera estación
 * real enviando, se perdieron así 323 lecturas hasta que se creó la partición a
 * mano, y sin esto habría vuelto a pasar el 1 de enero de 2027.
 *
 * El trabajo solo llama a `crear_particiones_telemetry` (migración 0006), que
 * es idempotente y corre con los permisos de su dueño: el rol de la aplicación
 * no puede crear tablas (DATA_MODEL.md §8) y así no hace falta ampliárselos.
 *
 * Mismo patrón que `OfflineDetectionService`: un `setInterval` en el worker, no
 * una cola aparte de BullMQ para una llamada cada doce horas.
 */
@Injectable()
export class TelemetryPartitionsService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(TelemetryPartitionsService.name);
  private timer?: NodeJS.Timeout;

  constructor(private readonly prisma: PrismaService) {}

  onModuleInit(): void {
    // Al arrancar y luego cada doce horas: si el worker lleva meses sin
    // reiniciarse, las particiones se siguen creando igual.
    void this.asegurarParticiones();
    this.timer = setInterval(() => void this.asegurarParticiones(), INTERVALO_MS);
  }

  onModuleDestroy(): void {
    if (this.timer) {
      clearInterval(this.timer);
    }
  }

  /** Público para poder forzarlo desde una prueba o una consola. */
  async asegurarParticiones(meses: number = MESES_POR_DELANTE): Promise<number> {
    try {
      const filas = await this.prisma.$queryRaw<
        { crear_particiones_telemetry: number }[]
      >`SELECT crear_particiones_telemetry(${meses}::int)`;
      const creadas = Number(filas[0]?.crear_particiones_telemetry ?? 0);
      if (creadas > 0) {
        this.logger.log(`Particiones de telemetry creadas: ${creadas}`);
      }
      return creadas;
    } catch (error) {
      // Nunca tira el worker: si esto falla, lo que se pierde es el margen,
      // y se reintenta en la siguiente pasada.
      this.logger.error(
        `No se pudieron crear las particiones de telemetry: ${(error as Error).message}`,
      );
      return 0;
    }
  }
}
