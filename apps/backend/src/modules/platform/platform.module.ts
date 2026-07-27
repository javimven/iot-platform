import { Module } from '@nestjs/common';
import { PrismaService } from '../../common/prisma/prisma.service';
import { AuditLogService } from '../../common/audit/audit-log.service';
import { PasswordService } from '../../common/security/password.service';
import { MailerService } from '../../common/mailer/mailer.service';
import { PlatformOrganizationsController } from './organizations/platform-organizations.controller';
import { PlatformOrganizationsService } from './organizations/platform-organizations.service';
import { PlatformFeaturesController } from './organizations/platform-features.controller';
import { PlatformFeaturesService } from './organizations/platform-features.service';
import { PlatformAuditController } from './audit/platform-audit.controller';
import { PlatformAuditService } from './audit/platform-audit.service';

/**
 * Espacio de plataforma (API_DESIGN.md §2): sin organización activa, requiere
 * `isPlatformAdmin` (PermissionsGuard). Incluye la excepción de Directorio
 * IoT (ADR-0005, ver DirectoryModule — `PlatformGatewaysController` vive ahí,
 * representativo del resto de recursos).
 */
@Module({
  controllers: [
    PlatformOrganizationsController,
    PlatformFeaturesController,
    PlatformAuditController,
  ],
  providers: [
    PrismaService,
    AuditLogService,
    PasswordService,
    MailerService,
    PlatformOrganizationsService,
    PlatformFeaturesService,
    PlatformAuditService,
  ],
})
export class PlatformModule {}
