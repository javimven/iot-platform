import { Controller, Get } from '@nestjs/common';
import { PlatformAuditService } from './platform-audit.service';
import { RequirePermission } from '../../../common/decorators/require-permission.decorator';

@Controller('platform/audit-log')
export class PlatformAuditController {
  constructor(private readonly audit: PlatformAuditService) {}

  @RequirePermission('platform.audit.read')
  @Get()
  list() {
    return this.audit.list();
  }
}
