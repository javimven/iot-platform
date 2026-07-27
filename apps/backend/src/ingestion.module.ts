import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { HealthController } from './common/health/health.controller';
import { PrismaService } from './common/prisma/prisma.service';
import { MqttIngestionService } from './modules/ingestion/mqtt-ingestion.service';

/**
 * Root module del proceso `ingestion` (ARCHITECTURE.md §5): único proceso que
 * habla MQTT con EMQX. Expone solo `/health` (para el healthcheck de Docker,
 * DEPLOYMENT.md), nunca una API de negocio.
 */
@Module({
  imports: [ConfigModule.forRoot({ isGlobal: true })],
  controllers: [HealthController],
  providers: [PrismaService, MqttIngestionService],
})
export class IngestionModule {}
