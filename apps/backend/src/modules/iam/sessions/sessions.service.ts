import { Injectable, UnauthorizedException } from '@nestjs/common';
import { PrismaService } from '../../../common/prisma/prisma.service';
import { AuditLogService } from '../../../common/audit/audit-log.service';
import {
  generateOpaqueSecret,
  hashOpaqueSecret,
  verifyOpaqueSecret,
} from '../../../common/security/opaque-secret.util';

export interface CreatedSession {
  sessionId: string;
  secret: string;
}

const REFRESH_TOKEN_TTL_DAYS = 30; // DEPLOYMENT.md §3 — valor por defecto, configurable en Etapa 13 avanzada

@Injectable()
export class SessionsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly auditLog: AuditLogService,
  ) {}

  /**
   * Crea una sesión para un usuario. `organizationId` es null hasta que se
   * complete la selección de organización (ARCHITECTURE.md §6) o para un
   * Admin de plataforma puro.
   */
  async create(params: {
    userId: string;
    organizationId?: string;
    userAgent?: string;
    ipAddress?: string;
  }): Promise<CreatedSession> {
    const secret = generateOpaqueSecret();
    const session = await this.prisma.runInTenantContext({ userId: params.userId }, (tx) =>
      tx.session.create({
        data: {
          userId: params.userId,
          organizationId: params.organizationId,
          refreshSecretHash: hashOpaqueSecret(secret),
          userAgent: params.userAgent,
          ipAddress: params.ipAddress,
          expiresAt: new Date(Date.now() + REFRESH_TOKEN_TTL_DAYS * 24 * 60 * 60 * 1000),
        },
      }),
    );
    return { sessionId: session.id, secret };
  }

  /**
   * Valida un refresh token y **rota** el secreto (refresh tokens rotativos,
   * fijado desde el inicio del proyecto). Búsqueda por `id` (PK), nunca por
   * hash del secreto — evita necesitar un índice sobre un hash y el riesgo de
   * timing de una búsqueda indexada por hash (DATA_MODEL.md §3).
   */
  async rotate(
    sessionId: string,
    candidateSecret: string,
  ): Promise<CreatedSession & { userId: string; organizationId: string | null }> {
    // Ni el contexto de organización ni el de usuario se conocen todavía en
    // este punto (se está reconstruyendo la identidad a partir del propio
    // token) — se usa la excepción estrecha `allowIdentityBootstrap`
    // (DATA_MODEL.md §7), no `isPlatformAdmin` (que está acotada al
    // Directorio IoT, ADR-0005, y no debe reutilizarse aquí). La seguridad
    // real de esta operación es poseer sessionId+secret, verificado justo
    // debajo — la política RLS solo permite la lectura puntual por PK.
    const session = await this.prisma.runInTenantContext({ allowIdentityBootstrap: true }, (tx) =>
      tx.session.findUnique({ where: { id: sessionId } }),
    );

    if (
      !session ||
      session.revokedAt ||
      session.expiresAt < new Date() ||
      !verifyOpaqueSecret(session.refreshSecretHash, candidateSecret)
    ) {
      throw new UnauthorizedException('Invalid or expired refresh token');
    }

    const newSecret = generateOpaqueSecret();
    await this.prisma.runInTenantContext({ userId: session.userId }, (tx) =>
      tx.session.update({
        where: { id: sessionId },
        data: { refreshSecretHash: hashOpaqueSecret(newSecret), lastUsedAt: new Date() },
      }),
    );

    return {
      sessionId: session.id,
      secret: newSecret,
      userId: session.userId,
      organizationId: session.organizationId,
    };
  }

  async revoke(sessionId: string, requestingUserId: string): Promise<void> {
    await this.prisma.runInTenantContext({ userId: requestingUserId }, async (tx) => {
      const session = await tx.session.findUnique({ where: { id: sessionId } });
      if (!session || session.userId !== requestingUserId) {
        return; // 204 idempotente — no se filtra si existía o pertenecía a otro (PERMISSIONS.md §9)
      }
      await tx.session.update({ where: { id: sessionId }, data: { revokedAt: new Date() } });
    });
  }

  /** Revoca todas las sesiones de un usuario — usado tras cambio de contraseña (SECURITY.md §3). */
  async revokeAllForUser(userId: string): Promise<void> {
    await this.prisma.runInTenantContext({ userId }, (tx) =>
      tx.session.updateMany({
        where: { userId, revokedAt: null },
        data: { revokedAt: new Date() },
      }),
    );
  }

  async listOwn(userId: string): Promise<
    Array<{
      id: string;
      userAgent: string | null;
      ipAddress: string | null;
      createdAt: Date;
      lastUsedAt: Date;
    }>
  > {
    return this.prisma.runInTenantContext({ userId }, (tx) =>
      tx.session.findMany({
        where: { userId, revokedAt: null },
        select: { id: true, userAgent: true, ipAddress: true, createdAt: true, lastUsedAt: true },
        orderBy: { lastUsedAt: 'desc' },
      }),
    );
  }

  /**
   * Sesiones de *otro* miembro de la misma organización (`sessions.read_others`,
   * `PERMISSIONS.md` §1, `BACKLOG.md` #14) — a diferencia de `listOwn`, el
   * contexto de tenant es el del Admin de organización que llama
   * (`organizationId`, no `userId` del objetivo), y el filtro por
   * `organizationId` en el `where` es explícito: sin él devolvería las
   * sesiones de cualquier miembro de la organización, no solo las del
   * miembro objetivo (RLS por sí sola no distingue entre miembros de la
   * misma organización, solo entre organizaciones — DATA_MODEL.md §7).
   */
  async listForUser(
    organizationId: string,
    targetUserId: string,
  ): Promise<
    Array<{
      id: string;
      userAgent: string | null;
      ipAddress: string | null;
      createdAt: Date;
      lastUsedAt: Date;
    }>
  > {
    return this.prisma.runInTenantContext({ organizationId }, (tx) =>
      tx.session.findMany({
        where: { userId: targetUserId, organizationId, revokedAt: null },
        select: { id: true, userAgent: true, ipAddress: true, createdAt: true, lastUsedAt: true },
        orderBy: { lastUsedAt: 'desc' },
      }),
    );
  }

  /** Revocar la sesión de otro miembro (`sessions.revoke_others`) — auditado, a diferencia de `revoke` (propia sesión). */
  async revokeForUser(
    organizationId: string,
    targetUserId: string,
    sessionId: string,
    actorUserId: string,
  ): Promise<void> {
    await this.prisma.runInTenantContext({ organizationId, userId: actorUserId }, async (tx) => {
      const session = await tx.session.findFirst({
        where: { id: sessionId, userId: targetUserId, organizationId },
      });
      if (!session) {
        return; // 204 idempotente — mismo criterio que `revoke` (PERMISSIONS.md §9/§13)
      }
      await tx.session.update({ where: { id: sessionId }, data: { revokedAt: new Date() } });
      await this.auditLog.record(tx, {
        organizationId,
        actorUserId,
        action: 'sessions.revoke_others',
        targetType: 'session',
        targetId: sessionId,
        metadata: { targetUserId },
      });
    });
  }
}
