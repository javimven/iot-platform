import { Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../../common/prisma/prisma.service';

/** Sin una lectura de sus sensores en este tiempo, se avisa (elección del usuario, 2026-09-21). */
const SILENCIO_MS = 60 * 60 * 1000;

/** Como mucho, un aviso por estación al día: el fallo dura hasta que alguien va. */
const ESPERA_ENTRE_AVISOS_MS = 24 * 60 * 60 * 1000;

/**
 * Pasado este silencio, una estación que tampoco da señales de vida se da por
 * abandonada y se deja de avisar: lo que interesa es enterarse de que algo se
 * ha roto, no que a diario recuerden una estación que lleva días parada y ya
 * se sabe (visto en vivo el 2026-09-21: al arrancar el servicio, lo primero
 * que avisó fue una estación de pruebas con cinco días sin datos).
 */
const SILENCIO_DE_ABANDONO_MS = 24 * 60 * 60 * 1000;

const INTERVALO_MS = 5 * 60 * 1000;

/** Identificador reservado de los datos del propio equipo (ADR-0008): no son de campo. */
const SENSOR_DE_EQUIPO = '_device';

/**
 * Avisa cuando una estación lleva una hora sin datos de sus sensores
 * (BACKLOG.md #57), pase lo que pase: tanto si ha dejado de enviar como si
 * sigue enviando batería y cobertura pero sin una sola lectura.
 *
 * El segundo caso es el que se lleva viendo con la WSC2-N: cualquier reinicio
 * le borra las declaraciones de sus sensores RS485 y sigue «en línea» sin
 * guardar nada. El 2026-09-21 pasó tres veces en una tarde y las tres se
 * descubrieron de casualidad; antes, un corte de tres días solo se notó al
 * echar de menos los datos.
 *
 * No entra en por qué: para eso están el aviso de la app y la ficha de la
 * estación. Aquí solo se abre la alerta (y el correo lo manda
 * `NotificationDispatchService`, una vez por alerta y destinatario).
 */
@Injectable()
export class NoSensorDataService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(NoSensorDataService.name);
  private timer?: NodeJS.Timeout;

  constructor(private readonly prisma: PrismaService) {}

  onModuleInit(): void {
    this.timer = setInterval(() => {
      this.scan().catch((error) =>
        this.logger.error(`No sensor data scan failed: ${(error as Error).message}`),
      );
    }, INTERVALO_MS);
  }

  onModuleDestroy(): void {
    if (this.timer) {
      clearInterval(this.timer);
    }
  }

  /** Público: útil para forzar una pasada desde una prueba. */
  async scan(ahora: Date = new Date()): Promise<void> {
    // Job de sistema: recorre todas las organizaciones, como
    // `OfflineDetectionService` (el bypass de RLS va por `runInTenantContext`,
    // nunca con el cliente a pelo).
    const gateways = await this.prisma.runInTenantContext({ isPlatformAdmin: true }, (tx) =>
      // Mismo filtro que `OfflineDetectionService`: una estación deshabilitada
      // o aún sin aprovisionar no tiene de qué avisar.
      tx.gateway.findMany({
        where: { status: { in: ['online', 'offline'] }, deletedAt: null },
      }),
    );

    for (const gateway of gateways) {
      try {
        await this.revisarGateway(gateway, ahora);
      } catch (error) {
        this.logger.error(`Gateway ${gateway.id}: ${(error as Error).message}`);
      }
    }
  }

  private async revisarGateway(
    gateway: { id: string; organizationId: string; lastSeenAt: Date | null },
    ahora: Date,
  ): Promise<void> {
    const { id: gatewayId, organizationId } = gateway;
    await this.prisma.runInTenantContext({ organizationId }, async (tx) => {
      const ultima = await this.ultimaLecturaDeCampo(tx, gatewayId);

      // Una estación sin sensores de campo, o que no ha dado datos nunca, no
      // tiene de qué avisar: no se sabe si es un fallo o es que aún no está
      // puesta en marcha.
      if (!ultima) return;

      const silencio = ahora.getTime() - ultima.getTime();
      const abierta = await tx.alert.findFirst({
        where: { gatewayId, alertType: 'no_sensor_data', status: { not: 'resolved' } },
      });

      if (silencio <= SILENCIO_MS) {
        if (abierta) {
          await tx.alert.update({
            where: { id: abierta.id },
            data: { status: 'resolved', resolvedAt: ahora },
          });
          this.logger.log(`Gateway ${gatewayId}: vuelven los datos de sensores, alerta resuelta`);
        }
        return;
      }

      if (abierta) return;

      // Una estación que lleva días sin datos y que además no envía nada se
      // da por parada, no por recién rota. El caso que sí interesa aunque
      // lleve días —la WSC2-N sin declarar sus sensores— sigue enviando
      // batería y cobertura, así que su `lastSeenAt` está fresco y pasa.
      const daSenalesDeVida =
        gateway.lastSeenAt != null && ahora.getTime() - gateway.lastSeenAt.getTime() <= SILENCIO_MS;
      if (!daSenalesDeVida && silencio > SILENCIO_DE_ABANDONO_MS) return;

      // Un aviso al día por estación: mientras nadie va a arreglarla, el
      // silencio sigue y no tiene sentido abrir una alerta (y su correo) en
      // cada pasada.
      const reciente = await tx.alert.findFirst({
        where: {
          gatewayId,
          alertType: 'no_sensor_data',
          openedAt: { gt: new Date(ahora.getTime() - ESPERA_ENTRE_AVISOS_MS) },
        },
        orderBy: { openedAt: 'desc' },
      });
      if (reciente) return;

      await tx.alert.create({
        data: {
          organizationId,
          alertType: 'no_sensor_data',
          gatewayId,
          status: 'open',
          openedAt: ahora,
          details: {
            ultimaLectura: ultima.toISOString(),
            silencioMinutos: Math.round(silencio / 60000),
          },
        },
      });
      this.logger.warn(
        `Gateway ${gatewayId}: ${Math.round(silencio / 60000)} min sin datos de sensores, alerta abierta`,
      );
    });
  }

  /**
   * La lectura más reciente de un sensor de campo de esa estación. Se dejan
   * fuera los datos del propio equipo (batería y cobertura): precisamente el
   * fallo que se busca es que lleguen solo esos.
   */
  private async ultimaLecturaDeCampo(
    tx: Prisma.TransactionClient,
    gatewayId: string,
  ): Promise<Date | null> {
    const filas = await tx.$queryRaw<{ ultima: Date | null }[]>`
      SELECT max(lr.ts_origin) AS ultima
      FROM latest_readings lr
      JOIN channels c ON c.id = lr.channel_id
      JOIN sensors s ON s.id = c.sensor_id
      JOIN devices d ON d.id = s.device_id
      WHERE d.gateway_id = ${gatewayId}::uuid
        AND s.external_identifier <> ${SENSOR_DE_EQUIPO}
        AND s.deleted_at IS NULL
        AND c.deleted_at IS NULL
        AND d.deleted_at IS NULL
    `;
    return filas[0]?.ultima ?? null;
  }
}
