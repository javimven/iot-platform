import {
  ArgumentsHost,
  Catch,
  ExceptionFilter,
  HttpException,
  HttpStatus,
  Logger,
} from '@nestjs/common';
import { Request, Response } from 'express';

/**
 * Formato de error RFC 7807 (API_DESIGN.md §4). En producción nunca se filtra
 * detalle interno (stack trace, nombre de tabla/columna) — solo un `detail`
 * genérico y un `instance`; el detalle completo va a los logs con el
 * correlationId (SECURITY.md §13, OBSERVABILITY.md §5).
 */
@Catch()
export class Rfc7807ExceptionFilter implements ExceptionFilter {
  private readonly logger = new Logger('ExceptionFilter');

  catch(exception: unknown, host: ArgumentsHost): void {
    const ctx = host.switchToHttp();
    const response = ctx.getResponse<Response>();
    const request = ctx.getRequest<Request>();
    const correlationId = (request as { correlationId?: string }).correlationId;

    const { status, type, title, detail, errors } = this.mapException(exception);

    if (status >= 500) {
      this.logger.error(
        `[${correlationId}] ${title}: ${exception instanceof Error ? exception.stack : String(exception)}`,
      );
    }

    response.status(status).json({
      type,
      title,
      status,
      detail,
      instance: request.originalUrl,
      ...(errors ? { errors } : {}),
    });
  }

  private mapException(exception: unknown): {
    status: number;
    type: string;
    title: string;
    detail?: string;
    errors?: Array<{ field: string; message: string }>;
  } {
    if (exception instanceof HttpException) {
      const status = exception.getStatus();
      const body = exception.getResponse();
      if (typeof body === 'object' && body !== null && 'message' in body) {
        const message = (body as { message: unknown }).message;
        if (Array.isArray(message)) {
          // Errores de validación de class-validator: se traducen a la
          // convención errors[] de RFC 7807 (API_DESIGN.md §4).
          return {
            status,
            type: 'validation-error',
            title: 'Validation failed',
            detail: 'One or more fields are invalid.',
            errors: message.map((m: string) => ({ field: this.extractField(m), message: m })),
          };
        }
        return { status, type: this.typeFor(status), title: String(message) };
      }
      return { status, type: this.typeFor(status), title: exception.message };
    }

    // Nunca se expone el mensaje/stack real de una excepción no controlada.
    return {
      status: HttpStatus.INTERNAL_SERVER_ERROR,
      type: 'internal-error',
      title: 'Internal server error',
      detail: 'An unexpected error occurred. It has been logged for investigation.',
    };
  }

  private typeFor(status: number): string {
    switch (status) {
      case 400:
        return 'validation-error';
      case 401:
        return 'unauthorized';
      case 403:
        return 'forbidden';
      case 404:
        return 'not-found';
      case 409:
        return 'conflict';
      case 429:
        return 'rate-limited';
      default:
        return 'error';
    }
  }

  private extractField(message: string): string {
    return message.split(' ')[0] ?? 'unknown';
  }
}
