import { Module } from '@nestjs/common';
import { AuditLogService } from '../../common/audit/audit-log.service';
import { PrismaService } from '../../common/prisma/prisma.service';
import { StorageService } from '../../common/storage/storage.service';
import { ActivitiesController } from './activities.controller';
import { ActivitiesService } from './activities.service';
import { CampaignAccess } from './campaign-access';
import { CampaignSummaryService } from './campaign-summary';
import { CampaignsController } from './campaigns.controller';
import { CampaignsService } from './campaigns.service';
import { CropUnitsService } from './crop-units.service';
import { CropsController } from './crops.controller';
import { DocumentsController } from './documents.controller';
import { DocumentsService } from './documents.service';
import { CampaignExportController } from './export/export.controller';
import { CampaignExportService } from './export/export.service';
import { NotebookCompletenessService } from './notebook-completeness';
import { NotebookController } from './notebook.controller';
import { NotebookCatalogService } from './notebook.service';

/**
 * Campañas y cuaderno de campo (BACKLOG.md #60, ADR-0012/0013/0014). Módulo
 * propio: reutiliza las parcelas (tablas y triggers de la migración 0008) sin
 * depender del módulo de satélite.
 */
@Module({
  controllers: [
    CampaignsController,
    ActivitiesController,
    CropsController,
    NotebookController,
    DocumentsController,
    CampaignExportController,
  ],
  providers: [
    PrismaService,
    AuditLogService,
    CampaignAccess,
    CampaignsService,
    CropUnitsService,
    ActivitiesService,
    CampaignSummaryService,
    NotebookCatalogService,
    NotebookCompletenessService,
    StorageService,
    DocumentsService,
    CampaignExportService,
  ],
  exports: [CampaignAccess, CampaignsService],
})
export class CampaignsModule {}
