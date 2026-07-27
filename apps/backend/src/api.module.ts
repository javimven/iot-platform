import { MiddlewareConsumer, Module, NestModule } from '@nestjs/common';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { APP_FILTER, APP_GUARD } from '@nestjs/core';
import { JwtModule } from '@nestjs/jwt';
import { IamModule } from './modules/iam/iam.module';
import { DirectoryModule } from './modules/directory/directory.module';
import { TelemetryModule } from './modules/telemetry/telemetry.module';
import { PlatformModule } from './modules/platform/platform.module';
import { HealthController } from './common/health/health.controller';
import { PrismaService } from './common/prisma/prisma.service';
import { CorrelationIdMiddleware } from './common/middleware/correlation-id.middleware';
import { Rfc7807ExceptionFilter } from './common/filters/rfc7807-exception.filter';
import { JwtAuthGuard } from './common/guards/jwt-auth.guard';
import { PermissionsGuard } from './common/guards/permissions.guard';

/**
 * Root module del proceso `api` (ARCHITECTURE.md §4-5): REST + WebSocket
 * (WebSocket se añade cuando exista el módulo de Telemetría/Alertas que lo
 * necesita, API_DESIGN.md §9). Único proceso que expone HTTP a la app
 * Flutter — nunca habla MQTT (eso es `ingestion`, ver ingestion.module.ts).
 */
@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true }),
    // Registrado global aquí (única fuente de verdad, RS256+kid, SECURITY.md
    // §8) para que JwtAuthGuard (APP_GUARD global, más abajo) y IamModule
    // resuelvan siempre la misma instancia de JwtService — registrarlo dos
    // veces en módulos distintos crearía dos JwtService independientes.
    JwtModule.registerAsync({
      global: true,
      inject: [ConfigService],
      useFactory: (config: ConfigService) => ({
        privateKey: config.getOrThrow<string>('JWT_PRIVATE_KEY'),
        publicKey: config.getOrThrow<string>('JWT_PUBLIC_KEY'),
        signOptions: {
          algorithm: 'RS256',
          keyid: config.get<string>('JWT_KID', 'v1'),
          expiresIn: config.get<string>('ACCESS_TOKEN_TTL', '15m'),
        },
        verifyOptions: { algorithms: ['RS256'] },
      }),
    }),
    IamModule,
    DirectoryModule,
    TelemetryModule,
    PlatformModule,
  ],
  controllers: [HealthController],
  providers: [
    PrismaService,
    { provide: APP_FILTER, useClass: Rfc7807ExceptionFilter },
    { provide: APP_GUARD, useClass: JwtAuthGuard },
    { provide: APP_GUARD, useClass: PermissionsGuard },
  ],
})
export class ApiModule implements NestModule {
  configure(consumer: MiddlewareConsumer): void {
    consumer.apply(CorrelationIdMiddleware).forRoutes('*');
  }
}
