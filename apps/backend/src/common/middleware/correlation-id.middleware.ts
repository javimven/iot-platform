import { Injectable, NestMiddleware } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { NextFunction, Request, Response } from 'express';

/**
 * Identificador de correlación por petición (OBSERVABILITY.md §5). Se expone
 * como X-Request-Id en la respuesta — más fácil de citar por un usuario o
 * soporte que el `traceparent` completo de OpenTelemetry.
 */
@Injectable()
export class CorrelationIdMiddleware implements NestMiddleware {
  use(req: Request & { correlationId?: string }, res: Response, next: NextFunction): void {
    const incoming = req.headers['x-request-id'];
    const correlationId = typeof incoming === 'string' ? incoming : randomUUID();
    req.correlationId = correlationId;
    res.setHeader('X-Request-Id', correlationId);
    next();
  }
}
