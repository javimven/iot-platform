import { Module } from '@nestjs/common';
import { PrismaService } from '../../common/prisma/prisma.service';
import { StorageService } from '../../common/storage/storage.service';
import { SatelliteQueueProducer } from '../../common/queues/satellite-queue.producer';
import { ParcelsModule } from '../parcels/parcels.module';
import { SatelliteController } from './satellite.controller';
import { SatelliteService } from './satellite.service';

/**
 * Cara de lectura del modulo de satelite, en el proceso `api` (BACKLOG.md
 * #36). Aqui NO vive el proveedor de Copernicus: la API solo lee lo que el
 * worker ya calculo y firma enlaces. Lo unico que escribe es encolar un
 * refresco.
 *
 * Reutiliza `ParcelsService` (de `ParcelsModule`) para resolver quien puede
 * ver una parcela: una sola forma de comprobarlo, no dos.
 */
@Module({
  imports: [ParcelsModule],
  controllers: [SatelliteController],
  providers: [PrismaService, StorageService, SatelliteQueueProducer, SatelliteService],
})
export class SatelliteModule {}
