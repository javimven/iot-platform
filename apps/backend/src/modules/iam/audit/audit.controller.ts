import { Controller, Get } from '@nestjs/common';
import { AuditService } from './audit.service';
import { CurrentUser } from '../../../common/decorators/current-user.decorator';
import { RequirePermission } from '../../../common/decorators/require-permission.decorator';
import { AccessTokenClaims } from '../../../common/guards/jwt-auth.guard';

@Controller('audit-log')
export class AuditController {
  constructor(private readonly audit: AuditService) {}

  // audit.read_full (Admin de organización) y audit.read_technical (Técnico)
  // comparten el mismo endpoint — el filtrado por rol vive en el servicio
  // (PERMISSIONS.md §4), el guard solo exige tener uno de los dos permisos.
  @RequirePermission('audit.read_technical')
  @Get()
  list(@CurrentUser() user: AccessTokenClaims) {
    return this.audit.listForOrganization(user);
  }
}
