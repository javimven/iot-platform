import { Module } from '@nestjs/common';
import { AuditLogService } from '../../common/audit/audit-log.service';
import { PrismaService } from '../../common/prisma/prisma.service';
import { ParcelGeometryService } from './parcel-geometry.service';
import { ParcelsController } from './parcels.controller';
import { ParcelsRepository } from './parcels.repository';
import { ParcelsService } from './parcels.service';

/**
 * Parcelas (BACKLOG.md #36). Modulo propio y no una carpeta mas dentro de
 * `directory/`: la parcela no sirve para operar estaciones, es la unidad del
 * modulo de satelite, y el Directorio IoT ya decidio no exponer conceptos que
 * el usuario no necesita (ADR-0006).
 */
@Module({
  controllers: [ParcelsController],
  providers: [
    PrismaService,
    AuditLogService,
    ParcelGeometryService,
    ParcelsRepository,
    ParcelsService,
  ],
  exports: [ParcelsService, ParcelsRepository, ParcelGeometryService],
})
export class ParcelsModule {}
