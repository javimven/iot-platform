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
 *
 * `$executeRaw` (INSERT sin RETURNING), no `tx.auditLogEntry.create()` —
 * bug real encontrado en vivo (2026-07-30): `.create()` genera un
 * `INSERT ... RETURNING`, y Postgres exige que la fila devuelta también
 * pase la política RLS de `SELECT` (`USING`), no solo la de escritura
 * (`WITH CHECK`, migración 0004). Para una entrada de Admin de plataforma
 * cuya `action` no empieza por `platform.` (p. ej. `org_features.update`),
 * la política de lectura la oculta a propósito de un vistazo general a la
 * auditoría de otra organización — pero eso hacía fallar el propio INSERT
 * con "new row violates row-level security policy", porque Postgres no
 * podía satisfacer el `RETURNING` que Prisma pide siempre. Nadie usa el
 * valor de retorno de `record()` (ya era `Promise<void>`), así que evitar el
 * `RETURNING` no pierde nada y evita el conflicto por completo.
 */
@Injectable()
export class AuditLogService {
  async record(tx: Prisma.TransactionClient, entry: AuditEntryInput): Promise<void> {
    await tx.$executeRaw`
      INSERT INTO audit_log (organization_id, actor_user_id, action, target_type, target_id, metadata)
      VALUES (
        ${entry.organizationId ?? null}::uuid,
        ${entry.actorUserId ?? null}::uuid,
        ${entry.action},
        ${entry.targetType ?? null},
        ${entry.targetId ?? null},
        ${entry.metadata != null ? JSON.stringify(entry.metadata) : null}::jsonb
      )
    `;
  }
}
