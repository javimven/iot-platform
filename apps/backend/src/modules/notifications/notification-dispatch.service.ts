import { Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { Alert, Prisma } from '@prisma/client';
import { PrismaService } from '../../common/prisma/prisma.service';
import { MailerService } from '../../common/mailer/mailer.service';

const SCAN_INTERVAL_MS = 30_000;
/** FUNCTIONAL_REQUIREMENTS.md §15: Admin de organización + Técnico + Operador (no Solo lectura). */
const NOTIFIED_ROLE_CODES = ['org_admin', 'technician', 'operator'];

/**
 * Notifica por email cada alerta abierta a los destinatarios de su
 * organización (FUNCTIONAL_REQUIREMENTS.md §15). Sondeo periódico en vez de
 * enviar en el mismo paso que crea la alerta (`TelemetryProcessingService`/
 * `OfflineDetectionService`) — evita acoplar la escritura de la alerta al
 * envío de email (una llamada SMTP no debe formar parte de la transacción
 * que abre la alerta) y reutiliza el mismo patrón ya justificado en
 * `OfflineDetectionService` (simplificación deliberada frente a un job
 * repetible de BullMQ para algo de esta frecuencia/volumen).
 *
 * `notification_log` (única fila por alerta+destinatario) es lo que impide
 * reenviar el mismo aviso en cada ciclo de sondeo.
 */
@Injectable()
export class NotificationDispatchService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(NotificationDispatchService.name);
  private timer?: NodeJS.Timeout;

  constructor(
    private readonly prisma: PrismaService,
    private readonly mailer: MailerService,
  ) {}

  onModuleInit(): void {
    this.timer = setInterval(() => {
      this.scan().catch((error) =>
        this.logger.error(`Notification scan failed: ${(error as Error).message}`),
      );
    }, SCAN_INTERVAL_MS);
  }

  onModuleDestroy(): void {
    if (this.timer) {
      clearInterval(this.timer);
    }
  }

  async scan(): Promise<void> {
    const openAlerts = await this.prisma.alert.findMany({
      where: { status: { not: 'resolved' } },
      take: 500,
    });
    for (const alert of openAlerts) {
      await this.dispatchForAlert(alert);
    }
  }

  private async dispatchForAlert(alert: Alert): Promise<void> {
    await this.prisma.runInTenantContext({ organizationId: alert.organizationId }, async (tx) => {
      const recipients = await tx.member.findMany({
        where: {
          organizationId: alert.organizationId,
          status: 'active',
          roleCode: { in: NOTIFIED_ROLE_CODES },
        },
        include: { user: true },
      });

      for (const recipient of recipients) {
        await this.notifyOnce(tx, alert, recipient.userId, recipient.user.email);
      }
    });
  }

  /**
   * Envía y registra el resultado — si ya existe una fila para este
   * alerta+destinatario (`notification_log`, `@@unique`), no se reenvía.
   * Limitación conocida de MVP: un envío marcado `failed` no se reintenta
   * automáticamente en el siguiente sondeo (evita reenviar sin límite si el
   * SMTP está caído) — queda visible en `notification_log` para revisión
   * manual (OBSERVABILITY.md).
   */
  private async notifyOnce(
    tx: Prisma.TransactionClient,
    alert: Alert,
    recipientUserId: string,
    recipientEmail: string,
  ): Promise<void> {
    const alreadyNotified = await tx.notificationLog.findUnique({
      where: { alertId_recipientUserId: { alertId: alert.id, recipientUserId } },
    });
    if (alreadyNotified) {
      return;
    }

    const result = await this.mailer.send({
      to: recipientEmail,
      subject: `Alerta ${alert.alertType === 'offline' ? 'de desconexión' : 'de umbral'} abierta`,
      text: this.buildBody(alert),
    });

    try {
      await tx.notificationLog.create({
        data: {
          organizationId: alert.organizationId,
          alertId: alert.id,
          recipientUserId,
          channel: 'email',
          status: result.ok ? 'sent' : 'failed',
          sentAt: new Date(),
          error: result.error,
        },
      });
    } catch (error) {
      if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002') {
        return; // Ciclo de sondeo concurrente ya lo registró — no es un fallo.
      }
      throw error;
    }
  }

  private buildBody(alert: Alert): string {
    if (alert.alertType === 'offline') {
      return `Un gateway o dispositivo ha dejado de reportar datos (alerta ${alert.id}, abierta ${alert.openedAt.toISOString()}).`;
    }
    return `Un canal ha superado su umbral configurado (alerta ${alert.id}, abierta ${alert.openedAt.toISOString()}).`;
  }
}
