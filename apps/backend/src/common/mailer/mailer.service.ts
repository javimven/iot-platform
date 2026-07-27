import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import * as nodemailer from 'nodemailer';

export interface MailMessage {
  to: string;
  subject: string;
  text: string;
}

/**
 * Envío de email real (Etapa 13, cierra el hueco de "solo logueado" de las
 * etapas anteriores). SMTP genérico (DEPLOYMENT.md §3: `SMTP_HOST/PORT/
 * USER/PASSWORD`) — en desarrollo apunta a Mailpit (docker-compose.yml), en
 * producción al proveedor real que se elija en Etapa 9.
 */
@Injectable()
export class MailerService implements OnModuleInit {
  private readonly logger = new Logger(MailerService.name);
  private transporter?: nodemailer.Transporter;
  private fromAddress = 'no-reply@example.com';

  constructor(private readonly config: ConfigService) {}

  onModuleInit(): void {
    this.fromAddress = this.config.get<string>('EMAIL_FROM', this.fromAddress);
    const user = this.config.get<string>('SMTP_USER');
    this.transporter = nodemailer.createTransport({
      host: this.config.getOrThrow<string>('SMTP_HOST'),
      port: this.config.get<number>('SMTP_PORT', 587),
      // Mailpit (desarrollo) no exige autenticación — solo se configura si
      // hay usuario, para no romper el arranque local sin credenciales.
      auth: user ? { user, pass: this.config.get<string>('SMTP_PASSWORD') } : undefined,
    });
  }

  /**
   * Best-effort: nunca lanza — quien la llama decide si un fallo de envío
   * debe bloquear la operación (SECURITY.md/ARCHITECTURE.md: no se
   * considera una "tarea pesada" bloqueante para el flujo principal).
   */
  async send(message: MailMessage): Promise<{ ok: boolean; error?: string }> {
    try {
      await this.transporter?.sendMail({
        from: this.fromAddress,
        to: message.to,
        subject: message.subject,
        text: message.text,
      });
      return { ok: true };
    } catch (error) {
      this.logger.error(`Failed to send email to ${message.to}: ${(error as Error).message}`);
      return { ok: false, error: (error as Error).message };
    }
  }
}
