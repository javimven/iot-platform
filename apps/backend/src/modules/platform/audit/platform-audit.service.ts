import { Injectable } from '@nestjs/common';
import { AuditLogEntry } from '@prisma/client';
import { PrismaService } from '../../../common/prisma/prisma.service';

/** `platform.audit.read` (PERMISSIONS.md §3): altas/bajas/suspensiones de organización. */
@Injectable()
export class PlatformAuditService {
  constructor(private readonly prisma: PrismaService) {}

  async list(): Promise<AuditLogEntry[]> {
    return this.prisma.runInTenantContext({ isPlatformAdmin: true }, (tx) =>
      tx.auditLogEntry.findMany({
        where: { action: { startsWith: 'platform.' } },
        orderBy: { createdAt: 'desc' },
        take: 200,
      }),
    );
  }
}
