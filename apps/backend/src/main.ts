import 'reflect-metadata';
import { NestFactory } from '@nestjs/core';
import { ValidationPipe } from '@nestjs/common';
import helmet from 'helmet';
import { ApiModule } from './api.module';
import { IngestionModule } from './ingestion.module';
import { WorkerModule } from './worker.module';

/**
 * Único entrypoint para los tres procesos (ARCHITECTURE.md §4, DEPLOYMENT.md
 * `infra/docker/Dockerfile`): `PROCESS_ROLE` decide qué módulo raíz se
 * bootstrapea. Mismo build, mismo `CMD`, distinta variable de entorno — no
 * son tres imágenes Docker distintas.
 */
async function bootstrap(): Promise<void> {
  const role = process.env.PROCESS_ROLE ?? 'api';

  switch (role) {
    case 'api': {
      const app = await NestFactory.create(ApiModule);
      app.use(helmet());
      app.enableCors({
        origin: (process.env.CORS_ALLOWED_ORIGINS ?? '').split(',').filter(Boolean),
        credentials: false, // Bearer token, no cookies (SECURITY.md §6) — no hace falta credentials:true
      });
      app.useGlobalPipes(
        new ValidationPipe({ whitelist: true, forbidNonWhitelisted: true, transform: true }),
      );
      await app.listen(process.env.PORT ?? 3000);
      break;
    }
    case 'ingestion': {
      const app = await NestFactory.create(IngestionModule);
      await app.listen(process.env.PORT ?? 3001); // Solo para /health (DEPLOYMENT.md)
      break;
    }
    case 'worker': {
      const app = await NestFactory.create(WorkerModule);
      await app.listen(process.env.PORT ?? 3002); // Solo para /health
      break;
    }
    default:
      throw new Error(`Unknown PROCESS_ROLE: ${role}`);
  }
}

bootstrap();
