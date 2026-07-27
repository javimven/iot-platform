import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';

export interface AuditEntryInput {
  organizationId?: string;
  actorUserId?: string;
  action: string;
  targetType?: string;
  targetId?: string;
  metadata?: Record<string, unknown>;
}

/**
 * Escribe en `audit_log` (DATA_MODEL.md §6, PERMISSIONS.md §3). Siempre
 * dentro de la misma transacción que la acción que audita (recibe el `tx`
 * de `PrismaService.runInTenantContext` del propio llamador) — si la acción
 * falla y hace rollback, la entrada de auditoría no debe quedar huérfana.
 */
@Injectable()
export class AuditLogService {
  async record(tx: Prisma.TransactionClient, entry: AuditEntryInput): Promise<void> {
    await tx.auditLogEntry.create({
      data: {
        organizationId: entry.organizationId,
        actorUserId: entry.actorUserId,
        action: entry.action,
        targetType: entry.targetType,
        targetId: entry.targetId,
        metadata: entry.metadata as Prisma.InputJsonValue | undefined,
      },
    });
  }
}
