import { Injectable } from '@nestjs/common';
import { AuditLogEntry } from '@prisma/client';
import { PrismaService } from '../../../common/prisma/prisma.service';
import { AccessTokenClaims } from '../../../common/guards/jwt-auth.guard';

/**
 * Auditoría de una organización (PERMISSIONS.md §3-4). Técnico ve solo la
 * parte "técnica" (Directorio IoT); Admin de organización ve todo
 * (`audit.read_full` ya incluye `audit.read_technical`, PERMISSIONS.md §4).
 */
const TECHNICAL_ACTION_PREFIXES = [
  'installations.',
  'zones.',
  'gateways.',
  'devices.',
  'sensors.',
  'channels.',
];

@Injectable()
export class AuditService {
  constructor(private readonly prisma: PrismaService) {}

  async listForOrganization(user: AccessTokenClaims): Promise<AuditLogEntry[]> {
    // El filtro por prefijo de acción va en el propio WHERE (no después, en
    // JS) para que el límite de 200 filas aplique sobre el resultado ya
    // filtrado — si no, un Técnico podría ver menos de 200 entradas
    // relevantes en una organización con mucha actividad no técnica.
    const actionFilter =
      user.roleCode === 'technician'
        ? { OR: TECHNICAL_ACTION_PREFIXES.map((prefix) => ({ action: { startsWith: prefix } })) }
        : {};

    return this.prisma.runInTenantContext(
      { userId: user.sub, organizationId: user.organizationId },
      (tx) =>
        tx.auditLogEntry.findMany({
          where: { organizationId: user.organizationId!, ...actionFilter },
          orderBy: { createdAt: 'desc' },
          take: 200,
        }),
    );
  }
}
