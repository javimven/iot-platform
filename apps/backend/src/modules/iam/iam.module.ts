import { Module } from '@nestjs/common';
import { AuthController } from './auth/auth.controller';
import { MeController } from './auth/me.controller';
import { AuthService } from './auth/auth.service';
import { UsersService } from './users/users.service';
import { MembersController } from './members/members.controller';
import { MembersService } from './members/members.service';
import { SessionsService } from './sessions/sessions.service';
import { OrganizationsController } from './organizations/organizations.controller';
import { OrganizationsService } from './organizations/organizations.service';
import { AuditController } from './audit/audit.controller';
import { AuditService } from './audit/audit.service';
import { PasswordService } from '../../common/security/password.service';
import { PrismaService } from '../../common/prisma/prisma.service';
import { AuditLogService } from '../../common/audit/audit-log.service';
import { MailerService } from '../../common/mailer/mailer.service';

/**
 * IAM (Usuarios, Organizaciones, Miembros, Roles, Sesiones, Auditoría de
 * organización — ARCHITECTURE.md §5). `JwtModule` no se registra aquí: se
 * registra una única vez, global, en el root module del proceso
 * (`api.module.ts`) — con `kid`/RS256 (SECURITY.md §8) — para que exista una
 * sola instancia de `JwtService` en toda la aplicación.
 */
@Module({
  controllers: [
    AuthController,
    MeController,
    MembersController,
    OrganizationsController,
    AuditController,
  ],
  providers: [
    PrismaService,
    AuthService,
    UsersService,
    MembersService,
    SessionsService,
    OrganizationsService,
    AuditService,
    AuditLogService,
    PasswordService,
    MailerService,
  ],
  exports: [UsersService, MembersService, SessionsService],
})
export class IamModule {}
