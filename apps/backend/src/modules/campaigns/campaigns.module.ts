import { Module } from '@nestjs/common';
import { AuditLogService } from '../../common/audit/audit-log.service';
import { PrismaService } from '../../common/prisma/prisma.service';
import { CampaignAccess } from './campaign-access';
import { CampaignsController } from './campaigns.controller';
import { CampaignsService } from './campaigns.service';
import { CropUnitsService } from './crop-units.service';
import { CropsController } from './crops.controller';

/**
 * Campañas y cuaderno de campo (BACKLOG.md #60, ADR-0012/0013/0014). Módulo
 * propio: reutiliza las parcelas (tablas y triggers de la migración 0008) sin
 * depender del módulo de satélite.
 */
@Module({
  controllers: [CampaignsController, CropsController],
  providers: [PrismaService, AuditLogService, CampaignAccess, CampaignsService, CropUnitsService],
  exports: [CampaignAccess, CampaignsService],
})
export class CampaignsModule {}
